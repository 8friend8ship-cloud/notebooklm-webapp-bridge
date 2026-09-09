param([switch]$SelfTestRecovery)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_AGENT_TAB_SUPERVISOR_V1_MIDCLEAN_VERIFY_RECOVER_20260909'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Cleanup=Join-Path $Root 'RunOwnedUiCleanup.ps1'
$Recovery=Join-Path $Root 'CentralTabAutoRecovery.ps1'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$Receipt=Join-Path $Root 'CENTRAL_TAB_SUPERVISOR_LAST.json'
$RecoveryReceipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
function Test-Host{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Test-Cdp{try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;return [bool]$v.Browser}catch{return $false}}
function Test-Remote{
 try{$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)desktop-commander'-and[string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'});if($p.Count-eq0){return $false};$ids=@($p.ProcessId);return (@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count-gt0)}catch{return $false}
}
function Find-Central{
 $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
 foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''
}
$started=(Get-Date).ToString('o')
$issues=New-Object System.Collections.Generic.List[string]
$cleanupObj=$null;$cleanupExit=9;$cleanupRaw=''
if(Test-Path $Cleanup){
 try{$cleanupRaw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Cleanup 2>&1|Out-String;$cleanupExit=$LASTEXITCODE;$cleanupObj=$cleanupRaw|ConvertFrom-Json}catch{$issues.Add('CLEANUP_PARSE_OR_EXEC_ERROR')}
}else{$issues.Add('CLEANUP_MISSING')}
if(-not$cleanupObj){$issues.Add('CLEANUP_NO_READBACK')}
elseif(-not[bool]$cleanupObj.ok){$issues.Add('CLEANUP_NOT_OK')}
elseif([string]$cleanupObj.version-notmatch'AUTH_DEDUP_MULTI_HWND'){ $issues.Add('CLEANUP_VERSION_MISMATCH') }
$registryCount=0;$registryOk=$true
try{$r=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;$registryCount=@($r).Count}catch{$registryOk=$false;$issues.Add('REGISTRY_PARSE_FAIL')}
$hostOk=Test-Host;$cdpOk=Test-Cdp;$remoteOk=Test-Remote
if(-not$hostOk){$issues.Add('LOCAL_HOST_DOWN')}
if(-not$cdpOk){$issues.Add('CFT_CDP_9224_DOWN')}
if(-not$remoteOk){$issues.Add('REMOTE_DC_OFFLINE')}
$authDupRemain=$false
if($cleanupObj -and $cleanupObj.authActions){
 foreach($a in @($cleanupObj.authActions)){if([int]$a.found-gt1-and[int]$a.closed-eq0-and[string]$a.action-notmatch'PROTECT_WAITING_USER'){ $authDupRemain=$true }}
}
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
$out=[ordered]@{
 ok=[bool]($issues.Count-eq0)
 version=$Version
 startedAt=$started
 completedAt=(Get-Date).ToString('o')
 phase='MID_CLEAN_VERIFY_RECOVER'
 cleanupExit=$cleanupExit
 cleanupVersion=$(if($cleanupObj){[string]$cleanupObj.version}else{''})
 cleanupClosed=$(if($cleanupObj){[int]$cleanupObj.closedCount}else{-1})
 registryOk=$registryOk
 registryCount=$registryCount
 hostOk=$hostOk
 cdp9224Ok=$cdpOk
 remoteDcOk=$remoteOk
 authDuplicateRemains=$authDupRemain
 issues=@($issues)
 recoveryTriggered=$recoveryTriggered
 recoveryExit=$recoveryExit
 recoveryCooldown=$recoveryCooldown
 policy='5M_MIDCLEAN;WAITING_USER_KEEP;KEEP_OPEN_KEEP;USER_CHROME_KEEP;COMPLETED_ACK_CLOSE;AUTH_DEDUP;HWND_READBACK;AUTO_RECOVERY'
}
$json=$out|ConvertTo-Json -Depth 30
$json|Set-Content -LiteralPath $Receipt -Encoding UTF8
try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'CENTRAL_TAB_SUPERVISOR_LAST.json') -Encoding UTF8}}catch{}
$out|ConvertTo-Json -Depth 30 -Compress
if($out.ok){exit 0}else{exit 4}
