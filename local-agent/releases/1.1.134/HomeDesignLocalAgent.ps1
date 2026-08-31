param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.134'
$TargetUrl='https://notebook.google.com/notebook/8d1eda83-cfe3-4487-b2bc-266a5be3465c'
$Port=9223
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='AGENT_1.1.134_SLIDES_REAL_CARD_WAIT_READONLY_RESULT.json'
$Marker=Join-Path $Root $Receipt
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function Save($o){$j=$o|ConvertTo-Json -Depth 100;$j|Set-Content -LiteralPath $Marker -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function Tabs{$o=(Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 3).Content|ConvertFrom-Json;return @($o|Where-Object{[string]$_.type-eq'page'})}
function Recv($w,[int]$sec){$b=New-Object byte[] 262144;$m=New-Object IO.MemoryStream;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter([Math]::Max(1000,$sec*1000));try{do{$g=New-Object ArraySegment[byte] -ArgumentList @(,$b);$z=$w.ReceiveAsync($g,$c.Token).GetAwaiter().GetResult();if($z.MessageType-eq[System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'};$m.Write($b,0,$z.Count)}while(-not$z.EndOfMessage);return([Text.Encoding]::UTF8.GetString($m.ToArray())|ConvertFrom-Json)}finally{$c.Dispose();$m.Dispose()}}
function Send($w,[ref]$q,[string]$method,[hashtable]$params=@{}){$q.Value++;$id=$q.Value;$bb=[Text.Encoding]::UTF8.GetBytes((@{id=$id;method=$method;params=$params}|ConvertTo-Json -Depth 30 -Compress));$g=New-Object ArraySegment[byte] -ArgumentList @(,$bb);$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000);try{[void]$w.SendAsync($g,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()};while($true){$z=Recv $w 8;if($z.id-eq$id){if($z.error){throw('CDP_'+$method+':'+($z.error|ConvertTo-Json -Compress))};return $z.result}}}
function Eval($w,[ref]$q,[string]$e){$z=Send $w $q 'Runtime.evaluate' @{expression=$e;returnByValue=$true;awaitPromise=$true;userGesture=$false};return $z.result.value}
function Connect([string]$u){$w=New-Object System.Net.WebSockets.ClientWebSocket;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000);try{[void]$w.ConnectAsync([Uri]$u,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()};return $w}
$r=[ordered]@{ok=$false;action='AGENT_1.1.134_SLIDES_REAL_CARD_WAIT_READONLY';version=$Version;targetUrl=$TargetUrl;exactTab=$false;waitSeconds=240;polls=0;busySeen=$false;busyFinal=$false;candidateCount=0;candidates=@();selectedCard=$null;bodySample='';readOnly=$true;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;stage='START';error='';startedAt=(Get-Date).ToString('o')}
$w=$null
try{$r.stage='EXACT_TAB';$tab=@(Tabs|Where-Object{[string]$_.url-eq$TargetUrl}|Select-Object -First 1);if(-not$tab){throw 'EXACT_NOTEBOOK_TAB_NOT_FOUND'};$r.exactTab=$true;$w=Connect([string]$tab[0].webSocketDebuggerUrl);$q=0;[void](Send $w ([ref]$q) 'Runtime.enable' @{});[void](Send $w ([ref]$q) 'Page.bringToFront' @{});$r.stage='WAIT_REAL_SLIDES_CARD';$js=@'
(() => {
 const slide=String.fromCharCode(49836,46972,51060,46300,32,51088,47308);
 const gen=String.fromCharCode(49373,49457,32,51473);
 const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};
 const body=String(document.body?.innerText||'');
 const busy=body.includes(slide+' '+gen)||body.includes(slide+'...')&&body.includes(gen)||/slides?[^\n]{0,80}(generating|creating)/i.test(body);
 const nodes=[...document.querySelectorAll('section,article,div,[role=group],[role=region]')].filter(vis);
 const hits=[];
 for(const e of nodes){const text=String(e.innerText||e.textContent||'').trim();if(!text||text.length<5||text.length>5000)continue;const low=text.toLowerCase();if(!(text.includes(slide)||low.includes('slide deck')||low.includes('slides')))continue;const bs=[...e.querySelectorAll('button,[role=button]')].filter(vis);const more=bs.find(b=>{const t=String([b.innerText,b.textContent,b.getAttribute('aria-label'),b.getAttribute('title'),b.querySelector('mat-icon')?.textContent].join(' '));return /more_vert|more|menu/i.test(t)||t.includes(String.fromCharCode(45908,48372,44592))});if(!more)continue;const rr=e.getBoundingClientRect();hits.push({text:text.slice(0,1800),len:text.length,x:rr.x,y:rr.y,w:rr.width,h:rr.height,menu:String([more.innerText,more.textContent,more.getAttribute('aria-label'),more.getAttribute('title'),more.querySelector('mat-icon')?.textContent].join(' ')).slice(0,300)});}
 hits.sort((a,b)=>a.len-b.len);
 return {busy,count:hits.length,hits:hits.slice(0,20),body:body.slice(-6000),slideText:slide};
})()
'@;$deadline=(Get-Date).AddSeconds($r.waitSeconds);$x=$null;do{$r.polls++;$x=Eval $w ([ref]$q) $js;if([bool]$x.busy){$r.busySeen=$true};if(-not[bool]$x.busy-and[int]$x.count-gt0){break};Start-Sleep -Seconds 3}while((Get-Date)-lt$deadline);$r.busyFinal=[bool]$x.busy;$r.candidateCount=[int]$x.count;$r.candidates=@($x.hits);$r.bodySample=[string]$x.body;if($r.candidateCount-gt0){$r.selectedCard=$r.candidates[0]};$r.ok=(-not$r.busyFinal-and$r.candidateCount-gt0);if(-not$r.ok){throw 'REAL_SLIDES_CARD_NOT_READY_WITH_MENU'};$r.stage='DONE'}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{if($w){try{$w.Dispose()}catch{}};$r.completedAt=(Get-Date).ToString('o');Save $r};$r|ConvertTo-Json -Depth 100 -Compress;if($r.ok){exit 0}else{exit 2}
