param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.136-image-task203'
$TaskId='CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01'
$HostBase='http://127.0.0.1:8765'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$ReceiptName='IMAGE_AGENT_CONTENTOS_TASK203_DIRECT.json'
$ReceiptPath=Join-Path $Root $ReceiptName
$VersionReceiptPath=Join-Path $Root 'IMAGE_AGENT_CONTENTOS_TASK203_DIRECT_1.1.136.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not$r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveJson([string]$Path,$Object){
  $parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  $Object|ConvertTo-Json -Depth 80|Set-Content -LiteralPath $Path -Encoding UTF8
}
function Publish($Object){
  SaveJson $ReceiptPath $Object
  SaveJson $VersionReceiptPath $Object
  try{
    $central=FindCentral
    if($central){
      $dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null
      SaveJson (Join-Path $dest $ReceiptName) $Object
      SaveJson (Join-Path $dest 'IMAGE_AGENT_CONTENTOS_TASK203_DIRECT_1.1.136.json') $Object
    }
  }catch{}
}

$rec=[ordered]@{
  ok=$false
  action='IMAGE_LANE_CONTENTOS_TASK203_HOST_DIRECT'
  agentVersion=$AgentVersion
  taskId=$TaskId
  hostTarget='1.3.0'
  repo='8friend8ship-cloud/contents-os-git'
  branch='main'
  script='tools/Repair-ContentOS-DriveCacheAppsScript.ps1'
  duplicateTaskCreated=$false
  newAppsScriptProject=$false
  newDeployment=$false
  newTrigger=$false
  oauthChanged=$false
  scopeChanged=$false
  normalChromeTouched=$false
  generateClicked=$false
  creditSpend=$false
  stage='START'
  hostHealth=$null
  submit=$null
  result=$null
  error=''
  startedAt=(Get-Date).ToString('o')
}

try{
  $rec.stage='HOST_HEALTH'
  $health=Invoke-RestMethod -Method Get -Uri ($HostBase+'/health') -TimeoutSec 5
  $rec.hostHealth=$health
  if(-not[bool]$health.ok -or [string]$health.version-ne'1.3.0' -or -not[bool]$health.asyncJobs){throw('HOST130_HEALTH_GATE_FAILED:'+($health|ConvertTo-Json -Compress))}

  $rec.stage='SUBMIT_FIXED_TASK203'
  $sourceText=(@{repo='8friend8ship-cloud/contents-os-git';branch='main';script='tools/Repair-ContentOS-DriveCacheAppsScript.ps1';args=@{}}|ConvertTo-Json -Compress)
  $task=[ordered]@{taskId=$TaskId;taskType='LOCAL_POWERSHELL';sourceText=$sourceText;timeoutSeconds=600}
  $submit=Invoke-RestMethod -Method Post -Uri ($HostBase+'/run') -ContentType 'application/json' -Body (@{task=$task}|ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 20
  $rec.submit=$submit
  if(-not[bool]$submit.ok -or @('STARTED','RUNNING','DONE') -notcontains [string]$submit.state){throw('TASK203_SUBMIT_FAILED:'+($submit|ConvertTo-Json -Depth 20 -Compress))}

  $rec.stage='POLL_FIXED_TASK203'
  $result=$null
  for($i=0;$i -lt 330;$i++){
    $result=Invoke-RestMethod -Method Get -Uri ($HostBase+'/result?taskId='+[Uri]::EscapeDataString($TaskId)) -TimeoutSec 8
    if(@('DONE','ERROR') -contains [string]$result.state){break}
    Start-Sleep -Seconds 2
  }
  $rec.result=$result
  if(-not$result){throw'TASK203_RESULT_EMPTY'}
  if([string]$result.state-eq'ERROR'){throw('TASK203_HOST_ERROR:'+ [string]$result.error)}
  if([string]$result.state-ne'DONE'){throw('TASK203_RESULT_PENDING_AFTER_POLL:'+ [string]$result.state)}
  if(-not[bool]$result.result.ok){throw('TASK203_SCRIPT_FAILED:'+ [string]$result.result.stderr)}

  $rec.ok=$true
  $rec.stage='DONE'
}catch{
  $rec.error=$_.Exception.Message
  $rec.stage='ERROR'
}finally{
  $rec.completedAt=(Get-Date).ToString('o')
  Publish $rec
}

$rec|ConvertTo-Json -Depth 80 -Compress
if($rec.ok){exit 0}else{exit 2}
