@echo off
setlocal
set "HDROOT=%LOCALAPPDATA%\HomeDesignAutomationV7\LocalAgent"
if not exist "%HDROOT%" mkdir "%HDROOT%"
set "OUT=%HDROOT%\RUN_LOCAL_EXECUTOR_RECOVERY_V1.pinned.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='https://api.github.com/repos/8friend8ship-cloud/notebooklm-webapp-bridge/contents/local-agent/bootstrap/RUN_LOCAL_EXECUTOR_RECOVERY_V1.ps1?ref=644761fd60c4bb2a1fd3c18c61bd50fc339c2753'; $r=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Flow-Recovery-Launcher';'Accept'='application/vnd.github+json'} -TimeoutSec 30; if(([string]$r.sha).ToLowerInvariant() -ne 'fcf2cc5d4f03cd5ecb822f8d3245a0cef78041a9'){throw ('RECOVERY_BLOB_PIN_MISMATCH:'+ [string]$r.sha)}; [IO.File]::WriteAllBytes('%OUT%',[Convert]::FromBase64String(([string]$r.content -replace '\s',''))); & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '%OUT%'; exit $LASTEXITCODE"
set "RC=%ERRORLEVEL%"
echo FLOW_RECOVERY_EXIT=%RC%
exit /b %RC%
