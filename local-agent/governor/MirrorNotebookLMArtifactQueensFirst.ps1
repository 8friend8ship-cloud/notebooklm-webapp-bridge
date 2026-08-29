param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$ArtifactType,
  [string]$SourcePath = '',
  [int64]$StartedAtEpochMs = 0,
  [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mirrorScript = Join-Path $here 'MirrorNotebookLMArtifactToDrive.ps1'
if (-not (Test-Path -LiteralPath $mirrorScript -PathType Leaf)) { throw 'NOTEBOOKLM_BASE_MIRROR_SCRIPT_NOT_FOUND' }

$invoke = @{
  TaskId = $TaskId
  ArtifactType = $ArtifactType
  SourcePath = $SourcePath
  StartedAtEpochMs = $StartedAtEpochMs
  TimeoutSeconds = $TimeoutSeconds
}

# The base mirror is another PowerShell script, not an external executable.
# $LASTEXITCODE is therefore not a reliable success signal here; parse its
# explicit JSON contract and fail closed on missing/invalid/not-ok output.
$raw = @()
try {
  $raw = @(& $mirrorScript @invoke 2>&1)
} catch {
  throw ('NOTEBOOKLM_BASE_MIRROR_EXCEPTION:' + $_.Exception.Message)
}
$text = @($raw | ForEach-Object { [string]$_ })
$lastJson = @($text | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
if ($lastJson.Count -lt 1) {
  throw ('NOTEBOOKLM_BASE_MIRROR_NO_JSON:output=' + ($text -join ' | '))
}
try { $mirror = $lastJson[0] | ConvertFrom-Json } catch { throw ('NOTEBOOKLM_BASE_MIRROR_BAD_JSON:' + $_.Exception.Message) }
if (-not $mirror.ok) { throw ('NOTEBOOKLM_BASE_MIRROR_NOT_OK:' + ([string]$mirror.error)) }
if (-not $mirror.destinationPath -or -not (Test-Path -LiteralPath ([string]$mirror.destinationPath) -PathType Leaf)) { throw 'QUEENS_NATIVE_ORIGINAL_NOT_FOUND' }
$dest = Get-Item -LiteralPath ([string]$mirror.destinationPath)
if ($dest.Length -le 0) { throw 'QUEENS_NATIVE_ORIGINAL_ZERO_BYTES' }

$sourceStillExists = $false
if ($mirror.sourcePath) { $sourceStillExists = Test-Path -LiteralPath ([string]$mirror.sourcePath) -PathType Leaf }
if (-not $sourceStillExists) { throw 'SOURCE_IMMUTABLE_VIOLATION' }

$hash = (Get-FileHash -LiteralPath $dest.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $hash) { throw 'QUEENS_SHA256_NOT_AVAILABLE' }
$assetId = 'NLM:' + $hash
$sidecarPath = $dest.FullName + '.capture.json'

$sidecar = [ordered]@{
  schemaVersion = 'notebooklm-queens-first-v2'
  status = 'QUEENS_INBOX'
  taskId = $TaskId
  artifactType = $ArtifactType
  assetId = $assetId
  sourceAssetId = ''
  sourcePath = [string]$mirror.sourcePath
  sourceName = [string]$mirror.sourceName
  sourceBytes = [int64]$mirror.sourceBytes
  nativeOriginalPath = $dest.FullName
  nativeOriginalName = $dest.Name
  nativeOriginalBytes = [int64]$dest.Length
  originalExtension = [string]$mirror.originalExtension
  detectedExtension = [string]$mirror.detectedExtension
  resolvedExtension = [string]$mirror.resolvedExtension
  extensionRepaired = [bool]$mirror.extensionRepaired
  sha256 = $hash
  relativeDrivePath = [string]$mirror.relativeDrivePath
  sourceImmutable = $true
  nativeOriginalVerified = $true
  hashDedupeReady = $true
  queensRegistrationReady = $true
  queensUrlVerified = $false
  seedDerivativeAllowed = $false
  seedDerivativeVerified = $false
  johnsonDeliveryAllowed = $false
  nextGate = 'QUEENS_URL_VERIFIED'
  createdAt = (Get-Date).ToString('o')
}
$sidecar | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sidecarPath -Encoding UTF8
$sidecarFile = Get-Item -LiteralPath $sidecarPath
if ($sidecarFile.Length -le 0) { throw 'QUEENS_SIDECAR_ZERO_BYTES' }

[pscustomobject]@{
  ok = $true
  action = 'MIRROR_NOTEBOOKLM_ARTIFACT_QUEENS_FIRST'
  taskId = $TaskId
  artifactType = $ArtifactType
  assetId = $assetId
  sourceImmutable = $true
  nativeOriginalVerified = $true
  nativeOriginalPath = $dest.FullName
  nativeOriginalName = $dest.Name
  nativeOriginalBytes = [int64]$dest.Length
  sha256 = $hash
  queensStatus = 'QUEENS_INBOX'
  queensUrlVerified = $false
  queensSidecarPath = $sidecarFile.FullName
  queensSidecarBytes = [int64]$sidecarFile.Length
  seedEligible = $false
  seedVerified = $false
  johnsonEligible = $false
  nextGate = 'QUEENS_URL_VERIFIED'
  mirror = $mirror
  completedAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 20 -Compress
