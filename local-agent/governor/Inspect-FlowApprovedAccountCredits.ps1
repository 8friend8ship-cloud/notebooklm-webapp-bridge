param(
  [int]$DebugPort=9224,
  [switch]$NavigateWorkspace,
  [switch]$CurrentScreenOnly,
  [switch]$InspectMediaOptions,
  [string]$DirectProjectUrl='',
  [int]$TimeoutSeconds=120,
  [string]$CentralRootOverride=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='FLOW_PROJECT_LIST_NEW_PROJECT_V8_20260829'
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
function Targets {
  try { return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/list") -TimeoutSec 3) }
  catch { return @() }
}
function Pages { return @(Targets | Where-Object { $_.type -eq 'page' }) }
function InvokeNodeCdp([string]$WsUrl,[string]$Mode,[string]$Arg=''){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue
  if(-not $node){ $node=Get-Command node -ErrorAction Stop }
  $js=Join-Path $env:TEMP ('flow-cdp-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $code=@'
const wsUrl=process.argv[2],mode=process.argv[3],arg=process.argv[4]||'';
function connect(url){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);let id=0,p=new Map();ws.onopen=()=>resolve({ws,send:(m,params={})=>new Promise((res,rej)=>{const n=++id;p.set(n,{res,rej});ws.send(JSON.stringify({id:n,method:m,params}));})});ws.onerror=reject;ws.onmessage=e=>{let x;try{x=JSON.parse(e.data)}catch{return};if(x.id&&p.has(x.id)){const q=p.get(x.id);p.delete(x.id);x.error?q.rej(new Error(JSON.stringify(x.error))):q.res(x.result)}}})}
const c=await connect(wsUrl);
try{
 if(mode==='navigate'){
   await c.send('Page.navigate',{url:arg});
   console.log(JSON.stringify({ok:true,navigatedTo:arg}));
 } else {
  const allowClick=mode==='scan-click';
  const mediaScan=mode==='media-scan';
  const expr=`(()=>{
    const vis=e=>{const r=e.getBoundingClientRect();const s=getComputedStyle(e);return !!(r.width&&r.height)&&s.visibility!=='hidden'&&s.display!=='none'&&!e.disabled};
    const txt=e=>String(e.innerText||e.textContent||e.value||e.getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ').slice(0,220);
    const controls=[...document.querySelectorAll('button,[role="button"],a,input[type="submit"],[role="tab"],[role="radio"]')].filter(vis);
    const inputs=[...document.querySelectorAll('textarea,input[type="text"],[contenteditable="true"],[role="textbox"]')].filter(vis);
    const items=controls.map((e,i)=>({i,text:txt(e),tag:e.tagName,role:e.getAttribute('role')||'',ariaLabel:e.getAttribute('aria-label')||'',ariaPressed:e.getAttribute('aria-pressed')||'',ariaSelected:e.getAttribute('aria-selected')||'',ariaChecked:e.getAttribute('aria-checked')||'',dataState:e.getAttribute('data-state')||'',href:e.href||'',cls:String(e.className||'').slice(0,180)}));
    const ins=inputs.map(e=>({tag:e.tagName,placeholder:e.getAttribute('placeholder')||'',aria:e.getAttribute('aria-label')||'',value:String(('value'in e)?e.value:(e.innerText||'')).slice(0,300)}));
    const url=location.href;
    let state='OTHER';
    const flowRoute=/labs\\.google\/fx\/(?:[a-z]{2}(?:-[A-Z]{2})?\/)?tools\/flow(?:\/|$)/i;
    const projectRoute=/labs\\.google\/fx\/(?:[a-z]{2}(?:-[A-Z]{2})?\/)?tools\/flow\/project\/[A-Za-z0-9-]+\/?(?:[?#].*)?$/i;
    const hasNewProject=items.some(it=>/^(new project|새\\s*프로젝트)$/i.test(it.text)||/new project|새\\s*프로젝트/i.test(it.ariaLabel));
    const hasCreateFlow=items.some(it=>/^create with google flow$/i.test(it.text));
    if(/accounts\\.google\\.com/i.test(url))state='GOOGLE_LOGIN';
    else if(projectRoute.test(url))state=ins.length?'FLOW_WORKSPACE':'FLOW_PROJECT_LOADING';
    else if(flowRoute.test(url)&&hasNewProject)state='FLOW_PROJECT_LIST';
    else if(flowRoute.test(url)&&hasCreateFlow)state='FLOW_LANDING';
    else if(flowRoute.test(url))state='FLOW_INTERMEDIATE';
    else if(/flow\\.google/i.test(url))state='FLOW_INTERMEDIATE';
    else if(/labs\\.google/i.test(url))state='LABS_INTERMEDIATE';
    let clicked=null,clickKind='';
    if(${allowClick?'true':'false'}&&state!=='FLOW_WORKSPACE'){
      const groups=[
        {kind:'COOKIE_CONSENT',rx:[/^agree$/i]},
        {kind:'FLOW_PRIMARY_CTA',rx:[/^create with google flow$/i,/^create with flow$/i,/^start creating$/i,/^enter flow$/i,/^try flow$/i,/^open flow$/i]},
        {kind:'FLOW_NEW_PROJECT',rx:[/^new project$/i,/^새\\s*프로젝트$/i]},
        {kind:'SAFE_CONTINUE',rx:[/^continue$/i,/^allow$/i,/^get started$/i,/^confirm$/i,/resume/i,/recent/i,/open project/i,/create project/i]}
      ];
      outer:for(const g of groups){for(const it of items){if(g.rx.some(r=>r.test(it.text)||r.test(it.ariaLabel))){try{const el=controls[it.i];el.scrollIntoView({block:'center',inline:'center',behavior:'instant'});el.focus({preventScroll:true});el.click();clicked=it;clickKind=g.kind;break outer}catch{}}}}
    }
    let mediaOptions=null;
    if(${mediaScan?'true':'false'}){
      const selected=it=>it.ariaPressed==='true'||it.ariaSelected==='true'||it.ariaChecked==='true'||/checked|selected|active/i.test(it.dataState)||/(^|\\s)(selected|active)(\\s|$)/i.test(it.cls);
      const mediaType=items.filter(it=>/^(image|video|이미지|동영상)$/i.test(it.text));
      const aspectRatios=items.filter(it=>/^(16:9|4:3|1:1|3:4|9:16)$/i.test(it.text));
      const counts=items.filter(it=>/^x[1-4]$/i.test(it.text));
      const models=items.filter(it=>/(nano banana|veo|imagen|gemini|banana)/i.test(it.text));
      const optionText=items.filter(it=>/(image|video|이미지|동영상|16:9|4:3|1:1|3:4|9:16|x1|x2|x3|x4|nano banana|veo|imagen)/i.test(it.text));
      mediaOptions={mediaType:mediaType.map(it=>({...it,selected:selected(it)})),aspectRatios:aspectRatios.map(it=>({...it,selected:selected(it)})),counts:counts.map(it=>({...it,selected:selected(it)})),models:models.map(it=>({...it,selected:selected(it)})),optionCandidates:optionText.map(it=>({...it,selected:selected(it)})),promptInputs:ins,promptReady:projectRoute.test(url)&&ins.length>0};
    }
    return {url,title:document.title,state,inputs:ins,buttons:items.slice(0,160),clicked,clickKind,passwordPrompt:!!document.querySelector('input[type="password"]'),emailPrompt:!!document.querySelector('input[type="email"]'),hasNewProject,hasCreateFlow,mediaOptions};
  })()`;
  const r=await c.send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true,userGesture:true});
  console.log(JSON.stringify(r.result?.value||{}));
 }
} finally { try{c.ws.close()}catch{}; setTimeout(()=>process.exit(0),30) }
'@
  Set-Content -LiteralPath $js -Value $code -Encoding ASCII
  try {
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$node.Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $psi.Arguments=('"'+$js+'" "'+$WsUrl+'" "'+$Mode+'" "'+($Arg -replace '"','\"')+'"')
    $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit(15000)){ try{Stop-Process -Id $p.Id -Force}catch{}; throw 'FLOW_CDP_DOM_TIMEOUT' }
    $raw=$ot.Result.Trim();if(-not $raw){ throw ('FLOW_CDP_DOM_EMPTY:'+ $et.Result.Trim()) }
    return (($raw -split "`r?`n")[-1] | ConvertFrom-Json)
  } finally { Remove-Item $js -Force -ErrorAction SilentlyContinue }
}
function Scan([string]$Ws,[bool]$Click){return InvokeNodeCdp $Ws $(if($Click){'scan-click'}else{'scan'})}
function MediaScan([string]$Ws){return InvokeNodeCdp $Ws 'media-scan'}
function Navigate([string]$Ws,[string]$Url){return InvokeNodeCdp $Ws 'navigate' $Url}
function WriteReceipt($Object,[string]$Name){$central=FindCentral;if($central){$dir=Join-Path $central 'Runtime_Readback\Flow_Bridge_Direct';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $dir $Name) -Encoding UTF8}}
function FlowPage { param($Pages) return ($Pages | Where-Object { ([string]$_.url) -match 'labs\.google|accounts\.google|flow\.google' } | Select-Object -First 1) }
function ValidateProjectUrl([string]$Url){return [bool]($Url -match '^https://labs\.google/fx/(?:[a-z]{2}(?:-[A-Z]{2})?/)?tools/flow/project/[A-Za-z0-9-]+/?$')}
$pages=@(Pages)
if($CurrentScreenOnly){
  $page=FlowPage $pages;if(-not $page){throw 'CDP_FLOW_PAGE_NOT_FOUND_ON_CURRENT_SCREEN'}
  $scan=Scan ([string]$page.webSocketDebuggerUrl) $false;$allTargets=@(Targets);$extTargets=@($allTargets|Where-Object{([string]$_.url)-like'chrome-extension://*'}|ForEach-Object{[ordered]@{type=[string]$_.type;url=[string]$_.url;title=[string]$_.title}});$input=@($scan.inputs)|Select-Object -First 1
  $ok=[bool]([string]$scan.state-eq'FLOW_WORKSPACE'-and$input);$result=[ordered]@{ok=$ok;action='FLOW_CURRENT_SCREEN_CDP_READONLY';version=$Version;state=[string]$scan.state;pageUrl=[string]$scan.url;pageTitle=[string]$scan.title;inputFound=[bool]$input;input=$input;buttons=@($scan.buttons);extensionTargets=$extTargets;generateClicked=$false;creditSpend=$false;readOnly=$true;checkedAt=(Get-Date).ToString('o')};WriteReceipt $result 'FLOW_CURRENT_SCREEN_CDP_READONLY.json';$result|ConvertTo-Json -Depth 40 -Compress;if($ok){exit 0}else{exit 2}
}
if($InspectMediaOptions){
  $directNav=$false
  if($DirectProjectUrl){if(-not(ValidateProjectUrl $DirectProjectUrl)){throw 'DIRECT_PROJECT_URL_REJECTED'};$pages=@(Pages);$page=FlowPage $pages;if($page){[void](Navigate ([string]$page.webSocketDebuggerUrl) $DirectProjectUrl);$directNav=$true;Start-Sleep -Seconds 2}}
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds);$scan=$null
  while((Get-Date)-lt$deadline){$pages=@(Pages);$page=FlowPage $pages;if(-not$page){Start-Sleep -Milliseconds 500;continue};$scan=MediaScan ([string]$page.webSocketDebuggerUrl);if([string]$scan.state-eq'FLOW_WORKSPACE'-and$scan.mediaOptions-and[bool]$scan.mediaOptions.promptReady){break};Start-Sleep -Seconds 1}
  $allTargets=@(Targets);$extTargets=@($allTargets|Where-Object{([string]$_.url)-like'chrome-extension://*'}|ForEach-Object{[ordered]@{type=[string]$_.type;url=[string]$_.url;title=[string]$_.title}})
  $ok=[bool]($scan-and[string]$scan.state-eq'FLOW_WORKSPACE'-and$scan.mediaOptions-and[bool]$scan.mediaOptions.promptReady)
  $result=[ordered]@{ok=$ok;action='FLOW_MEDIA_TYPE_AND_SIDE_OPTIONS_READBACK';version=$Version;directProjectUrl=$DirectProjectUrl;directNavigationAttempted=$directNav;state=$(if($scan){[string]$scan.state}else{'NO_PAGE'});pageUrl=$(if($scan){[string]$scan.url}else{''});pageTitle=$(if($scan){[string]$scan.title}else{''});mediaOptions=$(if($scan){$scan.mediaOptions}else{$null});extensionTargets=$extTargets;generateClicked=$false;creditSpend=$false;readOnly=$true;checkedAt=(Get-Date).ToString('o')};WriteReceipt $result 'FLOW_MEDIA_TYPE_AND_SIDE_OPTIONS_READBACK.json';$result|ConvertTo-Json -Depth 50 -Compress;if($ok){exit 0}else{exit 2}
}
if($NavigateWorkspace){
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds);$history=@();$final=$null;$credential=$false;$directNav=$false
  if($DirectProjectUrl){if(-not(ValidateProjectUrl $DirectProjectUrl)){throw 'DIRECT_PROJECT_URL_REJECTED'};$pages=@(Pages);$page=FlowPage $pages;if($page){[void](Navigate ([string]$page.webSocketDebuggerUrl) $DirectProjectUrl);$directNav=$true;Start-Sleep -Seconds 2}}
  while((Get-Date)-lt$deadline){$pages=@(Pages);$page=FlowPage $pages;if(-not$page){Start-Sleep -Milliseconds 600;continue};$scan=Scan ([string]$page.webSocketDebuggerUrl) $true;$history+=[ordered]@{at=(Get-Date).ToString('o');url=[string]$scan.url;title=[string]$scan.title;state=[string]$scan.state;inputCount=@($scan.inputs).Count;clickKind=[string]$scan.clickKind;clicked=$scan.clicked};$final=$scan;if([string]$scan.state-eq'FLOW_WORKSPACE'-and@($scan.inputs).Count){break};if([string]$scan.state-eq'GOOGLE_LOGIN'-and($scan.passwordPrompt-or$scan.emailPrompt)){$credential=$true;break};Start-Sleep -Seconds 2}
  $allTargets=@(Targets);$extTargets=@($allTargets|Where-Object{([string]$_.url)-like'chrome-extension://*'}|ForEach-Object{[ordered]@{type=[string]$_.type;url=[string]$_.url;title=[string]$_.title}});$ok=[bool]($final-and[string]$final.state-eq'FLOW_WORKSPACE'-and@($final.inputs).Count)
  $result=[ordered]@{ok=$ok;action='FLOW_LANDING_PROJECT_LIST_TO_WORKSPACE';version=$Version;directProjectUrl=$DirectProjectUrl;directNavigationAttempted=$directNav;workspaceReached=$ok;credentialEntryRequired=$credential;finalState=$(if($final){[string]$final.state}else{'NO_PAGE'});pageUrl=$(if($final){[string]$final.url}else{''});pageTitle=$(if($final){[string]$final.title}else{''});inputs=$(if($final){@($final.inputs)}else{@()});extensionTargets=$extTargets;history=$history;cookieConsentHandled=[bool](@($history|Where-Object{$_.clickKind-eq'COOKIE_CONSENT'}).Count);flowPrimaryCtaHandled=[bool](@($history|Where-Object{$_.clickKind-eq'FLOW_PRIMARY_CTA'}).Count);newProjectHandled=[bool](@($history|Where-Object{$_.clickKind-eq'FLOW_NEW_PROJECT'}).Count);generateClicked=$false;creditSpend=$false;credentialEnteredByAutomation=$false;checkedAt=(Get-Date).ToString('o')};WriteReceipt $result 'FLOW_LANDING_PROJECT_LIST_TO_WORKSPACE.json';$result|ConvertTo-Json -Depth 40 -Compress;if($ok){exit 0}elseif($credential){exit 3}else{exit 2}
}
throw 'MODE_REQUIRED'
