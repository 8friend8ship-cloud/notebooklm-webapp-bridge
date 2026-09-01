param(
  [ValidateSet('Probe','Run')][string]$Mode='Probe',
  [int]$DebugPort=9224,
  [string]$ProjectTitle='00_중앙에이전트_통합관리',
  [string]$Question='',
  [string]$RunId='',
  [int]$TimeoutSeconds=150,
  [string]$CentralRootOverride='',
  [switch]$RestartDedicatedChrome
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Version='DRIVE_GEMINI_PROJECT_REVIEW_V1_20260901'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$TargetUrl='https://drive.google.com/drive/u/0/my-drive'

function Find-Cft { Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 }
function Dedicated { try { return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and ([string]$_.CommandLine).Contains($UserData) }) } catch { return @() } }
function Stop-Dedicated { foreach($p in @(Dedicated)){ try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{} }; Start-Sleep 2 }
function Find-Central {
  if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride)){return $CentralRootOverride}
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('내 드라이브\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  return ''
}
function Pages { try { return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/list") -TimeoutSec 3 | Where-Object {$_.type -eq 'page'}) } catch { return @() } }
function Wait-Debug { param([int]$Seconds=30); $d=(Get-Date).AddSeconds($Seconds); do { if((Pages).Count -gt 0){return $true}; Start-Sleep -Milliseconds 500 } while((Get-Date)-lt $d); return $false }

function Invoke-DomAction([string]$WsUrl,[string]$Action,[string]$Project,[string]$Prompt,[string]$Rid){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue; if(-not $node){$node=Get-Command node -ErrorAction Stop}
  $js=Join-Path $env:TEMP ('drive-gemini-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $payload=[ordered]@{action=$Action;project=$Project;prompt=$Prompt;runId=$Rid}|ConvertTo-Json -Compress
  $code=@'
const wsUrl=process.argv[2];
const cfg=JSON.parse(process.argv[3]);
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function conn(url){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);let id=0,p=new Map();ws.onopen=()=>resolve({ws,send:(m,params={})=>new Promise((res,rej)=>{const n=++id;p.set(n,{res,rej});ws.send(JSON.stringify({id:n,method:m,params}));})});ws.onerror=reject;ws.onmessage=e=>{let x;try{x=JSON.parse(e.data)}catch{return};if(x.id&&p.has(x.id)){const q=p.get(x.id);p.delete(x.id);x.error?q.rej(new Error(JSON.stringify(x.error))):q.res(x.result)}}})}
const c=await conn(wsUrl);
try{
  const cfgLit=JSON.stringify(cfg);
  const expr=`(async()=>{const CFG=${cfgLit};
    const sleep=ms=>new Promise(r=>setTimeout(r,ms));
    const norm=s=>String(s||'').replace(/\\s+/g,' ').trim().toLowerCase();
    const vis=e=>{try{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)!==0}catch{return false}};
    const roots=()=>{const a=[document],seen=new Set(a);for(let i=0;i<a.length;i++){for(const e of a[i].querySelectorAll?.('*')||[]){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);a.push(e.shadowRoot)}}}return a};
    const all=sel=>{const o=[],seen=new Set();for(const r of roots())for(const e of r.querySelectorAll?.(sel)||[])if(!seen.has(e)){seen.add(e);o.push(e)}return o};
    const label=e=>norm([e?.innerText,e?.textContent,e?.value,e?.getAttribute?.('aria-label'),e?.getAttribute?.('title'),e?.getAttribute?.('placeholder'),e?.getAttribute?.('data-tooltip')].filter(Boolean).join(' '));
    const clickText=(words,scope=document)=>{const w=words.map(norm);const xs=[...scope.querySelectorAll?.('button,[role=button],a,[role=menuitem],[tabindex]')||[]].filter(vis).map(e=>({e,t:label(e)})).filter(x=>x.t&&x.t.length<600&&w.some(q=>x.t===q||x.t.includes(q))).sort((a,b)=>a.t.length-b.t.length);if(xs[0]){xs[0].e.click();return {text:xs[0].t}};return null};
    const wait=async(fn,ms=30000)=>{const end=Date.now()+ms;while(Date.now()<end){try{const v=fn();if(v)return v}catch{}await sleep(350)}return null};
    const fill=e=>{e.focus();if(e instanceof HTMLInputElement||e instanceof HTMLTextAreaElement){const p=e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const s=Object.getOwnPropertyDescriptor(p,'value')?.set;s?s.call(e,CFG.prompt):e.value=CFG.prompt;e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:CFG.prompt}));e.dispatchEvent(new Event('change',{bubbles:true}));}else{e.textContent=CFG.prompt;e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:CFG.prompt}));}};
    const body=()=>norm(document.body?.innerText||'');
    const out={url:location.href,title:document.title,projectTitle:CFG.project,action:CFG.action,runId:CFG.runId,at:new Date().toISOString(),loginRequired:false,projectContext:false,geminiOpened:false,sourceSearchToggleFound:false,sourceSearchEnabled:null,questionEditorFound:false,questionSubmitted:false,answerComplete:false,exportClicked:false,exportUrl:'',status:'UNKNOWN',diagnostic:{}};
    if(/accounts\\.google\\.com/i.test(location.href)||/(로그인|sign in|email or phone|이메일 또는 휴대전화)/i.test(document.body?.innerText||'')){out.loginRequired=true;out.status='LOGIN_REQUIRED';return out}
    if(!body().includes(norm(CFG.project))){
      const search=all('input,textarea,[contenteditable=true],[role=textbox]').filter(vis).find(e=>/(드라이브에서 검색|search in drive)/i.test(label(e)));
      if(search){const old=CFG.prompt;CFG.prompt=CFG.project;fill(search);CFG.prompt=old;search.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));search.dispatchEvent(new KeyboardEvent('keyup',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));await sleep(2500)}
    }
    let projectEl=await wait(()=>all('[role=row],[role=gridcell],[role=listitem],div,span').filter(vis).map(e=>({e,t:label(e)})).filter(x=>x.t===norm(CFG.project)||x.t.startsWith(norm(CFG.project)+' ')).sort((a,b)=>a.t.length-b.t.length)[0]?.e,8000);
    if(projectEl && !body().includes('프로젝트 소스') && !body().includes('project sources')){try{projectEl.dispatchEvent(new MouseEvent('dblclick',{bubbles:true,detail:2}));await sleep(2500)}catch{}}
    out.projectContext=body().includes(norm(CFG.project)) || /프로젝트 소스|project sources/i.test(document.body?.innerText||'');
    if(!/(gemini에 질문|ask gemini|프로젝트 소스|project sources)/i.test(document.body?.innerText||'')){
      const g=clickText(['gemini']);if(g){out.geminiOpened=true;await sleep(1800)}
    } else out.geminiOpened=true;
    const toggles=all('[role=switch],input[type=checkbox],button[aria-checked],div[role=checkbox]').filter(vis);
    let tg=null;
    for(const e of toggles){const t=label(e)+' '+label(e.parentElement)+' '+label(e.parentElement?.parentElement);if(/소스를 검색|search sources|sources.*search|search.*sources/i.test(t)){tg=e;break}}
    if(!tg){const labs=all('div,span,label').filter(vis).filter(e=>/gemini가 소스를 검색하도록 허용|소스를 검색하도록 허용|allow gemini to search sources|search sources/i.test(label(e)));for(const l of labs){tg=l.closest('label')?.querySelector('[role=switch],input[type=checkbox],button[aria-checked],[role=checkbox]')||l.parentElement?.querySelector?.('[role=switch],input[type=checkbox],button[aria-checked],[role=checkbox]');if(tg)break}}
    if(tg){out.sourceSearchToggleFound=true;const state=()=>tg instanceof HTMLInputElement?!!tg.checked:(tg.getAttribute('aria-checked')==='true'||tg.getAttribute('data-state')==='checked');out.sourceSearchEnabled=state();if(CFG.action==='RUN'&&!out.sourceSearchEnabled){tg.click();await sleep(500);out.sourceSearchEnabled=state()}}
    const editors=all('textarea,input[type=text],[contenteditable=true],[role=textbox]').filter(vis);
    const editor=editors.find(e=>/(gemini에 질문|ask gemini|질문|ask|prompt|메시지|message)/i.test(label(e)))||editors.filter(e=>!/(드라이브에서 검색|search in drive)/i.test(label(e))).at(-1);
    out.questionEditorFound=!!editor;
    if(CFG.action!=='RUN'){
      out.status=out.projectContext&&out.geminiOpened&&out.sourceSearchToggleFound&&out.questionEditorFound?'PROBE_PASS':'PROBE_PARTIAL';
      out.diagnostic={body:(document.body?.innerText||'').slice(0,5000),editors:editors.map(e=>label(e)).slice(0,20),toggles:toggles.map(e=>({label:label(e),checked:e instanceof HTMLInputElement?e.checked:e.getAttribute('aria-checked')})).slice(0,20)};
      return out;
    }
    if(!editor){out.status='QUESTION_EDITOR_NOT_FOUND';return out}
    if(!out.sourceSearchToggleFound){out.status='SOURCE_SEARCH_TOGGLE_NOT_VERIFIED';return out}
    if(out.sourceSearchEnabled!==true){out.status='SOURCE_SEARCH_TOGGLE_NOT_ENABLED';return out}
    if(!CFG.prompt){out.status='EMPTY_QUESTION';return out}
    fill(editor);await sleep(250);
    let send=all('button,[role=button]').filter(vis).map(e=>({e,t:label(e)})).filter(x=>/(보내기|send|submit|전송)/i.test(x.t)&&!x.e.disabled).sort((a,b)=>a.t.length-b.t.length)[0]?.e;
    if(send){send.click()}else{editor.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));editor.dispatchEvent(new KeyboardEvent('keyup',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}))}
    out.questionSubmitted=true;
    const beforeLen=(document.body?.innerText||'').length;
    const answered=await wait(()=>{const txt=document.body?.innerText||'';const busy=/(응답 생성|generating|thinking|생각 중)/i.test(txt);return !busy&&txt.length>beforeLen+80},90000);
    out.answerComplete=!!answered;
    if(!answered){out.status='ANSWER_INCOMPLETE';return out}
    let ex=clickText(['google docs로 내보내기','docs로 내보내기','export to google docs','export to docs']);
    if(!ex){const more=all('button,[role=button]').filter(vis).map(e=>({e,t:label(e)})).filter(x=>/(더보기|more|more actions|기타)/i.test(x.t)).at(-1)?.e;if(more){more.click();await sleep(350);ex=clickText(['google docs로 내보내기','docs로 내보내기','export to google docs','export to docs'])}}
    out.exportClicked=!!ex;
    if(!ex){out.status='DOC_EXPORT_CONTROL_NOT_FOUND';return out}
    await sleep(1200);
    const docLink=all('a').filter(vis).map(e=>e.href||'').filter(h=>/docs\\.google\\.com\\/document\\/d\\//i.test(h)).at(-1)||'';
    out.exportUrl=docLink;
    out.status='RUN_SUBMITTED_EXPORT_CLICKED';
    out.diagnostic={bodyTail:(document.body?.innerText||'').slice(-6000)};
    return out;
  })()`;
  const r=await c.send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true,userGesture:true});
  console.log(JSON.stringify(r.result?.value||{}));
}finally{try{c.ws.close()}catch{};setTimeout(()=>process.exit(0),20)}
'@
  Set-Content -LiteralPath $js -Value $code -Encoding UTF8
  try{
    $p=Start-Process -FilePath $node.Source -ArgumentList @($js,$WsUrl,$payload) -NoNewWindow -PassThru -RedirectStandardOutput ($js+'.out') -RedirectStandardError ($js+'.err')
    if(-not $p.WaitForExit(($TimeoutSeconds+30)*1000)){try{Stop-Process -Id $p.Id -Force}catch{};throw 'DRIVE_GEMINI_DOM_TIMEOUT'}
    $raw=Get-Content ($js+'.out') -Raw -ErrorAction SilentlyContinue
    if(-not $raw){$er=Get-Content ($js+'.err') -Raw -ErrorAction SilentlyContinue;throw ('DRIVE_GEMINI_DOM_EMPTY:'+ $er)}
    return (($raw.Trim()-split "`r?`n")[-1] | ConvertFrom-Json)
  } finally { Remove-Item $js,($js+'.out'),($js+'.err') -Force -ErrorAction SilentlyContinue }
}

if($Mode -eq 'Run' -and -not $RunId){$RunId='DRIVE_GEMINI_REVIEW_'+(Get-Date -Format 'yyyyMMdd_HHmm')}
$stateDir=Join-Path $Base 'DriveGeminiReview';New-Item -ItemType Directory -Force -Path $stateDir|Out-Null
$statePath=Join-Path $stateDir ($RunId+'.json')
if($Mode -eq 'Run' -and $RunId -and (Test-Path -LiteralPath $statePath)){
  try{$old=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json;if($old.questionSubmitted -eq $true){$old|ConvertTo-Json -Depth 50 -Compress;exit 0}}catch{}
}

if($RestartDedicatedChrome){Stop-Dedicated}
$cft=Find-Cft;if(-not $cft){throw 'CFT_NOT_FOUND'}
if((Dedicated).Count -eq 0){
  Start-Process $cft.FullName -ArgumentList @("--user-data-dir=$UserData",'--profile-directory=Default',("--remote-debugging-port=$DebugPort"),'--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check',$TargetUrl)|Out-Null
}
if(-not (Wait-Debug 30)){throw 'CDP_9224_NOT_READY'}
$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$last=$null
while((Get-Date)-lt $deadline){
  $pages=@(Pages)
  $page=$pages|Where-Object{$_.url -match 'drive\.google\.com|accounts\.google\.com'}|Select-Object -First 1
  if(-not $page){
    try{Invoke-WebRequest -Uri ("http://127.0.0.1:$DebugPort/json/new?"+[uri]::EscapeDataString($TargetUrl)) -Method Put -TimeoutSec 3|Out-Null}catch{}
    Start-Sleep 2;continue
  }
  $last=Invoke-DomAction ([string]$page.webSocketDebuggerUrl) $Mode $ProjectTitle $Question $RunId
  if($last.status -notin @('PROBE_PARTIAL','UNKNOWN')){break}
  Start-Sleep 2
}
if(-not $last){$last=[pscustomobject]@{status='NO_DRIVE_PAGE';url='';title='';loginRequired=$false;projectContext=$false;geminiOpened=$false;sourceSearchToggleFound=$false;sourceSearchEnabled=$null;questionEditorFound=$false;questionSubmitted=$false;answerComplete=$false;exportClicked=$false;exportUrl=''}}
$result=[ordered]@{ok=($last.status -in @('PROBE_PASS','RUN_SUBMITTED_EXPORT_CLICKED'));action='DRIVE_GEMINI_PROJECT_REVIEW';version=$Version;mode=$Mode;runId=$RunId;projectTitle=$ProjectTitle;status=[string]$last.status;url=[string]$last.url;title=[string]$last.title;loginRequired=[bool]$last.loginRequired;projectContext=[bool]$last.projectContext;geminiOpened=[bool]$last.geminiOpened;sourceSearchToggleFound=[bool]$last.sourceSearchToggleFound;sourceSearchEnabled=$last.sourceSearchEnabled;questionEditorFound=[bool]$last.questionEditorFound;questionSubmitted=[bool]$last.questionSubmitted;answerComplete=[bool]$last.answerComplete;exportClicked=[bool]$last.exportClicked;exportUrl=[string]$last.exportUrl;diagnostic=$last.diagnostic;at=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $statePath -Encoding UTF8
$central=Find-Central
if($central){$dir=Join-Path $central 'Runtime_Readback\DRIVE_GEMINI';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$name=if($Mode -eq 'Probe'){'DRIVE_GEMINI_PROJECT_PROBE.json'}else{($RunId+'.json')};$path=Join-Path $dir $name;$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $path -Encoding UTF8;$result['resultPath']=$path}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}elseif($result.loginRequired){exit 3}else{exit 2}
