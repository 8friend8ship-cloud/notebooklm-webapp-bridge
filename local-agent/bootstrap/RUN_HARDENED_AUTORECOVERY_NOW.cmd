@echo off
setlocal EnableExtensions
set "PS=%TEMP%\RUN_HARDENED_AUTORECOVERY_NOW.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$u='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/RUN_HARDENED_AUTORECOVERY_NOW.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%PS%' -TimeoutSec 60"
if errorlevel 1 exit /b %errorlevel%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS%"
set "RC=%ERRORLEVEL%"
del /q "%PS%" >nul 2>&1
exit /b %RC%
