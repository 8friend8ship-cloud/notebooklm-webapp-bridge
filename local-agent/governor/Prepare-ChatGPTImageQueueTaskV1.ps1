param(
  [Parameter(Mandatory=$true)][string]$TaskFile,
  [string]$CentralRootOverride='G:\내 드라이브\00_중앙에이전트'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
$binding=Join-Path $runtimeDir 'CHATGPT_IMAGE_ADAPTER_BINDING_PLAN_V1.json'
$contract=Join-Path $runtimeDir 'CHATGPT_IMAGE_ENTRYPOINT_CONTRACT_V1.json'
$out=Join-Path $runtimeDir 'CHATGPT_IMAGE_QUEUE_PREP_V1.json'
function Write-Receipt([hashtable]$body,[int]$code){
  New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null
  $body.generatedAt=(Get-Date).ToString('o')
  $body|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Output ($body|ConvertTo-Json -Depth 30 -Compress)
  exit $code
}
if(-not(Test-Path -LiteralPath $TaskFile -PathType Leaf)){Write-Receipt @{ok=$false;status='HOLD_TASK_FILE_MISSING'} 2}
try{$t=Get-Content -LiteralPath $TaskFile -Raw -Encoding UTF8|ConvertFrom-Json}catch{Write-Receipt @{ok=$false;status='HOLD_TASK_JSON_INVALID';error=$_.Exception.Message} 3}
foreach($f in @('taskId','prompt','sourceWorkflow','createdAt')){if([string]::IsNullOrWhiteSpace([string]$t.$f)){Write-Receipt @{ok=$false;status='HOLD_REQUIRED_FIELD_MISSING';missingField=$f} 4}}
$flowQuota=([string]$t.flowQuotaState).ToUpperInvariant();if(-not $flowQuota){$flowQuota='UNKNOWN'}
$gptQuota=([string]$t.chatGptQuotaState).ToUpperInvariant();if(-not $gptQuota){$gptQuota='UNKNOWN'}
$validQuota=@('UNKNOWN','AVAILABLE','LOW','BLOCKED','COOLDOWN')
if($flowQuota -notin $validQuota -or $gptQuota -notin $validQuota){Write-Receipt @{ok=$false;status='HOLD_INVALID_QUOTA_STATE';flowQuotaState=$flowQuota;chatGptQuotaState=$gptQuota} 5}
$flowFailure=[string]$t.fallbackReason
$flowBlocked=$flowQuota -in @('BLOCKED','COOLDOWN')
$gptBlocked=$gptQuota -in @('BLOCKED','COOLDOWN')
if($flowBlocked -and $gptBlocked){Write-Receipt @{ok=$true;status='WAIT_QUOTA';route='QUEUE_WAIT';taskId=[string]$t.taskId;flowQuotaState=$flowQuota;chatGptQuotaState=$gptQuota;retryBackoffMinutes=@(5,15,60);automaticBrowserAction=$false} 0}
if(-not $flowBlocked -and [string]::IsNullOrWhiteSpace($flowFailure)){
  Write-Receipt @{ok=$true;status='ROUTE_FLOW';route='FLOW_AGENT_BRIDGE';taskId=[string]$t.taskId;flowQuotaState=$flowQuota;chatGptQuotaState=$gptQuota;automaticBrowserAction=$false;reason='FLOW_AVAILABLE_OR_UNKNOWN_NO_FAILURE_EVIDENCE'} 0
}
if($gptBlocked){Write-Receipt @{ok=$true;status='WAIT_GPT_QUOTA';route='QUEUE_WAIT';taskId=[string]$t.taskId;flowQuotaState=$flowQuota;chatGptQuotaState=$gptQuota;automaticBrowserAction=$false} 0}
if(-not(Test-Path -LiteralPath $binding -PathType Leaf)){Write-Receipt @{ok=$false;status='HOLD_BINDING_RECEIPT_MISSING';route='CHATGPT_IMAGE_AUTO_FALLBACK';taskId=[string]$t.taskId;automaticBrowserAction=$false} 6}
$b=Get-Content -LiteralPath $binding -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $b.ok -or $b.status -ne 'READY_FOR_ADAPTER_BINDING'){Write-Receipt @{ok=$false;status='HOLD_BINDING_NOT_READY';route='CHATGPT_IMAGE_AUTO_FALLBACK';taskId=[string]$t.taskId;bindingStatus=[string]$b.status;automaticBrowserAction=$false} 7}
if(-not(Test-Path -LiteralPath $contract -PathType Leaf)){Write-Receipt @{ok=$false;status='HOLD_EXTENSION_CONTRACT_MISSING';route='CHATGPT_IMAGE_AUTO_FALLBACK';taskId=[string]$t.taskId;automaticBrowserAction=$false} 8}
$c=Get-Content -LiteralPath $contract -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $c.ok -or $c.status -ne 'CONTRACT_CANDIDATES_FOUND'){Write-Receipt @{ok=$false;status='HOLD_EXTENSION_CONTRACT_NOT_READY';route='CHATGPT_IMAGE_AUTO_FALLBACK';taskId=[string]$t.taskId;contractStatus=[string]$c.status;automaticBrowserAction=$false} 9}
Write-Receipt @{
  ok=$true
  status='READY_FOR_EXACT_INTERFACE_CONFIRMATION'
  route='CHATGPT_IMAGE_AUTO_FALLBACK'
  taskId=[string]$t.taskId
  prompt=[string]$t.prompt
  fallbackReason=$flowFailure
  flowQuotaState=$flowQuota
  chatGptQuotaState=$gptQuota
  automaticQueueIntake=$true
  automaticBrowserAction=$false
  next='CONFIRM_EXACT_EXTENSION_MESSAGE_OR_STORAGE_INTERFACE_THEN_BIND_AUTOMATIC_SUBMIT_AND_DOWNLOAD'
  prohibitions=@('NO_BLIND_UI_CLICK','NO_REINSTALL','NO_NEW_OAUTH','NO_COOKIE_OR_TOKEN_READ','NO_AUTOMATION_PASS_FROM_MANUAL_TEST')
} 0
