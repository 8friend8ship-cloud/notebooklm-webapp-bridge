param(
  [int]$IntervalMinutes = 5,
  [string]$TaskName = 'Central Apps Script Runner'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($IntervalMinutes -lt 5) { throw 'IntervalMinutes must be at least 5.' }

$SourceCommit = 'd946c1f1861467cd8277b31823ebe60756074295'
$LogicalRelease = 'central-runner-readonly-bootstrap-v7'
$ExpectedRunnerVersion = 'CENTRAL_APPS_SCRIPT_RUNNER_V2_READONLY_BOOTSTRAP_V7_20260831'
$RepoRaw = "https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$SourceCommit/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner"
$ManifestUrl = "$RepoRaw/tasks.json"
$RunnerUrl = "$RepoRaw/CentralAppsScriptRunnerV2.ps1"
$InstallDir = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$RunnerPath = Join-Path $InstallDir 'CentralAppsScriptRunnerPinned.ps1'
$WrapperPath = Join-Path $InstallDir 'CentralAppsScriptRunnerPinnedWrapper.ps1'
$StatePath = Join-Path $InstallDir 'state.json'
$LogPath = Join-Path $InstallDir 'install-pinned.log'
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message"
}

try {
  $claspCmd = Get-Command clasp.cmd -ErrorAction SilentlyContinue
  if (!$claspCmd) { throw 'EXISTING_CLASP_CMD_REQUIRED_NO_INSTALL_STARTED' }
  & $claspCmd.Source show-authorized-user --json *> $null
  if ($LASTEXITCODE -ne 0) {
    & $claspCmd.Source show-authorized-user *> $null
    if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE_NO_LOGIN_STARTED' }
  }
  Write-InstallLog 'Existing clasp authorization verified. No login/OAuth started.'

  $manifest = Invoke-RestMethod -UseBasicParsing -Uri $ManifestUrl -TimeoutSec 30
  if ([string]$manifest.channel -ne 'CENTRAL_APPS_SCRIPT_RUNNER_V2') { throw 'MANIFEST_CHANNEL_MISMATCH' }
  if ([string]$manifest.mode -ne 'READ_ONLY_BOOTSTRAP') { throw 'MANIFEST_MODE_NOT_READ_ONLY' }
  if ([string]$manifest.releaseRef -ne $LogicalRelease) { throw 'MANIFEST_LOGICAL_RELEASE_MISMATCH' }
  $enabled = @($manifest.tasks | Where-Object { $_.enabled })
  if ($enabled.Count -ne 1) { throw 'MANIFEST_ENABLED_TASK_COUNT_NOT_ONE' }
  if ([string]$enabled[0].action -ne 'BOUND_APPS_SCRIPT_READONLY_RECOVERY') { throw 'MANIFEST_ENABLED_ACTION_NOT_READ_ONLY' }
  Write-InstallLog "Pinned manifest verified sourceCommit=$SourceCommit enabledTask=$($enabled[0].taskId)."

  Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $RunnerPath -TimeoutSec 30
  if (!(Test-Path $RunnerPath) -or (Get-Item $RunnerPath).Length -lt 2000) { throw 'RUNNER_DOWNLOAD_FAILED' }
  $runnerText = Get-Content -Raw -LiteralPath $RunnerPath
  if ($runnerText -notmatch [regex]::Escape($ExpectedRunnerVersion)) { throw 'RUNNER_VERSION_MISMATCH' }
  if ($runnerText -notmatch 'MUTATION_ACTION_DISABLED_IN_READONLY_BOOTSTRAP_RELEASE') { throw 'RUNNER_MUTATION_GATE_MISSING' }
  $runnerText = $runnerText -replace [regex]::Escape("'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/central-runner-readonly-bootstrap-v7/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/tasks.json'"), ("'" + $ManifestUrl + "'")
  $runnerText = $runnerText -replace [regex]::Escape('$AssetBase = "https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$ReleaseRef/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner"'), ('$AssetBase = "' + $RepoRaw + '"')
  Set-Content -LiteralPath $RunnerPath -Value $runnerText -Encoding UTF8
  $check = Get-Content -Raw -LiteralPath $RunnerPath
  if ($check -notmatch [regex]::Escape($SourceCommit)) { throw 'RUNNER_SOURCE_COMMIT_PIN_FAILED' }
  if ($check -match 'raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/\$ReleaseRef/') { throw 'RUNNER_MUTABLE_ASSET_ROUTE_REMAINS' }
  $tokens=$null; $parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) { throw 'PINNED_RUNNER_PARSE_FAILED' }
  Write-InstallLog "Runner pinned and parsed version=$ExpectedRunnerVersion sourceCommit=$SourceCommit."

  $wrapper = "& `"$RunnerPath`"`r`nexit `$LASTEXITCODE`r`n"
  Set-Content -LiteralPath $WrapperPath -Value $wrapper -Encoding UTF8
  $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ([string]::IsNullOrWhiteSpace($currentIdentity)) { throw 'WINDOWS_IDENTITY_NOT_RESOLVED' }
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperPath`""
  $start = (Get-Date).AddMinutes(1)
  $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
  $principal = New-ScheduledTaskPrincipal -UserId $currentIdentity -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -InputObject (New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal) -Force | Out-Null
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $WrapperPath
  $firstExit = $LASTEXITCODE
  Write-InstallLog "Initial pinned runner exit=$firstExit"
  if ($firstExit -ne 0) { throw "INITIAL_RUN_FAILED:$firstExit" }
  if (!(Test-Path $StatePath)) { throw 'RUNNER_STATE_NOT_CREATED' }
  $registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  Write-InstallLog "INSTALL_VERIFIED taskState=$($registered.State) sourceCommit=$SourceCommit"
  Write-Host 'CENTRAL_APPS_SCRIPT_RUNNER_PINNED_INSTALLED'
  Write-Host "SOURCE_COMMIT=$SourceCommit"
  Write-Host "RUNNER_VERSION=$ExpectedRunnerVersion"
  Write-Host "TASK_NAME=$TaskName"
  Write-Host "INTERVAL_MINUTES=$IntervalMinutes"
  exit 0
} catch {
  Write-InstallLog "INSTALL_FAILED $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
