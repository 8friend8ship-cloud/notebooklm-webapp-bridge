param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.63'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Pinned1162='e57e061f3797e90a314483d12494845d3eb7fa32'
$ExpectedWatchdog='ac7127eeb33588dc84bef321909a938e8e7be455'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$Receipt=Join-Path $Root 'FLOW_WORKER_WATCHDOG_RECOVERY_1.1.63.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Api([string]$p){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$p+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'} -TimeoutSec 20}
function ReadJ([string]$p){if(Test-Path $p){try{return Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}}
function SaveJ([string]$p,$o){$d=Split-Path $p -Parent;if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null};$o|ConvertTo-Json -Depth 40|Set-Content $p -Encoding UTF8}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c){return $c}}};''}
$errors=@();$baseOk=$false;$watchdogOk=$false;$central=Central
try{
  $r=Api 'local-agent/releases/1.1.62/HomeDesignLocalAgent.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$Pinned1162){throw('BASE_1162_API_SHA:'+[string]$r.sha)}
  $tmp=Join-Path $Root 'HomeDesignLocalAgent-1.1.62-pinned.ps1';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$Pinned1162){throw'BASE_1162_LOCAL_SHA'}
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp;$rc=$LASTEXITCODE;$baseOk=($rc -eq 0);if(-not$baseOk){throw('BASE_1162_EXIT_'+$rc)}
}catch{$errors+=('BASE:'+ $_.Exception.Message)}
try{
  $r=Api 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$ExpectedWatchdog){throw('WATCHDOG_API_SHA:'+[string]$r.sha)}
  $dst=Join-Path $Root 'HomeDesignLocalWatchdog.ps1';$tmp=$dst+'.1163';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$ExpectedWatchdog){throw'WATCHDOG_LOCAL_SHA'};Move-Item $tmp $dst -Force;$watchdogOk=$true
}catch{$errors+=('WATCHDOG:'+ $_.Exception.Message)}
try{$s=ReadJ $State;if(-not$s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member watchdogVersion 'WATCHDOG_ONE_SHOT_AGENT_FIX_20260829' -Force;$s|Add-Member watchdogSha $ExpectedWatchdog -Force;$s|Add-Member status $(if($baseOk-and$watchdogOk){'FLOW_WORKER_WATCHDOG_RECOVERY_APPLIED'}else{'FLOW_WORKER_WATCHDOG_RECOVERY_FAILED'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJ $State $s}catch{$errors+=('STATE:'+ $_.Exception.Message)}
$ok=($baseOk-and$watchdogOk-and$errors.Count-eq0)
$rec=[ordered]@{ok=$ok;action='FLOW_WORKER_WATCHDOG_RECOVERY';agentVersion=$AgentVersion;baseAgent='1.1.62';baseAgentSha=$Pinned1162;watchdogSha=$ExpectedWatchdog;watchdogOneShotAgentGuardFixed=$watchdogOk;periodicCftRestartChurnPrevented=$watchdogOk;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;errors=$errors;at=(Get-Date).ToString('o')};SaveJ $Receipt $rec;if($central){SaveJ (Join-Path $central 'Runtime_Readback\FLOW_WORKER_WATCHDOG_RECOVERY_1.1.63.json') $rec};$rec|ConvertTo-Json -Depth 40 -Compress;if($ok){exit 0}else{exit 2}
