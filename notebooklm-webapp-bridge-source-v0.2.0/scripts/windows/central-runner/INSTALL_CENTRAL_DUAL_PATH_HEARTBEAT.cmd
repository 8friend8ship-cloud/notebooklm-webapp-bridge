@echo off
setlocal
set "INSTALL_DIR=%LOCALAPPDATA%\CentralDualPathHeartbeat"
set "INSTALLER=%INSTALL_DIR%\Install-CentralDualPathHeartbeat.ps1"
set "PINNED_INSTALLER_COMMIT=468af75b9f7790a5ad33ec1276dc25dc6bed8a1d"
set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/%PINNED_INSTALLER_COMMIT%/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/Install-CentralDualPathHeartbeat.ps1"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%INSTALLER%'"
if errorlevel 1 goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -IntervalMinutes 5
if errorlevel 1 goto :fail
echo.
echo CENTRAL DUAL PATH HEARTBEAT INSTALLED AND INITIAL READ-ONLY HEARTBEAT COMPLETED.
echo PINNED_INSTALLER_COMMIT=%PINNED_INSTALLER_COMMIT%
exit /b 0
:fail
echo.
echo CENTRAL DUAL PATH HEARTBEAT INSTALL FAILED. See %%LOCALAPPDATA%%\CentralDualPathHeartbeat\install.log
pause
exit /b 1
