param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$OriginalBlob='bc5fd70c2609f30fc8e9d46027665f1f6444066a'
$ExpectedBootstrapSha='728d39aa7e3d78457263e3a585a5e6945bd1362a'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Receipt='BOOTSTRAP_MAINTENANCE_RESUME_V1.json'
$Marker=Join-Path $Root 'BOOTSTRAP_MAINTENANCE_SENTINEL_147.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function Save($o){$j=$o|ConvertTo-Json -Depth 30;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function ApiContent([string]$Path){$headers=@{'User-Agent'='HomeDesign-Resume-Maintenance';'Accept'='application/vnd.github+json'};$url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30}
function RefreshBootstrap{
  $m=ApiContent 'local-agent/bootstrap/AgentBootstrap.ps1';if(([string]$m.sha).ToLowerInvariant()-ne$ExpectedBootstrapSha){throw('BOOTSTRAP_API_SHA_MISMATCH:'+([string]$m.sha))}
  $tmp=$Bootstrap+'.maintenance';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$m.content-replace'\s','')));$a=(GitBlobSha1 $tmp).ToLowerInvariant();if($a-ne$ExpectedBootstrapSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('BOOTSTRAP_LOCAL_SHA_MISMATCH:'+ $a)};Move-Item $tmp $Bootstrap -Force;return $a
}
function RestartBootstrapLoop{
  $loops=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{$_.Name -match '(?i)powershell|pwsh' -and [string]$_.CommandLine -match '(?i)AgentBootstrap\.ps1' -and [string]$_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})
  if($loops.Count-ne1){throw('AGENTBOOTSTRAP_LOOP_COUNT:'+ $loops.Count)}
  $old=[int]$loops[0].ProcessId;[ordered]@{done=$true;bootstrapSha=$ExpectedBootstrapSha;oldPid=$old;source='RESUME_MAINTENANCE_V1';at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $Marker -Encoding UTF8
  $helper=Join-Path $Root 'RESTART_AGENTBOOTSTRAP_LOOP_RESUME_V1.ps1';$ht=@'
param([int]$OldPid,[string]$Bootstrap,[string]$Root)
$ErrorActionPreference='SilentlyContinue'
Start-Sleep -Seconds 3
try{$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$OldPid);if($p -and [string]$p.CommandLine -match '(?i)AgentBootstrap\.ps1' -and [string]$p.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'){Stop-Process -Id $OldPid -Force -ErrorAction SilentlyContinue}}catch{}
Start-Sleep -Seconds 2
try{Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$Bootstrap+'"'),'-Loop') -WindowStyle Hidden|Out-Null}catch{}
try{[ordered]@{ok=$true;action='AGENTBOOTSTRAP_LOOP_RESTART_FROM_RESUME';oldPid=$OldPid;bootstrap=$Bootstrap;at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Root 'BOOTSTRAP_LOOP_RESTART_FROM_RESUME.json') -Encoding UTF8}catch{}
'@;Set-Content -LiteralPath $helper -Value $ht -Encoding UTF8;Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$helper+'"'),'-OldPid',[string]$old,'-Bootstrap',('"'+$Bootstrap+'"'),'-Root',('"'+$Root+'"')) -WindowStyle Hidden|Out-Null;return $old
}
$stable=$null;try{$stable=ApiContent 'local-agent/stable/agent.json';$stable=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$stable.content-replace'\s',''))))|ConvertFrom-Json}catch{}
if($stable -and [string]$stable.notes -match 'BOOTSTRAP_MAINTENANCE_ONLY_V1'){
  $r=[ordered]@{ok=$false;action='BOOTSTRAP_MAINTENANCE_RESUME_ONLY';normalNotebooklmCoreRan=$false;bootstrapSha='';oldBootstrapPid=0;helperStarted=$false;normalChromeTouched=$false;hostTouched=$false;tabletLockTouched=$false;oauthChanged=$false;newTask=$false;newTrigger=$false;newDeployment=$false;startedAt=(Get-Date).ToString('o');completedAt='';error=''}
  try{$r.bootstrapSha=RefreshBootstrap;$r.oldBootstrapPid=RestartBootstrapLoop;$r.helperStarted=$true;$r.ok=$true}catch{$r.error=$_.Exception.Message}
  $r.completedAt=(Get-Date).ToString('o');Save $r;if($r.ok){exit 0}else{exit 2}
}
# No maintenance flag: delegate byte-for-byte to the last verified normal Resume blob.
try{$headers=@{'User-Agent'='HomeDesign-Resume-Verified-Delegate';'Accept'='application/vnd.github+json'};$b=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/git/blobs/'+$OriginalBlob) -Headers $headers -Method Get -TimeoutSec 30;$p=Join-Path $Root ('RESUME_ORIGINAL_'+$OriginalBlob+'.ps1');[IO.File]::WriteAllBytes($p,[Convert]::FromBase64String(([string]$b.content-replace'\s','')));if((GitBlobSha1 $p).ToLowerInvariant()-ne$OriginalBlob){throw 'ORIGINAL_RESUME_BLOB_MISMATCH'};& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $p;exit $LASTEXITCODE}catch{exit 3}
