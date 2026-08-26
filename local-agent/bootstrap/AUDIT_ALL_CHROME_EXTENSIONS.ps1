$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$now = Get-Date
$desktop = [Environment]::GetFolderPath('Desktop')
$outJson = Join-Path $desktop 'CHROME_ALL_EXTENSIONS_AUDIT.json'
$outTxt  = Join-Path $desktop 'CHROME_ALL_EXTENSIONS_AUDIT.txt'

function Get-VersionFromManifest([string]$manifestPath) {
  try {
    $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    return [string]$m.version
  } catch { return $null }
}

function Get-ChromeProfiles {
  $root = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if (!(Test-Path $root)) { return @() }
  $profiles = @()
  Get-ChildItem -LiteralPath $root -Directory | Where-Object {
    $_.Name -eq 'Default' -or $_.Name -like 'Profile *'
  } | ForEach-Object {
    $profiles += [pscustomobject]@{ Name=$_.Name; Path=$_.FullName }
  }
  return $profiles
}

function Get-InstalledExtensions {
  $items = @()
  foreach ($p in (Get-ChromeProfiles)) {
    $extRoot = Join-Path $p.Path 'Extensions'
    if (!(Test-Path $extRoot)) { continue }
    foreach ($idDir in (Get-ChildItem -LiteralPath $extRoot -Directory)) {
      $versions = Get-ChildItem -LiteralPath $idDir.FullName -Directory | Sort-Object Name -Descending
      $latest = $versions | Select-Object -First 1
      if (!$latest) { continue }
      $manifest = Join-Path $latest.FullName 'manifest.json'
      $name = $idDir.Name
      $version = Get-VersionFromManifest $manifest
      try {
        $m = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if ($m.name -and $m.name -notmatch '^__MSG_') { $name = [string]$m.name }
      } catch {}
      $items += [pscustomobject]@{
        profile=$p.Name; extensionId=$idDir.Name; name=$name; version=$version;
        manifest=$manifest; exists=(Test-Path $manifest)
      }
    }
  }
  return $items
}

function Get-ProcessesSafe {
  $names = @('chrome','node','powershell','pwsh')
  $rows = @()
  foreach ($n in $names) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
      $rows += [pscustomobject]@{name=$_.ProcessName; id=$_.Id; startTime=($_.StartTime.ToString('o'))}
    }
  }
  return $rows
}

function Get-ScheduledRecoveryTasks {
  $rows = @()
  try {
    Get-ScheduledTask | Where-Object {
      $_.TaskName -match 'HomeDesign|Chrome|Agent|Bridge|Resume|Governor'
    } | ForEach-Object {
      $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath
      $rows += [pscustomobject]@{
        taskName=$_.TaskName; taskPath=$_.TaskPath; state=[string]$_.State;
        lastRunTime=if($info.LastRunTime){$info.LastRunTime.ToString('o')}else{$null};
        lastTaskResult=$info.LastTaskResult; nextRunTime=if($info.NextRunTime){$info.NextRunTime.ToString('o')}else{$null}
      }
    }
  } catch {}
  return $rows
}

$extensions = @(Get-InstalledExtensions)
$processes = @(Get-ProcessesSafe)
$tasks = @(Get-ScheduledRecoveryTasks)

$localRoots = @(
  (Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'),
  (Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner')
)
$files = @()
foreach ($r in $localRoots) {
  if (Test-Path $r) {
    Get-ChildItem -LiteralPath $r -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match 'Agent|Host|Bridge|Governor|health|result|state|version' } |
      Select-Object -First 200 | ForEach-Object {
        $files += [pscustomobject]@{path=$_.FullName; modified=$_.LastWriteTime.ToString('o'); size=$_.Length}
      }
  }
}

$known = [ordered]@{
  notebookLMBridge = @($extensions | Where-Object { $_.name -match 'NotebookLM' -or $_.manifest -match 'notebooklm' })
  googleAILocalBridge = @($extensions | Where-Object { $_.name -match 'Google AI Local Bridge' })
  flowAgentBridge = @($extensions | Where-Object { $_.name -match 'Flow.*Bridge' })
  aiStudioBridge = @($extensions | Where-Object { $_.name -match 'AI Studio.*Bridge' })
  frontAppTestBridge = @($extensions | Where-Object { $_.name -match 'Front App Test Bridge' })
  sketchUpBridge = @($extensions | Where-Object { $_.name -match 'SketchUp Plan Template Bridge' })
  chatGPTImageAuto = @($extensions | Where-Object { $_.name -match 'ChatGPT Image Auto' })
  uniConverter = @($extensions | Where-Object { $_.name -match 'UniConverter' })
  saveToGoogleDrive = @($extensions | Where-Object { $_.name -match 'Save to Google Drive' })
}

$result = [ordered]@{
  generatedAt=$now.ToString('o')
  computerName=$env:COMPUTERNAME
  userName=$env:USERNAME
  completionRule='Install/enabled is not complete. Require Queue->browser action->real result->persistence->ACK->central readback->sleep/logon reconnect.'
  installedExtensionCount=$extensions.Count
  extensions=$extensions
  knownExtensions=$known
  processes=$processes
  scheduledRecoveryTasks=$tasks
  runtimeEvidenceFiles=$files
  gates=[ordered]@{
    liveReadbackRequired=$true
    notebookLME2ERequired=$true
    googleAILocalBridgeRetestRequired=$true
    flowRealGenerationRequired=$true
    sketchUpOneCaseRequired=$true
    chatGPTImageQueueAdapterRequired=$true
    sleepWakeRetestRequired=$true
    logonRetestRequired=$true
  }
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outJson -Encoding UTF8

$lines = @()
$lines += 'HomeDesign Chrome Extension Audit'
$lines += ('Generated: ' + $now.ToString('yyyy-MM-dd HH:mm:ss'))
$lines += ('Installed extension records: ' + $extensions.Count)
$lines += ('Recovery scheduled tasks: ' + $tasks.Count)
$lines += ''
$lines += 'Known extension matches:'
foreach($k in $known.Keys){ $lines += ('- ' + $k + ': ' + @($known[$k]).Count) }
$lines += ''
$lines += 'Evidence JSON: ' + $outJson
$lines += 'IMPORTANT: This inventory does not by itself mark E2E COMPLETE.'
$lines | Set-Content -LiteralPath $outTxt -Encoding UTF8

Write-Host '============================================================'
Write-Host 'CHROME ALL EXTENSIONS AUDIT: COMPLETE'
Write-Host ('JSON: ' + $outJson)
Write-Host ('TEXT: ' + $outTxt)
Write-Host 'No extension was removed or changed.'
Write-Host '============================================================'
exit 0
