param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.64'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Pinned1163='f316587dffeb482d0fc8c6567f611790eba1aa77'
$ExpectedBootstrap='8324f18260c34d9ceb5639ad081547b322256dcc'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Receipt=Join-Path $Root 'FLOW_BOOTSTRAP_CHURN_FIX_1.1.64.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Api([string]$p){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$p+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'} -TimeoutSec 20}
function ReadJ([string]$p){if(Test-Path $p){try{return Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}}
function SaveJ([string]$p,$o){$d=Split-Path $p -Parent;if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null};$o|ConvertTo-Json -Depth 40|Set-Content $p -Encoding UTF8}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c){return $c}}};''}
$errors=@();$baseOk=$false;$bootstrapOk=$false;$replacementScheduled=$false;$central=Central
try{
  $r=Api 'local-agent/releases/1.1.63/HomeDesignLocalAgent.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$Pinned1163){throw('BASE_1163_API_SHA:'+[string]$r.sha)}
  $tmp=Join-Path $Root 'HomeDesignLocalAgent-1.1.63-pinned.ps1';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$Pinned1163){throw'BASE_1163_LOCAL_SHA'}
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp;$rc=$LASTEXITCODE;$baseOk=($rc -eq 0);if(-not$baseOk){throw('BASE_1163_EXIT_'+$rc)}
}catch{$errors+=('BASE:'+ $_.Exception.Message)}
try{
  $r=Api 'local-agent/bootstrap/AgentBootstrap.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$ExpectedBootstrap){throw('BOOTSTRAP_API_SHA:'+[string]$r.sha)}
  $tmp=$Bootstrap+'.1164';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$ExpectedBootstrap){throw'BOOTSTRAP_LOCAL_SHA'};Move-Item $tmp $Bootstrap -Force;$bootstrapOk=$true
}catch{$errors+=('BOOTSTRAP:'+ $_.Exception.Message)}
try{
  $helper=Join-Path $Root 'ReplaceBootstrapLoop-1.1.64.ps1'
  @'
Start-Sleep -Seconds 6
try{
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)' })){
    try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}
  }
}catch{}
Start-Sleep -Seconds 2
$bootstrap=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent\AgentBootstrap.ps1'
if(Test-Path -LiteralPath $bootstrap){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$bootstrap`"",'-Loop') -WindowStyle Hidden|Out-Null}
'@ | Set-Content -LiteralPath $helper -Encoding ASCII
  Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$helper`"") -WindowStyle Hidden|Out-Null
  $replacementScheduled=$true
}catch{$errors+=('LOOP_REPLACE:'+ $_.Exception.Message)}
try{$s=ReadJ $State;if(-not$s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member bootstrapVersion 'BOOTSTRAP_SKIP_UNCHANGED_AGENT_V1_20260829' -Force;$s|Add-Member bootstrapSha $ExpectedBootstrap -Force;$s|Add-Member status $(if($baseOk-and$bootstrapOk-and$replacementScheduled){'FLOW_BOOTSTRAP_CHURN_FIX_APPLIED'}else{'FLOW_BOOTSTRAP_CHURN_FIX_FAILED'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJ $State $s}catch{$errors+=('STATE:'+ $_.Exception.Message)}
$ok=($baseOk-and$bootstrapOk-and$replacementScheduled-and$errors.Count-eq0)
$rec=[ordered]@{ok=$ok;action='FLOW_BOOTSTRAP_CHURN_FIX';agentVersion=$AgentVersion;baseAgent='1.1.63';baseAgentSha=$Pinned1163;bootstrapSha=$ExpectedBootstrap;bootstrapSkipsUnchangedStable=$bootstrapOk;bootstrapLoopReplacementScheduled=$replacementScheduled;periodicCftRestartChurnPrevented=$bootstrapOk;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;errors=$errors;at=(Get-Date).ToString('o')};SaveJ $Receipt $rec;if($central){SaveJ (Join-Path $central 'Runtime_Readback\FLOW_BOOTSTRAP_CHURN_FIX_1.1.64.json') $rec};$rec|ConvertTo-Json -Depth 40 -Compress;if($ok){exit 0}else{exit 2}
