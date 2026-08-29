param(
  [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [string]$ArtifactText='contentos-stage-table.xlsx',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=45
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$StandardDownloads=Join-Path $env:USERPROFILE 'Downloads'
$Started=Get-Date

function Find-Chrome {
  if(Test-Path -LiteralPath $CftRoot){
    $x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
    if($x){return [string]$x.FullName}
  }
  foreach($c in @((Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))){if($c -and (Test-Path -LiteralPath $c)){return [string]$c}}
  throw 'CHROME_EXE_NOT_FOUND'
}
function Dedicated-Procs { try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$UserData*"})}catch{return @()} }
function Debug-Ready { try{$v=Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/version") -TimeoutSec 2;return [bool]$v.webSocketDebuggerUrl}catch{return $false} }
function Start-DebugChrome {
  if(Debug-Ready){return}
  foreach($p in @(Dedicated-Procs)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Milliseconds 800
  $chrome=Find-Chrome
  $args=@("--remote-debugging-port=$RemoteDebuggingPort",'--remote-allow-origins=*',"--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$NotebookUrl)
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  $deadline=(Get-Date).AddSeconds(15)
  do{Start-Sleep -Milliseconds 400;if(Debug-Ready){return}}while((Get-Date)-lt $deadline)
  throw 'CDP_PORT_NOT_READY'
}
function Get-CdpTabs {
  $raw=Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3
  $flat=New-Object Collections.Generic.List[object]
  foreach($item in @($raw)){
    if($item -is [System.Array]){foreach($inner in @($item)){$flat.Add($inner)}}else{$flat.Add($item)}
  }
  return @($flat)
}
function Get-NotebookTab {
  $tabs=@(Get-CdpTabs)
  $matches=@($tabs|Where-Object{[string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/notebook/*'})
  if($matches.Count -lt 1){return $null}
  return $matches[0]
}
function Get-WebSocketUri($Tab) {
  $values=@($Tab.webSocketDebuggerUrl)
  $url=''
  foreach($v in $values){$s=[string]$v;if($s -match '^wss?://'){$url=$s;break}}
  if(-not $url){throw ('CDP_WEBSOCKET_URL_INVALID:type='+$Tab.GetType().FullName+';count='+$values.Count)}
  $uri=$null
  if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri)){throw ('CDP_WEBSOCKET_URI_PARSE_FAILED:'+ $url)}
  return $uri
}
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws){
  $buf=New-Object byte[] 65536;$ms=New-Object IO.MemoryStream
  try{do{$seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf);$res=$Ws.ReceiveAsync($seg,[Threading.CancellationToken]::None).GetAwaiter().GetResult();if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'};$ms.Write($buf,0,$res.Count)}while(-not $res.EndOfMessage);return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json}finally{$ms.Dispose()}
}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){
  $Seq.Value++;$id=$Seq.Value;$json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes);$Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
  while($true){$msg=Receive-Cdp $Ws;if($msg.id -eq $id){if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))};return $msg.result}}
}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){$r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true;userGesture=$true};return $r.result.value}
function Click-Cdp($Ws,[ref]$Seq,[double]$X,[double]$Y){[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseMoved';x=$X;y=$Y});[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mousePressed';x=$X;y=$Y;button='left';clickCount=1});Start-Sleep -Milliseconds 80;[void](Send-Cdp $Ws $Seq 'Input.dispatchMouseEvent' @{type='mouseReleased';x=$X;y=$Y;button='left';clickCount=1})}
function Read-DownloadDirs {
  $dirs=New-Object Collections.Generic.List[string];if($StandardDownloads){$dirs.Add($StandardDownloads)}
  $pref=Join-Path $UserData 'Default\Preferences';if(Test-Path -LiteralPath $pref){try{$j=Get-Content -LiteralPath $pref -Raw -Encoding UTF8|ConvertFrom-Json;$d=[string]$j.download.default_directory;if($d -and -not $dirs.Contains($d)){$dirs.Add($d)}}catch{}}
  return @($dirs|Where-Object{$_ -and (Test-Path -LiteralPath $_)}|Select-Object -Unique)
}
function Find-NewFile([datetime]$Since){$hits=@();foreach($d in @(Read-DownloadDirs)){$hits+=@(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTime -ge $Since.AddSeconds(-2) -and $_.Length -gt 0 -and $_.Extension -notin @('.crdownload','.tmp')}|Sort-Object LastWriteTime -Descending)};return @($hits|Sort-Object LastWriteTime -Descending|Select-Object -First 10)}

$result=[ordered]@{ok=$false;action='NOTEBOOKLM_EXISTING_DOWNLOAD_CDP_TRUSTED_CLICK_V2';notebookUrl=$NotebookUrl;artifactText=$ArtifactText;startedAt=$Started.ToString('o');cdpTab=$null;webSocketUrl='';menu=$null;download=$null;downloadDirs=@();files=@();error=''}
$ws=$null
try{
  Start-DebugChrome
  $deadline=(Get-Date).AddSeconds(20);$tab=$null
  do{$tab=Get-NotebookTab;if($tab){break};Start-Sleep -Milliseconds 500}while((Get-Date)-lt $deadline)
  if(-not $tab){throw 'NOTEBOOK_TAB_NOT_FOUND'}
  $uri=Get-WebSocketUri $tab
  $result.cdpTab=[ordered]@{type=[string]$tab.type;url=[string]$tab.url;title=[string]$tab.title}
  $result.webSocketUrl=$uri.AbsoluteUri
  $ws=New-Object System.Net.WebSockets.ClientWebSocket;$ws.ConnectAsync($uri,[Threading.CancellationToken]::None).GetAwaiter().GetResult();$seq=0
  [void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{});[void](Send-Cdp $ws ([ref]$seq) 'Page.bringToFront' @{});Start-Sleep -Milliseconds 900
  $artifactJson=$ArtifactText|ConvertTo-Json -Compress
  $findMenu=@"
(() => { const wanted=String($artifactJson).toLowerCase(); const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'}; const roots=[document],seen=new Set(roots);for(let i=0;i<roots.length;i++){for(const e of roots[i].querySelectorAll?.('*')||[]){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot)}}} const nodes=[];for(const r of roots){nodes.push(...(r.querySelectorAll?.('section,article,div,[role=group],[role=region]')||[]))} const hits=nodes.filter(vis).filter(e=>String(e.innerText||e.textContent||'').toLowerCase().includes(wanted)).sort((a,b)=>String(a.innerText||'').length-String(b.innerText||'').length); for(const root of hits){const bs=[...root.querySelectorAll('button,[role=button]')].filter(vis);const b=bs.find(x=>/more|menu|option|더보기|메뉴|more_vert/.test(String([x.innerText,x.textContent,x.getAttribute('aria-label'),x.getAttribute('title')].join(' ')).toLowerCase()));if(b){const q=b.getBoundingClientRect();return {ok:true,x:q.left+q.width/2,y:q.top+q.height/2,text:String(root.innerText||root.textContent||'').slice(0,500)}}} return {ok:false,error:'ARTIFACT_MENU_NOT_FOUND',candidateCount:hits.length}; })()
"@
  $menu=Eval-Cdp $ws ([ref]$seq) $findMenu;$result.menu=$menu;if(-not $menu.ok){throw $menu.error};Click-Cdp $ws ([ref]$seq) ([double]$menu.x) ([double]$menu.y);Start-Sleep -Milliseconds 700
  $findDownload=@"
(() => { const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'}; const roots=[document],seen=new Set(roots);for(let i=0;i<roots.length;i++){for(const e of roots[i].querySelectorAll?.('*')||[]){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot)}}} const els=[];for(const r of roots){els.push(...(r.querySelectorAll?.('button,[role=button],[role=menuitem],a')||[]))} for(const e of els.filter(vis)){const t=String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).toLowerCase();if(t.includes('download')||t.includes('다운로드')){const q=e.getBoundingClientRect();return {ok:true,x:q.left+q.width/2,y:q.top+q.height/2,text:t.slice(0,300)}}} return {ok:false,error:'DOWNLOAD_MENU_ITEM_NOT_FOUND'}; })()
"@
  $dl=Eval-Cdp $ws ([ref]$seq) $findDownload;$result.download=$dl;if(-not $dl.ok){throw $dl.error};$clickAt=Get-Date;Click-Cdp $ws ([ref]$seq) ([double]$dl.x) ([double]$dl.y)
  $result.downloadDirs=@(Read-DownloadDirs);$until=(Get-Date).AddSeconds($TimeoutSeconds);$files=@();do{Start-Sleep -Milliseconds 500;$files=@(Find-NewFile $clickAt);if($files.Count -gt 0){break}}while((Get-Date)-lt $until)
  $result.files=@($files|ForEach-Object{[ordered]@{name=$_.Name;fullName=$_.FullName;size=[int64]$_.Length;lastWriteTime=$_.LastWriteTime.ToString('o')}})
  if($result.files.Count -lt 1){throw 'REAL_FILE_NOT_FOUND_AFTER_TRUSTED_CDP_CLICK'};$result.ok=$true
}catch{$result.error=$_.Exception.Message}
finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 20 -Compress
if($result.ok){exit 0}else{exit 2}
