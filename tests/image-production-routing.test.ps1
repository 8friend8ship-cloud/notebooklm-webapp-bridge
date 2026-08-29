$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '..\local-agent\governor\Resolve-ImageGenerationRouteV1.ps1'
function Invoke-Route([hashtable]$p,[int]$ExpectedExit=0){
  $args=@('-NoProfile','-File',$script)
  foreach($k in $p.Keys){$args += @("-$k",[string]$p[$k])}
  $out=& pwsh @args
  $rc=$LASTEXITCODE
  if($rc -ne $ExpectedExit){throw "unexpected exit $rc expected $ExpectedExit output=$out"}
  return ($out|ConvertFrom-Json)
}
$r=Invoke-Route @{FlowState='READY'}
if($r.route -ne 'FLOW_AGENT_BRIDGE' -or $r.routeReason -ne 'FLOW_HEALTHY'){throw 'FLOW_HEALTHY_ROUTE_FAIL'}
$r=Invoke-Route @{FlowState='FAILED';FlowFailureReason='FLOW_GENERATION_FAILED';ChatGptAdapterState='READY_FOR_ADAPTER_BINDING'}
if($r.route -ne 'CHATGPT_IMAGE_AUTO_FALLBACK'){throw 'GPT_FALLBACK_ROUTE_FAIL'}
$r=Invoke-Route @{FlowState='FAILED';FlowFailureReason='FLOW_GENERATION_FAILED';ChatGptAdapterState='UNKNOWN'} 2
if($r.route -ne 'HOLD_DIAGNOSTIC' -or $r.routeReason -ne 'CHATGPT_FALLBACK_NOT_READY'){throw 'FALLBACK_NOT_READY_FAIL_CLOSED_FAIL'}
$r=Invoke-Route @{FlowState='FAILED';FlowFailureReason='FLOW_GENERATION_FAILED';ChatGptAdapterState='READY_FOR_ADAPTER_BINDING';ChangedEvidence='false'} 2
if($r.routeReason -ne 'SAME_FAILURE_WITHOUT_CHANGED_EVIDENCE'){throw 'BLIND_RETRY_GUARD_FAIL'}
$tmp=Join-Path $env:TEMP ('image-route-'+[guid]::NewGuid().ToString('N')+'.png')
try{
  [IO.File]::WriteAllBytes($tmp,[byte[]](137,80,78,71,13,10,26,10,1))
  $r=Invoke-Route @{FlowState='FAILED';FlowFailureReason='FLOW_RESULT_DOWNLOAD_FAILED';ChatGptAdapterState='READY_FOR_ADAPTER_BINDING';DownloadedFile=$tmp;DriveFileId='drive-fixture-1';QueensRegistered='true';ResultAckCount=1}
  if(-not $r.realImageFile -or $r.completion -ne 'FUNCTION_E2E_PENDING' -or $r.nextGate -ne 'RESULT_ACK_X2'){throw 'ACK_GATE_FAIL'}
  $r=Invoke-Route @{FlowState='FAILED';FlowFailureReason='FLOW_RESULT_DOWNLOAD_FAILED';ChatGptAdapterState='READY_FOR_ADAPTER_BINDING';DownloadedFile=$tmp;DriveFileId='drive-fixture-1';QueensRegistered='true';ResultAckCount=2}
  if(-not $r.functionalPass -or $r.completion -ne 'VERIFIED' -or $r.nextGate -ne 'DONE'){throw 'FUNCTIONAL_COMPLETION_GATE_FAIL'}
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
$tmp=Join-Path $env:TEMP ('image-route-'+[guid]::NewGuid().ToString('N')+'.html')
try{
  Set-Content -LiteralPath $tmp -Value '<html>not image</html>' -Encoding UTF8
  $r=Invoke-Route @{FlowState='FAILED';FlowFailureReason='FLOW_RESULT_DOWNLOAD_FAILED';ChatGptAdapterState='READY_FOR_ADAPTER_BINDING';DownloadedFile=$tmp;DriveFileId='drive-fixture-2';QueensRegistered='true';ResultAckCount=2}
  if($r.realImageFile -or $r.completion -eq 'VERIFIED' -or $r.nextGate -ne 'REAL_IMAGE_DOWNLOAD'){throw 'NON_IMAGE_REJECTION_FAIL'}
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
Write-Host 'IMAGE_PRODUCTION_ROUTING_TEST_PASS'
