param(
  [string]$Title='2026-08-29 NotebookLM Fresh E2E 전체 산출물 검증',
  [string]$SourceText='2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 고유 마커: NLM_FRESH_ALL_20260829_1915.',
  [string]$ExpectedOldNotebookId='69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=120
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
  $deadline=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 400;if(Debug-Ready){return}}while((Get-Date)-lt $deadline)
  throw 'CDP_PORT_NOT_READY'
}
function Get-Tabs {return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3)}
function Get-PageTab {return @(Get-Tabs|Where-Object{[string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/*'}|Select-Object -First 1)[0]}
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws){$buf=New-Object byte[] 65536;$ms=New-Object IO.MemoryStream;try{do{$seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf);$res=$Ws.ReceiveAsync($seg,[Threading.CancellationToken]::None).GetAwaiter().GetResult();if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'};$ms.Write($buf,0,$res.Count)}while(-not $res.EndOfMessage);return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json}finally{$ms.Dispose()}}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){$Seq.Value++;$id=$Seq.Value;$json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes);$Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult();while($true){$msg=Receive-Cdp $Ws;if($msg.id -eq $id){if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))};return $msg.result}}}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){$r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click-Cdp($Ws,[ref]$Seq,[double]$X,[double]$Y){[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$X;y=$Y});[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mousePressed';x=$X;y=$Y;button='left';clickCount=1});Start-Sleep -Milliseconds 100;[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$X;y=$Y;button='left';clickCount=1})}
function Wait-Url($Ws,[ref]$Seq,[int]$Seconds){$deadline=(Get-Date).AddSeconds($Seconds);do{Start-Sleep -Milliseconds 400;$u=[string](Eval-Cdp $Ws $Seq 'location.href');if($u -match '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){return $u}}while((Get-Date)-lt $deadline);return ''}

$result=[ordered]@{ok=$false;action='NOTEBOOKLM_FRESH_NOTEBOOK_CREATE_SOURCE_CDP_V2';title=$Title;startedAt=$Started.ToString('o');notebookUrl='';notebookId='';previousNotebookId=$ExpectedOldNotebookId;freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;marker='NLM_FRESH_ALL_20260829_1915';error='';evidence=@{}}
$ws=$null
try{
  Start-DebugChrome
  $deadline=(Get-Date).AddSeconds(20);$tab=$null;do{$tab=Get-PageTab;if($tab){break};Start-Sleep -Milliseconds 400}while((Get-Date)-lt $deadline);if(-not $tab){throw 'NOTEBOOK_TAB_NOT_FOUND'}
  $uri=[Uri]([string]$tab.webSocketDebuggerUrl);$ws=New-Object System.Net.WebSockets.ClientWebSocket;$ws.ConnectAsync($uri,[Threading.CancellationToken]::None).GetAwaiter().GetResult();$seq=0
  [void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{})
  [void](Send-Cdp $ws ([ref]$seq) 'Page.navigate' @{url=$NotebookHome});Start-Sleep -Seconds 2

  $findCreate=@"
(() => { const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0}; const els=[...document.querySelectorAll('button,[role=button],a')].filter(vis); for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('노트북 만들기')||raw.includes('새 노트북')||raw.includes('새 노트 만들기')||t.includes('create new notebook')||t.includes('new notebook')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,200),count:els.length}}} return {ok:false,error:'CREATE_NEW_NOTEBOOK_CONTROL_NOT_FOUND',sample:document.body.innerText.slice(0,1200)}; })()
"@
  $c=Eval-Cdp $ws ([ref]$seq) $findCreate;if(-not $c.ok){throw ($c.error+': '+[string]$c.sample)};$result.evidence.createControl=[string]$c.text;Click-Cdp $ws ([ref]$seq) ([double]$c.x) ([double]$c.y)
  $u=Wait-Url $ws ([ref]$seq) ([Math]::Min(45,$TimeoutSeconds));if(-not $u){throw 'FRESH_NOTEBOOK_URL_NOT_CREATED'}
  if($u -notmatch '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){throw 'FRESH_NOTEBOOK_ID_NOT_PARSED'}
  $id=[string]$Matches[1];if($ExpectedOldNotebookId -and $id -eq $ExpectedOldNotebookId){throw 'OLD_NOTEBOOK_REUSED'}
  $result.notebookUrl=$u;$result.notebookId=$id;$result.freshNotebook=$true
  Start-Sleep -Seconds 2

  $titleJson=$Title|ConvertTo-Json -Compress
  $rename=@"
(async()=>{const sleep=ms=>new Promise(r=>setTimeout(r,ms));const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};let e=document.querySelector('editable-project-title');if(!e)e=[...document.querySelectorAll('input,textarea,[contenteditable=true]')].filter(vis).find(x=>/제목|title|untitled/i.test(String([x.value,x.textContent,x.getAttribute('aria-label'),x.getAttribute('placeholder')].join(' '))));if(!e)return {ok:false};try{e.click();e.focus();await sleep(150);const target=e.matches('input,textarea,[contenteditable=true]')?e:[...e.querySelectorAll('input,textarea,[contenteditable=true]')].find(vis);if(!target)return {ok:false};if('value' in target){const p=target.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;if(s)s.call(target,$titleJson);else target.value=$titleJson;}else{target.textContent=$titleJson;}target.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:$titleJson}));target.dispatchEvent(new Event('change',{bubbles:true}));target.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',bubbles:true}));return {ok:true};}catch(ex){return {ok:false,error:String(ex)}}})()
"@
  $rn=Eval-Cdp $ws ([ref]$seq) $rename;$result.evidence.renameAttempt=$rn

  $findAdd=@"
(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('button,[role=button],a')].filter(vis);for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('소스 추가')||t.includes('add source')||t.includes('add sources')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}const body=document.body.innerText;return {ok:false,dialogOpen:/복사한 텍스트|copied text|paste text/i.test(body),sample:body.slice(0,1200)};})()
"@
  $a=Eval-Cdp $ws ([ref]$seq) $findAdd;if($a.ok){Click-Cdp $ws ([ref]$seq) ([double]$a.x) ([double]$a.y);Start-Sleep -Milliseconds 900}elseif(-not $a.dialogOpen){throw ('ADD_SOURCE_CONTROL_NOT_FOUND: '+[string]$a.sample)}

  $findCopied=@"
(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const els=[...document.querySelectorAll('button,[role=button],a,div[tabindex]')].filter(vis);for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('복사한 텍스트')||raw.includes('텍스트 붙여넣기')||t.includes('copied text')||t.includes('paste text')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,sample:document.body.innerText.slice(0,1400)};})()
"@
  $cp=Eval-Cdp $ws ([ref]$seq) $findCopied;if(-not $cp.ok){throw ('COPIED_TEXT_SOURCE_CONTROL_NOT_FOUND: '+[string]$cp.sample)};$result.evidence.sourceTypeControl=[string]$cp.text;Click-Cdp $ws ([ref]$seq) ([double]$cp.x) ([double]$cp.y);Start-Sleep -Milliseconds 800

  $sourceJson=$SourceText|ConvertTo-Json -Compress
  $fill=@"
(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('textarea,[contenteditable=true],input:not([type=hidden])')].filter(vis);const e=all.find(x=>x.tagName==='TEXTAREA')||all.find(x=>x.getAttribute('contenteditable')==='true')||all.find(x=>/텍스트|text|paste|붙여넣/i.test(String(x.getAttribute('placeholder')||'')));if(!e)return {ok:false,error:'PASTED_TEXT_EDITOR_NOT_FOUND',count:all.length,sample:document.body.innerText.slice(0,1400)};e.focus();if('value' in e){const p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;if(s)s.call(e,$sourceJson);else e.value=$sourceJson;}else{e.textContent=$sourceJson;}e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:$sourceJson}));e.dispatchEvent(new Event('change',{bubbles:true}));return {ok:true,len:('value'in e?e.value:e.textContent).length,tag:e.tagName,placeholder:e.getAttribute('placeholder')||''};})()
"@
  $fl=Eval-Cdp $ws ([ref]$seq) $fill;if(-not $fl.ok){throw ($fl.error+': '+[string]$fl.sample)};$result.evidence.editor=$fl
  Start-Sleep -Milliseconds 500

  $findSubmit=@"
(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled};const els=[...document.querySelectorAll('button,[role=button]')].filter(vis);const exact=['삽입','추가','저장','insert','add','save'];for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).trim();const t=raw.toLowerCase().replace(/\s+/g,' ');if(exact.some(w=>t===w||t.startsWith(w+' '))){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,sample:els.map(e=>String([e.innerText,e.getAttribute('aria-label')].join(' ')).trim()).filter(Boolean).slice(-30)};})()
"@
  $sb=Eval-Cdp $ws ([ref]$seq) $findSubmit;if(-not $sb.ok){throw ('SOURCE_SUBMIT_CONTROL_NOT_FOUND: '+(($sb.sample|ConvertTo-Json -Compress)))};$result.evidence.submitControl=[string]$sb.text;Click-Cdp $ws ([ref]$seq) ([double]$sb.x) ([double]$sb.y);$result.sourceAdded=$true

  $marker='NLM_FRESH_ALL_20260829_1915';$markerJson=$marker|ConvertTo-Json -Compress
  $verifyDeadline=(Get-Date).AddSeconds([Math]::Min(45,$TimeoutSeconds));do{Start-Sleep -Milliseconds 700;$v=Eval-Cdp $ws ([ref]$seq) @"
(() => {const txt=document.body.innerText||'';const dialogs=[...document.querySelectorAll('[role=dialog],mat-dialog-container')].filter(e=>{const r=e.getBoundingClientRect();return r.width>2&&r.height>2});const marker=txt.includes($markerJson);const sourceSignals=[...document.querySelectorAll('input[type=checkbox],[role=checkbox],mat-checkbox')].length;const hasSourceText=/모든 소스|all sources|소스\s*1|1\s*개의?\s*소스|source\s*1/i.test(txt);return {marker:marker,dialogCount:dialogs.length,sourceSignals:sourceSignals,hasSourceText:hasSourceText,sample:txt.slice(0,1800)};})()
"@;if($v.marker -or (($v.dialogCount -eq 0) -and ($v.hasSourceText -or $v.sourceSignals -gt 0))){$result.sourceVerified=$true;$result.evidence.verify=$v;break}}while((Get-Date)-lt $verifyDeadline)
  if(-not $result.sourceVerified){$result.evidence.verify=$v;throw 'SOURCE_ADD_NOT_VERIFIED'}
  $finalUrl=[string](Eval-Cdp $ws ([ref]$seq) 'location.href');if($finalUrl -notmatch '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){throw 'FINAL_NOTEBOOK_URL_LOST'};if([string]$Matches[1] -ne $id){throw 'NOTEBOOK_ID_CHANGED_UNEXPECTEDLY'}
  $result.notebookUrl=$finalUrl;$result.ok=$true
}catch{$result.error=$_.Exception.Message}
finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 30 -Compress
if($result.ok -and $result.freshNotebook -and $result.sourceAdded -and $result.sourceVerified){exit 0}else{exit 2}
