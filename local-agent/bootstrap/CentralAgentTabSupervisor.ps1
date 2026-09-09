param([switch]$SelfTestRecovery)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_AGENT_TAB_SUPERVISOR_V2_POWER_REMOTE_ROLE_ROUTE_20260909'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Cleanup=Join-Path $Root 'RunOwnedUiCleanup.ps1'
$Recovery=Join-Path $Root 'CentralTabAutoRecovery.ps1'
$PowerGuard=Join-Path $Root 'CentralAgentPowerContinuityGuard.ps1'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$Receipt=Join-Path $Root 'CENTRAL_TAB_SUPERVISOR_LAST.json'
$RecoveryReceipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
function Test-Host{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Test-Cdp{try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;return [bool]$v.Browser}catch{return $false}}
function Test-Remote{
 try{$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)desktop-commander'-and[string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'});if($p.Count-eq0){return $false};$ids=@($p.ProcessId);return (@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count-gt0)}catch{return $false}
}
function Find-Central{
 $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
 foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''
}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Refresh-Verified([string]$RepoPath,[string]$Dest){
 try{$u='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Central-Supervisor';'Accept'='application/vnd.github+json'} -TimeoutSec 15;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$sha=(GitBlob $b).ToLowerInvariant();if($sha-ne([string]$x.sha).ToLowerInvariant()){throw'SHA_MISMATCH'};$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,$b);Move-Item $tmp $Dest -Force;return $sha}catch{return ''}
}
function PowerGuard-Processes{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)CentralAgentPowerContinuityGuard\.ps1'})}catch{return @()}}
function Ensure-PowerGuard{
 $o=[ordered]@{sha='';before=0;started=$false;after=0;ok=$false;error=''}
 try{$o.before=[int](PowerGuard-Processes).Count;$o.sha=Refresh-Verified 'local-agent/bootstrap/CentralAgentPowerContinuityGuard.ps1' $PowerGuard;if(-not$o.sha){throw'POWER_GUARD_REFRESH_FAILED'};if((PowerGuard-Processes).Count-eq0){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$PowerGuard) -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 2;$o.started=$true};$o.after=[int](PowerGuard-Processes).Count;$o.ok=($o.after-gt0)}catch{$o.error=$_.Exception.Message};return [pscustomobject]$o
}
$started=(Get-Date).ToString('o')
$issues=New-Object System.Collections.Generic.List[string]
$powerGuard=Ensure-PowerGuard
if(-not$powerGuard.ok){$issues.Add('POWER_CONTINUITY_GUARD_DOWN')}
$cleanupObj=$null;$cleanupExit=9;$cleanupRaw=''
if(Test-Path $Cleanup){
 try{$cleanupRaw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Cleanup 2>&1|Out-String;$cleanupExit=$LASTEXITCODE;$cleanupObj=$cleanupRaw|ConvertFrom-Json}catch{$issues.Add('CLEANUP_PARSE_OR_EXEC_ERROR')}
}else{$issues.Add('CLEANUP_MISSING')}
if(-not$cleanupObj){$issues.Add('CLEANUP_NO_READBACK')}
elseif(-not[bool]$cleanupObj.ok){$issues.Add('CLEANUP_NOT_OK')}
elseif([string]$cleanupObj.version-notmatch'RUN_OWNED_UI_CLEANUP_V[45]_'){ $issues.Add('CLEANUP_VERSION_MISMATCH') }
$registryCount=0;$registryOk=$true
try{$r=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;$registryCount=@($r).Count}catch{$registryOk=$false;$issues.Add('REGISTRY_PARSE_FAIL')}
$registryPruned=0;$registryCountAfter=$registryCount
$pruneIds=@()
if($registryOk-and$cleanupObj-and$cleanupObj.results){foreach($rr in @($cleanupObj.results)){if([string]$rr.state-match '^(ALREADY_NOT_VISIBLE|CLOSED_EXACT_HWND|HWND_REUSED_OWNER_MISMATCH|ALREADY_CLOSED|CLOSED)$' -and [string]$rr.runId){$pruneIds+=[string]$rr.runId}};$pruneIds=@($pruneIds|Sort-Object -Unique)}
if($registryOk-and$pruneIds.Count-gt0){try{$kept=@($r|Where-Object{$pruneIds-notcontains[string]$_.runId});if($kept.Count-lt$registryCount){$tmp=$Registry+'.compact';ConvertTo-Json -InputObject ([object[]]$kept) -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item $tmp $Registry -Force;$registryPruned=$registryCount-$kept.Count;$registryCountAfter=$kept.Count}}catch{$issues.Add('REGISTRY_COMPACT_FAIL')}}
$hostOk=Test-Host;$cdpOk=Test-Cdp;$remoteOk=Test-Remote
if(-not$hostOk){$issues.Add('LOCAL_HOST_DOWN')}
if(-not$cdpOk){$issues.Add('CFT_CDP_9224_DOWN')}
if(-not$remoteOk){$issues.Add('REMOTE_DC_OFFLINE')}
$authDupRemain=$false
if($cleanupObj -and $cleanupObj.authActions){foreach($a in @($cleanupObj.authActions)){if([int]$a.found-gt1-and[int]$a.closed-eq0-and[string]$a.action-notmatch'PROTECT_WAITING_USER'){$authDupRemain=$true}}}
if($authDupRemain){$issues.Add('AUTH_DUPLICATE_REMAINS')}
if($SelfTestRecovery){$issues.Add('SELF_TEST_RECOVERY_TRIGGER')}
$recoveryTriggered=$false;$recoveryCooldown=$false;$recoveryExit=$null
if($issues.Count-gt0-and(Test-Path $Recovery)){
 $recent=$false
 try{if(Test-Path $RecoveryReceipt){$recent=(((Get-Date)-(Get-Item $RecoveryReceipt).LastWriteTime).TotalSeconds-lt120)}}catch{}
 if($recent-and-not$SelfTestRecovery){$recoveryCooldown=$true}else{
  try{$reason=($issues -join ',');& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Recovery -Reason $reason|Out-Null;$recoveryExit=$LASTEXITCODE;$recoveryTriggered=$true}catch{$recoveryExit=9}
 }
}
$hostAfter=Test-Host;$cdpAfter=Test-Cdp;$remoteAfter=Test-Remote
$out=[ordered]@{
 ok=[bool]($issues.Count-eq0-or($powerGuard.ok-and$hostAfter-and$cdpAfter-and$remoteAfter-and-not$authDupRemain))
 version=$Version;startedAt=$started;completedAt=(Get-Date).ToString('o');phase='POWER_GUARD+MID_CLEAN_VERIFY_RECOVER'
 powerGuardOk=[bool]$powerGuard.ok;powerGuardSha=[string]$powerGuard.sha;powerGuardStarted=[bool]$powerGuard.started;powerGuardProcessAfter=[int]$powerGuard.after;powerGuardError=[string]$powerGuard.error
 cleanupExit=$cleanupExit;cleanupVersion=$(if($cleanupObj){[string]$cleanupObj.version}else{''});cleanupClosed=$(if($cleanupObj){[int]$cleanupObj.closedCount}else{-1})
 registryOk=$registryOk;registryCount=$registryCount;registryPruned=$registryPruned;registryCountAfter=$registryCountAfter
 hostOk=$hostAfter;cdp9224Ok=$cdpAfter;remoteDcOk=$remoteAfter;authDuplicateRemains=$authDupRemain;issues=@($issues)
 recoveryTriggered=$recoveryTriggered;recoveryExit=$recoveryExit;recoveryCooldown=$recoveryCooldown
 policy='AC_REMOTE_PRESENT=>ES_SYSTEM_REQUIRED_ONLY;DISPLAY_CAN_OFF;NO_POWERCFG_CHANGE;5M_CENTRAL_ROLE_ROUTE;WAITING_USER_KEEP;USER_CHROME_KEEP;REMOTE_EXACT_REPAIR'
 googleControlPlane='DRIVE_RUNTIME_READBACK_EXISTING_AUTH';windowsExecutionIdentity='EXISTING_USER_TASK;NO_GOOGLE_PERMISSION_BYPASS'
}
$json=$out|ConvertTo-Json -Depth 30
$json|Set-Content -LiteralPath $Receipt -Encoding UTF8
try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'CENTRAL_TAB_SUPERVISOR_LAST.json') -Encoding UTF8}}catch{}
$out|ConvertTo-Json -Depth 30 -Compress
if($out.ok){exit 0}else{exit 4}
