param(
  [string]$Title='2026-08-29 NotebookLM Fresh E2E 전체 산출물 검증',
  [string]$SourceText='2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 고유 마커 NLM_FRESH_ALL_20260829_1915.',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=90
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$NotebookHome='https://notebook.google.com/'
$Started=Get-Date
function Find-Chrome {
  if(Test-Path -LiteralPath $CftRoot){$x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1;if($x){return [string]$x.FullName}}
  foreach($c in @((Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))){if($c -and (Test-Path -LiteralPath $c)){return [string]$c}}
  throw 'CHROME_EXE_NOT_FOUND'
}
function Debug-Ready {try{$v=Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/version") -TimeoutSec 2;return [bool]$v.webSocketDebuggerUrl}catch{return $false}}
function Dedicated-Procs {try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$UserData*"})}catch{return @()}}
function Start-DebugChrome {
  if(Debug-Ready){return}
  foreach($p in @(Dedicated-Procs)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Milliseconds 700
  $chrome=Find-Chrome
  $args=@("--remote-debugging-port=$RemoteDebuggingPort",'--remote-allow-origins=*',"--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$NotebookHome)
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  $deadline=(Get-Date).AddSeconds(15);do{Start-Sleep -Milliseconds 400;if(Debug-Ready){return}}while((Get-Date)-lt $deadline)
  throw 'CDP_PORT_NOT_READY'
}
function Get-Tabs {return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3)}
function Get-PageTab {return @(Get-Tabs|Where-Object{[string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/*'}|Select-Object -First 1)[0]}
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws){$buf=New-Object byte[] 65536;$ms=New-Object IO.MemoryStream;try{do{$seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf);$res=$Ws.ReceiveAsync($seg,[Threading.CancellationToken]::None).GetAwaiter().GetResult();if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'};$ms.Write($buf,0,$res.Count)}while(-not $res.EndOfMessage);return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json}finally{$ms.Dispose()}}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){$Seq.Value++;$id=$Seq.Value;$json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes);$Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult();while($true){$msg=Receive-Cdp $Ws;if($msg.id -eq $id){if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))};return $msg.result}}}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){$r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click-Cdp($Ws,[ref]$Seq,[double]$X,[double]$Y){[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$X;y=$Y});[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mousePressed';x=$X;y=$Y;button='left';clickCount=1});Start-Sleep -Milliseconds 80;[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$X;y=$Y;button='left';clickCount=1})}
$result=[ordered]@{ok=$false;action='NOTEBOOKLM_FRESH_NOTEBOOK_CREATE_CDP_V1';title=$Title;startedAt=$Started.ToString('o');notebookUrl='';notebookId='';sourceAdded=$false;error=''}
$ws=$null
try{
  Start-DebugChrome;$deadline=(Get-Date).AddSeconds(20);$tab=$null;do{$tab=Get-PageTab;if($tab){break};Start-Sleep -Milliseconds 400}while((Get-Date)-lt $deadline);if(-not $tab){throw 'NOTEBOOK_HOME_TAB_NOT_FOUND'}
  $uri=[Uri]([string]$tab.webSocketDebuggerUrl);$ws=New-Object System.Net.WebSockets.ClientWebSocket;$ws.ConnectAsync($uri,[Threading.CancellationToken]::None).GetAwaiter().GetResult();$seq=0
  [void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{});Start-Sleep -Milliseconds 700
  $findCreate=@"
(() => { const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'}; for(const e of [...document.querySelectorAll('button,[role=button],a')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('새 노트북 만들기')||raw.includes('새 노트 만들기')||raw.includes('새로 만들기')||t.includes('create new notebook')||t.includes('new notebook')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,200)}}} return {ok:false,error:'CREATE_NEW_NOTEBOOK_CONTROL_NOT_FOUND'}; })()
"@
  $c=Eval-Cdp $ws ([ref]$seq) $findCreate;if(-not $c.ok){throw $c.error};Click-Cdp $ws ([ref]$seq) ([double]$c.x) ([double]$c.y)
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds);do{Start-Sleep -Milliseconds 500;$u=[string](Eval-Cdp $ws ([ref]$seq) 'location.href');if($u -match '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){break}}while((Get-Date)-lt $deadline)
  if($u -notmatch '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){throw 'FRESH_NOTEBOOK_URL_NOT_CREATED'}
  $result.notebookUrl=$u;$result.notebookId=$Matches[1]
  $titleJson=$Title|ConvertTo-Json -Compress
  $sourceJson=$SourceText|ConvertTo-Json -Compress
  $prep=@"
(async()=>{ const sleep=ms=>new Promise(r=>setTimeout(r,ms)); const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'}; const find=(words)=>[...document.querySelectorAll('button,[role=button],a,input,textarea,[contenteditable=true]')].filter(vis).find(e=>{const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title'),e.getAttribute('placeholder')].join(' ')).toLowerCase();return words.some(w=>raw.includes(w))}); const titleEl=find(['untitled notebook','제목 없는 노트북','제목 없는 노트']); if(titleEl){titleEl.click();await sleep(300); const inp=[...document.querySelectorAll('input,textarea,[contenteditable=true]')].filter(vis).find(e=>!String(e.getAttribute('placeholder')||'').toLowerCase().includes('search')); if(inp){inp.focus(); if('value' in inp) inp.value=$titleJson; else inp.textContent=$titleJson; inp.dispatchEvent(new Event('input',{bubbles:true})); inp.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',bubbles:true})); }} return {ok:true};})()
"@
  [void](Eval-Cdp $ws ([ref]$seq) $prep)
  $result.ok=$true
}catch{$result.error=$_.Exception.Message}
finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 20 -Compress
if($result.ok){exit 0}else{exit 2}
