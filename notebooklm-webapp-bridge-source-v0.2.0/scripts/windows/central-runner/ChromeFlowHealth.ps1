param(
  [int]$TimeoutSeconds = 25
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='CHROME_FLOW_HEALTH_V3_20260829'
$LegacyRoot=Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot=Join-Path $Base 'LocalAgent'
$BootstrapFile=Join-Path $AgentRoot 'AgentBootstrap.ps1'
$StatePath=Join-Path $AgentRoot 'state.json'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$ManifestPath=Join-Path $ExtensionRoot 'manifest.json'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$ReportPath=Join-Path $LegacyRoot 'chrome-flow-health.json'
$LogPath=Join-Path $LegacyRoot 'chrome-flow-health.log'
$Front='https://notebooklm-webapp-bridge.vercel.app/'
$Apps='https://script.google.com/macros/s/AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P/exec'
$FallbackExtensionId='llgjlejpknemhdmckoaifgjnjikceamp'
New-Item -ItemType Directory -Force -Path $LegacyRoot|Out-Null
function Log([string]$m){Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $m" -Encoding UTF8}
function Json([string]$p){if(!(Test-Path -LiteralPath $p)){return $null};try{Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Procs([string]$needle){try{@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine).Contains($needle)})}catch{@()}}
function Cft(){Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}
function Bootstrap(){if(!(Test-Path -LiteralPath $BootstrapFile)){return $false};$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*LocalAgent*AgentBootstrap.ps1*'});if(!$p.Count){Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapFile`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep 1};return $true}
function Restart-Dedicated([string]$chrome){
  $normalBefore=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{-not $_.CommandLine -or -not ([string]$_.CommandLine).Contains($UserData)}|ForEach-Object{[int]$_.ProcessId})
  foreach($p in @(Procs $UserData)){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}
  Start-Sleep 2
  $args=@("--user-data-dir=$UserData",'--profile-directory=Default','--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble')
  if(Test-Path -LiteralPath (Join-Path $ExtensionRoot 'manifest.json')){$args+=("--load-extension=$ExtensionRoot")}
  $args+=$Front
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  Start-Sleep 4
  $normalAfter=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{-not $_.CommandLine -or -not ([string]$_.CommandLine).Contains($UserData)}|ForEach-Object{[int]$_.ProcessId})
  $missing=@($normalBefore|Where-Object{$normalAfter -notcontains $_})
  return [ordered]@{dedicatedRunning=@(Procs $UserData).Count -gt 0;normalChromeUntouched=($missing.Count -eq 0);normalMissing=$missing}
}
function Ping([string]$chrome,[string]$id){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(!$node){$node=Get-Command node -ErrorAction SilentlyContinue};if(!$node){return [ordered]@{ok=$false;error='NODE_NOT_FOUND'}}
  $listener=New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$port=([Net.IPEndPoint]$listener.LocalEndpoint).Port;$listener.Stop()
  $tmp=Join-Path $env:TEMP ('flow-wake-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $tmp|Out-Null;$r=Join-Path $tmp 'r.json';$s=Join-Path $tmp 's.js'
  $rcode=($r|ConvertTo-Json -Compress);$iid=($id|ConvertTo-Json -Compress);$ms=[Math]::Max(10000,$TimeoutSeconds*1000)
  $js=@'
const http=require('http'),fs=require('fs');const port=__PORT__,out=__OUT__,id=__ID__;let done=false;const finish=o=>{if(done)return;done=true;try{fs.writeFileSync(out,JSON.stringify(o,null,2))}catch{};setTimeout(()=>server.close(()=>process.exit(o.ok?0:2)),100)};const html=`<script>try{chrome.runtime.sendMessage(${id},{source:'notebooklm-webapp-bridge',type:'PING'},r=>{fetch('/r',{method:'POST',body:JSON.stringify(chrome.runtime.lastError?{ok:false,error:chrome.runtime.lastError.message}:{ok:!!r?.ok,response:r})})})}catch(e){fetch('/r',{method:'POST',body:JSON.stringify({ok:false,error:String(e)})})}</script>`;const server=http.createServer((q,p)=>{if(q.method==='GET'){p.end(html);return}let b='';q.on('data',c=>b+=c);q.on('end',()=>{p.end('ok');try{finish(JSON.parse(b||'{}'))}catch{finish({ok:false,error:'PARSE'})}})});server.listen(port,'127.0.0.1');setTimeout(()=>finish({ok:false,error:'PING_TIMEOUT'}),__MS__);
'@
  $js=$js.Replace('__PORT__',[string]$port).Replace('__OUT__',$rcode).Replace('__ID__',$iid).Replace('__MS__',[string]$ms);Set-Content -LiteralPath $s -Value $js -Encoding UTF8
  $np=Start-Process -FilePath $node.Source -ArgumentList @($s) -WindowStyle Hidden -PassThru;Start-Sleep -Milliseconds 400;Start-Process -FilePath $chrome -ArgumentList @("--user-data-dir=$UserData",'--profile-directory=Default',"http://127.0.0.1:$port/")|Out-Null
  $d=(Get-Date).AddSeconds($TimeoutSeconds+4);while((Get-Date)-lt$d -and !(Test-Path -LiteralPath $r)){Start-Sleep -Milliseconds 300};if(!(Test-Path -LiteralPath $r)){try{$np.Kill()}catch{};return [ordered]@{ok=$false;error='PING_RESULT_MISSING'}};try{return Get-Content -LiteralPath $r -Raw|ConvertFrom-Json}catch{return [ordered]@{ok=$false;error='PING_RESULT_PARSE'}}
}
Log '=== FLOW HEALTH V3 START ==='
$bootstrap=Bootstrap
$state=Json $StatePath;$manifest=Json $ManifestPath;$chrome=Cft
if(!$chrome){throw 'CFT_CHROME_NOT_FOUND'}
$restart=Restart-Dedicated $chrome.FullName
$frontOk=$false;try{$w=Invoke-WebRequest -UseBasicParsing -Uri $Front -TimeoutSec 15;$frontOk=$w.StatusCode -ge 200 -and $w.StatusCode -lt 400}catch{}
$appsOk=$false;try{$a=Invoke-RestMethod -Uri $Apps -Method Post -ContentType 'text/plain;charset=utf-8' -Body '{"action":"health"}' -TimeoutSec 20;$appsOk=[bool]$a.ok}catch{}
$ping=Ping $chrome.FullName $FallbackExtensionId
$ok=[bool]($bootstrap -and $restart.dedicatedRunning -and $restart.normalChromeUntouched -and $frontOk -and $appsOk -and $ping.ok)
$report=[ordered]@{ok=$ok;version=$Version;generatedAt=(Get-Date).ToString('o');state=$state;manifestVersion=$(if($manifest){[string]$manifest.version}else{''});dedicatedRestart=$restart;frontHealthOk=$frontOk;appsScriptHealthOk=$appsOk;notebookExtensionPing=$ping;queueWakeIntent='SERVICE_WORKER_COLD_RELOAD_THEN_LOCAL_ASYNC_POLL';policy=[ordered]@{noReinstall=$true;noNewOAuth=$true;noNewAppsScriptProject=$true;noNewDeployment=$true;normalChromeUntouched=[bool]$restart.normalChromeUntouched;generateClicked=$false;creditSpend=$false}}
$report|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Log "DONE ok=$ok dedicated=$($restart.dedicatedRunning) normalUntouched=$($restart.normalChromeUntouched) ping=$($ping.ok) apps=$appsOk front=$frontOk"
[ordered]@{ok=$ok;action='CHROME_FLOW_HEALTH';version=$Version;dedicatedChromeRunning=[bool]$restart.dedicatedRunning;normalChromeUntouched=[bool]$restart.normalChromeUntouched;notebookPingOk=[bool]$ping.ok;appsScriptHealthOk=$appsOk;frontHealthOk=$frontOk;reportPath=$ReportPath}|ConvertTo-Json -Depth 10
if($ok){exit 0}else{exit 2}
