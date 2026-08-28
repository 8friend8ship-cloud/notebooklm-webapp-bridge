param(
  [string]$TaskId='',
  [string]$CentralRootOverride='',
  [int]$DebugPort=9224
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$NotebookExtension=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$NotebookFront='https://notebooklm-webapp-bridge.vercel.app/'
$FlowUrl='https://labs.google/fx/tools/flow'
$ExpectedFlowExtensionId='lgedgmpcikglaajhfclcihicgafimlna'

function Safe-TaskId([string]$Value){if([string]::IsNullOrWhiteSpace($Value)){return ('FLOW_BRIDGE_CONNECT_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))};if($Value -notmatch '^[A-Za-z0-9_.-]{1,180}$'){throw 'UNSAFE_TASK_ID'};return $Value}
function Write-JsonAtomic([string]$Path,$Object){$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$tmp=$Path+'.tmp';$Object|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function Find-CentralRoot {
  if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride -PathType Container)){return $CentralRootOverride}
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($candidate in @((Join-Path $r $target),(Join-Path (Join-Path $r 'My Drive') $target),(Join-Path (Join-Path $r $myDriveKo) $target),(Join-Path (Join-Path $r 'Google Drive') $target))){try{if(Test-Path -LiteralPath $candidate -PathType Container){return $candidate}}catch{}}
  }
  return ''
}
function Find-CftChrome {return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}
function Dedicated-Procs {try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine).Contains($UserData)})}catch{return @()}}
function Normal-Procs {try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{-not $_.CommandLine -or -not ([string]$_.CommandLine).Contains($UserData)})}catch{return @()}}
function Normal-BrowserRoots {return @(Normal-Procs|Where-Object{-not $_.CommandLine -or ([string]$_.CommandLine) -notmatch '(?i)(^|\s)--type='})}
function Stop-Dedicated {$k=@();foreach($p in @(Dedicated-Procs)){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null;$k += [int]$p.ProcessId}catch{}};Start-Sleep -Seconds 2;return @($k)}
function Find-FlowExtension {
  $candidates=@(
    (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0\flow-agent-bridge-v0.1.0'),
    (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0'),
    (Join-Path $Base 'Extension\Flow-Agent-Bridge'),
    (Join-Path $Base 'Extension\Google-AI-Local-Bridge-Flow')
  )
  foreach($p in $candidates){try{if(Test-Path -LiteralPath (Join-Path $p 'manifest.json') -PathType Leaf){return $p}}catch{}}
  return ''
}
function Restore-Notebook {
  try{
    Stop-Dedicated|Out-Null
    $chrome=Find-CftChrome;if(-not $chrome){return $false}
    $args=@("--user-data-dir=$UserData",'--profile-directory=Default','--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble')
    if(Test-Path -LiteralPath (Join-Path $NotebookExtension 'manifest.json') -PathType Leaf){$args+=("--load-extension=$NotebookExtension")}
    $args+=$NotebookFront
    Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.Directory.FullName|Out-Null
    Start-Sleep -Seconds 2
    return (@(Dedicated-Procs).Count -gt 0)
  }catch{return $false}
}
function Read-TextSafe([string]$Path,[int]$Max=12000){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''};try{$t=Get-Content -LiteralPath $Path -Raw -Encoding UTF8;if($t.Length -gt $Max){return $t.Substring(0,$Max)};return $t}catch{return ''}}
function Invoke-DeepProbe([string]$BrowserWs,[string]$PageWs,[string]$Sentinel){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $node){$node=Get-Command node -ErrorAction SilentlyContinue};if(-not $node){return [ordered]@{ok=$false;stage='NODE_NOT_FOUND'}}
  $js=Join-Path $env:TEMP ('flow-bridge-deep-probe-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $code=@'
const browserWs=process.argv[2], pageWs=process.argv[3], sentinel=process.argv[4], expectedId=process.argv[5];
function connect(url){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);let seq=0;const pending=new Map();ws.onopen=()=>resolve({ws,send:(method,params={})=>new Promise((res,rej)=>{const id=++seq;pending.set(id,{res,rej});ws.send(JSON.stringify({id,method,params}));})});ws.onerror=reject;ws.onmessage=e=>{let m;try{m=JSON.parse(e.data)}catch{return};if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.rej(new Error(JSON.stringify(m.error))):p.res(m.result);}};});}
const b=await connect(browserWs);const all=await b.send('Target.getTargets');
const ext=(all.targetInfos||[]).filter(t=>(t.url||'').startsWith('chrome-extension://'));
const expected=ext.filter(t=>(t.url||'').startsWith('chrome-extension://'+expectedId+'/'));
const p=await connect(pageWs);const sentinelLit=JSON.stringify(sentinel);
const baseExpr=`(()=>{const roots=[document],q=[document],seen=new Set(q);while(q.length){const r=q.shift();let a=[];try{a=[...r.querySelectorAll('*')]}catch{};for(const e of a){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot);q.push(e.shadowRoot)}}}const vis=e=>{if(!e)return false;const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity)!==0&&r.width>18&&r.height>18&&r.bottom>=0&&r.right>=0};const desc=e=>[e.getAttribute?.('aria-label'),e.getAttribute?.('placeholder'),e.getAttribute?.('data-placeholder'),e.getAttribute?.('title'),e.getAttribute?.('name'),e.id,e.textContent,e.value].filter(Boolean).join(' ').replace(/\\s+/g,' ').trim();let inputs=[];for(const r of roots){try{inputs.push(...r.querySelectorAll('textarea,input[type=text],input:not([type]),[contenteditable=true],[role=textbox]'))}catch{}}let best=null,score=-9999;for(const e of [...new Set(inputs)]){if(!vis(e)||e.disabled||e.readOnly)continue;const d=desc(e).toLowerCase();let s=0;for(const w of ['prompt','describe','description','imagine','scene','video','image','create','make','what do you want','type your','enter your','프롬프트','설명','장면','영상','이미지','만들','생성','입력'])if(d.includes(w))s+=12;for(const w of ['search','find','검색','댓글','comment','title','제목','name','이름'])if(d.includes(w))s-=20;if(e.tagName==='TEXTAREA')s+=12;if(e.isContentEditable)s+=7;if(e.getAttribute?.('role')==='textbox')s+=4;const z=e.getBoundingClientRect();s+=Math.min(12,Math.round(z.width*z.height/30000));if(z.top>innerHeight*.35)s+=3;if(s>score){score=s;best=e}}let fill={attempted:false,verified:false,cleared:false};if(best&&score>=5){fill.attempted=true;const old=('value'in best)?best.value:best.textContent;const v=${sentinelLit};best.focus();if('value'in best){const proto=best.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const set=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(set)set.call(best,v);else best.value=v}else best.textContent=v;try{best.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}))}catch{best.dispatchEvent(new Event('input',{bubbles:true}))}best.dispatchEvent(new Event('change',{bubbles:true}));fill.verified=(('value'in best)?best.value:best.textContent)===v;if('value'in best){const proto=best.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const set=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(set)set.call(best,old);else best.value=old}else best.textContent=old;try{best.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'deleteContentBackward',data:null}))}catch{best.dispatchEvent(new Event('input',{bubbles:true}))}best.dispatchEvent(new Event('change',{bubbles:true}));fill.cleared=(('value'in best)?best.value:best.textContent)===old}let buttons=[];for(const r of roots){try{buttons.push(...r.querySelectorAll('button,[role=button],a'))}catch{}}const routeHints=[...new Set(buttons)].filter(vis).map(e=>({text:desc(e).slice(0,180),href:e.href||''})).filter(x=>/project|create|new|generate|flow|프로젝트|만들|생성/i.test(x.text+' '+x.href)).slice(0,20);return {url:location.href,title:document.title,readyState:document.readyState,shadowRootCount:roots.length-1,inputCandidateCount:inputs.length,promptInputFound:!!(best&&score>=5),promptInputScore:score,promptInputTag:best?.tagName||'',promptInputDesc:best?desc(best).slice(0,240):'',inputFillAttempted:fill.attempted,inputFillVerified:fill.verified,inputCleared:fill.cleared,routeHints,bodyTextLength:(document.body?.innerText||'').length}})()`;
let r=await p.send('Runtime.evaluate',{expression:baseExpr,returnByValue:true,awaitPromise:true,userGesture:true});
let first=r.result?.value||null, navigated=false, navText='';
if(first && !first.promptInputFound){
  const navExpr=`(()=>{const roots=[document],q=[document],seen=new Set(q);while(q.length){const r=q.shift();let a=[];try{a=[...r.querySelectorAll('*')]}catch{};for(const e of a){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot);q.push(e.shadowRoot)}}}const vis=e=>{if(!e)return false;const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&r.width>18&&r.height>18};const desc=e=>[e.getAttribute?.('aria-label'),e.getAttribute?.('title'),e.textContent].filter(Boolean).join(' ').replace(/\\s+/g,' ').trim();let all=[];for(const r of roots){try{all.push(...r.querySelectorAll('button,[role=button],a'))}catch{}}const c=[...new Set(all)].filter(vis).map(e=>({e,t:desc(e)})).find(x=>/^(new project|create project|새 프로젝트|프로젝트 만들기)$/i.test(x.t)||/new project|create project|새 프로젝트|프로젝트 만들기/i.test(x.t));if(!c)return {clicked:false,text:''};c.e.click();return {clicked:true,text:c.t.slice(0,180)}})()`;
  const nr=await p.send('Runtime.evaluate',{expression:navExpr,returnByValue:true,userGesture:true});navigated=!!nr.result?.value?.clicked;navText=nr.result?.value?.text||'';
  if(navigated){await new Promise(r=>setTimeout(r,3500));r=await p.send('Runtime.evaluate',{expression:baseExpr,returnByValue:true,awaitPromise:true,userGesture:true});}
}
console.log(JSON.stringify({ok:true,targets:{extensionTargets:ext,expectedExtensionTargets:expected,extensionTargetCount:ext.length,expectedExtensionTargetCount:expected.length,expectedServiceWorkerCount:expected.filter(t=>t.type==='service_worker').length},firstPage:first,navigatedToWorkspace:navigated,navigationText:navText,page:r.result?.value||null}));
'@
  Set-Content -LiteralPath $js -Value $code -Encoding UTF8
  try{
    $out=& $node.Source $js $BrowserWs $PageWs $Sentinel $ExpectedFlowExtensionId 2>&1|Out-String;$trim=$out.Trim();
    if(-not $trim){return [ordered]@{ok=$false;stage='EMPTY_DEEP_PROBE'}}
    $last=($trim.Split("`n")|Select-Object -Last 1).Trim();return ($last|ConvertFrom-Json)
  }catch{return [ordered]@{ok=$false;stage='DEEP_PROBE_ERROR';error=$_.Exception.Message;nativeOutput=$(if($trim){$trim}else{''})}}finally{Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue}
}

$task=Safe-TaskId $TaskId
$central=Find-CentralRoot
if(-not $central){throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'}
$flowExtension=Find-FlowExtension
if(-not $flowExtension){throw 'FLOW_EXTENSION_PATH_NOT_FOUND'}
$manifest=Get-Content -LiteralPath (Join-Path $flowExtension 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$manifestBackground='';try{$manifestBackground=[string]$manifest.background.service_worker}catch{}
$manifestContentScripts=@();try{$manifestContentScripts=@($manifest.content_scripts|ForEach-Object{[ordered]@{matches=@($_.matches);js=@($_.js);runAt=[string]$_.run_at}})}catch{}
$manifestActionPopup='';try{$manifestActionPopup=[string]$manifest.action.default_popup}catch{}
$extensionArchitecture=$(if($manifestBackground){'background_service_worker'}elseif($manifestActionPopup -and @($manifest.content_scripts).Count -gt 0){'content_script_plus_popup'}elseif(@($manifest.content_scripts).Count -gt 0){'content_script_only'}else{'extension_page_or_unknown'})
$contentSource=Read-TextSafe (Join-Path $flowExtension 'content.js')
$popupHtmlSource=Read-TextSafe (Join-Path $flowExtension 'popup.html')
$popupJsSource=Read-TextSafe (Join-Path $flowExtension 'popup.js')
$chrome=Find-CftChrome
if(-not $chrome){throw 'CFT_CHROME_EXE_NOT_FOUND'}
$normalBefore=@(Normal-Procs|ForEach-Object{[int]$_.ProcessId})
$normalRootBefore=@(Normal-BrowserRoots|ForEach-Object{[int]$_.ProcessId})
$dedicatedStopped=@(Stop-Dedicated)
$args=@("--user-data-dir=$UserData",'--profile-directory=Default','--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble','--disable-download-notification',("--load-extension=$flowExtension"),("--remote-debugging-port=$DebugPort"),'--remote-debugging-address=127.0.0.1',$FlowUrl)
Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.Directory.FullName|Out-Null

$version=$null;$targets=@();$deadline=(Get-Date).AddSeconds(30)
do{
  try{$version=Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/version") -TimeoutSec 2;if($version.webSocketDebuggerUrl){$targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/list") -TimeoutSec 2);if(@($targets|Where-Object{$_.type -eq 'page' -and $_.url -and ([string]$_.url).Contains('/fx/tools/flow')}).Count -gt 0){break}}}catch{}
  Start-Sleep -Milliseconds 500
}while((Get-Date)-lt $deadline)

$flowPages=@($targets|Where-Object{$_.type -eq 'page' -and $_.url -and ([string]$_.url).Contains('/fx/tools/flow')})
$flowPage=$flowPages|Select-Object -First 1
$loginPages=@($targets|Where-Object{$_.type -eq 'page' -and $_.url -and ([string]$_.url).Contains('accounts.google.com')})
$dedicatedCmd=@(Dedicated-Procs|ForEach-Object{[string]$_.CommandLine})
$loadArgPresent=(@($dedicatedCmd|Where-Object{$_ -and $_.Contains('--load-extension=') -and $_.Contains($flowExtension)}).Count -gt 0)
$sentinel='CENTRAL_AGENT_FLOW_INPUT_PROBE_'+(Get-Date -Format 'HHmmss')
$deep=$null
if($version -and $version.webSocketDebuggerUrl -and $flowPage -and $flowPage.webSocketDebuggerUrl){$deep=Invoke-DeepProbe -BrowserWs ([string]$version.webSocketDebuggerUrl) -PageWs ([string]$flowPage.webSocketDebuggerUrl) -Sentinel $sentinel}else{$deep=[ordered]@{ok=$false;stage='NO_CDP_PAGE_FOR_DEEP_PROBE'}}
$restored=Restore-Notebook
$normalAfter=@(Normal-Procs|ForEach-Object{[int]$_.ProcessId})
$normalRootAfter=@(Normal-BrowserRoots|ForEach-Object{[int]$_.ProcessId})
$missingRoot=@($normalRootBefore|Where-Object{$normalRootAfter -notcontains $_})
$normalChromeUntouched=($missingRoot.Count -eq 0)
$contentScriptConfigured=(@($manifestContentScripts).Count -gt 0 -and @($manifestContentScripts|Where-Object{@($_.matches) -contains 'https://labs.google/*' -and @($_.js) -contains 'content.js'}).Count -gt 0)
$inputVerified=($deep -and $deep.ok -and [bool]$deep.page.promptInputFound -and [bool]$deep.page.inputFillVerified -and [bool]$deep.page.inputCleared)
$extensionContextGate=$(if($extensionArchitecture -eq 'background_service_worker'){($deep -and $deep.ok -and [int]$deep.targets.expectedServiceWorkerCount -gt 0)}else{$contentScriptConfigured})
$ok=($version -and $version.webSocketDebuggerUrl -and $flowPages.Count -gt 0 -and $loadArgPresent -and $loginPages.Count -eq 0 -and $extensionContextGate -and $inputVerified -and $restored -and $normalChromeUntouched)

$readbackDir=Join-Path (Join-Path $central 'Runtime_Readback') 'Flow_Bridge_Direct'
$resultPath=Join-Path $readbackDir ($task+'_result.json')
$ackPath=Join-Path $readbackDir ($task+'_ACK.json')
$result=[ordered]@{
  ok=[bool]$ok;action='FLOW_BRIDGE_DEEP_CONNECT_PROBE_V2';taskId=$task;centralRoot=$central;flowUrl=$FlowUrl;
  extensionPath=$flowExtension;expectedExtensionId=$ExpectedFlowExtensionId;extensionName=[string]$manifest.name;extensionVersion=[string]$manifest.version;manifestVersion=[int]$manifest.manifest_version;extensionArchitecture=$extensionArchitecture;manifestBackgroundServiceWorker=$manifestBackground;manifestContentScripts=$manifestContentScripts;manifestActionPopup=$manifestActionPopup;contentScriptConfigured=[bool]$contentScriptConfigured;
  sourceContract=[ordered]@{contentJs=$contentSource;popupHtml=$popupHtmlSource;popupJs=$popupJsSource};
  cftChrome=$chrome.FullName;debugPort=$DebugPort;cdpReady=[bool]($version -and $version.webSocketDebuggerUrl);flowPageFound=($flowPages.Count -gt 0);flowPages=@($flowPages|ForEach-Object{[ordered]@{title=$_.title;url=$_.url;type=$_.type}});loginRequired=($loginPages.Count -gt 0);loadExtensionArgPresent=[bool]$loadArgPresent;
  deepProbe=$deep;extensionContextGate=[bool]$extensionContextGate;promptInputVerified=[bool]$inputVerified;
  dedicatedStopped=$dedicatedStopped;notebookDedicatedRestored=[bool]$restored;normalChromeBeforeCount=$normalBefore.Count;normalChromeAfterCount=$normalAfter.Count;normalChromeMissingRootPids=$missingRoot;normalChromeUntouched=[bool]$normalChromeUntouched;
  generateClicked=$false;creditSpend=$false;oauthChanged=$false;chromeSettingsChanged=$false;verificationContract='ARCHITECTURE_CLASSIFIED+CONTENT_SCRIPT_CONFIGURED_OR_SERVICE_WORKER+WORKSPACE_NAVIGATION+PROMPT_INPUT_FILL_READBACK_CLEAR+DRIVE_ACK';at=(Get-Date).ToString('o')
}
Write-JsonAtomic $resultPath $result
$ack=[ordered]@{ack=[bool]$ok;taskId=$task;action='FLOW_BRIDGE_DEEP_CONNECT_PROBE_V2';resultPath=$resultPath;extensionArchitecture=$extensionArchitecture;extensionContextGate=[bool]$extensionContextGate;promptInputVerified=[bool]$inputVerified;generateClicked=$false;creditSpend=$false;at=(Get-Date).ToString('o')}
Write-JsonAtomic $ackPath $ack
$result['resultPath']=$resultPath;$result['ackPath']=$ackPath;$result['ack']=[bool]$ok
$result|ConvertTo-Json -Depth 60 -Compress
if($ok){exit 0}else{exit 2}
