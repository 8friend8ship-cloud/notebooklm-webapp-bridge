param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='THREE_STAGE_FAILOVER_V2_CONTROL_AWARE_FALSE_HEALTH_20260919'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'THREE_STAGE_FAILOVER_LAST.json'
$KeepAlive=Join-Path $Root 'DesktopCommanderKeepAlive.ps1'
$LocalWatchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c -PathType Container){return $c}}};''}
function Save($o){try{$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content $Receipt -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content (Join-Path $d 'THREE_STAGE_FAILOVER_LAST.json') -Encoding UTF8}}catch{}}
function RunPs([string]$p,[int]$sec=180){if(-not(Test-Path $p)){return 127};try{$x=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$p`"") -PassThru -WindowStyle Hidden;if(-not$x.WaitForExit($sec*1000)){try{Stop-Process -Id $x.Id -Force}catch{};return 124};return [int]$x.ExitCode}catch{return 125}}
function RemoteLocalHealth{try{$p=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and ([string]$_.CommandLine)-match'(?i)desktop-commander' -and ([string]$_.CommandLine)-match'(?i)(?:^|\s)remote(?:\s|$)'});$tcp=@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$_.OwningProcess -in @($p.ProcessId)});[pscustomobject]@{processCount=$p.Count;tcpEstablished=$tcp.Count;healthy=($p.Count-gt0-and$tcp.Count-gt0)}}catch{[pscustomobject]@{processCount=0;tcpEstablished=0;healthy=$false}}}
function TailscaleHealth{$o=[ordered]@{installed=$false;serviceRunning=$false;backendState='';ip='';healthy=$false;unattendedCapable=$true;error=''};try{$cmd=Get-Command tailscale.exe -ErrorAction SilentlyContinue;if(-not$cmd){$cmd=Get-Command tailscale -ErrorAction SilentlyContinue};$o.installed=[bool]$cmd;$svc=Get-Service Tailscale -ErrorAction SilentlyContinue;$o.serviceRunning=($svc-and$svc.Status-eq'Running');if($cmd){$raw=& $cmd.Source status --json 2>$null|Out-String;if($raw){$j=$raw|ConvertFrom-Json;$o.backendState=[string]$j.BackendState;$ips=@($j.TailscaleIPs);if($ips.Count){$o.ip=[string]$ips[0]};$o.healthy=($o.serviceRunning-and$o.backendState-eq'Running'-and[bool]$o.ip)}}}catch{$o.error=$_.Exception.Message};[pscustomobject]$o}
function FetchRecoveryControl{
  try{
    $u='https://api.github.com/repos/8friend8ship-cloud/notebooklm-webapp-bridge/contents/local-agent/control/remote-dc-recovery.json?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-ThreeStage-V2';'Accept'='application/vnd.github+json';'Cache-Control'='no-cache'} -TimeoutSec 15
    if(-not$x.content){return $null}
    $j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$x.content-replace'\s','')))|ConvertFrom-Json
    return $j
  }catch{return $null}
}
function RecoveryRequestActive($c){
  if(-not$c){return $false}
  if(-not[bool]$c.enabled){return $false}
  $rid=[string]$c.requestId;if(-not$rid){return $false}
  $exp=[string]$c.expiresAt
  if($exp){try{if([DateTimeOffset]::Parse($exp).UtcDateTime-lt[DateTime]::UtcNow){return $false}}catch{return $false}}
  return $true
}
$r=[ordered]@{ok=$false;version=$Version;startedAt=(Get-Date).ToString('o');completedAt='';stage='';primary=[ordered]@{};secondary=[ordered]@{};tertiary=[ordered]@{};returnToPrimary=$false;receiptRequired='REMOTE_PING+COMMAND+FILE_RW_X2';errors=@()}
try{
 $control=FetchRecoveryControl
 $r.activeRecoveryRequestId=if($control){[string]$control.requestId}else{''}
 $r.activeRecoveryRequested=[bool](RecoveryRequestActive $control)
 $before=RemoteLocalHealth;$r.primary.before=$before
 if($r.activeRecoveryRequested){
   $r.primary.falseHealthyGuardForced=$true
   $r.primary.forcedWatchdogExit=RunPs $LocalWatchdog 420
   Start-Sleep -Seconds 3
 }else{$r.primary.falseHealthyGuardForced=$false}
 if(-not$before.healthy -and -not$r.activeRecoveryRequested){$r.primary.keepAliveExit=RunPs $KeepAlive 240;Start-Sleep -Seconds 3}
 $after=RemoteLocalHealth;$r.primary.after=$after
 if($after.healthy -and -not$r.activeRecoveryRequested){$r.stage='L1_REMOTE_DC_LOCAL_TRANSPORT';$r.ok=$true}
 elseif($after.healthy -and $r.activeRecoveryRequested -and [int]$r.primary.forcedWatchdogExit-eq0){$r.stage='L1_RECOVERY_CONTROL_FORCED_WATCHDOG_LOCAL_HEALTHY';$r.ok=$true}
 else{
   $ts=TailscaleHealth;$r.secondary=$ts
   if($ts.healthy){$r.stage='L2_TAILSCALE_AVAILABLE_FOR_OOB';$r.ok=$false;$r.errors+='REMOTE_DC_NOT_RECOVERED_EXTERNALLY_VERIFY_VIA_TAILNET_RDP'}
   else{
     $r.tertiary.watchdogExit=RunPs $LocalWatchdog 420;Start-Sleep -Seconds 3;$post=RemoteLocalHealth;$r.tertiary.post=$post
     if($post.healthy){$r.stage='L3_LOCAL_L0_RECOVERED_PRIMARY';$r.returnToPrimary=$true;$r.ok=$true}else{$r.stage='L3_LOCAL_L0_ACTIVE_PRIMARY_STILL_DOWN';$r.ok=$false;$r.errors+='PRIMARY_REMOTE_STILL_UNAVAILABLE'}
   }
 }
}catch{$r.errors+=$_.Exception.Message}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 40 -Compress
if($r.ok){exit 0}else{exit 4}
