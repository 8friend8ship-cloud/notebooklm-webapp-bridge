param(
  [ValidateSet('NOTEBOOKLM','FLOW','AI_STUDIO','FRONT_QA','GENERIC')][string]$Service='GENERIC',
  [Parameter(Mandatory=$true)][string]$TargetUrl,
  [int]$RemoteDebuggingPort=9231,
  [int]$TimeoutSeconds=40,
  [switch]$RestartDedicatedChrome,
  [switch]$ProbeInput,
  [string]$Sentinel=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='MANAGED_EXTENSION_EXACT_TARGET_V2_20260828'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'

function Find-Central {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function Find-CftChrome {
  $root=Join-Path $Base 'ChromeForTesting'
  if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'CHROME_FOR_TESTING_ROOT_NOT_FOUND'}
  $hit=Get-ChildItem -LiteralPath $root -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
  if(-not $hit){throw 'CHROME_FOR_TESTING_EXE_NOT_FOUND'}
  return $hit.FullName
}
function Find-NotebookExtension {
  $preferred=@(
    (Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'),
    (Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge-CANONICAL'),
    (Join-Path $Base 'Extension\NotebookLM')
  )
  foreach($p in $preferred){
    $m=Join-Path $p 'manifest.json'
    if(Test-Path -LiteralPath $m -PathType Leaf){
      try{$j=Get-Content -LiteralPath $m -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$j.name -match 'NotebookLM'){return $p}}catch{}
    }
  }
  $root=Join-Path $Base 'Extension'
  if(Test-Path -LiteralPath $root){
    foreach($m in @(Get-ChildItem -LiteralPath $root -Filter manifest.json -Recurse -File -ErrorAction SilentlyContinue)){
      try{$j=Get-Content -LiteralPath $m.FullName -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$j.name -match 'NotebookLM'){return $m.Directory.FullName}}catch{}
    }
  }
  throw 'NOTEBOOKLM_EXTENSION_PATH_NOT_FOUND'
}
function Get-NormalChromeRoots {
  try{
    return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{
      $cmd=[string]$_.CommandLine
      (-not $cmd -or -not $cmd.Contains($DedicatedUserData)) -and (-not $cmd -or $cmd -notmatch '(?i)(^|\s)--type=')
    }|ForEach-Object{[int]$_.ProcessId})
  }catch{return @()}
}
function Stop-Dedicated {
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine).Contains($DedicatedUserData)})){
    try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}
  }
  Start-Sleep -Milliseconds 900
}
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[int]$TimeoutMs=5000){
  $buf=New-Object byte[] 262144
  $ms=New-Object IO.MemoryStream
  $cts=New-Object Threading.CancellationTokenSource
  $cts.CancelAfter($TimeoutMs)
  try{
    do{
      $seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf)
      $r=$Ws.ReceiveAsync($seg,$cts.Token).GetAwaiter().GetResult()
      if($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'}
      $ms.Write($buf,0,$r.Count)
    }while(-not $r.EndOfMessage)
    return ([Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json)
  }finally{$cts.Dispose();$ms.Dispose()}
}
$script:CdpEvents=New-Object System.Collections.ArrayList
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){
  $Seq.Value++
  $id=$Seq.Value
  $json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 40 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
  $Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
  while($true){
    $msg=Receive-Cdp $Ws 7000
    if($msg.id -eq $id){
      if($msg.error){throw ('CDP_'+$Method+':'+($msg.error|ConvertTo-Json -Compress))}
      return $msg.result
    }
    if($msg.method){[void]$script:CdpEvents.Add($msg)}
  }
}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expression,[Nullable[int]]$ContextId=$null){
  $p=@{expression=$Expression;returnByValue=$true;awaitPromise=$true;userGesture=$true}
  if($null -ne $ContextId){$p.contextId=[int]$ContextId}
  $r=Send-Cdp $Ws $Seq 'Runtime.evaluate' $p
  if($r.exceptionDetails){throw ('CDP_RUNTIME_EXCEPTION:'+($r.exceptionDetails|ConvertTo-Json -Depth 8 -Compress))}
  return $r.result.value
}
function Get-Target([int]$Port,[string]$NotebookId){
  try{$targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 2)}catch{return $null}
  return $targets|Where-Object{$_.type -eq 'page' -and ([string]$_.url).Contains($NotebookId) -and $_.webSocketDebuggerUrl}|Select-Object -First 1
}

$normalBefore=@(Get-NormalChromeRoots)
$chrome=Find-CftChrome
$extPath=Find-NotebookExtension
$manifest=Get-Content -LiteralPath (Join-Path $extPath 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$manifest.manifest_version -ne 3){throw 'NOTEBOOKLM_MANIFEST_NOT_V3'}
$arch=$(if($manifest.background -and $manifest.background.service_worker){'background_service_worker'}elseif(@($manifest.content_scripts).Count -gt 0){'content_script'}else{'extension_page'})
try{$u=[uri]$TargetUrl;$notebookId=($u.AbsolutePath.Trim('/') -split '/')[-1]}catch{throw 'TARGET_URL_INVALID'}
if(-not $notebookId){throw 'NOTEBOOK_ID_NOT_FOUND_IN_URL'}
if($RestartDedicatedChrome){Stop-Dedicated}
$args=@(
  "--user-data-dir=$DedicatedUserData",
  '--profile-directory=Default',
  '--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',
  "--load-extension=$extPath",
  "--remote-debugging-port=$RemoteDebuggingPort",
  '--remote-debugging-address=127.0.0.1',
  '--new-window',
  $TargetUrl
)
Start-Process -FilePath $chrome -ArgumentList $args -WorkingDirectory (Split-Path -Parent $chrome)|Out-Null
$deadline=(Get-Date).AddSeconds([Math]::Max(15,$TimeoutSeconds));$target=$null
do{$target=Get-Target $RemoteDebuggingPort $notebookId;if($target){break};Start-Sleep -Milliseconds 500}while((Get-Date)-lt $deadline)
if(-not $target){throw 'EXACT_NOTEBOOK_TARGET_NOT_FOUND'}
$ws=New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
$seq=0
$extensionContextActive=$false;$extensionOrigin='';$extensionContextId=$null;$markerAttempts=0
try{
  $readyDeadline=(Get-Date).AddSeconds(20)
  do{
    $markerAttempts++
    $script:CdpEvents.Clear()
    try{[void](Send-Cdp $ws ([ref]$seq) 'Runtime.disable' @{})}catch{}
    [void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{})
    foreach($ev in @($script:CdpEvents|Where-Object{$_.method -eq 'Runtime.executionContextCreated'})){
      $ctx=$ev.params.context
      if(-not $ctx -or -not $ctx.id){continue}
      try{
        $v=Eval-Cdp $ws ([ref]$seq) 'Boolean(globalThis.__NLM_WEBAPP_BRIDGE_LOADED__)' ([int]$ctx.id)
        if([bool]$v){$extensionContextActive=$true;$extensionContextId=[int]$ctx.id;$extensionOrigin=[string]$ctx.origin;break}
      }catch{}
    }
    if($extensionContextActive){break}
    Start-Sleep -Milliseconds 600
  }while((Get-Date)-lt $readyDeadline)

  $sentinelValue=$(if($Sentinel){$Sentinel}else{'CENTRAL_NLM_EXACT_V2_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()})
  $sentinelJson=$sentinelValue|ConvertTo-Json -Compress
  $probeExpr=@"
(()=>{
 const roots=[document],q=[document],seen=new Set(q);while(q.length){const r=q.shift();let es=[];try{es=[...r.querySelectorAll('*')]}catch{};for(const e of es){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot);q.push(e.shadowRoot)}}}
 const all=[];for(const r of roots){let es=[];try{es=[...r.querySelectorAll('textarea,input[type="text"],input:not([type]),[role="textbox"],[contenteditable="true"],[contenteditable="plaintext-only"],[aria-multiline="true"]')]}catch{};for(const e of es){const z=e.getBoundingClientRect?.()||{};if(!(z.width>2&&z.height>2)||e.disabled||e.closest?.('[role="dialog"],dialog'))continue;const meta=[e.getAttribute?.('placeholder'),e.getAttribute?.('aria-label'),e.getAttribute?.('data-placeholder'),e.getAttribute?.('data-testid')].filter(Boolean).join(' ').toLowerCase();if(/search|검색/.test(meta))continue;const score=/질문|메시지|ask|chat|message|prompt|query|anything|type/.test(meta)?10:0;all.push({e,score,meta})}}
 all.sort((a,b)=>b.score-a.score);const x=all[0];if(!x)return {found:false,candidateCount:0};const e=x.e;const old=('value'in e)?e.value:(e.innerText??e.textContent??'');
 const set=v=>{e.focus?.();if(e instanceof HTMLTextAreaElement){const s=Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value')?.set;s?s.call(e,v):e.value=v}else if(e instanceof HTMLInputElement){const s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;s?s.call(e,v):e.value=v}else{e.textContent=v}try{e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}))}catch{e.dispatchEvent(new Event('input',{bubbles:true}))}e.dispatchEvent(new Event('change',{bubbles:true}))};
 set($sentinelJson);const read=('value'in e)?e.value:(e.innerText??e.textContent??'');set(old);const restored=(('value'in e)?e.value:(e.innerText??e.textContent??''))===old;return {found:true,verified:read===$sentinelJson,restored,candidateCount:all.length,tag:e.tagName,meta:x.meta,url:location.href,title:document.title,loginRequired:/sign in to|sign in with google|로그인|google 계정으로/i.test(document.body?.innerText||'')};
})()
"@
  $input=$(if($ProbeInput){Eval-Cdp $ws ([ref]$seq) $probeExpr}else{[pscustomobject]@{found=$true;verified=$true;restored=$true;candidateCount=0;url=[string]$target.url;title=[string]$target.title;loginRequired=$false}})
}finally{try{$ws.Dispose()}catch{}}
$normalAfter=@(Get-NormalChromeRoots);$missing=@($normalBefore|Where-Object{$normalAfter -notcontains $_})
$targetVerified=[bool](([string]$target.url).Contains($notebookId))
$inputGate=[bool]($input -and $input.found -and $input.verified -and $input.restored -and -not $input.loginRequired)
$ok=[bool]($targetVerified -and $extensionContextActive -and $inputGate -and $missing.Count -eq 0)
$result=[ordered]@{
  ok=$ok;version=$Version;service=$Service;targetUrlRequested=$TargetUrl;targetUrlActual=[string]$target.url;notebookId=$notebookId;
  targetContextOpened=$true;targetContextVerified=$targetVerified;extensionPath=$extPath;manifestName=[string]$manifest.name;manifestVersion=[string]$manifest.version;architecture=$arch;
  extensionContextActive=$extensionContextActive;extensionContextOrigin=$extensionOrigin;extensionContextId=$extensionContextId;markerAttempts=$markerAttempts;
  inputProbeRequested=[bool]$ProbeInput;inputFound=[bool]$input.found;inputVerified=[bool]$input.verified;inputRestored=[bool]$input.restored;input=$input;
  normalChromeUntouched=($missing.Count -eq 0);normalChromeMissingRoots=$missing;normalChromeRootsBefore=$normalBefore;normalChromeRootsAfter=$normalAfter;
  chromeForTesting=$chrome;dedicatedUserData=$DedicatedUserData;remoteDebuggingPort=$RemoteDebuggingPort;
  generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;chromeSettingsChanged=$false;at=(Get-Date).ToString('o')
}
$central=Find-Central
if($central){$dir=Join-Path $central 'Runtime_Readback\Chrome_Exact_Target';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$path=Join-Path $dir ('EXACT_TARGET_V2_'+$Service+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.json');$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $path -Encoding UTF8;$result['resultPath']=$path}
$result|ConvertTo-Json -Depth 50 -Compress
if($ok){exit 0}else{exit 2}
