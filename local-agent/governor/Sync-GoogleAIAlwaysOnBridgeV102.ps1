param(
  [switch]$AllowDedicatedRestart
)

$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ExtensionId='kieodjjlhpefnakodgllmpckepjaggbd'
$ExpectedName='Google AI Local Bridge v1'
$ExpectedVersion='1.0.2'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ReceiptPath=Join-Path $Root 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC.json'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$CanonicalRoot='extensions/google-ai-always-on-bridge/1.0.2'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$Canonical=@{
  'manifest.json'=@{blob='bdcdb6b67c096eebc7f9c4322251ca02526264b1';sha256='22c1ad5470b355f05d8e53e07c66d068dc16366f7b677dd12fcd15ab2f36a553'}
  'service-worker.js'=@{blob='7a0509a4cff6b987a5c5b36fd22024ce88a87a5f';sha256='bc522b5ccf93b754cdba2454b96e08ce0323b470414058b7dd8657623550a602'}
  'content/flow.js'=@{blob='cf21e7cd741aa59e4aca9b87aca742e4642afecc';sha256='80b069153a101b61a37f66bc23890184bda0f0b8ca1bfafa804213afe6997b21'}
}

function Api([string]$Path){
  Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-GoogleAI-AlwaysOn-Sync';'Accept'='application/vnd.github+json'} -TimeoutSec 30
}
function GitBlob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function Sha256([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function ReadJson([string]$Path){try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function FindCentral{
  $name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $name),(Join-Path $d.Root ('My Drive\'+$name)),(Join-Path $d.Root ($myDriveKo+'\'+$name)),(Join-Path $d.Root ('Google Drive\'+$name)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
function SaveReceipt($Object){
  $json=$Object|ConvertTo-Json -Depth 40
  $json|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
  $central=FindCentral
  if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC.json') -Encoding UTF8}
}
function AddCandidate([System.Collections.ArrayList]$List,[string]$Profile,[string]$Path,[string]$Source){
  if(-not$Path){return}
  try{$resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path}catch{return}
  if(-not(Test-Path -LiteralPath (Join-Path $resolved 'manifest.json') -PathType Leaf)){return}
  $manifest=ReadJson (Join-Path $resolved 'manifest.json')
  if(-not$manifest -or [string]$manifest.name-ne$ExpectedName){return}
  if(@($List|Where-Object{[string]$_.path-eq$resolved}).Count-gt0){return}
  [void]$List.Add([pscustomobject]@{profile=$Profile;path=$resolved;source=$Source;version=[string]$manifest.version})
}
function ScanProfile([System.Collections.ArrayList]$List,[string]$Label,[string]$ProfileRoot){
  if(-not(Test-Path -LiteralPath $ProfileRoot -PathType Container)){return}
  foreach($prefName in @('Preferences','Secure Preferences')){
    $pref=Join-Path $ProfileRoot $prefName;if(-not(Test-Path -LiteralPath $pref -PathType Leaf)){continue}
    try{
      $data=Get-Content -LiteralPath $pref -Raw -Encoding UTF8|ConvertFrom-Json
      $settings=$data.extensions.settings
      if(-not$settings){continue}
      $prop=$settings.PSObject.Properties[$ExtensionId]
      if(-not$prop -or -not$prop.Value.path){continue}
      $p=[string]$prop.Value.path
      if(-not[IO.Path]::IsPathRooted($p)){$p=Join-Path $ProfileRoot $p}
      AddCandidate $List $Label $p $prefName
    }catch{}
  }
}
function GetCandidates{
  $list=New-Object System.Collections.ArrayList
  $normal=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if(Test-Path -LiteralPath $normal){foreach($p in @(Get-ChildItem -LiteralPath $normal -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name-eq'Default'-or$_.Name-like'Profile *'})){ScanProfile $list ('NORMAL_CHROME/'+$p.Name) $p.FullName}}
  ScanProfile $list 'HOMEDESIGN_CFT/Default' (Join-Path $DedicatedUserData 'Default')
  AddCandidate $list 'KNOWN_FALLBACK' (Join-Path $env:USERPROFILE 'Downloads\Google_AI_Always_On_Bridge_v1.0.1_fixed\extension') 'KNOWN_PATH'
  return @($list)
}
function FetchCanonical([string]$Relative,[string]$Temp){
  $spec=$Canonical[$Relative];if(-not$spec){throw('CANONICAL_SPEC_MISSING:'+ $Relative)}
  $r=Api ($CanonicalRoot+'/'+$Relative)
  if(([string]$r.sha).ToLowerInvariant()-ne([string]$spec.blob).ToLowerInvariant()){throw('CANONICAL_GIT_BLOB_MISMATCH:'+ $Relative)}
  [IO.File]::WriteAllBytes($Temp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')))
  if((GitBlob $Temp).ToLowerInvariant()-ne([string]$spec.blob).ToLowerInvariant()){throw('DOWNLOADED_GIT_BLOB_MISMATCH:'+ $Relative)}
  if((Sha256 $Temp)-ne([string]$spec.sha256).ToLowerInvariant()){throw('DOWNLOADED_SHA256_MISMATCH:'+ $Relative)}
}
function UpdateTarget($Candidate,[string]$Stamp){
  $path=[string]$Candidate.path
  $config=Join-Path $path 'config.js';if(-not(Test-Path -LiteralPath $config -PathType Leaf)){throw('CONFIG_MISSING_PRESERVE_REQUIRED:'+ $path)}
  $notebook=Join-Path $path 'content\notebooklm.js';if(-not(Test-Path -LiteralPath $notebook -PathType Leaf)){throw('NOTEBOOKLM_MISSING_PRESERVE_REQUIRED:'+ $path)}
  $configBefore=Sha256 $config;$notebookBefore=Sha256 $notebook
  $backup=Join-Path (Join-Path $Base 'Backups\GoogleAIAlwaysOnBridge') $Stamp
  $backup=Join-Path $backup (([string]$Candidate.profile-replace'[^A-Za-z0-9_.-]','_'))
  New-Item -ItemType Directory -Force -Path (Join-Path $backup 'content')|Out-Null
  foreach($rel in @('manifest.json','service-worker.js','content/flow.js')){
    $dest=Join-Path $path ($rel-replace'/','\')
    if(Test-Path -LiteralPath $dest -PathType Leaf){$bak=Join-Path $backup ($rel-replace'/','\');$bakParent=Split-Path -Parent $bak;if(-not(Test-Path -LiteralPath $bakParent)){New-Item -ItemType Directory -Force -Path $bakParent|Out-Null};Copy-Item -LiteralPath $dest -Destination $bak -Force}
  }
  $temps=@{}
  try{
    foreach($rel in @('manifest.json','service-worker.js','content/flow.js')){
      $dest=Join-Path $path ($rel-replace'/','\');$parent=Split-Path -Parent $dest;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
      $tmp=$dest+'.v102sync';FetchCanonical $rel $tmp;$temps[$rel]=$tmp
    }
    foreach($rel in @('manifest.json','service-worker.js','content/flow.js')){$dest=Join-Path $path ($rel-replace'/','\');Move-Item -LiteralPath $temps[$rel] -Destination $dest -Force}
    $manifest=ReadJson (Join-Path $path 'manifest.json');if(-not$manifest-or[string]$manifest.name-ne$ExpectedName-or[string]$manifest.version-ne$ExpectedVersion){throw'POST_UPDATE_MANIFEST_IDENTITY_FAILED'}
    foreach($rel in @('manifest.json','service-worker.js','content/flow.js')){$dest=Join-Path $path ($rel-replace'/','\');if((Sha256 $dest)-ne([string]$Canonical[$rel].sha256).ToLowerInvariant()){throw('POST_UPDATE_SHA256_MISMATCH:'+ $rel)}}
    $configAfter=Sha256 $config;$notebookAfter=Sha256 $notebook
    if($configAfter-ne$configBefore){throw'CONFIG_MUTATION_DETECTED'}
    if($notebookAfter-ne$notebookBefore){throw'NOTEBOOKLM_MUTATION_DETECTED'}
    return [pscustomobject]@{ok=$true;profile=$Candidate.profile;path=$path;fromVersion=$Candidate.version;toVersion=$ExpectedVersion;backupPath=$backup;configPreserved=$true;configSha256=$configAfter;notebooklmPreserved=$true;notebooklmSha256=$notebookAfter;manifestSha256=(Sha256 (Join-Path $path 'manifest.json'));serviceWorkerSha256=(Sha256 (Join-Path $path 'service-worker.js'));flowSha256=(Sha256 (Join-Path $path 'content\flow.js'))}
  }catch{
    foreach($rel in @('manifest.json','service-worker.js','content/flow.js')){
      $bak=Join-Path $backup ($rel-replace'/','\');$dest=Join-Path $path ($rel-replace'/','\');if(Test-Path -LiteralPath $bak -PathType Leaf){Copy-Item -LiteralPath $bak -Destination $dest -Force}
      if($temps.ContainsKey($rel)){Remove-Item -LiteralPath $temps[$rel] -Force -ErrorAction SilentlyContinue}
    }
    throw
  }
}
function GetCdpPorts{
  $ports=@()
  try{foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue)){$cmd=[string]$p.CommandLine;if($cmd-match'--remote-debugging-port(?:=|\s+)(\d+)'){$ports+=[int]$Matches[1]}}}catch{}
  return @($ports|Sort-Object -Unique)
}
function InvokeNodeExpression([string]$Ws,[string]$Expression){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not$node){$node=Get-Command node -ErrorAction SilentlyContinue};if(-not$node){return [pscustomobject]@{ok=$false;error='NODE_NOT_FOUND';value=$null}}
  $js=Join-Path $env:TEMP ('hd-ext-eval-'+[guid]::NewGuid().ToString('N')+'.mjs')
  $code=@'
const wsUrl=process.argv[2], expr=Buffer.from(process.argv[3],'base64').toString('utf8');
const ws=new WebSocket(wsUrl);let seq=0;const pending=new Map();
const opened=new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
ws.onmessage=e=>{let m;try{m=JSON.parse(e.data)}catch{return};if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result);}};
await opened;const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
try{const r=await send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true,userGesture:true});console.log(JSON.stringify({ok:true,value:r.result?.value??null}));}catch(e){console.log(JSON.stringify({ok:false,error:String(e.message||e)}));process.exitCode=2;}finally{try{ws.close()}catch{}}
'@
  Set-Content -LiteralPath $js -Value $code -Encoding UTF8
  try{$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Expression));$out=& $node.Source $js $Ws $b64 2>&1|Out-String;$last=($out.Trim().Split("`n")|Select-Object -Last 1).Trim();if(-not$last){return [pscustomobject]@{ok=$false;error='EMPTY_NODE_RESULT';value=$null}};return ($last|ConvertFrom-Json)}catch{return [pscustomobject]@{ok=$false;error=$_.Exception.Message;value=$null}}finally{Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue}
}
function TryCdpReload{
  foreach($port in @(GetCdpPorts)){
    try{
      $targets=@(Invoke-RestMethod -Uri ('http://127.0.0.1:'+ $port +'/json/list') -TimeoutSec 3)
      $t=$targets|Where-Object{[string]$_.url -like ('chrome-extension://'+$ExtensionId+'/*') -and $_.webSocketDebuggerUrl}|Select-Object -First 1
      if(-not$t){continue}
      $reload=InvokeNodeExpression ([string]$t.webSocketDebuggerUrl) "(()=>{setTimeout(()=>chrome.runtime.reload(),120);return 'RELOAD_SCHEDULED'})()"
      if(-not$reload.ok){continue}
      Start-Sleep -Seconds 4
      $targets2=@(Invoke-RestMethod -Uri ('http://127.0.0.1:'+ $port +'/json/list') -TimeoutSec 3)
      $t2=$targets2|Where-Object{[string]$_.url -like ('chrome-extension://'+$ExtensionId+'/*') -and $_.webSocketDebuggerUrl}|Select-Object -First 1
      $version=''
      if($t2){$vr=InvokeNodeExpression ([string]$t2.webSocketDebuggerUrl) 'chrome.runtime.getManifest().version';if($vr.ok){$version=[string]$vr.value}}
      return [pscustomobject]@{requested=$true;port=$port;verified=($version-eq$ExpectedVersion);version=$version;targetUrl=$(if($t2){[string]$t2.url}else{'RESTARTING_OR_SLEEPING'})}
    }catch{}
  }
  return [pscustomobject]@{requested=$false;port=$null;verified=$false;version='';targetUrl=''}
}
function FindCftChrome{return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}
function RestartDedicated([string]$ExtensionPath){
  if(-not$AllowDedicatedRestart){return [pscustomobject]@{attempted=$false;ok=$false;reason='SWITCH_NOT_SET'}}
  $chrome=FindCftChrome;if(-not$chrome){return [pscustomobject]@{attempted=$true;ok=$false;reason='CFT_CHROME_NOT_FOUND'}}
  try{Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine-and([string]$_.CommandLine).Contains($DedicatedUserData)}|ForEach-Object{try{Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}};Start-Sleep -Seconds 2
    $args=@("--user-data-dir=$DedicatedUserData",'--profile-directory=Default','--new-window','--no-first-run','--no-default-browser-check',("--load-extension=$ExtensionPath"),'--remote-debugging-port=9224','--remote-debugging-address=127.0.0.1','https://labs.google/fx/tools/flow')
    Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.Directory.FullName|Out-Null;Start-Sleep -Seconds 5
    return [pscustomobject]@{attempted=$true;ok=$true;reason='DEDICATED_ONLY';normalChromeTouched=$false}
  }catch{return [pscustomobject]@{attempted=$true;ok=$false;reason=$_.Exception.Message;normalChromeTouched=$false}}
}

$started=(Get-Date).ToString('o');$errors=@();$updates=@();$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
try{
  $candidates=@(GetCandidates)
  if($candidates.Count-eq0){throw'INSTALLED_EXTENSION_PATH_NOT_FOUND'}
  foreach($candidate in $candidates){try{$updates+=UpdateTarget $candidate $stamp}catch{$errors+=([string]$candidate.profile+':'+$_.Exception.Message)}}
  if($updates.Count-eq0){throw('NO_TARGET_UPDATED:'+($errors-join'|'))}
  $cdp=TryCdpReload
  $dedicated=$null
  if(-not$cdp.verified){$dedicatedCandidate=$updates|Where-Object{[string]$_.profile-like'HOMEDESIGN_CFT/*'}|Select-Object -First 1;if($dedicatedCandidate){$dedicated=RestartDedicated ([string]$dedicatedCandidate.path);if($dedicated.ok){Start-Sleep -Seconds 4;$cdp=TryCdpReload}}}
  $ok=[bool]($updates.Count-gt0 -and @($updates|Where-Object{-not$_.configPreserved-or-not$_.notebooklmPreserved}).Count-eq0)
  $rec=[ordered]@{ok=$ok;action='GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC';revision='V1_PATH_PRESERVE_SECRET_SAFE';startedAt=$started;completedAt=(Get-Date).ToString('o');extensionId=$ExtensionId;expectedVersion=$ExpectedVersion;updatedTargets=$updates;errors=$errors;configContentRead=$false;configPreserved=$true;notebooklmPreserved=$true;normalChromeTouched=$false;dedicatedRestart=$dedicated;cdpReloadRequested=[bool]$cdp.requested;cdpReloadVerified=[bool]$cdp.verified;cdpPort=$cdp.port;runtimeVersion=[string]$cdp.version;reloadPending=[bool](-not$cdp.verified);generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;duplicateInstallCreated=$false};SaveReceipt $rec;$rec|ConvertTo-Json -Depth 40 -Compress;if($ok){exit 0}else{exit 2}
}catch{
  $errors+=$_.Exception.Message;$rec=[ordered]@{ok=$false;action='GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC';revision='V1_PATH_PRESERVE_SECRET_SAFE';startedAt=$started;completedAt=(Get-Date).ToString('o');extensionId=$ExtensionId;expectedVersion=$ExpectedVersion;updatedTargets=$updates;errors=$errors;configContentRead=$false;normalChromeTouched=$false;reloadPending=$true;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;duplicateInstallCreated=$false};SaveReceipt $rec;$rec|ConvertTo-Json -Depth 40 -Compress;exit 2
}
