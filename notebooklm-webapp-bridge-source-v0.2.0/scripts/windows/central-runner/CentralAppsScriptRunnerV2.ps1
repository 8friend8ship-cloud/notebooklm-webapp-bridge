param(
  [string]$TaskManifestUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/tasks.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RunnerVersion = 'CENTRAL_APPS_SCRIPT_RUNNER_V2_X5_READONLY_20260831'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$StatePath = Join-Path $StateRoot 'state.json'
$LogPath = Join-Path $StateRoot 'runner.log'
$AssetBase = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-RunnerLog([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message"
}
function Load-State() {
  if (!(Test-Path $StatePath)) { return [ordered]@{ runnerVersion=$RunnerVersion; tasks=@{} } }
  try {
    $raw = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    $tasks = @{}
    if ($raw.tasks) { foreach ($p in $raw.tasks.PSObject.Properties) { $tasks[$p.Name] = $p.Value } }
    return [ordered]@{ runnerVersion=$RunnerVersion; tasks=$tasks }
  } catch {
    Write-RunnerLog "STATE_PARSE_FAILED $($_.Exception.Message)"
    return [ordered]@{ runnerVersion=$RunnerVersion; tasks=@{} }
  }
}
function Save-State($State) {
  [ordered]@{ runnerVersion=$RunnerVersion; updatedAt=(Get-Date).ToUniversalTime().ToString('o'); tasks=$State.tasks } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}
function Download-ActionScript([string]$Name) {
  $dest = Join-Path $StateRoot $Name
  Invoke-WebRequest -UseBasicParsing -Uri "$AssetBase/$Name" -OutFile $dest
  if (!(Test-Path $dest) -or (Get-Item $dest).Length -lt 500) { throw "ACTION_SCRIPT_DOWNLOAD_FAILED:$Name" }
  return $dest
}
function Invoke-AllowlistedTask($Task) {
  switch ([string]$Task.action) {
    'CONTENTOS_APPS_SCRIPT_SYNC' {
      $script = Download-ActionScript 'ContentOSAppsScriptSync.ps1'
      $json = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -TargetTitle ([string]$Task.targetTitle) -ExpectedDeploymentId ([string]$Task.expectedDeploymentId) 2>&1 | Out-String)
      if ($LASTEXITCODE -ne 0) { throw "CONTENTOS_SYNC_FAILED:$json" }
      try { return ($json | ConvertFrom-Json) } catch { return [ordered]@{ok=$true; action='CONTENTOS_APPS_SCRIPT_SYNC'; raw=$json.Trim()} }
    }
    'CHROME_FLOW_HEALTH' {
      $script = Download-ActionScript 'ChromeFlowHealth.ps1'
      $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script)
      if ($Task.appsScriptUrl) { $args += @('-AppsScriptUrl',[string]$Task.appsScriptUrl) }
      if ($Task.frontendUrl) { $args += @('-FrontendUrl',[string]$Task.frontendUrl) }
      $json = (& powershell.exe @args 2>&1 | Out-String)
      if ($LASTEXITCODE -ne 0) { throw "CHROME_FLOW_HEALTH_FAILED:$json" }
      try { return ($json | ConvertFrom-Json) } catch { return [ordered]@{ok=$true; action='CHROME_FLOW_HEALTH'; raw=$json.Trim()} }
    }
    'BOUND_APPS_SCRIPT_READONLY_RECOVERY' {
      $script = Download-ActionScript 'RecoverExistingBoundAppsScript.ps1'
      $json = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -TargetTitle ([string]$Task.targetTitle) `
        -ExpectedSpreadsheetId ([string]$Task.expectedSpreadsheetId) `
        -ExpectedDeploymentId ([string]$Task.expectedDeploymentId) 2>&1 | Out-String)
      if ($LASTEXITCODE -ne 0) { throw "BOUND_READONLY_RECOVERY_FAILED:$json" }
      try {
        $parsed = $json | ConvertFrom-Json
        if (-not $parsed.ok -or [string]$parsed.mode -ne 'READ_ONLY' -or $parsed.mutationPerformed -ne $false) { throw 'BOUND_READONLY_RECEIPT_CONTRACT_FAILED' }
        return $parsed
      } catch {
        throw "BOUND_READONLY_RECEIPT_PARSE_FAILED:$json"
      }
    }
    default { throw 'ACTION_NOT_WHITELISTED' }
  }
}

try {
  Write-RunnerLog "RUN_START version=$RunnerVersion"
  $manifest = Invoke-RestMethod -Uri $TaskManifestUrl -Method Get
  if ([string]$manifest.channel -notin @('CENTRAL_APPS_SCRIPT_RUNNER_V1','CENTRAL_APPS_SCRIPT_RUNNER_V2')) { throw 'TASK_CHANNEL_MISMATCH' }
  $state = Load-State
  $runHadFailure = $false
  foreach ($task in @($manifest.tasks)) {
    if (!$task.enabled) { continue }
    $taskId = [string]$task.taskId
    if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
    $existing = $state.tasks[$taskId]
    if ($existing -and [string]$existing.status -eq 'COMPLETED') { continue }
    $attempts = if ($existing -and $existing.attempts) { [int]$existing.attempts } else { 0 }
    $maxAttempts = if ($task.maxAttempts) { [int]$task.maxAttempts } else { 1 }
    if ($attempts -ge $maxAttempts) { continue }
    $attempts++
    $state.tasks[$taskId] = [ordered]@{status='RUNNING';attempts=$attempts;action=[string]$task.action;startedAt=(Get-Date).ToUniversalTime().ToString('o')}
    Save-State $state
    Write-RunnerLog "TASK_START id=$taskId action=$($task.action) attempt=$attempts"
    try {
      $result = Invoke-AllowlistedTask $task
      $state.tasks[$taskId] = [ordered]@{status='COMPLETED';attempts=$attempts;action=[string]$task.action;completedAt=(Get-Date).ToUniversalTime().ToString('o');result=$result}
      Save-State $state
      Write-RunnerLog "TASK_COMPLETED id=$taskId"
    } catch {
      $runHadFailure = $true
      $state.tasks[$taskId] = [ordered]@{status='FAILED';attempts=$attempts;action=[string]$task.action;failedAt=(Get-Date).ToUniversalTime().ToString('o');error=$_.Exception.Message}
      Save-State $state
      Write-RunnerLog "TASK_FAILED id=$taskId error=$($_.Exception.Message)"
    }
  }
  if ($runHadFailure) { Write-RunnerLog 'RUN_END_WITH_TASK_FAILURE'; exit 2 }
  Write-RunnerLog 'RUN_END_SUCCESS'
  exit 0
} catch {
  Write-RunnerLog "RUN_FATAL error=$($_.Exception.Message)"
  exit 1
}
