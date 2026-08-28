param([switch]$Deep,[switch]$Quick)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Control=Join-Path $Base 'Control'
$StateDir=Join-Path $Control 'State'
$Logs=Join-Path $Control 'Logs'
$AgentRoot=Join-Path $Base 'LocalAgent'
$HubState=Join-Path $StateDir 'NOTEBOOK_RUNTIME_HUB_LATEST.json'
$DeepStamp=Join-Path $StateDir 'NOTEBOOK_RUNTIME_HUB_LAST_DEEP.txt'
$History=Join-Path $StateDir 'NOTEBOOK_RUNTIME_HUB_HISTORY.jsonl'
$Log=Join-Path $Logs ('NOTEBOOK_RUNTIME_HUB_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
$ProjectId='contents-os-gcp'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
New-Item -ItemType Directory -Force -Path $StateDir,$Logs|Out-Null

function Log([string]$m){$x='['+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'] '+$m;Add-Content -LiteralPath $Log -Value $x -Encoding UTF8}
function ReadJson([string]$p){try{if(Test-Path -LiteralPath $p){return Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json}}catch{};return $null}
function BoolCommand([string]$n){return [bool](Get-Command $n -ErrorAction SilentlyContinue)}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function FindCentralFolder{
  $target='00_중앙에이전트'
  foreach($letter in 'D'..'Z'){
    foreach($p in @("$letter`:\My Drive\$target","$letter`:\내 드라이브\$target","$letter`:\Google Drive\$target","$letter`:\$target")){if(Test-Path -LiteralPath $p){return $p}}
  }
  foreach($p in @((Join-Path $env:USERPROFILE ('My Drive\'+$target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $p){return $p}}
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    foreach($p in @((Join-Path $d.Root $target),(Join-Path $d.Root ('My Drive\'+$target)),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $p){return $p}}
  }
  return ''
}
function ScheduledTaskState([string]$name){try{$t=Get-ScheduledTask -TaskName $name -ErrorAction Stop;return [ordered]@{present=$true;state=[string]$t.State}}catch{return [ordered]@{present=$false;state='MISSING'}}}
function GetClaspState{
  $cli=BoolCommand 'clasp';$auth=(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.clasprc.json'))
  return [ordered]@{cli=$cli;authReceiptPresent=$auth;status=$(if(-not $cli){'CLASP_CLI_MISSING'}elseif(-not $auth){'CLASP_AUTH_RECEIPT_MISSING'}else{'CLASP_READY_RECEIPT_PRESENT'})}
}
function GetGcloudState([bool]$deep){
  $cli=BoolCommand 'gcloud';if(-not $cli){return [ordered]@{cli=$false;activeAuth=$false;project='';enabledServices=@();status='GCLOUD_CLI_MISSING'}}
  $active=$false;$proj='';$services=@()
  try{$acct=(& gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>$null|Select-Object -First 1);$active=![string]::IsNullOrWhiteSpace([string]$acct)}catch{}
  try{$proj=[string](& gcloud config get-value project 2>$null|Select-Object -First 1)}catch{}
  if($deep -and $active){try{$services=@(& gcloud services list --enabled --project $ProjectId --format='value(config.name)' 2>$null|Where-Object{$_})}catch{}}
  return [ordered]@{cli=$true;activeAuth=$active;project=$proj;enabledServices=$services;status=$(if(-not $active){'GCLOUD_AUTH_MISSING'}elseif($proj -ne $ProjectId){'GCLOUD_PROJECT_MISMATCH'}else{'GCLOUD_READY'})}
}
function GetStableVersions{
  $out=[ordered]@{agent='UNKNOWN';bridge='UNKNOWN';host='UNKNOWN'}
  try{$a=Invoke-RestMethod -Uri ('https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/stable/agent.json?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -TimeoutSec 8;$out.agent=[string]$a.version}catch{}
  try{$b=Invoke-RestMethod -Uri ('https://raw.githubusercontent.com/'+$Repo+'/main/runtime/stable/release.json?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -TimeoutSec 8;$out.bridge=[string]$b.version}catch{}
  $h=HostHealth;if($h){try{$out.host=[string]$h.version}catch{}}
  return $out
}
function GetGovernorState{
  $paths=@(
    (Join-Path $StateDir 'LATEST_STATUS.json'),
    (Join-Path $Base 'ChromeGovernor\state.json'),
    (Join-Path $AgentRoot 'state.json')
  )
  foreach($p in $paths){$j=ReadJson $p;if($j){return [ordered]@{found=$true;path=$p;data=$j}}}
  return [ordered]@{found=$false;path='';data=$null}
}
function GetDriveSyncState{
  $p=Join-Path $Base 'ChromeGovernor\drive-sync.json';$j=ReadJson $p
  if($j){return [ordered]@{found=$true;path=$p;status=[string]$j.status;target=[string]$j.path;at=[string]$j.at}}
  return [ordered]@{found=$false;path=$p;status='NO_DRIVE_SYNC_RECEIPT';target='';at=''}
}
function GetLocalRuntime{
  $h=HostHealth;$agent=ReadJson (Join-Path $AgentRoot 'state.json')
  $bridge=ReadJson (Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge\manifest.json')
  return [ordered]@{
    hostHealthy=($null -ne $h -and [bool]$h.ok);hostVersion=$(if($h){[string]$h.version}else{'UNKNOWN'});
    agentVersion=$(if($agent){[string]$agent.agentVersion}else{'UNKNOWN'});agentStatus=$(if($agent){[string]$agent.status}else{'UNKNOWN'});
    bridgeVersion=$(if($bridge){[string]$bridge.version}else{'UNKNOWN'});node=BoolCommand 'node';powershell=$true
  }
}
function IsDeepDue{
  if($Deep){return $true};if(-not(Test-Path -LiteralPath $DeepStamp)){return $true}
  try{$d=[datetime](Get-Content -LiteralPath $DeepStamp -Raw);return (((Get-Date)-$d).TotalHours -ge 20)}catch{return $true}
}
function WriteState($obj){
  $json=$obj|ConvertTo-Json -Depth 30
  $json|Set-Content -LiteralPath $HubState -Encoding UTF8
  ($obj|ConvertTo-Json -Depth 8 -Compress)|Add-Content -LiteralPath $History -Encoding UTF8
  $central=FindCentralFolder
  if($central){
    try{$dir=Join-Path $central 'RUNTIME_READBACK\NOTEBOOK_HUB';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir 'NOTEBOOK_RUNTIME_HUB_LATEST.json') -Encoding UTF8;$obj.driveWritebackOk=$true;$obj.centralPath=$dir;$obj|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $HubState -Encoding UTF8}catch{$obj.driveWritebackOk=$false;$obj.centralPath=''}
  }else{$obj.driveWritebackOk=$false;$obj.centralPath=''}
  return $obj
}

$deepDue=IsDeepDue
Log ('START deep='+[int]$deepDue)
$runtime=GetLocalRuntime
$clasp=GetClaspState
$gcloud=GetGcloudState $deepDue
$gov=GetGovernorState
$drive=GetDriveSyncState
$stable=GetStableVersions
$tasks=[ordered]@{autoResume=ScheduledTaskState 'HomeDesignAutomation-AutoResume';governor=ScheduledTaskState 'HomeDesignAutomation-GovernorV6'}

$problems=New-Object Collections.Generic.List[string]
if(-not $runtime.hostHealthy){$problems.Add('HOST_UNHEALTHY')}
if($runtime.agentStatus -notmatch 'RUN|PASS|READY|HEALTH'){$problems.Add('AGENT_STATUS_NOT_HEALTHY')}
if(-not $clasp.cli){$problems.Add('CLASP_CLI_MISSING')}
if(-not $clasp.authReceiptPresent){$problems.Add('CLASP_AUTH_RECEIPT_MISSING')}
if(-not $gcloud.cli){$problems.Add('GCLOUD_CLI_MISSING')}
if($gcloud.cli -and -not $gcloud.activeAuth){$problems.Add('GCLOUD_AUTH_MISSING')}
if($gcloud.activeAuth -and $gcloud.project -ne $ProjectId){$problems.Add('GCLOUD_PROJECT_MISMATCH')}
if(-not $tasks.autoResume.present){$problems.Add('AUTO_RESUME_TASK_MISSING')}
if(-not $gov.found){$problems.Add('GOVERNOR_READBACK_MISSING')}
if(-not $drive.found -or $drive.status -ne 'SYNCED'){$problems.Add('DRIVE_SYNC_NOT_CONFIRMED')}

$approvals=New-Object Collections.Generic.List[string]
# These are never auto-executed by this hub; they are surfaced to Central Agent only when truly required.
if(-not $clasp.authReceiptPresent){$approvals.Add('CLASP_AUTH_IF_CURRENT_RECEIPT_CANNOT_BE_RECOVERED')}
if($gcloud.cli -and -not $gcloud.activeAuth){$approvals.Add('GOOGLE_LOGIN_IF_EXISTING_AUTH_CANNOT_BE_RECOVERED')}

$status=if($problems.Count -eq 0){'PASS_LOCAL_RUNTIME'}elseif($runtime.hostHealthy -and $drive.found){'DEGRADED_DIAGNOSE_MINIMUM_FIX'}else{'FAIL_LOCAL_RUNTIME'}
$policy=[ordered]@{
  precheck='HISTORY_LAST_GOOD_SUCCESS_FAILURE_FIRST';
  repair='NO_BLIND_RETRY;ROOT_CAUSE;MINIMUM_PATCH;SAME_FIXTURE_RETEST';
  api='USE_ONLY_FOR_PROBLEM_SOLVING_OR_FINAL_TEMPLATE_QUALITY_OR_LEARNING_COMPARE_WHEN_CENTRAL_BACKDATA_IS_INSUFFICIENT';
  afterApi='STORE_USEFUL_DELTA_AS_SEED_TEMPLATE_ASSET_WITH_TAG_SUMMARY_KEYWORDS_URL_LINEAGE';
  approval='REUSE_EXISTING_APPROVALS;ASK_ONLY_FOR_LOGIN_2FA_NEW_SECRET_SCOPE_PAID_API_PUBLIC_HIGH_IMPACT_DESTRUCTIVE_PAYMENT';
  chrome='OFFICIAL_API_FIRST;CHROME_EXTENSION_ONLY_FOR_UI_GAPS;PRESERVE_NORMAL_CHROME';
  media='TEXT_IMAGE_VIDEO_AUDIO_MOTION_FACE_EXPRESSION_LIPSYNC_SUBTITLE_PERSONA_LANGUAGE_VOICE_AS_REUSABLE_POINTER_ASSETS'
}
$result=[ordered]@{
  schema='CENTRAL_NOTEBOOK_RUNTIME_HUB_V1';generatedAt=(Get-Date).ToString('o');deep=$deepDue;status=$status;projectId=$ProjectId;
  runtime=$runtime;stable=$stable;clasp=$clasp;gcloud=$gcloud;scheduledTasks=$tasks;governor=$gov;driveSync=$drive;
  problems=@($problems);approvalRequired=@($approvals);policy=$policy;driveWritebackOk=$false;centralPath=''
}
if($deepDue){(Get-Date).ToString('o')|Set-Content -LiteralPath $DeepStamp -Encoding UTF8}
$result=WriteState $result
Log ('END status='+$result.status+' drive='+[int]$result.driveWritebackOk+' problems='+$problems.Count)
$result|ConvertTo-Json -Depth 30
if($status -eq 'PASS_LOCAL_RUNTIME'){exit 0}elseif($status -eq 'DEGRADED_DIAGNOSE_MINIMUM_FIX'){exit 1}else{exit 2}
