param(
  [string]$AppsScriptUrl = 'https://script.google.com/macros/s/AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P/exec',
  [string]$FrontendUrl = 'https://notebooklm-webapp-bridge.vercel.app',
  [int]$TimeoutSeconds = 18
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Version = 'CHROME_FLOW_HEALTH_V1_1_20260824'
$Root = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$ReportPath = Join-Path $Root 'chrome-flow-health.json'
$LogPath = Join-Path $Root 'chrome-flow-health.log'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function Log([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
}

function Add-Check([System.Collections.Generic.List[object]]$Checks,[string]$Name,[bool]$Ok,[string]$Detail) {
  $Checks.Add([pscustomobject]@{ name=$Name; ok=$Ok; detail=$Detail }) | Out-Null
}

function Get-ChromePath {
  $cmd = Get-Command chrome.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
  return $null
}

function Read-Manifest([string]$Path) {
  try {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
  } catch { return $null }
}

function Get-ChromeExtensionInventory {
  $userData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  # Windows PowerShell 5.1 compatibility: use a normal PowerShell array here.
  # Generic List[object] wrapped by @() can throw "Argument types do not match".
  $rows = @()
  if (!(Test-Path -LiteralPath $userData)) { return @() }

  $profiles = Get-ChildItem -LiteralPath $userData -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }

  foreach ($profile in $profiles) {
    $seen = @{}
    $extRoot = Join-Path $profile.FullName 'Extensions'
    if (Test-Path -LiteralPath $extRoot) {
      foreach ($idDir in (Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue)) {
        $versionDir = Get-ChildItem -LiteralPath $idDir.FullName -Directory -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending | Select-Object -First 1
        if (!$versionDir) { continue }
        $manifestPath = Join-Path $versionDir.FullName 'manifest.json'
        $m = Read-Manifest $manifestPath
        if (!$m) { continue }
        $key = "$($profile.Name)|$($idDir.Name)"
        $seen[$key] = $true
        $rows += [pscustomobject]@{
          profile=$profile.Name; id=$idDir.Name; name=[string]$m.name; version=[string]$m.version;
          path=$versionDir.FullName; unpacked=$false; manifest=$m
        }
      }
    }

    $prefPath = Join-Path $profile.FullName 'Preferences'
    if (Test-Path -LiteralPath $prefPath) {
      try {
        $p = Get-Content -Raw -LiteralPath $prefPath -Encoding UTF8 | ConvertFrom-Json
        $settings = $p.extensions.settings
        if ($settings) {
          foreach ($prop in $settings.PSObject.Properties) {
            $s = $prop.Value
            if (!$s.path) { continue }
            $path = [string]$s.path
            if (!(Test-Path -LiteralPath $path)) { continue }
            $m = Read-Manifest (Join-Path $path 'manifest.json')
            if (!$m) { continue }
            $key = "$($profile.Name)|$($prop.Name)"
            if ($seen[$key]) { continue }
            $rows += [pscustomobject]@{
              profile=$profile.Name; id=$prop.Name; name=[string]$m.name; version=[string]$m.version;
              path=$path; unpacked=$true; manifest=$m
            }
          }
        }
      } catch { Log "PREFERENCES_PARSE_FAILED profile=$($profile.Name) error=$($_.Exception.Message)" }
    }
  }
  return $rows
}

function Test-ExtensionFiles($Ext,[System.Collections.Generic.List[object]]$Checks) {
  if (!$Ext) { return }
  $m = $Ext.manifest
  $base = [string]$Ext.path
  if ($m.background -and $m.background.service_worker) {
    $p = Join-Path $base ([string]$m.background.service_worker)
    Add-Check $Checks "$($Ext.name) service_worker" (Test-Path -LiteralPath $p) $p
  }
  foreach ($cs in @($m.content_scripts)) {
    foreach ($js in @($cs.js)) {
      $p = Join-Path $base ([string]$js)
      Add-Check $Checks "$($Ext.name) content_script $js" (Test-Path -LiteralPath $p) $p
    }
  }
}

function Get-FreePort {
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
  $listener.Start()
  $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  $listener.Stop()
  return $port
}

function Invoke-ExtensionPing([string]$ChromePath,[string]$ExtensionId,[int]$TimeoutSeconds) {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if (!$node) { $node = Get-Command node -ErrorAction SilentlyContinue }
  if (!$node) { return [ordered]@{ ok=$false; error='NODE_NOT_FOUND' } }
  if ($ExtensionId -notmatch '^[a-p]{32}$') { return [ordered]@{ ok=$false; error='INVALID_EXTENSION_ID'; extensionId=$ExtensionId } }

  $port = Get-FreePort
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  $tmp = Join-Path $env:TEMP "chrome-flow-ping-$stamp"
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $resultPath = Join-Path $tmp 'result.json'
  $serverPath = Join-Path $tmp 'server.js'
  $resultJs = ($resultPath | ConvertTo-Json -Compress)
  $extJs = ($ExtensionId | ConvertTo-Json -Compress)
  $timeoutMs = [Math]::Max(5000,$TimeoutSeconds*1000)

  $server = @'
const http = require('http');
const fs = require('fs');
const port = __PORT__;
const resultPath = __RESULT_PATH__;
const extensionId = __EXTENSION_ID__;
const html = `<!doctype html><meta charset="utf-8"><title>HomeDesign Chrome Bridge Check</title>
<body style="font-family:system-ui;padding:24px"><h2>Chrome Bridge 자동 점검</h2><div id="s">확장 응답 확인 중…</div>
<script>
const done=(obj)=>fetch('/result',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(obj)})
  .then(()=>{document.getElementById('s').textContent=obj.ok?'연결 정상 — 이 탭은 닫아도 됩니다.':'연결 점검 필요 — '+(obj.error||'unknown');});
try{
  if(!globalThis.chrome || !chrome.runtime || !chrome.runtime.sendMessage){ done({ok:false,error:'CHROME_RUNTIME_UNAVAILABLE'}); }
  else chrome.runtime.sendMessage(extensionId,{source:'notebooklm-webapp-bridge',type:'PING'},(response)=>{
    if(chrome.runtime.lastError) done({ok:false,error:chrome.runtime.lastError.message,extensionId});
    else done({ok:!!(response&&response.ok),response,extensionId});
  });
}catch(e){done({ok:false,error:String(e),extensionId});}
</script>`;
let finished=false;
const finish=(obj,code=0)=>{
  if(finished) return; finished=true;
  try{fs.writeFileSync(resultPath,JSON.stringify(obj,null,2));}catch{}
  setTimeout(()=>server.close(()=>process.exit(code)),150);
};
const server=http.createServer((req,res)=>{
  if(req.method==='GET' && req.url==='/'){
    res.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'}); res.end(html); return;
  }
  if(req.method==='POST' && req.url==='/result'){
    let body=''; req.on('data',c=>body+=c); req.on('end',()=>{
      let obj; try{obj=JSON.parse(body||'{}');}catch{obj={ok:false,error:'RESULT_JSON_PARSE_FAILED',raw:body};}
      res.writeHead(200,{'content-type':'text/plain'});res.end('ok'); finish(obj,obj.ok?0:2);
    }); return;
  }
  res.writeHead(404);res.end('not found');
});
server.listen(port,'127.0.0.1');
setTimeout(()=>finish({ok:false,error:'EXTENSION_PING_TIMEOUT',extensionId},2),__TIMEOUT_MS__);
'@
  $server = $server.Replace('__PORT__',[string]$port).Replace('__RESULT_PATH__',$resultJs).Replace('__EXTENSION_ID__',$extJs).Replace('__TIMEOUT_MS__',[string]$timeoutMs)
  Set-Content -LiteralPath $serverPath -Value $server -Encoding UTF8

  $proc = Start-Process -FilePath $node.Source -ArgumentList @($serverPath) -WindowStyle Hidden -PassThru
  Start-Sleep -Milliseconds 600
  Start-Process -FilePath $ChromePath -ArgumentList "http://127.0.0.1:$port/" | Out-Null

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds + 3)
  while ((Get-Date) -lt $deadline -and !(Test-Path -LiteralPath $resultPath)) { Start-Sleep -Milliseconds 300 }
  if (!(Test-Path -LiteralPath $resultPath)) {
    try { if (!$proc.HasExited) { $proc.Kill() } } catch {}
    return [ordered]@{ ok=$false; error='PING_RESULT_NOT_CREATED'; extensionId=$ExtensionId; port=$port }
  }
  try { return Get-Content -Raw -LiteralPath $resultPath -Encoding UTF8 | ConvertFrom-Json }
  catch { return [ordered]@{ ok=$false; error='PING_RESULT_PARSE_FAILED'; extensionId=$ExtensionId } }
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$inventory = @(Get-ChromeExtensionInventory)
$known = @(
  [pscustomobject]@{ name='NotebookLM WebApp Bridge'; expected='0.2.4'; priority='P0_FALLBACK' },
  [pscustomobject]@{ name='Google AI Local Bridge v1'; expected='1.0.1'; priority='P0' },
  [pscustomobject]@{ name='Flow Agent Bridge'; expected='0.1.0'; priority='P1' },
  [pscustomobject]@{ name='AI Studio Bridge'; expected='0.3.2'; priority='P1' },
  [pscustomobject]@{ name='Front App Test Bridge'; expected='1.0.2'; priority='P1' }
)

$knownResults = @()
foreach ($k in $known) {
  $matches = @($inventory | Where-Object { $_.name -eq $k.name })
  $ext = $matches | Select-Object -First 1
  $ok = $null -ne $ext
  $detail = 'NOT_FOUND'
  if ($ok) { $detail = "v$($ext.version) id=$($ext.id) profile=$($ext.profile) path=$($ext.path)" }
  Add-Check $checks "Installed $($k.name)" $ok $detail
  if ($ext) {
    Add-Check $checks "Version $($k.name)" ([string]$ext.version -eq [string]$k.expected) "installed=$($ext.version) expected=$($k.expected)"
    Test-ExtensionFiles $ext $checks
  }
  $knownResults += [pscustomobject]@{
    name=$k.name; expected=$k.expected; priority=$k.priority; found=$ok;
    version=$(if($ext){$ext.version}else{$null}); id=$(if($ext){$ext.id}else{$null});
    profile=$(if($ext){$ext.profile}else{$null}); path=$(if($ext){$ext.path}else{$null}); unpacked=$(if($ext){$ext.unpacked}else{$null})
  }
}

$chromePath = Get-ChromePath
Add-Check $checks 'Chrome executable' ($null -ne $chromePath) ([string]$chromePath)

$clasp = Get-Command clasp.cmd -ErrorAction SilentlyContinue
$claspDetail = 'NOT_FOUND'
if ($clasp) { $claspDetail = [string]$clasp.Source }
Add-Check $checks 'clasp.cmd' ($null -ne $clasp) $claspDetail
$claspAuth = $false
if ($clasp) {
  & $clasp.Source show-authorized-user --json *> $null
  if ($LASTEXITCODE -eq 0) { $claspAuth=$true }
  else {
    & $clasp.Source show-authorized-user *> $null
    if ($LASTEXITCODE -eq 0) { $claspAuth=$true }
  }
}
$claspAuthDetail = 'NOT_AVAILABLE'
if ($claspAuth) { $claspAuthDetail = 'REUSED_NO_NEW_LOGIN' }
Add-Check $checks 'Existing clasp authorization' $claspAuth $claspAuthDetail

$task = Get-ScheduledTask -TaskName 'Central Apps Script Runner' -ErrorAction SilentlyContinue
$taskDetail = 'NOT_INSTALLED'
if ($task) { $taskDetail = "state=$($task.State)" }
Add-Check $checks 'Central Apps Script Runner scheduled task' ($null -ne $task) $taskDetail

$frontendHealth = $null
try {
  $r = Invoke-WebRequest -UseBasicParsing -Uri $FrontendUrl -Method Get -TimeoutSec 12
  $frontendHealth = [ordered]@{ ok=($r.StatusCode -ge 200 -and $r.StatusCode -lt 400); status=[int]$r.StatusCode }
} catch { $frontendHealth=[ordered]@{ok=$false;error=$_.Exception.Message} }
Add-Check $checks 'NotebookLM frontend HTTP' ([bool]$frontendHealth.ok) (($frontendHealth | ConvertTo-Json -Compress))

$appsHealth = $null
try {
  $body = @{action='health'} | ConvertTo-Json -Compress
  $appsHealth = Invoke-RestMethod -Uri $AppsScriptUrl -Method Post -ContentType 'text/plain;charset=utf-8' -Body $body -TimeoutSec 15
} catch {
  try { $appsHealth = Invoke-RestMethod -Uri $AppsScriptUrl -Method Get -TimeoutSec 15 }
  catch { $appsHealth=[ordered]@{ok=$false;error=$_.Exception.Message} }
}
Add-Check $checks 'Apps Script health' ([bool]$appsHealth.ok) (($appsHealth | ConvertTo-Json -Depth 6 -Compress))

$notebook = $knownResults | Where-Object { $_.name -eq 'NotebookLM WebApp Bridge' } | Select-Object -First 1
$ping = [ordered]@{ok=$false;error='NOT_ATTEMPTED'}
if ($chromePath -and $notebook -and $notebook.found) {
  try { $ping = Invoke-ExtensionPing -ChromePath $chromePath -ExtensionId ([string]$notebook.id) -TimeoutSeconds $TimeoutSeconds }
  catch { $ping=[ordered]@{ok=$false;error=$_.Exception.Message} }
}
Add-Check $checks 'NotebookLM extension external PING' ([bool]$ping.ok) (($ping | ConvertTo-Json -Depth 8 -Compress))

$localBridge = $knownResults | Where-Object { $_.name -eq 'Google AI Local Bridge v1' } | Select-Object -First 1
$routingMode = if ([bool]$ping.ok -and [bool]$appsHealth.ok) {
  if ($localBridge -and $localBridge.found) { 'NOTEBOOKLM_FALLBACK_READY_LOCAL_BRIDGE_PRESENT' }
  else { 'NOTEBOOKLM_FALLBACK_READY_LOCAL_BRIDGE_MISSING' }
} else { 'BLOCKED_NEEDS_REPAIR' }

$report = [ordered]@{
  ok = ([bool]$ping.ok -and [bool]$appsHealth.ok)
  version = $Version
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  computerName = $env:COMPUTERNAME
  chromePath = $chromePath
  routingMode = $routingMode
  extensions = $knownResults
  checks = $checks
  frontendHealth = $frontendHealth
  appsScriptHealth = $appsHealth
  notebookExtensionPing = $ping
  policy = [ordered]@{
    noNewOAuth = $true
    noNewAppsScriptProject = $true
    noNewDeployment = $true
    noChromeExtensionDeletion = $true
    existingAuthorizationOnly = $true
  }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Log "DONE ok=$($report.ok) routing=$routingMode report=$ReportPath"

[ordered]@{
  ok=$report.ok; action='CHROME_FLOW_HEALTH'; version=$Version; routingMode=$routingMode;
  reportPath=$ReportPath; notebookPingOk=[bool]$ping.ok; appsScriptHealthOk=[bool]$appsHealth.ok;
  at=(Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 8
if ($report.ok) { exit 0 } else { exit 2 }
