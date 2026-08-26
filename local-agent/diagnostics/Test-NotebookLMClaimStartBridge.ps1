param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]{1,180}$')][string]$TaskId,
  [ValidateSet('AUTO','TEXT','IMAGE','AUDIO','VIDEO')][string]$TaskKind='AUTO',
  [int]$ExpectedMediaSeconds=0,
  [int]$ClaimedAgeSeconds=0,
  [int]$StartGraceSeconds=60,
  [string]$ExpectedOutputPath='',
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
function Get-WorkBudgetSeconds([string]$Kind,[int]$MediaSeconds){
  $m=[Math]::Max(0,$MediaSeconds)
  switch($Kind){
    'AUDIO' { return [Math]::Max(120,[int]([Math]::Ceiling($m*1.5)+60)) }
    'VIDEO' { return [Math]::Max(300,[int]([Math]::Ceiling($m*3.0)+180)) }
    'IMAGE' { return 180 }
    'TEXT'  { return 120 }
    default { return $(if($m -gt 0){[Math]::Max(180,[int]([Math]::Ceiling($m*2.0)+120))}else{180}) }
  }
}
function Read-OutputProgress([string]$Path){
  $o=[ordered]@{configured=$false;exists=$false;kind='';sizeBytes=0;lastWrite='';ageSeconds=$null;progressing=$false}
  if([string]::IsNullOrWhiteSpace($Path)){return $o}
  $o.configured=$true
  try{
    if(Test-Path -LiteralPath $Path){
      $o.exists=$true;$item=Get-Item -LiteralPath $Path -ErrorAction Stop
      $o.kind=$(if($item.PSIsContainer){'DIRECTORY'}else{'FILE'})
      if($item.PSIsContainer){
        $files=@(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue)
        $o.sizeBytes=[int64](($files|Measure-Object -Property Length -Sum).Sum)
        $latest=$files|Sort-Object LastWriteTime -Descending|Select-Object -First 1
        if($latest){$o.lastWrite=$latest.LastWriteTime.ToString('o');$o.ageSeconds=[int][Math]::Floor(((Get-Date)-$latest.LastWriteTime).TotalSeconds)}
      }else{
        $o.sizeBytes=[int64]$item.Length;$o.lastWrite=$item.LastWriteTime.ToString('o');$o.ageSeconds=[int][Math]::Floor(((Get-Date)-$item.LastWriteTime).TotalSeconds)
      }
      if($null -ne $o.ageSeconds -and $o.ageSeconds -le 90){$o.progressing=$true}
    }
  }catch{}
  return $o
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

$resolvedKind=$TaskKind
if($resolvedKind -eq 'AUTO'){
  if($ExpectedMediaSeconds -gt 0){$resolvedKind='VIDEO'}else{$resolvedKind='TEXT'}
}
$workBudget=Get-WorkBudgetSeconds $resolvedKind $ExpectedMediaSeconds
$startedAt=$null;$runAgeSeconds=$null
if($status -and $status.startedAt){try{$startedAt=[datetime]$status.startedAt;$runAgeSeconds=[int][Math]::Floor(((Get-Date)-$startedAt).TotalSeconds)}catch{}}
$outputProgress=Read-OutputProgress $ExpectedOutputPath

$state='UNKNOWN'
$ok=$false
$problem=''
if(-not $health -or -not [bool]$health.ok){
  $state='HOST_DOWN';$problem='Local Command Host health check failed.'
}elseif($result -or ($hostResult -and [string]$hostResult.state -eq 'DONE')){
  $state='DONE';$ok=$true
}elseif(($hostResult -and [string]$hostResult.state -eq 'RUNNING') -or ($status -and $wrapperAlive)){
  if($outputProgress.progressing){$state='PROGRESSING';$ok=$true}
  elseif($null -ne $runAgeSeconds -and $runAgeSeconds -gt $workBudget){$state='RUNNING_OVER_BUDGET';$problem='Work started but exceeded media-aware budget without recent output progress.'}
  else{$state='START_CONFIRMED';$ok=$true}
}elseif($status -and -not $wrapperAlive){
  $state='START_LOST';$problem='status.json exists but wrapper process is not alive and no result.json exists.'
}elseif($hostResult -and [string]$hostResult.state -eq 'ERROR'){
  $state='HOST_TASK_ERROR';$problem=[string]$hostResult.error
}else{
  if($ClaimedAgeSeconds -ge $StartGraceSeconds){$state='CLAIMED_START_DELAY';$problem='Claimed but no Host RUNNING/DONE evidence within start grace window.'}
  else{$state='CLAIMED_PENDING_START';$problem='Claimed and still inside the short start grace window.'}
}

$out=[ordered]@{
  ok=$ok
  action='NOTEBOOKLM_CLAIM_START_BRIDGE_TEST_V2'
  taskId=$TaskId
  state=$state
  checkedAt=(Get-Date).ToString('o')
  taskKind=$resolvedKind
  expectedMediaSeconds=$ExpectedMediaSeconds
  startGraceSeconds=$StartGraceSeconds
  claimedAgeSeconds=$ClaimedAgeSeconds
  workBudgetSeconds=$workBudget
  runAgeSeconds=$runAgeSeconds
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
  outputProgress=$outputProgress
  problem=$problem
  immediateAction=$(switch($state){
    'DONE' {'NO_ACTION'}
    'PROGRESSING' {'NO_ACTION_OUTPUT_IS_CHANGING'}
    'START_CONFIRMED' {'NO_ACTION_WITHIN_MEDIA_BUDGET'}
    'CLAIMED_PENDING_START' {'WAIT_SHORT_START_GRACE_ONLY'}
    'CLAIMED_START_DELAY' {'CHECK_POLLER_AND_HOST_HANDOFF_NOW'}
    'RUNNING_OVER_BUDGET' {'CHECK_OUTPUT_PROGRESS_THEN_DIAGNOSE_WORKER'}
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
if($state -in @('DONE','PROGRESSING','START_CONFIRMED','CLAIMED_PENDING_START')){exit 0}else{exit 2}
