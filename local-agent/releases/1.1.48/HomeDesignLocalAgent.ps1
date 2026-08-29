param()

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$AgentVersion = '1.1.48'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root = Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$LegacyAgent = Join-Path $Root 'HomeDesignLocalAgent-1.1.46.ps1'
$LegacyAgentUrl = 'https://raw.githubusercontent.com/' + $Repo + '/main/local-agent/releases/1.1.46/HomeDesignLocalAgent.ps1'
$LegacyAgentSha = 'b72e57af70f77578fddb3de49f6581a37e2de792'
$PowerHelper = Join-Path $Root 'Setup-PowerContinuity.ps1'
$PowerHelperUrl = 'https://raw.githubusercontent.com/' + $Repo + '/main/local-agent/capture/Setup-PowerContinuity.ps1'
$PowerHelperSha = 'b98ed149d91cdec4ff75ccf4b03aa7b9e09f241f'
$QueueMarker = Join-Path $Root 'queue-integrity-sync-v2-1.1.45-dispatch.json'
$PersonaMarker = Join-Path $Root 'persona-bind-v1-1.1.46-dispatch.json'
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
  Invoke-WebRequest -UseBasicParsing -Uri ($Url + '?cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $temp -TimeoutSec 30
  $actual = (Get-GitBlob $temp).ToLowerInvariant()
  if ($actual -ne $ExpectedSha.ToLowerInvariant()) {
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
  if (-not $Path) { return }
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Object | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Recover-AbandonedMarkerOnce([string]$MarkerPath, [string]$ResultPath, [string]$ExpectedSourceSha, [string]$TicketName) {
  if (-not (Test-Path -LiteralPath $MarkerPath)) { return $false }
  if ($ResultPath -and (Test-Path -LiteralPath $ResultPath)) { return $false }
  if (Test-MarkerAlive $MarkerPath) { return $false }
  $marker = Read-Json $MarkerPath
  if (-not $marker) { return $false }
  if ([string]$marker.sourceSha -ne $ExpectedSourceSha) { return $false }
  $ticket = Join-Path $Root $TicketName
  if (Test-Path -LiteralPath $ticket) { return $false }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $stale = $MarkerPath + '.stale.' + $stamp
  Move-Item -LiteralPath $MarkerPath -Destination $stale -Force
  Save-Json $ticket ([ordered]@{ok=$true;action='ABANDONED_DISPATCH_MARKER_RECOVERY_ONCE';sourceSha=$ExpectedSourceSha;staleMarker=$stale;at=(Get-Date).ToString('o')})
  return $true
}

function Invoke-PowerShellCaptured([string]$Path, [string[]]$ScriptArgs) {
  $allArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Path) + @($ScriptArgs)
  $output = & powershell.exe @allArgs 2>&1 | Out-String
  return [ordered]@{exitCode=$LASTEXITCODE;stdout=$output.Trim();args=@($ScriptArgs)}
}

function Parse-LastJson([string]$Text) {
  $parsed = $null
  foreach ($line in @($Text -split "`r?`n")) {
    if (-not $line -or -not $line.Trim()) { continue }
    try {
      $candidate = $line.Trim() | ConvertFrom-Json
      if ($candidate -and $null -ne $candidate.ok) { $parsed = $candidate }
    } catch {}
  }
  return $parsed
}

function Test-PowerDesired($Status) {
  if (-not $Status -or -not [bool]$Status.ok) { return $false }
  $s = $Status.state
  if (-not $s -or -not [bool]$s.ok) { return $false }
  if (-not $Status.watchdog -or -not [bool]$Status.watchdog.exists) { return $false }
  if (-not $Status.night -or -not [bool]$Status.night.exists) { return $false }
  return [bool](
    [string]$s.nightStart -eq '02:00' -and
    [string]$s.nightEnd -eq '05:00' -and
    [int]$s.idleDisplayMinutes -eq 30 -and
    [string]$s.acAutomaticSleep -eq 'DISABLED' -and
    [string]$s.acAutomaticHibernate -eq 'DISABLED' -and
    [string]$s.acUsbSelectiveSuspend -eq 'DISABLED' -and
    [string]$s.keyboardFreezeGuard -eq 'NO_AC_SLEEP_RESUME_PLUS_USB_SELECTIVE_SUSPEND_DISABLED'
  )
}

$central = Find-CentralRoot
$queueResultPath = ''
$personaResultPath = ''
$runtimeRoot = ''
if ($central) {
  $runtimeRoot = Join-Path $central 'Runtime_Readback'
  $queueResultPath = Join-Path $runtimeRoot 'AppsScript_QueueIntegrity\NOTEBOOKLM_QUEUE_INTEGRITY_SYNC.json'
  $personaResultPath = Join-Path $runtimeRoot 'AppsScript_Persona\WEBAPP_TEMPLATE_05_PERSONA_BIND_V1.json'
}

$errors = @()
$legacyFetchSha = ''
$powerFetchSha = ''
$legacyRun = $null
$legacyParsed = $null
$queueMarkerRecovered = $false
$personaMarkerRecovered = $false
$powerInstalledThisCycle = $false
$powerStatusBefore = $null
$powerInstallResult = $null
$powerStatusAfter = $null

try {
  $legacyFetchSha = Fetch-Pinned $LegacyAgentUrl $LegacyAgent $LegacyAgentSha
  $queueMarkerRecovered = Recover-AbandonedMarkerOnce $QueueMarker $queueResultPath '9a06c6ef475a6427a04258c1ff84ebdc2ce498a3' 'queue-integrity-sync-v2-1.1.45-marker-recovery.once.json'
  $personaMarkerRecovered = Recover-AbandonedMarkerOnce $PersonaMarker $personaResultPath '186e987af8cb61e7a11242a6a2c69251ec0e1c73' 'persona-bind-v1-1.1.46-marker-recovery.once.json'
  $legacyRun = Invoke-PowerShellCaptured $LegacyAgent @()
  $legacyParsed = Parse-LastJson ([string]$legacyRun.stdout)
} catch {
  $errors += ('LEGACY_AGENT:' + $_.Exception.Message)
}

try {
  $powerFetchSha = Fetch-Pinned $PowerHelperUrl $PowerHelper $PowerHelperSha
  $statusRun = Invoke-PowerShellCaptured $PowerHelper @('-StatusOnly')
  $powerStatusBefore = Parse-LastJson ([string]$statusRun.stdout)
  if (-not (Test-PowerDesired $powerStatusBefore)) {
    $powerInstalledThisCycle = $true
    $installRun = Invoke-PowerShellCaptured $PowerHelper @('-Install','-NightStart','02:00','-NightEnd','05:00','-IdleDisplayMinutes','30')
    $powerInstallResult = Parse-LastJson ([string]$installRun.stdout)
    if ([int]$installRun.exitCode -ne 0 -or -not $powerInstallResult -or -not [bool]$powerInstallResult.ok) {
      throw ('POWER_INSTALL_FAILED:' + [string]$installRun.exitCode + ':' + [string]$installRun.stdout)
    }
  }
  $statusAfterRun = Invoke-PowerShellCaptured $PowerHelper @('-StatusOnly')
  $powerStatusAfter = Parse-LastJson ([string]$statusAfterRun.stdout)
  if (-not (Test-PowerDesired $powerStatusAfter)) {
    throw ('POWER_READBACK_MISMATCH:' + [string]$statusAfterRun.stdout)
  }
} catch {
  $errors += ('POWER_CONTINUITY:' + $_.Exception.Message)
}

$powerOk = [bool]($powerFetchSha -eq $PowerHelperSha -and (Test-PowerDesired $powerStatusAfter))
$legacyOk = [bool]($legacyFetchSha -eq $LegacyAgentSha -and $legacyRun -and [int]$legacyRun.exitCode -eq 0 -and $legacyParsed -and [bool]$legacyParsed.ok)
$status = if ($powerOk -and $legacyOk) {
  'POWER_CONTINUITY_AND_LEGACY_GOVERNORS_PASS'
} elseif ($powerOk) {
  'POWER_CONTINUITY_PASS_LEGACY_GOVERNOR_HOLD'
} else {
  'POWER_CONTINUITY_FAILED'
}

$receipt = [ordered]@{
  ok = $powerOk
  governanceOk = $legacyOk
  action = 'AGENT_1.1.48_POWER_CONTINUITY_SELF_HEAL'
  agentVersion = $AgentVersion
  status = $status
  legacyAgentVersion = '1.1.46'
  legacyAgentSha = $legacyFetchSha
  legacyExitCode = if ($legacyRun) { $legacyRun.exitCode } else { $null }
  legacyResult = $legacyParsed
  queueMarkerRecoveredOnce = $queueMarkerRecovered
  personaMarkerRecoveredOnce = $personaMarkerRecovered
  powerHelperSha = $powerFetchSha
  powerInstalledThisCycle = $powerInstalledThisCycle
  powerStatusBefore = $powerStatusBefore
  powerInstallResult = $powerInstallResult
  powerContinuity = $powerStatusAfter
  requiredPolicy = [ordered]@{
    idleDisplayMinutes = 30
    nightStart = '02:00'
    nightEnd = '05:00'
    acAutomaticSleep = 'DISABLED'
    acAutomaticHibernate = 'DISABLED'
    acUsbSelectiveSuspend = 'DISABLED'
    keyboardFreezeGuard = 'NO_AC_SLEEP_RESUME_PLUS_USB_SELECTIVE_SUSPEND_DISABLED'
    batterySleepAndUsbPolicyOverride = $false
  }
  newProjectCreated = $false
  oauthChanged = $false
  scopeChanged = $false
  newDeployment = $false
  newTrigger = $false
  paidGeminiApiCalled = $false
  generateClicked = $false
  creditSpend = $false
  normalChromeRestarted = $false
  errors = $errors
  at = (Get-Date).ToString('o')
}

if ($runtimeRoot) {
  Save-Json (Join-Path $runtimeRoot 'AGENT_1.1.48_POWER_CONTINUITY_SELF_HEAL.json') $receipt
  Save-Json (Join-Path $runtimeRoot 'POWER_CONTINUITY_RUNTIME_READBACK.json') $receipt
}
try {
  $stateObject = Read-Json $State
  if (-not $stateObject) { $stateObject = [pscustomobject]@{} }
  $stateObject | Add-Member agentVersion $AgentVersion -Force
  $stateObject | Add-Member agentMode 'POWER_CONTINUITY_SELF_HEAL_1.1.48' -Force
  $stateObject | Add-Member ok $powerOk -Force
  $stateObject | Add-Member governanceOk $legacyOk -Force
  $stateObject | Add-Member status $status -Force
  $stateObject | Add-Member powerContinuityOk $powerOk -Force
  $stateObject | Add-Member updatedAt ((Get-Date).ToString('o')) -Force
  Save-Json $State $stateObject
} catch {}

$receipt | ConvertTo-Json -Depth 60 -Compress
if ($powerOk) { exit 0 } else { exit 2 }
