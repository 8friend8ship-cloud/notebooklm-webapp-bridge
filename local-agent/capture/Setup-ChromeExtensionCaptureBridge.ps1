param(
  [switch]$SmokeOnly,
  [switch]$FlowBridgeConnectSmoke,
  [switch]$FlowExtensionInspect,
  [switch]$FlowExactWorkspaceProbe,
  [switch]$NotebookLMTabPrecheck,
  [string]$FlowSmokeTaskId = '',
  [int]$FlowDebugPort = 9224,
  [int]$FlowExactTimeoutSeconds = 45,
  [string]$FlowExactTargetUrl = 'https://labs.google/fx/tools/flow',
  [int]$NotebookLMDebugPort = 9223,
  [string]$ManagerRef = 'main',
  [string]$LocalInboxRoot = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX',
  [string]$CentralRootOverride = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$ManagerExpected = '76a9718b30d1432829ea7c0f2e6af95ea6942ab8'
$FlowHelperExpected = '43df9a311505abb0cb5e9b5a4aae2ce0bb881da0'
$FlowAutopilotV2Expected = '02a8d4b57c90d96e5bde6521b2e2f939decd60e7'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent\capture'
$Manager = Join-Path $InstallRoot 'ManageChromeExtensionArtifacts.ps1'
$Wrapper = Join-Path $InstallRoot 'Reconcile-AllManagedChromeArtifacts.ps1'
$TaskName = 'HomeDesign-CaptureBridge-ManagedChrome-Reconcile'
$Services = @('NotebookLM','Flow','AIStudio','GoogleAI','FrontQA','SketchUp')

function GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
  $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create()
  try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}
function Sha256([string]$Path){$h=[Security.Cryptography.SHA256]::Create();try{$fs=[IO.File]::OpenRead($Path);try{return (($h.ComputeHash($fs)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$fs.Dispose()}}finally{$h.Dispose()}}
function Find-FlowExtensionLocal {
  $base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
  foreach($p in @(
    (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0\flow-agent-bridge-v0.1.0'),
    (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0'),
    (Join-Path $base 'Extension\Flow-Agent-Bridge'),
    (Join-Path $base 'Extension\Google-AI-Local-Bridge-Flow')
  )){if(Test-Path -LiteralPath (Join-Path $p 'manifest.json') -PathType Leaf){return $p}}
  return ''
}

if($NotebookLMTabPrecheck){
  $result=[ordered]@{ok=$false;action='NOTEBOOKLM_DEDICATED_CHROME_TAB_PRECHECK';cdpReady=$false;debugPort=$NotebookLMDebugPort;controlCenterPresent=$false;notebookTabPresent=$false;notebookResultPagePresent=$false;controlCenterTabs=@();notebookTabs=@();allPages=@();normalChromeMutated=$false;downloadClicked=$false;readOnly=$true;error='';at=(Get-Date).ToString('o')}
  try{
    $version=Invoke-RestMethod -Uri ("http://127.0.0.1:$NotebookLMDebugPort/json/version") -TimeoutSec 3
    $result.cdpReady=[bool]$version.webSocketDebuggerUrl
    if(-not $result.cdpReady){throw 'DEDICATED_CHROME_CDP_NOT_READY'}
    $targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$NotebookLMDebugPort/json/list") -TimeoutSec 4)
    $pages=@($targets|Where-Object{$_.type -eq 'page'}|ForEach-Object{[ordered]@{title=[string]$_.title;url=[string]$_.url;id=[string]$_.id}})
    $control=@($pages|Where-Object{$_.url -like 'https://notebooklm-webapp-bridge.vercel.app/*'})
    $notebook=@($pages|Where-Object{$_.url -match '^https://(notebook|notebooklm)\.google\.com/'})
    $result.allPages=$pages
    $result.controlCenterTabs=$control
    $result.notebookTabs=$notebook
    $result.controlCenterPresent=(@($control).Count -gt 0)
    $result.notebookTabPresent=(@($notebook).Count -gt 0)
    $result.notebookResultPagePresent=(@($notebook|Where-Object{$_.url -match '/notebook/'}).Count -gt 0)
    $result.ok=[bool]($result.controlCenterPresent -and $result.notebookResultPagePresent)
    if(-not $result.ok){$result.error='PRECHECK_REQUIRES_CONTROL_CENTER_AND_NOTEBOOK_RESULT_PAGE'}
  }catch{$result.error=$_.Exception.Message}
  $result.completedAt=(Get-Date).ToString('o')
  $result|ConvertTo-Json -Depth 20 -Compress
  if($result.ok){exit 0}else{exit 2}
}

if($FlowExtensionInspect){
  $ext=Find-FlowExtensionLocal;if(-not $ext){throw 'FLOW_EXTENSION_PATH_NOT_FOUND'}
  $manifestPath=Join-Path $ext 'manifest.json';$manifestRaw=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8;$manifest=$manifestRaw|ConvertFrom-Json
  $files=@('manifest.json','content.js','popup.html','popup.js')
  $inventory=@()
  foreach($name in $files){$p=Join-Path $ext $name;if(Test-Path -LiteralPath $p -PathType Leaf){$raw=Get-Content -LiteralPath $p -Raw -Encoding UTF8;$inventory += [ordered]@{name=$name;path=$p;bytes=[int64](Get-Item -LiteralPath $p).Length;sha256=(Sha256 $p);text=$(if($raw.Length -le 20000){$raw}else{$raw.Substring(0,20000)})}}}
  $extraScripts=@()
  $popup=Join-Path $ext 'popup.html'
  if(Test-Path -LiteralPath $popup -PathType Leaf){$html=Get-Content -LiteralPath $popup -Raw -Encoding UTF8;foreach($m in [regex]::Matches($html,'<script[^>]+src=["'']([^"'']+)["'']',[Text.RegularExpressions.RegexOptions]::IgnoreCase)){ $name=[string]$m.Groups[1].Value;if($name -and $name -notmatch '^(https?:|//)'){$p=Join-Path $ext $name;if((Test-Path -LiteralPath $p -PathType Leaf) -and -not($files -contains $name)){$raw=Get-Content -LiteralPath $p -Raw -Encoding UTF8;$extraScripts += [ordered]@{name=$name;path=$p;bytes=[int64](Get-Item -LiteralPath $p).Length;sha256=(Sha256 $p);text=$(if($raw.Length -le 20000){$raw}else{$raw.Substring(0,20000)})}}}}
  }
  [ordered]@{ok=$true;action='FLOW_EXTENSION_SOURCE_INSPECT';extensionPath=$ext;name=[string]$manifest.name;version=[string]$manifest.version;manifestVersion=[int]$manifest.manifest_version;background=$manifest.background;contentScripts=$manifest.content_scripts;actionConfig=$manifest.action;permissions=$manifest.permissions;hostPermissions=$manifest.host_permissions;files=$inventory;extraScripts=$extraScripts;readOnly=$true;chromeStarted=$false;creditSpend=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 40 -Compress
  exit 0
}

if($FlowExactWorkspaceProbe){
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $v2=Join-Path $InstallRoot 'ManagedExtensionAutopilotV2.ps1'
  $tmpV2=$v2+'.download'
  $v2Raw='https://raw.githubusercontent.com/'+$Repo+'/refs/heads/main/local-agent/governor/ManagedExtensionAutopilotV2.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $v2Raw -OutFile $tmpV2 -TimeoutSec 20
  $v2Actual=(GitBlobSha1 $tmpV2).ToLowerInvariant()
  if($v2Actual -ne $FlowAutopilotV2Expected){
    Remove-Item -LiteralPath $tmpV2 -Force -ErrorAction SilentlyContinue
    throw ('FLOW_AUTOPILOT_V2_SHA_MISMATCH:actual={0}:expected={1}' -f $v2Actual,$FlowAutopilotV2Expected)
  }
  Move-Item -LiteralPath $tmpV2 -Destination $v2 -Force
  $probeArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$v2,'-Mode','ProbeExact','-Service','FLOW','-TargetUrl',$FlowExactTargetUrl,'-ExpectedUrlPattern','labs\.google/.*/flow|labs\.google/fx/tools/flow','-ExpectedExtensionId','lgedgmpcikglaajhfclcihicgafimlna','-RemoteDebuggingPort',[string]$FlowDebugPort,'-TimeoutSeconds',[string]$FlowExactTimeoutSeconds,'-RestartDedicatedChrome','-ProbeInput')
  $oldEap=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try{$probeOut=& powershell.exe @probeArgs 2>&1;$probeRc=$LASTEXITCODE}finally{$ErrorActionPreference=$oldEap}
  $probeText=($probeOut|Out-String).Trim();$probe=$null
  try{$probe=(($probeText -split "`r?`n")[-1]|ConvertFrom-Json)}catch{}
  [ordered]@{
    ok=[bool]($probeRc -eq 0 -and $probe -and $probe.ok)
    action='FLOW_VISIBLE_EXACT_WORKSPACE_PROBE_WRAPPER'
    helperExit=$probeRc
    helperSha=$v2Actual
    targetUrl=$FlowExactTargetUrl
    debugPort=$FlowDebugPort
    inputProbe=$true
    generateClicked=$false
    creditSpend=$false
    oauthChanged=$false
    chromeSettingsChanged=$false
    result=$probe
    raw=$probeText
    at=(Get-Date).ToString('o')
  }|ConvertTo-Json -Depth 70 -Compress
  exit 0
}

if ($FlowBridgeConnectSmoke) {
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $helper = Join-Path $InstallRoot 'RunFlowBridgeConnectSmoke.ps1'
  $tmpHelper = $helper + '.download'
  $helperRaw = 'https://raw.githubusercontent.com/' + $Repo + '/refs/heads/main/local-agent/governor/RunFlowBridgeConnectSmoke.ps1?hdcb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $helperRaw -OutFile $tmpHelper -TimeoutSec 20
  $helperActual = (GitBlobSha1 $tmpHelper).ToLowerInvariant()
  if ($helperActual -ne $FlowHelperExpected) {
    Remove-Item -LiteralPath $tmpHelper -Force -ErrorAction SilentlyContinue
    throw ('FLOW_HELPER_SHA_MISMATCH:actual={0}:expected={1}' -f $helperActual,$FlowHelperExpected)
  }
  Move-Item -LiteralPath $tmpHelper -Destination $helper -Force
  $helperArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper,'-DebugPort',[string]$FlowDebugPort)
  if ($FlowSmokeTaskId) { $helperArgs += @('-TaskId',$FlowSmokeTaskId) }
  if ($CentralRootOverride) { $helperArgs += @('-CentralRootOverride',$CentralRootOverride) }
  $oldEap=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try { $helperOut = & powershell.exe @helperArgs 2>&1; $helperRc = $LASTEXITCODE } finally { $ErrorActionPreference=$oldEap }
  $helperText = ($helperOut | Out-String).Trim()
  [ordered]@{
    ok = ($helperRc -eq 0)
    action = 'FLOW_BRIDGE_CONNECT_PROBE_WRAPPER'
    helperExit = $helperRc
    helperSha = $helperActual
    helperOutput = $helperText
    diagnosticOnly = $true
    generateClicked = $false
    creditSpend = $false
    at = (Get-Date).ToString('o')
  } | ConvertTo-Json -Depth 50 -Compress
  exit 0
}

function Find-CentralRoot {
  if ($CentralRootOverride) {
    if (Test-Path -LiteralPath $CentralRootOverride -PathType Container) { return (Resolve-Path -LiteralPath $CentralRootOverride).Path }
    throw ('CENTRAL_ROOT_OVERRIDE_NOT_FOUND:{0}' -f $CentralRootOverride)
  }
  $target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    $root = [string]$drive.Root
    if (-not $root) { continue }
    foreach ($candidate in @(
      (Join-Path $root $target),
      (Join-Path $root ('My Drive\' + $target)),
      (Join-Path $root ($myDriveKo + '\' + $target)),
      (Join-Path $root ('Google Drive\' + $target))
    )) {
      if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
  }
  throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'
}

New-Item -ItemType Directory -Force -Path $InstallRoot,$LocalInboxRoot | Out-Null
$CentralRoot = Find-CentralRoot
foreach ($service in $Services) {
  New-Item -ItemType Directory -Force -Path (Join-Path $LocalInboxRoot $service) | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path $CentralRoot 'CaptureBridge\INBOX') $service) | Out-Null
}

$raw = 'https://raw.githubusercontent.com/' + $Repo + '/refs/heads/' + $ManagerRef + '/local-agent/capture/ManageChromeExtensionArtifacts.ps1?hdcb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$tmp = $Manager + '.download'
Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $tmp -TimeoutSec 20
$actual = (GitBlobSha1 $tmp).ToLowerInvariant()
if ($actual -ne $ManagerExpected) {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  throw ('CAPTURE_MANAGER_SHA_MISMATCH:actual={0}:expected={1}' -f $actual,$ManagerExpected)
}
Move-Item -LiteralPath $tmp -Destination $Manager -Force

$escapedManager = $Manager.Replace("'","''")
$escapedLocal = $LocalInboxRoot.Replace("'","''")
$wrapperBody = @"
`$ErrorActionPreference='Continue'
`$Manager='$escapedManager'
`$LocalInboxRoot='$escapedLocal'
`$known=@('NotebookLM','Flow','AIStudio','GoogleAI','FrontQA','SketchUp')
`$discovered=@(Get-ChildItem -LiteralPath `$LocalInboxRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { `$_.Name })
`$services=@(`$known + `$discovered | Where-Object { `$_ -match '^[A-Za-z0-9_.-]{1,64}$' } | Sort-Object -Unique)
foreach(`$service in `$services){
  try { & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `$Manager -ServiceKey `$service -ReconcileOnly -LocalInboxRoot `$LocalInboxRoot | Out-Null } catch {}
}
"@
Set-Content -LiteralPath $Wrapper -Value $wrapperBody -Encoding UTF8

$scheduled = $false
if (-not $SmokeOnly) {
  $tr = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Wrapper + '"'
  & schtasks.exe /Create /F /SC MINUTE /MO 5 /TN $TaskName /TR $tr | Out-Null
  if ($LASTEXITCODE -ne 0) { throw ('CAPTURE_SCHEDULED_TASK_CREATE_FAILED:{0}' -f $LASTEXITCODE) }
  $scheduled = $true
}

$smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ('CaptureBridgeManagedChromeSmoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
$smoke = @()
foreach ($service in $Services) {
  if ($service -eq 'Flow') {
    $src = Join-Path $smokeRoot 'flow-smoke.png'
    [IO.File]::WriteAllBytes($src,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZK1sAAAAASUVORK5CYII='))
  } else {
    $src = Join-Path $smokeRoot (($service.ToLowerInvariant()) + '-smoke.txt')
    Set-Content -LiteralPath $src -Value ('MANAGED_CHROME_CAPTURE_SMOKE ' + $service + ' ' + (Get-Date).ToString('o')) -Encoding UTF8
  }
  $args = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Manager,'-ServiceKey',$service,'-SourcePath',$src,'-TaskId',('SETUP_SMOKE_' + $service),'-LocalInboxRoot',$LocalInboxRoot)
  if ($CentralRootOverride) { $args += @('-CentralRootOverride',$CentralRoot) }
  $rawResult = & powershell.exe @args
  if ($LASTEXITCODE -ne 0) { throw ('CAPTURE_SMOKE_FAILED:{0}' -f $service) }
  $parsed = ($rawResult | Select-Object -Last 1) | ConvertFrom-Json
  if (-not [bool]$parsed.ok -or [int]$parsed.processedCount -lt 1 -or [bool]$parsed.genericDownloadsScan) {
    throw ('CAPTURE_SMOKE_CONTRACT_FAILED:{0}' -f $service)
  }
  $first = @($parsed.results)[0]
  if (-not [bool]$first.originalPreserved -or -not (Test-Path -LiteralPath ([string]$first.drivePath) -PathType Leaf)) {
    throw ('CAPTURE_SMOKE_COPY_VERIFY_FAILED:{0}' -f $service)
  }
  $smoke += [ordered]@{service=$service;ok=$true;drivePath=[string]$first.drivePath;bytes=[int64]$first.bytes;sha256=[string]$first.sha256}
}

$futureService = 'FutureManagedExtension'
$futureSrc = Join-Path $smokeRoot 'future-managed-smoke.txt'
Set-Content -LiteralPath $futureSrc -Value ('MANAGED_CHROME_CAPTURE_SMOKE ' + $futureService + ' ' + (Get-Date).ToString('o')) -Encoding UTF8
$futureArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Manager,'-ServiceKey',$futureService,'-SourcePath',$futureSrc,'-TaskId','SETUP_SMOKE_FUTURE_MANAGED','-LocalInboxRoot',$LocalInboxRoot)
if ($CentralRootOverride) { $futureArgs += @('-CentralRootOverride',$CentralRoot) }
$futureRaw = & powershell.exe @futureArgs
if ($LASTEXITCODE -ne 0) { throw 'CAPTURE_SMOKE_FAILED:FUTURE_MANAGED' }
$futureParsed = ($futureRaw | Select-Object -Last 1) | ConvertFrom-Json
if (-not [bool]$futureParsed.ok -or [int]$futureParsed.processedCount -lt 1 -or [bool]$futureParsed.knownProfile -or [bool]$futureParsed.genericDownloadsScan) {
  throw 'CAPTURE_SMOKE_CONTRACT_FAILED:FUTURE_MANAGED'
}
$futureFirst = @($futureParsed.results)[0]
$smoke += [ordered]@{service=$futureService;ok=$true;drivePath=[string]$futureFirst.drivePath;bytes=[int64]$futureFirst.bytes;sha256=[string]$futureFirst.sha256;knownProfile=$false}

$result = [ordered]@{
  ok = $true
  action = 'SETUP_MANAGED_CHROME_CAPTUREBRIDGE'
  services = $Services
  futureManagedAdapter = $futureService
  manager = $Manager
  managerRef = $ManagerRef
  managerSha = $actual
  localInboxRoot = $LocalInboxRoot
  centralRoot = $CentralRoot
  scheduledTask = $TaskName
  scheduled = $scheduled
  smokeOnly = [bool]$SmokeOnly
  dynamicInboxDiscovery = $true
  genericDownloadsSync = $false
  copyOnly = $true
  smoke = $smoke
  at = (Get-Date).ToString('o')
}
$result | ConvertTo-Json -Depth 10 -Compress