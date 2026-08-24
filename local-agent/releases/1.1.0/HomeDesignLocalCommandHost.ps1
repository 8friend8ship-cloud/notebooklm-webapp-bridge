param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$LogRoot = Join-Path $Root 'Logs'
$ResultRoot = Join-Path $Root 'CommandResults'
New-Item -ItemType Directory -Force -Path $LogRoot,$ResultRoot | Out-Null
$LogFile = Join-Path $LogRoot ('command_host_' + (Get-Date -Format 'yyyyMMdd') + '.log')
function Log([string]$m){Add-Content -LiteralPath $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
function Send-Json($ctx,$obj,[int]$status=200){$json=$obj|ConvertTo-Json -Depth 20 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json);$ctx.Response.StatusCode=$status;$ctx.Response.ContentType='application/json; charset=utf-8';$ctx.Response.ContentLength64=$bytes.Length;$ctx.Response.OutputStream.Write($bytes,0,$bytes.Length);$ctx.Response.OutputStream.Close()}
function Read-Body($req){$sr=New-Object IO.StreamReader($req.InputStream,$req.ContentEncoding);try{return $sr.ReadToEnd()}finally{$sr.Dispose()}}
function Invoke-Native([string]$file,[string[]]$args){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$file;$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true;$psi.Arguments=($args|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ';$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$out=$p.StandardOutput.ReadToEnd();$err=$p.StandardError.ReadToEnd();$p.WaitForExit();return[pscustomobject]@{exitCode=$p.ExitCode;stdout=$out;stderr=$err}}

$AllowedRepo='8friend8ship-cloud/animation'
$AllowedBranch='codex/video-promo-agent-workflow-20260823'
$AllowedScripts=@(
  'tools/Run-AnimationTestDeploymentE2E.ps1',
  'tools/Recover-AnimationRuntime-Lineage.ps1',
  'tools/Recover-AnimationVercel-Lineage.ps1',
  'tools/Sync-AnimationVideoAgentsToExistingScript.ps1',
  'tools/Render-VideoProductionManifest.ps1',
  'tools/Run-VideoFrameQA.ps1'
)
$listener=New-Object Net.HttpListener;$listener.Prefixes.Add('http://127.0.0.1:8765/');$listener.Start();Log 'Local command host START 127.0.0.1:8765 v1.1.1'
while($listener.IsListening){$ctx=$null;try{$ctx=$listener.GetContext();$path=$ctx.Request.Url.AbsolutePath;if($ctx.Request.HttpMethod -eq 'GET' -and $path -eq '/health'){Send-Json $ctx @{ok=$true;service='HomeDesign Local Command Host';version='1.1.1';time=(Get-Date).ToString('o')};continue};if($ctx.Request.HttpMethod -ne 'POST' -or $path -ne '/run'){Send-Json $ctx @{ok=$false;error='NOT_FOUND'} 404;continue};$raw=Read-Body $ctx.Request;$body=$raw|ConvertFrom-Json;$task=$body.task;if(-not $task){throw 'task missing'};if([string]$task.taskType -ne 'LOCAL_POWERSHELL'){throw 'taskType not allowed'};$spec=([string]$task.sourceText)|ConvertFrom-Json;if([string]$spec.repo -ne $AllowedRepo){throw 'repo not allowed'};if([string]$spec.branch -ne $AllowedBranch){throw 'branch not allowed'};if($AllowedScripts -notcontains [string]$spec.script){throw 'script not allowlisted'};$safeScript=[string]$spec.script;if($safeScript -match '\.\.' -or $safeScript.StartsWith('/')){throw 'unsafe script path'};$rawUrl="https://raw.githubusercontent.com/$AllowedRepo/$AllowedBranch/$safeScript";$taskDir=Join-Path $ResultRoot ([string]$task.taskId);New-Item -ItemType Directory -Force -Path $taskDir|Out-Null;$localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $localScript -TimeoutSec 60;$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$localScript);if($spec.args){foreach($p in $spec.args.PSObject.Properties){$name=[string]$p.Name;if($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$'){throw "unsafe arg name: $name"};$args+="-$name";$args+=[string]$p.Value}};Log ("RUN task="+$task.taskId+" script="+$safeScript);$r=Invoke-Native 'powershell.exe' $args;$result=[ordered]@{ok=($r.exitCode -eq 0);taskId=[string]$task.taskId;script=$safeScript;exitCode=$r.exitCode;stdout=([string]$r.stdout).Trim();stderr=([string]$r.stderr).Trim();at=(Get-Date).ToString('o')};$result|ConvertTo-Json -Depth 20|Set-Content (Join-Path $taskDir 'result.json') -Encoding UTF8;Log ("DONE task="+$task.taskId+" exit="+$r.exitCode);Send-Json $ctx $result $(if($r.exitCode -eq 0){200}else{500})}catch{$msg=$_.Exception.Message;Log ("ERROR "+$msg);if($ctx){try{Send-Json $ctx @{ok=$false;error=$msg;at=(Get-Date).ToString('o')} 500}catch{}}}}
