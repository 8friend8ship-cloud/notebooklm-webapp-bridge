param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$src=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.0-source.ps1'
$patched=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.1-patched.ps1'
$base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.0/HomeDesignLocalCommandHost.ps1'
$expected='3cee6a57aa2fd2ab9bcf04f275f4c95296bba247'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
$url=$base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $src -TimeoutSec 60
$actual=(GitBlobSha1 $src).ToLowerInvariant();if($actual -ne $expected){throw "Host 1.2.0 source hash mismatch actual=$actual expected=$expected"}
$code=Get-Content -LiteralPath $src -Raw -Encoding UTF8
$versionOld="`$HostVersion='1.2.0'";$versionNew="`$HostVersion='1.2.1'"
if(-not $code.Contains($versionOld)){throw 'Host 1.2.0 version patch target not found'}
$code=$code.Replace($versionOld,$versionNew)
$allowOld="'tools/Run-VideoFrameQA.ps1')";$allowNew="'tools/Run-VideoFrameQA.ps1','tools/Run-AgentDashboardPromoProductionE2E.ps1')"
if($code.Contains($allowOld)){$code=$code.Replace($allowOld,$allowNew)}
$downloadOld='Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $localScript -TimeoutSec 60'
$downloadNew='Invoke-WebRequest -UseBasicParsing -Uri ($rawUrl+''?hdcb=''+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $localScript -TimeoutSec 60'
if(-not $code.Contains($downloadOld)){throw 'Host raw download patch target not found'}
$code=$code.Replace($downloadOld,$downloadNew)
Set-Content -LiteralPath $patched -Value $code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patched
exit $LASTEXITCODE
