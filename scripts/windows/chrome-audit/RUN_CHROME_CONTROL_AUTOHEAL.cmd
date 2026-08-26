@echo off
setlocal EnableExtensions
chcp 65001 >nul
title HomeDesign Chrome Control Auto-Heal

set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/scripts/windows/chrome-audit/AUTO_HEAL_CHROME_RUNTIME.ps1"
set "PS1=%TEMP%\AUTO_HEAL_CHROME_RUNTIME.ps1"

echo ============================================================
echo HomeDesign Chrome Control
echo Audit ^> Safe Auto-Repair ^> Re-Audit ^> Centralized Evidence
echo ============================================================
echo Desktop audit clutter will be consolidated automatically.
echo Normal Chrome, OAuth, extension removal and permissions are not changed.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';Invoke-WebRequest -UseBasicParsing -Uri ('%URL%?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile '%PS1%' -TimeoutSec 60"
if errorlevel 1 goto :fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

echo.
echo Results are stored under:
echo %%LOCALAPPDATA%%\HomeDesignAutomation\ChromeControl\Current
echo Previous runs:
echo %%LOCALAPPDATA%%\HomeDesignAutomation\ChromeControl\History
echo.
pause
exit /b %RC%

:fail
echo DOWNLOAD FAILED - NOTHING WAS CHANGED
pause
exit /b 90
