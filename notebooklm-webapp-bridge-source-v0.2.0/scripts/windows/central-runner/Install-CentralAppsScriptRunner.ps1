param(
  [int]$IntervalMinutes = 5,
  [string]$TaskName = 'Central Apps Script Runner'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($IntervalMinutes -lt 5) { throw 'IntervalMinutes must be at least 5.' }

$installDir = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$runnerPath = Join-Path $installDir 'CentralAppsScriptRunner.ps1'
$logPath = Join-Path $installDir 'install.log'
$runnerUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/CentralAppsScriptRunner.ps1'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) $Message"
}

try {
  if (!(Get-Command clasp -ErrorAction SilentlyContinue)) {
    if (!(Get-Command npm -ErrorAction SilentlyContinue)) { throw 'CLASP_AND_NPM_NOT_FOUND' }
    Write-InstallLog 'clasp missing; installing current @google/clasp with npm.'
    & npm install --global '@google/clasp@latest'
    if ($LASTEXITCODE -ne 0 -or !(Get-Command clasp -ErrorAction SilentlyContinue)) { throw 'CLASP_INSTALL_FAILED' }
  }

  # Reuse only the authorization already verified on this Windows profile.
  & clasp show-authorized-user --json *> $null
  if ($LASTEXITCODE -ne 0) {
    & clasp show-authorized-user *> $null
    if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE_NO_LOGIN_STARTED' }
  }
  Write-InstallLog 'Existing clasp authorization verified.'

  Invoke-WebRequest -UseBasicParsing -Uri $runnerUrl -OutFile $runnerPath
  if (!(Test-Path $runnerPath) -or (Get-Item $runnerPath).Length -lt 1000) { throw 'RUNNER_DOWNLOAD_FAILED' }

  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runnerPath`""
  $start = (Get-Date).AddMinutes(1)
  $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
  $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
  Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
  Write-InstallLog "Scheduled task registered: $TaskName every $IntervalMinutes minutes."

  # Run once now; later runs are automatic.
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runnerPath
  $firstExit = $LASTEXITCODE
  Write-InstallLog "Initial runner exit=$firstExit"
  if ($firstExit -ne 0) { throw "INITIAL_RUN_FAILED:$firstExit" }

  $registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  Write-InstallLog "INSTALL_VERIFIED taskState=$($registered.State)"

  Write-Host 'CENTRAL_APPS_SCRIPT_RUNNER_INSTALLED'
  Write-Host "TASK_NAME=$TaskName"
  Write-Host "INTERVAL_MINUTES=$IntervalMinutes"
  Write-Host "RUNNER_PATH=$runnerPath"
  Write-Host "STATE_PATH=$(Join-Path $installDir 'state.json')"
  exit 0
} catch {
  Write-InstallLog "INSTALL_FAILED $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
