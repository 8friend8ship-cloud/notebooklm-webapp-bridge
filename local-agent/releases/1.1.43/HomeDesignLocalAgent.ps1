param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$State=Join-Path $Root 'state.json'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Probe=Join-Path $Root 'Run-ExactTargetNotebookLMRegressionV2-1.1.43.ps1'
$Marker=Join-Path $Root 'exact-target-v2-1.1.43-dispatch.json'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$HostUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.2.9/HomeDesignLocalCommandHost.ps1'
$HostSha='2b58e72d35fb8b8e56b179fc89dbc7ba7ac3a577'
$BootstrapUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/bootstrap/AgentBootstrap.ps1'
$BootstrapSha='93bbbcfbb1e3afc718c6c39d009036dc1c964b78'
$ProbeUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/Run-ExactTargetNotebookLMRegressionV2.ps1'
$ProbeSha='1b7f543850c42b6d4f36641c73b5c9021ccd3384'

function GitBlob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Fetch([string]$u,[string]$d,[string]$sha){$t=$d+'.download';Invoke-WebRequest -UseBasicParsing -Uri ($u+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $t -TimeoutSec 20;$a=(GitBlob $t).ToLowerInvariant();if($a -ne $sha.ToLowerInvariant()){Remove-Item $t -Force -ErrorAction SilentlyContinue;throw ('SHA_MISMATCH:'+ $a+':'+$sha)};Move-Item $t $d -Force;return $a}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function StopHost{try{foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine) -match 'HomeDesignLocalCommandHost'})){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}}catch{};Start-Sleep -Milliseconds 1000}
function StartHost{$args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$HostFile+'"'));Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden|Out-Null;$deadline=(Get-Date).AddSeconds(35);do{Start-Sleep -Milliseconds 500;$h=HostHealth;if($h -and [bool]$h.ok -and [string]$h.version -eq '1.2.9' -and [bool]$h.asyncJobs){return $h}}while((Get-Date)-lt $deadline);throw 'HOST_1.2.9_START_FAILED'}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('내 드라이브\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c -PathType Container){return $c}}};return ''}
function SaveJson([string]$p,$o){$par=Split-Path -Parent $p;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};$o|ConvertTo-Json -Depth 80|Set-Content -LiteralPath $p -Encoding UTF8}

# Give the queue Host task time to finish persisting its result before replacing Host1.2.7.
Start-Sleep -Seconds 5
$c=Central
$resultPath='';if($c){$resultPath=Join-Path $c 'Runtime_Readback\Chrome_Exact_Target\NOTEBOOKLM_EXACT_TARGET_X2_REGRESSION_V2.json'}
$before=HostHealth;$hostAfter=$null;$hostSha='';$bootstrapSha='';$probeSha='';$dispatch='';$pid=$null;$err='';$existing=$null
try{$hostSha=Fetch $HostUrl $HostFile $HostSha;StopHost;$hostAfter=StartHost}catch{$err+='HOST:'+($_.Exception.Message)+';'}
try{$bootstrapSha=Fetch $BootstrapUrl $Bootstrap $BootstrapSha}catch{$err+='BOOTSTRAP:'+($_.Exception.Message)+';'}
try{$probeSha=Fetch $ProbeUrl $Probe $ProbeSha}catch{$err+='PROBE:'+($_.Exception.Message)+';'}
if($resultPath -and (Test-Path $resultPath)){
  try{$existing=Get-Content $resultPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  $dispatch=if($existing -and $existing.ok){'RUNTIME_X2_V2_PASS'}else{'RUNTIME_X2_V2_RESULT_PRESENT_FAILED'}
}elseif(Test-Path $Marker){
  $m=$null;try{$m=Get-Content $Marker -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  $alive=$false;if($m -and $m.pid){try{$alive=[bool](Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue)}catch{}}
  $dispatch=if($alive){'DISPATCH_V2_ALREADY_RUNNING'}else{'DISPATCH_V2_MARKER_PRESENT_NO_RESULT_HOLD'}
}elseif($hostAfter -and [string]$hostAfter.version -eq '1.2.9' -and [bool]$hostAfter.asyncJobs -and $probeSha -eq $ProbeSha){
  try{$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Probe+'"';$p=[Diagnostics.Process]::Start($psi);$pid=[int]$p.Id;SaveJson $Marker ([ordered]@{version='1.1.43';pid=$pid;hostVersion='1.2.9';probeSha=$ProbeSha;startedAt=(Get-Date).ToString('o');expectedResult=$resultPath;retryPolicy='NO_BLIND_RETRY'});$dispatch='DISPATCHED_V2_BACKGROUND'}catch{$err+='DISPATCH:'+($_.Exception.Message)+';';$dispatch='DISPATCH_V2_FAILED'}
}else{$dispatch='HOST_OR_PROBE_V2_GATE_FAILED'}
$hostOk=[bool]($hostAfter -and [bool]$hostAfter.ok -and [string]$hostAfter.version -eq '1.2.9' -and [bool]$hostAfter.asyncJobs)
$bootstrapOk=[bool]($bootstrapSha -eq $BootstrapSha)
$probeOk=[bool]($probeSha -eq $ProbeSha)
$ok=[bool]($hostOk -and $bootstrapOk -and $probeOk -and $dispatch -in @('DISPATCHED_V2_BACKGROUND','DISPATCH_V2_ALREADY_RUNNING','RUNTIME_X2_V2_PASS'))
$status=if($dispatch -eq 'RUNTIME_X2_V2_PASS'){'SELF_HEAL_PASS'}elseif($ok){'HOST129_PASS_EXACT_TARGET_V2_PENDING'}else{'HOST129_OR_EXACT_TARGET_V2_FAILED'}
$receipt=[ordered]@{ok=$ok;action='AGENT_1.1.43_HOST129_AND_EXACT_TARGET_V2_DISPATCH';agentVersion='1.1.43';hostBefore=$before;hostAfter=$hostAfter;hostSha=$hostSha;bootstrapPatched=$bootstrapOk;bootstrapSha=$bootstrapSha;probeSha=$probeSha;dispatchState=$dispatch;pid=$pid;resultPath=$resultPath;existingResult=$existing;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;normalChromeRestarted=$false;retryPolicy='NO_BLIND_RETRY';error=$err;at=(Get-Date).ToString('o')}
if($c){SaveJson (Join-Path $c 'Runtime_Readback\AGENT_1.1.43_HOST129_AND_EXACT_TARGET_V2_DISPATCH.json') $receipt}
try{$s=$null;if(Test-Path $State){$s=Get-Content $State -Raw -Encoding UTF8|ConvertFrom-Json};if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion '1.1.43' -Force;$s|Add-Member commandHostVersion $(if($hostAfter){[string]$hostAfter.version}else{''}) -Force;$s|Add-Member hostHealthy $hostOk -Force;$s|Add-Member hostAsyncJobs $(if($hostAfter){[bool]$hostAfter.asyncJobs}else{$false}) -Force;$s|Add-Member agentMode 'HOST129_EXACT_TARGET_V2_DISPATCH_1.1.43' -Force;$s|Add-Member ok $ok -Force;$s|Add-Member status $status -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $State $s}catch{}
$receipt|ConvertTo-Json -Depth 80 -Compress
if($ok){exit 0}else{exit 2}
