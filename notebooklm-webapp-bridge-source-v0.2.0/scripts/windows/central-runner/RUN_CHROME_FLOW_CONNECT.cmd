@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "ROOT=%LOCALAPPDATA%\CentralAppsScriptRunner"
set "BASE=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner"
set "HEALTH=%ROOT%\ChromeFlowHealth.ps1"
set "RUNNER=%ROOT%\CentralAppsScriptRunner.ps1"
set "REPORT=%ROOT%\chrome-flow-health.json"
set "DESKTOP_REPORT=%USERPROFILE%\Desktop\CHROME_FLOW_HEALTH_RESULT.json"

if not exist "%ROOT%" mkdir "%ROOT%"

echo [1/3] Chrome Flow health script update...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/ChromeFlowHealth.ps1' -OutFile '%HEALTH%'"
if errorlevel 1 goto :download_fail

echo [2/3] Central runner V2 refresh (existing schedule is preserved)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/CentralAppsScriptRunnerV2.ps1' -OutFile '%RUNNER%'"
if errorlevel 1 goto :download_fail

echo [3/3] Chrome extension + Apps Script E2E health check...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HEALTH%"
set "RC=%ERRORLEVEL%"

if exist "%REPORT%" copy /Y "%REPORT%" "%DESKTOP_REPORT%" >nul

echo.
echo ============================================================
if "%RC%"=="0" (
  echo CHROME FLOW CONNECT CHECK: PASS
) else (
  echo CHROME FLOW CONNECT CHECK: NEEDS REPAIR ^(exit=%RC%^)
)
echo REPORT: %REPORT%
echo DESKTOP COPY: %DESKTOP_REPORT%
echo RUNNER LOG: %ROOT%\runner.log
echo HEALTH LOG: %ROOT%\chrome-flow-health.log
echo ============================================================
echo.
echo No new OAuth, Apps Script project, or deployment was created.
echo If a Chrome check tab opened, it may be closed after this result.
pause
exit /b %RC%

:download_fail
echo.
echo DOWNLOAD FAILED. Existing OAuth/Apps Script approvals were not changed.
echo Check network access and run this same CMD again.
pause
exit /b 1
