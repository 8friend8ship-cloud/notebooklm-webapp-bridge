param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$HostVersion='1.2.9'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$LogRoot=Join-Path $Root 'Logs'
$ResultRoot=Join-Path $Root 'CommandResults'
$WrapperFile=Join-Path $Root 'HomeDesignAsyncJobWrapper.ps1'
New-Item -ItemType Directory -Force -Path $LogRoot,$ResultRoot|Out-Null
$LogFile=Join-Path $LogRoot ('command_host_'+(Get-Date -Format 'yyyyMMdd')+'.log')

function Log([string]$Message){Add-Content -LiteralPath $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8}
function Kill-Tree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function Quote-Args([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function Write-JsonAtomic([string]$Path,$Object){$tmp=$Path+'.tmp';$Object|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Get-Value($Object,[string[]]$Names){if(-not $Object){return $null};foreach($name in $Names){$prop=$Object.PSObject.Properties[$name];if($prop -and $null -ne $prop.Value -and [string]$prop.Value -ne ''){return $prop.Value}};return $null}
function Safe-TaskId([string]$TaskId){if($TaskId -notmatch '^[A-Za-z0-9_.-]{1,180}$'){throw 'unsafe taskId'};return $TaskId}

$wrapper=@'
param(
  [Parameter(Mandatory=$true)][string]$ScriptPath,
  [Parameter(Mandatory=$true)][string]$ArgsPath,
  [Parameter(Mandatory=$true)][string]$ResultPath,
  [int]$TimeoutSeconds=600
)
$ErrorActionPreference='Continue'
if($TimeoutSeconds -lt 30){$TimeoutSeconds=30};if($TimeoutSeconds -gt 1800){$TimeoutSeconds=1800}
function Quote-Args([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function Kill-Tree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
$argsList=@();if(Test-Path -LiteralPath $ArgsPath){try{$loaded=Get-Content -LiteralPath $ArgsPath -Raw -Encoding UTF8|ConvertFrom-Json;if($null -ne $loaded){$argsList=@($loaded)}}catch{}}
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
$psi.Arguments=Quote-Args (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath)+@($argsList))
$proc=New-Object Diagnostics.Process;$proc.StartInfo=$psi;[void]$proc.Start()
$outTask=$proc.StandardOutput.ReadToEndAsync();$errTask=$proc.StandardError.ReadToEndAsync();$finished=$proc.WaitForExit($TimeoutSeconds*1000)
$timedOut=$false
if(-not $finished){$timedOut=$true;$childId=$proc.Id;Kill-Tree -ProcessId $childId;try{[void]$proc.WaitForExit(5000)}catch{}}
$stdout='';$stderr='';if($outTask.IsCompleted){try{$stdout=$outTask.Result}catch{}}else{$stdout='[stdout stream did not close before timeout]'};if($errTask.IsCompleted){try{$stderr=$errTask.Result}catch{}}else{$stderr='[stderr stream did not close before timeout]'}
$exitCode=124;if(-not $timedOut){try{$exitCode=$proc.ExitCode}catch{$exitCode=1}}
$result=[ordered]@{ok=($exitCode -eq 0 -and -not $timedOut);exitCode=$exitCode;timedOut=$timedOut;timeoutSeconds=$TimeoutSeconds;stdout=([string]$stdout).Trim();stderr=([string]$stderr).Trim();completedAt=(Get-Date).ToString('o')}
$tmp=$ResultPath+'.tmp';$result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $ResultPath -Force
'@
Set-Content -LiteralPath $WrapperFile -Value $wrapper -Encoding UTF8

function Find-HeaderEnd([byte[]]$Bytes){for($i=0;$i -le $Bytes.Length-4;$i++){if($Bytes[$i]-eq 13 -and $Bytes[$i+1]-eq 10 -and $Bytes[$i+2]-eq 13 -and $Bytes[$i+3]-eq 10){return $i}};return -1}
function Read-HttpRequest([Net.Sockets.NetworkStream]$Stream){
  $ms=New-Object IO.MemoryStream;$buf=New-Object byte[] 8192;$headerEnd=-1
  while($headerEnd -lt 0){$n=$Stream.Read($buf,0,$buf.Length);if($n -le 0){throw 'client closed before headers'};$ms.Write($buf,0,$n);if($ms.Length -gt 1048576){throw 'request headers too large'};$headerEnd=Find-HeaderEnd $ms.ToArray()}
  $all=$ms.ToArray();$headerText=[Text.Encoding]::ASCII.GetString($all,0,$headerEnd);$lines=$headerText -split "`r`n";$parts=$lines[0] -split ' ';if($parts.Count -lt 2){throw 'invalid request line'}
  $headers=@{};if($lines.Count -gt 1){foreach($line in $lines[1..($lines.Count-1)]){if($line -match '^([^:]+):\s*(.*)$'){$headers[$matches[1].Trim().ToLowerInvariant()]=$matches[2].Trim()}}}
  $contentLength=0;if($headers.ContainsKey('content-length')){[void][int]::TryParse([string]$headers['content-length'],[ref]$contentLength)};if($contentLength -gt 10485760){throw 'request body too large'}
  $bodyStart=$headerEnd+4;while(($ms.Length-$bodyStart) -lt $contentLength){$n=$Stream.Read($buf,0,$buf.Length);if($n -le 0){break};$ms.Write($buf,0,$n)}
  $all=$ms.ToArray();$available=[Math]::Max(0,[Math]::Min($contentLength,$all.Length-$bodyStart));$body='';if($available -gt 0){$body=[Text.Encoding]::UTF8.GetString($all,$bodyStart,$available)}
  return [pscustomobject]@{method=[string]$parts[0];path=[string]$parts[1];headers=$headers;body=$body}
}
function Send-HttpJson([Net.Sockets.NetworkStream]$Stream,$Object,[int]$Status=200){
  $json=$Object|ConvertTo-Json -Depth 30 -Compress;$body=[Text.Encoding]::UTF8.GetBytes($json)
  $reason=if($Status -eq 200){'OK'}elseif($Status -eq 404){'Not Found'}elseif($Status -eq 409){'Conflict'}else{'Internal Server Error'}
  $head="HTTP/1.1 $Status $reason`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($body.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Headers: Content-Type`r`nAccess-Control-Allow-Methods: GET,POST,OPTIONS`r`nConnection: close`r`n`r`n"
  $hb=[Text.Encoding]::ASCII.GetBytes($head);$Stream.Write($hb,0,$hb.Length);if($body.Length){$Stream.Write($body,0,$body.Length)};$Stream.Flush()
}
function Query-TaskId([string]$Path){if($Path -match '^/result\?taskId=(.+)$'){return [Uri]::UnescapeDataString([string]$matches[1])};return ''}

$AllowRules=@(
  [pscustomobject]@{repo='8friend8ship-cloud/animation';branch='codex/video-promo-agent-workflow-20260823';scripts=@('tools/Run-AnimationTestDeploymentE2E.ps1','tools/Recover-AnimationRuntime-Lineage.ps1','tools/Recover-AnimationVercel-Lineage.ps1','tools/Sync-AnimationVideoAgentsToExistingScript.ps1','tools/Render-VideoProductionManifest.ps1','tools/Run-VideoFrameQA.ps1','tools/Run-AgentDashboardPromoProductionE2E.ps1')},
  [pscustomobject]@{repo='8friend8ship-cloud/notebooklm-webapp-bridge';branch='main';scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1','local-agent/governor/RunChromeGovernorReadbackV2.ps1','local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1','local-agent/governor/InspectRecentNotebookLMDownloads.ps1','local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1','local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1','local-agent/capture/ManageChromeExtensionArtifacts.ps1','local-agent/capture/Setup-ChromeExtensionCaptureBridge.ps1','local-agent/governor/ManagedExtensionAutopilotV2.ps1','local-agent/governor/ManagedExtensionExactTargetLauncher.ps1','local-agent/governor/Run-ExactTargetNotebookLMRegression.ps1','local-agent/governor/Sync-CentralLearningQaAppsScript.ps1','local-agent/governor/Run-GeminiWebLearningQa.ps1','local-agent/governor/Inspect-FlowApprovedAccountCredits.ps1')},
  [pscustomobject]@{repo='8friend8ship-cloud/contents-os-git';branch='main';scripts=@('tools/Switch-ContentOS-VercelGit.ps1','tools/Repair-ContentOS-DriveCacheAppsScript.ps1')}
)

function Start-AsyncTask($Task){
  $taskId=Safe-TaskId ([string](Get-Value $Task @('taskId','TASK_ID')));$taskDir=Join-Path $ResultRoot $taskId;New-Item -ItemType Directory -Force -Path $taskDir|Out-Null
  $resultPath=Join-Path $taskDir 'result.json';$statusPath=Join-Path $taskDir 'status.json'
  $existingResult=Read-Json $resultPath;if($existingResult){return [ordered]@{ok=$true;state='DONE';taskId=$taskId;result=$existingResult;hostVersion=$HostVersion}}
  $existingStatus=Read-Json $statusPath;if($existingStatus -and $existingStatus.wrapperPid){$p=Get-Process -Id ([int]$existingStatus.wrapperPid) -ErrorAction SilentlyContinue;if($p){return [ordered]@{ok=$true;state='RUNNING';taskId=$taskId;startedAt=$existingStatus.startedAt;hostVersion=$HostVersion}}}
  $taskType=[string](Get-Value $Task @('taskType','TASK_TYPE'));if($taskType -ne 'LOCAL_POWERSHELL'){throw 'taskType not allowed'}
  $sourceText=[string](Get-Value $Task @('sourceText','SOURCE_TEXT'));$spec=$sourceText|ConvertFrom-Json
  $rule=$AllowRules|Where-Object{[string]$_.repo -eq [string]$spec.repo -and [string]$_.branch -eq [string]$spec.branch}|Select-Object -First 1;if(-not $rule){throw 'repo/branch not allowlisted'}
  $safeScript=[string]$spec.script;if($safeScript -match '\.\.' -or $safeScript.StartsWith('/')){throw 'unsafe script path'};if(@($rule.scripts) -notcontains $safeScript){throw 'script not allowlisted'}
  $rawUrl="https://raw.githubusercontent.com/$($rule.repo)/$($rule.branch)/$safeScript";$localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));Invoke-WebRequest -UseBasicParsing -Uri ($rawUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $localScript -TimeoutSec 8
  $argsList=@();if($spec.args){foreach($argProp in $spec.args.PSObject.Properties){$name=[string]$argProp.Name;if($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$'){throw "unsafe arg name: $name"};if($argProp.Value -is [bool]){if([bool]$argProp.Value){$argsList+="-$name"};continue};$argsList+="-$name";$argsList+=[string]$argProp.Value}}
  $argsPath=Join-Path $taskDir 'args.json';ConvertTo-Json -InputObject @($argsList) -Depth 10|Set-Content -LiteralPath $argsPath -Encoding UTF8
  $timeout=600;$rawTimeout=Get-Value $Task @('timeoutSeconds','TIMEOUT_SECONDS','timeout_seconds');if($rawTimeout){$parsed=0;if([int]::TryParse([string]$rawTimeout,[ref]$parsed) -and $parsed -gt 0){$timeout=$parsed}};if($timeout -lt 30){$timeout=30};if($timeout -gt 1800){$timeout=1800}
  Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.Arguments=Quote-Args @('-NoProfile','-ExecutionPolicy','Bypass','-File',$WrapperFile,'-ScriptPath',$localScript,'-ArgsPath',$argsPath,'-ResultPath',$resultPath,'-TimeoutSeconds',[string]$timeout)
  $wrapperProc=[Diagnostics.Process]::Start($psi);$status=[ordered]@{taskId=$taskId;state='RUNNING';wrapperPid=$wrapperProc.Id;startedAt=(Get-Date).ToString('o');timeoutSeconds=$timeout;script=$safeScript;hostVersion=$HostVersion};Write-JsonAtomic $statusPath $status
  Log "ACCEPT task=$taskId wrapperPid=$($wrapperProc.Id) timeoutSec=$timeout script=$safeScript"
  return [ordered]@{ok=$true;state='STARTED';taskId=$taskId;wrapperPid=$wrapperProc.Id;timeoutSeconds=$timeout;hostVersion=$HostVersion;transport='TcpListenerAsync'}
}
function Get-AsyncResult([string]$TaskId){
  $taskId=Safe-TaskId $TaskId;$taskDir=Join-Path $ResultRoot $taskId;$resultPath=Join-Path $taskDir 'result.json';$statusPath=Join-Path $taskDir 'status.json'
  $result=Read-Json $resultPath;if($result){return [ordered]@{ok=$true;state='DONE';taskId=$taskId;result=$result;hostVersion=$HostVersion}}
  $status=Read-Json $statusPath;if(-not $status){return [ordered]@{ok=$true;state='NOT_FOUND';taskId=$taskId;hostVersion=$HostVersion}}
  if($status.wrapperPid){$p=Get-Process -Id ([int]$status.wrapperPid) -ErrorAction SilentlyContinue;if($p){return [ordered]@{ok=$true;state='RUNNING';taskId=$taskId;startedAt=$status.startedAt;timeoutSeconds=$status.timeoutSeconds;hostVersion=$HostVersion}}}
  return [ordered]@{ok=$true;state='ERROR';taskId=$taskId;error='ASYNC_WRAPPER_EXITED_WITHOUT_RESULT';hostVersion=$HostVersion}
}
function Cancel-AsyncTask([string]$TaskId){
  $taskId=Safe-TaskId $TaskId;$taskDir=Join-Path $ResultRoot $taskId;$status=Read-Json (Join-Path $taskDir 'status.json');if($status -and $status.wrapperPid){Kill-Tree -ProcessId ([int]$status.wrapperPid)}
  $result=[ordered]@{ok=$false;exitCode=124;timedOut=$true;canceled=$true;stderr='CANCELED_BY_BRIDGE';completedAt=(Get-Date).ToString('o')};Write-JsonAtomic (Join-Path $taskDir 'result.json') $result;return [ordered]@{ok=$true;state='CANCELED';taskId=$taskId;hostVersion=$HostVersion}
}

$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,8765);$listener.Start();Log "Local command host START tcp://127.0.0.1:8765 v$HostVersion async=true"
try{
  while($true){
    $client=$listener.AcceptTcpClient();$stream=$null
    try{
      $stream=$client.GetStream();$stream.ReadTimeout=15000;$stream.WriteTimeout=15000;$req=Read-HttpRequest $stream
      if($req.method -eq 'OPTIONS'){Send-HttpJson $stream @{ok=$true;version=$HostVersion;asyncJobs=$true};continue}
      if($req.method -eq 'GET' -and $req.path -eq '/health'){Send-HttpJson $stream @{ok=$true;service='HomeDesign Local Command Host';version=$HostVersion;transport='TcpListenerAsync';asyncJobs=$true;time=(Get-Date).ToString('o')};continue}
      $queryTask=Query-TaskId $req.path;if($req.method -eq 'GET' -and $queryTask){Send-HttpJson $stream (Get-AsyncResult $queryTask);continue}
      if($req.method -eq 'POST' -and $req.path -eq '/run'){$body=$req.body|ConvertFrom-Json;$task=$body.task;if(-not $task){throw 'task missing'};Send-HttpJson $stream (Start-AsyncTask $task);continue}
      if($req.method -eq 'POST' -and $req.path -eq '/cancel'){$body=$req.body|ConvertFrom-Json;Send-HttpJson $stream (Cancel-AsyncTask ([string]$body.taskId));continue}
      Send-HttpJson $stream @{ok=$false;error='NOT_FOUND'} 404
    }catch{$msg=$_.Exception.Message;Log ("ERROR "+$msg);if($stream){try{Send-HttpJson $stream @{ok=$false;error=$msg;version=$HostVersion;at=(Get-Date).ToString('o')} 500}catch{}}}
    finally{if($stream){try{$stream.Dispose()}catch{}};if($client){try{$client.Close()}catch{}}}
  }
}finally{try{$listener.Stop()}catch{};Log 'Local command host STOP'}
