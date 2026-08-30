param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.99'
$Port=9223
$ExpectedBridge='0.2.39'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root | Out-Null
function FindCentral {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root
    if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveCentral([string]$Name,$Object){
  try{
    $j=$Object | ConvertTo-Json -Depth 60
    $j | Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8
    $c=FindCentral
    if($c){
      $d=Join-Path $c 'Runtime_Readback'
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      $p=Join-Path $d $Name
      $j | Set-Content -LiteralPath $p -Encoding UTF8
      return $p
    }
  }catch{}
  return ''
}
function Targets {
  $r=Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 4
  $o=$r.Content | ConvertFrom-Json
  $a=@()
  if($o -is [System.Array]){foreach($x in $o){$a += $x}}
  elseif($null -ne $o){$a += $o}
  return $a
}
function Recv($w,[int]$wanted,[int]$sec=8){
  $deadline=(Get-Date).AddSeconds($sec)
  $buf=New-Object byte[] 65536
  while((Get-Date) -lt $deadline){
    $seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf)
    $cts=New-Object Threading.CancellationTokenSource
    $cts.CancelAfter(1500)
    try{
      $ms=New-Object IO.MemoryStream
      do{
        $r=$w.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult()
        if($r.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'}
        if($r.Count -gt 0){$ms.Write($buf,0,$r.Count)}
      }while(-not $r.EndOfMessage)
      $obj=([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
      if($obj.id -eq $wanted){return $obj}
    }catch [OperationCanceledException] {}
    finally{$cts.Dispose()}
  }
  throw ('CDP_RESPONSE_TIMEOUT_'+$wanted)
}
function Send($w,[int]$id,[string]$method,$params){
  $payload=[ordered]@{id=$id;method=$method;params=$params} | ConvertTo-Json -Depth 30 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
  $seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
  [void]$w.SendAsync($seg,[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
  return Recv $w $id 8
}
$result=[ordered]@{
  ok=$false
  action='AGENT_1.1.99_WAKE_EXISTING_NOTEBOOKLM_AUTO_POLL_ONCE'
  version=$Version
  startedAt=(Get-Date).ToString('o')
  bridgeVersion=''
  extensionId=''
  serviceWorkerFound=$false
  autoStateBefore=$null
  dispatchAccepted=$false
  wakeKey='nlmManualAutoPollWakeV1'
  normalChromeTouched=$false
  bridgeChanged=$false
  oauthChanged=$false
  scopeChanged=$false
  queueTaskCreated=$false
  error=''
  centralPath=''
}
$ws=$null
try{
  $targets=@(Targets)
  $sw=@($targets | Where-Object {[string]$_.type -eq 'service_worker' -and [string]$_.url -like 'chrome-extension://*/worker.js'} | Select-Object -First 1)
  if(-not $sw -or -not $sw[0].webSocketDebuggerUrl){throw 'NOTEBOOKLM_SERVICE_WORKER_NOT_FOUND'}
  $result.serviceWorkerFound=$true
  if([string]$sw[0].url -match '^chrome-extension://([^/]+)/'){$result.extensionId=$Matches[1]}
  [Net.WebSockets.ClientWebSocket]$ws=New-Object Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]([string]$sw[0].webSocketDebuggerUrl),[Threading.CancellationToken]::None).GetAwaiter().GetResult()
  [void](Send $ws 1 'Runtime.enable' @{})
  $expr=@'
(async()=>{
  const source='notebooklm-webapp-bridge';
  const key='nlmManualAutoPollWakeV1';
  const stored=await chrome.storage.local.get(['nlmAutoRunnerStateV025']);
  const before=stored.nlmAutoRunnerStateV025||null;
  const version=chrome.runtime.getManifest().version;
  const at=new Date().toISOString();
  chrome.runtime.sendMessage({source,type:'RUN_AUTO_POLL'})
    .then(async response=>{
      const receipt={at,completedAt:new Date().toISOString(),ok:!!response?.ok,response:response||null,error:''};
      try{await chrome.storage.local.set({[key]:receipt});}catch{}
    })
    .catch(async error=>{
      const receipt={at,completedAt:new Date().toISOString(),ok:false,response:null,error:String(error?.message||error)};
      try{await chrome.storage.local.set({[key]:receipt});}catch{}
    });
  return {dispatched:true,version,before,key};
})()
'@
  $ev=Send $ws 2 'Runtime.evaluate' @{expression=$expr;awaitPromise=$true;returnByValue=$true;userGesture=$true}
  $v=$ev.result.result.value
  $result.bridgeVersion=[string]$v.version
  $result.autoStateBefore=$v.before
  $result.dispatchAccepted=[bool]$v.dispatched
  if($result.bridgeVersion -ne $ExpectedBridge){throw ('BRIDGE_VERSION_MISMATCH expected='+$ExpectedBridge+' actual='+$result.bridgeVersion)}
  if(-not $result.dispatchAccepted){throw 'AUTO_POLL_DISPATCH_NOT_ACCEPTED'}
  $result.ok=$true
}catch{
  $result.error=$_.Exception.Message
}
finally{
  if($ws){try{$ws.Dispose()}catch{}}
  $result.completedAt=(Get-Date).ToString('o')
  $result.centralPath=SaveCentral 'AGENT_1.1.99_WAKE_EXISTING_NOTEBOOKLM_AUTO_POLL_ONCE_RESULT.json' $result
}
$result | ConvertTo-Json -Depth 60 -Compress
if($result.ok){exit 0}else{exit 2}
