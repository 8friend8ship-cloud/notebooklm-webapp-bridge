param()

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$AgentVersion = '1.1.46'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root = Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$QueueGovernor = Join-Path $Root 'Sync-NotebookLMQueueIntegrityAppsScriptV2-1.1.45.ps1'
$QueueMarker = Join-Path $Root 'queue-integrity-sync-v2-1.1.45-dispatch.json'
$QueueUrl = 'https://raw.githubusercontent.com/' + $Repo + '/main/local-agent/governor/Sync-NotebookLMQueueIntegrityAppsScriptV2.ps1'
$QueueSha = '9a06c6ef475a6427a04258c1ff84ebdc2ce498a3'

$PersonaGovernor = Join-Path $Root 'Bind-FrontPersonaOrchestrationAppsScriptV1-1.1.46.ps1'
$PersonaMarker = Join-Path $Root 'persona-bind-v1-1.1.46-dispatch.json'
$PersonaUrl = 'https://raw.githubusercontent.com/' + $Repo + '/main/local-agent/governor/Bind-FrontPersonaOrchestrationAppsScriptV1.ps1'
$PersonaSha = '186e987af8cb61e7a11242a6a2c69251ec0e1c73'
$PersonaSourceCommit = '0ad86472116e73728d99c0c49d940e0a884d4739'
$PersonaDeploymentId = 'AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$State = Join-Path $Root 'state.json'

function Get-GitBlob([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
  $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header, 0, $all, 0, $header.Length)
  [Buffer]::BlockCopy($bytes, 0, $all, $header.Length, $bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create()
  try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') }
  finally { $sha.Dispose() }
}

function Fetch-Pinned([string]$Url, [string]$Destination, [string]$ExpectedSha) {
  $temp = $Destination + '.download'
  Invoke-WebRequest -UseBasicParsing -Uri ($Url + '?cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $temp -TimeoutSec 20
  $actual = (Get-GitBlob $temp).ToLowerInvariant()
  if ($actual -ne $ExpectedSha) {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    throw ('SHA_MISMATCH:' + $actual + ':' + $ExpectedSha)
  }
  Move-Item -LiteralPath $temp -Destination $Destination -Force
  return $actual
}

function Find-CentralRoot {
  $name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    if (-not $drive.Root) { continue }
    foreach ($candidate in @(
      (Join-Path $drive.Root $name),
      (Join-Path $drive.Root ($myDriveKo + '\' + $name)),
      (Join-Path $drive.Root ('My Drive\' + $name)),
      (Join-Path $drive.Root ('Google Drive\' + $name))
    )) {
      if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
  }
  return ''
}

function Save-Json([string]$Path, $Object) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Object | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
  try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Test-MarkerAlive([string]$MarkerPath) {
  $marker = Read-Json $MarkerPath
  if (-not $marker -or -not $marker.pid) { return $false }
  try { return [bool](Get-Process -Id ([int]$marker.pid) -ErrorAction SilentlyContinue) } catch { return $false }
}

function Start-Governor([string]$ScriptPath, [string]$MarkerPath, [string]$ExpectedResult, [string]$ActionName, [string]$SourceSha) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'powershell.exe'
  $psi.UseShellExecute = $true
  $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
  $process = [Diagnostics.Process]::Start($psi)
  $pidValue = [int]$process.Id
  Save-Json $MarkerPath ([ordered]@{
    version = $AgentVersion
    pid = $pidValue
    action = $ActionName
    sourceSha = $SourceSha
    startedAt = (Get-Date).ToString('o')
    expectedResult = $ExpectedResult
    retryPolicy = 'NO_BLIND_RETRY'
    newProjectCreated = $false
    oauthChanged = $false
    scopeChanged = $false
  })
  return $pidValue
}

$central = Find-CentralRoot
$queueResultPath = ''
$personaResultPath = ''
if ($central) {
  $queueResultPath = Join-Path $central 'Runtime_Readback\AppsScript_QueueIntegrity\NOTEBOOKLM_QUEUE_INTEGRITY_SYNC.json'
  $personaResultPath = Join-Path $central 'Runtime_Readback\AppsScript_Persona\WEBAPP_TEMPLATE_05_PERSONA_BIND_V1.json'
}

$queueExisting = Read-Json $queueResultPath
$personaExisting = Read-Json $personaResultPath
$queueFetchSha = ''
$personaFetchSha = ''
$queueDispatch = ''
$personaDispatch = ''
$queuePid = $null
$personaPid = $null
$errors = @()

try { $queueFetchSha = Fetch-Pinned $QueueUrl $QueueGovernor $QueueSha }
catch { $errors += ('QUEUE_FETCH:' + $_.Exception.Message); $queueDispatch = 'QUEUE_FETCH_FAILED' }
try { $personaFetchSha = Fetch-Pinned $PersonaUrl $PersonaGovernor $PersonaSha }
catch { $errors += ('PERSONA_FETCH:' + $_.Exception.Message); $personaDispatch = 'PERSONA_FETCH_FAILED' }

if (-not $queueDispatch) {
  if ($queueExisting -and $queueExisting.ok -and [string]$queueExisting.status -eq 'PUSH_PULL_READBACK_PASS' -and [string]$queueExisting.version -eq '0.2.10-queue-lock') {
    $queueDispatch = 'LIVE_QUEUE_LOCK_PASS'
  } elseif (Test-MarkerAlive $QueueMarker) {
    $queueDispatch = 'SYNC_V2_ALREADY_RUNNING'
  } elseif (Test-Path -LiteralPath $QueueMarker) {
    $queueDispatch = 'SYNC_V2_MARKER_NO_RESULT_HOLD'
  } elseif ($queueExisting -and -not $queueExisting.ok) {
    $queueDispatch = 'QUEUE_PREVIOUS_FAILURE_HOLD'
  } else {
    try {
      $queuePid = Start-Governor $QueueGovernor $QueueMarker $queueResultPath 'QUEUE_INTEGRITY_SYNC_V2' $QueueSha
      $queueDispatch = 'SYNC_V2_DISPATCHED_BACKGROUND'
    } catch {
      $errors += ('QUEUE_DISPATCH:' + $_.Exception.Message)
      $queueDispatch = 'SYNC_V2_DISPATCH_FAILED'
    }
  }
}

if (-not $personaDispatch) {
  $personaPass = [bool](
    $personaExisting -and
    $personaExisting.ok -and
    [string]$personaExisting.status -eq 'PUSH_PULL_READBACK_X2_PASS' -and
    [string]$personaExisting.sourceCommit -eq $PersonaSourceCommit -and
    [string]$personaExisting.deploymentId -eq $PersonaDeploymentId
  )
  if ($personaPass) {
    $personaDispatch = 'LIVE_PERSONA_BIND_X2_PASS'
  } elseif (Test-MarkerAlive $PersonaMarker) {
    $personaDispatch = 'PERSONA_BIND_ALREADY_RUNNING'
  } elseif (Test-Path -LiteralPath $PersonaMarker) {
    $personaDispatch = 'PERSONA_BIND_MARKER_NO_RESULT_HOLD'
  } elseif ($personaExisting -and -not $personaExisting.ok -and [string]$personaExisting.sourceCommit -eq $PersonaSourceCommit) {
    $personaDispatch = 'PERSONA_PREVIOUS_FAILURE_HOLD'
  } else {
    try {
      $personaPid = Start-Governor $PersonaGovernor $PersonaMarker $personaResultPath 'PERSONA_APPS_SCRIPT_BIND_V1' $PersonaSha
      $personaDispatch = 'PERSONA_BIND_DISPATCHED_BACKGROUND'
    } catch {
      $errors += ('PERSONA_DISPATCH:' + $_.Exception.Message)
      $personaDispatch = 'PERSONA_BIND_DISPATCH_FAILED'
    }
  }
}

$queueOk = [bool]($queueFetchSha -eq $QueueSha -and $queueDispatch -in @('LIVE_QUEUE_LOCK_PASS', 'SYNC_V2_ALREADY_RUNNING', 'SYNC_V2_DISPATCHED_BACKGROUND'))
$personaOk = [bool]($personaFetchSha -eq $PersonaSha -and $personaDispatch -in @('LIVE_PERSONA_BIND_X2_PASS', 'PERSONA_BIND_ALREADY_RUNNING', 'PERSONA_BIND_DISPATCHED_BACKGROUND'))
$ok = [bool]($queueOk -and $personaOk)
$allLive = [bool]($queueDispatch -eq 'LIVE_QUEUE_LOCK_PASS' -and $personaDispatch -eq 'LIVE_PERSONA_BIND_X2_PASS')
$status = if ($allLive) { 'SELF_HEAL_PASS' } elseif ($ok) { 'PERSONA_BIND_RUNTIME_PENDING' } else { 'PERSONA_BIND_HOLD' }

$receipt = [ordered]@{
  ok = $ok
  action = 'AGENT_1.1.46_QUEUE_INTEGRITY_PLUS_PERSONA_BIND'
  agentVersion = $AgentVersion
  queueGovernorSha = $queueFetchSha
  personaGovernorSha = $personaFetchSha
  queueDispatchState = $queueDispatch
  personaDispatchState = $personaDispatch
  queuePid = $queuePid
  personaPid = $personaPid
  queueResultPath = $queueResultPath
  personaResultPath = $personaResultPath
  queueExistingResult = $queueExisting
  personaExistingResult = $personaExisting
  newProjectCreated = $false
  oauthChanged = $false
  scopeChanged = $false
  newDeployment = $false
  newTrigger = $false
  paidGeminiApiCalled = $false
  generateClicked = $false
  creditSpend = $false
  normalChromeRestarted = $false
  retryPolicy = 'NO_BLIND_RETRY'
  errors = $errors
  status = $status
  at = (Get-Date).ToString('o')
}

if ($central) { Save-Json (Join-Path $central 'Runtime_Readback\AGENT_1.1.46_QUEUE_INTEGRITY_PLUS_PERSONA_BIND.json') $receipt }
try {
  $stateObject = Read-Json $State
  if (-not $stateObject) { $stateObject = [pscustomobject]@{} }
  $stateObject | Add-Member agentVersion $AgentVersion -Force
  $stateObject | Add-Member agentMode 'QUEUE_INTEGRITY_PLUS_PERSONA_BIND_1.1.46' -Force
  $stateObject | Add-Member ok $ok -Force
  $stateObject | Add-Member status $status -Force
  $stateObject | Add-Member updatedAt ((Get-Date).ToString('o')) -Force
  Save-Json $State $stateObject
} catch {}

$receipt | ConvertTo-Json -Depth 50 -Compress
if ($ok) { exit 0 } else { exit 2 }
