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

function Safe-TaskId([string]$Value){if([string]::IsNullOrWhiteSpace($Value)){return ('FLOW_BRIDGE_CONNECT_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))};if($Value -notmatch '^[A-Za-z0-9_.-]{1,180}$'){throw 'UNSAFE_TASK_ID'};return $Value}
function Write-JsonAtomic([string]$Path,$Object){$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$tmp=$Path+'.tmp';$Object|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force}
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

$task=Safe-TaskId $TaskId
$central=Find-CentralRoot
if(-not $central){throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'}
$flowExtension=Find-FlowExtension
if(-not $flowExtension){throw 'FLOW_EXTENSION_PATH_NOT_FOUND'}
$manifest=Get-Content -LiteralPath (Join-Path $flowExtension 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$chrome=Find-CftChrome
if(-not $chrome){throw 'CFT_CHROME_EXE_NOT_FOUND'}
$normalBefore=@(Normal-Procs|ForEach-Object{[int]$_.ProcessId})
$normalRootBefore=@(Normal-BrowserRoots|ForEach-Object{[int]$_.ProcessId})
$dedicatedStopped=@(Stop-Dedicated)
$args=@("--user-data-dir=$UserData",'--profile-directory=Default','--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble','--disable-download-notification',("--load-extension=$flowExtension"),("--remote-debugging-port=$DebugPort"),'--remote-debugging-address=127.0.0.1',$FlowUrl)
Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.Directory.FullName|Out-Null

$version=$null;$targets=@();$deadline=(Get-Date).AddSeconds(30)
do{
  try{
    $version=Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/version") -TimeoutSec 2
    if($version.webSocketDebuggerUrl){
      $targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$DebugPort/json/list") -TimeoutSec 2)
      if(@($targets|Where-Object{$_.type -eq 'page' -and $_.url -and ([string]$_.url).Contains('/fx/tools/flow')}).Count -gt 0){break}
    }
  }catch{}
  Start-Sleep -Milliseconds 500
}while((Get-Date)-lt $deadline)

$flowPages=@($targets|Where-Object{$_.type -eq 'page' -and $_.url -and ([string]$_.url).Contains('/fx/tools/flow')})
$loginPages=@($targets|Where-Object{$_.type -eq 'page' -and $_.url -and ([string]$_.url).Contains('accounts.google.com')})
$extensionTargets=@($targets|Where-Object{$_.url -and ([string]$_.url).StartsWith('chrome-extension://')}|ForEach-Object{[ordered]@{type=$_.type;title=$_.title;url=$_.url}})
$dedicatedCmd=@(Dedicated-Procs|ForEach-Object{[string]$_.CommandLine})
$loadArgPresent=(@($dedicatedCmd|Where-Object{$_ -and $_.Contains('--load-extension=') -and $_.Contains($flowExtension)}).Count -gt 0)
$restored=Restore-Notebook
$normalAfter=@(Normal-Procs|ForEach-Object{[int]$_.ProcessId})
$normalRootAfter=@(Normal-BrowserRoots|ForEach-Object{[int]$_.ProcessId})
$missingNormal=@($normalBefore|Where-Object{$normalAfter -notcontains $_})
$missingRoot=@($normalRootBefore|Where-Object{$normalRootAfter -notcontains $_})
$childChurn=@($missingNormal|Where-Object{$missingRoot -notcontains $_})
$normalChromeUntouched=($missingRoot.Count -eq 0)
$ok=($version -and $version.webSocketDebuggerUrl -and $flowPages.Count -gt 0 -and $loadArgPresent -and $loginPages.Count -eq 0 -and $restored -and $normalChromeUntouched)

$readbackDir=Join-Path (Join-Path $central 'Runtime_Readback') 'Flow_Bridge_Direct'
$resultPath=Join-Path $readbackDir ($task+'_result.json')
$ackPath=Join-Path $readbackDir ($task+'_ACK.json')
$result=[ordered]@{
  ok=[bool]$ok;action='FLOW_BRIDGE_DIRECT_CONNECT_SMOKE';taskId=$task;centralRoot=$central;flowUrl=$FlowUrl;
  extensionPath=$flowExtension;extensionName=[string]$manifest.name;extensionVersion=[string]$manifest.version;
  cftChrome=$chrome.FullName;debugPort=$DebugPort;cdpReady=[bool]($version -and $version.webSocketDebuggerUrl);
  flowPageFound=($flowPages.Count -gt 0);flowPages=@($flowPages|ForEach-Object{[ordered]@{title=$_.title;url=$_.url}});
  loginRequired=($loginPages.Count -gt 0);loadExtensionArgPresent=[bool]$loadArgPresent;extensionTargets=$extensionTargets;extensionTargetCount=$extensionTargets.Count;
  dedicatedStopped=$dedicatedStopped;notebookDedicatedRestored=[bool]$restored;
  normalChromeBeforeCount=$normalBefore.Count;normalChromeAfterCount=$normalAfter.Count;normalChromeMissingPids=$missingNormal;
  normalChromeRootBeforeCount=$normalRootBefore.Count;normalChromeRootAfterCount=$normalRootAfter.Count;normalChromeMissingRootPids=$missingRoot;normalChromeChildChurnPids=$childChurn;normalChromeUntouched=[bool]$normalChromeUntouched;
  generateClicked=$false;creditSpend=$false;oauthChanged=$false;chromeSettingsChanged=$false;at=(Get-Date).ToString('o')
}
Write-JsonAtomic $resultPath $result
$ack=[ordered]@{ack=[bool]$ok;taskId=$task;action='FLOW_BRIDGE_DIRECT_CONNECT_SMOKE';resultPath=$resultPath;generateClicked=$false;creditSpend=$false;at=(Get-Date).ToString('o')}
Write-JsonAtomic $ackPath $ack
$result['resultPath']=$resultPath;$result['ackPath']=$ackPath;$result['ack']=[bool]$ok
$result|ConvertTo-Json -Depth 30 -Compress
if($ok){exit 0}else{exit 2}
