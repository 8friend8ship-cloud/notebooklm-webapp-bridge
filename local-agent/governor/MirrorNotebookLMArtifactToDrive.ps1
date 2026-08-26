param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$ArtifactType,
  [int64]$StartedAtEpochMs = 0,
  [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

function Get-ExpectedExtensions([string]$type) {
  switch ($type.ToUpperInvariant()) {
    'AUDIO_OVERVIEW' { return @('.mp3','.wav','.m4a','.ogg','.mp4') }
    'VIDEO_OVERVIEW' { return @('.mp4','.webm','.mov') }
    'SLIDES' { return @('.pdf','.pptx') }
    'REPORT' { return @('.pdf','.docx','.txt') }
    'DATA_TABLE' { return @('.xlsx','.csv') }
    'INFOGRAPHIC' { return @('.png','.jpg','.jpeg','.webp','.pdf') }
    'MIND_MAP' { return @('.pdf','.png','.json') }
    'FLASHCARDS' { return @('.pdf','.csv','.txt') }
    'QUIZ' { return @('.pdf','.txt','.csv') }
    default { return @('.mp3','.wav','.m4a','.mp4','.webm','.pdf','.pptx','.xlsx','.csv','.png','.jpg','.jpeg','.webp','.docx','.txt','.json') }
  }
}

function Find-GoogleDriveMyDrive {
  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    if (-not $d.Root) { continue }
    $candidates.Add((Join-Path $d.Root 'My Drive'))
    $candidates.Add((Join-Path $d.Root '내 드라이브'))
  }
  if ($env:USERPROFILE) {
    $candidates.Add((Join-Path $env:USERPROFILE 'My Drive'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Google Drive\My Drive'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Google Drive\내 드라이브'))
  }
  foreach ($p in ($candidates | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
  }
  throw 'GOOGLE_DRIVE_MY_DRIVE_NOT_FOUND'
}

$downloads = Join-Path $env:USERPROFILE 'Downloads'
if (-not (Test-Path -LiteralPath $downloads)) { throw 'WINDOWS_DOWNLOADS_NOT_FOUND' }
$exts = Get-ExpectedExtensions $ArtifactType
$startedUtc = if ($StartedAtEpochMs -gt 0) { [DateTimeOffset]::FromUnixTimeMilliseconds($StartedAtEpochMs).UtcDateTime.AddSeconds(-5) } else { [DateTime]::UtcNow.AddSeconds(-15) }
$deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30,[Math]::Min(600,$TimeoutSeconds)))
$found = $null

while ([DateTime]::UtcNow -lt $deadline) {
  $found = Get-ChildItem -LiteralPath $downloads -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTimeUtc -ge $startedUtc -and $exts -contains $_.Extension.ToLowerInvariant() -and $_.Name -notlike '*.crdownload' } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if ($found) { break }
  Start-Sleep -Seconds 2
}
if (-not $found) { throw "NOTEBOOKLM_ARTIFACT_DOWNLOAD_NOT_FOUND:$ArtifactType" }

$myDrive = Find-GoogleDriveMyDrive
$typeFolder = switch ($ArtifactType.ToUpperInvariant()) {
  'AUDIO_OVERVIEW' { 'Audio' }
  'VIDEO_OVERVIEW' { 'Video' }
  'SLIDES' { 'Slides' }
  'REPORT' { 'Report' }
  'DATA_TABLE' { 'DataTable' }
  'INFOGRAPHIC' { 'Infographic' }
  'MIND_MAP' { 'MindMap' }
  'FLASHCARDS' { 'Flashcards' }
  'QUIZ' { 'Quiz' }
  default { 'Other' }
}
$destDir = Join-Path (Join-Path $myDrive 'NotebookLM_Artifacts') $typeFolder
New-Item -ItemType Directory -Path $destDir -Force | Out-Null
$base = [IO.Path]::GetFileNameWithoutExtension($found.Name)
$ext = $found.Extension
$safeTask = ($TaskId -replace '[^A-Za-z0-9_.-]','_')
$destName = "${safeTask}__${base}${ext}"
$destPath = Join-Path $destDir $destName
Copy-Item -LiteralPath $found.FullName -Destination $destPath -Force
$copied = Get-Item -LiteralPath $destPath
if ($copied.Length -le 0) { throw 'DRIVE_SYNC_COPY_ZERO_BYTES' }

[pscustomobject]@{
  ok = $true
  action = 'MIRROR_NOTEBOOKLM_ARTIFACT_TO_DRIVE_SYNC'
  taskId = $TaskId
  artifactType = $ArtifactType
  sourcePath = $found.FullName
  sourceName = $found.Name
  sourceBytes = $found.Length
  googleDriveRoot = $myDrive
  destinationPath = $copied.FullName
  destinationName = $copied.Name
  destinationBytes = $copied.Length
  relativeDrivePath = "NotebookLM_Artifacts/$typeFolder/$($copied.Name)"
  copiedAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 6 -Compress
