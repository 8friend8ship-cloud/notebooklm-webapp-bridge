param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.103'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$TargetNotebookId='8d1eda83-cfe3-4487-b2bc-266a5be3465c'
$TargetUrl='https://notebook.google.com/notebook/'+$TargetNotebookId
$Port=9223
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $Base 'ChromeUserData'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$Delegate=Join-Path $Root 'HomeDesignLocalAgent.1.1.102.ps1'
$DelegateSha='6c72fdde2c9c2a8e68734e2c9da32930d8456330'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Raw([string]$Path){return 'https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
function FetchDelegate{$tmp=$Delegate+'.download';Invoke-WebRequest -UseBasicParsing -Uri (Raw 'local-agent/releases/1.1.102/HomeDesignLocalAgent.ps1') -OutFile $tmp -TimeoutSec 30;$a=(GitBlobSha1 $tmp).ToLowerInvariant();if($a-ne$DelegateSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('DELEGATE_SHA_MISMATCH actual='+$a+' expected='+$DelegateSha)};Move-Item $tmp $Delegate -Force;return 'RAW_VERIFIED'}
function DebugReady{try{$v=Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/version") -TimeoutSec 2;return [bool]$v.webSocketDebuggerUrl}catch{return $false}}
function FindChrome{if(Test-Path -LiteralPath $CftRoot){$x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1;if($x){return [string]$x.FullName}};foreach($c in @((Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))){if($c -and(Test-Path -LiteralPath $c)){return [string]$c}};throw 'CHROME_EXE_NOT_FOUND'}
function DedicatedProcs{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine-and$_.CommandLine-like("*"+$UserData+"*")})}catch{return @()}}
function StartDedicated{if(DebugReady){return 'ALREADY_READY'};foreach($p in @(DedicatedProcs)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}};Start-Sleep -Milliseconds 800;$chrome=FindChrome;$args=@("--remote-debugging-port=$Port",'--remote-allow-origins=*',"--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$TargetUrl);Start-Process -FilePath $chrome -ArgumentList $args|Out-Null;$d=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 400;if(DebugReady){return 'STARTED_DEDICATED'}}while((Get-Date)-lt$d);throw 'CDP_PORT_NOT_READY'}
function FlatTabs{$r=Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 3;$o=$r.Content|ConvertFrom-Json;$a=@();if($o-is[System.Array]){foreach($x in$o){$a+=$x}}elseif($null-ne$o){$a+=$o};return $a}
function Recv($w,[int]$sec){$b=New-Object byte[] 65536;$m=New-Object IO.MemoryStream;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter([Math]::Max(1000,$sec*1000));try{do{$g=New-Object ArraySegment[byte] -ArgumentList @(,$b);$r=$w.ReceiveAsync($g,$c.Token).GetAwaiter().GetResult();if($r.MessageType-eq[System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'};$m.Write($b,0,$r.Count)}while(-not$r.EndOfMessage);return ([Text.Encoding]::UTF8.GetString($m.ToArray())|ConvertFrom-Json)}finally{$c.Dispose();$m.Dispose()}}
function Send($w,[ref]$q,[string]$method,[hashtable]$params=@{}){$q.Value++;$id=$q.Value;$j=@{id=$id;method=$method;params=$params}|ConvertTo-Json -Depth 30 -Compress;$bb=[Text.Encoding]::UTF8.GetBytes($j);$g=New-Object ArraySegment[byte] -ArgumentList @(,$bb);$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000);try{[void]$w.SendAsync($g,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()};while($true){$z=Recv $w 8;if($z.id-eq$id){if($z.error){throw('CDP_'+$method+':'+($z.error|ConvertTo-Json -Compress))};return $z.result}}}
function Connect([string]$wsUrl){$w=New-Object System.Net.WebSockets.ClientWebSocket;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000);try{[void]$w.ConnectAsync([Uri]$wsUrl,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()};return $w}
function EnsureExactTab{
  $start=StartDedicated
  $tabs=@(FlatTabs|Where-Object{[string]$_.type-eq'page'})
  $exact=$tabs|Where-Object{[string]$_.url-eq$TargetUrl}|Select-Object -First 1
  if($exact){return [ordered]@{mode=$start+'+EXACT_PRESENT';url=[string]$exact.url;tabId=[string]$exact.id}}
  if($tabs.Count-gt0){$tab=$tabs|Where-Object{[string]$_.url-like'https://notebook.google.com/*'}|Select-Object -First 1;if(-not$tab){$tab=$tabs|Select-Object -First 1};$w=Connect ([string]$tab.webSocketDebuggerUrl);try{$q=0;[void](Send $w ([ref]$q) 'Page.enable' @{});[void](Send $w ([ref]$q) 'Page.navigate' @{url=$TargetUrl})}finally{$w.Dispose()}}
  else{$v=Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/version") -TimeoutSec 3;$w=Connect ([string]$v.webSocketDebuggerUrl);try{$q=0;[void](Send $w ([ref]$q) 'Target.createTarget' @{url=$TargetUrl})}finally{$w.Dispose()}}
  $d=(Get-Date).AddSeconds(30);do{Start-Sleep -Milliseconds 500;$exact=@(FlatTabs|Where-Object{[string]$_.type-eq'page'-and[string]$_.url-eq$TargetUrl}|Select-Object -First 1);if($exact){return [ordered]@{mode=$start+'+EXACT_NAVIGATED';url=[string]$exact[0].url;tabId=[string]$exact[0].id}}}while((Get-Date)-lt$d)
  throw 'EXACT_NOTEBOOK_TAB_NOT_VERIFIED'
}
function LastJson([string]$Text){$p=$null;foreach($line in @($Text-split"`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 50)){try{$j=$line|ConvertFrom-Json;if($j){$p=$j}}catch{}};return $p}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveCentral([string]$Name,$Object){try{$j=$Object|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$p=Join-Path $d $Name;$j|Set-Content -LiteralPath $p -Encoding UTF8;return $p}}catch{};return ''}
$result=[ordered]@{ok=$false;action='AGENT_1.1.103_EXACT_TAB_THEN_AUDIO_DRIVE';version=$Version;targetNotebookId=$TargetNotebookId;targetUrl=$TargetUrl;startedAt=(Get-Date).ToString('o');tabPreflight=$null;exactTabVerified=$false;delegateFetch='';delegateExit=$null;childAction='';childStage='';childError='';childOk=$false;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;stage='START';error='';centralPath=''}
try{$result.stage='EXACT_TAB_PREFLIGHT';$pf=EnsureExactTab;$result.tabPreflight=$pf;$result.exactTabVerified=([string]$pf.url-eq$TargetUrl);if(-not$result.exactTabVerified){throw 'EXACT_TAB_PREFLIGHT_FAILED'};$result.stage='FETCH_DELEGATE';$result.delegateFetch=FetchDelegate;$result.stage='RUN_DELEGATE';$o=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Delegate 2>&1|Out-String;$result.delegateExit=$LASTEXITCODE;$p=LastJson $o;if(-not$p){throw ('DELEGATE_RESULT_JSON_NOT_FOUND '+$o.Trim())};$result.childAction=[string]$p.action;$result.childStage=[string]$p.stage;$result.childError=[string]$p.error;$result.childOk=[bool]$p.ok;$result.ok=([int]$result.delegateExit-eq0-and$result.childOk);if(-not$result.ok){throw ('DELEGATE_FAILED stage='+$result.childStage+' error='+$result.childError)};$result.stage='DONE'}catch{$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.103_EXACT_TAB_THEN_AUDIO_DRIVE_RESULT.json' $result}
$result|ConvertTo-Json -Depth 80 -Compress
if($result.ok){exit 0}else{exit 2}
