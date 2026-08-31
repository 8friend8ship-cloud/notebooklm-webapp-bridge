param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.124/HomeDesignLocalAgent.ps1'
$tmp=Join-Path $env:TEMP 'HomeDesignLocalAgent_1.1.125_child.ps1'
$src=(Invoke-WebRequest -UseBasicParsing -Uri $raw -TimeoutSec 20).Content
$src=$src.Replace("49828,53804,46356,50724","49828,53916,46356,50724")
$src=$src.Replace("$Version='1.1.124'","$Version='1.1.125'")
$src=$src.Replace("AGENT_1.1.124_GENERATION_ONLY_AUDIO_START_RESULT.json","AGENT_1.1.125_GENERATION_ONLY_AUDIO_START_RESULT.json")
Set-Content -LiteralPath $tmp -Value $src -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
exit $LASTEXITCODE
