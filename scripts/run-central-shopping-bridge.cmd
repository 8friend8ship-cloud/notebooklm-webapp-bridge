@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run-central-shopping-bridge.ps1" %*
set EXITCODE=%ERRORLEVEL%
endlocal & exit /b %EXITCODE%
