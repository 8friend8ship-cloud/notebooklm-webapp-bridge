@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

title HomeDesign Chrome Flow Auto Resume

set "ROOT=%LOCALAPPDATA%\CentralAppsScriptRunner"
set "BASE=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner"
set "HEALTH=%ROOT%\ChromeFlowHealth.ps1"
set "RUNNER=%ROOT%\CentralAppsScriptRunner.ps1"
set "REPORT=%ROOT%\chrome-flow-health.json"
set "DESKTOP_REPORT=%USERPROFILE%\Desktop\CHROME_FLOW_HEALTH_RESULT.json"

echo ============================================================
echo HomeDesign Chrome Flow AUTO RESUME
echo ============================================================
echo.
echo [1/4] Looking for an existing RUN_CHROME_FLOW_CONNECT.cmd ...

set "FOUND="
for %%D in (
  "%USERPROFILE%\Desktop"
  "%USERPROFILE%\Downloads"
  "%USERPROFILE%\Documents"
  "%USERPROFILE%\OneDrive\Desktop"
  "%USERPROFILE%\OneDrive\Downloads"
  "%USERPROFILE%\OneDrive\Documents"
) do (
  if exist "%%~D" (
    for /r "%%~D" %%F in (RUN_CHROME_FLOW_CONNECT.cmd) do (
      if not defined FOUND set "FOUND=%%~fF"
    )
  )
)

if defined FOUND (
  echo Existing launcher found:
  echo !FOUND!
  echo.
  echo Running existing launcher...
  call "!FOUND!"
  exit /b %ERRORLEVEL%
)

echo Existing launcher not found.
echo This is OK. Continuing directly with the latest remote V2.
echo.

if not exist "%ROOT%" mkdir "%ROOT%"

echo [2/4] Downloading latest ChromeFlowHealth V2...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/ChromeFlowHealth.ps1' -OutFile '%HEALTH%'"
if errorlevel 1 goto :download_fail

echo [3/4] Refreshing Central Runner V2...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/CentralAppsScriptRunnerV2.ps1' -OutFile '%RUNNER%'"
if errorlevel 1 goto :download_fail

echo [4/4] Running canonical HomeDesign Local Agent / dedicated CFT health...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HEALTH%"
set "RC=%ERRORLEVEL%"

if exist "%REPORT%" copy /Y "%REPORT%" "%DESKTOP_REPORT%" >nul

echo.
echo ============================================================
if "%RC%"=="0" (
  echo RESULT: PASS
) else (
  echo RESULT: CHECK NEEDED ^(exit=%RC%^)
)
echo REPORT: %REPORT%
echo DESKTOP COPY: %DESKTOP_REPORT%
echo ============================================================
echo.
echo No reinstall. No new OAuth. No new Apps Script project.
echo Existing HomeDesign Local Agent and stable NotebookLM v0.2.6 are reused.
pause
exit /b %RC%

:download_fail
echo.
echo ============================================================
echo DOWNLOAD FAILED
echo ============================================================
echo Existing approvals and installed Local Agent were not changed.
echo Check network access and run this same file again.
pause
exit /b 1
