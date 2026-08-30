param([int]$StartPort=9222,[int]$EndPort=9230)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$result=[ordered]@{ok=$true;action='NOTEBOOKLM_CDP_PORT_TAB_INVENTORY_V1';startedAt=(Get-Date).ToString('o');ports=@();chromeProcesses=@();normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;error=''}
try{
  for($p=$StartPort;$p -le $EndPort;$p++){
    $entry=[ordered]@{port=$p;ready=$false;browser='';webSocketDebuggerUrl='';tabs=@();error=''}
    try{
      $v=Invoke-RestMethod -Uri ("http://127.0.0.1:$p/json/version") -TimeoutSec 2
      $entry.ready=[bool]$v.webSocketDebuggerUrl;$entry.browser=[string]$v.Browser;$entry.webSocketDebuggerUrl=[string]$v.webSocketDebuggerUrl
      if($entry.ready){
        $tabs=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$p/json/list") -TimeoutSec 3)
        foreach($t in $tabs){
          $url=[string]$t.url;$id='';if($url -match '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)'){$id=[string]$Matches[1]}
          $entry.tabs += [ordered]@{type=[string]$t.type;title=[string]$t.title;url=$url;notebookId=$id;webSocketDebuggerUrl=[string]$t.webSocketDebuggerUrl}
        }
      }
    }catch{$entry.error=$_.Exception.Message}
    $result.ports += $entry
  }
  try{
    foreach($proc in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue)){
      if(-not $proc.CommandLine){continue}
      $cmd=[string]$proc.CommandLine
      if($cmd -match '--remote-debugging-port=(\d+)'){
        $port=[int]$Matches[1];$ud='';if($cmd -match '--user-data-dir=(?:"([^"]+)"|([^\s]+))'){$ud=$(if($Matches[1]){$Matches[1]}else{$Matches[2]})}
        $result.chromeProcesses += [ordered]@{pid=[int]$proc.ProcessId;remoteDebuggingPort=$port;userDataDir=$ud;commandLine=$cmd}
      }
    }
  }catch{}
}catch{$result.ok=$false;$result.error=$_.Exception.Message}
$result.completedAt=(Get-Date).ToString('o')
$result|ConvertTo-Json -Depth 30 -Compress
if($result.ok){exit 0}else{exit 2}
