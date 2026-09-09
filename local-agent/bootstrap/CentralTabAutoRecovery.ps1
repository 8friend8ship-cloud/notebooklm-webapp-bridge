param([string]$Reason='')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_TAB_AUTO_RECOVERY_V3_REMOTE_GUARD_CDP_ONLY_20260909'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
$RemoteGuard=Join-Path $Root 'DesktopCommanderKeepAlive.ps1'
$RemoteGuardReceipt=Join-Path $Root 'REMOTE_DC_KEEPALIVE_LAST.json'
$actions=@()
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
 try{$u='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Central-Recovery';'Accept'='application/vnd.github+json'} -TimeoutSec 20;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$sha=(GitBlob $b).ToLowerInvariant();if($sha-ne([string]$x.sha).ToLowerInvariant()){throw'SHA_MISMATCH'};$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,$b);Move-Item $tmp $Dest -Force;return $sha}catch{return ''}
}
$before=[ordered]@{host=(Test-Host);cdp=(Test-Cdp);remote=(Test-Remote)}
if(-not$before.host){
 try{$apply=Join-Path $Root 'Apply-EmbeddedHost129.ps1';$host=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.9.ps1';$rec=Join-Path $Root 'EMBEDDED_HOST129_CENTRAL_TAB_RECOVERY.json';if((Test-Path $apply)-and(Test-Path $host)){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $apply -HostPath $host -ReceiptPath $rec|Out-Null;$actions+='HOST129_RECOVERY_INVOKED'}else{$actions+='HOST129_RECOVERY_MISSING'}}catch{$actions+=('HOST129_RECOVERY_ERROR:'+$_.Exception.Message)}
}
if(-not$before.cdp){
 try{
  $chrome=Get-ChildItem -LiteralPath (Join-Path $Base 'ChromeForTesting') -Recurse -Filter chrome.exe -File -ErrorAction Stop|Sort-Object FullName -Descending|Select-Object -First 1
  if($chrome){
   $args=@("--user-data-dir=$(Join-Path $Base 'ChromeUserData')",'--profile-directory=Default','--remote-debugging-port=9224','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble','https://labs.google/fx/tools/flow')
   Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.DirectoryName|Out-Null
   $actions+='CFT_9224_CDP_ONLY_RECOVERY_INVOKED'
  }else{$actions+='CFT_9224_RECOVERY_MISSING'}
 }catch{$actions+=('CFT_9224_RECOVERY_ERROR:'+$_.Exception.Message)}
}
$remoteGuardExit=$null;$remoteGuardSha='';$remoteGuardStatus='NOT_NEEDED'
if((-not$before.remote)-or($Reason-match'(?i)REMOTE_DC|TRANSPORT|DATA_PLANE')){
 try{
  $remoteGuardSha=Refresh-Verified 'local-agent/bootstrap/DesktopCommanderKeepAlive.ps1' $RemoteGuard
  if($remoteGuardSha){$actions+=('REMOTE_GUARD_REFRESH:'+ $remoteGuardSha)}else{$actions+='REMOTE_GUARD_REFRESH_FAILED'}
  if(Test-Path $RemoteGuard){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $RemoteGuard|Out-Null;$remoteGuardExit=$LASTEXITCODE;$actions+=('REMOTE_GUARD_RUN_EXIT_'+$remoteGuardExit)}else{$actions+='REMOTE_GUARD_MISSING'}
  if(Test-Path $RemoteGuardReceipt){try{$g=Get-Content $RemoteGuardReceipt -Raw -Encoding UTF8|ConvertFrom-Json;$remoteGuardStatus=[string]$g.status}catch{$remoteGuardStatus='RECEIPT_PARSE_FAIL'}}
 }catch{$actions+=('REMOTE_GUARD_ERROR:'+$_.Exception.Message)}
}
Start-Sleep -Seconds 4
$cleanup=Join-Path $Root 'RunOwnedUiCleanup.ps1'
if(Test-Path $cleanup){try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cleanup|Out-Null;$actions+='CLEANUP_RERUN'}catch{$actions+=('CLEANUP_RERUN_ERROR:'+$_.Exception.Message)}}
$after=[ordered]@{host=(Test-Host);cdp=(Test-Cdp);remote=(Test-Remote)}
$out=[ordered]@{
 ok=[bool]($after.host-and$after.cdp-and$after.remote)
 version=$Version
 time=(Get-Date).ToString('o')
 reason=$Reason
 before=$before
 actions=$actions
 after=$after
 remoteGuardSha=$remoteGuardSha
 remoteGuardExit=$remoteGuardExit
 remoteGuardStatus=$remoteGuardStatus
 chrome137LoadExtensionRemoved=$true
 recoveryMode='CENTRAL_ROLE_ROUTE_HOST+DIRECT_CDP+REMOTE_TRANSPORT_GUARD+UI_CLEANUP'
 googleControlPlane='DRIVE_READBACK_EXISTING_USER_AUTH_ONLY;NO_NEW_OAUTH'
 windowsExecutionIdentity='EXISTING_USER_SCHEDULED_TASK;GOOGLE_AUTH_DOES_NOT_BYPASS_WINDOWS_PERMISSIONS'
}
$json=$out|ConvertTo-Json -Depth 30
$json|Set-Content -LiteralPath $Receipt -Encoding UTF8
try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'CENTRAL_TAB_RECOVERY_LAST.json') -Encoding UTF8}}catch{}
$out|ConvertTo-Json -Depth 30 -Compress
if($out.ok){exit 0}elseif($remoteGuardStatus-eq'HUMAN_GATE_REMOTE_DEVICE_AUTH'){exit 5}else{exit 4}
