param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$AgentVersion = '1.0.0'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot = Join-Path $Base 'LocalAgent'
$ExtensionRoot = Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$UserData = Join-Path $Base 'ChromeUserData'
$CftRoot = Join-Path $Base 'ChromeForTesting'
$BackupRoot = Join-Path $AgentRoot 'Backups'
$LogRoot = Join-Path $AgentRoot 'Logs'
$StateFile = Join-Path $AgentRoot 'state.json'
$ReleaseUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'

New-Item -ItemType Directory -Force -Path $AgentRoot,$BackupRoot,$LogRoot | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogRoot ("agent_" + $Stamp + '.log')

function Log([string]$Message) {
  $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-State([hashtable]$Patch) {
  $state = @{}
  if (Test-Path -LiteralPath $StateFile) {
    try {
      $old = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($p in $old.PSObject.Properties) { $state[$p.Name] = $p.Value }
    } catch {}
  }
  foreach ($k in $Patch.Keys) { $state[$k] = $Patch[$k] }
  $state['agentVersion'] = $AgentVersion
  $state['updatedAt'] = (Get-Date).ToString('o')
  $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Find-CftChrome {
  if (-not (Test-Path -LiteralPath $CftRoot)) { return $null }
  return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
}

function DedicatedProcesses {
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine -like "*$UserData*" })
  } catch { return @() }
}

function Stop-DedicatedChrome {
  $procs = DedicatedProcesses
  foreach ($p in $procs) {
    try {
      $gp = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
      if ($gp -and $gp.MainWindowHandle -ne 0) { [void]$gp.CloseMainWindow() }
    } catch {}
  }
  Start-Sleep -Seconds 5
  foreach ($p in (DedicatedProcesses)) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 2
}

function Launch-DedicatedChrome([string]$FrontUrl) {
  $chrome = Find-CftChrome
  if (-not $chrome) { throw 'Chrome for Testing executable not found.' }
  if (-not (Test-Path -LiteralPath (Join-Path $ExtensionRoot 'manifest.json'))) { throw 'Extension manifest missing.' }

  $args = @(
    "--user-data-dir=$UserData",
    '--profile-directory=Default',
    "--load-extension=$ExtensionRoot",
    '--new-window',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-session-crashed-bubble',
    $FrontUrl
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $chrome.FullName
  $psi.WorkingDirectory = $chrome.Directory.FullName
  $psi.UseShellExecute = $false
  $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  [void][System.Diagnostics.Process]::Start($psi)
  Start-Sleep -Seconds 8
  if ((DedicatedProcesses).Count -le 0) { throw 'Dedicated Chrome did not remain running.' }
}

function Test-Health([string]$HealthUrl) {
  if (-not $HealthUrl) { return $true }
  try {
    $body = '{"action":"health"}'
    $r = Invoke-RestMethod -Uri $HealthUrl -Method Post -ContentType 'text/plain;charset=utf-8' -Body $body -TimeoutSec 30
    return [bool]$r.ok
  } catch {
    Log ("Health test failed: " + $_.Exception.Message)
    return $false
  }
}

function Test-InstalledFiles($Release) {
  foreach ($f in @($Release.files)) {
    $local = Join-Path $ExtensionRoot ([string]$f.path).Replace('/','\')
    if (-not (Test-Path -LiteralPath $local)) { return $false }
    if ((Sha256 $local) -ne ([string]$f.sha256).ToLowerInvariant()) { return $false }
  }
  return $true
}

function Download-Release($Release,[string]$Stage) {
  New-Item -ItemType Directory -Force -Path $Stage | Out-Null
  foreach ($f in @($Release.files)) {
    $rel = [string]$f.path
    if ($rel -match '\.\.' -or [IO.Path]::IsPathRooted($rel)) { throw "Unsafe release path: $rel" }
    $dest = Join-Path $Stage $rel.Replace('/','\')
    $parent = Split-Path $dest -Parent
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $baseUrl = ([string]$Release.baseUrl).TrimEnd('/')
    if (-not $baseUrl.StartsWith('https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/')) { throw 'Untrusted release baseUrl.' }
    $url = "$baseUrl/$rel"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 60
    $actual = Sha256 $dest
    $expected = ([string]$f.sha256).ToLowerInvariant()
    if ($actual -ne $expected) { throw "SHA256 mismatch: $rel" }
  }
}

function Backup-Extension([string]$BackupDir) {
  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  if (Test-Path -LiteralPath $ExtensionRoot) {
    Copy-Item -LiteralPath $ExtensionRoot -Destination (Join-Path $BackupDir 'extension') -Recurse -Force
  }
}

function Install-Stage([string]$Stage) {
  New-Item -ItemType Directory -Force -Path $ExtensionRoot | Out-Null
  Get-ChildItem -LiteralPath $ExtensionRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
  Copy-Item -Path (Join-Path $Stage '*') -Destination $ExtensionRoot -Recurse -Force
}

function Rollback([string]$BackupDir,[string]$FrontUrl) {
  $saved = Join-Path $BackupDir 'extension'
  if (-not (Test-Path -LiteralPath $saved)) { throw 'Rollback backup missing.' }
  Stop-DedicatedChrome
  New-Item -ItemType Directory -Force -Path $ExtensionRoot | Out-Null
  Get-ChildItem -LiteralPath $ExtensionRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
  Copy-Item -Path (Join-Path $saved '*') -Destination $ExtensionRoot -Recurse -Force
  Launch-DedicatedChrome $FrontUrl
}

function Cleanup-Backups {
  $dirs = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
  foreach ($d in ($dirs | Select-Object -Skip 5)) {
    try { Remove-Item -LiteralPath $d.FullName -Recurse -Force } catch {}
  }
}

try {
  Log '=== HomeDesign Local Agent cycle START ==='
  Write-State @{ status='CHECKING'; lastError='' }

  $release = Invoke-RestMethod -Uri $ReleaseUrl -Method Get -TimeoutSec 30
  if (-not $release.enabled) {
    Log 'Stable release disabled; no action.'
    Write-State @{ status='RELEASE_DISABLED' }
    exit 0
  }
  if ([string]$release.channel -ne 'stable') { throw 'Unexpected release channel.' }
  if ($release.requiresUserApproval) {
    Log 'Release requires user approval; skipped.'
    Write-State @{ status='NEEDS_USER_APPROVAL'; candidateVersion=[string]$release.version }
    exit 0
  }

  $installedVersion = '0.0.0'
  $manifestPath = Join-Path $ExtensionRoot 'manifest.json'
  if (Test-Path -LiteralPath $manifestPath) {
    try { $installedVersion = [string](Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch {}
  }

  $filesHealthy = Test-InstalledFiles $release
  $needsUpdate = ([version]$installedVersion -lt [version][string]$release.version) -or (-not $filesHealthy)
  Log "Installed=$installedVersion Candidate=$($release.version) FilesHealthy=$filesHealthy NeedsUpdate=$needsUpdate"

  if (-not $needsUpdate) {
    if ((DedicatedProcesses).Count -le 0) {
      Launch-DedicatedChrome ([string]$release.frontUrl)
      Log 'Dedicated Chrome was down and has been restarted.'
    }
    Write-State @{ status='HEALTHY'; installedVersion=$installedVersion; candidateVersion=[string]$release.version; lastSuccessAt=(Get-Date).ToString('o') }
    Log 'No update required.'
    exit 0
  }

  $cycle = Get-Date -Format 'yyyyMMdd_HHmmss'
  $stage = Join-Path $AgentRoot ("Stage\" + $cycle)
  $backup = Join-Path $BackupRoot $cycle

  Download-Release $release $stage
  Log 'Release downloaded and SHA256 verified.'
  Backup-Extension $backup
  Log "Backup created: $backup"

  Stop-DedicatedChrome
  Install-Stage $stage
  Log 'New extension files installed.'

  $newManifest = Get-Content -LiteralPath (Join-Path $ExtensionRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string]$newManifest.version -ne [string]$release.version) { throw 'Installed manifest version mismatch.' }
  if (-not (Test-InstalledFiles $release)) { throw 'Installed file hash verification failed.' }

  Launch-DedicatedChrome ([string]$release.frontUrl)
  if (-not (Test-Health ([string]$release.healthUrl))) { throw 'Apps Script health failed after update.' }

  Write-State @{
    status='UPDATED_HEALTH_PASS'
    installedVersion=[string]$release.version
    candidateVersion=[string]$release.version
    backup=$backup
    lastSuccessAt=(Get-Date).ToString('o')
    awaitingE2E=$true
  }
  Log "Update SUCCESS to $($release.version). Awaiting central E2E evidence."
  Cleanup-Backups

} catch {
  $message = $_.Exception.Message
  Log ("ERROR: " + $message)
  Write-State @{ status='UPDATE_FAILED'; lastError=$message }

  try {
    if ($backup -and (Test-Path -LiteralPath (Join-Path $backup 'extension'))) {
      $front = if ($release -and $release.frontUrl) { [string]$release.frontUrl } else { 'https://notebooklm-webapp-bridge.vercel.app' }
      Rollback $backup $front
      Log 'Automatic rollback SUCCESS.'
      Write-State @{ status='ROLLED_BACK'; lastError=$message; rollbackAt=(Get-Date).ToString('o') }
    }
  } catch {
    Log ("ROLLBACK ERROR: " + $_.Exception.Message)
    Write-State @{ status='ROLLBACK_FAILED'; lastError=($message + ' | rollback: ' + $_.Exception.Message) }
  }
  exit 1
} finally {
  Log '=== HomeDesign Local Agent cycle END ==='
}
