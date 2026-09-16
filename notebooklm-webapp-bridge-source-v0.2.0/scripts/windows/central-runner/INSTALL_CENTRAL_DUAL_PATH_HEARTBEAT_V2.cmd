@echo off
setlocal
set "INSTALL_DIR=%LOCALAPPDATA%\CentralDualPathHeartbeat"
set "INSTALLER=%INSTALL_DIR%\Install-CentralDualPathHeartbeatV2.ps1"
set "PINNED_INSTALLER_COMMIT=e0dd1b969dc9c95731ae626fdd52af99bf234c6d"
set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/%PINNED_INSTALLER_COMMIT%/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/Install-CentralDualPathHeartbeatV2.ps1"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%INSTALLER%'"
if errorlevel 1 goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -IntervalMinutes 5
if errorlevel 1 goto :fail
echo.
echo CENTRAL DUAL PATH HEARTBEAT V2 INSTALLED. INITIAL READ-ONLY HEARTBEAT COMPLETED.
echo PINNED_INSTALLER_COMMIT=%PINNED_INSTALLER_COMMIT%
exit /b 0
:fail
echo.
echo CENTRAL DUAL PATH HEARTBEAT V2 INSTALL FAILED. See %%LOCALAPPDATA%%\CentralDualPathHeartbeat\install-v2.log
pause
exit /b 1
