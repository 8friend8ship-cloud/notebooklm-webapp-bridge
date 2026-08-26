param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]{1,180}$')][string]$TaskId,
  [int]$HostPort=8765,
  [switch]$WriteCentralReadback
)

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ResultRoot=Join-Path $Root 'CommandResults'
$TaskRoot=Join-Path $ResultRoot $TaskId
$StatusPath=Join-Path $TaskRoot 'status.json'
$ResultPath=Join-Path $TaskRoot 'result.json'

function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Find-CentralRoot {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($candidate in @(
      (Join-Path $r $target),
      (Join-Path $r ('My Drive\'+$target)),
      (Join-Path $r ('내 드라이브\'+$target)),
      (Join-Path $r ('Google Drive\'+$target))
    )){if(Test-Path -LiteralPath $candidate){return $candidate}}
  }
  return ''
}

$health=$null;$healthError=''
try{$health=Invoke-RestMethod -Uri ("http://127.0.0.1:$HostPort/health") -Method Get -TimeoutSec 3}catch{$healthError=$_.Exception.Message}
$hostResult=$null;$hostResultError=''
try{$hostResult=Invoke-RestMethod -Uri ("http://127.0.0.1:$HostPort/result?taskId="+[Uri]::EscapeDataString($TaskId)) -Method Get -TimeoutSec 3}catch{$hostResultError=$_.Exception.Message}
$status=Read-Json $StatusPath
$result=Read-Json $ResultPath
$wrapperPid=$null;$wrapperAlive=$false
if($status -and $status.wrapperPid){
  try{$wrapperPid=[int]$status.wrapperPid;$wrapperAlive=[bool](Get-Process -Id $wrapperPid -ErrorAction SilentlyContinue)}catch{}
}

$state='UNKNOWN'
$ok=$false
$problem=''
if(-not $health -or -not [bool]$health.ok){
  $state='HOST_DOWN';$problem='Local Command Host health check failed.'
}elseif($result -or ($hostResult -and [string]$hostResult.state -eq 'DONE')){
  $state='DONE';$ok=$true
}elseif(($hostResult -and [string]$hostResult.state -eq 'RUNNING') -or ($status -and $wrapperAlive)){
  $state='START_CONFIRMED';$ok=$true
}elseif($status -and -not $wrapperAlive){
  $state='START_LOST';$problem='status.json exists but wrapper process is not alive and no result.json exists.'
}elseif($hostResult -and [string]$hostResult.state -eq 'ERROR'){
  $state='HOST_TASK_ERROR';$problem=[string]$hostResult.error
}else{
  $state='CLAIMED_BUT_NOT_STARTED';$problem='No Host RUNNING/DONE evidence and no local wrapper status/result yet.'
}

$out=[ordered]@{
  ok=$ok
  action='NOTEBOOKLM_CLAIM_START_BRIDGE_TEST'
  taskId=$TaskId
  state=$state
  checkedAt=(Get-Date).ToString('o')
  hostHealthy=$(if($health){[bool]$health.ok}else{$false})
  hostVersion=$(if($health){[string]$health.version}else{''})
  hostAsyncJobs=$(if($health){[bool]$health.asyncJobs}else{$false})
  hostResult=$hostResult
  hostHealthError=$healthError
  hostResultError=$hostResultError
  localStatusExists=(Test-Path -LiteralPath $StatusPath)
  localResultExists=(Test-Path -LiteralPath $ResultPath)
  wrapperPid=$wrapperPid
  wrapperAlive=$wrapperAlive
  statusPath=$StatusPath
  resultPath=$ResultPath
  problem=$problem
  immediateAction=$(switch($state){
    'DONE' {'NO_ACTION'}
    'START_CONFIRMED' {'NO_ACTION'}
    'CLAIMED_BUT_NOT_STARTED' {'CHECK_POLLER_AND_HOST_HANDOFF_NOW'}
    'START_LOST' {'DIAGNOSTIC_HOLD_THEN_MINIMUM_RECOVERY'}
    'HOST_DOWN' {'RECOVER_EXISTING_HOST_ONLY'}
    'HOST_TASK_ERROR' {'READ_HOST_ERROR_THEN_MINIMUM_FIX'}
    default {'DIAGNOSE'}
  })
}

if($WriteCentralReadback){
  $central=Find-CentralRoot
  if($central){
    try{
      $dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null
      $dest=Join-Path $dir ('NOTEBOOKLM_CLAIM_START_'+$TaskId+'.json')
      $out|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $dest -Encoding UTF8
      $out.centralReadback=$dest
    }catch{$out.centralReadbackError=$_.Exception.Message}
  }else{$out.centralReadbackError='CENTRAL_DRIVE_ROOT_NOT_FOUND'}
}

$out|ConvertTo-Json -Depth 30 -Compress
if($state -in @('DONE','START_CONFIRMED')){exit 0}else{exit 2}
