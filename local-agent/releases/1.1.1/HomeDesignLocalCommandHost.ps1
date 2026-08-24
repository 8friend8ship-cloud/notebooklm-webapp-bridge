param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$HostVersion='1.1.1'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$LogRoot = Join-Path $Root 'Logs'
$ResultRoot = Join-Path $Root 'CommandResults'
New-Item -ItemType Directory -Force -Path $LogRoot,$ResultRoot | Out-Null
$LogFile = Join-Path $LogRoot ('command_host_' + (Get-Date -Format 'yyyyMMdd') + '.log')

function Log([string]$m){Add-Content -LiteralPath $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
function Send-Json($ctx,$obj,[int]$status=200){
  $json=$obj|ConvertTo-Json -Depth 20 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $ctx.Response.StatusCode=$status;$ctx.Response.ContentType='application/json; charset=utf-8';$ctx.Response.ContentLength64=$bytes.Length
  $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length);$ctx.Response.OutputStream.Close()
}
function Read-Body($req){$sr=New-Object IO.StreamReader($req.InputStream,$req.ContentEncoding);try{return $sr.ReadToEnd()}finally{$sr.Dispose()}}
function Invoke-Native([string]$file,[string[]]$args){
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$file;$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
  $psi.Arguments = ($args|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' '
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$out=$p.StandardOutput.ReadToEnd();$err=$p.StandardError.ReadToEnd();$p.WaitForExit()
  return [pscustomobject]@{exitCode=$p.ExitCode;stdout=$out;stderr=$err}
}

$AllowRules=@(
  [pscustomobject]@{
    repo='8friend8ship-cloud/animation';branch='codex/video-promo-agent-workflow-20260823';scripts=@(
      'tools/Run-AnimationTestDeploymentE2E.ps1','tools/Recover-AnimationRuntime-Lineage.ps1','tools/Recover-AnimationVercel-Lineage.ps1','tools/Sync-AnimationVideoAgentsToExistingScript.ps1'
    )
  },
  [pscustomobject]@{
    repo='8friend8ship-cloud/notebooklm-webapp-bridge';branch='main';scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1')
  }
)

$listener=New-Object Net.HttpListener;$listener.Prefixes.Add('http://127.0.0.1:8765/');$listener.Start();Log "Local command host START 127.0.0.1:8765 v$HostVersion"
while($listener.IsListening){
  $ctx=$null
  try{
    $ctx=$listener.GetContext();$path=$ctx.Request.Url.AbsolutePath
    if($ctx.Request.HttpMethod -eq 'GET' -and $path -eq '/health'){Send-Json $ctx @{ok=$true;service='HomeDesign Local Command Host';version=$HostVersion;time=(Get-Date).ToString('o')};continue}
    if($ctx.Request.HttpMethod -ne 'POST' -or $path -ne '/run'){Send-Json $ctx @{ok=$false;error='NOT_FOUND'} 404;continue}
    $raw=Read-Body $ctx.Request;$body=$raw|ConvertFrom-Json;$task=$body.task
    if(-not $task){throw 'task missing'}
    if([string]$task.taskType -ne 'LOCAL_POWERSHELL'){throw 'taskType not allowed'}
    $spec=([string]$task.sourceText)|ConvertFrom-Json
    $rule=$AllowRules|Where-Object{[string]$_.repo -eq [string]$spec.repo -and [string]$_.branch -eq [string]$spec.branch}|Select-Object -First 1
    if(-not $rule){throw 'repo/branch not allowlisted'}
    $safeScript=[string]$spec.script
    if($safeScript -match '\.\.' -or $safeScript.StartsWith('/')){throw 'unsafe script path'}
    if(@($rule.scripts) -notcontains $safeScript){throw 'script not allowlisted'}
    $rawUrl="https://raw.githubusercontent.com/$($rule.repo)/$($rule.branch)/$safeScript"
    $taskDir=Join-Path $ResultRoot ([string]$task.taskId);New-Item -ItemType Directory -Force -Path $taskDir|Out-Null
    $localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $localScript -TimeoutSec 60
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$localScript)
    if($spec.args){foreach($p in $spec.args.PSObject.Properties){$name=[string]$p.Name;if($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$'){throw "unsafe arg name: $name"};$args+="-$name";$args+=[string]$p.Value}}
    Log ("RUN task="+$task.taskId+" repo="+$rule.repo+" script="+$safeScript)
    $r=Invoke-Native 'powershell.exe' $args
    $result=[ordered]@{ok=($r.exitCode -eq 0);taskId=[string]$task.taskId;script=$safeScript;exitCode=$r.exitCode;stdout=([string]$r.stdout).Trim();stderr=([string]$r.stderr).Trim();at=(Get-Date).ToString('o')}
    $result|ConvertTo-Json -Depth 20|Set-Content (Join-Path $taskDir 'result.json') -Encoding UTF8
    Log ("DONE task="+$task.taskId+" exit="+$r.exitCode);Send-Json $ctx $result $(if($r.exitCode -eq 0){200}else{500})
  }catch{
    $msg=$_.Exception.Message;Log ("ERROR "+$msg);if($ctx){try{Send-Json $ctx @{ok=$false;error=$msg;at=(Get-Date).ToString('o')} 500}catch{}}
  }
}
