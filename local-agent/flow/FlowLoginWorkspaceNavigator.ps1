param(
  [int]$DebugPort=9224,
  [string]$TargetUrl='https://labs.google/fx/tools/flow',
  [int]$TimeoutSeconds=120,
  [string]$CentralRootOverride='',
  [switch]$RestartDedicatedChrome
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Version='FLOW_LOGIN_WORKSPACE_NAV_V1_20260829'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$FlowExtCandidates=@(
  (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0\flow-agent-bridge-v0.1.0'),
  (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0'),
  (Join-Path $Base 'Extension\Flow-Agent-Bridge'),
  (Join-Path $Base 'Extension\Google-AI-Local-Bridge-Flow')
)
function Find-Cft{Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}
function Find-FlowExt{foreach($p in $FlowExtCandidates){if(Test-Path -LiteralPath (Join-Path $p 'manifest.json') -PathType Leaf){return $p}};return ''}
function Dedicated{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine).Contains($UserData)})}catch{return @()}}
function Stop-Dedicated{foreach($p in @(Dedicated)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}};Start-Sleep 2}
function Find-Central{if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride)){return $CentralRootOverride};$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('내 드라이브\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)))){if(Test-Path -LiteralPath $c){return $c}}};return ''}
function Pages{try{return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/list") -TimeoutSec 3|Where-Object{$_.type -eq 'page'})}catch{return @()}}
function Invoke-PageAction([string]$WsUrl){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $node){$node=Get-Command node -ErrorAction Stop}
  $js=Join-Path $env:TEMP ('flow-nav-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $code=@'
const wsUrl=process.argv[2];
function conn(url){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);let id=0,p=new Map();ws.onopen=()=>resolve({ws,send:(m,params={})=>new Promise((res,rej)=>{const n=++id;p.set(n,{res,rej});ws.send(JSON.stringify({id:n,method:m,params}));})});ws.onerror=reject;ws.onmessage=e=>{let x;try{x=JSON.parse(e.data)}catch{return};if(x.id&&p.has(x.id)){const q=p.get(x.id);p.delete(x.id);x.error?q.rej(new Error(JSON.stringify(x.error))):q.res(x.result)}}})}
const c=await conn(wsUrl);try{
 const expr=`(()=>{const txt=(document.body?.innerText||'').slice(0,6000);const norm=s=>String(s||'').trim().replace(/\\s+/g,' ');const els=[...document.querySelectorAll('button,[role="button"],a,input[type="submit"]')].filter(e=>{const r=e.getBoundingClientRect();return r.width&&r.height&&!e.disabled});const items=els.map((e,i)=>({i,text:norm(e.innerText||e.textContent||e.value||e.getAttribute('aria-label')||''),tag:e.tagName,href:e.href||''}));const input=[...document.querySelectorAll('textarea,input[type="text"],[contenteditable="true"],[role="textbox"]')].find(e=>{const r=e.getBoundingClientRect();return r.width&&r.height&&!e.disabled});const url=location.href;let state='OTHER';if(/accounts\\.google\\.com/i.test(url))state='GOOGLE_LOGIN';else if(/labs\\.google\/fx\/tools\/flow/i.test(url)){if(input)state='FLOW_WORKSPACE';else state='FLOW_LANDING_OR_CONSENT'};else if(/labs\\.google/i.test(url))state='GOOGLE_LABS_INTERMEDIATE';const allow=[/^계속$/i,/^continue$/i,/^동의$/i,/^agree$/i,/^허용$/i,/^allow$/i,/^시작하기$/i,/^get started$/i,/^try flow$/i,/^open flow$/i,/^flow 시작/i,/^accept$/i,/^확인$/i,/^confirm$/i];let clicked=null;if(state!=='FLOW_WORKSPACE'){for(const it of items){if(allow.some(rx=>rx.test(it.text))){const el=els[it.i];try{el.click();clicked=it;break}catch{}}}}return {url,title:document.title,state,inputFound:!!input,clicked,buttons:items.slice(0,80),bodyText:txt};})()`;
 const r=await c.send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true,userGesture:true});console.log(JSON.stringify(r.result?.value||{}));
}finally{try{c.ws.close()}catch{};setTimeout(()=>process.exit(0),20)}
'@
  Set-Content -LiteralPath $js -Value $code -Encoding UTF8
  try{$p=Start-Process -FilePath $node.Source -ArgumentList @($js,$WsUrl) -NoNewWindow -PassThru -RedirectStandardOutput ($js+'.out') -RedirectStandardError ($js+'.err');if(-not $p.WaitForExit(15000)){try{Stop-Process -Id $p.Id -Force}catch{};throw 'FLOW_NAV_DOM_TIMEOUT'};$raw=Get-Content ($js+'.out') -Raw -ErrorAction SilentlyContinue;if(-not $raw){$er=Get-Content ($js+'.err') -Raw -ErrorAction SilentlyContinue;throw ('FLOW_NAV_DOM_EMPTY:'+ $er)};return (($raw.Trim()-split "`r?`n")[-1]|ConvertFrom-Json)}finally{Remove-Item $js,($js+'.out'),($js+'.err') -Force -ErrorAction SilentlyContinue}
}
$normalBefore=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{-not($_.CommandLine -and ([string]$_.CommandLine).Contains($UserData))}|ForEach-Object{[int]$_.ProcessId})
$ext=Find-FlowExt;if(-not $ext){throw 'FLOW_EXTENSION_NOT_FOUND'}
$cft=Find-Cft;if(-not $cft){throw 'CFT_NOT_FOUND'}
if($RestartDedicatedChrome){Stop-Dedicated}
if((Dedicated).Count -eq 0){Start-Process $cft.FullName -ArgumentList @("--user-data-dir=$UserData",'--profile-directory=Default',"--disable-extensions-except=$ext","--load-extension=$ext",("--remote-debugging-port=$DebugPort"),'--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check',$TargetUrl)|Out-Null}
$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$history=@();$workspace=$null;$needsCredential=$false;$last=$null
while((Get-Date)-lt $deadline){
  $pages=@(Pages);$page=$pages|Where-Object{$_.url -match 'accounts\.google\.com|labs\.google'}|Select-Object -First 1
  if(-not $page){Start-Sleep -Milliseconds 700;continue}
  $last=Invoke-PageAction ([string]$page.webSocketDebuggerUrl);$history += [ordered]@{at=(Get-Date).ToString('o');url=[string]$last.url;title=[string]$last.title;state=[string]$last.state;inputFound=[bool]$last.inputFound;clicked=$last.clicked}
  if([string]$last.state -eq 'FLOW_WORKSPACE' -and $last.inputFound){$workspace=$last;break}
  if([string]$last.state -eq 'GOOGLE_LOGIN'){
    $body=[string]$last.bodyText
    if($body -match '(?i)password|비밀번호|email or phone|이메일 또는 휴대전화'){$needsCredential=$true;break}
  }
  Start-Sleep -Seconds 2
}
$normalAfter=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{-not($_.CommandLine -and ([string]$_.CommandLine).Contains($UserData))}|ForEach-Object{[int]$_.ProcessId});$normalMissing=@($normalBefore|Where-Object{$normalAfter -notcontains $_})
$result=[ordered]@{ok=[bool]($workspace -and $normalMissing.Count -eq 0);action='FLOW_LOGIN_TO_WORKSPACE_NAVIGATION';version=$Version;workspaceReached=[bool]$workspace;credentialEntryRequired=$needsCredential;targetUrl=$TargetUrl;actualUrl=$(if($workspace){[string]$workspace.url}elseif($last){[string]$last.url}else{''});finalState=$(if($workspace){'FLOW_WORKSPACE'}elseif($needsCredential){'MANUAL_CREDENTIAL_REQUIRED'}elseif($last){[string]$last.state}else{'NO_TARGET_PAGE'});inputFound=$(if($workspace){[bool]$workspace.inputFound}else{$false});history=$history;normalChromeUntouched=($normalMissing.Count -eq 0);normalChromeMissingPids=$normalMissing;dedicatedChromeOnly=$true;generateClicked=$false;creditSpend=$false;at=(Get-Date).ToString('o')}
$central=Find-Central;if($central){$dir=Join-Path $central 'Runtime_Readback\FLOW';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$path=Join-Path $dir 'FLOW_LOGIN_TO_WORKSPACE_NAVIGATION.json';$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $path -Encoding UTF8;$result['resultPath']=$path}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}elseif($needsCredential){exit 3}else{exit 2}
