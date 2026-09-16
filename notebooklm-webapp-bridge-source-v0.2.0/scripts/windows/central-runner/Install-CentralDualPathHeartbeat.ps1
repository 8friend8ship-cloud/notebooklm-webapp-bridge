param(
  [int]$IntervalMinutes = 5,
  [string]$TaskName = 'Central Dual Path Heartbeat Runner'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($IntervalMinutes -lt 5) { throw 'IntervalMinutes must be at least 5.' }

$SourceCommit = '25209e5b9775900ec7a92f9a8787b400c4f35080'
$RunnerVersion = 'CENTRAL_DUAL_PATH_HEARTBEAT_V1_20260916'
$Raw = "https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$SourceCommit/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/CentralDualPathHeartbeatRunner.ps1"
$InstallDir = Join-Path $env:LOCALAPPDATA 'CentralDualPathHeartbeat'
$RunnerPath = Join-Path $InstallDir 'CentralDualPathHeartbeatRunner.ps1'
$WrapperPath = Join-Path $InstallDir 'CentralDualPathHeartbeatRunnerWrapper.ps1'
$InstallLog = Join-Path $InstallDir 'install.log'
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $InstallLog -Value "$(Get-Date -Format o) $Message"
}

try {
  Invoke-WebRequest -UseBasicParsing -Uri $Raw -OutFile $RunnerPath -TimeoutSec 30
  if (!(Test-Path $RunnerPath) -or (Get-Item $RunnerPath).Length -lt 1500) { throw 'HEARTBEAT_RUNNER_DOWNLOAD_FAILED' }
  $text = Get-Content -Raw -LiteralPath $RunnerPath
  if ($text -notmatch [regex]::Escape($RunnerVersion)) { throw 'HEARTBEAT_RUNNER_VERSION_MISMATCH' }
  if ($text -notmatch 'remoteDcRequired = \$false') { throw 'REMOTE_DC_INDEPENDENCE_GATE_MISSING' }
  if ($text -notmatch 'claspRequired = \$false') { throw 'CLASP_INDEPENDENCE_GATE_MISSING' }
  if ($text -notmatch "mutationPerformed = \$false") { throw 'READ_ONLY_GATE_MISSING' }
  $tokens=$null; $parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) { throw 'HEARTBEAT_RUNNER_PARSE_FAILED' }
  Write-InstallLog "Pinned heartbeat runner verified sourceCommit=$SourceCommit version=$RunnerVersion"

  $wrapper = "& `"$RunnerPath`"`r`nexit `$LASTEXITCODE`r`n"
  Set-Content -LiteralPath $WrapperPath -Value $wrapper -Encoding UTF8
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ([string]::IsNullOrWhiteSpace($identity)) { throw 'WINDOWS_IDENTITY_NOT_RESOLVED' }
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperPath`""
  $start = (Get-Date).AddMinutes(1)
  $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
  $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -InputObject (New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal) -Force | Out-Null

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $WrapperPath
  $exit = $LASTEXITCODE
  Write-InstallLog "Initial heartbeat exit=$exit"
  if ($exit -ne 0) { throw "INITIAL_HEARTBEAT_FAILED:$exit" }
  $registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  Write-InstallLog "INSTALL_VERIFIED taskState=$($registered.State) sourceCommit=$SourceCommit"
  Write-Host 'CENTRAL_DUAL_PATH_HEARTBEAT_INSTALLED'
  Write-Host "SOURCE_COMMIT=$SourceCommit"
  Write-Host "TASK_NAME=$TaskName"
  Write-Host "INTERVAL_MINUTES=$IntervalMinutes"
  exit 0
} catch {
  Write-InstallLog "INSTALL_FAILED $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
