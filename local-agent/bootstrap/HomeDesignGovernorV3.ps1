param(
  [switch]$Interactive
)

$ErrorActionPreference = 'SilentlyContinue'

$Base       = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Control    = Join-Path $Base 'Control'
$Logs       = Join-Path $Control 'Logs'
$Archive    = Join-Path $Control 'DesktopArchive'
$StateDir   = Join-Path $Control 'State'
$RuntimeDir = Join-Path $Base 'LocalAgent'

@($Control,$Logs,$Archive,$StateDir,$RuntimeDir) | ForEach-Object {
  New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Log = Join-Path $Logs ("GOVERNOR_" + $Stamp + ".log")
$LatestJson = Join-Path $StateDir 'LATEST_STATUS.json'
$LatestTxt  = Join-Path $StateDir 'LATEST_STATUS.txt'

function Log([string]$m) {
  $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m)
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
  if ($Interactive) { Write-Host $line }
}

function Read-JsonSafe([string]$path) {
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-ChromeInventory {
  $userData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  $out = @()
  if (-not (Test-Path -LiteralPath $userData)) { return @() }

  $profiles = Get-ChildItem -LiteralPath $userData -Directory | Where-Object {
    $_.Name -eq 'Default' -or $_.Name -like 'Profile *'
  }

  foreach ($profile in $profiles) {
    $pref = Read-JsonSafe (Join-Path $profile.FullName 'Preferences')
    $settings = $null
    if ($pref -and $pref.extensions -and $pref.extensions.settings) { $settings = $pref.extensions.settings }

    $root = Join-Path $profile.FullName 'Extensions'
    if (-not (Test-Path -LiteralPath $root)) { continue }

    foreach ($idDir in Get-ChildItem -LiteralPath $root -Directory) {
      $verDir = Get-ChildItem -LiteralPath $idDir.FullName -Directory | Sort-Object Name -Descending | Select-Object -First 1
      if (-not $verDir) { continue }

      $manifestPath = Join-Path $verDir.FullName 'manifest.json'
      $m = Read-JsonSafe $manifestPath
      if (-not $m) { continue }

      $name = [string]$m.name
      if ($name -like '__MSG_*__' -and $m.default_locale) {
        $key = $name.Trim('_')
        if ($key.StartsWith('MSG_')) { $key = $key.Substring(4) }
        $msgPath = Join-Path $verDir.FullName ("_locales\" + [string]$m.default_locale + "\messages.json")
        $msgs = Read-JsonSafe $msgPath
        if ($msgs -and ($msgs.PSObject.Properties.Name -contains $key)) {
          $name = [string]$msgs.$key.message
        }
      }

      $enabled = $null
      $state = $null
      if ($settings -and ($settings.PSObject.Properties.Name -contains $idDir.Name)) {
        $entry = $settings.($idDir.Name)
        if ($entry.PSObject.Properties.Name -contains 'state') {
          $state = $entry.state
          try { $enabled = ([int]$state -eq 1) } catch {}
        }
      }

      $out += [pscustomobject]@{
        profile=$profile.Name
        id=$idDir.Name
        name=$name
        version=[string]$m.version
        enabled=$enabled
        state=$state
        path=$verDir.FullName
      }
    }
  }
  return @($out | Sort-Object name,version,profile)
}

function Get-Runtime {
  $all = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'chrome|powershell|pwsh|node'
  } | Select-Object Name,ProcessId,ExecutablePath,CommandLine)

  $agent = @($all | Where-Object {
    $_.CommandLine -match 'HomeDesignLocalAgent|LocalAgent|CommandHost|ChromeGovernor|CentralAppsScriptRunner|notebooklm-webapp-bridge|HomeDesignAutoResume'
  })
  $dedicated = @($all | Where-Object {
    $_.Name -match '^chrome' -and $_.CommandLine -match 'remote-debugging-port|Chrome for Testing|HomeDesignAutomationV7|CentralAppsScriptRunner|user-data-dir'
  })

  [ordered]@{
    agent_running = ($agent.Count -gt 0)
    agent_processes = $agent
    dedicated_chrome_running = ($dedicated.Count -gt 0)
    dedicated_chrome_processes = $dedicated
  }
}

function Get-GovernorTaskState {
  try {
    $t = Get-ScheduledTask -TaskName 'HomeDesignAutomation-Governor' -ErrorAction Stop
    return [ordered]@{present=$true;state=[string]$t.State}
  } catch {
    return [ordered]@{present=$false;state='MISSING'}
  }
}

function Invoke-SafeRuntimeHeal {
  $resume = Join-Path $RuntimeDir 'HomeDesignAutoResume.ps1'
  $url = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/HomeDesignAutoResume.ps1'

  if (-not (Test-Path -LiteralPath $resume)) {
    try {
      $u = $url + '?hdcb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $resume -TimeoutSec 45
      Log "Downloaded current safe runtime resume script."
    } catch {
      Log ("Runtime resume download failed: " + $_.Exception.Message)
      return $false
    }
  }

  try {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $resume | Out-Null
    Log "Safe runtime self-heal invoked."
    return $true
  } catch {
    Log ("Runtime self-heal failed: " + $_.Exception.Message)
    return $false
  }
}

function Move-KnownDesktopArtifacts {
  $desktop = [Environment]::GetFolderPath('Desktop')
  if (-not (Test-Path -LiteralPath $desktop)) { return @() }

  $moved = @()
  $filePatterns = @(
    'CHROME_ALL_EXTENSIONS_*',
    'CHROME_FLOW_HEALTH_RESULT*',
    'RUN_AUDIT*.cmd',
    'RUN_CHROME_FLOW_CONNECT*.cmd',
    'FIND_AND_RUN_CHROME_FLOW_CONNECT*.cmd',
    'RESUME_LOCAL_AGENT*.cmd',
    'FINAL_RESUME_AGENT*.cmd',
    'RUN_VIDEO_RUNTIME_RECOVERY*.cmd',
    'VIDEO_RUNTIME_RECOVERY*_RESULT*'
  )

  foreach ($pat in $filePatterns) {
    foreach ($item in Get-ChildItem -LiteralPath $desktop -Filter $pat -Force -ErrorAction SilentlyContinue) {
      if ($item.PSIsContainer) { continue }
      $dest = Join-Path $Archive ($Stamp + '_' + $item.Name)
      try {
        Move-Item -LiteralPath $item.FullName -Destination $dest -Force
        $moved += $item.FullName
      } catch {}
    }
  }

  $folderPatterns = @(
    'HomeDesignChromeAudit*',
    'ChromeAudit*',
    'ChromeFlowHealth*',
    'LocalAgentRecovery*',
    'VideoRuntimeRecovery*'
  )
  foreach ($pat in $folderPatterns) {
    foreach ($item in Get-ChildItem -LiteralPath $desktop -Directory -Filter $pat -Force -ErrorAction SilentlyContinue) {
      $dest = Join-Path $Archive ($Stamp + '_' + $item.Name)
      try {
        Move-Item -LiteralPath $item.FullName -Destination $dest
        $moved += $item.FullName
      } catch {}
    }
  }
  return $moved
}

function Ensure-OneDesktopShortcut {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $link = Join-Path $desktop 'HomeDesign 자동화 상태.lnk'
  try {
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($link)
    $sc.TargetPath = 'notepad.exe'
    $sc.Arguments = '"' + $LatestTxt + '"'
    $sc.WorkingDirectory = $StateDir
    $sc.Description = 'HomeDesign automation latest status'
    $sc.Save()
  } catch {}
}

Log "===== HomeDesign Governor start ====="
$moved = @(Move-KnownDesktopArtifacts)
Log ("Desktop cleanup moved items: " + $moved.Count)

$extensionsBefore = @(Get-ChromeInventory)
$runtimeBefore = Get-Runtime
$task = Get-GovernorTaskState

$healed = $false
if (-not $runtimeBefore.agent_running -or -not $runtimeBefore.dedicated_chrome_running) {
  Log "Runtime incomplete; invoking safe self-heal."
  $healed = Invoke-SafeRuntimeHeal
  Start-Sleep -Seconds 6
}

$extensions = @(Get-ChromeInventory)
$runtime = Get-Runtime
$task = Get-GovernorTaskState

$known = [ordered]@{
  'NotebookLM WebApp Bridge' = @('NotebookLM WebApp Bridge','notebooklm')
  'Google AI Local Bridge' = @('Google AI Local Bridge','Google AI Local Bridge v1')
  'Flow Agent Bridge' = @('Flow Agent Bridge','Flow Bridge')
  'AI Studio Bridge' = @('AI Studio Bridge')
  'Front App Test Bridge' = @('Front App Test Bridge')
  'SketchUp Plan Template Bridge' = @('SketchUp Plan Template Bridge')
  'ChatGPT Image Auto' = @('ChatGPT Image Auto')
  'UniConverter' = @('UniConverter')
  'Save to Google Drive' = @('Save to Google Drive')
}

$checks = @()
foreach ($kv in $known.GetEnumerator()) {
  $matches = @($extensions | Where-Object {
    $n=[string]$_.name
    $hit=$false
    foreach($needle in $kv.Value){ if($n -like "*$needle*"){ $hit=$true; break } }
    $hit
  })

  if ($matches.Count -eq 0) {
    $s = if($kv.Key -eq 'Save to Google Drive'){'PASS_NOT_INSTALLED'}
         elseif($kv.Key -eq 'UniConverter'){'OPTIONAL_NOT_INSTALLED'}
         else{'LIVE_READBACK_REQUIRED'}
    $checks += [pscustomobject]@{name=$kv.Key;status=$s;version='';enabled=$null}
    continue
  }

  $best=$matches | Sort-Object version -Descending | Select-Object -First 1
  if($kv.Key -eq 'Save to Google Drive'){$s='APPROVAL_REQUIRED_REMOVE'}
  elseif($kv.Key -eq 'UniConverter'){$s='OPTIONAL_OR_REMOVE'}
  elseif($best.enabled -eq $false){$s='FAIL_DISABLED'}
  elseif($null -eq $best.enabled){$s='LIVE_READBACK_REQUIRED'}
  else{$s='PASS_INSTALLED_ENABLED'}
  $checks += [pscustomobject]@{name=$kv.Key;status=$s;version=$best.version;enabled=$best.enabled}
}

$runtimeChecks = @(
  [pscustomobject]@{name='Local Agent / Host';status=$(if($runtime.agent_running){'PASS_RUNNING'}else{'FAIL_NOT_RUNNING'})},
  [pscustomobject]@{name='Dedicated Chrome';status=$(if($runtime.dedicated_chrome_running){'PASS_RUNNING'}else{'FAIL_NOT_RUNNING'})},
  [pscustomobject]@{name='Governor Scheduled Task';status=$(if($task.present){'PASS_PRESENT'}else{'FAIL_MISSING'})}
)

$blocking = @($checks + $runtimeChecks | Where-Object { $_.status -match '^FAIL' })
$approval = @($checks | Where-Object { $_.status -match '^APPROVAL_REQUIRED' })
$live = @($checks + $runtimeChecks | Where-Object { $_.status -eq 'LIVE_READBACK_REQUIRED' })

$overall = if($blocking.Count -gt 0){'FAIL'}
           elseif($approval.Count -gt 0){'APPROVAL_REQUIRED'}
           elseif($live.Count -gt 0){'LIVE_READBACK_REQUIRED'}
           else{'PASS'}

$result = [ordered]@{
  overall=$overall
  generated_at=(Get-Date).ToString('o')
  auto_heal_invoked=$healed
  desktop_items_archived=$moved
  extensions=$checks
  runtime=$runtimeChecks
  blockers=$blocking
  approval_required=$approval
  live_readback_required=$live
  state_root=$StateDir
  archive_root=$Archive
  rule='safe auto-fix -> recheck -> record; destructive extension removal requires approval'
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LatestJson -Encoding UTF8

$lines=@()
$lines += "HomeDesign Automation Status"
$lines += "OVERALL: $overall"
$lines += "TIME: $($result.generated_at)"
$lines += "AUTO HEAL INVOKED: $healed"
$lines += "DESKTOP ITEMS ARCHIVED: $($moved.Count)"
$lines += ""
$lines += "[RUNTIME]"
foreach($x in $runtimeChecks){$lines += ("{0,-30} {1}" -f $x.name,$x.status)}
$lines += ""
$lines += "[CHROME EXTENSIONS]"
foreach($x in $checks){$lines += ("{0,-34} {1,-28} v={2}" -f $x.name,$x.status,$x.version)}
$lines += ""
$lines += "Detailed JSON: $LatestJson"
$lines += "Logs: $Logs"
$lines += "Desktop archive: $Archive"
$lines += ""
$lines += "Only destructive/high-risk changes wait for approval."
$lines | Set-Content -LiteralPath $LatestTxt -Encoding UTF8

Ensure-OneDesktopShortcut
Log ("OVERALL=" + $overall)
Log "===== HomeDesign Governor end ====="

if($Interactive){
  Write-Host ""
  Write-Host "============================================================"
  Write-Host ("OVERALL: " + $overall)
  Write-Host ("Latest status: " + $LatestTxt)
  Write-Host ("Central control: " + $Control)
  Write-Host "============================================================"
}

if($overall -eq 'PASS'){exit 0}
if($overall -eq 'LIVE_READBACK_REQUIRED'){exit 2}
if($overall -eq 'APPROVAL_REQUIRED'){exit 3}
exit 1
