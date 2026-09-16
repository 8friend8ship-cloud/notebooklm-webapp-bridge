param(
  [int]$IntervalMinutes = 5,
  [string]$TaskName = 'Central Dual Path Heartbeat Runner V2'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($IntervalMinutes -lt 5) { throw 'IntervalMinutes must be at least 5.' }

$SourceCommit = 'cca2e103dc6864c385c33a18a71f0a7c6b8f875a'
$RunnerVersion = 'CENTRAL_DUAL_PATH_HEARTBEAT_V2_20260916'
$Raw = "https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$SourceCommit/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/CentralDualPathHeartbeatRunnerV2.ps1"
$InstallDir = Join-Path $env:LOCALAPPDATA 'CentralDualPathHeartbeat'
$RunnerPath = Join-Path $InstallDir 'CentralDualPathHeartbeatRunnerV2.ps1'
$WrapperPath = Join-Path $InstallDir 'CentralDualPathHeartbeatRunnerV2Wrapper.ps1'
$StatePath = Join-Path $InstallDir 'state-v2.json'
$InstallLog = Join-Path $InstallDir 'install-v2.log'
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $InstallLog -Value "$(Get-Date -Format o) $Message"
}

try {
  Invoke-WebRequest -UseBasicParsing -Uri $Raw -OutFile $RunnerPath -TimeoutSec 30
  if (!(Test-Path $RunnerPath) -or (Get-Item $RunnerPath).Length -lt 1800) { throw 'HEARTBEAT_V2_RUNNER_DOWNLOAD_FAILED' }
  $text = Get-Content -Raw -LiteralPath $RunnerPath
  if (-not $text.Contains($RunnerVersion)) { throw 'HEARTBEAT_V2_RUNNER_VERSION_MISMATCH' }
  if (-not $text.Contains('remoteDcRequired = $false')) { throw 'REMOTE_DC_INDEPENDENCE_GATE_MISSING' }
  if (-not $text.Contains('claspRequired = $false')) { throw 'CLASP_INDEPENDENCE_GATE_MISSING' }
  if (-not $text.Contains('oauthRequired = $false')) { throw 'OAUTH_INDEPENDENCE_GATE_MISSING' }
  if (-not $text.Contains('paidServiceRequired = $false')) { throw 'PAID_SERVICE_INDEPENDENCE_GATE_MISSING' }
  if (-not $text.Contains('targetMutationPerformed = $false')) { throw 'READ_ONLY_GATE_MISSING' }
  if (-not $text.Contains('runCount = $runCount')) { throw 'RUNCOUNT_GATE_MISSING' }

  $tokens=$null; $parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) { throw 'HEARTBEAT_V2_RUNNER_PARSE_FAILED' }
  Write-InstallLog "Pinned heartbeat V2 verified sourceCommit=$SourceCommit version=$RunnerVersion"

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
  Write-InstallLog "Initial heartbeat V2 exit=$exit"
  if ($exit -ne 0) { throw "INITIAL_HEARTBEAT_V2_FAILED:$exit" }
  if (!(Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw 'STATE_V2_NOT_CREATED' }
  $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
  if (-not $state.ok -or [int]$state.runCount -lt 1 -or -not $state.runtimeReadbackFound) { throw 'STATE_V2_READBACK_GATE_FAILED' }

  $registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  Write-InstallLog "INSTALL_V2_VERIFIED taskState=$($registered.State) runCount=$($state.runCount) sourceCommit=$SourceCommit"
  Write-Host 'CENTRAL_DUAL_PATH_HEARTBEAT_V2_INSTALLED'
  Write-Host "SOURCE_COMMIT=$SourceCommit"
  Write-Host "TASK_NAME=$TaskName"
  Write-Host "INTERVAL_MINUTES=$IntervalMinutes"
  Write-Host "RUN_COUNT=$($state.runCount)"
  exit 0
} catch {
  Write-InstallLog "INSTALL_V2_FAILED $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
