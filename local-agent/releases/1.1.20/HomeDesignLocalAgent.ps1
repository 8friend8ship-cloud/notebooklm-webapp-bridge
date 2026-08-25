param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.20'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.19-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.20-patched.ps1'
$SourceUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.19/HomeDesignLocalAgent.ps1'
$Expected='c911928014f49ed50a91c5461b4c45ee0534e94b'

function GitBlobSha1([string]$Path){$B=[IO.File]::ReadAllBytes($Path);$H=[Text.Encoding]::ASCII.GetBytes(('blob '+$B.Length+[char]0));$A=New-Object byte[] ($H.Length+$B.Length);[Buffer]::BlockCopy($H,0,$A,0,$H.Length);[Buffer]::BlockCopy($B,0,$A,$H.Length,$B.Length);$S=[Security.Cryptography.SHA1]::Create();try{return (($S.ComputeHash($A)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$S.Dispose()}}
$Url=$SourceUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Source -TimeoutSec 20
$Actual=(GitBlobSha1 $Source).ToLowerInvariant()
if($Actual -ne $Expected){throw "AGENT_1.1.19_SOURCE_SHA_MISMATCH actual=$Actual expected=$Expected"}
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$OldVersion="`$AgentVersion='1.1.19'"
$NewVersion="`$AgentVersion='1.1.20'"
if(-not $Code.Contains($OldVersion)){throw 'AGENT_VERSION_PATCH_TARGET_MISSING'}
$Code=$Code.Replace($OldVersion,$NewVersion)
$OldMutex="'HomeDesignLocalAgent119'"
$NewMutex="'HomeDesignLocalAgent120'"
if(-not $Code.Contains($OldMutex)){throw 'AGENT_MUTEX_PATCH_TARGET_MISSING'}
$Code=$Code.Replace($OldMutex,$NewMutex)
$OldFetch="function WriteApiText([string]`$RepoPath,[string]`$LocalPath,[int]`$Timeout=10){`$R=ApiFile `$RepoPath 'main' `$Timeout;`$Tmp=`$LocalPath+'.download';[IO.File]::WriteAllBytes(`$Tmp,(ApiBytes `$R));Move-Item `$Tmp `$LocalPath -Force;return Get-Content `$LocalPath -Raw -Encoding UTF8}"
$NewFetch="function WriteApiText([string]`$RepoPath,[string]`$LocalPath,[int]`$Timeout=10){`$Url='https://raw.githubusercontent.com/'+`$Repo+'/main/'+`$RepoPath+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();`$Tmp=`$LocalPath+'.download';Invoke-WebRequest -UseBasicParsing -Uri `$Url -OutFile `$Tmp -TimeoutSec `$Timeout;Move-Item `$Tmp `$LocalPath -Force;return Get-Content `$LocalPath -Raw -Encoding UTF8}"
if(-not $Code.Contains($OldFetch)){throw 'WRITE_API_TEXT_PATCH_TARGET_MISSING'}
$Code=$Code.Replace($OldFetch,$NewFetch)
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
exit $LASTEXITCODE
