param(
  [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Version = 'CHROME_FLOW_HEALTH_V2_20260824'

$LegacyRoot = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot = Join-Path $Base 'LocalAgent'
$AgentFile = Join-Path $AgentRoot 'HomeDesignLocalAgent.ps1'
$BootstrapFile = Join-Path $AgentRoot 'AgentBootstrap.ps1'
$AgentStatePath = Join-Path $AgentRoot 'state.json'
$ExtensionRoot = Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$ManifestPath = Join-Path $ExtensionRoot 'manifest.json'
$UserData = Join-Path $Base 'ChromeUserData'
$CftRoot = Join-Path $Base 'ChromeForTesting'
$ReportPath = Join-Path $LegacyRoot 'chrome-flow-health.json'
$LogPath = Join-Path $LegacyRoot 'chrome-flow-health.log'
$StableReleaseUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
$FallbackExtensionId = 'llgjlejpknemhdmckoaifgjnjikceamp'

New-Item -ItemType Directory -Force -Path $LegacyRoot | Out-Null

function Log([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
}

function Read-JsonFile([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) { return $null }
  try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { Log "JSON_READ_FAIL path=$Path error=$($_.Exception.Message)"; return $null }
}

function Normalize-PathText([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  try { return ([IO.Path]::GetFullPath($Path)).TrimEnd('\\').ToLowerInvariant() }
  catch { return $Path.TrimEnd('\\').ToLowerInvariant() }
}

function Find-CftChrome {
  if (!(Test-Path -LiteralPath $CftRoot)) { return $null }
  return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
}

function Get-ProcessRows([string]$Needle) {
  try {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine -like "*$Needle*" })
  } catch { return @() }
}

function Start-BootstrapLoopIfMissing {
  if (!(Test-Path -LiteralPath $BootstrapFile)) { return $false }
  $existing = @(Get-ProcessRows 'HomeDesignAutomationV7*LocalAgent*AgentBootstrap.ps1')
  if ($existing.Count -gt 0) { return $true }
  try {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapFile`"",'-Loop'
    ) -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 1
    Log 'LOCAL_AGENT_BOOTSTRAP_LOOP_STARTED_SAFE'
    return $true
  } catch {
    Log "LOCAL_AGENT_BOOTSTRAP_LOOP_START_FAIL $($_.Exception.Message)"
    return $false
  }
}

function Invoke-SafeAgentCycleIfNeeded($Release,$State,$Manifest) {
  if (!(Test-Path -LiteralPath $AgentFile)) { return [ordered]@{attempted=$false;reason='AGENT_FILE_MISSING'} }
  $targetVersion = [string]$Release.version
  $installedState = if ($State) { [string]$State.installedVersion } else { '' }
  $manifestVersion = if ($Manifest) { [string]$Manifest.version } else { '' }
  $dedicatedRunning = @(Get-ProcessRows $UserData).Count -gt 0
  $needs = ($installedState -ne $targetVersion) -or ($manifestVersion -ne $targetVersion) -or (-not $dedicatedRunning)
  if (-not $needs) { return [ordered]@{attempted=$false;reason='ALREADY_CURRENT'} }

  $activeAgent = @(Get-ProcessRows 'HomeDesignLocalAgent.ps1')
  if ($activeAgent.Count -gt 0) { return [ordered]@{attempted=$false;reason='AGENT_CYCLE_ALREADY_RUNNING'} }

  try {
    Log "SAFE_AGENT_CYCLE_START target=$targetVersion state=$installedState manifest=$manifestVersion dedicatedRunning=$dedicatedRunning"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AgentFile
    $exitCode = $LASTEXITCODE
    Log "SAFE_AGENT_CYCLE_END exit=$exitCode"
    Start-Sleep -Seconds 2
    return [ordered]@{attempted=$true;exitCode=$exitCode;reason='STABLE_CHANNEL_APPLY_OR_HEALTH'}
  } catch {
    Log "SAFE_AGENT_CYCLE_FAIL $($_.Exception.Message)"
    return [ordered]@{attempted=$true;exitCode=1;reason='EXCEPTION';error=$_.Exception.Message}
  }
}

function Resolve-DedicatedExtensionId {
  $expected = Normalize-PathText $ExtensionRoot
  $preferenceFiles = @(
    (Join-Path $UserData 'Default\Preferences'),
    (Join-Path $UserData 'Default\Secure Preferences')
  )
  foreach ($pref in $preferenceFiles) {
    if (!(Test-Path -LiteralPath $pref)) { continue }
    try {
      $json = Get-Content -LiteralPath $pref -Raw -Encoding UTF8 | ConvertFrom-Json
      $settings = $json.extensions.settings
      if (!$settings) { continue }
      foreach ($prop in $settings.PSObject.Properties) {
        $s = $prop.Value
        $p = Normalize-PathText ([string]$s.path)
        if ($p -and $p -eq $expected) {
          return [ordered]@{id=$prop.Name;source=$pref}
        }
      }
    } catch { Log "EXTENSION_ID_PREF_PARSE_FAIL path=$pref error=$($_.Exception.Message)" }
  }
  return [ordered]@{id=$FallbackExtensionId;source='CENTRAL_REGISTRY_FALLBACK'}
}

function Get-FreePort {
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
  $listener.Start()
  $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  $listener.Stop()
  return $port
}

function Invoke-DedicatedExtensionPing([string]$ChromePath,[string]$ExtensionId) {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if (!$node) { $node = Get-Command node -ErrorAction SilentlyContinue }
  if (!$node) { return [ordered]@{ok=$false;error='NODE_NOT_FOUND_FOR_LOCAL_PING'} }
  if ($ExtensionId -notmatch '^[a-p]{32}$') { return [ordered]@{ok=$false;error='INVALID_EXTENSION_ID';extensionId=$ExtensionId} }

  $port = Get-FreePort
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  $tmp = Join-Path $env:TEMP "homedesign-cft-ping-$stamp"
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $resultPath = Join-Path $tmp 'result.json'
  $serverPath = Join-Path $tmp 'server.js'
  $resultJs = ($resultPath | ConvertTo-Json -Compress)
  $extJs = ($ExtensionId | ConvertTo-Json -Compress)
  $timeoutMs = [Math]::Max(8000,$TimeoutSeconds*1000)

  $server = @'
const http=require('http'),fs=require('fs');
const port=__PORT__,resultPath=__RESULT_PATH__,extensionId=__EXTENSION_ID__;
const html=`<!doctype html><meta charset="utf-8"><title>HomeDesign CFT Bridge Check</title><div id="s">NotebookLM Bridge 확인 중…</div><script>
const done=o=>fetch('/result',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(o)}).then(()=>document.getElementById('s').textContent=o.ok?'연결 정상 — 이 탭은 닫아도 됩니다.':'점검 필요 — '+(o.error||'unknown'));
try{if(!globalThis.chrome?.runtime?.sendMessage)done({ok:false,error:'CHROME_RUNTIME_UNAVAILABLE'});else chrome.runtime.sendMessage(extensionId,{source:'notebooklm-webapp-bridge',type:'PING'},r=>{if(chrome.runtime.lastError)done({ok:false,error:chrome.runtime.lastError.message,extensionId});else done({ok:!!r?.ok,response:r,extensionId});});}catch(e){done({ok:false,error:String(e),extensionId});}</script>`;
let finished=false;const finish=(o,c=0)=>{if(finished)return;finished=true;try{fs.writeFileSync(resultPath,JSON.stringify(o,null,2));}catch{}setTimeout(()=>server.close(()=>process.exit(c)),100)};
const server=http.createServer((req,res)=>{if(req.method==='GET'&&req.url==='/'){res.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'});res.end(html);return;}if(req.method==='POST'&&req.url==='/result'){let b='';req.on('data',c=>b+=c);req.on('end',()=>{let o;try{o=JSON.parse(b||'{}')}catch{o={ok:false,error:'RESULT_JSON_PARSE_FAILED'}}res.writeHead(200);res.end('ok');finish(o,o.ok?0:2)});return;}res.writeHead(404);res.end('not found')});
server.listen(port,'127.0.0.1');setTimeout(()=>finish({ok:false,error:'EXTENSION_PING_TIMEOUT',extensionId},2),__TIMEOUT_MS__);
'@
  $server = $server.Replace('__PORT__',[string]$port).Replace('__RESULT_PATH__',$resultJs).Replace('__EXTENSION_ID__',$extJs).Replace('__TIMEOUT_MS__',[string]$timeoutMs)
  Set-Content -LiteralPath $serverPath -Value $server -Encoding UTF8

  $proc = Start-Process -FilePath $node.Source -ArgumentList @($serverPath) -WindowStyle Hidden -PassThru
  Start-Sleep -Milliseconds 500
  $args = @(
    "--user-data-dir=$UserData",
    '--profile-directory=Default',
    "http://127.0.0.1:$port/"
  )
  Start-Process -FilePath $ChromePath -ArgumentList $args | Out-Null

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds + 3)
  while ((Get-Date) -lt $deadline -and !(Test-Path -LiteralPath $resultPath)) { Start-Sleep -Milliseconds 300 }
  if (!(Test-Path -LiteralPath $resultPath)) {
    try { if (!$proc.HasExited) { $proc.Kill() } } catch {}
    return [ordered]@{ok=$false;error='PING_RESULT_NOT_CREATED';extensionId=$ExtensionId}
  }
  try { return Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { return [ordered]@{ok=$false;error='PING_RESULT_PARSE_FAILED';extensionId=$ExtensionId} }
}

Log '=== CHROME FLOW HEALTH V2 START ==='

$release = $null
try { $release = Invoke-RestMethod -Uri $StableReleaseUrl -Method Get -TimeoutSec 20 }
catch { $release = [pscustomobject]@{enabled=$false;version='';healthUrl='';frontUrl='';error=$_.Exception.Message} }

$bootstrapLoopReady = Start-BootstrapLoopIfMissing
$stateBefore = Read-JsonFile $AgentStatePath
$manifestBefore = Read-JsonFile $ManifestPath
$agentCycle = if ($release -and $release.enabled) { Invoke-SafeAgentCycleIfNeeded $release $stateBefore $manifestBefore } else { [ordered]@{attempted=$false;reason='STABLE_RELEASE_UNAVAILABLE'} }
$state = Read-JsonFile $AgentStatePath
$manifest = Read-JsonFile $ManifestPath
$cft = Find-CftChrome
$dedicatedRunning = @(Get-ProcessRows $UserData).Count -gt 0
$extIdentity = Resolve-DedicatedExtensionId

$frontHealth = [ordered]@{ok=$false}
if ($release -and $release.frontUrl) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri ([string]$release.frontUrl) -Method Get -TimeoutSec 15
    $frontHealth = [ordered]@{ok=($r.StatusCode -ge 200 -and $r.StatusCode -lt 400);status=[int]$r.StatusCode}
  } catch { $frontHealth=[ordered]@{ok=$false;error=$_.Exception.Message} }
}

$appsHealth = [ordered]@{ok=$false}
if ($release -and $release.healthUrl) {
  try {
    $body = @{action='health'} | ConvertTo-Json -Compress
    $appsHealth = Invoke-RestMethod -Uri ([string]$release.healthUrl) -Method Post -ContentType 'text/plain;charset=utf-8' -Body $body -TimeoutSec 20
  } catch { $appsHealth=[ordered]@{ok=$false;error=$_.Exception.Message} }
}

$ping = [ordered]@{ok=$false;error='NOT_ATTEMPTED'}
if ($cft -and $dedicatedRunning -and $extIdentity.id) {
  try { $ping = Invoke-DedicatedExtensionPing -ChromePath $cft.FullName -ExtensionId ([string]$extIdentity.id) }
  catch { $ping=[ordered]@{ok=$false;error=$_.Exception.Message} }
}

$targetVersion = if ($release) { [string]$release.version } else { '' }
$stateVersion = if ($state) { [string]$state.installedVersion } else { '' }
$manifestVersion = if ($manifest) { [string]$manifest.version } else { '' }
$versionReady = $targetVersion -and ($stateVersion -eq $targetVersion) -and ($manifestVersion -eq $targetVersion)
$agentStatus = if ($state) { [string]$state.status } else { 'NO_STATE' }
$awaitingE2E = if ($state -and $null -ne $state.awaitingE2E) { [bool]$state.awaitingE2E } else { $false }
$baseHealthy = $bootstrapLoopReady -and $versionReady -and $dedicatedRunning -and [bool]$appsHealth.ok -and [bool]$frontHealth.ok
$pingHealthy = [bool]$ping.ok
$overall = $baseHealthy -and $pingHealthy

$nextAction = if (-not $release.enabled) { 'STABLE_RELEASE_READ_REPAIR' }
elseif (-not $versionReady) { 'LOCAL_AGENT_STABLE_APPLY_PENDING' }
elseif (-not $dedicatedRunning) { 'DEDICATED_CFT_RESTART_PENDING' }
elseif (-not [bool]$appsHealth.ok) { 'APPS_SCRIPT_HEALTH_REPAIR' }
elseif (-not $pingHealthy) { 'DEDICATED_EXTENSION_PING_REPAIR' }
elseif ($awaitingE2E) { 'RUN_NOTEBOOKLM_AUTO_E2E_X2_AND_AUDIT_ACK' }
else { 'NOTEBOOKLM_BRIDGE_HEALTH_READY' }

$report = [ordered]@{
  ok=$overall
  version=$Version
  generatedAt=(Get-Date).ToUniversalTime().ToString('o')
  canonical=[ordered]@{
    mode='HOMEDESIGN_LOCAL_AGENT_DEDICATED_CFT'
    base=$Base
    stableReleaseUrl=$StableReleaseUrl
    targetVersion=$targetVersion
    extensionId=[string]$extIdentity.id
    extensionIdSource=[string]$extIdentity.source
  }
  localAgent=[ordered]@{
    root=$AgentRoot
    bootstrapLoopReady=$bootstrapLoopReady
    statePath=$AgentStatePath
    state=$state
    safeCycle=$agentCycle
  }
  dedicatedChrome=[ordered]@{
    chromePath=$(if($cft){$cft.FullName}else{$null})
    userData=$UserData
    running=$dedicatedRunning
  }
  extension=[ordered]@{
    root=$ExtensionRoot
    manifestVersion=$manifestVersion
    stateInstalledVersion=$stateVersion
    targetVersion=$targetVersion
    versionReady=$versionReady
  }
  frontHealth=$frontHealth
  appsScriptHealth=$appsHealth
  notebookExtensionPing=$ping
  awaitingE2E=$awaitingE2E
  nextAction=$nextAction
  policy=[ordered]@{
    noReinstall=$true
    noNewOAuth=$true
    noNewAppsScriptProject=$true
    noNewDeployment=$true
    normalChatGPTChromeUntouched=$true
    stableChannelOnly=$true
    rollbackOwnedByExistingLocalAgent=$true
  }
}
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Log "DONE ok=$overall status=$agentStatus target=$targetVersion installed=$stateVersion manifest=$manifestVersion ping=$pingHealthy next=$nextAction"

[ordered]@{
  ok=$overall
  action='CHROME_FLOW_HEALTH'
  version=$Version
  localAgentStatus=$agentStatus
  targetVersion=$targetVersion
  installedVersion=$stateVersion
  manifestVersion=$manifestVersion
  dedicatedChromeRunning=$dedicatedRunning
  notebookPingOk=$pingHealthy
  appsScriptHealthOk=[bool]$appsHealth.ok
  awaitingE2E=$awaitingE2E
  nextAction=$nextAction
  reportPath=$ReportPath
} | ConvertTo-Json -Depth 10

if ($overall) { exit 0 } else { exit 2 }
