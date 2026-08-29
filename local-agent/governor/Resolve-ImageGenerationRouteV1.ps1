param(
  [Parameter(Mandatory=$true)][string]$FlowState,
  [string]$FlowFailureReason='',
  [string]$ChatGptAdapterState='UNKNOWN',
  [string]$DownloadedFile='',
  [string]$DriveFileId='',
  [ValidateSet('true','false')][string]$QueensRegistered='false',
  [int]$ResultAckCount=0,
  [ValidateSet('true','false')][string]$ChangedEvidence='true'
)
$ErrorActionPreference='Stop'
$accepted=@('.png','.jpg','.jpeg','.webp')
$flowHealthy=@('READY','CONNECTED','STARTED','RUNNING','RESULT_READY')
$fallbackReasons=@('FLOW_RUNTIME_UNAVAILABLE','FLOW_GENERATION_FAILED','FLOW_UI_CHANGED','FLOW_LOGIN_SESSION_INVALID','FLOW_CREDIT_OR_QUOTA_BLOCKED','FLOW_RESULT_DOWNLOAD_FAILED')
$queensOk=($QueensRegistered -eq 'true')
$changed=($ChangedEvidence -eq 'true')
$route='HOLD_DIAGNOSTIC';$status='HOLD';$reason='UNRESOLVED_ROUTE'
if($flowHealthy -contains $FlowState){
  $route='FLOW_AGENT_BRIDGE';$status='ROUTE_READY';$reason='FLOW_HEALTHY'
}elseif(($fallbackReasons -contains $FlowFailureReason) -and $changed){
  if($ChatGptAdapterState -eq 'READY_FOR_ADAPTER_BINDING'){
    $route='CHATGPT_IMAGE_AUTO_FALLBACK';$status='ROUTE_READY';$reason=$FlowFailureReason
  }else{
    $reason='CHATGPT_FALLBACK_NOT_READY'
  }
}elseif(-not $changed){
  $reason='SAME_FAILURE_WITHOUT_CHANGED_EVIDENCE'
}else{
  $reason='FLOW_FAILURE_NOT_FALLBACK_ELIGIBLE'
}
$fileOk=$false;$bytes=0;$ext=''
if($DownloadedFile -and (Test-Path -LiteralPath $DownloadedFile -PathType Leaf)){
  $item=Get-Item -LiteralPath $DownloadedFile
  $bytes=[int64]$item.Length
  $ext=[IO.Path]::GetExtension($item.Name).ToLowerInvariant()
  $fileOk=(($accepted -contains $ext) -and $bytes -gt 0)
}
$driveOk=-not [string]::IsNullOrWhiteSpace($DriveFileId)
$functionalPass=($fileOk -and $driveOk -and $queensOk -and $ResultAckCount -ge 2)
$completion=$(if($functionalPass){'VERIFIED'}else{'FUNCTION_E2E_PENDING'})
[ordered]@{
  ok=($route -ne 'HOLD_DIAGNOSTIC')
  route=$route
  routeStatus=$status
  routeReason=$reason
  flowState=$FlowState
  flowFailureReason=$FlowFailureReason
  chatGptAdapterState=$ChatGptAdapterState
  duplicateGenerationAllowed=$false
  downloadedFile=$DownloadedFile
  extension=$ext
  bytes=$bytes
  realImageFile=$fileOk
  driveFileId=$DriveFileId
  driveReadbackEvidence=$driveOk
  queensRegistered=$queensOk
  resultAckCount=$ResultAckCount
  requiredResultAckCount=2
  functionalPass=$functionalPass
  completion=$completion
  nextGate=$(if(-not $fileOk){'REAL_IMAGE_DOWNLOAD'}elseif(-not $driveOk){'DRIVE_READBACK'}elseif(-not $queensOk){'QUEENS_REGISTRATION'}elseif($ResultAckCount -lt 2){'RESULT_ACK_X2'}else{'DONE'})
  at=(Get-Date).ToString('o')
}|ConvertTo-Json -Depth 20 -Compress
if($route -eq 'HOLD_DIAGNOSTIC'){exit 2}
exit 0
