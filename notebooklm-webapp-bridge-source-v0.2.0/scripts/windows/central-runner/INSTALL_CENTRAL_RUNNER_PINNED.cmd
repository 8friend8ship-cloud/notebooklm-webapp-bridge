@echo off
setlocal
set "INSTALL_DIR=%LOCALAPPDATA%\CentralAppsScriptRunner"
set "INSTALLER=%INSTALL_DIR%\Install-CentralAppsScriptRunnerPinned.ps1"
set "PINNED_INSTALLER_COMMIT=612e78716c1faf0434984787df0701a4d1bcc84d"
set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/%PINNED_INSTALLER_COMMIT%/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/Install-CentralAppsScriptRunnerPinned.ps1"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%INSTALLER%'"
if errorlevel 1 goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -IntervalMinutes 5
if errorlevel 1 goto :fail
echo.
echo CENTRAL APPS SCRIPT PINNED READ-ONLY RUNNER INSTALLED AND INITIAL RUN COMPLETED.
echo PINNED_INSTALLER_COMMIT=%PINNED_INSTALLER_COMMIT%
exit /b 0
:fail
echo.
echo CENTRAL RUNNER PINNED INSTALL FAILED. See %%LOCALAPPDATA%%\CentralAppsScriptRunner\install-pinned.log
pause
exit /b 1
