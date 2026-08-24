param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$HostVersion='1.1.4'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$LogRoot=Join-Path $Root 'Logs'
$ResultRoot=Join-Path $Root 'CommandResults'
New-Item -ItemType Directory -Force -Path $LogRoot,$ResultRoot|Out-Null
$LogFile=Join-Path $LogRoot ('command_host_'+(Get-Date -Format 'yyyyMMdd')+'.log')

function Log([string]$Message){Add-Content -LiteralPath $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8}
function Kill-Tree([int]$ProcessId){
  try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}
  catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}
}
function Invoke-Native([string]$File,[string[]]$Args,[int]$TimeoutSeconds){
  if($TimeoutSeconds -lt 30){$TimeoutSeconds=30};if($TimeoutSeconds -gt 1800){$TimeoutSeconds=1800}
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$File;$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
  $psi.Arguments=($Args|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' '
  $proc=New-Object Diagnostics.Process;$proc.StartInfo=$psi;[void]$proc.Start()
  $outTask=$proc.StandardOutput.ReadToEndAsync();$errTask=$proc.StandardError.ReadToEndAsync()
  $finished=$proc.WaitForExit($TimeoutSeconds*1000)
  if(-not $finished){
    $processId=$proc.Id;Log "TIMEOUT processId=$processId timeoutSec=$TimeoutSeconds";Kill-Tree -ProcessId $processId
    try{[void]$proc.WaitForExit(5000)}catch{}
    $out='';$err='';try{$out=$outTask.Result}catch{};try{$err=$errTask.Result}catch{}
    return [pscustomobject]@{exitCode=124;stdout=$out;stderr=$err;timedOut=$true;timeoutSeconds=$TimeoutSeconds}
  }
  $proc.WaitForExit()
  return [pscustomobject]@{exitCode=$proc.ExitCode;stdout=$outTask.Result;stderr=$errTask.Result;timedOut=$false;timeoutSeconds=$TimeoutSeconds}
}
function Find-HeaderEnd([byte[]]$Bytes){
  for($i=0;$i -le $Bytes.Length-4;$i++){
    if($Bytes[$i]-eq 13 -and $Bytes[$i+1]-eq 10 -and $Bytes[$i+2]-eq 13 -and $Bytes[$i+3]-eq 10){return $i}
  }
  return -1
}
function Read-HttpRequest([Net.Sockets.NetworkStream]$Stream){
  $ms=New-Object IO.MemoryStream;$buf=New-Object byte[] 8192;$headerEnd=-1
  while($headerEnd -lt 0){
    $n=$Stream.Read($buf,0,$buf.Length);if($n -le 0){throw 'client closed before headers'}
    $ms.Write($buf,0,$n);if($ms.Length -gt 1048576){throw 'request headers too large'}
    $headerEnd=Find-HeaderEnd $ms.ToArray()
  }
  $all=$ms.ToArray();$headerText=[Text.Encoding]::ASCII.GetString($all,0,$headerEnd)
  $lines=$headerText -split "`r`n";$requestLine=$lines[0];$parts=$requestLine -split ' '
  if($parts.Count -lt 2){throw 'invalid request line'}
  $headers=@{}
  foreach($line in $lines[1..($lines.Count-1)]){if($line -match '^([^:]+):\s*(.*)$'){$headers[$matches[1].Trim().ToLowerInvariant()]=$matches[2].Trim()}}
  $contentLength=0;if($headers.ContainsKey('content-length')){[void][int]::TryParse([string]$headers['content-length'],[ref]$contentLength)}
  if($contentLength -gt 10485760){throw 'request body too large'}
  $bodyStart=$headerEnd+4
  while(($ms.Length-$bodyStart) -lt $contentLength){$n=$Stream.Read($buf,0,$buf.Length);if($n -le 0){break};$ms.Write($buf,0,$n)}
  $all=$ms.ToArray();$available=[Math]::Max(0,[Math]::Min($contentLength,$all.Length-$bodyStart));$body=''
  if($available -gt 0){$body=[Text.Encoding]::UTF8.GetString($all,$bodyStart,$available)}
  return [pscustomobject]@{method=[string]$parts[0];path=[string]$parts[1];headers=$headers;body=$body}
}
function Send-HttpJson([Net.Sockets.NetworkStream]$Stream,$Object,[int]$Status=200){
  $json=$Object|ConvertTo-Json -Depth 30 -Compress;$body=[Text.Encoding]::UTF8.GetBytes($json)
  $reason=if($Status -eq 200){'OK'}elseif($Status -eq 404){'Not Found'}elseif($Status -eq 504){'Gateway Timeout'}else{'Internal Server Error'}
  $head="HTTP/1.1 $Status $reason`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($body.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Headers: Content-Type`r`nAccess-Control-Allow-Methods: GET,POST,OPTIONS`r`nConnection: close`r`n`r`n"
  $hb=[Text.Encoding]::ASCII.GetBytes($head);$Stream.Write($hb,0,$hb.Length);if($body.Length){$Stream.Write($body,0,$body.Length)};$Stream.Flush()
}

$AllowRules=@(
  [pscustomobject]@{repo='8friend8ship-cloud/animation';branch='codex/video-promo-agent-workflow-20260823';scripts=@('tools/Run-AnimationTestDeploymentE2E.ps1','tools/Recover-AnimationRuntime-Lineage.ps1','tools/Recover-AnimationVercel-Lineage.ps1','tools/Sync-AnimationVideoAgentsToExistingScript.ps1','tools/Render-VideoProductionManifest.ps1','tools/Run-VideoFrameQA.ps1')},
  [pscustomobject]@{repo='8friend8ship-cloud/notebooklm-webapp-bridge';branch='main';scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1')}
)

$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,8765)
$listener.Start();Log "Local command host START tcp://127.0.0.1:8765 v$HostVersion"
try{
  while($true){
    $client=$listener.AcceptTcpClient();$stream=$null
    try{
      $stream=$client.GetStream();$stream.ReadTimeout=15000;$stream.WriteTimeout=15000;$req=Read-HttpRequest $stream
      if($req.method -eq 'OPTIONS'){Send-HttpJson $stream @{ok=$true;version=$HostVersion};continue}
      if($req.method -eq 'GET' -and $req.path -eq '/health'){Send-HttpJson $stream @{ok=$true;service='HomeDesign Local Command Host';version=$HostVersion;transport='TcpListener';time=(Get-Date).ToString('o')};continue}
      if($req.method -ne 'POST' -or $req.path -ne '/run'){Send-HttpJson $stream @{ok=$false;error='NOT_FOUND'} 404;continue}
      $body=$req.body|ConvertFrom-Json;$task=$body.task;if(-not $task){throw 'task missing'}
      if([string]$task.taskType -ne 'LOCAL_POWERSHELL'){throw 'taskType not allowed'}
      $spec=([string]$task.sourceText)|ConvertFrom-Json
      $rule=$AllowRules|Where-Object{[string]$_.repo -eq [string]$spec.repo -and [string]$_.branch -eq [string]$spec.branch}|Select-Object -First 1
      if(-not $rule){throw 'repo/branch not allowlisted'}
      $safeScript=[string]$spec.script;if($safeScript -match '\.\.' -or $safeScript.StartsWith('/')){throw 'unsafe script path'}
      if(@($rule.scripts) -notcontains $safeScript){throw 'script not allowlisted'}
      $rawUrl="https://raw.githubusercontent.com/$($rule.repo)/$($rule.branch)/$safeScript"
      $taskDir=Join-Path $ResultRoot ([string]$task.taskId);New-Item -ItemType Directory -Force -Path $taskDir|Out-Null
      $localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $localScript -TimeoutSec 60
      $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$localScript)
      if($spec.args){foreach($argProp in $spec.args.PSObject.Properties){$name=[string]$argProp.Name;if($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$'){throw "unsafe arg name: $name"};if($argProp.Value -is [bool]){if([bool]$argProp.Value){$args+="-$name"};continue};$args+="-$name";$args+=[string]$argProp.Value}}
      $timeout=600;if($task.PSObject.Properties.Name -contains 'timeoutSeconds'){$parsedTimeout=0;if([int]::TryParse([string]$task.timeoutSeconds,[ref]$parsedTimeout) -and $parsedTimeout -gt 0){$timeout=$parsedTimeout}}
      if($timeout -lt 30){$timeout=30};if($timeout -gt 1800){$timeout=1800}
      Log ("RUN task="+$task.taskId+" repo="+$rule.repo+" script="+$safeScript+" timeoutSec="+$timeout)
      $r=Invoke-Native 'powershell.exe' $args $timeout
      $result=[ordered]@{ok=($r.exitCode -eq 0);taskId=[string]$task.taskId;script=$safeScript;exitCode=$r.exitCode;timedOut=[bool]$r.timedOut;timeoutSeconds=$r.timeoutSeconds;stdout=([string]$r.stdout).Trim();stderr=([string]$r.stderr).Trim();hostVersion=$HostVersion;transport='TcpListener';at=(Get-Date).ToString('o')}
      $result|ConvertTo-Json -Depth 30|Set-Content (Join-Path $taskDir 'result.json') -Encoding UTF8
      Log ("DONE task="+$task.taskId+" exit="+$r.exitCode+" timedOut="+$r.timedOut)
      if($r.timedOut){Send-HttpJson $stream $result 504}else{Send-HttpJson $stream $result $(if($r.exitCode -eq 0){200}else{500})}
    }catch{
      $msg=$_.Exception.Message;Log ("ERROR "+$msg);if($stream){try{Send-HttpJson $stream @{ok=$false;error=$msg;version=$HostVersion;at=(Get-Date).ToString('o')} 500}catch{}}
    }finally{if($stream){try{$stream.Dispose()}catch{}};if($client){try{$client.Close()}catch{}}}
  }
}finally{try{$listener.Stop()}catch{};Log 'Local command host STOP'}
