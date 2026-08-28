param()
$ErrorActionPreference='Continue';$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent';New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1';$Probe=Join-Path $Root 'Run-ExactTargetNotebookLMRegression-1.1.40.ps1';$State=Join-Path $Root 'state.json';$Marker=Join-Path $Root 'exact-target-1.1.40-dispatch.json'
$BootstrapUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/bootstrap/AgentBootstrap.ps1';$BootstrapSha='93bbbcfbb1e3afc718c6c39d009036dc1c964b78'
$ProbeUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/Run-ExactTargetNotebookLMRegression.ps1';$ProbeSha='ebab97b3f5cf39d829ee162e644179c30e2f6ba2'
function GitBlob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Fetch([string]$u,[string]$d,[string]$sha){$t=$d+'.download';Invoke-WebRequest -UseBasicParsing -Uri ($u+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $t -TimeoutSec 30;$a=(GitBlob $t).ToLowerInvariant();if($a -ne $sha.ToLowerInvariant()){Remove-Item $t -Force -ErrorAction SilentlyContinue;throw ('SHA_MISMATCH:'+ $a+':'+$sha)};Move-Item $t $d -Force;return $a}
function Central{ $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('내 드라이브\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c -PathType Container){return $c}}};return ''}
function SaveJson([string]$p,$o){$parent=Split-Path -Parent $p;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$o|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $p -Encoding UTF8}
$c=Central;$resultPath='';if($c){$resultPath=Join-Path $c 'Runtime_Readback\Chrome_Exact_Target\NOTEBOOKLM_EXACT_TARGET_X2_REGRESSION.json'}
$bootstrapSha='';$probeSha='';$dispatchState='';$pid=$null;$err='';$existingResult=$null
try{$bootstrapSha=Fetch $BootstrapUrl $Bootstrap $BootstrapSha}catch{$err+='BOOTSTRAP:'+($_.Exception.Message)+';'}
try{$probeSha=Fetch $ProbeUrl $Probe $ProbeSha}catch{$err+='PROBE:'+($_.Exception.Message)+';'}
if($resultPath -and (Test-Path -LiteralPath $resultPath)){
  try{$existingResult=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  $dispatchState=if($existingResult -and $existingResult.ok){'RUNTIME_X2_PASS'}else{'RUNTIME_X2_RESULT_PRESENT_FAILED'}
}elseif(Test-Path -LiteralPath $Marker){
  $m=$null;try{$m=Get-Content $Marker -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  $alive=$false;if($m -and $m.pid){try{$alive=[bool](Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue)}catch{}}
  $dispatchState=if($alive){'DISPATCH_ALREADY_RUNNING'}else{'DISPATCH_MARKER_PRESENT_NO_RESULT_HOLD'}
}else{
  try{
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.CreateNoWindow=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Probe+'"'
    $p=[Diagnostics.Process]::Start($psi);$pid=[int]$p.Id
    $mark=[ordered]@{version='1.1.40';pid=$pid;probeSha=$ProbeSha;bootstrapSha=$BootstrapSha;startedAt=(Get-Date).ToString('o');expectedResult=$resultPath;retryPolicy='NO_BLIND_RETRY';status='DISPATCHED'};SaveJson $Marker $mark
    $dispatchState='DISPATCHED_BACKGROUND'
  }catch{$err+='DISPATCH:'+($_.Exception.Message)+';';$dispatchState='DISPATCH_FAILED'}
}
$ok=[bool]($bootstrapSha -eq $BootstrapSha -and $probeSha -eq $ProbeSha -and $dispatchState -in @('DISPATCHED_BACKGROUND','DISPATCH_ALREADY_RUNNING','RUNTIME_X2_PASS'))
$status=if($dispatchState -eq 'RUNTIME_X2_PASS'){'SELF_HEAL_PASS'}elseif($ok){'EXACT_TARGET_BACKGROUND_PENDING'}else{$dispatchState}
$receipt=[ordered]@{ok=$ok;action='AGENT_1.1.40_EXACT_TARGET_BACKGROUND_DISPATCH';agentVersion='1.1.40';bootstrapPatched=($bootstrapSha -eq $BootstrapSha);bootstrapSha=$bootstrapSha;probeSha=$probeSha;dispatchState=$dispatchState;pid=$pid;resultPath=$resultPath;existingResult=$existingResult;normalChromeUntouchedByDispatcher=$true;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;chromeSettingsChanged=$false;retryPolicy='NO_BLIND_RETRY';error=$err;at=(Get-Date).ToString('o')}
if($c){SaveJson (Join-Path $c 'Runtime_Readback\AGENT_1.1.40_EXACT_TARGET_BACKGROUND_DISPATCH.json') $receipt}
try{$s=$null;if(Test-Path $State){$s=Get-Content $State -Raw -Encoding UTF8|ConvertFrom-Json};if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion '1.1.40' -Force;$s|Add-Member agentMode 'EXACT_TARGET_BACKGROUND_DISPATCH_1.1.40' -Force;$s|Add-Member ok $ok -Force;$s|Add-Member status $status -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $State $s}catch{}
$receipt|ConvertTo-Json -Depth 60 -Compress
if($ok){exit 0}else{exit 2}
