param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='RESUME_V10_RDC_SELF_HEAL_20260911'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$OriginalBlob='bc5fd70c2609f30fc8e9d46027665f1f6444066a'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='RESUME_TABLET_PRIMARY_HOLD_GUARD_LATEST.json'
$RepairReceipt='RDC_DATAPLANE_RECYCLE_V1_20260911.json'
$KeepAliveLocal=Join-Path $Root 'DesktopCommanderKeepAlive.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){try{$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function SaveRepair($o){try{$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content -LiteralPath (Join-Path $Root $RepairReceipt) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $RepairReceipt) -Encoding UTF8}}catch{}}
function StableViaRaw{$o=[ordered]@{ok=$false;enabled=$true;version='';notes='';sha='';transport='RAW';error=''};$tmp=Join-Path $Root 'stable_agent_raw.tmp';try{Invoke-WebRequest -UseBasicParsing -Uri ('https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/stable/agent.json?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Resume-V10'} -OutFile $tmp -TimeoutSec 10;$o.sha=(GitBlobSha1 $tmp).ToLowerInvariant();$j=Get-Content $tmp -Raw -Encoding UTF8|ConvertFrom-Json;$o.enabled=[bool]$j.enabled;$o.version=[string]$j.version;$o.notes=[string]$j.notes;$o.ok=$true}catch{$o.error=$_.Exception.Message}finally{Remove-Item $tmp -Force -ErrorAction SilentlyContinue};[pscustomobject]$o}
function StableViaApi{$o=[ordered]@{ok=$false;enabled=$true;version='';notes='';sha='';transport='API_FALLBACK';error=''};try{$u='https://api.github.com/repos/'+$Repo+'/contents/local-agent/stable/agent.json?ref=main';$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Resume-V10';'Accept'='application/vnd.github+json'} -TimeoutSec 10;$o.sha=[string]$x.sha;$j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$x.content-replace'\s','')))|ConvertFrom-Json;$o.enabled=[bool]$j.enabled;$o.version=[string]$j.version;$o.notes=[string]$j.notes;$o.ok=$true}catch{$o.error=$_.Exception.Message};[pscustomobject]$o}
function EnsureRdcRecoveryOnce{
  $stamp=Join-Path $Root $RepairReceipt
  if(Test-Path -LiteralPath $stamp){return}
  $r=[ordered]@{ok=$false;action='RDC_DATAPLANE_RECYCLE_ONCE';version=$Version;startedAt=(Get-Date).ToString('o');source='AUTORESUME_EXISTING_LANE';keepAliveFetched=$false;keepAliveSha='';keepAliveExit=$null;errors=@();newTrigger=$false;newOAuth=$false;broadNodeKill=$false;globalExecutionPolicyChanged=$false}
  try{
    $tmp=$KeepAliveLocal+'.download';$u='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/bootstrap/DesktopCommanderKeepAlive.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{'User-Agent'='HomeDesign-RdcRecovery-V1'} -OutFile $tmp -TimeoutSec 30;$r.keepAliveSha=(GitBlobSha1 $tmp).ToLowerInvariant();Move-Item -LiteralPath $tmp -Destination $KeepAliveLocal -Force;$r.keepAliveFetched=$true
    $raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $KeepAliveLocal 2>&1|Out-String;$r.keepAliveExit=$LASTEXITCODE;$r.keepAliveOutput=$raw.Trim();$r.ok=([int]$LASTEXITCODE-eq0)
  }catch{$r.errors+=$_.Exception.Message}
  $r.completedAt=(Get-Date).ToString('o');SaveRepair $r
}
EnsureRdcRecoveryOnce
$s=StableViaRaw;if(-not$s.ok){$s=StableViaApi}
$hold=[bool]($s.ok-and-not$s.enabled-and([string]$s.notes-match'TABLET_PRIMARY_(HOLD|BOOTSTRAP_KEEPALIVE)'))
if($hold){$r=[ordered]@{ok=$true;action='RESUME_TABLET_PRIMARY_HOLD_GUARD';version=$Version;stableMetaTransport=[string]$s.transport;stableContentSha=[string]$s.sha;stableVersion=[string]$s.version;stableEnabled=$false;stableNotes=[string]$s.notes;normalNotebooklmCoreRan=$false;imageHookRan=$false;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;hostTouched=$false;tabletLockTouched=$false;oauthChanged=$false;scopeChanged=$false;newTask=$false;newTrigger=$false;newDeployment=$false;at=(Get-Date).ToString('o')};Save $r;exit 0}
if(-not$s.ok){$r=[ordered]@{ok=$true;action='RESUME_STABLE_API_UNREACHABLE_FAIL_CLOSED';version=$Version;normalNotebooklmCoreRan=$false;imageHookRan=$false;normalChromeTouched=$false;error=[string]$s.error;at=(Get-Date).ToString('o')};Save $r;exit 0}
try{$u='https://api.github.com/repos/'+$Repo+'/git/blobs/'+$OriginalBlob;$b=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Resume-V10';'Accept'='application/vnd.github+json'} -TimeoutSec 20;$p=Join-Path $Root ('RESUME_ORIGINAL_'+$OriginalBlob+'.ps1');[IO.File]::WriteAllBytes($p,[Convert]::FromBase64String(([string]$b.content-replace'\s','')));if((GitBlobSha1 $p).ToLowerInvariant()-ne$OriginalBlob){throw 'ORIGINAL_RESUME_BLOB_MISMATCH'};& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $p;exit $LASTEXITCODE}catch{$r=[ordered]@{ok=$false;action='RESUME_V10_DELEGATE_ERROR';version=$Version;normalNotebooklmCoreRan=$false;error=$_.Exception.Message;at=(Get-Date).ToString('o')};Save $r;exit 3}
