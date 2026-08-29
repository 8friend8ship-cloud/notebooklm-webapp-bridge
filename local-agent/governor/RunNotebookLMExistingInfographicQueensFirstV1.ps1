param(
  [string]$TaskId = 'NLM_INFOGRAPHIC_EXISTING_QUEENS_FIRST',
  [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=90
)
$ErrorActionPreference='Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$downloadScript = Join-Path $here 'RunNotebookLMDirectCDPDownloadSyncedV3.ps1'
$queensScript = Join-Path $here 'MirrorNotebookLMArtifactQueensFirst.ps1'
if (-not (Test-Path -LiteralPath $downloadScript -PathType Leaf)) { throw 'DIRECT_CDP_DOWNLOAD_SCRIPT_NOT_FOUND' }
if (-not (Test-Path -LiteralPath $queensScript -PathType Leaf)) { throw 'QUEENS_FIRST_SCRIPT_NOT_FOUND' }

function Invoke-DownloadAttempt([string]$label) {
  $raw = & $downloadScript -NotebookUrl $NotebookUrl -ArtifactText $label -RemoteDebuggingPort $RemoteDebuggingPort -TimeoutSeconds $TimeoutSeconds 2>&1
  $exitCode = $LASTEXITCODE
  $lines = @($raw | ForEach-Object { [string]$_ })
  $jsonLine = @($lines | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
  $obj = $null
  if ($jsonLine.Count -gt 0) { try { $obj = $jsonLine[0] | ConvertFrom-Json } catch {} }
  [pscustomobject]@{ label=$label; exitCode=$exitCode; raw=$lines; result=$obj }
}

$attempts = New-Object System.Collections.Generic.List[object]
$download = $null
foreach ($label in @('인포그래픽','Infographic')) {
  $a = Invoke-DownloadAttempt $label
  $attempts.Add($a)
  if ($a.exitCode -eq 0 -and $a.result -and $a.result.ok -and @($a.result.files).Count -gt 0) { $download = $a.result; break }
  $err = if ($a.result) { [string]$a.result.error } else { '' }
  if ($err -and $err -notmatch 'ARTIFACT_MENU_NOT_FOUND|NOTEBOOK_TAB_NOT_FOUND') { break }
}
if (-not $download) {
  $summary = @($attempts | ForEach-Object { [pscustomobject]@{label=$_.label;exitCode=$_.exitCode;error=if($_.result){[string]$_.result.error}else{'NO_JSON_RESULT'}} })
  throw ('INFOGRAPHIC_EXISTING_DOWNLOAD_FAILED:' + ($summary | ConvertTo-Json -Compress))
}

$file = @($download.files | Where-Object { [int64]$_.size -gt 0 } | Select-Object -First 1)
if ($file.Count -lt 1) { throw 'INFOGRAPHIC_DOWNLOADED_FILE_NOT_FOUND' }
$sourcePath = [string]$file[0].fullName
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ('INFOGRAPHIC_SOURCE_PATH_MISSING:' + $sourcePath) }

$rawQueens = & $queensScript -TaskId $TaskId -ArtifactType 'INFOGRAPHIC' -SourcePath $sourcePath -TimeoutSeconds $TimeoutSeconds 2>&1
$qExit = $LASTEXITCODE
$qLines = @($rawQueens | ForEach-Object { [string]$_ })
$qJsonLine = @($qLines | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
if ($qExit -ne 0 -or $qJsonLine.Count -lt 1) { throw ('INFOGRAPHIC_QUEENS_FIRST_FAILED:exit=' + $qExit + ';output=' + ($qLines -join ' | ')) }
$q = $qJsonLine[0] | ConvertFrom-Json
if (-not $q.ok -or -not $q.nativeOriginalVerified -or -not $q.sourceImmutable -or [int64]$q.nativeOriginalBytes -le 0) { throw 'INFOGRAPHIC_QUEENS_FIRST_NOT_VERIFIED' }
if ($q.johnsonEligible) { throw 'JOHNSON_MUST_REMAIN_GATED_BEFORE_SEED_VERIFICATION' }

[pscustomobject]@{
  ok = $true
  action = 'NOTEBOOKLM_EXISTING_INFOGRAPHIC_QUEENS_FIRST_V1'
  taskId = $TaskId
  artifactType = 'INFOGRAPHIC'
  generationUsed = $false
  download = $download
  nativeOriginalVerified = [bool]$q.nativeOriginalVerified
  sourceImmutable = [bool]$q.sourceImmutable
  nativeOriginalPath = [string]$q.nativeOriginalPath
  nativeOriginalName = [string]$q.nativeOriginalName
  nativeOriginalBytes = [int64]$q.nativeOriginalBytes
  sha256 = [string]$q.sha256
  assetId = [string]$q.assetId
  queensStatus = [string]$q.queensStatus
  queensSidecarPath = [string]$q.queensSidecarPath
  seedEligible = [bool]$q.seedEligible
  seedVerified = [bool]$q.seedVerified
  johnsonEligible = [bool]$q.johnsonEligible
  nextGate = [string]$q.nextGate
  completedAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 30 -Compress
