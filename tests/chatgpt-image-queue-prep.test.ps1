$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\local-agent\governor\Prepare-ChatGPTImageQueueTaskV1.ps1'
function Run([hashtable]$task,[switch]$WithReceipts,[int]$Expected=0){
  $root=Join-Path $env:TEMP ('gpt-image-queue-'+[guid]::NewGuid().ToString('N'))
  $dir=Join-Path $root 'Runtime_Readback\CHROME';New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $taskFile=Join-Path $root 'task.json';$task|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $taskFile -Encoding UTF8
  if($WithReceipts){
    @{ok=$true;status='READY_FOR_ADAPTER_BINDING'}|ConvertTo-Json|Set-Content (Join-Path $dir 'CHATGPT_IMAGE_ADAPTER_BINDING_PLAN_V1.json') -Encoding UTF8
    @{ok=$true;status='CONTRACT_CANDIDATES_FOUND'}|ConvertTo-Json|Set-Content (Join-Path $dir 'CHATGPT_IMAGE_ENTRYPOINT_CONTRACT_V1.json') -Encoding UTF8
  }
  $out=& pwsh -NoProfile -File $script -TaskFile $taskFile -CentralRootOverride $root
  $rc=$LASTEXITCODE
  if($rc -ne $Expected){throw "unexpected exit $rc expected $Expected output=$out"}
  $j=$out|ConvertFrom-Json
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  return $j
}
$base=@{taskId='T1';prompt='make a simple test image';sourceWorkflow='TEST';createdAt='2026-08-29T18:20:00+09:00'}
$r=Run ($base+@{flowQuotaState='AVAILABLE';chatGptQuotaState='AVAILABLE'})
if($r.status -ne 'ROUTE_FLOW'){throw 'FLOW_ROUTE_FAIL'}
$r=Run ($base+@{flowQuotaState='BLOCKED';chatGptQuotaState='BLOCKED';fallbackReason='FLOW_CREDIT_OR_QUOTA_BLOCKED'})
if($r.status -ne 'WAIT_QUOTA'){throw 'BOTH_QUOTA_WAIT_FAIL'}
$r=Run ($base+@{flowQuotaState='BLOCKED';chatGptQuotaState='AVAILABLE';fallbackReason='FLOW_CREDIT_OR_QUOTA_BLOCKED'}) -Expected 6
if($r.status -ne 'HOLD_BINDING_RECEIPT_MISSING'){throw 'FAIL_CLOSED_BINDING_FAIL'}
$r=Run ($base+@{flowQuotaState='BLOCKED';chatGptQuotaState='AVAILABLE';fallbackReason='FLOW_CREDIT_OR_QUOTA_BLOCKED'}) -WithReceipts
if($r.status -ne 'READY_FOR_EXACT_INTERFACE_CONFIRMATION' -or -not $r.automaticQueueIntake -or $r.automaticBrowserAction){throw 'QUEUE_PREP_FAIL'}
Write-Host 'CHATGPT_IMAGE_QUEUE_PREP_TEST_PASS'
