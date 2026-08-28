param(
  [Parameter(Mandatory=$true)][ValidateSet('NotebookLM','Flow','AIStudio','GoogleAI')][string]$ServiceKey,
  [string]$SourcePath = '',
  [string]$TaskId = '',
  [switch]$ReconcileOnly,
  [string]$LocalInboxRoot = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX',
  [string]$CentralRootOverride = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-ServiceConfig([string]$Key) {
  switch ($Key) {
    'NotebookLM' {
      return [ordered]@{
        folder = 'NotebookLM'
        extensions = @('.mp3','.wav','.m4a','.ogg','.mp4','.webm','.mov','.pdf','.pptx','.xlsx','.csv','.png','.jpg','.jpeg','.webp','.docx','.txt','.json')
      }
    }
    'Flow' {
      return [ordered]@{
        folder = 'Flow'
        extensions = @('.mp4','.webm','.mov','.png','.jpg','.jpeg','.webp')
      }
    }
    'AIStudio' {
      return [ordered]@{
        folder = 'AIStudio'
        extensions = @('.json','.txt','.md','.csv','.pdf','.png','.jpg','.jpeg','.webp','.mp3','.wav','.m4a','.mp4','.webm','.mov')
      }
    }
    'GoogleAI' {
      return [ordered]@{
        folder = 'GoogleAI'
        extensions = @('.json','.txt','.md','.csv','.pdf','.png','.jpg','.jpeg','.webp','.mp3','.wav','.m4a','.mp4','.webm','.mov')
      }
    }
  }
  throw ('UNSUPPORTED_SERVICE_KEY:{0}' -f $Key)
}

function Find-CentralRoot {
  if ($CentralRootOverride) {
    if (Test-Path -LiteralPath $CentralRootOverride -PathType Container) {
      return (Resolve-Path -LiteralPath $CentralRootOverride).Path
    }
    throw ('CENTRAL_ROOT_OVERRIDE_NOT_FOUND:{0}' -f $CentralRootOverride)
  }

  $target = '00_중앙에이전트'
  foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    $root = [string]$drive.Root
    if (-not $root) { continue }
    foreach ($candidate in @(
      (Join-Path $root $target),
      (Join-Path $root ('My Drive\' + $target)),
      (Join-Path $root ('내 드라이브\' + $target)),
      (Join-Path $root ('Google Drive\' + $target))
    )) {
      if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
  }
  throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-VerifiedArtifact([System.IO.FileInfo]$File,$Config) {
  if (-not $File -or -not $File.Exists) { throw 'ARTIFACT_NOT_FOUND' }
  if ($File.Name -like '*.crdownload' -or $File.Name -like '*.tmp' -or $File.Name -like '*.capture.json') {
    throw ('ARTIFACT_INCOMPLETE_OR_METADATA:{0}' -f $File.FullName)
  }
  if ($File.Length -le 0) { throw ('ARTIFACT_ZERO_BYTES:{0}' -f $File.FullName) }
  $ext = $File.Extension.ToLowerInvariant()
  if ($Config.extensions -notcontains $ext) {
    throw ('ARTIFACT_EXTENSION_NOT_ALLOWED:{0}:service={1}' -f $ext,$ServiceKey)
  }
}

$config = Get-ServiceConfig $ServiceKey
$localServiceDir = Join-Path $LocalInboxRoot ([string]$config.folder)
New-Item -ItemType Directory -Force -Path $localServiceDir | Out-Null
$centralRoot = Find-CentralRoot
$driveServiceDir = Join-Path (Join-Path $centralRoot 'CaptureBridge\INBOX') ([string]$config.folder)
New-Item -ItemType Directory -Force -Path $driveServiceDir | Out-Null
$healthDir = Join-Path $centralRoot 'CaptureBridge\Health'
New-Item -ItemType Directory -Force -Path $healthDir | Out-Null

if (-not $TaskId) { $TaskId = 'CAPTURE_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
$safeTask = ($TaskId -replace '[^A-Za-z0-9_.-]','_')
$results = @()

function Copy-ToCaptureAndDrive([System.IO.FileInfo]$Source,[string]$Mode) {
  Assert-VerifiedArtifact $Source $config

  $sourceFull = [IO.Path]::GetFullPath($Source.FullName)
  $localName = if ($Mode -eq 'EXACT_SOURCE_PATH') { "${safeTask}__$($Source.Name)" } else { $Source.Name }
  $localPath = Join-Path $localServiceDir $localName
  $localFull = [IO.Path]::GetFullPath($localPath)

  if ($sourceFull -ne $localFull) {
    Copy-Item -LiteralPath $Source.FullName -Destination $localPath -Force
  }
  $localFile = Get-Item -LiteralPath $localPath -ErrorAction Stop
  Assert-VerifiedArtifact $localFile $config

  $drivePath = Join-Path $driveServiceDir $localFile.Name
  $needsCopy = $true
  if (Test-Path -LiteralPath $drivePath -PathType Leaf) {
    $existing = Get-Item -LiteralPath $drivePath -ErrorAction Stop
    if ($existing.Length -eq $localFile.Length) {
      try { $needsCopy = ((Get-Sha256 $existing.FullName) -ne (Get-Sha256 $localFile.FullName)) } catch { $needsCopy = $true }
    }
  }
  if ($needsCopy) { Copy-Item -LiteralPath $localFile.FullName -Destination $drivePath -Force }

  $driveFile = Get-Item -LiteralPath $drivePath -ErrorAction Stop
  Assert-VerifiedArtifact $driveFile $config
  if ([int64]$driveFile.Length -ne [int64]$localFile.Length) { throw 'DRIVE_COPY_SIZE_MISMATCH' }
  $localHash = Get-Sha256 $localFile.FullName
  $driveHash = Get-Sha256 $driveFile.FullName
  if ($localHash -ne $driveHash) { throw 'DRIVE_COPY_HASH_MISMATCH' }

  $meta = [ordered]@{
    serviceKey = $ServiceKey
    taskId = $TaskId
    mode = $Mode
    sourcePath = $Source.FullName
    sourceBytes = [int64]$Source.Length
    localCapturePath = $localFile.FullName
    drivePath = $driveFile.FullName
    bytes = [int64]$driveFile.Length
    sha256 = $driveHash
    originalPreserved = (Test-Path -LiteralPath $Source.FullName -PathType Leaf)
    copiedAt = (Get-Date).ToString('o')
  }
  $meta | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($drivePath + '.capture.json') -Encoding UTF8
  return [pscustomobject]$meta
}

if ($SourcePath) {
  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw ('EXACT_SOURCE_PATH_NOT_FOUND:{0}' -f $SourcePath) }
  $results += Copy-ToCaptureAndDrive (Get-Item -LiteralPath $SourcePath -ErrorAction Stop) 'EXACT_SOURCE_PATH'
} elseif ($ReconcileOnly) {
  foreach ($file in @(Get-ChildItem -LiteralPath $localServiceDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)) {
    if ($file.Name -like '*.crdownload' -or $file.Name -like '*.tmp' -or $file.Name -like '*.capture.json') { continue }
    if ($file.Length -le 0) { continue }
    if ($config.extensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
    $results += Copy-ToCaptureAndDrive $file 'RECONCILE_EXPLICIT_INBOX'
  }
} else {
  throw 'SOURCE_PATH_OR_RECONCILE_REQUIRED'
}

$health = [ordered]@{
  ok = $true
  action = 'MANAGED_CHROME_EXTENSION_CAPTUREBRIDGE'
  serviceKey = $ServiceKey
  taskId = $TaskId
  localInbox = $localServiceDir
  driveInbox = $driveServiceDir
  processedCount = @($results).Count
  sourceDiscovery = 'EXPLICIT_SOURCE_PATH_OR_EXPLICIT_SERVICE_INBOX_ONLY'
  genericDownloadsScan = $false
  copyOnly = $true
  results = @($results)
  at = (Get-Date).ToString('o')
}
$healthPath = Join-Path $healthDir (('CAPTUREBRIDGE_{0}_HEALTH.json' -f $ServiceKey.ToUpperInvariant()))
$health | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $healthPath -Encoding UTF8
$health | ConvertTo-Json -Depth 12 -Compress
