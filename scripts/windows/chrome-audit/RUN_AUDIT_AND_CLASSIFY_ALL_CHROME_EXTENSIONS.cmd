@echo off
setlocal EnableExtensions
chcp 65001 >nul

title HomeDesign Chrome Extensions Audit + Classification

set "BASE=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/scripts/windows/chrome-audit"
set "TMP=%TEMP%\HomeDesignChromeAudit"
set "AUDIT=%TMP%\AUDIT_ALL_CHROME_EXTENSIONS.ps1"
set "CLASSIFY=%TMP%\CLASSIFY_CHROME_AUDIT_RESULT.ps1"

if not exist "%TMP%" mkdir "%TMP%"

echo ============================================================
echo HomeDesign Chrome Extensions FULL AUDIT + CLASSIFICATION
echo ============================================================
echo This is read-only. It does not remove or modify extensions.
echo.

echo [1/4] Downloading latest audit script...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/AUDIT_ALL_CHROME_EXTENSIONS.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -OutFile '%AUDIT%' -TimeoutSec 60"
if errorlevel 1 goto :download_fail

echo [2/4] Downloading latest classifier...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/CLASSIFY_CHROME_AUDIT_RESULT.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -OutFile '%CLASSIFY%' -TimeoutSec 60"
if errorlevel 1 goto :download_fail

echo [3/4] Running local Chrome/Agent/Host audit...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AUDIT%"
set "AUDIT_RC=%ERRORLEVEL%"

echo [4/4] Classifying PASS / FAIL / LIVE_READBACK_REQUIRED...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLASSIFY%"
set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
if "%RC%"=="0" (
  echo RESULT: PASS
) else if "%RC%"=="2" (
  echo RESULT: LIVE_READBACK_REQUIRED
) else (
  echo RESULT: FAIL
)
echo.
echo Desktop outputs:
echo   CHROME_ALL_EXTENSIONS_AUDIT.json
echo   CHROME_ALL_EXTENSIONS_AUDIT.txt
echo   CHROME_ALL_EXTENSIONS_CLASSIFIED.json
echo   CHROME_ALL_EXTENSIONS_CLASSIFIED.txt
echo ============================================================
echo.
pause
exit /b %RC%

:download_fail
echo.
echo DOWNLOAD FAILED - NOTHING WAS CHANGED.
echo Existing Chrome extensions and approvals remain untouched.
pause
exit /b 90
