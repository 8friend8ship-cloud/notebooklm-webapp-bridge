$ErrorActionPreference='Stop'
$worker=Join-Path $PSScriptRoot '..\local-agent\jobs\Run-ImagePackExecutorWorkerV1.ps1'
$root=Join-Path $env:TEMP ('image-exec-worker-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item -ItemType Directory -Force -Path $root|Out-Null
  $out=& powershell.exe -NoProfile -NonInteractive -File $worker -CentralRootOverride $root -Once
  if($LASTEXITCODE -ne 0){throw "QUEUE_EMPTY_EXIT_FAIL:$out"}
  $r=$out|ConvertFrom-Json
  if($r.status -ne 'QUEUE_EMPTY' -or $r.executed){throw 'QUEUE_EMPTY_CONTRACT_FAIL'}
  $q=Join-Path $root 'ImageExecutor\Queue'
  @{taskId='PROD_DISABLED_TEST';prompt='must not execute';canary=$false;generationAllowed=$true;aspectRatio='16:9'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $q 'prod-disabled.json') -Encoding UTF8
  $out=& powershell.exe -NoProfile -NonInteractive -File $worker -CentralRootOverride $root -Once
  if($LASTEXITCODE -ne 0){throw "PROD_HOLD_EXIT_FAIL:$out"}
  $r=$out|ConvertFrom-Json
  if($r.status -ne 'HOLD_PRODUCTION_DISABLED_V1_CANARY_ONLY' -or $r.executed){throw 'PRODUCTION_FAILCLOSE_CONTRACT_FAIL'}
  if(-not(Test-Path -LiteralPath (Join-Path $q 'prod-disabled.json'))){throw 'HOLD_TASK_SHOULD_REMAIN_QUEUED'}
  Write-Host 'IMAGE_PACK_EXECUTOR_WORKER_CONTRACT_TEST_PASS'
}finally{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
