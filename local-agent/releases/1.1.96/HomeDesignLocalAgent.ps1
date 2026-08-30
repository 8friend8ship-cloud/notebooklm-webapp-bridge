param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.96'
$TargetNotebookId='8d1eda83-cfe3-4487-b2bc-266a5be3465c'
$TargetUrl='https://notebook.google.com/notebook/'+$TargetNotebookId
$ResearchQuery=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('QUkg7L2Y7YWQ7LigIOyDneyCsCDsm4ztgaztlIzroZzsmrAg642w7J207YSwIOyImOynkSDrtoTshJ0g7YWc7ZSM66a/IOyCrOyaqeyekCDqsIDsuZgg6rKA7KadIOyCrOuhgA=='))
$Port=9223
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveCentral([string]$Name,$Object){
  try{
    $j=$Object|ConvertTo-Json -Depth 60
    $j|Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8
    $c=FindCentral
    if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$p=Join-Path $d $Name;$j|Set-Content -LiteralPath $p -Encoding UTF8;return $p}
  }catch{}
  return ''
}
function Tabs{
  $r=Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 4
  $o=$r.Content|ConvertFrom-Json;$a=@()
  if($o -is [System.Array]){foreach($x in $o){$a+=$x}}elseif($null-ne $o){$a+=$o}
  return $a
}
function Recv($w,[int]$s){
  $b=New-Object byte[] 65536;$m=New-Object IO.MemoryStream;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter([Math]::Max(1000,$s*1000))
  try{
    do{$g=New-Object ArraySegment[byte] -ArgumentList @(,$b);$r=$w.ReceiveAsync($g,$c.Token).GetAwaiter().GetResult();if($r.MessageType-eq[System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'};$m.Write($b,0,$r.Count)}while(-not $r.EndOfMessage)
    return ([Text.Encoding]::UTF8.GetString($m.ToArray())|ConvertFrom-Json)
  }finally{$c.Dispose();$m.Dispose()}
}
function Send($w,[ref]$q,[string]$m,[hashtable]$p=@{}){
  $q.Value++;$id=$q.Value;$j=@{id=$id;method=$m;params=$p}|ConvertTo-Json -Depth 30 -Compress;$bb=[Text.Encoding]::UTF8.GetBytes($j);$g=New-Object ArraySegment[byte] -ArgumentList @(,$bb);$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000)
  try{[void]$w.SendAsync($g,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()}
  while($true){$z=Recv $w 8;if($z.id-eq$id){if($z.error){throw ('CDP_'+$m+':'+($z.error|ConvertTo-Json -Compress))};return $z.result}}
}
function Eval($w,[ref]$q,[string]$e){$r=Send $w $q 'Runtime.evaluate' @{expression=$e;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click($w,[ref]$q,[double]$x,[double]$y){
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$x;y=$y})
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mousePressed';x=$x;y=$y;button='left';clickCount=1})
  Start-Sleep -Milliseconds 100
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$x;y=$y;button='left';clickCount=1})
}
$result=[ordered]@{
  ok=$false;action='AGENT_1.1.96_FAST_RESEARCH_RESULTS_READONLY_BEFORE_IMPORT';version=$Version;startedAt=(Get-Date).ToString('o')
  notebookUrl='';sourceTabClicked=$false;addSourceClicked=$false;fastResearchVisible=$false;researchFilled=$false;researchSubmitted=$false;researchResultsObserved=$false
  sourceCountBefore=0;sourceCountAfter=0;resultControls=@();bodyText='';normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false
  importClicked=$false;chatSubmitted=$false;studioSelected=$false;generateClicked=$false;error='';centralPath=''
}
$w=$null
try{
  $t=@(Tabs|Where-Object{[string]$_.type-eq'page'}|Where-Object{[string]$_.url-like'https://notebook.google.com/*'}|Select-Object -First 1)
  if(-not $t){throw 'NO_NOTEBOOKLM_PAGE'}
  [System.Net.WebSockets.ClientWebSocket]$w=New-Object System.Net.WebSockets.ClientWebSocket
  $c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000)
  try{[void]$w.ConnectAsync([Uri]([string]$t[0].webSocketDebuggerUrl),$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()}
  $q=0;[void](Send $w ([ref]$q) 'Runtime.enable' @{});[void](Send $w ([ref]$q) 'Page.enable' @{});[void](Send $w ([ref]$q) 'Page.bringToFront' @{});[void](Send $w ([ref]$q) 'Page.navigate' @{url=$TargetUrl});Start-Sleep -Seconds 2
  $result.notebookUrl=[string](Eval $w ([ref]$q) 'location.href');if($result.notebookUrl-ne$TargetUrl){throw 'EXACT_NOTEBOOK_NAVIGATION_FAILED'}
  $before=Eval $w ([ref]$q) "(() => {const t=document.body?.innerText||'';const m=t.match(/\uC18C\uC2A4\s*([0-9]+)\uAC1C/i)||t.match(/([0-9]+)\s*sources?/i);return m?Number(m[1]):0})()"
  $result.sourceCountBefore=[int]$before
  $x=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const txt=e=>String([e.innerText,e.textContent,e.getAttribute?.('aria-label')].join(' ')).replace(/\s+/g,' ').trim();const a=[...document.querySelectorAll('*')].filter(vis).filter(e=>{const s=txt(e).toLowerCase();return s==='\uCD9C\uCC98'||s==='sources'||s.includes('\uCD9C\uCC98')||s.includes('sources')}).sort((p,n)=>{const a=p.getBoundingClientRect(),b=n.getBoundingClientRect();return a.width*a.height-b.width*b.height});if(!a.length)return {ok:false};let e=a[0].closest('button,[role=button],[role=tab],a,nb-button,nb-tab')||a[0];const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:txt(e).slice(0,120)}})()"
  if(-not $x.ok){throw 'SOURCE_TAB_NOT_FOUND'};Click $w ([ref]$q) ([double]$x.x) ([double]$x.y);$result.sourceTabClicked=$true;Start-Sleep -Milliseconds 800
  $body=[string](Eval $w ([ref]$q) '(document.body?.innerText||"")')
  if($body -notmatch '(?i)Fast Research'){
    $x=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const txt=e=>String([e.innerText,e.textContent,e.getAttribute?.('aria-label')].join(' ')).replace(/\s+/g,' ').trim();const a=[...document.querySelectorAll('*')].filter(vis).filter(e=>{const s=txt(e).toLowerCase();return s.includes('\uC18C\uC2A4 \uCD94\uAC00')||s.includes('add source')}).sort((p,n)=>{const a=p.getBoundingClientRect(),b=n.getBoundingClientRect();return a.width*a.height-b.width*b.height});if(!a.length)return {ok:false};let e=a[0].closest('button,[role=button],a,nb-button')||a[0];const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:txt(e).slice(0,120)}})()"
    if(-not $x.ok){throw 'ADD_SOURCE_CONTROL_NOT_FOUND'};Click $w ([ref]$q) ([double]$x.x) ([double]$x.y);$result.addSourceClicked=$true;Start-Sleep -Seconds 1
  }
  $body=[string](Eval $w ([ref]$q) '(document.body?.innerText||"")');$result.fastResearchVisible=($body -match '(?i)Fast Research');if(-not $result.fastResearchVisible){throw 'FAST_RESEARCH_UI_NOT_VISIBLE'}
  $rj=$ResearchQuery|ConvertTo-Json -Compress
  $x=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('input,textarea,[role=textbox],[contenteditable=true]')].filter(vis);let e=all.find(x=>{const m=String([x.getAttribute('placeholder'),x.getAttribute('aria-label')].join(' ')).toLowerCase();return (m.includes('\uC6F9')&&m.includes('\uC18C\uC2A4'))||(m.includes('search')&&m.includes('source'))||m.includes('research')})||all.find(x=>String([x.getAttribute('placeholder'),x.getAttribute('aria-label')].join(' ')).toLowerCase().includes('search'));if(!e)return {ok:false,count:all.length};e.focus();const val=$rj;if('value'in e){const p=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;if(s)s.call(e,val);else e.value=val}else{e.textContent=val};e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:val}));e.dispatchEvent(new Event('change',{bubbles:true}));return {ok:true,tag:e.tagName,ph:e.getAttribute('placeholder'),aria:e.getAttribute('aria-label')}})()"
  if(-not $x.ok){throw ('RESEARCH_EDITOR_NOT_FOUND count='+[string]$x.count)};$result.researchFilled=$true
  $x=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled};for(const e of [...document.querySelectorAll('button,[role=button],nb-button')].filter(vis)){const m=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title'),e.querySelector('mat-icon')?.textContent].join(' ')).replace(/\s+/g,' ').trim().toLowerCase();if((m==='search'||m==='\uAC80\uC0C9'||m.includes('\uAC80\uC0C9'))&&!m.includes('search_spark')){const r=e.getBoundingClientRect();return {ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:m.slice(0,120)}}}return {ok:false}})()"
  if($x.ok){Click $w ([ref]$q) ([double]$x.x) ([double]$x.y)}else{[void](Send $w ([ref]$q) 'Input.dispatchKeyEvent' @{type='keyDown';key='Enter';code='Enter';windowsVirtualKeyCode=13});[void](Send $w ([ref]$q) 'Input.dispatchKeyEvent' @{type='keyUp';key='Enter';code='Enter';windowsVirtualKeyCode=13})};$result.researchSubmitted=$true
  $deadline=(Get-Date).AddSeconds(180)
  do{
    Start-Sleep -Seconds 2
    $v=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>1&&r.height>1&&s.display!=='none'&&s.visibility!=='hidden'};const body=document.body?.innerText||'';const controls=[...document.querySelectorAll('button,[role=button],nb-button,input[type=checkbox],[role=checkbox],mat-checkbox,a')].filter(vis).map(e=>({tag:e.tagName,role:e.getAttribute('role'),text:String(e.innerText||e.textContent||'').trim().slice(0,240),aria:String(e.getAttribute('aria-label')||'').slice(0,240),title:String(e.getAttribute('title')||'').slice(0,240),checked:(e.checked===true||e.getAttribute('aria-checked')==='true')}));const checks=controls.filter(x=>x.role==='checkbox'||x.tag==='MAT-CHECKBOX'||x.tag==='INPUT').length;const importish=controls.some(x=>/import|\uAC00\uC838\uC624\uAE30|\uCD94\uAC00/i.test([x.text,x.aria,x.title].join(' '))&&!/add source|\uC18C\uC2A4 \uCD94\uAC00/i.test([x.text,x.aria,x.title].join(' ')));const busy=/searching|researching|\uAC80\uC0C9 \uC911|\uC870\uC0AC \uC911/i.test(body);return {body:body.slice(0,12000),controls:controls.slice(0,180),checks:checks,importish:importish,busy:busy}})()"
    if((-not [bool]$v.busy)-and(([int]$v.checks-gt0)-or[bool]$v.importish)){$result.researchResultsObserved=$true;$result.bodyText=[string]$v.body;$result.resultControls=@($v.controls);break}
  }while((Get-Date)-lt $deadline)
  if(-not $result.researchResultsObserved){$result.bodyText=[string](Eval $w ([ref]$q) '(document.body?.innerText||"").slice(0,12000)');throw 'RESEARCH_RESULTS_NOT_OBSERVED'}
  $after=Eval $w ([ref]$q) "(() => {const t=document.body?.innerText||'';const m=t.match(/\uC18C\uC2A4\s*([0-9]+)\uAC1C/i)||t.match(/([0-9]+)\s*sources?/i);return m?Number(m[1]):0})()";$result.sourceCountAfter=[int]$after
  $result.ok=$true
}catch{$result.error=$_.Exception.Message}
finally{
  if($w){try{$w.Dispose()}catch{}}
  $result.completedAt=(Get-Date).ToString('o')
  $result.centralPath=SaveCentral 'AGENT_1.1.96_FAST_RESEARCH_RESULTS_READONLY_RESULT.json' $result
}
$result|ConvertTo-Json -Depth 60 -Compress
if($result.ok){exit 0}else{exit 2}
