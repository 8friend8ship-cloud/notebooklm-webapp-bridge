param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.13'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.12-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.13-patched.ps1'
$SourceCommit='6768cda0c7813c0f003cb84b2b820120761a6703'
$Url="https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$SourceCommit/local-agent/releases/1.1.12/HomeDesignLocalAgent.ps1"
$Sep=if($Url.Contains('?')){'&'}else{'?'}
$Url=$Url+$Sep+'hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Source -TimeoutSec 60
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
if(-not $Code.Contains("`$AgentVersion='1.1.12'")){throw 'Agent 1.1.12 version marker missing'}
if(-not $Code.Contains('function KillTree([int]$Pid)')){throw 'Agent 1.1.12 PID patch target missing'}
if(-not $Code.Contains('$Video=RunVideoJob $Central')){throw 'Agent 1.1.12 video job patch target missing'}
$Code=$Code.Replace("`$AgentVersion='1.1.12'","`$AgentVersion='1.1.13'")
$Code=$Code.Replace('function KillTree([int]$Pid)','function KillTree([int]$ProcessId)')
$Code=$Code.Replace('& taskkill.exe /PID $Pid /T /F','& taskkill.exe /PID $ProcessId /T /F')
$Code=$Code.Replace('Stop-Process -Id $Pid -Force','Stop-Process -Id $ProcessId -Force')
$Code=$Code.Replace('$Video=RunVideoJob $Central',"`$Video=[ordered]@{status='DEFERRED_SEPARATE_WORKFLOW';ok=`$true;attempts=0;jobId=''}")
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
$Rc=$LASTEXITCODE
if($Rc -ne 0){throw "Patched Local Agent 1.1.13 failed exit=$Rc"}
