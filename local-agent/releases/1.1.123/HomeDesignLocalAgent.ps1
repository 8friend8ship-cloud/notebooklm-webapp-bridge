param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.122/HomeDesignLocalAgent.ps1'
$tmp=Join-Path $env:TEMP 'HomeDesignLocalAgent_1.1.123_child.ps1'
$src=(Invoke-WebRequest -UseBasicParsing -Uri $raw -TimeoutSec 20).Content
$src=$src.Replace("s.includes('스튜디오')","s.includes('\\uC2A4\\uD29C\\uB514\\uC624')")
$src=$src.Replace("o.m.includes('오디오 오버뷰')","o.m.includes('\\uC624\\uB514\\uC624 \\uC624\\uBC84\\uBDF0')")
$src=$src.Replace("t==='생성'","t==='\\uC0DD\\uC131'")
$src=$src.Replace("t.startsWith('생성 ')","t.startsWith('\\uC0DD\\uC131 ')")
$src=$src.Replace("/generating|creating|생성 중|만드는 중/","/generating|creating|\\uC0DD\\uC131 \\uC911|\\uB9CC\\uB4DC\\uB294 \\uC911/")
$src=$src.Replace("t.includes('오디오 오버뷰')","t.includes('\\uC624\\uB514\\uC624 \\uC624\\uBC84\\uBDF0')")
Set-Content -LiteralPath $tmp -Value $src -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
exit $LASTEXITCODE
