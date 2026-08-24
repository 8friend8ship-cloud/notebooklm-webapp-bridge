param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.7'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$src=Join-Path $Root 'HomeDesignLocalAgent-1.1.6-source.ps1'
$patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.7-patched.ps1'
$url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.6/HomeDesignLocalAgent.ps1'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $src -TimeoutSec 60
$code=Get-Content -LiteralPath $src -Raw -Encoding UTF8
$old="foreach(`$l in 'D'..'Z')"
$new="foreach(`$l in @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { [string]`$_.Name }))"
if(-not $code.Contains($old)){throw '1.1.6 FindCentral patch target not found'}
$code=$code.Replace($old,$new)
$code=$code.Replace("`$AgentVersion='1.1.6'","`$AgentVersion='1.1.7'")
Set-Content -LiteralPath $patched -Value $code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patched
$rc=$LASTEXITCODE
if($rc -ne 0){throw "Patched Local Agent 1.1.7 failed exit=$rc"}
