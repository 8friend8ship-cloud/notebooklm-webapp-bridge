@echo off
setlocal
set "HDROOT=%LOCALAPPDATA%\HomeDesignAutomationV7\LocalAgent"
if not exist "%HDROOT%" mkdir "%HDROOT%"
set "OUT=%HDROOT%\RUN_LOCAL_EXECUTOR_RECOVERY_V1.pinned.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='https://api.github.com/repos/8friend8ship-cloud/notebooklm-webapp-bridge/contents/local-agent/bootstrap/RUN_LOCAL_EXECUTOR_RECOVERY_V1.ps1?ref=a8ac6cbc75329dc6472500c169f3226a9a08540e'; $r=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Flow-Recovery-Launcher';'Accept'='application/vnd.github+json'} -TimeoutSec 30; if(([string]$r.sha).ToLowerInvariant() -ne 'c3357a722fed085f2660efe951a3ff41418862fa'){throw ('RECOVERY_BLOB_PIN_MISMATCH:'+ [string]$r.sha)}; [IO.File]::WriteAllBytes('%OUT%',[Convert]::FromBase64String(([string]$r.content -replace '\s',''))); & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '%OUT%'; exit $LASTEXITCODE"
set "RC=%ERRORLEVEL%"
echo FLOW_RECOVERY_EXIT=%RC%
exit /b %RC%
