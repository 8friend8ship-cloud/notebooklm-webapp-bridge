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
  $tmpHelper = $helper + '.embedded'
  $payload='cGFyYW0oCiAgW3N0cmluZ10kVGFza0lkPScnLAogIFtzdHJpbmddJENlbnRyYWxSb290T3ZlcnJpZGU9JycsCiAgW2ludF0kRGVidWdQb3J0PTkyMjQKKQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTdG9wJwokUHJvZ3Jlc3NQcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJwoKJEJhc2U9Sm9pbi1QYXRoICRlbnY6TE9DQUxBUFBEQVRBICdIb21lRGVzaWduQXV0b21hdGlvblY3JwokVXNlckRhdGE9Sm9pbi1QYXRoICRCYXNlICdDaHJvbWVVc2VyRGF0YScKJENmdFJvb3Q9Sm9pbi1QYXRoICRCYXNlICdDaHJvbWVGb3JUZXN0aW5nJwokTm90ZWJvb2tFeHRlbnNpb249Sm9pbi1QYXRoICRCYXNlICdFeHRlbnNpb25cTm90ZWJvb2tMTS1XZWJBcHAtQnJpZGdlJwokTm90ZWJvb2tGcm9udD0naHR0cHM6Ly9ub3RlYm9va2xtLXdlYmFwcC1icmlkZ2UudmVyY2VsLmFwcC8nCiRGbG93VXJsPSdodHRwczovL2xhYnMuZ29vZ2xlL2Z4L3Rvb2xzL2Zsb3cnCiRFeHBlY3RlZEZsb3dFeHRlbnNpb25JZD0nbGdlZGdtcGNpa2dsYWFqaGZjbGNpaGljZ2FmaW1sbmEnCgpmdW5jdGlvbiBTYWZlLVRhc2tJZChbc3RyaW5nXSRWYWx1ZSl7aWYoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkVmFsdWUpKXtyZXR1cm4gKCdGTE9XX0JSSURHRV9DT05ORUNUXycrKEdldC1EYXRlIC1Gb3JtYXQgJ3l5eXlNTWRkX0hIbW1zcycpKX07aWYoJFZhbHVlIC1ub3RtYXRjaCAnXltBLVphLXowLTlfLi1dezEsMTgwfSQnKXt0aHJvdyAnVU5TQUZFX1RBU0tfSUQnfTtyZXR1cm4gJFZhbHVlfQpmdW5jdGlvbiBXcml0ZS1Kc29uQXRvbWljKFtzdHJpbmddJFBhdGgsJE9iamVjdCl7JHBhcmVudD1TcGxpdC1QYXRoIC1QYXJlbnQgJFBhdGg7aWYoLW5vdChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwYXJlbnQpKXtOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkcGFyZW50fE91dC1OdWxsfTskdG1wPSRQYXRoKycudG1wJzskT2JqZWN0fENvbnZlcnRUby1Kc29uIC1EZXB0aCA2MHxTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHRtcCAtRW5jb2RpbmcgVVRGODtNb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRQYXRoIC1Gb3JjZX0KZnVuY3Rpb24gRmluZC1DZW50cmFsUm9vdCB7CiAgaWYoJENlbnRyYWxSb290T3ZlcnJpZGUgLWFuZCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkQ2VudHJhbFJvb3RPdmVycmlkZSAtUGF0aFR5cGUgQ29udGFpbmVyKSl7cmV0dXJuICRDZW50cmFsUm9vdE92ZXJyaWRlfQogICR0YXJnZXQ9W1RleHQuRW5jb2RpbmddOjpVVEY4LkdldFN0cmluZyhbQ29udmVydF06OkZyb21CYXNlNjRTdHJpbmcoJ01EQmY3S1NSN0pXWjdKZVE3SjIwN0tDRTdZcTQnKSkKICAkbXlEcml2ZUtvPVtUZXh0LkVuY29kaW5nXTo6VVRGOC5HZXRTdHJpbmcoW0NvbnZlcnRdOjpGcm9tQmFzZTY0U3RyaW5nKCc2NEswSU91VG5PdWR2T3lkdE91NGpBPT0nKSkKICBmb3JlYWNoKCRkcml2ZSBpbiBAKEdldC1QU0RyaXZlIC1QU1Byb3ZpZGVyIEZpbGVTeXN0ZW0gLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKXsKICAgICRyPVtzdHJpbmddJGRyaXZlLlJvb3Q7aWYoLW5vdCAkcil7Y29udGludWV9CiAgICBmb3JlYWNoKCRjYW5kaWRhdGUgaW4gQCgoSm9pbi1QYXRoICRyICR0YXJnZXQpLChKb2luLVBhdGggKEpvaW4tUGF0aCAkciAnTXkgRHJpdmUnKSAkdGFyZ2V0KSwoSm9pbi1QYXRoIChKb2luLVBhdGggJHIgJG15RHJpdmVLbykgJHRhcmdldCksKEpvaW4tUGF0aCAoSm9pbi1QYXRoICRyICdHb29nbGUgRHJpdmUnKSAkdGFyZ2V0KSkpe3RyeXtpZihUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRjYW5kaWRhdGUgLVBhdGhUeXBlIENvbnRhaW5lcil7cmV0dXJuICRjYW5kaWRhdGV9fWNhdGNoe319CiAgfQogIHJldHVybiAnJwp9CmZ1bmN0aW9uIEZpbmQtQ2Z0Q2hyb21lIHtyZXR1cm4gR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJENmdFJvb3QgLVJlY3Vyc2UgLUZpbHRlciBjaHJvbWUuZXhlIC1GaWxlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlfFNvcnQtT2JqZWN0IEZ1bGxOYW1lIC1EZXNjZW5kaW5nfFNlbGVjdC1PYmplY3QgLUZpcnN0IDF9CmZ1bmN0aW9uIERlZGljYXRlZC1Qcm9jcyB7dHJ5e3JldHVybiBAKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWU9J2Nocm9tZS5leGUnIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZXxXaGVyZS1PYmplY3R7JF8uQ29tbWFuZExpbmUgLWFuZCAoW3N0cmluZ10kXy5Db21tYW5kTGluZSkuQ29udGFpbnMoJFVzZXJEYXRhKX0pfWNhdGNoe3JldHVybiBAKCl9fQpmdW5jdGlvbiBOb3JtYWwtUHJvY3Mge3RyeXtyZXR1cm4gQChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyAtRmlsdGVyICJOYW1lPSdjaHJvbWUuZXhlJyIgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWV8V2hlcmUtT2JqZWN0ey1ub3QgJF8uQ29tbWFuZExpbmUgLW9yIC1ub3QgKFtzdHJpbmddJF8uQ29tbWFuZExpbmUpLkNvbnRhaW5zKCRVc2VyRGF0YSl9KX1jYXRjaHtyZXR1cm4gQCgpfX0KZnVuY3Rpb24gTm9ybWFsLUJyb3dzZXJSb290cyB7cmV0dXJuIEAoTm9ybWFsLVByb2NzfFdoZXJlLU9iamVjdHstbm90ICRfLkNvbW1hbmRMaW5lIC1vciAoW3N0cmluZ10kXy5Db21tYW5kTGluZSkgLW5vdG1hdGNoICcoP2kpKF58XHMpLS10eXBlPSd9KX0KZnVuY3Rpb24gU3RvcC1EZWRpY2F0ZWQgeyRrPUAoKTtmb3JlYWNoKCRwIGluIEAoRGVkaWNhdGVkLVByb2NzKSl7dHJ5eyYgdGFza2tpbGwuZXhlIC9QSUQgKFtpbnRdJHAuUHJvY2Vzc0lkKSAvVCAvRiAyPiRudWxsfE91dC1OdWxsOyRrICs9IFtpbnRdJHAuUHJvY2Vzc0lkfWNhdGNoe319O1N0YXJ0LVNsZWVwIC1TZWNvbmRzIDI7cmV0dXJuIEAoJGspfQpmdW5jdGlvbiBGaW5kLUZsb3dFeHRlbnNpb24gewogICRjYW5kaWRhdGVzPUAoCiAgICAoSm9pbi1QYXRoICRlbnY6VVNFUlBST0ZJTEUgJ0Rvd25sb2Fkc1xmbG93LWFnZW50LWJyaWRnZS12MC4xLjBcZmxvdy1hZ2VudC1icmlkZ2UtdjAuMS4wJyksCiAgICAoSm9pbi1QYXRoICRlbnY6VVNFUlBST0ZJTEUgJ0Rvd25sb2Fkc1xmbG93LWFnZW50LWJyaWRnZS12MC4xLjAnKSwKICAgIChKb2luLVBhdGggJEJhc2UgJ0V4dGVuc2lvblxGbG93LUFnZW50LUJyaWRnZScpLAogICAgKEpvaW4tUGF0aCAkQmFzZSAnRXh0ZW5zaW9uXEdvb2dsZS1BSS1Mb2NhbC1CcmlkZ2UtRmxvdycpCiAgKQogIGZvcmVhY2goJHAgaW4gJGNhbmRpZGF0ZXMpe3RyeXtpZihUZXN0LVBhdGggLUxpdGVyYWxQYXRoIChKb2luLVBhdGggJHAgJ21hbmlmZXN0Lmpzb24nKSAtUGF0aFR5cGUgTGVhZil7cmV0dXJuICRwfX1jYXRjaHt9fQogIHJldHVybiAnJwp9CmZ1bmN0aW9uIFJlc3RvcmUtTm90ZWJvb2sgewogIHRyeXsKICAgIFN0b3AtRGVkaWNhdGVkfE91dC1OdWxsCiAgICAkY2hyb21lPUZpbmQtQ2Z0Q2hyb21lO2lmKC1ub3QgJGNocm9tZSl7cmV0dXJuICRmYWxzZX0KICAgICRhcmdzPUAoIi0tdXNlci1kYXRhLWRpcj0kVXNlckRhdGEiLCctLXByb2ZpbGUtZGlyZWN0b3J5PURlZmF1bHQnLCctLW5ldy13aW5kb3cnLCctLW5vLWZpcnN0LXJ1bicsJy0tbm8tZGVmYXVsdC1icm93c2VyLWNoZWNrJywnLS1kaXNhYmxlLXNlc3Npb24tY3Jhc2hlZC1idWJibGUnKQogICAgaWYoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICROb3RlYm9va0V4dGVuc2lvbiAnbWFuaWZlc3QuanNvbicpIC1QYXRoVHlwZSBMZWFmKXskYXJncys9KCItLWxvYWQtZXh0ZW5zaW9uPSROb3RlYm9va0V4dGVuc2lvbiIpfQogICAgJGFyZ3MrPSROb3RlYm9va0Zyb250CiAgICBTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAkY2hyb21lLkZ1bGxOYW1lIC1Bcmd1bWVudExpc3QgJGFyZ3MgLVdvcmtpbmdEaXJlY3RvcnkgJGNocm9tZS5EaXJlY3RvcnkuRnVsbE5hbWV8T3V0LU51bGwKICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDIKICAgIHJldHVybiAoQChEZWRpY2F0ZWQtUHJvY3MpLkNvdW50IC1ndCAwKQogIH1jYXRjaHtyZXR1cm4gJGZhbHNlfQp9CmZ1bmN0aW9uIFJlYWQtVGV4dFNhZmUoW3N0cmluZ10kUGF0aCxbaW50XSRNYXg9MTIwMDApe2lmKC1ub3QoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkUGF0aCAtUGF0aFR5cGUgTGVhZikpe3JldHVybiAnJ307dHJ5eyR0PUdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkUGF0aCAtUmF3IC1FbmNvZGluZyBVVEY4O2lmKCR0Lkxlbmd0aCAtZ3QgJE1heCl7cmV0dXJuICR0LlN1YnN0cmluZygwLCRNYXgpfTtyZXR1cm4gJHR9Y2F0Y2h7cmV0dXJuICcnfX0KZnVuY3Rpb24gSW52b2tlLURlZXBQcm9iZShbc3RyaW5nXSRCcm93c2VyV3MsW3N0cmluZ10kUGFnZVdzLFtzdHJpbmddJFNlbnRpbmVsKXsKICAkbm9kZT1HZXQtQ29tbWFuZCBub2RlLmV4ZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZTtpZigtbm90ICRub2RlKXskbm9kZT1HZXQtQ29tbWFuZCBub2RlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlfTtpZigtbm90ICRub2RlKXtyZXR1cm4gW29yZGVyZWRdQHtvaz0kZmFsc2U7c3RhZ2U9J05PREVfTk9UX0ZPVU5EJ319CiAgJGpzPUpvaW4tUGF0aCAkZW52OlRFTVAgKCdmbG93LWJyaWRnZS1kZWVwLXByb2JlLScrW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSsnLm1qcycpCiAgJGNvZGU9QCcKY29uc3QgYnJvd3NlcldzPXByb2Nlc3MuYXJndlsyXSwgcGFnZVdzPXByb2Nlc3MuYXJndlszXSwgc2VudGluZWw9cHJvY2Vzcy5hcmd2WzRdLCBleHBlY3RlZElkPXByb2Nlc3MuYXJndls1XTsKZnVuY3Rpb24gY29ubmVjdCh1cmwpe3JldHVybiBuZXcgUHJvbWlzZSgocmVzb2x2ZSxyZWplY3QpPT57Y29uc3Qgd3M9bmV3IFdlYlNvY2tldCh1cmwpO2xldCBzZXE9MDtjb25zdCBwZW5kaW5nPW5ldyBNYXAoKTt3cy5vbm9wZW49KCk9PnJlc29sdmUoe3dzLHNlbmQ6KG1ldGhvZCxwYXJhbXM9e30pPT5uZXcgUHJvbWlzZSgocmVzLHJlaik9Pntjb25zdCBpZD0rK3NlcTtwZW5kaW5nLnNldChpZCx7cmVzLHJlan0pO3dzLnNlbmQoSlNPTi5zdHJpbmdpZnkoe2lkLG1ldGhvZCxwYXJhbXN9KSk7fSl9KTt3cy5vbmVycm9yPXJlamVjdDt3cy5vbm1lc3NhZ2U9ZT0+e2xldCBtO3RyeXttPUpTT04ucGFyc2UoZS5kYXRhKX1jYXRjaHtyZXR1cm59O2lmKG0uaWQmJnBlbmRpbmcuaGFzKG0uaWQpKXtjb25zdCBwPXBlbmRpbmcuZ2V0KG0uaWQpO3BlbmRpbmcuZGVsZXRlKG0uaWQpO20uZXJyb3I/cC5yZWoobmV3IEVycm9yKEpTT04uc3RyaW5naWZ5KG0uZXJyb3IpKSk6cC5yZXMobS5yZXN1bHQpO319O30pO30KY29uc3QgYj1hd2FpdCBjb25uZWN0KGJyb3dzZXJXcyk7Y29uc3QgYWxsPWF3YWl0IGIuc2VuZCgnVGFyZ2V0LmdldFRhcmdldHMnKTsKY29uc3QgZXh0PShhbGwudGFyZ2V0SW5mb3N8fFtdKS5maWx0ZXIodD0+KHQudXJsfHwnJykuc3RhcnRzV2l0aCgnY2hyb21lLWV4dGVuc2lvbjovLycpKTsKY29uc3QgZXhwZWN0ZWQ9ZXh0LmZpbHRlcih0PT4odC51cmx8fCcnKS5zdGFydHNXaXRoKCdjaHJvbWUtZXh0ZW5zaW9uOi8vJytleHBlY3RlZElkKycvJykpOwpjb25zdCBwPWF3YWl0IGNvbm5lY3QocGFnZVdzKTtjb25zdCBzZW50aW5lbExpdD1KU09OLnN0cmluZ2lmeShzZW50aW5lbCk7CmNvbnN0IGJhc2VFeHByPWAoKCk9Pntjb25zdCByb290cz1bZG9jdW1lbnRdLHE9W2RvY3VtZW50XSxzZWVuPW5ldyBTZXQocSk7d2hpbGUocS5sZW5ndGgpe2NvbnN0IHI9cS5zaGlmdCgpO2xldCBhPVtdO3RyeXthPVsuLi5yLnF1ZXJ5U2VsZWN0b3JBbGwoJyonKV19Y2F0Y2h7fTtmb3IoY29uc3QgZSBvZiBhKXtpZihlLnNoYWRvd1Jvb3QmJiFzZWVuLmhhcyhlLnNoYWRvd1Jvb3QpKXtzZWVuLmFkZChlLnNoYWRvd1Jvb3QpO3Jvb3RzLnB1c2goZS5zaGFkb3dSb290KTtxLnB1c2goZS5zaGFkb3dSb290KX19fWNvbnN0IHZpcz1lPT57aWYoIWUpcmV0dXJuIGZhbHNlO2NvbnN0IHM9Z2V0Q29tcHV0ZWRTdHlsZShlKSxyPWUuZ2V0Qm91bmRpbmdDbGllbnRSZWN0KCk7cmV0dXJuIHMuZGlzcGxheSE9PSdub25lJyYmcy52aXNpYmlsaXR5IT09J2hpZGRlbicmJk51bWJlcihzLm9wYWNpdHkpIT09MCYmci53aWR0aD4xOCYmci5oZWlnaHQ+MTgmJnIuYm90dG9tPj0wJiZyLnJpZ2h0Pj0wfTtjb25zdCBkZXNjPWU9PltlLmdldEF0dHJpYnV0ZT8uKCdhcmlhLWxhYmVsJyksZS5nZXRBdHRyaWJ1dGU/LigncGxhY2Vob2xkZXInKSxlLmdldEF0dHJpYnV0ZT8uKCdkYXRhLXBsYWNlaG9sZGVyJyksZS5nZXRBdHRyaWJ1dGU/LigndGl0bGUnKSxlLmdldEF0dHJpYnV0ZT8uKCduYW1lJyksZS5pZCxlLnRleHRDb250ZW50LGUudmFsdWVdLmZpbHRlcihCb29sZWFuKS5qb2luKCcgJykucmVwbGFjZSgvXFxzKy9nLCcgJykudHJpbSgpO2xldCBpbnB1dHM9W107Zm9yKGNvbnN0IHIgb2Ygcm9vdHMpe3RyeXtpbnB1dHMucHVzaCguLi5yLnF1ZXJ5U2VsZWN0b3JBbGwoJ3RleHRhcmVhLGlucHV0W3R5cGU9dGV4dF0saW5wdXQ6bm90KFt0eXBlXSksW2NvbnRlbnRlZGl0YWJsZT10cnVlXSxbcm9sZT10ZXh0Ym94XScpKX1jYXRjaHt9fWxldCBiZXN0PW51bGwsc2NvcmU9LTk5OTk7Zm9yKGNvbnN0IGUgb2YgWy4uLm5ldyBTZXQoaW5wdXRzKV0pe2lmKCF2aXMoZSl8fGUuZGlzYWJsZWR8fGUucmVhZE9ubHkpY29udGludWU7Y29uc3QgZD1kZXNjKGUpLnRvTG93ZXJDYXNlKCk7bGV0IHM9MDtmb3IoY29uc3QgdyBvZiBbJ3Byb21wdCcsJ2Rlc2NyaWJlJywnZGVzY3JpcHRpb24nLCdpbWFnaW5lJywnc2NlbmUnLCd2aWRlbycsJ2ltYWdlJywnY3JlYXRlJywnbWFrZScsJ3doYXQgZG8geW91IHdhbnQnLCd0eXBlIHlvdXInLCdlbnRlciB5b3VyJywn7ZSE66Gs7ZSE7Yq4Jywn7ISk66qFJywn7J6l66m0Jywn7JiB7IOBJywn7J2066+47KeAJywn66eM65OkJywn7IOd7ISxJywn7J6F66ClJ10paWYoZC5pbmNsdWRlcyh3KSlzKz0xMjtmb3IoY29uc3QgdyBvZiBbJ3NlYXJjaCcsJ2ZpbmQnLCfqsoDsg4knLCfrjJPquIAnLCdjb21tZW50JywndGl0bGUnLCfsoJzrqqknLCduYW1lJywn7J2066aEJ10paWYoZC5pbmNsdWRlcyh3KSlzLT0yMDtpZihlLnRhZ05hbWU9PT0nVEVYVEFSRUEnKXMrPTEyO2lmKGUuaXNDb250ZW50RWRpdGFibGUpcys9NztpZihlLmdldEF0dHJpYnV0ZT8uKCdyb2xlJyk9PT0ndGV4dGJveCcpcys9NDtjb25zdCB6PWUuZ2V0Qm91bmRpbmdDbGllbnRSZWN0KCk7cys9TWF0aC5taW4oMTIsTWF0aC5yb3VuZCh6LndpZHRoKnouaGVpZ2h0LzMwMDAwKSk7aWYoei50b3A+aW5uZXJIZWlnaHQqLjM1KXMrPTM7aWYocz5zY29yZSl7c2NvcmU9cztiZXN0PWV9fWxldCBmaWxsPXthdHRlbXB0ZWQ6ZmFsc2UsdmVyaWZpZWQ6ZmFsc2UsY2xlYXJlZDpmYWxzZX07aWYoYmVzdCYmc2NvcmU+PTUpe2ZpbGwuYXR0ZW1wdGVkPXRydWU7Y29uc3Qgb2xkPSgndmFsdWUnaW4gYmVzdCk/YmVzdC52YWx1ZTpiZXN0LnRleHRDb250ZW50O2NvbnN0IHY9JHtzZW50aW5lbExpdH07YmVzdC5mb2N1cygpO2lmKCd2YWx1ZSdpbiBiZXN0KXtjb25zdCBwcm90bz1iZXN0LnRhZ05hbWU9PT0nVEVYVEFSRUEnP0hUTUxUZXh0QXJlYUVsZW1lbnQucHJvdG90eXBlOkhUTUxJbnB1dEVsZW1lbnQucHJvdG90eXBlO2NvbnN0IHNldD1PYmplY3QuZ2V0T3duUHJvcGVydHlEZXNjcmlwdG9yKHByb3RvLCd2YWx1ZScpPy5zZXQ7aWYoc2V0KXNldC5jYWxsKGJlc3Qsdik7ZWxzZSBiZXN0LnZhbHVlPXZ9ZWxzZSBiZXN0LnRleHRDb250ZW50PXY7dHJ5e2Jlc3QuZGlzcGF0Y2hFdmVudChuZXcgSW5wdXRFdmVudCgnaW5wdXQnLHtidWJibGVzOnRydWUsaW5wdXRUeXBlOidpbnNlcnRUZXh0JyxkYXRhOnZ9KSl9Y2F0Y2h7YmVzdC5kaXNwYXRjaEV2ZW50KG5ldyBFdmVudCgnaW5wdXQnLHtidWJibGVzOnRydWV9KSl9YmVzdC5kaXNwYXRjaEV2ZW50KG5ldyBFdmVudCgnY2hhbmdlJyx7YnViYmxlczp0cnVlfSkpO2ZpbGwudmVyaWZpZWQ9KCgndmFsdWUnaW4gYmVzdCk/YmVzdC52YWx1ZTpiZXN0LnRleHRDb250ZW50KT09PXY7aWYoJ3ZhbHVlJ2luIGJlc3Qpe2NvbnN0IHByb3RvPWJlc3QudGFnTmFtZT09PSdURVhUQVJFQSc/SFRNTFRleHRBcmVhRWxlbWVudC5wcm90b3R5cGU6SFRNTElucHV0RWxlbWVudC5wcm90b3R5cGU7Y29uc3Qgc2V0PU9iamVjdC5nZXRPd25Qcm9wZXJ0eURlc2NyaXB0b3IocHJvdG8sJ3ZhbHVlJyk/LnNldDtpZihzZXQpc2V0LmNhbGwoYmVzdCxvbGQpO2Vsc2UgYmVzdC52YWx1ZT1vbGR9ZWxzZSBiZXN0LnRleHRDb250ZW50PW9sZDt0cnl7YmVzdC5kaXNwYXRjaEV2ZW50KG5ldyBJbnB1dEV2ZW50KCdpbnB1dCcse2J1YmJsZXM6dHJ1ZSxpbnB1dFR5cGU6J2RlbGV0ZUNvbnRlbnRCYWNrd2FyZCcsZGF0YTpudWxsfSkpfWNhdGNoe2Jlc3QuZGlzcGF0Y2hFdmVudChuZXcgRXZlbnQoJ2lucHV0Jyx7YnViYmxlczp0cnVlfSkpfWJlc3QuZGlzcGF0Y2hFdmVudChuZXcgRXZlbnQoJ2NoYW5nZScse2J1YmJsZXM6dHJ1ZX0pKTtmaWxsLmNsZWFyZWQ9KCgndmFsdWUnaW4gYmVzdCk/YmVzdC52YWx1ZTpiZXN0LnRleHRDb250ZW50KT09PW9sZH1sZXQgYnV0dG9ucz1bXTtmb3IoY29uc3QgciBvZiByb290cyl7dHJ5e2J1dHRvbnMucHVzaCguLi5yLnF1ZXJ5U2VsZWN0b3JBbGwoJ2J1dHRvbixbcm9sZT1idXR0b25dLGEnKSl9Y2F0Y2h7fX1jb25zdCByb3V0ZUhpbnRzPVsuLi5uZXcgU2V0KGJ1dHRvbnMpXS5maWx0ZXIodmlzKS5tYXAoZT0+KHt0ZXh0OmRlc2MoZSkuc2xpY2UoMCwxODApLGhyZWY6ZS5ocmVmfHwnJ30pKS5maWx0ZXIoeD0+L3Byb2plY3R8Y3JlYXRlfG5ld3xnZW5lcmF0ZXxmbG93fO2UhOuhnOygne2KuHzrp4zrk6R87IOd7ISxL2kudGVzdCh4LnRleHQrJyAnK3guaHJlZikpLnNsaWNlKDAsMjApO3JldHVybiB7dXJsOmxvY2F0aW9uLmhyZWYsdGl0bGU6ZG9jdW1lbnQudGl0bGUscmVhZHlTdGF0ZTpkb2N1bWVudC5yZWFkeVN0YXRlLHNoYWRvd1Jvb3RDb3VudDpyb290cy5sZW5ndGgtMSxpbnB1dENhbmRpZGF0ZUNvdW50OmlucHV0cy5sZW5ndGgscHJvbXB0SW5wdXRGb3VuZDohIShiZXN0JiZzY29yZT49NSkscHJvbXB0SW5wdXRTY29yZTpzY29yZSxwcm9tcHRJbnB1dFRhZzpiZXN0Py50YWdOYW1lfHwnJyxwcm9tcHRJbnB1dERlc2M6YmVzdD9kZXNjKGJlc3QpLnNsaWNlKDAsMjQwKTonJyxpbnB1dEZpbGxBdHRlbXB0ZWQ6ZmlsbC5hdHRlbXB0ZWQsaW5wdXRGaWxsVmVyaWZpZWQ6ZmlsbC52ZXJpZmllZCxpbnB1dENsZWFyZWQ6ZmlsbC5jbGVhcmVkLHJvdXRlSGludHMsYm9keVRleHRMZW5ndGg6KGRvY3VtZW50LmJvZHk/LmlubmVyVGV4dHx8JycpLmxlbmd0aH19KSgpYDsKbGV0IHI9YXdhaXQgcC5zZW5kKCdSdW50aW1lLmV2YWx1YXRlJyx7ZXhwcmVzc2lvbjpiYXNlRXhwcixyZXR1cm5CeVZhbHVlOnRydWUsYXdhaXRQcm9taXNlOnRydWUsdXNlckdlc3R1cmU6dHJ1ZX0pOwpsZXQgZmlyc3Q9ci5yZXN1bHQ/LnZhbHVlfHxudWxsLCBuYXZpZ2F0ZWQ9ZmFsc2UsIG5hdlRleHQ9Jyc7CmlmKGZpcnN0ICYmICFmaXJzdC5wcm9tcHRJbnB1dEZvdW5kKXsKICBjb25zdCBuYXZFeHByPWAoKCk9Pntjb25zdCByb290cz1bZG9jdW1lbnRdLHE9W2RvY3VtZW50XSxzZWVuPW5ldyBTZXQocSk7d2hpbGUocS5sZW5ndGgpe2NvbnN0IHI9cS5zaGlmdCgpO2xldCBhPVtdO3RyeXthPVsuLi5yLnF1ZXJ5U2VsZWN0b3JBbGwoJyonKV19Y2F0Y2h7fTtmb3IoY29uc3QgZSBvZiBhKXtpZihlLnNoYWRvd1Jvb3QmJiFzZWVuLmhhcyhlLnNoYWRvd1Jvb3QpKXtzZWVuLmFkZChlLnNoYWRvd1Jvb3QpO3Jvb3RzLnB1c2goZS5zaGFkb3dSb290KTtxLnB1c2goZS5zaGFkb3dSb290KX19fWNvbnN0IHZpcz1lPT57aWYoIWUpcmV0dXJuIGZhbHNlO2NvbnN0IHM9Z2V0Q29tcHV0ZWRTdHlsZShlKSxyPWUuZ2V0Qm91bmRpbmdDbGllbnRSZWN0KCk7cmV0dXJuIHMuZGlzcGxheSE9PSdub25lJyYmcy52aXNpYmlsaXR5IT09J2hpZGRlbicmJnIud2lkdGg+MTgmJnIuaGVpZ2h0PjE4fTtjb25zdCBkZXNjPWU9PltlLmdldEF0dHJpYnV0ZT8uKCdhcmlhLWxhYmVsJyksZS5nZXRBdHRyaWJ1dGU/LigndGl0bGUnKSxlLnRleHRDb250ZW50XS5maWx0ZXIoQm9vbGVhbikuam9pbignICcpLnJlcGxhY2UoL1xccysvZywnICcpLnRyaW0oKTtsZXQgYWxsPVtdO2Zvcihjb25zdCByIG9mIHJvb3RzKXt0cnl7YWxsLnB1c2goLi4uci5xdWVyeVNlbGVjdG9yQWxsKCdidXR0b24sW3JvbGU9YnV0dG9uXSxhJykpfWNhdGNoe319Y29uc3QgYz1bLi4ubmV3IFNldChhbGwpXS5maWx0ZXIodmlzKS5tYXAoZT0+KHtlLHQ6ZGVzYyhlKX0pKS5maW5kKHg9Pi9eKG5ldyBwcm9qZWN0fGNyZWF0ZSBwcm9qZWN0fOyDiCDtlITroZzsoJ3tirh87ZSE66Gc7KCd7Yq4IOunjOuTpOq4sCkkL2kudGVzdCh4LnQpfHwvbmV3IHByb2plY3R8Y3JlYXRlIHByb2plY3R87IOIIO2UhOuhnOygne2KuHztlITroZzsoJ3tirgg66eM65Ok6riwL2kudGVzdCh4LnQpKTtpZighYylyZXR1cm4ge2NsaWNrZWQ6ZmFsc2UsdGV4dDonJ307Yy5lLmNsaWNrKCk7cmV0dXJuIHtjbGlja2VkOnRydWUsdGV4dDpjLnQuc2xpY2UoMCwxODApfX0pKClgOwogIGNvbnN0IG5yPWF3YWl0IHAuc2VuZCgnUnVudGltZS5ldmFsdWF0ZScse2V4cHJlc3Npb246bmF2RXhwcixyZXR1cm5CeVZhbHVlOnRydWUsdXNlckdlc3R1cmU6dHJ1ZX0pO25hdmlnYXRlZD0hIW5yLnJlc3VsdD8udmFsdWU/LmNsaWNrZWQ7bmF2VGV4dD1uci5yZXN1bHQ/LnZhbHVlPy50ZXh0fHwnJzsKICBpZihuYXZpZ2F0ZWQpe2F3YWl0IG5ldyBQcm9taXNlKHI9PnNldFRpbWVvdXQociwzNTAwKSk7cj1hd2FpdCBwLnNlbmQoJ1J1bnRpbWUuZXZhbHVhdGUnLHtleHByZXNzaW9uOmJhc2VFeHByLHJldHVybkJ5VmFsdWU6dHJ1ZSxhd2FpdFByb21pc2U6dHJ1ZSx1c2VyR2VzdHVyZTp0cnVlfSk7fQp9CmNvbnNvbGUubG9nKEpTT04uc3RyaW5naWZ5KHtvazp0cnVlLHRhcmdldHM6e2V4dGVuc2lvblRhcmdldHM6ZXh0LGV4cGVjdGVkRXh0ZW5zaW9uVGFyZ2V0czpleHBlY3RlZCxleHRlbnNpb25UYXJnZXRDb3VudDpleHQubGVuZ3RoLGV4cGVjdGVkRXh0ZW5zaW9uVGFyZ2V0Q291bnQ6ZXhwZWN0ZWQubGVuZ3RoLGV4cGVjdGVkU2VydmljZVdvcmtlckNvdW50OmV4cGVjdGVkLmZpbHRlcih0PT50LnR5cGU9PT0nc2VydmljZV93b3JrZXInKS5sZW5ndGh9LGZpcnN0UGFnZTpmaXJzdCxuYXZpZ2F0ZWRUb1dvcmtzcGFjZTpuYXZpZ2F0ZWQsbmF2aWdhdGlvblRleHQ6bmF2VGV4dCxwYWdlOnIucmVzdWx0Py52YWx1ZXx8bnVsbH0pKTsKJ0AKICBTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJGpzIC1WYWx1ZSAkY29kZSAtRW5jb2RpbmcgVVRGOAogIHRyeXsKICAgICRvdXQ9JiAkbm9kZS5Tb3VyY2UgJGpzICRCcm93c2VyV3MgJFBhZ2VXcyAkU2VudGluZWwgJEV4cGVjdGVkRmxvd0V4dGVuc2lvbklkIDI+JjF8T3V0LVN0cmluZzskdHJpbT0kb3V0LlRyaW0oKTsKICAgIGlmKC1ub3QgJHRyaW0pe3JldHVybiBbb3JkZXJlZF1Ae29rPSRmYWxzZTtzdGFnZT0nRU1QVFlfREVFUF9QUk9CRSd9fQogICAgJGxhc3Q9KCR0cmltLlNwbGl0KCJgbiIpfFNlbGVjdC1PYmplY3QgLUxhc3QgMSkuVHJpbSgpO3JldHVybiAoJGxhc3R8Q29udmVydEZyb20tSnNvbikKICB9Y2F0Y2h7cmV0dXJuIFtvcmRlcmVkXUB7b2s9JGZhbHNlO3N0YWdlPSdERUVQX1BST0JFX0VSUk9SJztlcnJvcj0kXy5FeGNlcHRpb24uTWVzc2FnZTtuYXRpdmVPdXRwdXQ9JChpZigkdHJpbSl7JHRyaW19ZWxzZXsnJ30pfX1maW5hbGx5e1JlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkanMgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlfQp9CgokdGFzaz1TYWZlLVRhc2tJZCAkVGFza0lkCiRjZW50cmFsPUZpbmQtQ2VudHJhbFJvb3QKaWYoLW5vdCAkY2VudHJhbCl7dGhyb3cgJ0NFTlRSQUxfRFJJVkVfUk9PVF9OT1RfRk9VTkQnfQokZmxvd0V4dGVuc2lvbj1GaW5kLUZsb3dFeHRlbnNpb24KaWYoLW5vdCAkZmxvd0V4dGVuc2lvbil7dGhyb3cgJ0ZMT1dfRVhURU5TSU9OX1BBVEhfTk9UX0ZPVU5EJ30KJG1hbmlmZXN0PUdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRmbG93RXh0ZW5zaW9uICdtYW5pZmVzdC5qc29uJykgLVJhdyAtRW5jb2RpbmcgVVRGOHxDb252ZXJ0RnJvbS1Kc29uCiRtYW5pZmVzdEJhY2tncm91bmQ9Jyc7dHJ5eyRtYW5pZmVzdEJhY2tncm91bmQ9W3N0cmluZ10kbWFuaWZlc3QuYmFja2dyb3VuZC5zZXJ2aWNlX3dvcmtlcn1jYXRjaHt9CiRtYW5pZmVzdENvbnRlbnRTY3JpcHRzPUAoKTt0cnl7JG1hbmlmZXN0Q29udGVudFNjcmlwdHM9QCgkbWFuaWZlc3QuY29udGVudF9zY3JpcHRzfEZvckVhY2gtT2JqZWN0e1tvcmRlcmVkXUB7bWF0Y2hlcz1AKCRfLm1hdGNoZXMpO2pzPUAoJF8uanMpO3J1bkF0PVtzdHJpbmddJF8ucnVuX2F0fX0pfWNhdGNoe30KJG1hbmlmZXN0QWN0aW9uUG9wdXA9Jyc7dHJ5eyRtYW5pZmVzdEFjdGlvblBvcHVwPVtzdHJpbmddJG1hbmlmZXN0LmFjdGlvbi5kZWZhdWx0X3BvcHVwfWNhdGNoe30KJGV4dGVuc2lvbkFyY2hpdGVjdHVyZT0kKGlmKCRtYW5pZmVzdEJhY2tncm91bmQpeydiYWNrZ3JvdW5kX3NlcnZpY2Vfd29ya2VyJ31lbHNlaWYoJG1hbmlmZXN0QWN0aW9uUG9wdXAgLWFuZCBAKCRtYW5pZmVzdC5jb250ZW50X3NjcmlwdHMpLkNvdW50IC1ndCAwKXsnY29udGVudF9zY3JpcHRfcGx1c19wb3B1cCd9ZWxzZWlmKEAoJG1hbmlmZXN0LmNvbnRlbnRfc2NyaXB0cykuQ291bnQgLWd0IDApeydjb250ZW50X3NjcmlwdF9vbmx5J31lbHNleydleHRlbnNpb25fcGFnZV9vcl91bmtub3duJ30pCiRjb250ZW50U291cmNlPVJlYWQtVGV4dFNhZmUgKEpvaW4tUGF0aCAkZmxvd0V4dGVuc2lvbiAnY29udGVudC5qcycpCiRwb3B1cEh0bWxTb3VyY2U9UmVhZC1UZXh0U2FmZSAoSm9pbi1QYXRoICRmbG93RXh0ZW5zaW9uICdwb3B1cC5odG1sJykKJHBvcHVwSnNTb3VyY2U9UmVhZC1UZXh0U2FmZSAoSm9pbi1QYXRoICRmbG93RXh0ZW5zaW9uICdwb3B1cC5qcycpCiRjaHJvbWU9RmluZC1DZnRDaHJvbWUKaWYoLW5vdCAkY2hyb21lKXt0aHJvdyAnQ0ZUX0NIUk9NRV9FWEVfTk9UX0ZPVU5EJ30KJG5vcm1hbEJlZm9yZT1AKE5vcm1hbC1Qcm9jc3xGb3JFYWNoLU9iamVjdHtbaW50XSRfLlByb2Nlc3NJZH0pCiRub3JtYWxSb290QmVmb3JlPUAoTm9ybWFsLUJyb3dzZXJSb290c3xGb3JFYWNoLU9iamVjdHtbaW50XSRfLlByb2Nlc3NJZH0pCiRkZWRpY2F0ZWRTdG9wcGVkPUAoU3RvcC1EZWRpY2F0ZWQpCiRhcmdzPUAoIi0tdXNlci1kYXRhLWRpcj0kVXNlckRhdGEiLCctLXByb2ZpbGUtZGlyZWN0b3J5PURlZmF1bHQnLCctLW5ldy13aW5kb3cnLCctLW5vLWZpcnN0LXJ1bicsJy0tbm8tZGVmYXVsdC1icm93c2VyLWNoZWNrJywnLS1kaXNhYmxlLXNlc3Npb24tY3Jhc2hlZC1idWJibGUnLCctLWRpc2FibGUtZG93bmxvYWQtbm90aWZpY2F0aW9uJywoIi0tbG9hZC1leHRlbnNpb249JGZsb3dFeHRlbnNpb24iKSwoIi0tcmVtb3RlLWRlYnVnZ2luZy1wb3J0PSREZWJ1Z1BvcnQiKSwnLS1yZW1vdGUtZGVidWdnaW5nLWFkZHJlc3M9MTI3LjAuMC4xJywkRmxvd1VybCkKU3RhcnQtUHJvY2VzcyAtRmlsZVBhdGggJGNocm9tZS5GdWxsTmFtZSAtQXJndW1lbnRMaXN0ICRhcmdzIC1Xb3JraW5nRGlyZWN0b3J5ICRjaHJvbWUuRGlyZWN0b3J5LkZ1bGxOYW1lfE91dC1OdWxsCgokdmVyc2lvbj0kbnVsbDskdGFyZ2V0cz1AKCk7JGRlYWRsaW5lPShHZXQtRGF0ZSkuQWRkU2Vjb25kcygzMCkKZG97CiAgdHJ5eyR2ZXJzaW9uPUludm9rZS1SZXN0TWV0aG9kIC1VcmkgKCJodHRwOi8vMTI3LjAuMC4xOiREZWJ1Z1BvcnQvanNvbi92ZXJzaW9uIikgLVRpbWVvdXRTZWMgMjtpZigkdmVyc2lvbi53ZWJTb2NrZXREZWJ1Z2dlclVybCl7JHRhcmdldHM9QChJbnZva2UtUmVzdE1ldGhvZCAtVXJpICgiaHR0cDovLzEyNy4wLjAuMTokRGVidWdQb3J0L2pzb24vbGlzdCIpIC1UaW1lb3V0U2VjIDIpO2lmKEAoJHRhcmdldHN8V2hlcmUtT2JqZWN0eyRfLnR5cGUgLWVxICdwYWdlJyAtYW5kICRfLnVybCAtYW5kIChbc3RyaW5nXSRfLnVybCkuQ29udGFpbnMoJy9meC90b29scy9mbG93Jyl9KS5Db3VudCAtZ3QgMCl7YnJlYWt9fX1jYXRjaHt9CiAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA1MDAKfXdoaWxlKChHZXQtRGF0ZSktbHQgJGRlYWRsaW5lKQoKJGZsb3dQYWdlcz1AKCR0YXJnZXRzfFdoZXJlLU9iamVjdHskXy50eXBlIC1lcSAncGFnZScgLWFuZCAkXy51cmwgLWFuZCAoW3N0cmluZ10kXy51cmwpLkNvbnRhaW5zKCcvZngvdG9vbHMvZmxvdycpfSkKJGZsb3dQYWdlPSRmbG93UGFnZXN8U2VsZWN0LU9iamVjdCAtRmlyc3QgMQokbG9naW5QYWdlcz1AKCR0YXJnZXRzfFdoZXJlLU9iamVjdHskXy50eXBlIC1lcSAncGFnZScgLWFuZCAkXy51cmwgLWFuZCAoW3N0cmluZ10kXy51cmwpLkNvbnRhaW5zKCdhY2NvdW50cy5nb29nbGUuY29tJyl9KQokZGVkaWNhdGVkQ21kPUAoRGVkaWNhdGVkLVByb2NzfEZvckVhY2gtT2JqZWN0e1tzdHJpbmddJF8uQ29tbWFuZExpbmV9KQokbG9hZEFyZ1ByZXNlbnQ9KEAoJGRlZGljYXRlZENtZHxXaGVyZS1PYmplY3R7JF8gLWFuZCAkXy5Db250YWlucygnLS1sb2FkLWV4dGVuc2lvbj0nKSAtYW5kICRfLkNvbnRhaW5zKCRmbG93RXh0ZW5zaW9uKX0pLkNvdW50IC1ndCAwKQokc2VudGluZWw9J0NFTlRSQUxfQUdFTlRfRkxPV19JTlBVVF9QUk9CRV8nKyhHZXQtRGF0ZSAtRm9ybWF0ICdISG1tc3MnKQokZGVlcD0kbnVsbAppZigkdmVyc2lvbiAtYW5kICR2ZXJzaW9uLndlYlNvY2tldERlYnVnZ2VyVXJsIC1hbmQgJGZsb3dQYWdlIC1hbmQgJGZsb3dQYWdlLndlYlNvY2tldERlYnVnZ2VyVXJsKXskZGVlcD1JbnZva2UtRGVlcFByb2JlIC1Ccm93c2VyV3MgKFtzdHJpbmddJHZlcnNpb24ud2ViU29ja2V0RGVidWdnZXJVcmwpIC1QYWdlV3MgKFtzdHJpbmddJGZsb3dQYWdlLndlYlNvY2tldERlYnVnZ2VyVXJsKSAtU2VudGluZWwgJHNlbnRpbmVsfWVsc2V7JGRlZXA9W29yZGVyZWRdQHtvaz0kZmFsc2U7c3RhZ2U9J05PX0NEUF9QQUdFX0ZPUl9ERUVQX1BST0JFJ319CiRyZXN0b3JlZD1SZXN0b3JlLU5vdGVib29rCiRub3JtYWxBZnRlcj1AKE5vcm1hbC1Qcm9jc3xGb3JFYWNoLU9iamVjdHtbaW50XSRfLlByb2Nlc3NJZH0pCiRub3JtYWxSb290QWZ0ZXI9QChOb3JtYWwtQnJvd3NlclJvb3RzfEZvckVhY2gtT2JqZWN0e1tpbnRdJF8uUHJvY2Vzc0lkfSkKJG1pc3NpbmdSb290PUAoJG5vcm1hbFJvb3RCZWZvcmV8V2hlcmUtT2JqZWN0eyRub3JtYWxSb290QWZ0ZXIgLW5vdGNvbnRhaW5zICRffSkKJG5vcm1hbENocm9tZVVudG91Y2hlZD0oJG1pc3NpbmdSb290LkNvdW50IC1lcSAwKQokY29udGVudFNjcmlwdENvbmZpZ3VyZWQ9KEAoJG1hbmlmZXN0Q29udGVudFNjcmlwdHMpLkNvdW50IC1ndCAwIC1hbmQgQCgkbWFuaWZlc3RDb250ZW50U2NyaXB0c3xXaGVyZS1PYmplY3R7QCgkXy5tYXRjaGVzKSAtY29udGFpbnMgJ2h0dHBzOi8vbGFicy5nb29nbGUvKicgLWFuZCBAKCRfLmpzKSAtY29udGFpbnMgJ2NvbnRlbnQuanMnfSkuQ291bnQgLWd0IDApCiRpbnB1dFZlcmlmaWVkPSgkZGVlcCAtYW5kICRkZWVwLm9rIC1hbmQgW2Jvb2xdJGRlZXAucGFnZS5wcm9tcHRJbnB1dEZvdW5kIC1hbmQgW2Jvb2xdJGRlZXAucGFnZS5pbnB1dEZpbGxWZXJpZmllZCAtYW5kIFtib29sXSRkZWVwLnBhZ2UuaW5wdXRDbGVhcmVkKQokZXh0ZW5zaW9uQ29udGV4dEdhdGU9JChpZigkZXh0ZW5zaW9uQXJjaGl0ZWN0dXJlIC1lcSAnYmFja2dyb3VuZF9zZXJ2aWNlX3dvcmtlcicpeygkZGVlcCAtYW5kICRkZWVwLm9rIC1hbmQgW2ludF0kZGVlcC50YXJnZXRzLmV4cGVjdGVkU2VydmljZVdvcmtlckNvdW50IC1ndCAwKX1lbHNleyRjb250ZW50U2NyaXB0Q29uZmlndXJlZH0pCiRvaz0oJHZlcnNpb24gLWFuZCAkdmVyc2lvbi53ZWJTb2NrZXREZWJ1Z2dlclVybCAtYW5kICRmbG93UGFnZXMuQ291bnQgLWd0IDAgLWFuZCAkbG9hZEFyZ1ByZXNlbnQgLWFuZCAkbG9naW5QYWdlcy5Db3VudCAtZXEgMCAtYW5kICRleHRlbnNpb25Db250ZXh0R2F0ZSAtYW5kICRpbnB1dFZlcmlmaWVkIC1hbmQgJHJlc3RvcmVkIC1hbmQgJG5vcm1hbENocm9tZVVudG91Y2hlZCkKCiRyZWFkYmFja0Rpcj1Kb2luLVBhdGggKEpvaW4tUGF0aCAkY2VudHJhbCAnUnVudGltZV9SZWFkYmFjaycpICdGbG93X0JyaWRnZV9EaXJlY3QnCiRyZXN1bHRQYXRoPUpvaW4tUGF0aCAkcmVhZGJhY2tEaXIgKCR0YXNrKydfcmVzdWx0Lmpzb24nKQokYWNrUGF0aD1Kb2luLVBhdGggJHJlYWRiYWNrRGlyICgkdGFzaysnX0FDSy5qc29uJykKJHJlc3VsdD1bb3JkZXJlZF1AewogIG9rPVtib29sXSRvazthY3Rpb249J0ZMT1dfQlJJREdFX0RFRVBfQ09OTkVDVF9QUk9CRV9WMic7dGFza0lkPSR0YXNrO2NlbnRyYWxSb290PSRjZW50cmFsO2Zsb3dVcmw9JEZsb3dVcmw7CiAgZXh0ZW5zaW9uUGF0aD0kZmxvd0V4dGVuc2lvbjtleHBlY3RlZEV4dGVuc2lvbklkPSRFeHBlY3RlZEZsb3dFeHRlbnNpb25JZDtleHRlbnNpb25OYW1lPVtzdHJpbmddJG1hbmlmZXN0Lm5hbWU7ZXh0ZW5zaW9uVmVyc2lvbj1bc3RyaW5nXSRtYW5pZmVzdC52ZXJzaW9uO21hbmlmZXN0VmVyc2lvbj1baW50XSRtYW5pZmVzdC5tYW5pZmVzdF92ZXJzaW9uO2V4dGVuc2lvbkFyY2hpdGVjdHVyZT0kZXh0ZW5zaW9uQXJjaGl0ZWN0dXJlO21hbmlmZXN0QmFja2dyb3VuZFNlcnZpY2VXb3JrZXI9JG1hbmlmZXN0QmFja2dyb3VuZDttYW5pZmVzdENvbnRlbnRTY3JpcHRzPSRtYW5pZmVzdENvbnRlbnRTY3JpcHRzO21hbmlmZXN0QWN0aW9uUG9wdXA9JG1hbmlmZXN0QWN0aW9uUG9wdXA7Y29udGVudFNjcmlwdENvbmZpZ3VyZWQ9W2Jvb2xdJGNvbnRlbnRTY3JpcHRDb25maWd1cmVkOwogIHNvdXJjZUNvbnRyYWN0PVtvcmRlcmVkXUB7Y29udGVudEpzPSRjb250ZW50U291cmNlO3BvcHVwSHRtbD0kcG9wdXBIdG1sU291cmNlO3BvcHVwSnM9JHBvcHVwSnNTb3VyY2V9OwogIGNmdENocm9tZT0kY2hyb21lLkZ1bGxOYW1lO2RlYnVnUG9ydD0kRGVidWdQb3J0O2NkcFJlYWR5PVtib29sXSgkdmVyc2lvbiAtYW5kICR2ZXJzaW9uLndlYlNvY2tldERlYnVnZ2VyVXJsKTtmbG93UGFnZUZvdW5kPSgkZmxvd1BhZ2VzLkNvdW50IC1ndCAwKTtmbG93UGFnZXM9QCgkZmxvd1BhZ2VzfEZvckVhY2gtT2JqZWN0e1tvcmRlcmVkXUB7dGl0bGU9JF8udGl0bGU7dXJsPSRfLnVybDt0eXBlPSRfLnR5cGV9fSk7bG9naW5SZXF1aXJlZD0oJGxvZ2luUGFnZXMuQ291bnQgLWd0IDApO2xvYWRFeHRlbnNpb25BcmdQcmVzZW50PVtib29sXSRsb2FkQXJnUHJlc2VudDsKICBkZWVwUHJvYmU9JGRlZXA7ZXh0ZW5zaW9uQ29udGV4dEdhdGU9W2Jvb2xdJGV4dGVuc2lvbkNvbnRleHRHYXRlO3Byb21wdElucHV0VmVyaWZpZWQ9W2Jvb2xdJGlucHV0VmVyaWZpZWQ7CiAgZGVkaWNhdGVkU3RvcHBlZD0kZGVkaWNhdGVkU3RvcHBlZDtub3RlYm9va0RlZGljYXRlZFJlc3RvcmVkPVtib29sXSRyZXN0b3JlZDtub3JtYWxDaHJvbWVCZWZvcmVDb3VudD0kbm9ybWFsQmVmb3JlLkNvdW50O25vcm1hbENocm9tZUFmdGVyQ291bnQ9JG5vcm1hbEFmdGVyLkNvdW50O25vcm1hbENocm9tZU1pc3NpbmdSb290UGlkcz0kbWlzc2luZ1Jvb3Q7bm9ybWFsQ2hyb21lVW50b3VjaGVkPVtib29sXSRub3JtYWxDaHJvbWVVbnRvdWNoZWQ7CiAgZ2VuZXJhdGVDbGlja2VkPSRmYWxzZTtjcmVkaXRTcGVuZD0kZmFsc2U7b2F1dGhDaGFuZ2VkPSRmYWxzZTtjaHJvbWVTZXR0aW5nc0NoYW5nZWQ9JGZhbHNlO3ZlcmlmaWNhdGlvbkNvbnRyYWN0PSdBUkNISVRFQ1RVUkVfQ0xBU1NJRklFRCtDT05URU5UX1NDUklQVF9DT05GSUdVUkVEX09SX1NFUlZJQ0VfV09SS0VSK1dPUktTUEFDRV9OQVZJR0FUSU9OK1BST01QVF9JTlBVVF9GSUxMX1JFQURCQUNLX0NMRUFSK0RSSVZFX0FDSyc7YXQ9KEdldC1EYXRlKS5Ub1N0cmluZygnbycpCn0KV3JpdGUtSnNvbkF0b21pYyAkcmVzdWx0UGF0aCAkcmVzdWx0CiRhY2s9W29yZGVyZWRdQHthY2s9W2Jvb2xdJG9rO3Rhc2tJZD0kdGFzazthY3Rpb249J0ZMT1dfQlJJREdFX0RFRVBfQ09OTkVDVF9QUk9CRV9WMic7cmVzdWx0UGF0aD0kcmVzdWx0UGF0aDtleHRlbnNpb25BcmNoaXRlY3R1cmU9JGV4dGVuc2lvbkFyY2hpdGVjdHVyZTtleHRlbnNpb25Db250ZXh0R2F0ZT1bYm9vbF0kZXh0ZW5zaW9uQ29udGV4dEdhdGU7cHJvbXB0SW5wdXRWZXJpZmllZD1bYm9vbF0kaW5wdXRWZXJpZmllZDtnZW5lcmF0ZUNsaWNrZWQ9JGZhbHNlO2NyZWRpdFNwZW5kPSRmYWxzZTthdD0oR2V0LURhdGUpLlRvU3RyaW5nKCdvJyl9CldyaXRlLUpzb25BdG9taWMgJGFja1BhdGggJGFjawokcmVzdWx0WydyZXN1bHRQYXRoJ109JHJlc3VsdFBhdGg7JHJlc3VsdFsnYWNrUGF0aCddPSRhY2tQYXRoOyRyZXN1bHRbJ2FjayddPVtib29sXSRvawokcmVzdWx0fENvbnZlcnRUby1Kc29uIC1EZXB0aCA2MCAtQ29tcHJlc3MKaWYoJG9rKXtleGl0IDB9ZWxzZXtleGl0IDJ9Cg=='
  [IO.File]::WriteAllBytes($tmpHelper,[Convert]::FromBase64String($payload))
  $helperActual = (GitBlobSha1 $tmpHelper).ToLowerInvariant()
  $helperExpected='43df9a311505abb0cb5e9b5a4aae2ce0bb881da0'
  if ($helperActual -ne $helperExpected) {
    Remove-Item -LiteralPath $tmpHelper -Force -ErrorAction SilentlyContinue
    throw ('FLOW_HELPER_EMBEDDED_SHA_MISMATCH:actual={0}:expected={1}' -f $helperActual,$helperExpected)
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
    action = 'FLOW_BRIDGE_CONNECT_PROBE_WRAPPER_EMBEDDED'
    helperExit = $helperRc
    helperSha = $helperActual
    helperOutput = $helperText
    diagnosticOnly = $true
    secondaryNetworkFetch = $false
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