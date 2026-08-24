param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\ChromeGovernor'
$Runner = Join-Path $Root 'ChromeExtensionGovernor.ps1'
$Status = Join-Path $Root 'SHOW_CHROME_EXTENSION_GOVERNOR_STATUS.ps1'
$BaseUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor'
$Desktop = [Environment]::GetFolderPath('Desktop')
if([string]::IsNullOrWhiteSpace($Desktop)){ $Desktop=Join-Path $env:USERPROFILE 'Desktop' }
$Startup = [Environment]::GetFolderPath('Startup')
New-Item -ItemType Directory -Force -Path $Root | Out-Null

Write-Host '=============================================================='
Write-Host ' HomeDesign Chrome Extension Governor - ONE TIME INSTALL'
Write-Host '=============================================================='
Write-Host 'Normal ChatGPT Chrome will NOT be closed.'
Write-Host 'No extension will be auto-deleted.'
Write-Host 'No OAuth / passwords / cookies / tokens are collected.'
Write-Host ''

Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/ChromeExtensionGovernor.ps1" -OutFile $Runner
Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/SHOW_CHROME_EXTENSION_GOVERNOR_STATUS.ps1" -OutFile $Status

try {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*ChromeExtensionGovernor.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}catch{}

$ws = New-Object -ComObject WScript.Shell
$startupLink = Join-Path $Startup 'HomeDesign Chrome Extension Governor.lnk'
$sc = $ws.CreateShortcut($startupLink)
$sc.TargetPath = 'powershell.exe'
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Runner`" -Loop"
$sc.WorkingDirectory = $Root
$sc.Description = 'HomeDesign Chrome Extension Governor - managed extension inventory, health and safe update routing'
$sc.Save()

$statusLink = Join-Path $Desktop 'HomeDesign Chrome Extension Governor Status.lnk'
$ss = $ws.CreateShortcut($statusLink)
$ss.TargetPath = 'powershell.exe'
$ss.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Status`""
$ss.WorkingDirectory = $Root
$ss.Description = 'HomeDesign Chrome Extension Governor current status'
$ss.Save()

Start-Process -FilePath 'powershell.exe' -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Runner`"",'-Loop'
) -WindowStyle Hidden

Write-Host 'Governor started.'
Write-Host ('Startup shortcut : ' + $startupLink)
Write-Host ('Status shortcut  : ' + $statusLink)
Write-Host ('State JSON       : ' + (Join-Path $Root 'state.json'))
Write-Host ('Desktop report   : ' + (Join-Path $Desktop 'CHROME_EXTENSION_GOVERNOR_RESULT.json'))
Write-Host ''
Write-Host 'INSTALL RESULT: ACTIVE'
Write-Host 'Future policy changes are read from GitHub automatically every cycle.'
Write-Host '=============================================================='
pause
