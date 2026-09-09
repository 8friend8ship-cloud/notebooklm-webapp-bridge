param([switch]$SelfTestRecovery)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_AGENT_TAB_SUPERVISOR_V6_PINNED_FALLBACK_AUTH_TTL_20260909'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$CleanupScript=Join-Path $Root 'RunOwnedUiCleanup.ps1'
$RecoveryScript=Join-Path $Root 'CentralTabAutoRecovery.ps1'
$PowerGuardScript=Join-Path $Root 'CentralAgentPowerContinuityGuard.ps1'
$PowerGuardReceipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$WindowActivityScript=Join-Path $Root 'WindowActivitySupervisor.ps1'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$Receipt=Join-Path $Root 'CENTRAL_TAB_SUPERVISOR_LAST.json'
$RecoveryReceipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
$PinnedSources=@{
  'local-agent/bootstrap/CentralAgentPowerContinuityGuard.ps1'=@{commit='f5e5a023b0b1ed6bd1f644a57be24fea02fe28ca';sha='b33d1ce889049e64706048ca8242e79b47b78e9c'}
  'local-agent/bootstrap/WindowActivitySupervisor.ps1'=@{commit='8ca2eb77b7e2891ca2f987a7d820bf4dbb7181ba';sha='9f32d803364a72a037e3ae849905d61bfe23a880'}
}

function Test-Host {try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Test-Cdp {try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;return [bool]$v.Browser}catch{return $false}}
function Test-Remote {
  try{$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -match '(?i)desktop-commander' -and [string]$_.CommandLine -match '(?i)(?:^|\s)remote(?:\s|$)'});if($p.Count -eq 0){return $false};$ids=@($p.ProcessId);return (@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids -contains $_.OwningProcess}).Count -gt 0)}catch{return $false}
}
function Find-Central {
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''
}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Install-VerifiedBytes([byte[]]$Bytes,[string]$ExpectedSha,[string]$Dest){$sha=(GitBlob $Bytes).ToLowerInvariant();if($sha -ne $ExpectedSha.ToLowerInvariant()){throw 'SHA_MISMATCH'};$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,$Bytes);Move-Item $tmp $Dest -Force;return $sha}
function Refresh-Verified([string]$RepoPath,[string]$Dest){
  $pin=$PinnedSources[$RepoPath]
  try{
    $u='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Central-Supervisor';'Accept'='application/vnd.github+json'} -TimeoutSec 12
    $b=[Convert]::FromBase64String(([string]$x.content -replace '\s',''));return (Install-VerifiedBytes $b ([string]$x.sha) $Dest)
  }catch{}
  if($pin){
    try{
      $raw='https://raw.githubusercontent.com/'+$Repo+'/'+[string]$pin.commit+'/'+$RepoPath;$tmp=$Dest+'.rawdownload';Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $tmp -TimeoutSec 15;$b=[IO.File]::ReadAllBytes($tmp);Remove-Item $tmp -Force -ErrorAction SilentlyContinue;return (Install-VerifiedBytes $b ([string]$pin.sha) $Dest)
    }catch{}
    try{if(Test-Path $Dest){$b=[IO.File]::ReadAllBytes($Dest);$sha=(GitBlob $b).ToLowerInvariant();if($sha -eq ([string]$pin.sha).ToLowerInvariant()){return $sha}}}catch{}
  }
  return ''
}
function Get-PowerGuardProcesses {Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -match '(?i)CentralAgentPowerContinuityGuard\.ps1'} }
function Read-PowerGuardReceipt {try{if(Test-Path $PowerGuardReceipt){return (Get-Content $PowerGuardReceipt -Raw -Encoding UTF8|ConvertFrom-Json)}}catch{};return $null}
function Ensure-PowerGuard {
  $o=[ordered]@{sha='';before=0;started=$false;restartedForVersion=$false;after=0;ok=$false;error='';receiptVersion='';systemRequiredHeld=$false;acPower=$false;remoteProcessPresent=$false}
  try{
    $o.sha=Refresh-Verified 'local-agent/bootstrap/CentralAgentPowerContinuityGuard.ps1' $PowerGuardScript;if(-not $o.sha){throw 'POWER_GUARD_REFRESH_FAILED'}
    $procs=@(Get-PowerGuardProcesses);$o.before=$procs.Count;$oldReceipt=Read-PowerGuardReceipt;$oldVersion=$(if($oldReceipt){[string]$oldReceipt.version}else{''})
    if($procs.Count -gt 0 -and $oldVersion -notmatch '^POWER_CONTINUITY_GUARD_V3_'){foreach($p in $procs){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop}catch{}};Start-Sleep -Seconds 1;$o.restartedForVersion=$true}
    if(@(Get-PowerGuardProcesses).Count -eq 0){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$PowerGuardScript) -WindowStyle Hidden|Out-Null;$o.started=$true;Start-Sleep -Seconds 3}
    $o.after=@(Get-PowerGuardProcesses).Count;$rr=Read-PowerGuardReceipt
    if($rr){$o.receiptVersion=[string]$rr.version;$o.systemRequiredHeld=[bool]$rr.systemRequiredHeld;$o.acPower=[bool]$rr.acPower;$o.remoteProcessPresent=[bool]$rr.remoteProcessPresent}
    $needsHold=[bool]($o.acPower -and $o.remoteProcessPresent);$o.ok=[bool]($o.after -gt 0 -and $o.receiptVersion -match '^POWER_CONTINUITY_GUARD_V3_' -and ((-not $needsHold) -or $o.systemRequiredHeld))
  }catch{$o.error=$_.Exception.Message}
  return [pscustomobject]$o
}
function Run-JsonScript([string]$Path){
  $o=[ordered]@{ok=$false;exit=9;raw='';obj=$null;error=''}
  try{$o.raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path 2>&1|Out-String;$o.exit=$LASTEXITCODE;try{$o.obj=$o.raw|ConvertFrom-Json}catch{$jsonLines=@($o.raw -split "`r?`n"|Where-Object{$_.Trim().StartsWith('{')});if($jsonLines.Count -gt 0){$o.obj=$jsonLines[-1]|ConvertFrom-Json}else{throw}};$o.ok=[bool]$o.obj.ok}catch{$o.error=$_.Exception.Message}
  return [pscustomobject]$o
}

$started=(Get-Date).ToString('o');$issues=New-Object System.Collections.Generic.List[string]
$powerGuardRun=Ensure-PowerGuard;if(-not $powerGuardRun.ok){$issues.Add('POWER_CONTINUITY_GUARD_DOWN')}
$activitySha=Refresh-Verified 'local-agent/bootstrap/WindowActivitySupervisor.ps1' $WindowActivityScript;$activityRun=$null
if(-not $activitySha){$issues.Add('WINDOW_ACTIVITY_REFRESH_FAILED')}elseif(Test-Path $WindowActivityScript){$activityRun=Run-JsonScript $WindowActivityScript;if(-not $activityRun.obj){$issues.Add('WINDOW_ACTIVITY_NO_READBACK')}elseif([string]$activityRun.obj.version -notmatch '^WINDOW_ACTIVITY_SUPERVISOR_V2_'){$issues.Add('WINDOW_ACTIVITY_VERSION_MISMATCH')}elseif(-not [bool]$activityRun.obj.ok){$issues.Add('WINDOW_ACTIVITY_NOT_OK')}}else{$issues.Add('WINDOW_ACTIVITY_MISSING')}
$cleanupRun=$null
if(Test-Path $CleanupScript){$cleanupRun=Run-JsonScript $CleanupScript;if(-not $cleanupRun.obj){$issues.Add('CLEANUP_NO_READBACK')}elseif(-not [bool]$cleanupRun.obj.ok){$issues.Add('CLEANUP_NOT_OK')}elseif([string]$cleanupRun.obj.version -notmatch 'RUN_OWNED_UI_CLEANUP_V[45]_'){$issues.Add('CLEANUP_VERSION_MISMATCH')}}else{$issues.Add('CLEANUP_MISSING')}
$registryCount=0;$registryOk=$true;$r=@();try{$r=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;$registryCount=@($r).Count}catch{$registryOk=$false;$issues.Add('REGISTRY_PARSE_FAIL')}
$registryPruned=0;$registryCountAfter=$registryCount;$pruneIds=@()
if($registryOk -and $cleanupRun -and $cleanupRun.obj -and $cleanupRun.obj.results){foreach($rr in @($cleanupRun.obj.results)){if([string]$rr.state -match '^(ALREADY_NOT_VISIBLE|CLOSED_EXACT_HWND|HWND_REUSED_OWNER_MISMATCH|ALREADY_CLOSED|CLOSED)$' -and [string]$rr.runId){$pruneIds+=[string]$rr.runId}};$pruneIds=@($pruneIds|Sort-Object -Unique)}
if($registryOk -and $pruneIds.Count -gt 0){try{$kept=@($r|Where-Object{$pruneIds -notcontains [string]$_.runId});if($kept.Count -lt $registryCount){$tmp=$Registry+'.compact';ConvertTo-Json -InputObject ([object[]]$kept) -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item $tmp $Registry -Force;$registryPruned=$registryCount-$kept.Count;$registryCountAfter=$kept.Count}}catch{$issues.Add('REGISTRY_COMPACT_FAIL')}}
$hostOk=Test-Host;$cdpOk=Test-Cdp;$remoteOk=Test-Remote;if(-not $hostOk){$issues.Add('LOCAL_HOST_DOWN')};if(-not $cdpOk){$issues.Add('CFT_CDP_9224_DOWN')};if(-not $remoteOk){$issues.Add('REMOTE_DC_OFFLINE')}
$authDupRemain=$false
if($activityRun -and $activityRun.obj){if([int]$activityRun.obj.duplicateFamiliesRemaining -gt 0){$authDupRemain=$true};if([int]$activityRun.obj.ttlCloseFailures -gt 0){$issues.Add('AUTH_TTL_CLOSE_FAILURE')}}
if(-not $authDupRemain -and $cleanupRun -and $cleanupRun.obj -and $cleanupRun.obj.authActions){foreach($a in @($cleanupRun.obj.authActions)){if([int]$a.found -gt 1 -and [int]$a.closed -eq 0 -and [string]$a.action -notmatch 'PROTECT_WAITING_USER'){$authDupRemain=$true}}}
if($authDupRemain){$issues.Add('AUTH_DUPLICATE_REMAINS')};if($SelfTestRecovery){$issues.Add('SELF_TEST_RECOVERY_TRIGGER')}
$recoveryTriggered=$false;$recoveryCooldown=$false;$recoveryExit=$null
if($issues.Count -gt 0 -and (Test-Path $RecoveryScript)){$recent=$false;try{if(Test-Path $RecoveryReceipt){$recent=(((Get-Date)-(Get-Item $RecoveryReceipt).LastWriteTime).TotalSeconds -lt 120)}}catch{};if($recent -and -not $SelfTestRecovery){$recoveryCooldown=$true}else{try{$reason=($issues -join ',');& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $RecoveryScript -Reason $reason|Out-Null;$recoveryExit=$LASTEXITCODE;$recoveryTriggered=$true}catch{$recoveryExit=9}}}
$hostAfter=Test-Host;$cdpAfter=Test-Cdp;$remoteAfter=Test-Remote;$activityObj=$(if($activityRun){$activityRun.obj}else{$null});$cleanupObj=$(if($cleanupRun){$cleanupRun.obj}else{$null})
$activityHealthy=[bool]($activityObj -and [bool]$activityObj.ok -and [string]$activityObj.version -match '^WINDOW_ACTIVITY_SUPERVISOR_V2_');$cleanupHealthy=[bool]($cleanupObj -and [bool]$cleanupObj.ok -and [string]$cleanupObj.version -match 'RUN_OWNED_UI_CLEANUP_V[45]_')
$out=[ordered]@{
  ok=[bool]($powerGuardRun.ok -and $activityHealthy -and $cleanupHealthy -and $hostAfter -and $cdpAfter -and $remoteAfter -and -not $authDupRemain)
  version=$Version;startedAt=$started;completedAt=(Get-Date).ToString('o');phase='PINNED_FALLBACK+POWER_V3+WINDOW_ACTIVITY_V2_AUTH_TTL+MID_CLEAN+VERIFY+RECOVER'
  powerGuardOk=[bool]$powerGuardRun.ok;powerGuardSha=[string]$powerGuardRun.sha;powerGuardStarted=[bool]$powerGuardRun.started;powerGuardRestartedForVersion=[bool]$powerGuardRun.restartedForVersion;powerGuardProcessAfter=[int]$powerGuardRun.after;powerGuardReceiptVersion=[string]$powerGuardRun.receiptVersion;powerGuardSystemRequiredHeld=[bool]$powerGuardRun.systemRequiredHeld;powerGuardError=[string]$powerGuardRun.error
  windowActivitySha=$activitySha;windowActivityVersion=$(if($activityObj){[string]$activityObj.version}else{''});windowActivityOk=$activityHealthy;windowActivityMonitorCount=$(if($activityObj){[int]$activityObj.monitorCount}else{0});windowActivityCaptureCount=$(if($activityObj){[int]$activityObj.captureCount}else{0});windowActivityClosedSuperseded=$(if($activityObj){[int]$activityObj.closedSupersededCount}else{0});windowActivityExpiredSingleAuth=$(if($activityObj){[int]$activityObj.expiredSingleAuthCount}else{0});windowActivityTtlCloseFailures=$(if($activityObj){[int]$activityObj.ttlCloseFailures}else{0});windowActivityStaleBeforeTtl=$(if($activityObj){@($activityObj.staleBeforeTtl).Count}else{0});windowActivityDuplicateFamiliesRemaining=$(if($activityObj){[int]$activityObj.duplicateFamiliesRemaining}else{0});windowActivityAuthTtlSec=$(if($activityObj){[int]$activityObj.authWindowTtlSec}else{0})
  cleanupExit=$(if($cleanupRun){$cleanupRun.exit}else{9});cleanupVersion=$(if($cleanupObj){[string]$cleanupObj.version}else{''});cleanupClosed=$(if($cleanupObj){[int]$cleanupObj.closedCount}else{-1});registryOk=$registryOk;registryCount=$registryCount;registryPruned=$registryPruned;registryCountAfter=$registryCountAfter
  hostOk=$hostAfter;cdp9224Ok=$cdpAfter;remoteDcOk=$remoteAfter;authDuplicateRemains=$authDupRemain;issues=@($issues);recoveryTriggered=$recoveryTriggered;recoveryExit=$recoveryExit;recoveryCooldown=$recoveryCooldown
  policy='VISIBLE_NOT_EQUAL_WORKING;AUTH_WINDOW_HARD_TTL_600S;WAITING_USER_NOT_INDEFINITE;PRE_REOPEN_CLOSE_OLD_FAMILY;PINNED_RAW_OR_LOCAL_LASTGOOD_IF_GITHUB_API_LIMITED;10M_MASKED_MULTI_MONITOR_CAPTURE;AC_REMOTE_PRESENT=>ES_SYSTEM_REQUIRED_ONLY;USER_NONAUTH_WINDOWS_PROTECTED;REMOTE_EXACT_REPAIR'
  googleControlPlane='DRIVE_RUNTIME_READBACK_EXISTING_AUTH';windowsExecutionIdentity='EXISTING_USER_TASK;NO_GOOGLE_PERMISSION_BYPASS'
}
$json=$out|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath $Receipt -Encoding UTF8
try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'CENTRAL_TAB_SUPERVISOR_LAST.json') -Encoding UTF8}}catch{}
$out|ConvertTo-Json -Depth 30 -Compress
if($out.ok){exit 0}else{exit 4}
