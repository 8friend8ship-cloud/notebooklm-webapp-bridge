param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.143-image-task203-submitdiag'
$TaskId='CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01'
$HostBase='http://127.0.0.1:8765'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$ResultRoot=Join-Path $Root 'CommandResults'
$TaskDir=Join-Path $ResultRoot $TaskId
$Receipt='IMAGE_TASK203_HOST130_SUBMIT_DIAG_1.1.143.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function Health{try{return Invoke-RestMethod -Method Get -Uri ($HostBase+'/health') -TimeoutSec 5}catch{return $null}}
function ReadText([string]$p){if(Test-Path -LiteralPath $p -PathType Leaf){try{return (Get-Content -LiteralPath $p -Raw -Encoding UTF8)}catch{}};return ''}
function TailLog(){try{$f=Get-ChildItem -LiteralPath (Join-Path $Root 'Logs') -Filter 'command_host_*.log' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($f){return (@(Get-Content -LiteralPath $f.FullName -Tail 40 -Encoding UTF8)-join "`n")}}catch{};return ''}
function PostRawJson([string]$uri,[string]$json){
  $out=[ordered]@{ok=$false;statusCode=0;body='';exception=''}
  try{$resp=Invoke-WebRequest -UseBasicParsing -Method Post -Uri $uri -ContentType 'application/json' -Body $json -TimeoutSec 25;$out.statusCode=[int]$resp.StatusCode;$out.body=[string]$resp.Content;$out.ok=$true}
  catch{$out.exception=$_.Exception.Message;try{$response=$_.Exception.Response;if($response){$out.statusCode=[int]$response.StatusCode;$sr=New-Object IO.StreamReader($response.GetResponseStream());try{$out.body=$sr.ReadToEnd()}finally{$sr.Dispose()}}}catch{}}
  return [pscustomobject]$out
}
$r=[ordered]@{ok=$false;action='IMAGE_TASK203_HOST130_SUBMIT_DIAG_AND_RUN';version=$Version;taskId=$TaskId;health=$null;beforeStatus='';beforeResult='';beforeFiles=@();beforeLogTail='';submitStatusCode=0;submitBody='';submitException='';afterStatus='';afterResult='';afterFiles=@();afterLogTail='';poll=$null;stage='START';error='';duplicateTaskCreated=$false;newAppsScriptProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;startedAt=(Get-Date).ToString('o')}
try{
  $r.health=Health
  if(-not$r.health -or -not[bool]$r.health.ok -or [string]$r.health.version-ne'1.3.0'){throw('HOST130_NOT_READY:'+($r.health|ConvertTo-Json -Compress -Depth 10))}
  $r.stage='CAPTURE_BEFORE'
  $r.beforeStatus=ReadText (Join-Path $TaskDir 'status.json')
  $r.beforeResult=ReadText (Join-Path $TaskDir 'result.json')
  if(Test-Path -LiteralPath $TaskDir){$r.beforeFiles=@(Get-ChildItem -LiteralPath $TaskDir -File -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{name=$_.Name;length=$_.Length;modified=$_.LastWriteTime.ToString('o')}})}
  $r.beforeLogTail=TailLog
  $r.stage='SUBMIT_SAME_TASK_ID'
  $sourceText=(@{repo='8friend8ship-cloud/contents-os-git';branch='main';script='tools/Repair-ContentOS-DriveCacheAppsScript.ps1';args=@{}}|ConvertTo-Json -Compress)
  $task=[ordered]@{taskId=$TaskId;taskType='LOCAL_POWERSHELL';sourceText=$sourceText;timeoutSeconds=600}
  $body=@{task=$task}|ConvertTo-Json -Depth 20 -Compress
  $submit=PostRawJson ($HostBase+'/run') $body
  $r.submitStatusCode=$submit.statusCode;$r.submitBody=$submit.body;$r.submitException=$submit.exception
  $r.stage='CAPTURE_AFTER_SUBMIT'
  Start-Sleep -Milliseconds 500
  $r.afterStatus=ReadText (Join-Path $TaskDir 'status.json')
  $r.afterResult=ReadText (Join-Path $TaskDir 'result.json')
  if(Test-Path -LiteralPath $TaskDir){$r.afterFiles=@(Get-ChildItem -LiteralPath $TaskDir -File -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{name=$_.Name;length=$_.Length;modified=$_.LastWriteTime.ToString('o')}})}
  $r.afterLogTail=TailLog
  if($submit.statusCode-ne200){throw('HOST_RUN_HTTP_'+$submit.statusCode+':'+$submit.body)}
  $parsed=$null;try{$parsed=$submit.body|ConvertFrom-Json}catch{}
  if(-not$parsed -or -not[bool]$parsed.ok){throw('HOST_RUN_BAD_RESPONSE:'+ $submit.body)}
  $r.stage='POLL_SAME_TASK_ID'
  for($i=0;$i-lt330;$i++){
    try{$p=Invoke-RestMethod -Method Get -Uri ($HostBase+'/result?taskId='+[Uri]::EscapeDataString($TaskId)) -TimeoutSec 8;$r.poll=$p;if(@('DONE','ERROR') -contains [string]$p.state){break}}catch{$r.error='POLL_HTTP:'+ $_.Exception.Message;break}
    Start-Sleep -Seconds 2
  }
  if(-not$r.poll){throw('TASK203_POLL_EMPTY')}
  if([string]$r.poll.state-ne'DONE'){throw('TASK203_POLL_STATE_'+[string]$r.poll.state+':'+[string]$r.poll.error)}
  if(-not[bool]$r.poll.result.ok){throw('TASK203_SCRIPT_FAILED:'+ [string]$r.poll.result.stderr)}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}