param(
  [string]$TaskId = 'NLM_VIEW_SEED_CAPTURE',
  [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [Parameter(Mandatory=$true)][string]$ArtifactLabel,
  [string]$ArtifactType='GENERIC_VIEW',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=60,
  [string]$CentralRootOverride='G:\내 드라이브'
)
$ErrorActionPreference='Stop'

function Get-Tabs { @(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3) }
function Get-NotebookTab { @(Get-Tabs | Where-Object { [string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/notebook/*' } | Select-Object -First 1) }
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws){$buf=New-Object byte[] 65536;$ms=New-Object IO.MemoryStream;try{do{$seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf);$res=$Ws.ReceiveAsync($seg,[Threading.CancellationToken]::None).GetAwaiter().GetResult();if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'};$ms.Write($buf,0,$res.Count)}while(-not $res.EndOfMessage);return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json}finally{$ms.Dispose()}}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){$Seq.Value++;$id=$Seq.Value;$json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes);$Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult();while($true){$msg=Receive-Cdp $Ws;if($msg.id -eq $id){if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))};return $msg.result}}}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){$r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click-Cdp($Ws,[ref]$Seq,[double]$X,[double]$Y){[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$X;y=$Y});[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mousePressed';x=$X;y=$Y;button='left';clickCount=1});Start-Sleep -Milliseconds 70;[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$X;y=$Y;button='left';clickCount=1})}

$tab = @(Get-NotebookTab)
if ($tab.Count -lt 1) { throw 'NOTEBOOK_TAB_NOT_FOUND' }
$wsUri = [string]$tab[0].webSocketDebuggerUrl
if (-not $wsUri) { throw 'NOTEBOOK_CDP_WEBSOCKET_NOT_FOUND' }
$ws=New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]$wsUri,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
$seq=0
try {
  [void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{})
  [void](Send-Cdp $ws ([ref]$seq) 'Page.enable' @{})
  [void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{})
  $labelJson=$ArtifactLabel|ConvertTo-Json -Compress
  $find=@"
(() => { const wanted=String($labelJson).toLowerCase(); const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'}; const roots=[document],seen=new Set(roots);for(let i=0;i<roots.length;i++){for(const e of roots[i].querySelectorAll?.('*')||[]){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot)}}} const candidates=[];for(const r of roots){for(const e of r.querySelectorAll?.('button,[role=button],article,section,div')||[]){if(!vis(e))continue;const t=String(e.innerText||e.textContent||'').trim();if(t&&t.toLowerCase().includes(wanted)){const q=e.getBoundingClientRect();candidates.push({e,t,len:t.length,x:q.left+q.width/2,y:q.top+q.height/2})}}} candidates.sort((a,b)=>a.len-b.len); if(!candidates.length)return {ok:false,error:'ARTIFACT_VIEW_TARGET_NOT_FOUND'}; const c=candidates[0]; return {ok:true,x:c.x,y:c.y,text:c.t.slice(0,500)}; })()
"@
  $target=Eval-Cdp $ws ([ref]$seq) $find
  if(-not $target.ok){throw $target.error}
  Click-Cdp $ws ([ref]$seq) ([double]$target.x) ([double]$target.y)
  Start-Sleep -Seconds 2
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
  $view=$null
  do {
    $view=Eval-Cdp $ws ([ref]$seq) "(() => ({url:location.href,title:document.title,text:String(document.body?.innerText||'').slice(0,50000),w:innerWidth,h:innerHeight,ready:document.readyState}))()"
    if($view -and $view.ready -eq 'complete'){break}
    Start-Sleep -Milliseconds 500
  } while((Get-Date)-lt $deadline)
  $shot=Send-Cdp $ws ([ref]$seq) 'Page.captureScreenshot' @{format='png';fromSurface=$true;captureBeyondViewport=$false}
  if(-not $shot.data){throw 'SEED_SCREENSHOT_CAPTURE_EMPTY'}
  $seedDir=Join-Path $CentralRootOverride 'NotebookLM_SeedCaptures'
  New-Item -ItemType Directory -Path $seedDir -Force | Out-Null
  $safeType=($ArtifactType -replace '[^A-Za-z0-9_-]','_')
  $base=Join-Path $seedDir ($TaskId+'__'+$safeType)
  $png=$base+'.png';$txt=$base+'.txt';$json=$base+'.capture.json'
  [IO.File]::WriteAllBytes($png,[Convert]::FromBase64String([string]$shot.data))
  [IO.File]::WriteAllText($txt,[string]$view.text,[Text.UTF8Encoding]::new($false))
  $meta=[ordered]@{schemaVersion='notebooklm-url-first-seed-v1';taskId=$TaskId;artifactType=$ArtifactType;artifactLabel=$ArtifactLabel;sourceNotebookUrl=$NotebookUrl;resolvedViewUrl=[string]$view.url;pageTitle=[string]$view.title;status='SEED_CAPTURE_READY';captureMode='NOTEBOOKLM_OPEN_VIEW';originalBinaryRequiredForSeed=$false;driveMirrorStatus='PENDING';sourceAssetPreserved=$true;screenshotPath=$png;textPath=$txt;capturedAt=(Get-Date).ToString('o')}
  [IO.File]::WriteAllText($json,($meta|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{ok=$true;action='NOTEBOOKLM_URL_FIRST_SEED_CAPTURE_V1';taskId=$TaskId;artifactType=$ArtifactType;resolvedViewUrl=[string]$view.url;screenshotPath=$png;textPath=$txt;sidecarPath=$json;driveMirrorStatus='PENDING';completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 20 -Compress
} finally { try{$ws.Dispose()}catch{} }
