param(
  [ValidateSet('NOTEBOOKLM','FLOW','AI_STUDIO','FRONT_QA','CENTRAL_CAPTURE','GENERIC')]
  [string]$Service='GENERIC',
  [Parameter(Mandatory=$true)][string]$TargetUrl,
  [string]$ExpectedUrlPattern='',
  [string]$ExpectedExtensionId='',
  [int]$RemoteDebuggingPort=9230,
  [int]$TimeoutSeconds=30,
  [switch]$RestartDedicatedChrome,
  [switch]$ProbeInput,
  [string]$Sentinel=''
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Version='MANAGED_EXTENSION_EXACT_TARGET_V1_20260828'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'ManagedExtensions'
$StatePath=Join-Path $Root 'autopilot-state.json'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$ReadbackDir=''

function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Find-Central{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(!$r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  };return ''
}
function Find-Chrome{
  $cft=Join-Path $Base 'ChromeForTesting'
  $x=@(Get-ChildItem -LiteralPath $cft -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1)
  if($x.Count){return $x[0].FullName}
  return @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))|Where-Object{$_ -and (Test-Path -LiteralPath $_)}|Select-Object -First 1
}
function Get-NormalChromeRoots{
  try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{(-not $_.CommandLine -or -not([string]$_.CommandLine).Contains($DedicatedUserData)) -and (-not $_.CommandLine -or ([string]$_.CommandLine)-notmatch '(?i)(^|\s)--type=')}|ForEach-Object{[int]$_.ProcessId})}catch{return @()}
}
function Stop-Dedicated{
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine).Contains($DedicatedUserData)}|ForEach-Object{try{& taskkill.exe /PID ([int]$_.ProcessId) /T /F 2>$null|Out-Null}catch{}}
  Start-Sleep -Seconds 2
}
function Get-ManagedPaths{
  $s=Read-Json $StatePath;if(-not $s){return @()}
  return @($s.extensions|Where-Object{$_.active -eq $true -and $_.activePath -and (Test-Path -LiteralPath ([string]$_.activePath))}|ForEach-Object{[string]$_.activePath}|Select-Object -Unique)
}
function Get-Architecture([string[]]$Paths,[string]$ExtId){
  $items=@();foreach($p in $Paths){$m=Read-Json (Join-Path $p 'manifest.json');if(-not $m){continue};$arch='extension_page';if($m.background -and $m.background.service_worker){$arch='background_service_worker'}elseif(@($m.content_scripts).Count -and $m.action -and $m.action.default_popup){$arch='content_script_plus_popup'}elseif(@($m.content_scripts).Count){$arch='content_script_only'};$items += [pscustomobject]@{path=$p;name=[string]$m.name;version=[string]$m.version;architecture=$arch;matches=@($m.content_scripts|ForEach-Object{@($_.matches)})|ForEach-Object{$_};js=@($m.content_scripts|ForEach-Object{@($_.js)})|ForEach-Object{$_};popup=$(if($m.action){[string]$m.action.default_popup}else{''});serviceWorker=$(if($m.background){[string]$m.background.service_worker}else{''})}}
  return $items
}
function Match-Target($targets,[string]$Url,[string]$Pattern){
  $pages=@($targets|Where-Object{$_.type -eq 'page'})
  if($Pattern){$x=$pages|Where-Object{([string]$_.url) -match $Pattern}|Select-Object -First 1;if($x){return $x}}
  try{$u=[uri]$Url;$x=$pages|Where-Object{try{([uri]([string]$_.url)).Host -eq $u.Host}catch{$false}}|Select-Object -First 1;if($x){return $x}}catch{}
  return $null
}
function Invoke-DomProbe([string]$WsUrl,[string]$Probe,[string]$Mark){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(!$node){$node=Get-Command node -ErrorAction Stop}
  $js=Join-Path $env:TEMP ('exact-target-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $code=@'
const wsUrl=process.argv[2], doProbe=process.argv[3]==='1', sentinel=process.argv[4]||'';
function conn(url){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);let id=0,p=new Map();ws.onopen=()=>resolve({ws,send:(m,params={})=>new Promise((res,rej)=>{const n=++id;p.set(n,{res,rej});ws.send(JSON.stringify({id:n,method:m,params}));})});ws.onerror=reject;ws.onmessage=e=>{let x;try{x=JSON.parse(e.data)}catch{return};if(x.id&&p.has(x.id)){const q=p.get(x.id);p.delete(x.id);x.error?q.rej(new Error(JSON.stringify(x.error))):q.res(x.result)}}})}
const c=await conn(wsUrl);try{
const expr=`(()=>{const roots=[document],q=[document],seen=new Set(q);while(q.length){const r=q.shift();let es=[];try{es=[...r.querySelectorAll('*')]}catch{};for(const e of es){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot);q.push(e.shadowRoot)}}}let cand=[];for(const r of roots){let es=[];try{es=[...r.querySelectorAll('textarea,input[type="text"],[contenteditable="true"],[role="textbox"]')]}catch{};for(const e of es){const rect=e.getBoundingClientRect?.()||{};cand.push({tag:e.tagName,aria:e.getAttribute?.('aria-label')||'',placeholder:e.getAttribute?.('placeholder')||'',visible:!!(rect.width&&rect.height),value:(e.value??e.innerText??e.textContent??'').slice(0,300)})}}return {url:location.href,title:document.title,candidates:cand,bodyText:(document.body?.innerText||'').slice(0,1000)}})()`;
let r=await c.send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true});let out={page:r.result?.value||null,inputFound:false,inputVerified:false,inputRestored:false};
if(doProbe){const probe=`(()=>{const roots=[document],q=[document],seen=new Set(q);while(q.length){const r=q.shift();let es=[];try{es=[...r.querySelectorAll('*')]}catch{};for(const e of es){if(e.shadowRoot&&!seen.has(e.shadowRoot)){seen.add(e.shadowRoot);roots.push(e.shadowRoot);q.push(e.shadowRoot)}}}let e=null;for(const r of roots){try{e=[...r.querySelectorAll('textarea,input[type="text"],[contenteditable="true"],[role="textbox"]')].find(x=>{const z=x.getBoundingClientRect();return z.width&&z.height&&!x.disabled})||e}catch{}}if(!e)return {found:false};const old=('value'in e)?e.value:e.innerText;const set=v=>{if('value'in e)e.value=v;else e.innerText=v;e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}));e.dispatchEvent(new Event('change',{bubbles:true}))};set(${JSON.stringify(sentinel)});const read=('value'in e)?e.value:e.innerText;set(old);const restored=(('value'in e)?e.value:e.innerText)===old;return {found:true,verified:read===${JSON.stringify(sentinel)},restored,tag:e.tagName,aria:e.getAttribute('aria-label')||'',placeholder:e.getAttribute('placeholder')||''}})()`;let p=await c.send('Runtime.evaluate',{expression:probe,returnByValue:true,awaitPromise:true,userGesture:true});const v=p.result?.value||{};out.inputFound=!!v.found;out.inputVerified=!!v.verified;out.inputRestored=!!v.restored;out.input=v}
console.log(JSON.stringify({ok:true,...out}))
}finally{try{c.ws.close()}catch{};setTimeout(()=>process.exit(0),30)}
'@
  Set-Content -LiteralPath $js -Value $code -Encoding UTF8
  try{$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$node.Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Arguments=('"'+$js+'" "'+$WsUrl+'" '+$(if($Probe){'1'}else{'0'})+' "'+($Mark -replace '"','\"')+'"');$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(20000)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{};throw 'DOM_PROBE_TIMEOUT_20S'};$raw=$ot.Result.Trim();if(!$raw){throw ('DOM_PROBE_EMPTY:'+ $et.Result.Trim())};return (($raw -split "`r?`n")[-1]|ConvertFrom-Json)}finally{Remove-Item $js -Force -ErrorAction SilentlyContinue}
}

$normalBefore=@(Get-NormalChromeRoots)
$paths=@(Get-ManagedPaths);if(!$paths.Count){throw 'NO_ACTIVE_MANAGED_EXTENSIONS'}
$arch=@(Get-Architecture $paths $ExpectedExtensionId)
$chrome=Find-Chrome;if(!$chrome){throw 'CHROME_EXE_NOT_FOUND'}
if($RestartDedicatedChrome){Stop-Dedicated}
$args=@("--user-data-dir=$DedicatedUserData",'--profile-directory=Default','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',('--load-extension='+($paths -join ',')),("--remote-debugging-port=$RemoteDebuggingPort"),'--remote-debugging-address=127.0.0.1',$TargetUrl)
Start-Process -FilePath $chrome -ArgumentList $args -WorkingDirectory (Split-Path -Parent $chrome)|Out-Null
$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$targets=@();$target=$null;do{try{$targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 2);$target=Match-Target $targets $TargetUrl $ExpectedUrlPattern;if($target){break}}catch{};Start-Sleep -Milliseconds 500}while((Get-Date)-lt $deadline)
$extensionTargets=@($targets|Where-Object{([string]$_.url) -like 'chrome-extension://*'})
$extensionIdActive=$false;if($ExpectedExtensionId){$extensionIdActive=@($extensionTargets|Where-Object{([string]$_.url) -like ('chrome-extension://'+$ExpectedExtensionId+'/*')}).Count -gt 0}else{$extensionIdActive=$extensionTargets.Count -gt 0}
$dom=$null;if($target){$mark=$(if($Sentinel){$Sentinel}else{'CENTRAL_EXACT_TARGET_'+$Service+'_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()});$dom=Invoke-DomProbe ([string]$target.webSocketDebuggerUrl) ([bool]$ProbeInput) $mark}
$normalAfter=@(Get-NormalChromeRoots);$missing=@($normalBefore|Where-Object{$normalAfter -notcontains $_})
$targetVerified=[bool]($target -and $dom -and $dom.ok)
$inputGate=$(if($ProbeInput){[bool]($dom.inputFound -and $dom.inputVerified -and $dom.inputRestored)}else{$true})
$result=[ordered]@{ok=[bool]($targetVerified -and $inputGate -and $missing.Count -eq 0);version=$Version;service=$Service;targetUrlRequested=$TargetUrl;targetUrlActual=$(if($target){[string]$target.url}else{''});targetContextOpened=[bool]$target;targetContextVerified=$targetVerified;expectedExtensionId=$ExpectedExtensionId;extensionContextTargets=@($extensionTargets|ForEach-Object{[ordered]@{type=$_.type;url=$_.url;title=$_.title}});extensionIdTargetObserved=$extensionIdActive;architecture=$arch;inputProbeRequested=[bool]$ProbeInput;inputFound=$(if($dom){[bool]$dom.inputFound}else{$false});inputVerified=$(if($dom){[bool]$dom.inputVerified}else{$false});inputRestored=$(if($dom){[bool]$dom.inputRestored}else{$false});dom=$dom;normalChromeUntouched=($missing.Count -eq 0);normalChromeMissingRoots=$missing;loadedPaths=$paths;remoteDebuggingPort=$RemoteDebuggingPort;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;chromeSettingsChanged=$false;at=(Get-Date).ToString('o')}
$central=Find-Central;if($central){$ReadbackDir=Join-Path $central 'Runtime_Readback\Chrome_Exact_Target';New-Item -ItemType Directory -Force -Path $ReadbackDir|Out-Null;$name=('EXACT_TARGET_'+$Service+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.json');$path=Join-Path $ReadbackDir $name;$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $path -Encoding UTF8;$result['resultPath']=$path}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}else{exit 2}
