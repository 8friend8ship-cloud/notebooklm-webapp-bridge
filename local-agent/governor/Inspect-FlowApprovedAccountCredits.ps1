param(
  [int]$DebugPort=9224,
  [switch]$NavigateWorkspace,
  [switch]$CurrentScreenOnly,
  [int]$TimeoutSeconds=120,
  [string]$CentralRootOverride=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='FLOW_CDP_ASCII_SAFE_V4_20260829'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$FlowUrl='https://labs.google/fx/tools/flow'
function FindCentral {
  if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride)){ return $CentralRootOverride }
  $name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not $d.Root){ continue }
    foreach($c in @((Join-Path $d.Root $name),(Join-Path $d.Root ('My Drive\'+$name)))){
      if(Test-Path -LiteralPath $c -PathType Container){ return $c }
    }
  }
  return ''
}
function Pages {
  try { return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/list") -TimeoutSec 3 | Where-Object { $_.type -eq 'page' }) }
  catch { return @() }
}
function InvokeDom([string]$WsUrl,[bool]$AllowClick){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue
  if(-not $node){ $node=Get-Command node -ErrorAction Stop }
  $js=Join-Path $env:TEMP ('flow-cdp-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $code=@'
const wsUrl=process.argv[2],allowClick=process.argv[3]==='1';
function connect(url){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);let id=0,p=new Map();ws.onopen=()=>resolve({ws,send:(m,params={})=>new Promise((res,rej)=>{const n=++id;p.set(n,{res,rej});ws.send(JSON.stringify({id:n,method:m,params}));})});ws.onerror=reject;ws.onmessage=e=>{let x;try{x=JSON.parse(e.data)}catch{return};if(x.id&&p.has(x.id)){const q=p.get(x.id);p.delete(x.id);x.error?q.rej(new Error(JSON.stringify(x.error))):q.res(x.result)}}})}
const c=await connect(wsUrl);
try{
  const expr=`(()=>{const vis=e=>{const r=e.getBoundingClientRect();return !!(r.width&&r.height)&&!e.disabled};const controls=[...document.querySelectorAll('button,[role="button"],a,input[type="submit"]')].filter(vis);const inputs=[...document.querySelectorAll('textarea,input[type="text"],[contenteditable="true"],[role="textbox"]')].filter(vis);const items=controls.map((e,i)=>({i,text:String(e.innerText||e.textContent||e.value||e.getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ').slice(0,180),tag:e.tagName,href:e.href||''}));const ins=inputs.map(e=>({tag:e.tagName,placeholder:e.getAttribute('placeholder')||'',aria:e.getAttribute('aria-label')||'',value:String(('value'in e)?e.value:(e.innerText||'')).slice(0,300)}));const url=location.href;let state='OTHER';if(/accounts\\.google\\.com/i.test(url))state='GOOGLE_LOGIN';else if(/labs\\.google\/fx\/tools\/flow/i.test(url))state=ins.length?'FLOW_WORKSPACE':'FLOW_LANDING';else if(/labs\\.google/i.test(url))state='LABS_INTERMEDIATE';let clicked=null;if(${allowClick?'true':'false'}&&state!=='FLOW_WORKSPACE'){const rx=[/^continue$/i,/^agree$/i,/^allow$/i,/^get started$/i,/^try flow$/i,/^open flow$/i,/^confirm$/i,/resume/i,/recent/i,/open project/i,/new project/i,/create project/i];for(const it of items){if(rx.some(r=>r.test(it.text))){try{controls[it.i].click();clicked=it;break}catch{}}}}return {url,title:document.title,state,inputs:ins,buttons:items.slice(0,120),clicked,passwordPrompt:!!document.querySelector('input[type="password"]'),emailPrompt:!!document.querySelector('input[type="email"]')};})()`;
  const r=await c.send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true,userGesture:true});
  console.log(JSON.stringify(r.result?.value||{}));
} finally { try{c.ws.close()}catch{}; setTimeout(()=>process.exit(0),30) }
'@
  Set-Content -LiteralPath $js -Value $code -Encoding ASCII
  try {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$node.Source
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.Arguments=('"'+$js+'" "'+$WsUrl+'" '+$(if($AllowClick){'1'}else{'0'}))
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    [void]$p.Start()
    $ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit(15000)){ try{Stop-Process -Id $p.Id -Force}catch{}; throw 'FLOW_CDP_DOM_TIMEOUT' }
    $raw=$ot.Result.Trim()
    if(-not $raw){ throw ('FLOW_CDP_DOM_EMPTY:'+ $et.Result.Trim()) }
    return (($raw -split "`r?`n")[-1] | ConvertFrom-Json)
  } finally { Remove-Item $js -Force -ErrorAction SilentlyContinue }
}
function WriteReceipt($Object,[string]$Name){
  $central=FindCentral
  if($central){
    $dir=Join-Path $central 'Runtime_Readback\Flow_Bridge_Direct'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $path=Join-Path $dir $Name
    $Object | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding UTF8
  }
}
$pages=@(Pages)
if($CurrentScreenOnly){
  $page=$pages | Where-Object { ([string]$_.url) -match 'labs\.google|accounts\.google' } | Select-Object -First 1
  if(-not $page){ throw 'CDP_FLOW_PAGE_NOT_FOUND_ON_CURRENT_SCREEN' }
  $scan=InvokeDom ([string]$page.webSocketDebuggerUrl) $false
  $extTargets=@($pages | Where-Object { ([string]$_.url) -like 'chrome-extension://*' } | ForEach-Object { [ordered]@{url=[string]$_.url;title=[string]$_.title} })
  $input=@($scan.inputs) | Select-Object -First 1
  $ok=[bool]([string]$scan.state -eq 'FLOW_WORKSPACE' -and $input)
  $result=[ordered]@{ok=$ok;action='FLOW_CURRENT_SCREEN_CDP_READONLY';version=$Version;state=[string]$scan.state;pageUrl=[string]$scan.url;pageTitle=[string]$scan.title;inputFound=[bool]$input;input=$input;buttons=@($scan.buttons);extensionTargets=$extTargets;generateClicked=$false;creditSpend=$false;readOnly=$true;checkedAt=(Get-Date).ToString('o')}
  WriteReceipt $result 'FLOW_CURRENT_SCREEN_CDP_READONLY.json'
  $result | ConvertTo-Json -Depth 40 -Compress
  if($ok){ exit 0 } else { exit 2 }
}
if($NavigateWorkspace){
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
  $history=@();$final=$null;$credential=$false
  while((Get-Date)-lt $deadline){
    $pages=@(Pages)
    $page=$pages | Where-Object { ([string]$_.url) -match 'labs\.google|accounts\.google' } | Select-Object -First 1
    if(-not $page){ Start-Sleep -Milliseconds 600; continue }
    $scan=InvokeDom ([string]$page.webSocketDebuggerUrl) $true
    $history += [ordered]@{at=(Get-Date).ToString('o');url=[string]$scan.url;state=[string]$scan.state;inputCount=@($scan.inputs).Count;clicked=$scan.clicked}
    $final=$scan
    if([string]$scan.state -eq 'FLOW_WORKSPACE' -and @($scan.inputs).Count){ break }
    if([string]$scan.state -eq 'GOOGLE_LOGIN' -and ($scan.passwordPrompt -or $scan.emailPrompt)){ $credential=$true; break }
    Start-Sleep -Seconds 2
  }
  $ok=[bool]($final -and [string]$final.state -eq 'FLOW_WORKSPACE' -and @($final.inputs).Count)
  $result=[ordered]@{ok=$ok;action='FLOW_LOGIN_CONSENT_TO_WORKSPACE';version=$Version;workspaceReached=$ok;credentialEntryRequired=$credential;finalState=$(if($final){[string]$final.state}else{'NO_PAGE'});pageUrl=$(if($final){[string]$final.url}else{''});inputs=$(if($final){@($final.inputs)}else{@()});history=$history;generateClicked=$false;creditSpend=$false;credentialEnteredByAutomation=$false;checkedAt=(Get-Date).ToString('o')}
  WriteReceipt $result 'FLOW_LOGIN_CONSENT_TO_WORKSPACE.json'
  $result | ConvertTo-Json -Depth 40 -Compress
  if($ok){ exit 0 } elseif($credential){ exit 3 } else { exit 2 }
}
throw 'MODE_REQUIRED'
