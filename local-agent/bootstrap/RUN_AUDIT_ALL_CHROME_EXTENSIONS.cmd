@echo off
setlocal EnableExtensions
chcp 65001 >nul
title HomeDesign Chrome All Extensions Audit

set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/AUDIT_ALL_CHROME_EXTENSIONS.ps1"
set "PS1=%TEMP%\AUDIT_ALL_CHROME_EXTENSIONS.ps1"

echo ============================================================
echo HomeDesign Chrome ALL EXTENSIONS AUDIT
echo - Read-only
echo - No reinstall
echo - No OAuth
echo - No extension changes
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';Invoke-WebRequest -UseBasicParsing -Uri ('%URL%?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile '%PS1%' -TimeoutSec 60"
if errorlevel 1 goto :fail

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo RESULT: AUDIT COMPLETE
  echo Desktop files:
  echo   CHROME_ALL_EXTENSIONS_AUDIT.json
  echo   CHROME_ALL_EXTENSIONS_AUDIT.txt
) else (
  echo RESULT: CHECK REQUIRED ^(exit=%RC%^)
)
echo.
pause
exit /b %RC%

:fail
echo DOWNLOAD FAILED - NOTHING WAS CHANGED
pause
exit /b 1
