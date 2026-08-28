param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$ArtifactType,
  [string]$SourcePath = '',
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
  $koMyDrive = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  $centralName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))

  # Prefer the already-proven central root when the local runner exposes it.
  if ($env:HDCENTRAL) {
    try {
      if (Test-Path -LiteralPath $env:HDCENTRAL) {
        $central = (Resolve-Path -LiteralPath $env:HDCENTRAL).Path
        $parent = Split-Path -Parent $central
        if ($parent -and (Test-Path -LiteralPath $parent)) { return $parent }
      }
    } catch {}
  }

  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    if (-not $d.Root) { continue }

    # Strongest probe: locate the known central folder and derive My Drive as its parent.
    foreach ($centralCandidate in @(
      (Join-Path $d.Root $centralName),
      (Join-Path (Join-Path $d.Root 'My Drive') $centralName),
      (Join-Path (Join-Path $d.Root $koMyDrive) $centralName)
    )) {
      try {
        if (Test-Path -LiteralPath $centralCandidate) {
          $resolvedCentral = (Resolve-Path -LiteralPath $centralCandidate).Path
          $parent = Split-Path -Parent $resolvedCentral
          if ($parent -and (Test-Path -LiteralPath $parent)) { return $parent }
        }
      } catch {}
    }

    $candidates.Add((Join-Path $d.Root 'My Drive'))
    $candidates.Add((Join-Path $d.Root $koMyDrive))
  }

  if ($env:USERPROFILE) {
    $candidates.Add((Join-Path $env:USERPROFILE 'My Drive'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Google Drive\My Drive'))
    $candidates.Add((Join-Path (Join-Path $env:USERPROFILE 'Google Drive') $koMyDrive))
  }

  foreach ($p in @($candidates | Select-Object -Unique)) {
    try {
      if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path }
    } catch {}
  }
  throw ('GOOGLE_DRIVE_MY_DRIVE_NOT_FOUND:candidates=' + (($candidates | Select-Object -Unique) -join '|'))
}

function Get-NotebookLMDownloadDirectories {
  $dirs = New-Object System.Collections.Generic.List[string]
  $canonical = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM'
  New-Item -ItemType Directory -Path $canonical -Force | Out-Null
  $dirs.Add($canonical)

  if ($env:USERPROFILE) {
    $dirs.Add((Join-Path $env:USERPROFILE 'Downloads'))
  }

  $pref = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\ChromeUserData\Default\Preferences'
  if (Test-Path -LiteralPath $pref) {
    try {
      $j = Get-Content -LiteralPath $pref -Raw -Encoding UTF8 | ConvertFrom-Json
      $configured = [string]$j.download.default_directory
      if ($configured) { $dirs.Add($configured) }
    } catch {}
  }

  $docs = [Environment]::GetFolderPath('MyDocuments')
  if ($docs) {
    $dirs.Add((Join-Path $docs '_365-3.30\CaptureBridge\INBOX\NotebookLM'))
    $dirs.Add((Join-Path $docs '365-3.30\CaptureBridge\INBOX\NotebookLM'))
  }

  return @($dirs | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

$localCaptureDir = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM'
$exts = Get-ExpectedExtensions $ArtifactType
$found = $null
$sourceMode = 'LEGACY_SCAN_FALLBACK'
$sourceDirs = @()

if ($SourcePath) {
  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw ("NOTEBOOKLM_EXACT_SOURCE_PATH_NOT_FOUND:{0}" -f $SourcePath)
  }
  $candidate = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
  $candidateExt = $candidate.Extension.ToLowerInvariant()
  if ($candidate.Name -like '*.crdownload' -or $candidate.Name -like '*.tmp') {
    throw ("NOTEBOOKLM_EXACT_SOURCE_INCOMPLETE:{0}" -f $candidate.FullName)
  }
  if ($exts -notcontains $candidateExt) {
    throw ("NOTEBOOKLM_EXACT_SOURCE_EXTENSION_MISMATCH:{0}:expected={1}" -f $candidateExt,($exts -join ','))
  }
  if ($candidate.Length -le 0) {
    throw ("NOTEBOOKLM_EXACT_SOURCE_ZERO_BYTES:{0}" -f $candidate.FullName)
  }
  $found = $candidate
  $sourceMode = 'EXACT_SOURCE_PATH'
} else {
  $sourceDirs = @(Get-NotebookLMDownloadDirectories)
  if ($sourceDirs.Count -eq 0) { throw 'NOTEBOOKLM_DOWNLOAD_SOURCE_DIRECTORIES_NOT_FOUND' }

  $startedUtc = if ($StartedAtEpochMs -gt 0) { [DateTimeOffset]::FromUnixTimeMilliseconds($StartedAtEpochMs).UtcDateTime.AddSeconds(-5) } else { [DateTime]::UtcNow.AddSeconds(-15) }
  $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30,[Math]::Min(600,$TimeoutSeconds)))

  while ([DateTime]::UtcNow -lt $deadline) {
    $candidates = @()
    foreach ($dir in $sourceDirs) {
      try {
        $candidates += @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
          Where-Object {
            $_.LastWriteTimeUtc -ge $startedUtc -and
            $exts -contains $_.Extension.ToLowerInvariant() -and
            $_.Name -notlike '*.crdownload' -and
            $_.Name -notlike '*.tmp' -and
            $_.Length -gt 0
          })
      } catch {}
    }
    $found = $candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($found) { break }
    Start-Sleep -Seconds 2
  }
  if (-not $found) {
    throw ("NOTEBOOKLM_ARTIFACT_DOWNLOAD_NOT_FOUND:{0}:searched={1}" -f $ArtifactType,($sourceDirs -join '|'))
  }
}

New-Item -ItemType Directory -Path $localCaptureDir -Force | Out-Null
$localSafeTask = ($TaskId -replace '[^A-Za-z0-9_.-]','_')
$localCaptureName = "${localSafeTask}__$($found.Name)"
$localCapturePath = Join-Path $localCaptureDir $localCaptureName
if ([IO.Path]::GetFullPath($found.FullName) -ne [IO.Path]::GetFullPath($localCapturePath)) {
  Copy-Item -LiteralPath $found.FullName -Destination $localCapturePath -Force
} else {
  $localCapturePath = $found.FullName
}
$localCaptured = Get-Item -LiteralPath $localCapturePath
if ($localCaptured.Length -le 0) { throw 'LOCAL_CAPTURE_COPY_ZERO_BYTES' }

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
Copy-Item -LiteralPath $localCaptured.FullName -Destination $destPath -Force
$copied = Get-Item -LiteralPath $destPath
if ($copied.Length -le 0) { throw 'DRIVE_SYNC_COPY_ZERO_BYTES' }

[pscustomobject]@{
  ok = $true
  action = 'MIRROR_NOTEBOOKLM_ARTIFACT_TO_DRIVE_SYNC'
  taskId = $TaskId
  artifactType = $ArtifactType
  sourceMode = $sourceMode
  searchedDirectories = $sourceDirs
  sourcePath = $found.FullName
  sourceName = $found.Name
  sourceBytes = $found.Length
  canonicalLocalDirectory = $localCaptureDir
  localCapturePath = $localCaptured.FullName
  localCaptureName = $localCaptured.Name
  localCaptureBytes = $localCaptured.Length
  googleDriveRoot = $myDrive
  destinationPath = $copied.FullName
  destinationName = $copied.Name
  destinationBytes = $copied.Length
  relativeDrivePath = "NotebookLM_Artifacts/$typeFolder/$($copied.Name)"
  copiedAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 -Compress
