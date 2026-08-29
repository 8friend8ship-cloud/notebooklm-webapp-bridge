param(
  [string]$TargetUrl = "https://www.coupang.com/",
  [string]$AppId = "APP_KFOOD",
  [string]$TaskId = "MANUAL_TEST",
  [string]$Query = "",
  [switch]$AutoScan
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$extensionPath = Join-Path $repoRoot "extensions\central-shopping-research-bridge"
if (-not (Test-Path $extensionPath)) {
  throw "Shopping bridge extension not found: $extensionPath"
}

$manifest = Join-Path $extensionPath "manifest.json"
if (-not (Test-Path $manifest)) {
  throw "manifest.json not found: $manifest"
}

$chromeCandidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $chromeCandidates) {
  throw "Google Chrome executable was not found in standard locations."
}

$chrome = $chromeCandidates[0]
$profileDir = Join-Path $env:LOCALAPPDATA "HomeDesignCentralAgent\ShoppingBridgeChrome"
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$builder = [System.UriBuilder]::new($TargetUrl)
if ($AutoScan) {
  $pairs = @(
    "central-shopping-scan=1",
    "appId=$([uri]::EscapeDataString($AppId))",
    "taskId=$([uri]::EscapeDataString($TaskId))"
  )
  if ($Query) { $pairs += "query=$([uri]::EscapeDataString($Query))" }
  $builder.Fragment = ($pairs -join "&")
}

$args = @(
  "--user-data-dir=$profileDir",
  "--load-extension=$extensionPath",
  "--no-first-run",
  "--no-default-browser-check",
  $builder.Uri.AbsoluteUri
)

Write-Host "[Central Shopping Bridge] Chrome: $chrome"
Write-Host "[Central Shopping Bridge] Extension: $extensionPath"
Write-Host "[Central Shopping Bridge] Profile: $profileDir"
Write-Host "[Central Shopping Bridge] Target: $($builder.Uri.AbsoluteUri)"
Write-Host "[Central Shopping Bridge] No login/CAPTCHA bypass; public visible UI research only."

Start-Process -FilePath $chrome -ArgumentList $args
