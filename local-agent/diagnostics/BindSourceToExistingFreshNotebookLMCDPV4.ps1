param(
  [string]$SourceText='2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 고유 마커: NLM_FRESH_ALL_20260829_1915.',
  [string]$PromptText='이 소스를 기반으로 AI 오디오 오버뷰를 만들 준비를 하고 핵심 내용을 정리해 주세요.',
  [string]$ExpectedOldNotebookId='69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=120,
  [int]$CdpCommandTimeoutSeconds=8
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Marker='NLM_FRESH_ALL_20260829_1915'

function Get-Tabs { return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3) }
function Parse-NotebookId([string]$Url){ if($Url -match '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){ return [string]$Matches[1] }; return '' }
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$Seconds){
  $buf=New-Object byte[] 65536; $ms=New-Object IO.MemoryStream; $cts=New-Object Threading.CancellationTokenSource; $cts.CancelAfter([Math]::Max(1000,$Seconds*1000))
  try{ do{ $seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf); try{$res=$Ws.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult()}catch{throw 'CDP_RECEIVE_TIMEOUT_OR_CLOSED'}; if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'}; $ms.Write($buf,0,$res.Count) }while(-not $res.EndOfMessage); return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json } finally{$cts.Dispose();$ms.Dispose()}
}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){
  $Seq.Value++;$id=$Seq.Value;$json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes);$cts=New-Object Threading.CancellationTokenSource;$cts.CancelAfter([Math]::Max(1000,$CdpCommandTimeoutSeconds*1000))
  try{$Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$cts.Token).GetAwaiter().GetResult()}catch{throw ('CDP_SEND_TIMEOUT '+$Method)}finally{$cts.Dispose()}
  while($true){$msg=Receive-Cdp $Ws $CdpCommandTimeoutSeconds;if($msg.id -eq $id){if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))};return $msg.result}}
}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){$r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click-Cdp($Ws,[ref]$Seq,[double]$X,[double]$Y){[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$X;y=$Y});[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mousePressed';x=$X;y=$Y;button='left';clickCount=1});Start-Sleep -Milliseconds 100;[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$X;y=$Y;button='left';clickCount=1})}
function Connect-Tab($Tab){$ws=New-Object System.Net.WebSockets.ClientWebSocket;$cts=New-Object Threading.CancellationTokenSource;$cts.CancelAfter([Math]::Max(1000,$CdpCommandTimeoutSeconds*1000));try{$ws.ConnectAsync([Uri]([string]$Tab.webSocketDebuggerUrl),$cts.Token).GetAwaiter().GetResult()}catch{$ws.Dispose();throw 'CDP_CONNECT_TIMEOUT_OR_FAILED'}finally{$cts.Dispose()};return $ws}

$result=[ordered]@{ok=$false;action='NOTEBOOKLM_EXISTING_FRESH_SOURCE_BIND_CDP_V4';startedAt=(Get-Date).ToString('o');notebookUrl='';notebookId='';sourceAdded=$false;sourceVerified=$false;promptFilled=$false;promptSubmitted=$false;studioSelected=$false;createdNotebook=$false;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;stage='START';error='';evidence=@{}}
$ws=$null
try{
  $result.stage='TAB_SELECT'
  $tabs=@(Get-Tabs|Where-Object{[string]$_.type -eq 'page' -and (Parse-NotebookId ([string]$_.url)) -and (Parse-NotebookId ([string]$_.url)) -ne $ExpectedOldNotebookId})
  if(-not $tabs -or $tabs.Count -eq 0){throw 'NO_EXISTING_FRESH_NOTEBOOK_TAB'}
  $chosen=$null
  foreach($t in $tabs){$probe=$null;try{$probe=Connect-Tab $t;$s=0;[void](Send-Cdp $probe ([ref]$s) 'Runtime.enable' @{});$v=Eval-Cdp $probe ([ref]$s) "({visible:document.visibilityState==='visible',title:document.title,body:(document.body?.innerText||'').slice(0,1800)})";if($v.visible){$chosen=$t;break}}catch{}finally{if($probe){try{$probe.Dispose()}catch{}}}}
  if(-not $chosen){$chosen=$tabs[0]}
  $result.notebookUrl=[string]$chosen.url;$result.notebookId=Parse-NotebookId $result.notebookUrl
  $ws=Connect-Tab $chosen;$seq=0;[void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{})
  $before=Eval-Cdp $ws ([ref]$seq) "({url:location.href,title:document.title,body:(document.body?.innerText||'').slice(0,2400)})";$result.evidence.before=$before
  if([string]$before.body -like "*$Marker*"){$result.sourceAdded=$true;$result.sourceVerified=$true}

  if(-not $result.sourceVerified){
    $result.stage='SOURCE_TAB'
    $findSourceTab="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('[role=tab],button,[role=button],a')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' ')).trim();const t=raw.toLowerCase();if(raw==='출처'||raw.startsWith('출처 ')||t==='sources'||t.startsWith('sources ')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw}}}return {ok:false};})()"
    $st=Eval-Cdp $ws ([ref]$seq) $findSourceTab;if($st.ok){Click-Cdp $ws ([ref]$seq) ([double]$st.x) ([double]$st.y);Start-Sleep -Milliseconds 700}

    $result.stage='ADD_SOURCE'
    $findAdd="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const body=document.body?.innerText||'';if(/복사한 텍스트|copied text|paste text/i.test(body))return {ok:false,dialogOpen:true};for(const e of [...document.querySelectorAll('button,[role=button],a')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('소스 추가')||t.includes('add source')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,dialogOpen:false,sample:body.slice(0,1400)};})()"
    $a=Eval-Cdp $ws ([ref]$seq) $findAdd;if($a.ok){Click-Cdp $ws ([ref]$seq) ([double]$a.x) ([double]$a.y);Start-Sleep -Milliseconds 800}elseif(-not $a.dialogOpen){throw ('ADD_SOURCE_CONTROL_NOT_FOUND: '+[string]$a.sample)}

    $result.stage='COPIED_TEXT'
    $findCopied="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('button,[role=button],a,div[tabindex]')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' '));const t=raw.toLowerCase();if(raw.includes('복사한 텍스트')||raw.includes('텍스트 붙여넣기')||t.includes('copied text')||t.includes('paste text')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,sample:(document.body?.innerText||'').slice(0,1600)};})()"
    $cp=Eval-Cdp $ws ([ref]$seq) $findCopied;if(-not $cp.ok){throw ('COPIED_TEXT_SOURCE_CONTROL_NOT_FOUND: '+[string]$cp.sample)};Click-Cdp $ws ([ref]$seq) ([double]$cp.x) ([double]$cp.y);Start-Sleep -Milliseconds 700

    $result.stage='PASTE_SOURCE'
    $sourceJson=$SourceText|ConvertTo-Json -Compress
    $fill="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const dialogs=[...document.querySelectorAll('[role=dialog],mat-dialog-container,.mat-mdc-dialog-container')].filter(vis);const root=dialogs[dialogs.length-1]||document;const all=[...root.querySelectorAll('textarea,[contenteditable=true],input:not([type=hidden])')].filter(vis);const e=all.find(x=>x.tagName==='TEXTAREA')||all.find(x=>/텍스트|text|paste|붙여넣/i.test(String(x.getAttribute('placeholder')||'')))||all.find(x=>x.getAttribute('contenteditable')==='true');if(!e)return {ok:false,error:'SOURCE_TEXT_EDITOR_NOT_FOUND',sample:(document.body?.innerText||'').slice(0,1600)};e.focus();if('value'in e){const p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;if(s)s.call(e,$sourceJson);else e.value=$sourceJson;}else{e.textContent=$sourceJson;}e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:$sourceJson}));e.dispatchEvent(new Event('change',{bubbles:true}));return {ok:true,len:('value'in e?e.value:e.textContent).length,placeholder:e.getAttribute('placeholder')||''};})()"
    $fl=Eval-Cdp $ws ([ref]$seq) $fill;if(-not $fl.ok){throw ($fl.error+': '+[string]$fl.sample)};$result.evidence.sourceEditor=$fl

    $result.stage='SUBMIT_SOURCE'
    $findSubmit="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled};const dialogs=[...document.querySelectorAll('[role=dialog],mat-dialog-container,.mat-mdc-dialog-container')].filter(vis);const root=dialogs[dialogs.length-1]||document;const exact=['삽입','추가','저장','insert','add','save'];for(const e of [...root.querySelectorAll('button,[role=button]')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).trim();const t=raw.toLowerCase().replace(/\s+/g,' ');if(exact.some(w=>t===w||t.startsWith(w+' '))){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return {ok:false,sample:[...root.querySelectorAll('button,[role=button]')].map(e=>String([e.innerText,e.getAttribute('aria-label')].join(' ')).trim()).filter(Boolean).slice(-30)};})()"
    $sb=Eval-Cdp $ws ([ref]$seq) $findSubmit;if(-not $sb.ok){throw ('SOURCE_SUBMIT_CONTROL_NOT_FOUND: '+(($sb.sample|ConvertTo-Json -Compress)))};Click-Cdp $ws ([ref]$seq) ([double]$sb.x) ([double]$sb.y);$result.sourceAdded=$true
    $deadline=(Get-Date).AddSeconds([Math]::Min(35,$TimeoutSeconds));do{Start-Sleep -Milliseconds 700;$v=Eval-Cdp $ws ([ref]$seq) "(() => {const txt=document.body?.innerText||'';const zero=/소스\s*0건|0\s*sources?/i.test(txt);const one=/소스\s*[1-9][0-9]*건|[1-9][0-9]*\s*sources?/i.test(txt);const marker=txt.includes('NLM_FRESH_ALL_20260829_1915');const checks=[...document.querySelectorAll('input[type=checkbox],[role=checkbox],mat-checkbox')].length;return {zero,one,marker,checks,sample:txt.slice(0,2200)}})()";if($v.marker -or $v.one -or (-not $v.zero -and $v.checks -gt 0)){$result.sourceVerified=$true;$result.evidence.sourceVerify=$v;break}}while((Get-Date)-lt $deadline)
    if(-not $result.sourceVerified){$result.evidence.sourceVerify=$v;throw 'SOURCE_ADD_NOT_VERIFIED'}
  }

  if($PromptText){
    $result.stage='CHAT_PROMPT'
    $findChatTab="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('[role=tab],button,[role=button],a')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' ')).trim();const t=raw.toLowerCase();if(raw==='채팅'||t==='chat'){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2}}}return {ok:false};})()";$ct=Eval-Cdp $ws ([ref]$seq) $findChatTab;if($ct.ok){Click-Cdp $ws ([ref]$seq) ([double]$ct.x) ([double]$ct.y);Start-Sleep -Milliseconds 600}
    $promptJson=$PromptText|ConvertTo-Json -Compress
    $fillPrompt="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('textarea,[contenteditable=true]')].filter(vis);const e=all.find(x=>/질문|창작|ask|create/i.test(String([x.getAttribute('placeholder'),x.getAttribute('aria-label')].join(' '))))||all[all.length-1];if(!e)return {ok:false};e.focus();if('value'in e){const p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;if(s)s.call(e,$promptJson);else e.value=$promptJson;}else{e.textContent=$promptJson;}e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:$promptJson}));e.dispatchEvent(new Event('change',{bubbles:true}));return {ok:true,len:('value'in e?e.value:e.textContent).length};})()";$pf=Eval-Cdp $ws ([ref]$seq) $fillPrompt;$result.promptFilled=[bool]$pf.ok;$result.evidence.promptFill=$pf
    if($result.promptFilled){$findArrow="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled};const els=[...document.querySelectorAll('button,[role=button]')].filter(vis);for(const e of els){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).toLowerCase();if(/send|submit|전송|보내기|arrow_forward/.test(raw)){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2}}}const right=els.map(e=>({e,r:e.getBoundingClientRect()})).filter(x=>x.r.left>innerWidth*0.65&&x.r.top>innerHeight*0.55).sort((a,b)=>b.r.left-a.r.left)[0];if(right){return {ok:true,x:right.r.left+right.r.width/2,y:right.r.top+right.r.height/2}}return {ok:false};})()";$ar=Eval-Cdp $ws ([ref]$seq) $findArrow;if($ar.ok){Click-Cdp $ws ([ref]$seq) ([double]$ar.x) ([double]$ar.y);$result.promptSubmitted=$true;Start-Sleep -Milliseconds 700}}
  }

  $result.stage='STUDIO_TAB'
  $findStudio="(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('[role=tab],button,[role=button],a')].filter(vis)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' ')).trim();const t=raw.toLowerCase();if(raw==='스튜디오'||t==='studio'){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2}}}return {ok:false};})()";$sd=Eval-Cdp $ws ([ref]$seq) $findStudio;if($sd.ok){Click-Cdp $ws ([ref]$seq) ([double]$sd.x) ([double]$sd.y);$result.studioSelected=$true}
  $result.ok=($result.sourceVerified -and $result.notebookId -and $result.notebookId -ne $ExpectedOldNotebookId)
  $result.stage=if($result.ok){'PASS'}else{'GATE_FAIL'}
}catch{$result.error=$_.Exception.Message;if($result.stage -eq 'START'){$result.stage='ERROR'}}
finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 40 -Compress
if($result.ok){exit 0}else{exit 2}
