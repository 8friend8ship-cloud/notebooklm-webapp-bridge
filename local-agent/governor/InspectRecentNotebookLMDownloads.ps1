param(
  [int]$Hours=48,
  [int]$MaxItems=80,
  [switch]$TriggerBridgeAutoPollViaCDP,
  [switch]$InspectChromeDownloadsViaCDP,
  [int]$RemoteDebuggingPort=9223
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$scriptVersion='D112_CONFIGURED_PATHS_CDP_POLL_DOWNLOAD_HISTORY'

$base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$userData=Join-Path $base 'ChromeUserData'
$extensionRoot=Join-Path $base 'Extension\NotebookLM-WebApp-Bridge'
$cftRoot=Join-Path $base 'ChromeForTesting'
$front='https://notebooklm-webapp-bridge.vercel.app/'

function Find-Chrome {
  if(Test-Path -LiteralPath $cftRoot){
    $hit=Get-ChildItem -LiteralPath $cftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
    if($hit){return $hit.FullName}
  }
  foreach($candidate in @(
    (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
  )){if($candidate -and (Test-Path -LiteralPath $candidate)){return $candidate}}
  throw 'CHROME_EXE_NOT_FOUND'
}
function Dedicated-Procs {
  try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$userData*"})}catch{return @()}
}
function Debug-Ready {
  try{$v=Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/version") -TimeoutSec 2;return [bool]$v.webSocketDebuggerUrl}catch{return $false}
}
function Ensure-DebugChrome {
  if(Debug-Ready){return $false}
  foreach($p in @(Dedicated-Procs)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Milliseconds 900
  $chrome=Find-Chrome
  $args=@(
    "--remote-debugging-port=$RemoteDebuggingPort",
    '--remote-allow-origins=*',
    "--user-data-dir=$userData",
    '--profile-directory=Default',
    "--load-extension=$extensionRoot",
    '--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',
    $front
  )
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  $deadline=(Get-Date).AddSeconds(18)
  do{Start-Sleep -Milliseconds 400;if(Debug-Ready){return $true}}while((Get-Date)-lt $deadline)
  throw 'CDP_PORT_NOT_READY'
}
function Receive-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws){
  $buf=New-Object byte[] 65536
  $ms=New-Object IO.MemoryStream
  try{
    do{
      $seg=New-Object ArraySegment[byte] -ArgumentList @(,$buf)
      $res=$Ws.ReceiveAsync($seg,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
      if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_WEBSOCKET_CLOSED'}
      $ms.Write($buf,0,$res.Count)
    }while(-not $res.EndOfMessage)
    return [Text.Encoding]::UTF8.GetString($ms.ToArray())|ConvertFrom-Json
  }finally{$ms.Dispose()}
}
function Send-Cdp([System.Net.WebSockets.ClientWebSocket]$Ws,[ref]$Seq,[string]$Method,[hashtable]$Params=@{}){
  $Seq.Value++
  $id=$Seq.Value
  $json=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 30 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $seg=New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
  $Ws.SendAsync($seg,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
  while($true){
    $msg=Receive-Cdp $Ws
    if($msg.id -eq $id){
      if($msg.error){throw ('CDP_'+$Method+': '+($msg.error|ConvertTo-Json -Compress))}
      return $msg.result
    }
  }
}
function Eval-Cdp($Ws,[ref]$Seq,[string]$Expr){
  $r=Send-Cdp $Ws $Seq 'Runtime.evaluate' @{expression=$Expr;returnByValue=$true;awaitPromise=$true}
  if($r.exceptionDetails){throw ('CDP_RUNTIME_EXCEPTION: '+($r.exceptionDetails|ConvertTo-Json -Depth 8 -Compress))}
  return $r.result.value
}
function Open-CdpTarget([string]$Url){
  $encoded=[uri]::EscapeDataString($Url)
  try{return Invoke-RestMethod -Method Put -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/new?$encoded") -TimeoutSec 4}catch{
    try{return Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/new?$encoded") -TimeoutSec 4}catch{throw}
  }
}

if($InspectChromeDownloadsViaCDP){
  $result=[ordered]@{ok=$false;action='INSPECT_CHROME_DOWNLOAD_HISTORY_CDP';scriptVersion=$scriptVersion;restartedDedicatedChrome=$false;count=0;items=@();error='';readOnly=$true;at=(Get-Date).ToString('o')}
  $ws=$null
  try{
    $result.restartedDedicatedChrome=[bool](Ensure-DebugChrome)
    $target=Open-CdpTarget 'chrome://downloads/'
    Start-Sleep -Milliseconds 1200
    if(-not $target.webSocketDebuggerUrl){
      $targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 4)
      $target=$targets|Where-Object{$_.url -like 'chrome://downloads*' -and $_.webSocketDebuggerUrl}|Select-Object -First 1
    }
    if(-not $target -or -not $target.webSocketDebuggerUrl){throw 'CHROME_DOWNLOADS_TARGET_NOT_FOUND'}
    $ws=New-Object System.Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $seq=0
    [void](Send-Cdp $ws ([ref]$seq) 'Runtime.enable' @{})
    $expr=@"
(async()=>{
  const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
  for(let i=0;i<20;i++){
    const m=document.querySelector('downloads-manager');
    if(m&&m.shadowRoot){
      const list=m.shadowRoot.querySelector('#downloadsList');
      const items=(m.items||list&&list.items||[]);
      if(items&&items.length){
        return items.slice(0,100).map(x=>({
          fileName:x.fileName||x.file_name||'',
          filePath:x.filePath||x.file_path||'',
          url:x.url&&x.url.url?x.url.url:(x.url||''),
          state:x.state||'',
          dangerType:x.dangerType||'',
          startTime:x.startTime||'',
          totalBytes:Number(x.totalBytes||0),
          receivedBytes:Number(x.receivedBytes||0)
        }));
      }
    }
    await sleep(250);
  }
  return [];
})()
"@
    $raw=@(Eval-Cdp $ws ([ref]$seq) $expr)
    $items=@()
    foreach($x in $raw){
      $path=[string]$x.filePath
      $exists=$false;$bytes=[int64]0;$lastWrite=''
      if($path){
        try{
          if(Test-Path -LiteralPath $path -PathType Leaf){$f=Get-Item -LiteralPath $path -ErrorAction Stop;$exists=$true;$bytes=[int64]$f.Length;$lastWrite=$f.LastWriteTime.ToString('o')}
        }catch{}
      }
      $items += [ordered]@{fileName=[string]$x.fileName;filePath=$path;exists=$exists;bytes=$bytes;lastWrite=$lastWrite;state=[string]$x.state;totalBytes=[int64]$x.totalBytes;receivedBytes=[int64]$x.receivedBytes;url=[string]$x.url}
    }
    $result.items=@($items)
    $result.count=@($items).Count
    $result.ok=$true
  }catch{$result.error=$_.Exception.Message}
  finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
  $result|ConvertTo-Json -Depth 12 -Compress
  if($result.ok){exit 0}else{exit 2}
}

if($TriggerBridgeAutoPollViaCDP){
  $result=[ordered]@{ok=$false;action='TRIGGER_BRIDGE_AUTO_POLL_CDP';scriptVersion=$scriptVersion;restartedDedicatedChrome=$false;targetUrl='';autoStateBefore=$null;pollResult=$null;error='';at=(Get-Date).ToString('o')}
  $ws=$null
  try{
    $result.restartedDedicatedChrome=[bool](Ensure-DebugChrome)
    $deadline=(Get-Date).AddSeconds(20)
    $targets=@()
    do{
      try{$targets=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3)}catch{$targets=@()}
      if(@($targets|Where-Object{($_.type -eq 'service_worker' -or $_.type -eq 'background_page') -and $_.webSocketDebuggerUrl}).Count -gt 0){break}
      Start-Sleep -Milliseconds 500
    }while((Get-Date)-lt $deadline)
    $workers=@($targets|Where-Object{($_.type -eq 'service_worker' -or $_.type -eq 'background_page') -and $_.webSocketDebuggerUrl})
    if($workers.Count -lt 1){throw 'EXTENSION_SERVICE_WORKER_TARGET_NOT_FOUND'}
    $matched=$false
    foreach($target in $workers){
      $candidate=$null
      try{
        $candidate=New-Object System.Net.WebSockets.ClientWebSocket
        $candidate.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $seq=0
        [void](Send-Cdp $candidate ([ref]$seq) 'Runtime.enable' @{})
        $probe=Eval-Cdp $candidate ([ref]$seq) "typeof pollReadyTasks === 'function'"
        if(-not [bool]$probe){$candidate.Dispose();continue}
        $matched=$true;$ws=$candidate;$result.targetUrl=[string]$target.url
        $result.autoStateBefore=Eval-Cdp $ws ([ref]$seq) "(async()=>{try{return typeof getAutoState==='function'?await getAutoState():null}catch(e){return {error:String(e&&e.message||e)}}})()"
        $result.pollResult=Eval-Cdp $ws ([ref]$seq) "(async()=>{try{return await pollReadyTasks('cdp_manual')}catch(e){return {ok:false,error:String(e&&e.message||e)}}})()"
        $result.ok=[bool]$result.pollResult.ok
        if(-not $result.ok -and -not $result.pollResult.error){$result.error='BRIDGE_AUTO_POLL_NOT_OK'}
        break
      }catch{if($candidate){try{$candidate.Dispose()}catch{}}}
    }
    if(-not $matched){throw 'NOTEBOOKLM_BRIDGE_SERVICE_WORKER_NOT_FOUND'}
  }catch{$result.error=$_.Exception.Message}
  finally{if($ws){try{$ws.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o')}
  $result|ConvertTo-Json -Depth 20 -Compress
  if($result.ok){exit 0}else{exit 2}
}

$cut=(Get-Date).AddHours(-1*[Math]::Max(1,[Math]::Min(168,$Hours)))
$limit=[Math]::Max(1,[Math]::Min(300,$MaxItems))
$exts=@('.mp3','.m4a','.wav','.ogg','.aac','.flac','.mp4','.webm','.mov','.pdf','.pptx','.xlsx','.csv','.png','.jpg','.jpeg','.webp','.docx','.txt','.json','.zip')
function Expand-EnvPath([string]$Value){if(-not $Value){return ''};try{return [Environment]::ExpandEnvironmentVariables($Value)}catch{return $Value}}
function Add-Candidate([System.Collections.Generic.List[object]]$List,[string]$Path,[string]$Source,[string]$Profile=''){
  $expanded=Expand-EnvPath $Path;if(-not $expanded){return};try{$full=[IO.Path]::GetFullPath($expanded)}catch{return}
  if(-not($List|Where-Object{[string]$_.path -ieq $full}|Select-Object -First 1)){$List.Add([pscustomobject]@{path=$full;source=$Source;profile=$Profile})}
}
$candidates=New-Object 'System.Collections.Generic.List[object]'
Add-Candidate $candidates (Join-Path $env:USERPROFILE 'Downloads') 'USERPROFILE_DOWNLOADS'
try{$shellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders';$downloadsGuid='{374DE290-123F-4565-9164-39C4925E467B}';$shell=(Get-ItemProperty -Path $shellKey -Name $downloadsGuid -ErrorAction Stop).$downloadsGuid;Add-Candidate $candidates ([string]$shell) 'WINDOWS_KNOWN_FOLDER_DOWNLOADS'}catch{}
$chromeUserData=$userData
$preferenceFiles=@();if(Test-Path -LiteralPath $chromeUserData -PathType Container){$preferenceFiles=@(Get-ChildItem -LiteralPath $chromeUserData -Filter 'Preferences' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 40)}
$profiles=@();foreach($pref in $preferenceFiles){try{$json=Get-Content -LiteralPath $pref.FullName -Raw -Encoding UTF8|ConvertFrom-Json;$profileName=Split-Path $pref.DirectoryName -Leaf;$downloadDir=[string]$json.download.default_directory;$saveDir=[string]$json.savefile.default_directory;if($downloadDir){Add-Candidate $candidates $downloadDir 'CHROME_PREFERENCES_DOWNLOAD_DEFAULT' $profileName};if($saveDir){Add-Candidate $candidates $saveDir 'CHROME_PREFERENCES_SAVEFILE_DEFAULT' $profileName};$profiles += [ordered]@{profile=$profileName;preferences=$pref.FullName;downloadDefault=$downloadDir;savefileDefault=$saveDir}}catch{$profiles += [ordered]@{profile=(Split-Path $pref.DirectoryName -Leaf);preferences=$pref.FullName;parseError=$_.Exception.Message}}}
$items=@();$checked=@();foreach($candidate in $candidates){$exists=Test-Path -LiteralPath $candidate.path -PathType Container;$checked += [ordered]@{path=$candidate.path;source=$candidate.source;profile=$candidate.profile;exists=[bool]$exists};if(-not $exists){continue};foreach($file in @(Get-ChildItem -LiteralPath $candidate.path -File -ErrorAction SilentlyContinue)){if($file.LastWriteTime -lt $cut -or $file.Length -le 0){continue};if($file.Name -like '*.crdownload' -or $file.Name -like '*.tmp'){continue};if($exts -notcontains $file.Extension.ToLowerInvariant()){continue};$items += [ordered]@{name=$file.Name;extension=$file.Extension.ToLowerInvariant();bytes=[int64]$file.Length;lastWrite=$file.LastWriteTime.ToString('o');fullName=$file.FullName;directory=$candidate.path;directorySource=$candidate.source;chromeProfile=$candidate.profile}}}
$items=@($items|Sort-Object {[DateTime]$_.lastWrite} -Descending|Group-Object fullName|ForEach-Object{$_.Group|Select-Object -First 1}|Select-Object -First $limit)
[ordered]@{ok=$true;action='INSPECT_RECENT_NOTEBOOKLM_DOWNLOADS_CONFIGURED_PATHS';scriptVersion=$scriptVersion;hours=$Hours;cut=$cut.ToString('o');chromeUserData=$chromeUserData;checkedDirectories=$checked;chromeProfiles=$profiles;count=@($items).Count;items=$items;genericFilesystemScan=$false;readOnly=$true;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
