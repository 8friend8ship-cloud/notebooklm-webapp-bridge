param([switch]$Loop)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Version = 'CHROME_EXTENSION_GOVERNOR_V1_20260824'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot = Join-Path $Base 'ChromeGovernor'
$LogRoot = Join-Path $GovRoot 'Logs'
$ReportPath = Join-Path $GovRoot 'state.json'
$InventoryPath = Join-Path $GovRoot 'inventory.json'
$DesktopReport = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CHROME_EXTENSION_GOVERNOR_RESULT.json'
$PolicyUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$NotebookReleaseUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
$AgentRoot = Join-Path $Base 'LocalAgent'
$AgentStatePath = Join-Path $AgentRoot 'state.json'
$AgentBootstrap = Join-Path $AgentRoot 'AgentBootstrap.ps1'
$DedicatedUserData = Join-Path $Base 'ChromeUserData'
$DedicatedExtensionRoot = Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'

New-Item -ItemType Directory -Force -Path $GovRoot,$LogRoot | Out-Null

function Log([string]$Message) {
  $log = Join-Path $LogRoot ('governor_' + (Get-Date -Format 'yyyyMMdd') + '.log')
  Add-Content -LiteralPath $log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8
}

function Read-Json([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) { return $null }
  try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { return $null }
}

function Get-Manifest([string]$Path) {
  return Read-Json (Join-Path $Path 'manifest.json')
}

function Add-InventoryRow([ref]$Rows,[string]$Profile,[string]$Id,[string]$Path,[bool]$Unpacked,[string]$Source) {
  $m = Get-Manifest $Path
  if (!$m) { return }
  $name = [string]$m.name
  $version = [string]$m.version
  $fileErrors = @()
  if ($m.background -and $m.background.service_worker) {
    $p = Join-Path $Path ([string]$m.background.service_worker)
    if (!(Test-Path -LiteralPath $p)) { $fileErrors += ('missing service_worker: ' + [string]$m.background.service_worker) }
  }
  foreach ($cs in @($m.content_scripts)) {
    foreach ($js in @($cs.js)) {
      $p = Join-Path $Path ([string]$js)
      if (!(Test-Path -LiteralPath $p)) { $fileErrors += ('missing content_script: ' + [string]$js) }
    }
  }
  $Rows.Value += [pscustomobject]@{
    profile=$Profile; id=$Id; name=$name; version=$version; path=$Path; unpacked=$Unpacked;
    source=$Source; manifestVersion=[string]$m.manifest_version; fileIntegrityOk=($fileErrors.Count -eq 0);
    fileErrors=$fileErrors
  }
}

function Scan-Profile([string]$ProfileName,[string]$ProfilePath) {
  $rows = @()
  if (!(Test-Path -LiteralPath $ProfilePath)) { return @() }
  $seen = @{}
  $extRoot = Join-Path $ProfilePath 'Extensions'
  if (Test-Path -LiteralPath $extRoot) {
    foreach ($idDir in @(Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue)) {
      $verDir = Get-ChildItem -LiteralPath $idDir.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
      if (!$verDir) { continue }
      Add-InventoryRow ([ref]$rows) $ProfileName $idDir.Name $verDir.FullName $false 'PROFILE_EXTENSIONS_DIR'
      $seen[$idDir.Name] = $true
    }
  }

  foreach ($prefName in @('Preferences','Secure Preferences')) {
    $prefPath = Join-Path $ProfilePath $prefName
    if (!(Test-Path -LiteralPath $prefPath)) { continue }
    try {
      $pref = Get-Content -LiteralPath $prefPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $settings = $pref.extensions.settings
      if (!$settings) { continue }
      foreach ($prop in $settings.PSObject.Properties) {
        if ($seen[$prop.Name]) { continue }
        $s = $prop.Value
        if (!$s.path) { continue }
        $p = [string]$s.path
        if (!(Test-Path -LiteralPath (Join-Path $p 'manifest.json'))) { continue }
        Add-InventoryRow ([ref]$rows) $ProfileName $prop.Name $p $true $prefName
        $seen[$prop.Name] = $true
      }
    } catch { Log "profile parse failed: $ProfileName / $prefName / $($_.Exception.Message)" }
  }
  return $rows
}

function Get-AllInventory {
  $rows = @()
  $normalRoot = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if (Test-Path -LiteralPath $normalRoot) {
    foreach ($d in @(Get-ChildItem -LiteralPath $normalRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
      $rows += @(Scan-Profile ('NORMAL_CHROME/' + $d.Name) $d.FullName)
    }
  }
  $dedicatedDefault = Join-Path $DedicatedUserData 'Default'
  $rows += @(Scan-Profile 'HOMEDESIGN_CFT/Default' $dedicatedDefault)

  if (Test-Path -LiteralPath (Join-Path $DedicatedExtensionRoot 'manifest.json')) {
    $already = @($rows | Where-Object { $_.path -eq $DedicatedExtensionRoot })
    if ($already.Count -eq 0) {
      Add-InventoryRow ([ref]$rows) 'HOMEDESIGN_CFT/LoadedExtension' 'RESOLVE_FROM_PROFILE' $DedicatedExtensionRoot $true 'LOCAL_AGENT_EXTENSION_ROOT'
    }
  }
  return $rows
}

function Ensure-NotebookLocalAgent {
  $state = Read-Json $AgentStatePath
  $release = $null
  try { $release = Invoke-RestMethod -Uri $NotebookReleaseUrl -Method Get -TimeoutSec 20 } catch {}
  $target = if ($release) { [string]$release.version } else { '' }
  $installed = if ($state) { [string]$state.installedVersion } else { '' }
  $bootstrapRunning = $false
  try {
    $bootstrapRunning = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*LocalAgent*AgentBootstrap.ps1*'
    }).Count -gt 0
  } catch {}

  if (!$bootstrapRunning -and (Test-Path -LiteralPath $AgentBootstrap)) {
    try {
      Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$AgentBootstrap`"",'-Loop') -WindowStyle Hidden | Out-Null
      $bootstrapRunning = $true
      Log 'NotebookLM Local Agent bootstrap loop restarted.'
    } catch { Log ('NotebookLM Local Agent restart failed: ' + $_.Exception.Message) }
  }

  return [ordered]@{
    state=$state; targetVersion=$target; installedVersion=$installed; bootstrapRunning=$bootstrapRunning;
    versionReady=([string]::IsNullOrWhiteSpace($target) -eq $false -and $installed -eq $target)
  }
}

function Classify($Inventory,$Policy) {
  $out = @()
  $managed = @($Policy.managedExtensions)
  $securityHold = @($Policy.securityHoldNames)
  $observeOnly = @($Policy.observeOnlyNames)

  foreach ($i in $Inventory) {
    $rule = $managed | Where-Object { [string]$_.name -eq [string]$i.name } | Select-Object -First 1
    $classification = 'UNREGISTERED_OBSERVE_ONLY'
    $mode = [string]$Policy.rules.unregisteredMode
    $expected = ''
    $action = 'OBSERVE_ONLY'

    if ($rule) {
      $classification = 'CENTRAL_MANAGED'
      $mode = [string]$rule.mode
      $expected = [string]$rule.canonicalVersion
      if (!$i.fileIntegrityOk) { $action = 'REPAIR_FILES_REQUIRED' }
      elseif ($expected -and [string]$i.version -ne $expected) { $action = 'VERSION_DIFF_HOLD_OR_CANONICAL_UPDATE' }
      else { $action = 'CHECK_OK' }
      if ($mode -eq 'LOCAL_AGENT_STABLE') { $action = 'OWNED_BY_LOCAL_AGENT' }
    } elseif ($securityHold -contains [string]$i.name) {
      $classification = 'SECURITY_HOLD'
      $mode = 'HOLD_NO_DELETE'
      $action = 'USER_REVIEW_REQUIRED_NO_AUTO_DELETE'
    } elseif ($observeOnly -contains [string]$i.name) {
      $classification = 'THIRD_PARTY_OBSERVE_ONLY'
      $mode = 'OBSERVE_ONLY'
      $action = 'NO_AUTO_CHANGE'
    } elseif ($i.unpacked) {
      $classification = 'UNPACKED_UNREGISTERED_HOLD'
      $mode = 'HOLD_NO_DELETE'
      $action = 'REGISTER_SOURCE_BEFORE_UPDATE'
    }

    $out += [pscustomobject]@{
      profile=$i.profile; id=$i.id; name=$i.name; installedVersion=$i.version; expectedVersion=$expected;
      classification=$classification; mode=$mode; action=$action; fileIntegrityOk=$i.fileIntegrityOk;
      path=$i.path; unpacked=$i.unpacked; source=$i.source; fileErrors=$i.fileErrors
    }
  }
  return $out
}

function Run-Cycle {
  Log "=== Governor cycle START $Version ==="
  $policy = $null
  try { $policy = Invoke-RestMethod -Uri $PolicyUrl -Method Get -TimeoutSec 20 }
  catch {
    Log ('Policy fetch failed: ' + $_.Exception.Message)
    $policy = [pscustomobject]@{ pollSeconds=900; rules=[pscustomobject]@{unregisteredMode='OBSERVE_ONLY'}; managedExtensions=@(); securityHoldNames=@(); observeOnlyNames=@() }
  }

  $notebook = Ensure-NotebookLocalAgent
  $inventory = @(Get-AllInventory)
  $classified = @(Classify $inventory $policy)
  $duplicates = @()
  foreach ($g in @($classified | Group-Object name)) {
    if ($g.Count -gt 1 -and $g.Name) {
      $duplicates += [pscustomobject]@{name=$g.Name;count=$g.Count;items=@($g.Group | Select-Object profile,id,installedVersion,path)}
    }
  }

  $managedProblems = @($classified | Where-Object {
    $_.classification -eq 'CENTRAL_MANAGED' -and $_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT')
  })
  $securityProblems = @($classified | Where-Object { $_.classification -eq 'SECURITY_HOLD' })
  $unregisteredUnpacked = @($classified | Where-Object { $_.classification -eq 'UNPACKED_UNREGISTERED_HOLD' })

  $report = [ordered]@{
    ok=($managedProblems.Count -eq 0 -and $securityProblems.Count -eq 0)
    version=$Version
    generatedAt=(Get-Date).ToUniversalTime().ToString('o')
    policyUpdatedAt=[string]$policy.updatedAt
    notebookLocalAgent=$notebook
    summary=[ordered]@{
      total=$classified.Count
      centralManaged=@($classified | Where-Object {$_.classification -eq 'CENTRAL_MANAGED'}).Count
      thirdPartyObserve=@($classified | Where-Object {$_.classification -eq 'THIRD_PARTY_OBSERVE_ONLY'}).Count
      securityHold=$securityProblems.Count
      unpackedUnregistered=$unregisteredUnpacked.Count
      duplicates=$duplicates.Count
      managedProblems=$managedProblems.Count
    }
    extensions=$classified
    duplicates=$duplicates
    policy=[ordered]@{
      noDelete=$true; noCredentialRead=$true; noNewOAuth=$true; noNormalChromeRestart=$true;
      safeAutomaticScope='inventory;file-integrity;version-diff;Local-Agent stable restart only'
    }
  }

  $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
  $inventory | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $InventoryPath -Encoding UTF8
  try { Copy-Item -LiteralPath $ReportPath -Destination $DesktopReport -Force } catch {}
  Log "cycle result total=$($classified.Count) managedProblems=$($managedProblems.Count) securityHold=$($securityProblems.Count) duplicates=$($duplicates.Count)"
  Log '=== Governor cycle END ==='
  return [pscustomobject]@{report=$report;pollSeconds=[Math]::Max(300,[int]$policy.pollSeconds)}
}

$mutex = New-Object System.Threading.Mutex($false,'HomeDesignChromeExtensionGovernorV1')
if (-not $mutex.WaitOne(0,$false)) { exit 0 }
try {
  do {
    $cycle = Run-Cycle
    if ($Loop) { Start-Sleep -Seconds $cycle.pollSeconds }
  } while ($Loop)
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
}
