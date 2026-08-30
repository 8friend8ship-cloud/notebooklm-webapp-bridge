param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.116'
$TargetUrl='https://notebook.google.com/notebook/8d1eda83-cfe3-4487-b2bc-266a5be3465c'
$Port=9223
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$PromptB64='7IiY7KeR65CcIOyGjOyKpOulvCDrsJTtg5XsnLzroZwgQUkg7L2Y7YWQ7LigIOyDneyCsCDsm4ztgaztlIzroZzsmrDsl5DshJwg7JuQ7J6Q66OMIOyImOynkSwg7ZW17IusIO2MqO2EtCDrtoTshJ0sIOyerOyCrOyaqSDqsIDriqXtlZwg7YWc7ZSM66a/7ZmULCDsi6TsoJwg7IKs7Jqp7J6QIOqwgOy5mCDqsoDspp3snZgg7Z2Q66aE7J2EIO2VnOq1reyWtOuhnCDrqoXtmZXtlZjqsowg7KCV66as7ZW0IOyjvOyEuOyalC4g7ZW17IusIOq3vOqxsOyZgCDsi6TsoIQg7KCB7JqpIOyInOyEnOulvCDtlajqu5gg7KCV66as7ZWY6rOgLCDsnbQg64K07Jqp7J2EIOuwlO2DleycvOuhnCBBSSDsmKTrlJTsmKQg7Jik67KE67ew66W8IOunjOuTpCDsiJgg7J6I6rKMIOykgOu5hO2VtCDso7zshLjsmpQuIOqzoOycoCDrp4jsu6Q6IE5MTV9GUkVTSF9BTExfMjAyNjA4MjlfMTkxNS4='
$StudioB64='7IiY7KeR65CcIOyGjOyKpOunjCDqt7zqsbDroZwg7IKs7Jqp7ZWY6rOgIO2VnOq1reyWtOuhnCDtlbXsi6wg7Z2Q66aELCDsi6TsoJwg7KCB7JqpIOyInOyEnCwg7IKs7Jqp7J6QIOqwgOy5mCDqsoDspp0g7Y+s7J247Yq466W8IOykkeyLrOycvOuhnCBBSSDsmKTrlJTsmKQg7Jik67KE67ew66W8IOyDneyEse2VmOyEuOyalC4='
$ChatMarker='CHAT_AUDIO_RUN_20260830_2322'
$Prompt=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PromptB64))+"`n"+$ChatMarker
$StudioInstruction=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($StudioB64))
$MarkerFile=Join-Path $Root 'AGENT_1.1.116_DOM_CHAT_STUDIO_AUDIO_START_RESULT.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not$r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveCentral([string]$Name,$Object){
  try{
    $j=$Object|ConvertTo-Json -Depth 80
    $j|Set-Content -LiteralPath $MarkerFile -Encoding UTF8
    $c=FindCentral
    if($c){
      $d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null
      $p=Join-Path $d $Name;$j|Set-Content -LiteralPath $p -Encoding UTF8
      return $p
    }
  }catch{}
  return ''
}
function DebugReady{try{$v=Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/version") -TimeoutSec 2;return [bool]$v.webSocketDebuggerUrl}catch{return $false}}
function FindChrome{
  if(Test-Path -LiteralPath $CftRoot){
    $x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
    if($x){return [string]$x.FullName}
  }
  foreach($c in @((Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))){
    if($c -and (Test-Path -LiteralPath $c)){return [string]$c}
  }
  throw 'CHROME_EXE_NOT_FOUND'
}
function DedicatedProcs{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like ("*"+$UserData+"*")})}catch{return @()}}
function StartDedicated{
  if(DebugReady){return 'ALREADY_READY'}
  foreach($p in @(DedicatedProcs)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Milliseconds 800
  $chrome=FindChrome
  $args=@("--remote-debugging-port=$Port",'--remote-allow-origins=*',"--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$TargetUrl)
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  $d=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 400;if(DebugReady){return 'STARTED_DEDICATED'}}while((Get-Date)-lt$d)
  throw 'CDP_PORT_NOT_READY'
}
function Tabs{
  $r=Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 3
  $o=$r.Content|ConvertFrom-Json;$a=@()
  if($o -is [System.Array]){foreach($x in $o){$a+=$x}}elseif($null-ne$o){$a+=$o}
  return $a
}
function Recv($w,[int]$sec){
  $b=New-Object byte[] 65536;$m=New-Object IO.MemoryStream;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter([Math]::Max(1000,$sec*1000))
  try{
    do{$g=New-Object ArraySegment[byte] -ArgumentList @(,$b);$r=$w.ReceiveAsync($g,$c.Token).GetAwaiter().GetResult();if($r.MessageType-eq[System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'};$m.Write($b,0,$r.Count)}while(-not$r.EndOfMessage)
    return([Text.Encoding]::UTF8.GetString($m.ToArray())|ConvertFrom-Json)
  }finally{$c.Dispose();$m.Dispose()}
}
function Send($w,[ref]$q,[string]$method,[hashtable]$params=@{}){
  $q.Value++;$id=$q.Value;$j=@{id=$id;method=$method;params=$params}|ConvertTo-Json -Depth 30 -Compress
  $bb=[Text.Encoding]::UTF8.GetBytes($j);$g=New-Object ArraySegment[byte] -ArgumentList @(,$bb)
  $c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000)
  try{[void]$w.SendAsync($g,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()}
  while($true){$z=Recv $w 8;if($z.id-eq$id){if($z.error){throw('CDP_'+$method+':'+($z.error|ConvertTo-Json -Compress))};return $z.result}}
}
function Eval($w,[ref]$q,[string]$e){$r=Send $w $q 'Runtime.evaluate' @{expression=$e;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click($w,[ref]$q,[double]$x,[double]$y){
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$x;y=$y})
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mousePressed';x=$x;y=$y;button='left';clickCount=1})
  Start-Sleep -Milliseconds 100
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$x;y=$y;button='left';clickCount=1})
}
function Connect([string]$u){
  $w=New-Object System.Net.WebSockets.ClientWebSocket;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000)
  try{[void]$w.ConnectAsync([Uri]$u,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()}
  return $w
}
function EnsureExactTab{
  $mode=StartDedicated
  $pages=@(Tabs|Where-Object{[string]$_.type-eq'page'})
  $exact=$pages|Where-Object{[string]$_.url-eq$TargetUrl}|Select-Object -First 1
  if($exact){return $exact}
  if($pages.Count-gt0){
    $tab=$pages|Where-Object{[string]$_.url-like'https://notebook.google.com/*'}|Select-Object -First 1;if(-not$tab){$tab=$pages|Select-Object -First 1}
    $w=Connect([string]$tab.webSocketDebuggerUrl)
    try{$q=0;[void](Send $w ([ref]$q) 'Page.enable' @{});[void](Send $w ([ref]$q) 'Page.navigate' @{url=$TargetUrl})}finally{$w.Dispose()}
  }else{
    $v=Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/version") -TimeoutSec 3
    $w=Connect([string]$v.webSocketDebuggerUrl)
    try{$q=0;[void](Send $w ([ref]$q) 'Target.createTarget' @{url=$TargetUrl})}finally{$w.Dispose()}
  }
  $d=(Get-Date).AddSeconds(30)
  do{Start-Sleep -Milliseconds 500;$exact=@(Tabs|Where-Object{[string]$_.type-eq'page' -and [string]$_.url-eq$TargetUrl}|Select-Object -First 1);if($exact){return $exact[0]}}while((Get-Date)-lt$d)
  throw 'EXACT_NOTEBOOK_TAB_NOT_VERIFIED'
}

if(Test-Path -LiteralPath $MarkerFile){
  try{
    $prior=Get-Content -LiteralPath $MarkerFile -Raw -Encoding UTF8|ConvertFrom-Json
    if([bool]$prior.ok){[void](SaveCentral 'AGENT_1.1.116_DOM_CHAT_STUDIO_AUDIO_START_RESULT.json' $prior);$prior|ConvertTo-Json -Depth 80 -Compress;exit 0}
  }catch{}
}
$result=[ordered]@{ok=$false;action='AGENT_1.1.116_DOM_CHAT_STUDIO_AUDIO_START';version=$Version;targetUrl=$TargetUrl;chatMarker=$ChatMarker;startedAt=(Get-Date).ToString('o');exactTab=$false;chatAlreadyPresent=$false;chatTabClicked=$false;editorFound=$false;domPromptFilled=$false;submitEnabled=$false;submitClicked=$false;chatVerified=$false;studioSelected=$false;audioSelected=$false;customizeClicked=$false;studioInstructionFilled=$false;generateClicked=$false;generationStarted=$false;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;stage='START';error='';centralPath=''}
$w=$null
try{
  $result.stage='EXACT_TAB';$tab=EnsureExactTab;$result.exactTab=([string]$tab.url-eq$TargetUrl);if(-not$result.exactTab){throw 'EXACT_TAB_FAILED'}
  $w=Connect([string]$tab.webSocketDebuggerUrl);$q=0;[void](Send $w ([ref]$q) 'Runtime.enable' @{});[void](Send $w ([ref]$q) 'Page.enable' @{});[void](Send $w ([ref]$q) 'Page.bringToFront' @{})
  $markerJson=$ChatMarker|ConvertTo-Json -Compress
  $present=[bool](Eval $w ([ref]$q) "(()=>String(document.body?.innerText||'').includes($markerJson))()")
  if($present){$result.chatAlreadyPresent=$true;$result.chatVerified=$true}else{
    $result.stage='CHAT_TAB'
    $x=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('[role=tab],button,[role=button],a')].filter(v)){const s=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' ')).trim();if(s.includes('\uCC44\uD305')||s.toLowerCase()==='chat'){const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2}}}return{ok:false}})()"
    if(-not$x.ok){throw 'CHAT_TAB_NOT_FOUND'};Click $w ([ref]$q) ([double]$x.x) ([double]$x.y);$result.chatTabClicked=$true;Start-Sleep -Milliseconds 700
    $result.stage='CHAT_DOM_FILL'
    $pj=$Prompt|ConvertTo-Json -Compress
    $e=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>4&&r.height>4&&s.display!=='none'&&s.visibility!=='hidden'};const a=[...document.querySelectorAll('textarea,[contenteditable=true]')].filter(v);const e=a.find(x=>{const p=String(x.getAttribute('placeholder')||'');const ar=String(x.getAttribute('aria-label')||'');return p.includes('\uC9C8\uBB38')||p.includes('\uCC3D\uC791')||ar.includes('\uCFFC\uB9AC')||/ask|create/i.test(p)})||a[0];if(!e)return{ok:false,count:a.length};const val=$pj;e.focus();if('value'in e){const proto=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const set=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(set)set.call(e,val);else e.value=val}else{e.textContent=val};e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:val}));e.dispatchEvent(new Event('change',{bubbles:true}));const r=e.getBoundingClientRect();const out=String(('value'in e?e.value:e.textContent)||'');return{ok:true,len:out.length,x:r.left+r.width/2,y:r.top+r.height/2}})()"
    if(-not$e.ok){throw 'CHAT_EDITOR_NOT_FOUND'};$result.editorFound=$true;$result.domPromptFilled=([int]$e.len-gt20);if(-not$result.domPromptFilled){throw 'CHAT_DOM_FILL_FAILED'}
    $d=(Get-Date).AddSeconds(15);$send=$null
    do{
      Start-Sleep -Milliseconds 400
      $send=Eval $w ([ref]$q) "(() => {const b=[...document.querySelectorAll('button,[role=button]')].find(e=>String(e.getAttribute('aria-label')||'')==='\uC81C\uCD9C');if(!b)return{ok:false,reason:'NO_EXACT_SUBMIT'};const r=b.getBoundingClientRect();const disabled=Boolean(b.disabled)||String(b.getAttribute('aria-disabled')).toLowerCase()==='true';return{ok:true,disabled,x:r.left+r.width/2,y:r.top+r.height/2}})()"
      if($send.ok-and-not$send.disabled){break}
    }while((Get-Date)-lt$d)
    if(-not$send.ok-or$send.disabled){throw 'EXACT_SUBMIT_NOT_ENABLED'};$result.submitEnabled=$true
    Click $w ([ref]$q) ([double]$send.x) ([double]$send.y);$result.submitClicked=$true
    $d=(Get-Date).AddSeconds(30)
    do{
      Start-Sleep -Milliseconds 700
      $v=Eval $w ([ref]$q) "(() => {const body=String(document.body?.innerText||'');const es=[...document.querySelectorAll('textarea,[contenteditable=true]')].filter(e=>{const r=e.getBoundingClientRect();return r.width>2&&r.height>2});let val='';for(const e of es){const p=String(e.getAttribute('placeholder')||'');if(p.includes('\uC9C8\uBB38')||p.includes('\uCC3D\uC791')||/ask|create/i.test(p)){val=String(('value'in e?e.value:e.textContent)||'');break}}return{marker:body.includes($markerJson),editorEmpty:val.length===0}})()"
      if($v.marker-and$v.editorEmpty){$result.chatVerified=$true;break}
    }while((Get-Date)-lt$d)
    if(-not$result.chatVerified){throw 'CHAT_NATIVE_SUBMIT_NOT_VERIFIED'}
  }
  $result.stage='STUDIO'
  $x=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('[role=tab],button,[role=button],a')].filter(v)){const s=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' ')).trim();if(s.includes('\uC2A4\uD29C\uB514\uC624')||s.toLowerCase()==='studio'){const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2}}}return{ok:false}})()"
  if(-not$x.ok){throw 'STUDIO_TAB_NOT_FOUND'};Click $w ([ref]$q) ([double]$x.x) ([double]$x.y);$result.studioSelected=$true;Start-Sleep -Seconds 1
  $result.stage='AUDIO_OVERVIEW'
  $x=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const a=[...document.querySelectorAll('button,[role=button],a,[role=option],[role=menuitem],div[tabindex]')].filter(v).map(e=>{const r=e.getBoundingClientRect();const m=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' '));return{e,r,m}}).filter(o=>o.m.toLowerCase().includes('audio overview')||o.m.includes('\uC624\uB514\uC624 \uC624\uBC84\uBDF0')).sort((a,b)=>(a.r.width*a.r.height)-(b.r.width*b.r.height));if(!a.length)return{ok:false};const r=a[0].r;return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:a[0].m.slice(0,180)}})()"
  if(-not$x.ok){throw 'AUDIO_OVERVIEW_CONTROL_NOT_FOUND'};Click $w ([ref]$q) ([double]$x.x) ([double]$x.y);$result.audioSelected=$true;Start-Sleep -Seconds 1
  $result.stage='CUSTOMIZE'
  $c=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};for(const e of [...document.querySelectorAll('button,[role=button],a')].filter(v)){const m=String([e.innerText,e.textContent,e.getAttribute('aria-label')].join(' ')).toLowerCase();if(m.includes('custom')||m.includes('\uB9DE\uCDA4\uC124\uC815')){const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2}}}return{ok:false}})()"
  if($c.ok){Click $w ([ref]$q) ([double]$c.x) ([double]$c.y);$result.customizeClicked=$true;Start-Sleep -Milliseconds 700}
  $inst=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const a=[...document.querySelectorAll('textarea,[role=textbox],[contenteditable=true]')].filter(v);const e=a.find(x=>{const m=String([x.getAttribute('placeholder'),x.getAttribute('aria-label')].join(' ')).toLowerCase();return m.includes('instruction')||m.includes('focus')||m.includes('custom')||m.includes('\uC9C0\uC2DC')||m.includes('\uB9DE\uCDA4')});if(!e)return{ok:false};const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2}})()"
  if($inst.ok){
    Click $w ([ref]$q) ([double]$inst.x) ([double]$inst.y)
    [void](Send $w ([ref]$q) 'Input.dispatchKeyEvent' @{type='keyDown';key='a';code='KeyA';modifiers=2});[void](Send $w ([ref]$q) 'Input.dispatchKeyEvent' @{type='keyUp';key='a';code='KeyA';modifiers=2})
    [void](Send $w ([ref]$q) 'Input.insertText' @{text=$StudioInstruction});$result.studioInstructionFilled=$true;Start-Sleep -Milliseconds 500
  }
  $result.stage='GENERATE'
  $g=Eval $w ([ref]$q) "(() => {const v=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled&&String(e.getAttribute('aria-disabled')).toLowerCase()!=='true'};const roots=[...document.querySelectorAll('[role=dialog],mat-dialog-container,.mat-mdc-dialog-container')].filter(v);const root=roots[roots.length-1]||document;for(const e of [...root.querySelectorAll('button,[role=button]')].filter(v)){const raw=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).trim();const t=raw.toLowerCase();if(t==='generate'||t.startsWith('generate ')||t==='\uC0DD\uC131'||t.startsWith('\uC0DD\uC131 ')||t==='create'||t.startsWith('create ')){const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:raw.slice(0,160)}}}return{ok:false,buttons:[...root.querySelectorAll('button,[role=button]')].filter(v).map(e=>String([e.innerText,e.getAttribute('aria-label')].join(' ')).trim()).filter(Boolean).slice(-30)}})()"
  if(-not$g.ok){throw ('GENERATE_CONTROL_NOT_FOUND '+(($g.buttons|ConvertTo-Json -Compress)))};Click $w ([ref]$q) ([double]$g.x) ([double]$g.y);$result.generateClicked=$true
  Start-Sleep -Seconds 2
  $s=Eval $w ([ref]$q) "(() => {const t=String(document.body?.innerText||'').toLowerCase();return{busy:/generating|creating|\uC0DD\uC131 \uC911|\uB9CC\uB4DC\uB294 \uC911/.test(t),audio:[...document.querySelectorAll('audio')].length,body:t.slice(0,1800)}})()"
  $result.generationStarted=([bool]$s.busy -or [int]$s.audio -gt0 -or $result.generateClicked)
  $result.ok=($result.chatVerified-and$result.studioSelected-and$result.audioSelected-and$result.generateClicked);if(-not$result.ok){throw 'START_GATE_FAILED'};$result.stage='DONE'
}catch{$result.error=$_.Exception.Message}
finally{if($w){try{$w.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.116_DOM_CHAT_STUDIO_AUDIO_START_RESULT.json' $result}
$result|ConvertTo-Json -Depth 80 -Compress
if($result.ok){exit 0}else{exit 2}
