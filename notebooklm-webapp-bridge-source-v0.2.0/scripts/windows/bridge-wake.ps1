param(
  [string]$ConfigPath = "$PSScriptRoot\windows-bridge-config.json"
)

$ErrorActionPreference = 'Stop'

function Write-BridgeLog($message) {
  $logDir = Join-Path $env:LOCALAPPDATA 'NotebookLMBridge'
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $line = "$(Get-Date -Format o) $message"
  Add-Content -Path (Join-Path $logDir 'wake.log') -Value $line
}

try {
  if (!(Test-Path $ConfigPath)) {
    throw "설정 파일이 없습니다: $ConfigPath"
  }

  $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
  $frontendUrl = [string]$config.frontendUrl
  $chromePath = [string]$config.chromePath

  if ([string]::IsNullOrWhiteSpace($frontendUrl) -or $frontendUrl -notmatch '^https?://') {
    throw 'frontendUrl이 올바르지 않습니다.'
  }

  if ([string]::IsNullOrWhiteSpace($chromePath)) {
    $candidates = @(
      "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
      "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $chromePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  }

  if (!$chromePath -or !(Test-Path $chromePath)) {
    throw 'Chrome 실행 파일을 찾지 못했습니다.'
  }

  Write-BridgeLog "WAKE_TRIGGER chrome=$chromePath frontend=$frontendUrl"

  $existing = Get-Process chrome -ErrorAction SilentlyContinue
  if (!$existing) {
    Start-Process -FilePath $chromePath -ArgumentList @('--new-window', $frontendUrl)
    Write-BridgeLog 'Chrome started.'
  } else {
    Start-Process -FilePath $chromePath -ArgumentList @('--new-tab', $frontendUrl)
    Write-BridgeLog 'Chrome already running; bridge tab opened.'
  }

  # Keep the machine awake briefly so Chrome, the extension service worker,
  # and the bridge frontend have time to initialize and claim queued work.
  $holdSeconds = if ($config.holdAwakeSeconds) { [int]$config.holdAwakeSeconds } else { 300 }
  Start-Sleep -Seconds ([Math]::Max(60, $holdSeconds))

  Write-BridgeLog 'Wake launcher finished.'
  exit 0
} catch {
  Write-BridgeLog "ERROR $($_.Exception.Message)"
  exit 1
}
