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
    default { return @('.mp3','.wav','.m4a','.mp4','.webm','.mov','.pdf','.pptx','.xlsx','.csv','.png','.jpg','.jpeg','.webp','.docx','.txt','.json') }
  }
}

function Get-DetectedExtension([string]$path, [string]$artifactType) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
  $stream = [IO.File]::OpenRead($path)
  try {
    $buffer = New-Object byte[] 32
    $read = $stream.Read($buffer,0,$buffer.Length)
    if ($read -ge 8 -and $buffer[0] -eq 0x89 -and $buffer[1] -eq 0x50 -and $buffer[2] -eq 0x4E -and $buffer[3] -eq 0x47 -and $buffer[4] -eq 0x0D -and $buffer[5] -eq 0x0A -and $buffer[6] -eq 0x1A -and $buffer[7] -eq 0x0A) { return '.png' }
    if ($read -ge 3 -and $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xD8 -and $buffer[2] -eq 0xFF) { return '.jpg' }
    if ($read -ge 12 -and [Text.Encoding]::ASCII.GetString($buffer,0,4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($buffer,8,4) -eq 'WEBP') { return '.webp' }
    if ($read -ge 5 -and [Text.Encoding]::ASCII.GetString($buffer,0,5) -eq '%PDF-') { return '.pdf' }
    if ($read -ge 12 -and [Text.Encoding]::ASCII.GetString($buffer,4,4) -eq 'ftyp') {
      if ($artifactType.ToUpperInvariant() -eq 'AUDIO_OVERVIEW') { return '.m4a' }
      return '.mp4'
    }
    if ($read -ge 4 -and $buffer[0] -eq 0x50 -and $buffer[1] -eq 0x4B -and $buffer[2] -eq 0x03 -and $buffer[3] -eq 0x04) {
      switch ($artifactType.ToUpperInvariant()) {
        'SLIDES' { return '.pptx' }
        'DATA_TABLE' { return '.xlsx' }
        'REPORT' { return '.docx' }
      }
    }
  } finally { $stream.Dispose() }
  return ''
}

function Resolve-ArtifactExtension([IO.FileInfo]$candidate, [string]$artifactType, [string[]]$expected) {
  $original = $candidate.Extension.ToLowerInvariant()
  $detected = Get-DetectedExtension $candidate.FullName $artifactType
  $generic = @('', '.dat', '.bin', '.blob', '.download')
  $resolved = $original
  $repaired = $false
  $allowRepair = ($artifactType.ToUpperInvariant() -eq 'INFOGRAPHIC')

  # Safety rule: extension repair is INFOGRAPHIC-only. Audio/video and all
  # other artifact families must arrive with one of their expected native
  # extensions; do not rename generic binary payloads into media files.
  if ($expected -notcontains $original) {
    if ($allowRepair -and $detected -and ($expected -contains $detected)) {
      $resolved = $detected
      $repaired = $true
    }
  }

  [pscustomobject]@{
    OriginalExtension = $original
    DetectedExtension = $detected
    ResolvedExtension = $resolved
    Repaired = $repaired
    RepairAllowed = $allowRepair
    GenericSource = ($generic -contains $original)
  }
}

function Get-Sha256([string]$path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Find-GoogleDriveMyDrive {
  $koMyDrive = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  $centralName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
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
    foreach ($centralCandidate in @((Join-Path $d.Root $centralName),(Join-Path (Join-Path $d.Root 'My Drive') $centralName),(Join-Path (Join-Path $d.Root $koMyDrive) $centralName))) {
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
    try { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } } catch {}
  }
  throw ('GOOGLE_DRIVE_MY_DRIVE_NOT_FOUND:candidates=' + (($candidates | Select-Object -Unique) -join '|'))
}

function Get-NotebookLMDownloadDirectories {
  $dirs = New-Object System.Collections.Generic.List[string]
  $canonical = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM'
  New-Item -ItemType Directory -Path $canonical -Force | Out-Null
  $dirs.Add($canonical)
  if ($env:USERPROFILE) { $dirs.Add((Join-Path $env:USERPROFILE 'Downloads')) }
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
$genericExts = @('', '.dat', '.bin', '.blob', '.download')
$found = $null
$sourceMode = 'LEGACY_SCAN_FALLBACK'
$sourceDirs = @()
$extensionInfo = $null

if ($SourcePath) {
  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw ("NOTEBOOKLM_EXACT_SOURCE_PATH_NOT_FOUND:{0}" -f $SourcePath) }
  $candidate = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
  if ($candidate.Name -like '*.crdownload' -or $candidate.Name -like '*.tmp') { throw ("NOTEBOOKLM_EXACT_SOURCE_INCOMPLETE:{0}" -f $candidate.FullName) }
  if ($candidate.Length -le 0) { throw ("NOTEBOOKLM_EXACT_SOURCE_ZERO_BYTES:{0}" -f $candidate.FullName) }
  $extensionInfo = Resolve-ArtifactExtension $candidate $ArtifactType $exts
  if ($exts -notcontains $extensionInfo.ResolvedExtension) { throw ("NOTEBOOKLM_EXACT_SOURCE_EXTENSION_MISMATCH:{0}:detected={1}:expected={2}" -f $extensionInfo.OriginalExtension,$extensionInfo.DetectedExtension,($exts -join ',')) }
  $found = $candidate
  $sourceMode = if ($extensionInfo.Repaired) { 'EXACT_SOURCE_PATH_EXTENSION_REPAIRED' } else { 'EXACT_SOURCE_PATH' }
} else {
  $sourceDirs = @(Get-NotebookLMDownloadDirectories)
  if ($sourceDirs.Count -eq 0) { throw 'NOTEBOOKLM_DOWNLOAD_SOURCE_DIRECTORIES_NOT_FOUND' }
  $startedUtc = if ($StartedAtEpochMs -gt 0) { [DateTimeOffset]::FromUnixTimeMilliseconds($StartedAtEpochMs).UtcDateTime.AddSeconds(-5) } else { [DateTime]::UtcNow.AddSeconds(-15) }
  $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30,[Math]::Min(600,$TimeoutSeconds)))
  while ([DateTime]::UtcNow -lt $deadline) {
    $candidates = @()
    foreach ($dir in $sourceDirs) {
      try {
        $candidates += @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object {
          $_.LastWriteTimeUtc -ge $startedUtc -and $_.Name -notlike '*.crdownload' -and $_.Name -notlike '*.tmp' -and $_.Length -gt 0 -and (($exts -contains $_.Extension.ToLowerInvariant()) -or ($ArtifactType.ToUpperInvariant() -eq 'INFOGRAPHIC' -and ($genericExts -contains $_.Extension.ToLowerInvariant())))
        })
      } catch {}
    }
    foreach ($candidate in @($candidates | Sort-Object LastWriteTimeUtc -Descending)) {
      $probe = Resolve-ArtifactExtension $candidate $ArtifactType $exts
      if ($exts -contains $probe.ResolvedExtension) { $found = $candidate; $extensionInfo = $probe; break }
    }
    if ($found) { break }
    Start-Sleep -Seconds 2
  }
  if (-not $found) { throw ("NOTEBOOKLM_ARTIFACT_DOWNLOAD_NOT_FOUND:{0}:searched={1}" -f $ArtifactType,($sourceDirs -join '|')) }
}

if (-not $extensionInfo) { $extensionInfo = Resolve-ArtifactExtension $found $ArtifactType $exts }
$resolvedExt = [string]$extensionInfo.ResolvedExtension
$sourceBytesBefore = [int64]$found.Length
$sourceHashBefore = Get-Sha256 $found.FullName
if (-not $sourceHashBefore) { throw 'SOURCE_SHA256_NOT_AVAILABLE' }

New-Item -ItemType Directory -Path $localCaptureDir -Force | Out-Null
$localSafeTask = ($TaskId -replace '[^A-Za-z0-9_.-]','_')
$sourceBase = [IO.Path]::GetFileNameWithoutExtension($found.Name)
$localCaptureName = "${localSafeTask}__${sourceBase}${resolvedExt}"
$localCapturePath = Join-Path $localCaptureDir $localCaptureName
if ([IO.Path]::GetFullPath($found.FullName) -ne [IO.Path]::GetFullPath($localCapturePath)) { Copy-Item -LiteralPath $found.FullName -Destination $localCapturePath -Force } else { $localCapturePath = $found.FullName }
$localCaptured = Get-Item -LiteralPath $localCapturePath
if ($localCaptured.Length -le 0) { throw 'LOCAL_CAPTURE_COPY_ZERO_BYTES' }
$localHash = Get-Sha256 $localCaptured.FullName
if ($localCaptured.Length -ne $sourceBytesBefore -or $localHash -ne $sourceHashBefore) { throw 'LOCAL_CAPTURE_BINARY_INTEGRITY_MISMATCH' }

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
$safeTask = ($TaskId -replace '[^A-Za-z0-9_.-]','_')
$destName = "${safeTask}__${sourceBase}${resolvedExt}"
$destPath = Join-Path $destDir $destName
Copy-Item -LiteralPath $localCaptured.FullName -Destination $destPath -Force
$copied = Get-Item -LiteralPath $destPath
if ($copied.Length -le 0) { throw 'DRIVE_SYNC_COPY_ZERO_BYTES' }
$destinationHash = Get-Sha256 $copied.FullName
if ($copied.Length -ne $sourceBytesBefore -or $destinationHash -ne $sourceHashBefore) { throw 'DRIVE_SYNC_BINARY_INTEGRITY_MISMATCH' }

if (-not (Test-Path -LiteralPath $found.FullName -PathType Leaf)) { throw 'SOURCE_IMMUTABLE_VIOLATION' }
$sourceAfter = Get-Item -LiteralPath $found.FullName
$sourceHashAfter = Get-Sha256 $sourceAfter.FullName
if ($sourceAfter.Length -ne $sourceBytesBefore -or $sourceHashAfter -ne $sourceHashBefore) { throw 'SOURCE_IMMUTABLE_HASH_MISMATCH' }

[pscustomobject]@{
  ok = $true
  action = 'MIRROR_NOTEBOOKLM_ARTIFACT_TO_DRIVE_SYNC'
  taskId = $TaskId
  artifactType = $ArtifactType
  sourceMode = $sourceMode
  searchedDirectories = $sourceDirs
  sourcePath = $found.FullName
  sourceName = $found.Name
  sourceBytes = $sourceBytesBefore
  sourceSha256 = $sourceHashBefore
  sourceImmutableVerified = $true
  originalExtension = $extensionInfo.OriginalExtension
  detectedExtension = $extensionInfo.DetectedExtension
  resolvedExtension = $extensionInfo.ResolvedExtension
  extensionRepaired = [bool]$extensionInfo.Repaired
  extensionRepairAllowed = [bool]$extensionInfo.RepairAllowed
  canonicalLocalDirectory = $localCaptureDir
  localCapturePath = $localCaptured.FullName
  localCaptureName = $localCaptured.Name
  localCaptureBytes = $localCaptured.Length
  localCaptureSha256 = $localHash
  googleDriveRoot = $myDrive
  destinationPath = $copied.FullName
  destinationName = $copied.Name
  destinationBytes = $copied.Length
  destinationSha256 = $destinationHash
  binaryIntegrityVerified = $true
  relativeDrivePath = "NotebookLM_Artifacts/$typeFolder/$($copied.Name)"
  copiedAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 -Compress
