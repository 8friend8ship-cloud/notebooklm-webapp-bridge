param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.138-image-task203'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ChildCommit='6615fd683d547f0eadf50202967a5c3574e9ebf6'
$ChildPath='local-agent/releases/1.1.136-image-task203/HomeDesignLocalAgent.ps1'
$ChildSha='f08f8a586f3405ce9019c370fe504557d03b3b70'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save([string]$name,$o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $name) -Encoding UTF8;try{$c=Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $name) -Encoding UTF8}}catch{}}
$entry=[ordered]@{ok=$true;action='IMAGE_LANE_TASK203_ENTRY_HEARTBEAT';version=$Version;taskId='CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01';stage='ENTRY_BEFORE_CHILD_FETCH';fetchMode='RAW_PINNED_COMMIT';duplicateTaskCreated=$false;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;pid=$PID;at=(Get-Date).ToString('o')};Save 'IMAGE_AGENT_CONTENTOS_TASK203_ENTRY.json' $entry
$result=[ordered]@{ok=$false;action='IMAGE_LANE_TASK203_WRAPPER';version=$Version;childCommit=$ChildCommit;childPath=$ChildPath;childSha=$ChildSha;fetchMode='RAW_PINNED_COMMIT';stage='FETCH_CHILD';childExitCode=$null;error='';startedAt=(Get-Date).ToString('o')}
try{
  $u='https://raw.githubusercontent.com/'+$Repo+'/'+$ChildCommit+'/'+$ChildPath+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $tmp=Join-Path $Root 'HomeDesignLocalAgent-image-task203-child.ps1'
  Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{'User-Agent'='HomeDesign-Image-Lane'} -OutFile $tmp -TimeoutSec 30
  $actual=(Blob $tmp).ToLowerInvariant()
  if($actual-ne$ChildSha){throw('CHILD_RAW_SHA_MISMATCH:'+ $actual)}
  $result.stage='RUN_CHILD'
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp
  $result.childExitCode=$LASTEXITCODE
  if($LASTEXITCODE-ne0){throw('CHILD_EXIT_'+$LASTEXITCODE)}
  $result.ok=$true;$result.stage='DONE'
}catch{$result.error=$_.Exception.Message;$result.stage='ERROR'}finally{$result.completedAt=(Get-Date).ToString('o');Save 'IMAGE_AGENT_CONTENTOS_TASK203_WRAPPER_1.1.138.json' $result}
$result|ConvertTo-Json -Depth 80 -Compress
if($result.ok){exit 0}else{exit 2}
