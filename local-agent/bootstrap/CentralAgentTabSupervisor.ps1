param([switch]$SelfTestRecovery)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_AGENT_TAB_SUPERVISOR_V13_INACTIVE_5M_ENDTASK_20260909'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$CleanupScript=Join-Path $Root 'RunOwnedUiCleanup.ps1'
$RecoveryScript=Join-Path $Root 'CentralTabAutoRecovery.ps1'
$PowerGuardScript=Join-Path $Root 'CentralAgentPowerContinuityGuard.ps1'
$PowerGuardReceipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$WindowActivityScript=Join-Path $Root 'WindowActivitySupervisor.ps1'
$InactiveGovernorScript=Join-Path $Root 'InactiveProcessGovernor.ps1'
$Receipt=Join-Path $Root 'CENTRAL_TAB_SUPERVISOR_LAST.json'
$RecoveryReceipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
$RequiredPowerGuardVersion='POWER_CONTINUITY_GUARD_V5_REMOTE_SYSTEM_AWAKE_SCREEN_OFF_20260909'
$Pins=@{
 'local-agent/bootstrap/CentralAgentPowerContinuityGuard.ps1'=@{commit='6e0ed663fd7d4c1e3ff3fc13bc8de94e58211e39';sha='a3239c04c9e7190f405afddcf6556b9228402710'}
 'local-agent/bootstrap/WindowActivitySupervisor.ps1'=@{commit='22aef32e7a24bcbc1fc3145afc1cbf5e5ad99e05';sha='407b1134d1d574bfdc3e44baaa0650eb29349765'}
 'local-agent/bootstrap/InactiveProcessGovernor.ps1'=@{commit='aa5254ed07e0cb8cefabf44690b5d38b11c676c8';sha='6b9a5f159cde6ae12b2ebc8c36280ec572604574'}
}
function Test-LocalHost{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Test-Cdp{try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;return [bool]$v.Browser}catch{return $false}}
function Test-Remote{try{$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)desktop-commander'-and[string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'});if($p.Count-eq0){return $false};$ids=@($p.ProcessId);return (@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count-gt0)}catch{return $false}}
function Find-Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return''}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Install-Verified([byte[]]$Bytes,[string]$Expected,[string]$Dest){$sha=(GitBlob $Bytes).ToLowerInvariant();if($sha-ne$Expected.ToLowerInvariant()){throw'SHA_MISMATCH'};$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,$Bytes);Move-Item $tmp $Dest -Force;return $sha}
function Refresh-Verified([string]$RepoPath,[string]$Dest){$pin=$Pins[$RepoPath];try{$u='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Supervisor-V13';'Accept'='application/vnd.github+json'} -TimeoutSec 8;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));return (Install-Verified $b ([string]$x.sha) $Dest)}catch{};if($pin){try{$u='https://raw.githubusercontent.com/'+$Repo+'/'+[string]$pin.commit+'/'+$RepoPath;$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Supervisor-V13';$b=$wc.DownloadData($u)}finally{$wc.Dispose()};return (Install-Verified $b ([string]$pin.sha) $Dest)}catch{};try{if(Test-Path $Dest){$b=[IO.File]::ReadAllBytes($Dest);$sha=(GitBlob $b).ToLowerInvariant();if($sha-eq([string]$pin.sha).ToLowerInvariant()){return $sha}}}catch{}};return''}
function Read-PowerReceipt{try{if(Test-Path $PowerGuardReceipt){return (Get-Content $PowerGuardReceipt -Raw -Encoding UTF8|ConvertFrom-Json)}}catch{};return $null}
function Get-PowerGuardProcs{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)CentralAgentPowerContinuityGuard\.ps1'})}
function Ensure-PowerGuard{
 $o=[ordered]@{sha='';ok=$false;after=0;receiptVersion='';systemRequiredHeld=$false;displayRequiredHeld=$false;remoteLeaseActive=$false;restarted=$false;error=''}
 try{
  $o.sha=Refresh-Verified 'local-agent/bootstrap/CentralAgentPowerContinuityGuard.ps1' $PowerGuardScript
  if(-not$o.sha){throw'POWER_GUARD_REFRESH_FAILED'}
  $rr=Read-PowerReceipt;$procs=@(Get-PowerGuardProcs)
  $mustRestart=[bool]($procs.Count-eq0-or-not$rr-or[string]$rr.version-ne$RequiredPowerGuardVersion)
  if($mustRestart){
   foreach($p in $procs){try{Stop-Process -Id ([int]$p.ProcessId) -Force}catch{}}
   Start-Sleep -Milliseconds 500
   Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$PowerGuardScript) -WindowStyle Hidden|Out-Null
   Start-Sleep -Seconds 3
   $o.restarted=$true
  }
  $procs=@(Get-PowerGuardProcs);$rr=Read-PowerReceipt;$o.after=$procs.Count
  if($rr){
   $o.receiptVersion=[string]$rr.version
   $o.systemRequiredHeld=[bool]$rr.systemRequiredHeld
   $o.displayRequiredHeld=[bool]$rr.displayRequiredHeld
   $o.remoteLeaseActive=[bool]($rr.remoteLeaseActive-or$rr.remoteProcessPresent)
   $need=[bool]$o.remoteLeaseActive
   $o.ok=[bool]($procs.Count-gt0-and$o.receiptVersion-eq$RequiredPowerGuardVersion-and((-not$need)-or($o.systemRequiredHeld-and-not$o.displayRequiredHeld)))
  }
 }catch{$o.error=$_.Exception.Message}
 return [pscustomobject]$o
}
function Run-Json([string]$Path){$o=[ordered]@{exit=9;obj=$null;raw='';error=''};try{$o.raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path 2>&1|Out-String;$o.exit=$LASTEXITCODE;try{$o.obj=$o.raw|ConvertFrom-Json}catch{$lines=@($o.raw-split"`r?`n"|Where-Object{$_.Trim().StartsWith('{')});if($lines.Count){$o.obj=$lines[-1]|ConvertFrom-Json}else{throw}}}catch{$o.error=$_.Exception.Message};return [pscustomobject]$o}
$started=(Get-Date).ToString('o');$issues=New-Object System.Collections.Generic.List[string]
$pg=Ensure-PowerGuard;if(-not$pg.ok){$issues.Add('POWER_CONTINUITY_GUARD_DOWN')}
$waSha=Refresh-Verified 'local-agent/bootstrap/WindowActivitySupervisor.ps1' $WindowActivityScript;$wa=$null;if(-not$waSha){$issues.Add('WINDOW_ACTIVITY_REFRESH_FAILED')}else{$wa=Run-Json $WindowActivityScript;if(-not$wa.obj){$issues.Add('WINDOW_ACTIVITY_NO_READBACK')}elseif([string]$wa.obj.version-notmatch'^WINDOW_ACTIVITY_SUPERVISOR_V5_'){$issues.Add('WINDOW_ACTIVITY_VERSION_MISMATCH')}elseif(-not[bool]$wa.obj.ok){$issues.Add('WINDOW_ACTIVITY_NOT_OK')}}
$igSha=Refresh-Verified 'local-agent/bootstrap/InactiveProcessGovernor.ps1' $InactiveGovernorScript;$ig=$null;if(-not$igSha){$issues.Add('INACTIVE_GOVERNOR_REFRESH_FAILED')}else{$ig=Run-Json $InactiveGovernorScript;if(-not$ig.obj){$issues.Add('INACTIVE_GOVERNOR_NO_READBACK')}elseif([string]$ig.obj.version-notmatch'^INACTIVE_PROCESS_GOVERNOR_V1_'){$issues.Add('INACTIVE_GOVERNOR_VERSION_MISMATCH')}elseif(-not[bool]$ig.obj.ok){$issues.Add('INACTIVE_GOVERNOR_NOT_OK')}}
$cl=$null;if(Test-Path $CleanupScript){$cl=Run-Json $CleanupScript;if(-not$cl.obj-or-not[bool]$cl.obj.ok){$issues.Add('CLEANUP_NOT_OK')}}else{$issues.Add('CLEANUP_MISSING')}
$hostOk0=Test-LocalHost;$cdpOk0=Test-Cdp;$remoteOk0=Test-Remote;if(-not$hostOk0){$issues.Add('LOCAL_HOST_DOWN')};if(-not$cdpOk0){$issues.Add('CFT_CDP_9224_DOWN')};if(-not$remoteOk0){$issues.Add('REMOTE_DC_OFFLINE')}
$authRemain=$false;if($wa-and$wa.obj){if([int]$wa.obj.duplicateFamiliesRemaining-gt0){$authRemain=$true};if([int]$wa.obj.ttlCloseFailures-gt0){$issues.Add('AUTH_TTL_CLOSE_FAILURE')}};if($authRemain){$issues.Add('AUTH_DUPLICATE_REMAINS')};if($SelfTestRecovery){$issues.Add('SELF_TEST_RECOVERY_TRIGGER')}
$recoveryTriggered=$false;$recoveryCooldown=$false;$recoveryExit=$null;if($issues.Count-gt0-and(Test-Path $RecoveryScript)){$recent=$false;try{if(Test-Path $RecoveryReceipt){$recent=(((Get-Date)-(Get-Item $RecoveryReceipt).LastWriteTime).TotalSeconds-lt120)}}catch{};if($recent-and-not$SelfTestRecovery){$recoveryCooldown=$true}else{try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $RecoveryScript -Reason ($issues-join',')|Out-Null;$recoveryExit=$LASTEXITCODE;$recoveryTriggered=$true}catch{$recoveryExit=9}}}
$hostOk1=Test-LocalHost;$cdpOk1=Test-Cdp;$remoteOk1=Test-Remote;$waObj=$(if($wa){$wa.obj}else{$null});$igObj=$(if($ig){$ig.obj}else{$null});$clObj=$(if($cl){$cl.obj}else{$null});$waOk=[bool]($waObj-and[bool]$waObj.ok-and[string]$waObj.version-match'^WINDOW_ACTIVITY_SUPERVISOR_V5_');$igOk=[bool]($igObj-and[bool]$igObj.ok-and[string]$igObj.version-match'^INACTIVE_PROCESS_GOVERNOR_V1_');$clOk=[bool]($clObj-and[bool]$clObj.ok)
$out=[ordered]@{ok=[bool]($pg.ok-and$waOk-and$igOk-and$clOk-and$hostOk1-and$cdpOk1-and$remoteOk1-and-not$authRemain);version=$Version;startedAt=$started;completedAt=(Get-Date).ToString('o');phase='POWER_REMOTE_SCREEN_OFF_CONTINUITY+WINDOW_V5_UIA+AUTH_TTL600+INACTIVE_5M_EXACT_PID+VERIFY_RECOVER';powerGuardOk=[bool]$pg.ok;powerGuardSha=[string]$pg.sha;powerGuardReceiptVersion=[string]$pg.receiptVersion;powerGuardRestarted=[bool]$pg.restarted;powerGuardSystemRequiredHeld=[bool]$pg.systemRequiredHeld;powerGuardDisplayRequiredHeld=[bool]$pg.displayRequiredHeld;powerGuardRemoteLeaseActive=[bool]$pg.remoteLeaseActive;powerGuardProcessAfter=[int]$pg.after;windowActivitySha=$waSha;windowActivityVersion=$(if($waObj){[string]$waObj.version}else{''});windowActivityOk=$waOk;windowActivityMonitorCount=$(if($waObj){[int]$waObj.monitorCount}else{0});windowActivityCaptureCount=$(if($waObj){[int]$waObj.captureCount}else{0});windowActivityAuthTtlSec=$(if($waObj){[int]$waObj.authWindowTtlSec}else{0});windowActivityExpiredSingleAuth=$(if($waObj){[int]$waObj.expiredSingleAuthCount}else{0});windowActivityTtlCloseFailures=$(if($waObj){[int]$waObj.ttlCloseFailures}else{0});windowActivityClosedSuperseded=$(if($waObj){[int]$waObj.closedSupersededCount}else{0});windowActivityDuplicateFamiliesRemaining=$(if($waObj){[int]$waObj.duplicateFamiliesRemaining}else{0});inactiveGovernorSha=$igSha;inactiveGovernorVersion=$(if($igObj){[string]$igObj.version}else{''});inactiveGovernorOk=$igOk;inactiveGovernorCandidateCount=$(if($igObj){[int]$igObj.candidateCount}else{0});inactiveGovernorForcedCount=$(if($igObj){[int]$igObj.forcedCount}else{0});inactiveGovernorExitedCount=$(if($igObj){[int]$igObj.exitedCount}else{0});inactiveGovernorProtectedSharedCount=$(if($igObj){[int]$igObj.protectedSharedCount}else{0});cleanupVersion=$(if($clObj){[string]$clObj.version}else{''});hostOk=$hostOk1;cdp9224Ok=$cdpOk1;remoteDcOk=$remoteOk1;issues=@($issues);recoveryTriggered=$recoveryTriggered;recoveryExit=$recoveryExit;recoveryCooldown=$recoveryCooldown;policy='VISIBLE!=WORKING;AUTH_HARD_TTL_600S;REGISTERED_TERMINAL_INACTIVE_300S;GRACEFUL_7S_THEN_EXACT_PID_FORCE;SHARED_BROWSER_PROCESS_FORCE_KILL_FORBIDDEN;UIAUTOMATION_V5;ALL_MONITORS_10M;REMOTE_SYSTEM_AWAKE;DISPLAY_CAN_OFF;PINNED_FALLBACK;REMOTE_EXACT_REPAIR'}
$json=$out|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath $Receipt -Encoding UTF8;try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'CENTRAL_TAB_SUPERVISOR_LAST.json') -Encoding UTF8}}catch{};$out|ConvertTo-Json -Depth 30 -Compress;if($out.ok){exit 0}else{exit 4}