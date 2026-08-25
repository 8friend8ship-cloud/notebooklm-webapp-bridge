$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$Front='https://notebooklm-webapp-bridge.vercel.app/'
$Port=9223

function DedicatedProcesses {
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*" })
  } catch { return @() }
}
function StopDedicated {
  foreach($p in @(DedicatedProcesses)) { try { Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue } catch {} }
  Start-Sleep -Seconds 2
}
function FindChrome {
  if(-not(Test-Path -LiteralPath $CftRoot)){ return $null }
  return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
}
function QuoteArgs([object[]]$Items){
  return (($Items | ForEach-Object { $s=[string]$_; if($s -match '[\s"]'){ '"'+($s -replace '"','\"')+'"' } else { $s } }) -join ' ')
}
function StartDiagnosticChrome([string]$ChromePath){
  $args=@(
    "--user-data-dir=$DedicatedUserData",
    '--profile-directory=Default',
    "--load-extension=$ExtensionRoot",
    "--remote-debugging-address=127.0.0.1",
    "--remote-debugging-port=$Port",
    '--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$Front
  )
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$ChromePath
  $psi.WorkingDirectory=(Split-Path $ChromePath -Parent)
  $psi.UseShellExecute=$false
  $psi.Arguments=QuoteArgs $args
  [void][Diagnostics.Process]::Start($psi)
}
function WaitJsonList {
  $deadline=(Get-Date).AddSeconds(15)
  do {
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2 } catch { Start-Sleep -Milliseconds 500 }
  } while((Get-Date) -lt $deadline)
  throw 'CDP_LIST_TIMEOUT'
}
function ReceiveCdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$WantedId,[int]$TimeoutSec=8){
  $deadline=(Get-Date).AddSeconds($TimeoutSec)
  $buf=New-Object byte[] 65536
  while((Get-Date) -lt $deadline){
    $seg=[ArraySegment[byte]]::new($buf)
    $cts=[Threading.CancellationTokenSource]::new()
    $cts.CancelAfter(1500)
    try {
      $ms=New-Object IO.MemoryStream
      do {
        $r=$Ws.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult()
        if($r.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close){ throw 'CDP_CLOSED' }
        if($r.Count -gt 0){ $ms.Write($buf,0,$r.Count) }
      } while(-not $r.EndOfMessage)
      $text=[Text.Encoding]::UTF8.GetString($ms.ToArray())
      $obj=$text | ConvertFrom-Json
      if($obj.id -eq $WantedId){ return $obj }
    } catch [OperationCanceledException] {} finally { $cts.Dispose() }
  }
  throw "CDP_RESPONSE_TIMEOUT_$WantedId"
}
function SendCdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$Id,[string]$Method,$Params){
  $payload=[ordered]@{id=$Id;method=$Method;params=$Params} | ConvertTo-Json -Depth 20 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
  $Ws.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
  return ReceiveCdp $Ws $Id
}

$result=[ordered]@{
  ok=$false; action='NOTEBOOKLM_AUTO_POLL_DIAGNOSTIC'; at=(Get-Date).ToString('o')
  bridgeVersion=''; dedicatedBefore=0; dedicatedAfter=0; normalChromeUntouched=$true
  serviceWorkerFound=$false; extensionId=''; config=$null; autoState=$null; sessionPresence=$null; alarms=$null; error=''
}
try {
  $manifestPath=Join-Path $ExtensionRoot 'manifest.json'
  if(Test-Path -LiteralPath $manifestPath){ try { $result.bridgeVersion=[string]((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).version) } catch {} }
  $before=@(DedicatedProcesses); $result.dedicatedBefore=$before.Count
  $chrome=FindChrome
  if(-not $chrome){ throw 'CFT_NOT_FOUND' }

  StopDedicated
  StartDiagnosticChrome $chrome.FullName
  $targets=WaitJsonList
  $sw=@($targets | Where-Object { $_.type -eq 'service_worker' -and $_.url -like 'chrome-extension://*/worker.js' } | Select-Object -First 1)
  if(-not $sw -or -not $sw[0].webSocketDebuggerUrl){
    Start-Sleep -Seconds 2
    $targets=WaitJsonList
    $sw=@($targets | Where-Object { $_.type -eq 'service_worker' -and $_.url -like 'chrome-extension://*/worker.js' } | Select-Object -First 1)
  }
  if(-not $sw -or -not $sw[0].webSocketDebuggerUrl){ throw 'EXTENSION_SERVICE_WORKER_NOT_FOUND' }
  $target=$sw[0]
  $result.serviceWorkerFound=$true
  if($target.url -match '^chrome-extension://([^/]+)/'){ $result.extensionId=$Matches[1] }

  $ws=[Net.WebSockets.ClientWebSocket]::new()
  try {
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    [void](SendCdp $ws 1 'Runtime.enable' @{})
    $expr=@'
(async()=>{
  const keys=['nlmBridgeConfig','nlmAutoRunnerStateV025','homeDesignBridgeSessionV7','nlmPersistentSessionV5'];
  const s=await chrome.storage.local.get(keys);
  const alarms=await chrome.alarms.getAll();
  const hasSession=(v)=>!!(typeof v==='string'?v:(v&&v.token));
  return {
    manifestVersion:chrome.runtime.getManifest().version,
    config:s.nlmBridgeConfig||null,
    autoState:s.nlmAutoRunnerStateV025||null,
    sessionPresence:{homeDesignBridgeSessionV7:hasSession(s.homeDesignBridgeSessionV7),nlmPersistentSessionV5:hasSession(s.nlmPersistentSessionV5)},
    alarms:alarms.map(a=>({name:a.name,periodInMinutes:a.periodInMinutes,scheduledTime:a.scheduledTime}))
  };
})()
'@
    $ev=SendCdp $ws 2 'Runtime.evaluate' @{expression=$expr;awaitPromise=$true;returnByValue=$true}
    $v=$ev.result.result.value
    $result.config=$v.config
    $result.autoState=$v.autoState
    $result.sessionPresence=$v.sessionPresence
    $result.alarms=$v.alarms
    if($v.manifestVersion){ $result.bridgeVersion=[string]$v.manifestVersion }
  } finally {
    try { $ws.Dispose() } catch {}
  }
  Start-Sleep -Seconds 2
  $result.dedicatedAfter=@(DedicatedProcesses).Count
  $result.ok=$true
} catch {
  $result.error=$_.Exception.Message
  $result.dedicatedAfter=@(DedicatedProcesses).Count
}
$result | ConvertTo-Json -Depth 30 -Compress
if($result.ok){ exit 0 } else { exit 2 }
