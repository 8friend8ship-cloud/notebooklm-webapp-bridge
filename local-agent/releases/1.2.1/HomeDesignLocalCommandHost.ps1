param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$src=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.0-source.ps1'
$patched=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.1-patched.ps1'
$url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.0/HomeDesignLocalCommandHost.ps1'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $src -TimeoutSec 60
$code=Get-Content -LiteralPath $src -Raw -Encoding UTF8
$versionOld="`$HostVersion='1.2.0'"
$versionNew="`$HostVersion='1.2.1'"
if(-not $code.Contains($versionOld)){throw 'Host 1.2.0 version patch target not found'}
$code=$code.Replace($versionOld,$versionNew)
$old="'tools/Run-VideoFrameQA.ps1')"
$new="'tools/Run-VideoFrameQA.ps1','tools/Run-AgentDashboardPromoProductionE2E.ps1')"
if(-not $code.Contains($old)){throw 'Host allowlist patch target not found'}
$code=$code.Replace($old,$new)
Set-Content -LiteralPath $patched -Value $code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patched
exit $LASTEXITCODE
