param(
  [string]$DownloadFolder = (Join-Path $env:USERPROFILE 'Downloads'),
  [string]$CaptureFolder = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM',
  [string]$FilenamePattern = '*',
  [int]$RunSeconds = 180,
  [int]$StableChecks = 3,
  [int]$StableCheckMilliseconds = 750
)

$ErrorActionPreference = 'Stop'
$allowedExtensions = @('.mp3','.wav','.m4a','.ogg','.mp4','.webm','.mov','.pdf','.pptx','.xlsx','.csv','.png','.jpg','.jpeg','.webp','.docx','.txt','.json')

if (-not (Test-Path -LiteralPath $DownloadFolder -PathType Container)) {
  throw ("DOWNLOAD_FOLDER_NOT_FOUND:{0}" -f $DownloadFolder)
}
New-Item -ItemType Directory -Path $CaptureFolder -Force | Out-Null

function Test-NotebookLMCandidate([string]$path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
  $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  if (-not $item) { return $false }
  if ($item.Name -like '*.crdownload' -or $item.Name -like '*.tmp') { return $false }
  if ($item.Name -notlike $FilenamePattern) { return $false }
  if ($allowedExtensions -notcontains $item.Extension.ToLowerInvariant()) { return $false }
  return $true
}

function Wait-StableFile([string]$path) {
  $required = [Math]::Max(2, $StableChecks)
  $lastLength = -1L
  $stable = 0
  for ($i = 0; $i -lt ($required + 12); $i++) {
    if (-not (Test-NotebookLMCandidate $path)) {
      Start-Sleep -Milliseconds $StableCheckMilliseconds
      continue
    }
    try {
      $item = Get-Item -LiteralPath $path -ErrorAction Stop
      if ($item.Length -gt 0 -and $item.Length -eq $lastLength) {
        $stable++
      } else {
        $stable = 0
      }
      $lastLength = $item.Length
      if ($stable -ge $required) {
        $stream = [IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $stream.Dispose()
        return $item
      }
    } catch {
      $stable = 0
    }
    Start-Sleep -Milliseconds $StableCheckMilliseconds
  }
  return $null
}

$watcher = [IO.FileSystemWatcher]::new($DownloadFolder)
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size, CreationTime'
$watcher.EnableRaisingEvents = $true

$copied = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(10,$RunSeconds))

try {
  while ([DateTime]::UtcNow -lt $deadline) {
    $remainingMs = [int][Math]::Max(50,[Math]::Min(750,($deadline - [DateTime]::UtcNow).TotalMilliseconds))
    $change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::All,$remainingMs)
    if ($change.TimedOut -or -not $change.Name) { continue }

    $path = Join-Path $DownloadFolder ([string]$change.Name)
    if ($seen.Contains($path)) { continue }
    if (-not (Test-NotebookLMCandidate $path)) { continue }

    $stable = Wait-StableFile $path
    if (-not $stable) { continue }
    [void]$seen.Add($stable.FullName)

    $dest = Join-Path $CaptureFolder $stable.Name
    Copy-Item -LiteralPath $stable.FullName -Destination $dest -Force
    $destItem = Get-Item -LiteralPath $dest -ErrorAction Stop
    if ($destItem.Length -ne $stable.Length -or $destItem.Length -le 0) {
      throw ("WATCHER_CAPTURE_COPY_VERIFY_FAILED:{0}" -f $stable.FullName)
    }
    $copied.Add([pscustomobject]@{
      sourcePath = $stable.FullName
      destinationPath = $destItem.FullName
      changeType = [string]$change.ChangeType
      bytes = $destItem.Length
      copiedAt = (Get-Date).ToString('o')
    })
  }
} finally {
  $watcher.Dispose()
}

[pscustomobject]@{
  ok = $true
  action = 'WATCH_NOTEBOOKLM_DOWNLOADS_TO_CAPTUREBRIDGE_FALLBACK'
  mode = 'FALLBACK_ONLY'
  waitMode = 'SYNCHRONOUS_WAIT_FOR_CHANGED'
  downloadFolder = $DownloadFolder
  captureFolder = $CaptureFolder
  filenamePattern = $FilenamePattern
  copiedCount = $copied.Count
  copied = $copied
} | ConvertTo-Json -Depth 8 -Compress
