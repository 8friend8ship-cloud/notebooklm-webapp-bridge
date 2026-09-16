param(
  [string]$ReceiptName = 'CENTRAL_DUAL_PATH_HEARTBEAT_V2_RESULT.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RunnerVersion = 'CENTRAL_DUAL_PATH_HEARTBEAT_V2_20260916'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CentralDualPathHeartbeat'
$StatePath = Join-Path $StateRoot 'state-v2.json'
$LogPath = Join-Path $StateRoot 'runner-v2.log'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-Log([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message"
}

function Find-CentralRuntimeReadback {
  $centralName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    $root = [string]$d.Root
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $candidates.Add((Join-Path $root $centralName))
    $candidates.Add((Join-Path $root ($myDriveKo + '\' + $centralName)))
    $candidates.Add((Join-Path $root ('My Drive\' + $centralName)))
    $candidates.Add((Join-Path $root ('Google Drive\' + $centralName)))
  }
  if ($env:USERPROFILE) {
    $candidates.Add((Join-Path $env:USERPROFILE $centralName))
    $candidates.Add((Join-Path $env:USERPROFILE ('Google Drive\' + $myDriveKo + '\' + $centralName)))
    $candidates.Add((Join-Path $env:USERPROFILE ('Google Drive\My Drive\' + $centralName)))
  }
  foreach ($candidate in @($candidates | Select-Object -Unique)) {
    try {
      if (Test-Path -LiteralPath $candidate -PathType Container) {
        $rr = Join-Path $candidate 'Runtime_Readback'
        if (Test-Path -LiteralPath $rr -PathType Container) { return $rr }
      }
    } catch {
      Write-Log "CANDIDATE_CHECK_FAILED path=$candidate error=$($_.Exception.Message)"
    }
  }
  return $null
}

try {
  $previousCount = 0
  if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try {
      $previous = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
      if ($null -ne $previous.runCount) { $previousCount = [int]$previous.runCount }
    } catch {
      Write-Log "PREVIOUS_STATE_PARSE_FAILED $($_.Exception.Message)"
    }
  }
  $runCount = $previousCount + 1
  $now = (Get-Date).ToUniversalTime().ToString('o')
  $readbackDir = Find-CentralRuntimeReadback
  if (-not $readbackDir) { throw 'CENTRAL_RUNTIME_READBACK_NOT_FOUND' }
  $centralReceipt = Join-Path $readbackDir $ReceiptName
  $state = [ordered]@{
    ok = $true
    mode = 'READ_ONLY_HEARTBEAT'
    targetMutationPerformed = $false
    runnerVersion = $RunnerVersion
    runCount = $runCount
    computerName = $env:COMPUTERNAME
    userName = $env:USERNAME
    timestamp = $now
    remoteDcRequired = $false
    claspRequired = $false
    oauthRequired = $false
    paidServiceRequired = $false
    runtimeReadbackFound = $true
    centralReceipt = $centralReceipt
  }
  $json = $state | ConvertTo-Json -Depth 6
  $json | Set-Content -LiteralPath $StatePath -Encoding UTF8
  $json | Set-Content -LiteralPath $centralReceipt -Encoding UTF8
  Write-Log "HEARTBEAT_PASS runCount=$runCount centralReceipt=$centralReceipt"
  $state | ConvertTo-Json -Depth 6
  exit 0
} catch {
  Write-Log "HEARTBEAT_FAIL $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
