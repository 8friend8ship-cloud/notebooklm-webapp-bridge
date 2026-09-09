param([string]$Reason='')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CENTRAL_TAB_AUTO_RECOVERY_V2_CDP_ONLY_CHROME137_20260909'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'CENTRAL_TAB_RECOVERY_LAST.json'
$actions=@()
function Test-Host{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Test-Cdp{try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;return [bool]$v.Browser}catch{return $false}}
function Test-Remote{
 try{$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)desktop-commander'-and[string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'});if($p.Count-eq0){return $false};$ids=@($p.ProcessId);return (@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count-gt0)}catch{return $false}
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
if(-not$before.remote){
 try{
  $dc=Join-Path $Root 'DesktopCommanderKeepAlive.ps1'
  if(Test-Path $dc){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$dc) -WindowStyle Hidden|Out-Null;$actions+='REMOTE_DC_RECOVERY_TRIGGERED'}else{$actions+='REMOTE_DC_RECOVERY_MISSING'}
 }catch{$actions+=('REMOTE_DC_RECOVERY_ERROR:'+$_.Exception.Message)}
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
 chrome137LoadExtensionRemoved=$true
 recoveryMode='DIRECT_CDP_ONLY'
}
$out|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Receipt -Encoding UTF8
$out|ConvertTo-Json -Depth 20 -Compress
if($out.ok){exit 0}else{exit 4}
