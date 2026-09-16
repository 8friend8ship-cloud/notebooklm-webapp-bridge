param(
  [string]$ReceiptName = 'CENTRAL_DUAL_PATH_HEARTBEAT_RESULT.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RunnerVersion = 'CENTRAL_DUAL_PATH_HEARTBEAT_V1_20260916'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CentralDualPathHeartbeat'
$StatePath = Join-Path $StateRoot 'state.json'
$LogPath = Join-Path $StateRoot 'runner.log'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-Log([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message"
}

function Find-CentralRuntimeReadback {
  try {
    $centralName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
      $root = [string]$d.Root
      if (-not $root) { continue }
      foreach ($candidate in @(
        (Join-Path $root $centralName),
        (Join-Path $root ($myDriveKo + '\\' + $centralName)),
        (Join-Path $root ('My Drive\\' + $centralName)),
        (Join-Path $root ('Google Drive\\' + $centralName))
      )) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
          $rr = Join-Path $candidate 'Runtime_Readback'
          New-Item -ItemType Directory -Force -Path $rr | Out-Null
          return $rr
        }
      }
    }
  } catch {
    Write-Log "DRIVE_DISCOVERY_FAILED $($_.Exception.Message)"
  }
  return $null
}

try {
  $now = (Get-Date).ToUniversalTime().ToString('o')
  $state = [ordered]@{
    ok = $true
    mode = 'READ_ONLY_HEARTBEAT'
    mutationPerformed = $false
    runnerVersion = $RunnerVersion
    computerName = $env:COMPUTERNAME
    userName = $env:USERNAME
    timestamp = $now
    remoteDcRequired = $false
    claspRequired = $false
    oauthRequired = $false
    paidServiceRequired = $false
  }
  $json = $state | ConvertTo-Json -Depth 5
  $localReceipt = Join-Path $StateRoot $ReceiptName
  $json | Set-Content -LiteralPath $localReceipt -Encoding UTF8
  $readbackDir = Find-CentralRuntimeReadback
  $centralReceipt = $null
  if ($readbackDir) {
    $centralReceipt = Join-Path $readbackDir $ReceiptName
    $json | Set-Content -LiteralPath $centralReceipt -Encoding UTF8
  }
  [ordered]@{
    ok = $true
    runnerVersion = $RunnerVersion
    localReceipt = $localReceipt
    centralReceipt = $centralReceipt
    timestamp = $now
  } | ConvertTo-Json -Depth 5
  Write-Log "HEARTBEAT_PASS centralReceipt=$centralReceipt"
  exit 0
} catch {
  Write-Log "HEARTBEAT_FAIL $($_.Exception.Message)"
  Write-Error $_.Exception.Message
  exit 1
}
