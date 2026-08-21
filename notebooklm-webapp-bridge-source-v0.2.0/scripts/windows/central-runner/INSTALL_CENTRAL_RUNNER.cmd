@echo off
setlocal
set "INSTALL_DIR=%LOCALAPPDATA%\CentralAppsScriptRunner"
set "INSTALLER=%INSTALL_DIR%\Install-CentralAppsScriptRunner.ps1"
set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/Install-CentralAppsScriptRunner.ps1"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%INSTALLER%'"
if errorlevel 1 goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -IntervalMinutes 5
if errorlevel 1 goto :fail
echo.
echo CENTRAL APPS SCRIPT RUNNER INSTALLED AND INITIAL RUN COMPLETED.
exit /b 0
:fail
echo.
echo CENTRAL RUNNER INSTALL FAILED. See %%LOCALAPPDATA%%\CentralAppsScriptRunner\install.log
pause
exit /b 1
