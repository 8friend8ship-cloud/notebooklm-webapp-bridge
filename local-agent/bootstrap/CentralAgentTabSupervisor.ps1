param([switch]$SelfTestRecovery)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_AGENT_TAB_SUPERVISOR_V16_INACTIVE_R2_PIN_20260909'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$CleanupScript=Join-Path $Root 'RunOwnedUiCleanup.ps1'
$RecoveryScript=Join-Path $Root 'CentralTabAutoRecovery.ps1'
$PowerGuardScript=Join-Path $Root 'CentralAgentPowerContinuityGuard.ps1'
$PowerGuardReceipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$RemoteGuardScript=Join-Path $Root 'DesktopCommanderKeepAlive.ps1'
$WindowActivityScript=Join-Path $Root 'WindowActivitySupervisor.ps1'
$InactiveGovernorScript=Join-Path $Root 'InactiveProcessGovernor.ps1'
$Receipt=Join-Path $Root 'CENTRAL_TAB_SUPERVISOR_LAST.json'
$RecoveryReceipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
$RequiredPowerGuardVersion='POWER_CONTINUITY_GUARD_V3_REMOTE_DISPLAY_AWAKE_20260909'
$RequiredRemoteGuardPattern='^REMOTE_DC_KEEPALIVE_V4_'
$Pins=@{
 'local-agent/bootstrap/CentralAgentPowerContinuityGuard.ps1'=@{commit='ac8a01a1e2ae9676bf8bf90698f9af5402cab1e9';sha='93bb738c22c8b82893cb2acb7cbc74ba97cb9e8a'}
 'local-agent/bootstrap/WindowActivitySupervisor.ps1'=@{commit='22aef32e7a24bcbc1fc3145afc1cbf5e5ad99e05';sha='407b1134d1d574bfdc3e44baaa0650eb29349765'}
 'local-agent/bootstrap/InactiveProcessGovernor.ps1'=@{commit='5d4cd5171d031c9d8252f03adb06925f5380181f';sha='5a9df27edd089d62f2eaf473a6cbdb984bd287b2'}
 'local-agent/bootstrap/DesktopCommanderKeepAlive.ps1'=@{commit='5c4ced4173a73556ac4f5c7279d8854dee289511';sha='bbf3fe89bc076d60b93169acca856a776769a7f3'}
}
function Test-LocalHost{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Test-Cdp{try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;return [bool]$v.Browser}catch{return $false}}
function Test-Remote{try{$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$'-and[string]$_.CommandLine-match'(?i)desktop-commander'-and[string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'});if($p.Count-eq0){return $false};$ids=@($p|ForEach-Object{[int]$_.ProcessId});return (@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count-gt0)}catch{return $false}}
function Find-Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return''}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Install-Verified([byte[]]$Bytes,[string]$Expected,[string]$Dest){$sha=(GitBlob $Bytes).ToLowerInvariant();if($sha-ne$Expected.ToLowerInvariant()){throw'SHA_MISMATCH'};$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,$Bytes);Move-Item $tmp $Dest -Force;return $sha}
function Refresh-Verified([string]$RepoPath,[string]$Dest){$pin=$Pins[$RepoPath];try{$u='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Supervisor-V16';'Accept'='application/vnd.github+json'} -TimeoutSec 8;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));return (Install-Verified $b ([string]$x.sha) $Dest)}catch{};if($pin){try{$u='https://raw.githubusercontent.com/'+$Repo+'/'+[string]$pin.commit+'/'+$RepoPath;$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Supervisor-V16';$b=$wc.DownloadData($u)}finally{$wc.Dispose()};return (Install-Verified $b ([string]$pin.sha) $Dest)}catch{};try{if(Test-Path $Dest){$b=[IO.File]::ReadAllBytes($Dest);$sha=(GitBlob $b).ToLowerInvariant();if($sha-eq([string]$pin.sha).ToLowerInvariant()){return $sha}}}catch{}};return''}
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
   $o.ok=[bool]($procs.Count-gt0-and$o.receiptVersion-eq$RequiredPowerGuardVersion-and((-not$need)-or($o.systemRequiredHeld-and$o.displayRequiredHeld)))
  }
 }catch{$o.error=$_.Exception.Message}
 return [pscustomobject]$o
}
function Run-Json([string]$Path){$o=[ordered]@{exit=9;obj=$null;raw='';error=''};try{$o.raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path 2>&1|Out-String;$o.exit=$LASTEXITCODE;try{$o.obj=$o.raw|ConvertFrom-Json}catch{$lines=@($o.raw-split"`r?`n"|Where-Object{$_.Trim().StartsWith('{')});if($lines.Count){$o.obj=$lines[-1]|ConvertFrom-Json}else{throw}}}catch{$o.error=$_.Exception.Message};return [pscustomobject]$o}
$started=(Get-Date).ToString('o');$issues=New-Object System.Collections.Generic.List[string]
$pg=Ensure-PowerGuard;if(-not$pg.ok){$issues.Add('POWER_CONTINUITY_GUARD_DOWN')}
$rgSha=Refresh-Verified 'local-agent/bootstrap/DesktopCommanderKeepAlive.ps1' $RemoteGuardScript;$rg=$null;$rgOk=$false
if(-not$rgSha){$issues.Add('REMOTE_GUARD_REFRESH_FAILED')}else{$rg=Run-Json $RemoteGuardScript;if(-not$rg.obj){$issues.Add('REMOTE_GUARD_NO_READBACK')}elseif([string]$rg.obj.version-notmatch$RequiredRemoteGuardPattern){$issues.Add('REMOTE_GUARD_VERSION_MISMATCH')}elseif(-not[bool]$rg.obj.ok){$issues.Add('REMOTE_GUARD_NOT_OK')}else{$rgOk=$true}}
$waSha=Refresh-Verified 'local-agent/bootstrap/WindowActivitySupervisor.ps1' $WindowActivityScript;$wa=$null;if(-not$waSha){$issues.Add('WINDOW_ACTIVITY_REFRESH_FAILED')}else{$wa=Run-Json $WindowActivityScript;if(-not$wa.obj){$issues.Add('WINDOW_ACTIVITY_NO_READBACK')}elseif([string]$wa.obj.version-notmatch'^WINDOW_ACTIVITY_SUPERVISOR_V5_'){$issues.Add('WINDOW_ACTIVITY_VERSION_MISMATCH')}elseif(-not[bool]$wa.obj.ok){$issues.Add('WINDOW_ACTIVITY_NOT_OK')}}
$igSha=Refresh-Verified 'local-agent/bootstrap/InactiveProcessGovernor.ps1' $InactiveGovernorScript;$ig=$null;if(-not$igSha){$issues.Add('INACTIVE_GOVERNOR_REFRESH_FAILED')}else{$ig=Run-Json $InactiveGovernorScript;if(-not$ig.obj){$issues.Add('INACTIVE_GOVERNOR_NO_READBACK')}elseif([string]$ig.obj.version-notmatch'^INACTIVE_PROCESS_GOVERNOR_V1_'){$issues.Add('INACTIVE_GOVERNOR_VERSION_MISMATCH')}elseif(-not[bool]$ig.obj.ok){$issues.Add('INACTIVE_GOVERNOR_NOT_OK')}}
$cl=$null;if(Test-Path $CleanupScript){$cl=Run-Json $CleanupScript;if(-not$cl.obj-or-not[bool]$cl.obj.ok){$issues.Add('CLEANUP_NOT_OK')}}else{$issues.Add('CLEANUP_MISSING')}
$hostOk0=Test-LocalHost;$cdpOk0=Test-Cdp;$remoteLocal0=Test-Remote;$remoteOk0=[bool]($rgOk-and$remoteLocal0);if(-not$hostOk0){$issues.Add('LOCAL_HOST_DOWN')};if(-not$cdpOk0){$issues.Add('CFT_CDP_9224_DOWN')};if(-not$remoteOk0){$issues.Add('REMOTE_DC_OFFLINE_OR_WITHDRAWN')}
$authRemain=$false;if($wa-and$wa.obj){if([int]$wa.obj.duplicateFamiliesRemaining-gt0){$authRemain=$true};if([int]$wa.obj.ttlCloseFailures-gt0){$issues.Add('AUTH_TTL_CLOSE_FAILURE')}};if($authRemain){$issues.Add('AUTH_DUPLICATE_REMAINS')};if($SelfTestRecovery){$issues.Add('SELF_TEST_RECOVERY_TRIGGER')}
$recoveryTriggered=$false;$recoveryCooldown=$false;$recoveryExit=$null;if($issues.Count-gt0-and(Test-Path $RecoveryScript)){$recent=$false;try{if(Test-Path $RecoveryReceipt){$recent=(((Get-Date)-(Get-Item $RecoveryReceipt).LastWriteTime).TotalSeconds-lt120)}}catch{};if($recent-and-not$SelfTestRecovery){$recoveryCooldown=$true}else{try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $RecoveryScript -Reason ($issues-join',')|Out-Null;$recoveryExit=$LASTEXITCODE;$recoveryTriggered=$true}catch{$recoveryExit=9}}}
$hostOk1=Test-LocalHost;$cdpOk1=Test-Cdp;$remoteLocal1=Test-Remote;$remoteOk1=[bool]($rgOk-and$remoteLocal1);$waObj=$(if($wa){$wa.obj}else{$null});$igObj=$(if($ig){$ig.obj}else{$null});$clObj=$(if($cl){$cl.obj}else{$null});$rgObj=$(if($rg){$rg.obj}else{$null});$waOk=[bool]($waObj-and[bool]$waObj.ok-and[string]$waObj.version-match'^WINDOW_ACTIVITY_SUPERVISOR_V5_');$igOk=[bool]($igObj-and[bool]$igObj.ok-and[string]$igObj.version-match'^INACTIVE_PROCESS_GOVERNOR_V1_');$clOk=[bool]($clObj-and[bool]$clObj.ok)
$out=[ordered]@{ok=[bool]($pg.ok-and$rgOk-and$waOk-and$igOk-and$clOk-and$hostOk1-and$cdpOk1-and$remoteOk1-and-not$authRemain);version=$Version;startedAt=$started;completedAt=(Get-Date).ToString('o');phase='POWER+REMOTE_GUARD_V4+DISPLAY_AWAKE+WINDOW_V5_UIA+AUTH_TTL600+INACTIVE_5M_EXACT_PID+VERIFY_RECOVER';powerGuardOk=[bool]$pg.ok;powerGuardSha=[string]$pg.sha;powerGuardReceiptVersion=[string]$pg.receiptVersion;powerGuardRestarted=[bool]$pg.restarted;powerGuardSystemRequiredHeld=[bool]$pg.systemRequiredHeld;powerGuardDisplayRequiredHeld=[bool]$pg.displayRequiredHeld;powerGuardRemoteLeaseActive=[bool]$pg.remoteLeaseActive;powerGuardProcessAfter=[int]$pg.after;remoteGuardSha=$rgSha;remoteGuardVersion=$(if($rgObj){[string]$rgObj.version}else{''});remoteGuardOk=$rgOk;remoteGuardStatus=$(if($rgObj){[string]$rgObj.status}else{''});remoteGuardDiagnostic=$(if($rgObj){[string]$rgObj.diagnosticReason}else{''});remoteGuardRestartAttempted=$(if($rgObj){[bool]$rgObj.restartAttempted}else{$false});remoteGuardHumanGate=$(if($rgObj){[bool]$rgObj.humanGate}else{$false});windowActivitySha=$waSha;windowActivityVersion=$(if($waObj){[string]$waObj.version}else{''});windowActivityOk=$waOk;windowActivityMonitorCount=$(if($waObj){[int]$waObj.monitorCount}else{0});windowActivityCaptureCount=$(if($waObj){[int]$waObj.captureCount}else{0});windowActivityAuthTtlSec=$(if($waObj){[int]$waObj.authWindowTtlSec}else{0});windowActivityExpiredSingleAuth=$(if($waObj){[int]$wa.obj.expiredSingleAuthCount}else{0});windowActivityTtlCloseFailures=$(if($waObj){[int]$wa.obj.ttlCloseFailures}else{0});windowActivityClosedSuperseded=$(if($waObj){[int]$waObj.closedSupersededCount}else{0});windowActivityDuplicateFamiliesRemaining=$(if($waObj){[int]$wa.obj.duplicateFamiliesRemaining}else{0});inactiveGovernorSha=$igSha;inactiveGovernorVersion=$(if($igObj){[string]$igObj.version}else{''});inactiveGovernorOk=$igOk;inactiveGovernorCandidateCount=$(if($igObj){[int]$igObj.candidateCount}else{0});inactiveGovernorForcedCount=$(if($igObj){[int]$igObj.forcedCount}else{0});inactiveGovernorExitedCount=$(if($igObj){[int]$igObj.exitedCount}else{0});inactiveGovernorProtectedSharedCount=$(if($igObj){[int]$igObj.protectedSharedCount}else{0});cleanupVersion=$(if($clObj){[string]$clObj.version}else{''});hostOk=$hostOk1;cdp9224Ok=$cdpOk1;remoteLocalProcessTcpOk=$remoteLocal1;remoteDcOk=$remoteOk1;issues=@($issues);recoveryTriggered=$recoveryTriggered;recoveryExit=$recoveryExit;recoveryCooldown=$recoveryCooldown;policy='VISIBLE!=WORKING;AUTH_HARD_TTL_600S;REGISTERED_TERMINAL_INACTIVE_300S;GRACEFUL_7S_THEN_EXACT_PID_FORCE;SHARED_BROWSER_PROCESS_FORCE_KILL_FORBIDDEN;UIAUTOMATION_V5;ALL_MONITORS_10M;REMOTE_SYSTEM_AWAKE;REMOTE_DISPLAY_AWAKE;KEEPALIVE_V4_AUTHORITATIVE;BROADCAST_WITHDRAWAL_RECOVERY;EXACT_NODE_ONLY;PINNED_FALLBACK'}
$json=$out|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath $Receipt -Encoding UTF8;try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'CENTRAL_TAB_SUPERVISOR_LAST.json') -Encoding UTF8}}catch{};$out|ConvertTo-Json -Depth 30 -Compress;if($out.ok){exit 0}else{exit 4}
