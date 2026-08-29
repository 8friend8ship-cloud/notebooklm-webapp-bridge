param(
  [string]$Title='2026-08-29 NotebookLM Fresh E2E 전체 산출물 검증',
  [string]$SourceText='2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 고유 마커: NLM_FRESH_ALL_20260829_1915.',
  [string]$ExpectedOldNotebookId='69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=120,
  [int]$CdpCommandTimeoutSeconds=8
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$NotebookHome='https://notebook.google.com/'
$Started=Get-Date
$Marker='NLM_FRESH_ALL_20260829_1915'

function Find-Chrome {
  if(Test-Path -LiteralPath $CftRoot){
    $x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
    if($x){return [string]$x.FullName}
  }
  foreach($c in @((Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))){
    if($c -and (Test-Path -LiteralPath $c)){return [string]$c}
  }
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
  $deadline=(Get-Date).AddSeconds(20)
  do{Start-Sleep -Milliseconds 400;if(Debug-Ready){return}}while((Get-Date)-lt $deadline)
  throw 'CDP_PORT_NOT_READY'
}
function Get-Tabs {return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3)}
function Get-NotebookTabs {
  $all=@(Get-Tabs)
  return @($all|Where-Object{[string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/*'})
}
function Get-ScalarTab([object[]]$Tabs){if($Tabs -and $Tabs.Count -gt 0){return $Tabs[0]};return $null}
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$Seconds){
  $buf=New-Object byte[] 65536
  $ms=New-Object IO.MemoryStream
  $cts=New-Object Threading.CancellationTokenSource
  $cts.CancelAfter([Math]::Max(1000,$Seconds*1000))
  try{
    do{
      $seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf)
      try{$res=$Ws.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult()}catch{throw 'CDP_RECEIVE_TIMEOUT_OR_CLOSED'}
      if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'}
      $ms.Write($buf,0,$res.Count)
    }while(-not $res.EndOfMessage)
    return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json
  }finally{$cts.Dispose();$ms.Dispose()}
}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){
  $Seq.Value++;$id=$Seq.Value
  $json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
  $cts=New-Object Threading.CancellationTokenSource
  $cts.CancelAfter([Math]::Max(1000,$CdpCommandTimeoutSeconds*1000))
  try{$Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$cts.Token).GetAwaiter().GetResult()}catch{throw ('CDP_SEND_TIMEOUT '+$Method)}finally{$cts.Dispose()}
  while($true){
    $msg=Receive-Cdp $Ws $CdpCommandTimeoutSeconds
    if($msg.id -eq $id){
      if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))}
      return $msg.result
    }
  }
}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){$r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click-Cdp($Ws,[ref]$Seq,[double]$X,[double]$Y){
  [void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$X;y=$Y})
  [void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mousePressed';x=$X;y=$Y;button='left';clickCount=1})
  Start-Sleep -Milliseconds 100
  [void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$X;y=$Y;button='left';clickCount=1})
}
function Connect-Tab($Tab){
  $wsUrl=[string]$Tab.webSocketDebuggerUrl
  if(-not $wsUrl){throw 'TAB_WEBSOCKET_URL_MISSING'}
  $uri=New-Object System.Uri($wsUrl)
  $ws=New-Object System.Net.WebSockets.ClientWebSocket
  $cts=New-Object Threading.CancellationTokenSource
  $cts.CancelAfter([Math]::Max(1000,$CdpCommandTimeoutSeconds*1000))
  try{$ws.ConnectAsync($uri,$cts.Token).GetAwaiter().GetResult()}catch{$ws.Dispose();throw 'CDP_CONNECT_TIMEOUT_OR_FAILED'}finally{$cts.Dispose()}
  return $ws
}
function Parse-NotebookId([string]$Url){if($Url -match '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){return [string]$Matches[1]};return ''}

$result=[ordered]@{ok=$false;action='NOTEBOOKLM_FRESH_NOTEBOOK_CREATE_SOURCE_CDP_V3';title=$Title;startedAt=$Started.ToString('o');notebookUrl='';notebookId='';previousNotebookId=$ExpectedOldNotebookId;freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;marker=$Marker;adoptedExistingFreshTab=$false;error='';stage='START';evidence=@{}}
$ws=$null
try{
  Start-DebugChrome
  $result.stage='TAB_DISCOVERY'
  $tabs=@(Get-NotebookTabs)
  if(-not $tabs -or $tabs.Count -eq 0){throw 'NOTEBOOK_TAB_NOT_FOUND'}

  $candidate=$null
  $freshTabs=@($tabs|Where-Object{(Parse-NotebookId ([string]$_.url)) -and (Parse-NotebookId ([string]$_.url)) -ne $ExpectedOldNotebookId})
  if($freshTabs.Count -eq 1){$candidate=$freshTabs[0];$result.adoptedExistingFreshTab=$true}
  elseif($freshTabs.Count -gt 1){
    foreach($t in $freshTabs){
      $probe=$null
      try{$probe=Connect-Tab $t;$s=0;[void](Send-Cdp $probe ([ref]$s) 'Runtime.enable' @{});$body=[string](Eval-Cdp $probe ([ref]$s) 'document.body ? document.body.innerText : ""');if($body -like "*$Marker*" -or $body -like "*$Title*"){$candidate=$t;break}}catch{}finally{if($probe){try{$probe.Dispose()}catch{}}}
    }
    if(-not $candidate){throw 'AMBIGUOUS_MULTIPLE_FRESH_NOTEBOOK_TABS'}
    $result.adoptedExistingFreshTab=$true
  }

  if($candidate){
    $result.notebookUrl=[string]$candidate.url;$result.notebookId=Parse-NotebookId $result.notebookUrl;$result.freshNotebook=$true
    $ws=Connect-Tab $candidate;$seq=0;[void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{})
  }else{
    $homeTabs=@($tabs|Where-Object{[string]$_.url -eq $NotebookHome -or [string]$_.url -eq 'https://notebook.google.com/'})
    $tab=Get-ScalarTab $homeTabs
    if(-not $tab){$tab=Get-ScalarTab $tabs}
    if(-not $tab){throw 'NOTEBOOK_HOME_TAB_NOT_FOUND'}
    $ws=Connect-Tab $tab;$seq=0;[void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{})
    [void](Send-Cdp $ws ([ref]$seq) 'Page.navigate' @{url=$NotebookHome});Start-Sleep -Seconds 2
    $result.stage='CREATE_CONTROL'
    $findCreate="(() => { const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0}; const els=[...document.querySelectorAll('button,[role=button],a')].filter(vis); for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('노트북 만들기')||raw.includes('새 노트북')||raw.includes('새 노트 만들기')||t.includes('create new notebook')||t.includes('new notebook')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,200)}}} return {ok:false,error:'CREATE_NEW_NOTEBOOK_CONTROL_NOT_FOUND',sample:document.body.innerText.slice(0,1200)}; })()"
    $c=Eval-Cdp $ws ([ref]$seq) $findCreate
    if(-not $c.ok){throw ($c.error+': '+[string]$c.sample)}
    $result.evidence.createControl=[string]$c.text
    Click-Cdp $ws ([ref]$seq) ([double]$c.x) ([double]$c.y)
    $result.stage='WAIT_FRESH_URL'
    $deadline=(Get-Date).AddSeconds([Math]::Min(45,$TimeoutSeconds));$u=''
    do{Start-Sleep -Milliseconds 400;$u=[string](Eval-Cdp $ws ([ref]$seq) 'location.href');if(Parse-NotebookId $u){break}}while((Get-Date)-lt $deadline)
    $id=Parse-NotebookId $u
    if(-not $id){throw 'FRESH_NOTEBOOK_URL_NOT_CREATED'}
    if($id -eq $ExpectedOldNotebookId){throw 'OLD_NOTEBOOK_REUSED'}
    $result.notebookUrl=$u;$result.notebookId=$id;$result.freshNotebook=$true
  }

  $result.stage='SOURCE_VERIFY_OR_ADD'
  Start-Sleep -Seconds 2
  $markerJson=$Marker|ConvertTo-Json -Compress
  $hasMarker=[bool](Eval-Cdp $ws ([ref]$seq) "document.body && document.body.innerText.includes($markerJson)")
  if($hasMarker){$result.sourceAdded=$true;$result.sourceVerified=$true}
  else{
    $findAdd="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('button,[role=button],a')].filter(vis);for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('소스 추가')||t.includes('add source')||t.includes('add sources')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}const body=document.body.innerText;return {ok:false,dialogOpen:/복사한 텍스트|copied text|paste text/i.test(body),sample:body.slice(0,1200)};})()"
    $a=Eval-Cdp $ws ([ref]$seq) $findAdd
    if($a.ok){Click-Cdp $ws ([ref]$seq) ([double]$a.x) ([double]$a.y);Start-Sleep -Milliseconds 900}elseif(-not $a.dialogOpen){throw ('ADD_SOURCE_CONTROL_NOT_FOUND: '+[string]$a.sample)}
    $findCopied="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('button,[role=button],a,div[tabindex]')].filter(vis);for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('복사한 텍스트')||raw.includes('텍스트 붙여넣기')||t.includes('copied text')||t.includes('paste text')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,sample:document.body.innerText.slice(0,1400)};})()"
    $cp=Eval-Cdp $ws ([ref]$seq) $findCopied
    if(-not $cp.ok){throw ('COPIED_TEXT_SOURCE_CONTROL_NOT_FOUND: '+[string]$cp.sample)}
    Click-Cdp $ws ([ref]$seq) ([double]$cp.x) ([double]$cp.y);Start-Sleep -Milliseconds 800
    $sourceJson=$SourceText|ConvertTo-Json -Compress
    $fill="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('textarea,[contenteditable=true],input:not([type=hidden])')].filter(vis);const e=all.find(x=>x.tagName==='TEXTAREA')||all.find(x=>x.getAttribute('contenteditable')==='true')||all.find(x=>/텍스트|text|paste|붙여넣/i.test(String(x.getAttribute('placeholder')||'')));if(!e)return {ok:false,error:'PASTED_TEXT_EDITOR_NOT_FOUND',sample:document.body.innerText.slice(0,1200)};e.focus();if('value' in e){const p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;if(s)s.call(e,$sourceJson);else e.value=$sourceJson;}else{e.textContent=$sourceJson;}e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:$sourceJson}));e.dispatchEvent(new Event('change',{bubbles:true}));return {ok:true};})()"
    $fl=Eval-Cdp $ws ([ref]$seq) $fill
    if(-not $fl.ok){throw ($fl.error+': '+[string]$fl.sample)}
    $findSubmit="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled};const els=[...document.querySelectorAll('button,[role=button]')].filter(vis);const exact=['삽입','추가','저장','insert','add','save'];for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).trim();const t=raw.toLowerCase().replace(/\s+/g,' ');if(exact.some(w=>t===w||t.startsWith(w+' '))){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,sample:els.map(e=>String([e.innerText,e.getAttribute('aria-label')].join(' ')).trim()).filter(Boolean).slice(-25)};})()"
    $sb=Eval-Cdp $ws ([ref]$seq) $findSubmit
    if(-not $sb.ok){throw ('SOURCE_SUBMIT_CONTROL_NOT_FOUND: '+(($sb.sample|ConvertTo-Json -Compress)))}
    Click-Cdp $ws ([ref]$seq) ([double]$sb.x) ([double]$sb.y)
    $result.sourceAdded=$true
    $verifyDeadline=(Get-Date).AddSeconds([Math]::Min(30,$TimeoutSeconds))
    do{Start-Sleep -Milliseconds 700;$hasMarker=[bool](Eval-Cdp $ws ([ref]$seq) "document.body && document.body.innerText.includes($markerJson)");if($hasMarker){break}}while((Get-Date)-lt $verifyDeadline)
    $result.sourceVerified=$hasMarker
  }
  $result.ok=($result.freshNotebook -and $result.sourceAdded -and $result.sourceVerified -and $result.notebookId -ne $ExpectedOldNotebookId)
  $result.stage=if($result.ok){'PASS'}else{'GATE_FAIL'}
  if(-not $result.ok){throw 'FRESH_NOTEBOOK_SOURCE_GATE_FAILED'}
}catch{$result.error=$_.Exception.Message;if($result.stage -eq 'START'){$result.stage='ERROR'}}
finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 30 -Compress
if($result.ok){exit 0}else{exit 2}
