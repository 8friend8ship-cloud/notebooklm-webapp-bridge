param()

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.51'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$PreviousAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.50.ps1'
$PreviousAgentUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.50/HomeDesignLocalAgent.ps1'
$PreviousAgentSha='131bedf4dd2b2ff1d360b075edec3fad388a5b8c'
$QueueLocalReceipt=Join-Path $Root 'NOTEBOOKLM_QUEUE_INTEGRITY_SYNC_V2.json'
$ExpectedQueueVersion='0.2.10-queue-lock'
$ExpectedQueueSourceSha='e7c22534048062eca913e2d1b5d8b3c6e7ac8b28'
$State=Join-Path $Root 'state.json'

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path)
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[] ($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}
  finally{$s.Dispose()}
}
function FetchPinned([string]$Url,[string]$Destination,[string]$ExpectedSha){
  $tmp=$Destination+'.download'
  Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
  if($actual -ne $ExpectedSha.ToLowerInvariant()){
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw ('SHA_MISMATCH:'+$actual+':'+$ExpectedSha)
  }
  Move-Item -LiteralPath $tmp -Destination $Destination -Force
  return $actual
}
function FindCentralRoot{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not $drv.Root){continue}
    foreach($cand in @(
      (Join-Path $drv.Root $centralName),
      (Join-Path $drv.Root ($myDriveKo+'\'+$centralName)),
      (Join-Path $drv.Root ('My Drive\'+$centralName)),
      (Join-Path $drv.Root ('Google Drive\'+$centralName))
    )){
      if(Test-Path -LiteralPath $cand -PathType Container){return $cand}
    }
  }
  return ''
}
function SaveJson([string]$Path,$Object){
  if(-not $Path){return}
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  $Object|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $Path -Encoding UTF8
}
function ReadJson([string]$Path){
  if(-not $Path -or -not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function InvokeChild([string]$Path){
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path 2>&1|Out-String
  return [ordered]@{exitCode=$LASTEXITCODE;stdout=$out.Trim()}
}
function LastJson([string]$Text){
  $parsed=$null
  foreach($line in @($Text -split "`r?`n")){
    if(-not $line -or -not $line.Trim()){continue}
    try{$candidate=$line.Trim()|ConvertFrom-Json;if($candidate -and $null -ne $candidate.ok){$parsed=$candidate}}catch{}
  }
  return $parsed
}
function PromoteQueueLocalReceipt([string]$DriveReceipt){
  $result=[ordered]@{checked=$true;promoted=$false;reason='';localPath=$QueueLocalReceipt;drivePath=$DriveReceipt;localReceipt=$null}
  if(-not $DriveReceipt){$result.reason='CENTRAL_DRIVE_NOT_MOUNTED';return $result}
  if(Test-Path -LiteralPath $DriveReceipt){$result.reason='CANONICAL_RECEIPT_ALREADY_PRESENT';return $result}
  $local=ReadJson $QueueLocalReceipt
  $result.localReceipt=$local
  if(-not $local){$result.reason='LOCAL_RECEIPT_NOT_PRESENT';return $result}
  if([string]$local.version -ne $ExpectedQueueVersion){$result.reason='LOCAL_RECEIPT_VERSION_MISMATCH';return $result}
  if([string]$local.status -eq 'PUSH_PULL_READBACK_PASS'){
    if(-not [bool]$local.ok){$result.reason='LOCAL_PASS_STATUS_WITH_OK_FALSE';return $result}
    if([string]$local.sourceSha -ne $ExpectedQueueSourceSha){$result.reason='LOCAL_PASS_SOURCE_SHA_MISMATCH';return $result}
  } elseif([string]$local.status -ne 'FAILED'){
    $result.reason='LOCAL_RECEIPT_STATUS_NOT_TERMINAL';return $result
  }
  SaveJson $DriveReceipt $local
  $result.promoted=$true
  $result.reason=if([bool]$local.ok){'LOCAL_VERIFIED_PASS_PROMOTED_TO_DRIVE'}else{'LOCAL_FAILURE_PROMOTED_TO_DRIVE_FOR_DIAGNOSIS'}
  return $result
}

$central=FindCentralRoot
$runtimeRoot=''
$queueDriveReceipt=''
if($central){
  $runtimeRoot=Join-Path $central 'Runtime_Readback'
  $queueDriveReceipt=Join-Path $runtimeRoot 'AppsScript_QueueIntegrity\NOTEBOOKLM_QUEUE_INTEGRITY_SYNC.json'
}

$errors=@()
$promotion=$null
$previousSha=''
$previousRun=$null
$previousParsed=$null
try{$promotion=PromoteQueueLocalReceipt $queueDriveReceipt}catch{$errors+=('QUEUE_LOCAL_RECEIPT_PROMOTION:'+$_.Exception.Message)}
try{
  $previousSha=FetchPinned $PreviousAgentUrl $PreviousAgent $PreviousAgentSha
  $previousRun=InvokeChild $PreviousAgent
  $previousParsed=LastJson ([string]$previousRun.stdout)
}catch{$errors+=('PREVIOUS_AGENT:'+$_.Exception.Message)}

$previousOk=[bool]($previousSha -eq $PreviousAgentSha -and $previousRun -and [int]$previousRun.exitCode -eq 0 -and $previousParsed -and [bool]$previousParsed.ok)
$queueCanonical=ReadJson $queueDriveReceipt
$queuePass=[bool]($queueCanonical -and [bool]$queueCanonical.ok -and [string]$queueCanonical.status -eq 'PUSH_PULL_READBACK_PASS' -and [string]$queueCanonical.version -eq $ExpectedQueueVersion -and [string]$queueCanonical.sourceSha -eq $ExpectedQueueSourceSha)
$status=if($queuePass -and $previousOk){'QUEUE_RECEIPT_PROMOTED_OR_PRESENT_AND_AGENT_PASS'}elseif($queuePass){'QUEUE_RECEIPT_PASS_PREVIOUS_AGENT_HOLD'}elseif($previousOk){'PREVIOUS_AGENT_PASS_QUEUE_RECEIPT_PENDING'}else{'QUEUE_RECEIPT_RECOVERY_HOLD'}
$receipt=[ordered]@{
  ok=$previousOk
  governanceOk=$previousOk
  queueIntegrityVerified=$queuePass
  action='AGENT_1.1.51_QUEUE_LOCAL_RECEIPT_PROMOTION'
  agentVersion=$AgentVersion
  status=$status
  previousAgentVersion='1.1.50'
  previousAgentSha=$previousSha
  previousExitCode=if($previousRun){$previousRun.exitCode}else{$null}
  previousResult=$previousParsed
  queueReceiptPromotion=$promotion
  queueCanonicalResult=$queueCanonical
  newProjectCreated=$false
  oauthChanged=$false
  scopeChanged=$false
  newDeployment=$false
  newTrigger=$false
  paidGeminiApiCalled=$false
  generateClicked=$false
  creditSpend=$false
  normalChromeRestarted=$false
  retryPolicy='NO_BLIND_RETRY_LOCAL_RECEIPT_FIRST'
  errors=$errors
  at=(Get-Date).ToString('o')
}
if($runtimeRoot){SaveJson (Join-Path $runtimeRoot 'AGENT_1.1.51_QUEUE_LOCAL_RECEIPT_PROMOTION.json') $receipt}
try{
  $s=ReadJson $State
  if(-not $s){$s=[pscustomobject]@{}}
  $s|Add-Member agentVersion $AgentVersion -Force
  $s|Add-Member agentMode 'QUEUE_LOCAL_RECEIPT_PROMOTION_1.1.51' -Force
  $s|Add-Member ok $previousOk -Force
  $s|Add-Member governanceOk $previousOk -Force
  $s|Add-Member queueIntegrityVerified $queuePass -Force
  $s|Add-Member status $status -Force
  $s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force
  SaveJson $State $s
}catch{}
$receipt|ConvertTo-Json -Depth 60 -Compress
if($previousOk){exit 0}else{exit 2}
