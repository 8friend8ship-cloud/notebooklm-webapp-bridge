param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.136'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$Port=9223
$Front='https://notebooklm-webapp-bridge.vercel.app/'
$NotebookHome='https://notebook.google.com/'
$ReceiptName='AGENT_1.1.136_NOTEBOOKLM_RUNTIME_RESTART_RESULT.json'
$ReceiptPath=Join-Path $Root $ReceiptName
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function FindCentral {
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $centralName),(Join-Path $d.Root ('My Drive\'+$centralName)),(Join-Path $d.Root ($myDriveKo+'\'+$centralName)),(Join-Path $d.Root ('Google Drive\'+$centralName)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveReceipt($o){
  $json=$o|ConvertTo-Json -Depth 40
  $json|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
  try{
    $central=FindCentral
    if($central){
      $dir=Join-Path $central 'Runtime_Readback'
      New-Item -ItemType Directory -Force -Path $dir|Out-Null
      $json|Set-Content -LiteralPath (Join-Path $dir $ReceiptName) -Encoding UTF8
    }
  }catch{}
}
function DedicatedProcesses {
  try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"})}catch{return @()}
}
function StopDedicated {
  foreach($p in @(DedicatedProcesses)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Seconds 2
}
function FindChrome {
  if(-not(Test-Path -LiteralPath $CftRoot -PathType Container)){return $null}
  return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s-match'[\s"]'){'"'+($s-replace'"','\"')+'"'}else{$s}})-join' ')}
function StartDedicated([string]$ChromePath){
  $args=@(
    "--user-data-dir=$DedicatedUserData",
    '--profile-directory=Default',
    "--load-extension=$ExtensionRoot",
    '--remote-debugging-address=127.0.0.1',
    "--remote-debugging-port=$Port",
    '--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',
    $Front,$NotebookHome
  )
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$ChromePath
  $psi.WorkingDirectory=(Split-Path $ChromePath -Parent)
  $psi.UseShellExecute=$false
  $psi.Arguments=QuoteArgs $args
  [void][Diagnostics.Process]::Start($psi)
}
function WaitTargets([int]$Seconds=25){
  $deadline=(Get-Date).AddSeconds($Seconds)
  do{try{return @(Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2)}catch{Start-Sleep -Milliseconds 500}}while((Get-Date)-lt$deadline)
  throw 'CDP_LIST_TIMEOUT'
}
function ReceiveCdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$WantedId,[int]$TimeoutSec=10){
  $deadline=(Get-Date).AddSeconds($TimeoutSec);$buf=New-Object byte[] 65536
  while((Get-Date)-lt$deadline){
    $seg=[ArraySegment[byte]]::new($buf);$cts=[Threading.CancellationTokenSource]::new();$cts.CancelAfter(1500)
    try{
      $ms=New-Object IO.MemoryStream
      do{$r=$Ws.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult();if($r.MessageType-eq[Net.WebSockets.WebSocketMessageType]::Close){throw'CDP_CLOSED'};if($r.Count-gt0){$ms.Write($buf,0,$r.Count)}}while(-not$r.EndOfMessage)
      $obj=([Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json)
      if($obj.id-eq$WantedId){return $obj}
    }catch[OperationCanceledException]{}finally{$cts.Dispose()}
  }
  throw "CDP_RESPONSE_TIMEOUT_$WantedId"
}
function SendCdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$Id,[string]$Method,$Params){
  $payload=[ordered]@{id=$Id;method=$Method;params=$Params}|ConvertTo-Json -Depth 20 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
  $Ws.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null
  return ReceiveCdp $Ws $Id
}
function HostHealth {
  try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [pscustomobject]@{ok=[bool]$h.ok;version=[string]$h.version}}catch{return [pscustomobject]@{ok=$false;version=''}}
}

$started=Get-Date
$r=[ordered]@{
  ok=$false;action='NOTEBOOKLM_RUNTIME_RESTART';version=$Version;startedAt=$started.ToString('o');stage='START';
  dedicatedBefore=0;dedicatedAfter=0;chromePath='';bridgeVersion='';hostHealthyBefore=$false;hostVersionBefore='';hostHealthyAfter=$false;hostVersionAfter='';
  serviceWorkerReady=$false;notebookTargetReady=$false;frontTargetReady=$false;extensionId='';sessionPresent=$false;alarmReady=$false;pollInvoked=$false;pollResult=$null;
  normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;extensionFilesChanged=$false;error=''
}
try{
  $r.stage='PRECHECK'
  $manifest=Join-Path $ExtensionRoot 'manifest.json'
  if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'NOTEBOOKLM_EXTENSION_MISSING'}
  try{$r.bridgeVersion=[string]((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json).version)}catch{}
  $chrome=FindChrome
  if(-not$chrome){throw 'CHROME_FOR_TESTING_NOT_FOUND'}
  $r.chromePath=$chrome.FullName
  $r.dedicatedBefore=@(DedicatedProcesses).Count
  $hh=HostHealth;$r.hostHealthyBefore=$hh.ok;$r.hostVersionBefore=$hh.version

  $r.stage='RESTART_DEDICATED_NOTEBOOKLM_CHROME'
  StopDedicated
  StartDedicated $chrome.FullName
  $targets=WaitTargets 25
  $r.dedicatedAfter=@(DedicatedProcesses).Count
  $r.notebookTargetReady=[bool](@($targets|Where-Object{$_.type-eq'page'-and($_.url-like'https://notebook.google.com/*'-or$_.url-like'https://notebooklm.google.com/*')}).Count-gt0)
  $r.frontTargetReady=[bool](@($targets|Where-Object{$_.type-eq'page'-and$_.url-like'https://notebooklm-webapp-bridge.vercel.app/*'}).Count-gt0)
  $sw=@($targets|Where-Object{$_.type-eq'service_worker'-and$_.url-like'chrome-extension://*/worker.js'}|Select-Object -First 1)
  if(-not$sw -or -not$sw[0].webSocketDebuggerUrl){Start-Sleep -Seconds 2;$targets=WaitTargets 10;$sw=@($targets|Where-Object{$_.type-eq'service_worker'-and$_.url-like'chrome-extension://*/worker.js'}|Select-Object -First 1)}
  if(-not$sw -or -not$sw[0].webSocketDebuggerUrl){throw 'NOTEBOOKLM_SERVICE_WORKER_NOT_FOUND'}
  $r.serviceWorkerReady=$true
  if($sw[0].url-match'^chrome-extension://([^/]+)/'){$r.extensionId=$Matches[1]}

  $r.stage='VERIFY_WORKER_AND_WAKE_POLL'
  $ws=[Net.WebSockets.ClientWebSocket]::new()
  try{
    $ws.ConnectAsync([Uri]$sw[0].webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    [void](SendCdp $ws 1 'Runtime.enable' @{})
    $expr=@'
(async()=>{
  const keys=['homeDesignBridgeSessionV7','nlmPersistentSessionV5'];
  const s=await chrome.storage.local.get(keys);
  const has=(v)=>!!(typeof v==='string'?v:(v&&v.token));
  if(typeof ensureAutoAlarm==='function') await ensureAutoAlarm();
  let poll=null;
  if(typeof pollReadyTasks==='function') poll=await pollReadyTasks('stable-runtime-restart-1.1.136');
  const alarms=await chrome.alarms.getAll();
  return {manifestVersion:chrome.runtime.getManifest().version,sessionPresent:has(s.homeDesignBridgeSessionV7)||has(s.nlmPersistentSessionV5),alarms:alarms.map(a=>({name:a.name,periodInMinutes:a.periodInMinutes})),poll};
})()
'@
    $ev=SendCdp $ws 2 'Runtime.evaluate' @{expression=$expr;awaitPromise=$true;returnByValue=$true}
    $v=$ev.result.result.value
    if($v.manifestVersion){$r.bridgeVersion=[string]$v.manifestVersion}
    $r.sessionPresent=[bool]$v.sessionPresent
    $r.alarmReady=[bool](@($v.alarms|Where-Object{$_.name-eq'nlm-auto-ready-poll'}).Count-gt0)
    $r.pollInvoked=$true;$r.pollResult=$v.poll
  }finally{try{$ws.Dispose()}catch{}}
  $hh2=HostHealth;$r.hostHealthyAfter=$hh2.ok;$r.hostVersionAfter=$hh2.version
  if($r.dedicatedAfter-lt1){throw 'DEDICATED_CHROME_NOT_RUNNING'}
  if(-not$r.notebookTargetReady){throw 'NOTEBOOKLM_PAGE_TARGET_NOT_READY'}
  if(-not$r.serviceWorkerReady){throw 'NOTEBOOKLM_SERVICE_WORKER_NOT_READY'}
  if(-not$r.alarmReady){throw 'NOTEBOOKLM_AUTO_POLL_ALARM_NOT_READY'}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');SaveReceipt $r}
$r|ConvertTo-Json -Depth 40 -Compress
if($r.ok){exit 0}else{exit 2}
