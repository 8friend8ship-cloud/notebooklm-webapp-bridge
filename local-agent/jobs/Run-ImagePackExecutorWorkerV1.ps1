param(
  [string]$CentralRootOverride='G:\내 드라이브\00_중앙에이전트',
  [int]$CdpPort=9224,
  [int]$TimeoutMs=360000,
  [switch]$Once
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root=Join-Path $CentralRootOverride 'ImageExecutor'
$queue=Join-Path $root 'Queue';$running=Join-Path $root 'Running';$done=Join-Path $root 'Done';$failed=Join-Path $root 'Failed';$results=Join-Path $root 'Results'
foreach($d in @($queue,$running,$done,$failed,$results)){New-Item -ItemType Directory -Force -Path $d|Out-Null}
$lockPath=Join-Path $root 'worker.lock'
$wrapper=Join-Path $PSScriptRoot 'Run-ChatGPTImageExactAdapterV1.ps1'
if(-not(Test-Path -LiteralPath $wrapper -PathType Leaf)){throw 'EXACT_ADAPTER_WRAPPER_MISSING'}
function Save-Result([hashtable]$r,[string]$taskId){$p=Join-Path $results (($taskId -replace '[^A-Za-z0-9._-]','_')+'.json');$r.generatedAt=(Get-Date).ToString('o');$r|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $p -Encoding UTF8;return $p}
function Process-One {
  $taskFile=Get-ChildItem -LiteralPath $queue -Filter '*.json' -File|Sort-Object LastWriteTime,Name|Select-Object -First 1
  if(-not $taskFile){return @{ok=$true;status='QUEUE_EMPTY';executed=$false}}
  try{$t=Get-Content -LiteralPath $taskFile.FullName -Raw -Encoding UTF8|ConvertFrom-Json}catch{return @{ok=$false;status='TASK_JSON_INVALID';executed=$false;file=$taskFile.Name}}
  $taskId=[string]$t.taskId;if(-not $taskId -or $taskId -notmatch '^[A-Za-z0-9._-]{4,120}$'){return @{ok=$false;status='TASK_ID_INVALID';executed=$false;file=$taskFile.Name}}
  $canary=($t.canary -eq $true -or [string]$t.canary -match '^(?i:true|1|yes)$')
  if(-not $canary){return @{ok=$true;status='HOLD_PRODUCTION_DISABLED_V1_CANARY_ONLY';executed=$false;taskId=$taskId}}
  $resultPath=Join-Path $results (($taskId -replace '[^A-Za-z0-9._-]','_')+'.json')
  if(Test-Path -LiteralPath $resultPath -PathType Leaf){return @{ok=$true;status='DEDUP_RESULT_EXISTS';executed=$false;taskId=$taskId;resultPath=$resultPath}}
  $claimed=Join-Path $running $taskFile.Name
  Move-Item -LiteralPath $taskFile.FullName -Destination $claimed -ErrorAction Stop
  try{
    $raw=& powershell.exe -NoProfile -NonInteractive -File $wrapper -Mode Execute -TaskFile $claimed -CentralRootOverride $CentralRootOverride -CdpPort $CdpPort -TimeoutMs $TimeoutMs 2>&1
    $rc=$LASTEXITCODE;$text=($raw|ForEach-Object{[string]$_}) -join "`n"
    try{$receipt=$text|ConvertFrom-Json}catch{$receipt=$null}
    $ok=($rc -eq 0 -and $receipt -and $receipt.ok -eq $true -and $receipt.copiedToCentralDrive -eq $true)
    $r=@{ok=$ok;status=$(if($ok){'EXECUTOR_CANARY_IMAGE_READY'}else{'EXECUTOR_ADAPTER_FAILED'});executed=$true;taskId=$taskId;canary=$true;productionAllowed=$false;adapterExitCode=$rc;adapterReceipt=$receipt;genericDownloadsScan=$false;duplicateGenerationAllowed=$false}
    $rp=Save-Result $r $taskId
    $terminal=if($ok){$done}else{$failed}
    Move-Item -LiteralPath $claimed -Destination (Join-Path $terminal $taskFile.Name) -Force
    $r.resultPath=$rp;return $r
  }catch{
    $r=@{ok=$false;status='EXECUTOR_EXCEPTION';executed=$true;taskId=$taskId;canary=$true;productionAllowed=$false;error=$_.Exception.Message;genericDownloadsScan=$false;duplicateGenerationAllowed=$false};$rp=Save-Result $r $taskId
    if(Test-Path -LiteralPath $claimed){Move-Item -LiteralPath $claimed -Destination (Join-Path $failed $taskFile.Name) -Force};$r.resultPath=$rp;return $r
  }
}
$lock=$null
try{
  if(Test-Path -LiteralPath $lockPath -PathType Leaf){
    $age=((Get-Date)-(Get-Item -LiteralPath $lockPath).LastWriteTime).TotalMinutes
    if($age -gt 10){Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue}
  }
  try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)}catch{Write-Output (@{ok=$true;status='WORKER_LOCK_BUSY';executed=$false}|ConvertTo-Json -Compress);exit 0}
  $result=Process-One
  Write-Output ($result|ConvertTo-Json -Depth 40 -Compress)
  if($result.ok){exit 0}else{exit 2}
}finally{
  if($lock){$lock.Dispose()}
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
