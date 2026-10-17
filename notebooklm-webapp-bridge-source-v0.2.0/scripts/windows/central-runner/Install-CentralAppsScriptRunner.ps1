param(
  [int]$IntervalMinutes = 5,
  [string]$TaskName = 'Central Apps Script Runner'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($IntervalMinutes -lt 5) { throw 'IntervalMinutes must be at least 5.' }

$releaseRef = 'central-runner-readonly-bootstrap-v7'
$expectedRunnerVersion = 'CENTRAL_APPS_SCRIPT_RUNNER_V2_READONLY_BOOTSTRAP_V7_20260831'
$installDir = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$runnerPath = Join-Path $installDir 'CentralAppsScriptRunner.ps1'
$wrapperPath = Join-Path $installDir 'CentralAppsScriptRunnerWrapper.ps1'
$statePath = Join-Path $installDir 'state.json'
$logPath = Join-Path $installDir 'install.log'
$runnerUrl = "https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$releaseRef/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/CentralAppsScriptRunnerV2.ps1"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) $Message"
}

try {
  $claspCmd = Get-Command clasp.cmd -ErrorAction SilentlyContinue
  if (!$claspCmd) { throw 'EXISTING_CLASP_CMD_REQUIRED_NO_INSTALL_STARTED' }

  & $claspCmd.Source show-authorized-user --json *> $null
  if ($LASTEXITCODE -ne 0) {
    & $claspCmd.Source show-authorized-user *> $null
    if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE_NO_LOGIN_STARTED' }
  }
  Write-InstallLog 'Existing clasp authorization verified through clasp.cmd.'

  Invoke-WebRequest -UseBasicParsing -Uri $runnerUrl -OutFile $runnerPath -TimeoutSec 30
  if (!(Test-Path $runnerPath) -or (Get-Item $runnerPath).Length -lt 2000) { throw 'RUNNER_DOWNLOAD_FAILED' }
  $tokens=$null; $parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) { throw 'RUNNER_PARSE_FAILED' }
  $runnerText = Get-Content -Raw -LiteralPath $runnerPath
  if ($runnerText -notmatch [regex]::Escape($expectedRunnerVersion)) { throw 'RUNNER_VERSION_MISMATCH' }
  if ($runnerText -notmatch "MUTATION_ACTION_DISABLED_IN_READONLY_BOOTSTRAP_RELEASE") { throw 'RUNNER_MUTATION_GATE_MISSING' }
  if ($runnerText -notmatch [regex]::Escape($releaseRef)) { throw 'RUNNER_RELEASE_REF_MISMATCH' }
  Write-InstallLog "Pinned read-only runner verified releaseRef=$releaseRef version=$expectedRunnerVersion."

  $wrapper = @'
& "$env:LOCALAPPDATA\CentralAppsScriptRunner\CentralAppsScriptRunner.ps1"
exit $LASTEXITCODE
'@
  Set-Content -LiteralPath $wrapperPath -Value $wrapper -Encoding UTF8

  $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ([string]::IsNullOrWhiteSpace($currentIdentity)) { throw 'WINDOWS_IDENTITY_NOT_RESOLVED' }

  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
  $start = (Get-Date).AddMinutes(1)
  $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
  $principal = New-ScheduledTaskPrincipal -UserId $currentIdentity -LogonType Interactive -RunLevel Limited
  $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
  Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
  Write-InstallLog "Scheduled task registered: $TaskName identity=$currentIdentity every $IntervalMinutes minutes."

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath
  $firstExit = $LASTEXITCODE
  Write-InstallLog "Initial runner exit=$firstExit"
  if ($firstExit -ne 0) { throw "INITIAL_RUN_FAILED:$firstExit" }
  if (!(Test-Path $statePath)) { throw 'RUNNER_STATE_NOT_CREATED' }

  $registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  Write-InstallLog "INSTALL_VERIFIED taskState=$($registered.State) runner=$expectedRunnerVersion releaseRef=$releaseRef"

  Write-Host 'CENTRAL_APPS_SCRIPT_RUNNER_INSTALLED'
  Write-Host "RUNNER_VERSION=$expectedRunnerVersion"
  Write-Host "RELEASE_REF=$releaseRef"
  Write-Host "TASK_NAME=$TaskName"
  Write-Host "INTERVAL_MINUTES=$IntervalMinutes"
  Write-Host "RUNNER_PATH=$runnerPath"
  Write-Host "WRAPPER_PATH=$wrapperPath"
  Write-Host "STATE_PATH=$statePath"
  exit 0
} catch {
  Write-InstallLog "INSTALL_FAILED $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
