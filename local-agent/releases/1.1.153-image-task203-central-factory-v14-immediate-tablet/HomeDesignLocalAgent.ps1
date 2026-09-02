param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.153-image-task203-central-factory-v14-immediate-tablet'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$BasePath='local-agent/releases/1.1.152-image-task203-central-factory-v14/HomeDesignLocalAgent.ps1'
$BaseBlob='d1ee150032ea984032111eb6752c0aa46b3f7e43'
$OldAnalyzer='a31f97cd41c2256dbacd3ad426037743090a11cc'
$NewAnalyzer='3f0265aeb5242bdf245ae93039a4474eb30a186b'
$OldVersion='1.1.152-image-task203-central-factory-v14'
$OldReceipt='IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.152.json'
$NewReceipt='IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.153.json'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
  $all=New-Object byte[]($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  ''
}
function SaveWrapperReceipt($o){
  try{
    $j=$o|ConvertTo-Json -Depth 30
    $p=Join-Path $Root 'IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.153_WRAPPER.json'
    $j|Set-Content -LiteralPath $p -Encoding UTF8
    $c=FindCentral
    if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.153_WRAPPER.json') -Encoding UTF8}
  }catch{}
}

$state=[ordered]@{ok=$false;action='TASK203_1.1.153_PATCHED_OVERLAY_WRAPPER';version=$Version;stage='START';baseBlob=$BaseBlob;analyzerCommit=$NewAnalyzer;patchedRunner='';error='';startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $api='https://api.github.com/repos/'+$Repo+'/contents/'+$BasePath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $r=Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='HomeDesign-Task203-1.1.153';'Accept'='application/vnd.github+json'} -Method Get -TimeoutSec 30
  if(([string]$r.sha).ToLowerInvariant()-ne$BaseBlob){throw('BASE_BLOB_MISMATCH actual='+[string]$r.sha+' expected='+$BaseBlob)}
  $baseFile=Join-Path $Root 'TASK203_1.1.152_BASE_VERIFIED.ps1'
  [IO.File]::WriteAllBytes($baseFile,[Convert]::FromBase64String(([string]$r.content-replace'\s','')))
  if((GitBlobSha1 $baseFile).ToLowerInvariant()-ne$BaseBlob){throw 'BASE_LOCAL_BLOB_MISMATCH'}

  $state.stage='PATCH_PINNED_RUNNER'
  $text=Get-Content -LiteralPath $baseFile -Raw -Encoding UTF8
  if($text-notlike ('*'+$OldAnalyzer+'*')){throw 'OLD_ANALYZER_PIN_NOT_FOUND'}
  if($text-notlike ('*'+$OldVersion+'*')){throw 'OLD_VERSION_NOT_FOUND'}
  if($text-notlike ('*'+$OldReceipt+'*')){throw 'OLD_RECEIPT_NOT_FOUND'}
  $text=$text.Replace($OldAnalyzer,$NewAnalyzer)
  $text=$text.Replace($OldVersion,$Version)
  $text=$text.Replace($OldReceipt,$NewReceipt)
  $patched=Join-Path $Root 'TASK203_1.1.153_PATCHED_RUNNER.ps1'
  Set-Content -LiteralPath $patched -Value $text -Encoding UTF8
  $verify=Get-Content -LiteralPath $patched -Raw -Encoding UTF8
  if($verify-notlike ('*'+$NewAnalyzer+'*')){throw 'NEW_ANALYZER_PIN_MISSING'}
  if($verify-notmatch 'CentralTabletRemoteDispatcher_20260902\.gs'){throw 'TABLET_DISPATCHER_OVERLAY_SOURCE_MISSING'}
  if($verify-notmatch 'ContentOS_Unified_Scheduler\.gs'){throw 'UNIFIED_SCHEDULER_OVERLAY_SOURCE_MISSING'}
  $state.patchedRunner=$patched

  $state.stage='EXECUTE_PATCHED_1.1.153'
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $patched
  $rc=$LASTEXITCODE
  if($rc-ne0){throw('PATCHED_RUNNER_EXIT_'+$rc)}
  $result=Join-Path $Root $NewReceipt
  if(-not(Test-Path -LiteralPath $result -PathType Leaf)){throw '1.1.153_RESULT_RECEIPT_MISSING'}
  $obj=Get-Content -LiteralPath $result -Raw -Encoding UTF8|ConvertFrom-Json
  if((-not [bool]$obj.ok)-or([string]$obj.analyzerCommit).ToLowerInvariant()-ne$NewAnalyzer){throw '1.1.153_RESULT_NOT_VERIFIED'}
  $state.ok=$true;$state.stage='DONE_BOUND_SOURCE_SYNC_VERIFIED_WAIT_FACTORY_WAKE'
}catch{
  $state.error=$_.Exception.Message;$state.stage='ERROR'
}finally{
  $state.completedAt=(Get-Date).ToString('o');SaveWrapperReceipt $state
}
$state|ConvertTo-Json -Depth 30 -Compress
if($state.ok){exit 0}else{exit 2}
