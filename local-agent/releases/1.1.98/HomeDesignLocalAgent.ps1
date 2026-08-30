param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.98'
$TargetNotebookId='8d1eda83-cfe3-4487-b2bc-266a5be3465c'
$TargetUrl='https://notebook.google.com/notebook/'+$TargetNotebookId
$Port=9223
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
function Tabs {
  $r=Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 4
  $o=$r.Content | ConvertFrom-Json
  $a=@()
  if($o -is [System.Array]){foreach($x in $o){$a += $x}}
  elseif($null -ne $o){$a += $o}
  return $a
}
function Recv($w,[int]$s){
  $b=New-Object byte[] 65536
  $m=New-Object IO.MemoryStream
  $c=New-Object Threading.CancellationTokenSource
  $c.CancelAfter([Math]::Max(1000,$s*1000))
  try{
    do{
      $g=New-Object ArraySegment[byte] -ArgumentList @(,$b)
      $r=$w.ReceiveAsync($g,$c.Token).GetAwaiter().GetResult()
      if($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'}
      $m.Write($b,0,$r.Count)
    }while(-not $r.EndOfMessage)
    return ([Text.Encoding]::UTF8.GetString($m.ToArray()) | ConvertFrom-Json)
  }finally{$c.Dispose();$m.Dispose()}
}
function Send($w,[ref]$q,[string]$m,[hashtable]$p=@{}){
  $q.Value++
  $id=$q.Value
  $j=@{id=$id;method=$m;params=$p} | ConvertTo-Json -Depth 30 -Compress
  $bb=[Text.Encoding]::UTF8.GetBytes($j)
  $g=New-Object ArraySegment[byte] -ArgumentList @(,$bb)
  $c=New-Object Threading.CancellationTokenSource
  $c.CancelAfter(8000)
  try{[void]$w.SendAsync($g,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()}
  while($true){
    $z=Recv $w 8
    if($z.id -eq $id){
      if($z.error){throw ('CDP_'+$m+':'+($z.error | ConvertTo-Json -Compress))}
      return $z.result
    }
  }
}
function Eval($w,[ref]$q,[string]$e){
  $r=Send $w $q 'Runtime.evaluate' @{expression=$e;returnByValue=$true;awaitPromise=$true;userGesture=$true}
  return $r.result.value
}
function Click($w,[ref]$q,[double]$x,[double]$y){
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$x;y=$y})
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mousePressed';x=$x;y=$y;button='left';clickCount=1})
  Start-Sleep -Milliseconds 100
  [void](Send $w $q 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$x;y=$y;button='left';clickCount=1})
}
$result=[ordered]@{
  ok=$false
  action='AGENT_1.1.98_FAST_RESEARCH_IMPORT_ONLY'
  version=$Version
  startedAt=(Get-Date).ToString('o')
  notebookUrl=''
  sourceTabClicked=$false
  fastResearchComplete=$false
  importButtonFound=$false
  importClicked=$false
  sourceCountBefore=0
  sourceCountAfter=0
  sourceVerified=$false
  normalChromeTouched=$false
  bridgeChanged=$false
  oauthChanged=$false
  scopeChanged=$false
  chatSubmitted=$false
  studioSelected=$false
  generateClicked=$false
  error=''
  centralPath=''
}
$w=$null
try{
  $t=@(Tabs | Where-Object {[string]$_.type -eq 'page'} | Where-Object {[string]$_.url -like 'https://notebook.google.com/*'} | Select-Object -First 1)
  if(-not $t){throw 'NO_NOTEBOOKLM_PAGE'}
  [System.Net.WebSockets.ClientWebSocket]$w=New-Object System.Net.WebSockets.ClientWebSocket
  $c=New-Object Threading.CancellationTokenSource
  $c.CancelAfter(8000)
  try{[void]$w.ConnectAsync([Uri]([string]$t[0].webSocketDebuggerUrl),$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()}
  $q=0
  [void](Send $w ([ref]$q) 'Runtime.enable' @{})
  [void](Send $w ([ref]$q) 'Page.enable' @{})
  [void](Send $w ([ref]$q) 'Page.bringToFront' @{})
  [void](Send $w ([ref]$q) 'Page.navigate' @{url=$TargetUrl})
  Start-Sleep -Seconds 2
  $result.notebookUrl=[string](Eval $w ([ref]$q) 'location.href')
  if($result.notebookUrl -ne $TargetUrl){throw 'EXACT_NOTEBOOK_NAVIGATION_FAILED'}
  $x=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const txt=e=>String([e.innerText,e.textContent,e.getAttribute?.('aria-label')].join(' ')).replace(/\s+/g,' ').trim();const a=[...document.querySelectorAll('*')].filter(vis).filter(e=>{const s=txt(e).toLowerCase();return s==='\\uCD9C\\uCC98'||s==='sources'||s.includes('\\uCD9C\\uCC98')||s.includes('sources')}).sort((p,n)=>{const a=p.getBoundingClientRect(),b=n.getBoundingClientRect();return a.width*a.height-b.width*b.height});if(!a.length)return{ok:false};let e=a[0].closest('button,[role=button],[role=tab],a,nb-button,nb-tab')||a[0];const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2}})()"
  if(-not $x.ok){throw 'SOURCE_TAB_NOT_FOUND'}
  Click $w ([ref]$q) ([double]$x.x) ([double]$x.y)
  $result.sourceTabClicked=$true
  Start-Sleep -Seconds 1
  $v=Eval $w ([ref]$q) "(() => {const t=document.body?.innerText||'';const m=t.match(/\\uC18C\\uC2A4\\s*([0-9]+)\\uAC1C/i)||t.match(/([0-9]+)\\s*sources?/i);return{body:t.slice(0,12000),count:m?Number(m[1]):0,complete:/Fast Research\\s*\\uC644\\uB8CC/i.test(t)}})()"
  $result.sourceCountBefore=[int]$v.count
  $result.fastResearchComplete=[bool]$v.complete
  if(-not $result.fastResearchComplete){throw 'FAST_RESEARCH_NOT_COMPLETE'}
  $x=Eval $w ([ref]$q) "(() => {const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled};const txt=e=>String([e.innerText,e.textContent,e.getAttribute?.('aria-label'),e.getAttribute?.('title')].join(' ')).replace(/\\s+/g,' ').trim();const a=[...document.querySelectorAll('button,[role=button],nb-button')].filter(vis).filter(e=>{const s=txt(e);return s==='\\uAC00\\uC838\\uC624\\uAE30'||s.includes('\\uAC00\\uC838\\uC624\\uAE30')||/^import$/i.test(s)});if(a.length!==1)return{ok:false,count:a.length,sample:a.map(e=>txt(e).slice(0,160)).slice(0,10)};const e=a[0];const r=e.getBoundingClientRect();return{ok:true,x:r.left+r.width/2,y:r.top+r.height/2,text:txt(e).slice(0,160)}})()"
  if(-not $x.ok){throw ('IMPORT_BUTTON_NOT_UNIQUE count='+[string]$x.count)}
  $result.importButtonFound=$true
  Click $w ([ref]$q) ([double]$x.x) ([double]$x.y)
  $result.importClicked=$true
  $deadline=(Get-Date).AddSeconds(90)
  do{
    Start-Sleep -Seconds 2
    $v=Eval $w ([ref]$q) "(() => {const t=document.body?.innerText||'';const m=t.match(/\\uC18C\\uC2A4\\s*([0-9]+)\\uAC1C/i)||t.match(/([0-9]+)\\s*sources?/i);return{count:m?Number(m[1]):0,body:t.slice(0,8000)}})()"
    $result.sourceCountAfter=[int]$v.count
    if($result.sourceCountAfter -gt 0){$result.sourceVerified=$true;break}
  }while((Get-Date) -lt $deadline)
  if(-not $result.sourceVerified){throw 'SOURCE_COUNT_ZERO_AFTER_IMPORT'}
  $result.ok=$true
}catch{
  $result.error=$_.Exception.Message
}
finally{
  if($w){try{$w.Dispose()}catch{}}
  $result.completedAt=(Get-Date).ToString('o')
  $result.centralPath=SaveCentral 'AGENT_1.1.98_FAST_RESEARCH_IMPORT_ONLY_RESULT.json' $result
}
$result | ConvertTo-Json -Depth 60 -Compress
if($result.ok){exit 0}else{exit 2}
