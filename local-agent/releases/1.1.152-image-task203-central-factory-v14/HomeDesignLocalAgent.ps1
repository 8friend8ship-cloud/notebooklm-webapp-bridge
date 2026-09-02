param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.152-image-task203-central-factory-v14'
$BridgeRepo='https://github.com/8friend8ship-cloud/notebooklm-webapp-bridge.git'
$AnalyzerRepo='https://github.com/8friend8ship-cloud/Analyzer-12.09.git'
$AnalyzerCommit='a31f97cd41c2256dbacd3ad426037743090a11cc'
$DiscoveryPath='local-agent/releases/appscript-0.3.0-webapp05-history-exactdeployment-discovery/HomeDesignLocalAgent.ps1'
$DiscoveryBlob='0d168954a5755b0556605dae121ab19adedeb3fe'
$DiscoveryReceipt='APPSCRIPT_DISCOVER_WEBAPP_TEMPLATE_05_BY_HISTORY_EXACT_DEPLOYMENT_0.3.0.json'
$DeploymentId='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.152.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

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
function Save($o){
  $j=$o|ConvertTo-Json -Depth 80
  $j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8
  try{
    $c=FindCentral
    if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}
  }catch{}
}
function GitBlob([string]$Repo,[string]$Path){
  Push-Location $Repo
  try{
    $s=(& git rev-parse ('HEAD:'+$Path) 2>&1|Out-String).Trim().ToLowerInvariant()
    if($LASTEXITCODE-ne0){throw('GIT_OBJECT_SHA_FAILED:'+ $Path)}
    $s
  }finally{Pop-Location}
}
function CloneScript([string]$ScriptId,[string]$Dir){
  New-Item -ItemType Directory -Force -Path $Dir|Out-Null
  Push-Location $Dir
  try{
    & clasp clone-script $ScriptId
    if($LASTEXITCODE-ne0){
      & clasp clone $ScriptId
      if($LASTEXITCODE-ne0){throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED'}
    }
  }finally{Pop-Location}
}
function GetDeployments([string]$ScriptId){
  $t=(& clasp list-deployments $ScriptId 2>&1|Out-String)
  if($LASTEXITCODE-ne0){throw 'CLASP_LIST_DEPLOYMENTS_FAILED'}
  @([regex]::Matches($t,'AKfy[A-Za-z0-9_-]+')|ForEach-Object{$_.Value}|Sort-Object -Unique)
}
function AssertDeployments([string[]]$Before,[string[]]$After){
  if((@($Before|Sort-Object)-join'|')-ne(@($After|Sort-Object)-join'|')){throw 'DEPLOYMENT_SET_CHANGED'}
}
function Layout([string]$Dir){
  $cfg=Join-Path $Dir '.clasp.json';$root=$Dir;$ext='.gs'
  if(Test-Path $cfg){
    $j=Get-Content -LiteralPath $cfg -Raw -Encoding UTF8|ConvertFrom-Json
    if($j.rootDir){$root=[IO.Path]::GetFullPath((Join-Path $Dir ([string]$j.rootDir)))}
  }
  if(-not(Test-Path $root)){throw 'CLASP_ROOT_DIR_MISSING'}
  $gs=@(Get-ChildItem $root -Recurse -File -Filter '*.gs' -ErrorAction SilentlyContinue).Count
  $js=@(Get-ChildItem $root -Recurse -File -Filter '*.js' -ErrorAction SilentlyContinue).Count
  if($js-gt$gs){$ext='.js'}
  [pscustomobject]@{Root=$root;Ext=$ext}
}
function Fingerprint([string]$Dir){
  $root=[IO.Path]::GetFullPath($Dir).TrimEnd([char[]]"\/")
  $parts=@()
  Get-ChildItem $root -Recurse -File -Force|Where-Object{$_.Name-ne'.clasp.json' -and $_.FullName-notmatch'[\\/]\.git[\\/]'}|Sort-Object FullName|ForEach-Object{
    $rel=$_.FullName.Substring($root.Length).TrimStart([char[]]"\/").Replace('\','/')
    $parts+=($rel+':'+(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)
  }
  if($parts.Count-eq0){throw 'SOURCE_FINGERPRINT_EMPTY'}
  $bytes=[Text.Encoding]::UTF8.GetBytes($parts-join"`n")
  $sha=[Security.Cryptography.SHA256]::Create()
  try{([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
}
function EnsureFactoryWakeAdapter([string]$RootDir){
  $pattern='function\s+processTaskQueue\s*\(\s*\)\s*\{'
  $files=@(Get-ChildItem $RootDir -Recurse -File|Where-Object{$_.Extension-in@('.gs','.js')})
  $hits=@()
  foreach($f in $files){if((Get-Content -LiteralPath $f.FullName -Raw)-match$pattern){$hits+=$f}}
  if($hits.Count-ne1){throw('PROCESSTASKQUEUE_DEFINITION_COUNT:'+ $hits.Count)}
  $file=$hits[0];$text=Get-Content -LiteralPath $file.FullName -Raw
  if($text-notmatch'runContentOsScheduledStagesFromFactory\s*\(\s*\)'){
    $adapter="`r`n  try {`r`n    if (typeof runContentOsScheduledStagesFromFactory === 'function') { runContentOsScheduledStagesFromFactory(); }`r`n  } catch (contentOsSchedulerError) {`r`n    console.warn('CONTENTOS_UNIFIED_SCHEDULER_DEGRADED', String(contentOsSchedulerError && contentOsSchedulerError.message || contentOsSchedulerError));`r`n  }"
    $text=[regex]::Replace($text,$pattern,'${0}'+$adapter,1)
    Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8
    return $true
  }
  return $false
}
function UpdateDeploymentStrict([string]$ProjectDir,[string]$Id,[string]$Description){
  Push-Location $ProjectDir
  try{
    & clasp update-deployment $Id --description $Description
    if($LASTEXITCODE-ne0){throw 'EXISTING_DEPLOYMENT_UPDATE_FAILED_NO_CREATE_FALLBACK'}
  }finally{Pop-Location}
}

$r=[ordered]@{
  ok=$false;action='TASK203_CENTRAL_FACTORY_V14_OVERLAY';version=$Version;stage='START';error='';
  discoveryOk=$false;scriptId='';analyzerCommit='';overlayFiles=@();sourceReadback=$false;
  schedulerV14Readback=$false;tabletDispatcherReadback=$false;openAi5Readback=$false;
  deploymentBefore=@();deploymentAfter=@();rollbackAttempted=$false;rollbackOk=$false;
  newAppsScriptProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;
  normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;
  startedAt=(Get-Date).ToString('o');completedAt=''
}
$scriptId='';$snapshot='';$pushed=$false;$deployBefore=@()
try{
  if(-not(Get-Command git -ErrorAction SilentlyContinue)){throw 'GIT_COMMAND_NOT_FOUND'}
  if(-not(Get-Command clasp -ErrorAction SilentlyContinue)){throw 'CLASP_COMMAND_NOT_FOUND_EXISTING_RUNNER_PATH_REQUIRED'}
  $auth=(& clasp show-authorized-user --json 2>&1|Out-String)
  if($LASTEXITCODE-ne0){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'}

  $work=Join-Path $env:TEMP ('task203-central-factory-v14-'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
  $bridge=Join-Path $work 'bridge';$analyzer=Join-Path $work 'analyzer';$live=Join-Path $work 'live';$verify=Join-Path $work 'verify';$snapshot=Join-Path $work 'snapshot';$rollbackVerify=Join-Path $work 'rollback-verify'
  New-Item -ItemType Directory -Force -Path $work|Out-Null
  $oldPrompt=$env:GIT_TERMINAL_PROMPT;$env:GIT_TERMINAL_PROMPT='0'
  try{
    $r.stage='CLONE_BRIDGE_DISCOVERY'
    & git clone --quiet --depth 1 --branch main $BridgeRepo $bridge
    if($LASTEXITCODE-ne0){throw 'BRIDGE_REPO_CLONE_FAILED'}
    if((GitBlob $bridge $DiscoveryPath)-ne$DiscoveryBlob){throw 'DISCOVERY_BLOB_MISMATCH'}
    $discovery=Join-Path $bridge ($DiscoveryPath-replace'/','\')
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $discovery
    if($LASTEXITCODE-ne0){throw 'READONLY_SCRIPT_DISCOVERY_FAILED'}
    $discFile=Join-Path $Root $DiscoveryReceipt
    if(-not(Test-Path -LiteralPath $discFile)){throw 'DISCOVERY_RECEIPT_MISSING'}
    $disc=Get-Content -LiteralPath $discFile -Raw -Encoding UTF8|ConvertFrom-Json
    if((-not [bool]$disc.ok) -or (-not [string]$disc.scriptId)){throw 'DISCOVERY_RECEIPT_NOT_PASS'}
    $scriptId=[string]$disc.scriptId;$r.scriptId=$scriptId;$r.discoveryOk=$true

    $r.stage='CLONE_ANALYZER_CANONICAL'
    & git clone --quiet --depth 1 --branch main $AnalyzerRepo $analyzer
    if($LASTEXITCODE-ne0){throw 'ANALYZER_REPO_CLONE_FAILED'}
    Push-Location $analyzer
    try{$head=(& git rev-parse HEAD 2>&1|Out-String).Trim().ToLowerInvariant()}finally{Pop-Location}
    if($head-ne$AnalyzerCommit){throw('ANALYZER_HEAD_MISMATCH:'+ $head)}
    $r.analyzerCommit=$head
  }finally{$env:GIT_TERMINAL_PROMPT=$oldPrompt}

  $sourceNames=@(
    'ContentOS_Drive_JSON_Cache_V3.gs',
    'ContentOS_Runtime_Registry_V3.gs',
    'ContentOS_Free_Backdata_Pipeline.gs',
    'ContentOS_Unified_Scheduler.gs',
    'Central_Image_Queens_Seed_AutoLearn_V2.gs',
    'ContentOS_Image_Learning_Web_Adapter_V2.gs',
    'ContentOS_DryWriter_Runtime_Config_Repair_20260902.gs',
    'Central_Workflow_Bridge_Crosscheck_20260902.gs',
    'Central_Sheet_Runtime_Audit_Autofix_20260902.gs',
    'Central_Api_Credential_Usage_Audit_20260902.gs',
    'CentralTabletRemoteDispatcher_20260902.gs',
    'OpenAI_5_Worker_Runtime_20260902.gs',
    'ContentOS_Factory_Control_20260823.gs'
  )
  foreach($name in $sourceNames){if(-not(Test-Path -LiteralPath (Join-Path $analyzer ('apps-script\'+$name)))){throw('ANALYZER_SOURCE_MISSING:'+ $name)}}

  $r.stage='CLONE_EXISTING_BOUND_SCRIPT'
  $deployBefore=GetDeployments $scriptId;$r.deploymentBefore=$deployBefore
  if($deployBefore-notcontains$DeploymentId){throw 'EXPECTED_DEPLOYMENT_ID_NOT_FOUND'}
  CloneScript $scriptId $live
  Copy-Item -LiteralPath $live -Destination $snapshot -Recurse -Force
  $snapshotFingerprint=Fingerprint $snapshot
  $layout=Layout $live

  $r.stage='OVERLAY_ANALYZER_CANONICAL_13'
  [void](EnsureFactoryWakeAdapter $layout.Root)
  foreach($name in $sourceNames){
    $src=Join-Path $analyzer ('apps-script\'+$name)
    $base=[IO.Path]::GetFileNameWithoutExtension($name)
    Copy-Item -Force -LiteralPath $src -Destination (Join-Path $layout.Root ($base+$layout.Ext))
    $r.overlayFiles+=$base
  }
  $allText=(Get-ChildItem $layout.Root -Recurse -File|Where-Object{$_.Extension-in@('.gs','.js')}|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw})-join"`n"
  if([regex]::Matches($allText,'runContentOsScheduledStagesFromFactory\s*\(\s*\)').Count-lt2){throw 'FACTORY_WAKE_ADAPTER_MISSING_BEFORE_PUSH'}
  if($allText-notmatch'CONTENTOS_UNIFIED_SCHEDULER_V14_TABLET_FACTORY_20260902'){throw 'SCHEDULER_V14_SOURCE_MISSING'}
  if($allText-notmatch'function\s+runCentralTabletRemoteDispatcherFromFactory\s*\('){throw 'TABLET_DISPATCHER_SOURCE_MISSING'}
  if($allText-notmatch'function\s+runOpenAi5WorkerControlCycleFromFactory\s*\('){throw 'OPENAI5_SOURCE_MISSING'}

  Push-Location $live
  try{& clasp push --force;if($LASTEXITCODE-ne0){throw 'CLASP_PUSH_FAILED'}}finally{Pop-Location}
  $pushed=$true

  $r.stage='CLONE_READBACK_VERIFY'
  CloneScript $scriptId $verify
  $vl=Layout $verify
  foreach($name in $sourceNames){
    $base=[IO.Path]::GetFileNameWithoutExtension($name)
    if(@(Get-ChildItem $vl.Root -Recurse -File|Where-Object{$_.BaseName-eq$base}).Count-ne1){throw('READBACK_FILE_COUNT_INVALID:'+ $base)}
  }
  $verifyText=(Get-ChildItem $vl.Root -Recurse -File|Where-Object{$_.Extension-in@('.gs','.js')}|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw})-join"`n"
  $r.schedulerV14Readback=($verifyText-match'CONTENTOS_UNIFIED_SCHEDULER_V14_TABLET_FACTORY_20260902')
  $r.tabletDispatcherReadback=($verifyText-match'function\s+runCentralTabletRemoteDispatcherFromFactory\s*\(')
  $r.openAi5Readback=($verifyText-match'function\s+runOpenAi5WorkerControlCycleFromFactory\s*\(')
  $r.sourceReadback=($r.schedulerV14Readback -and $r.tabletDispatcherReadback -and $r.openAi5Readback -and ([regex]::Matches($verifyText,'runContentOsScheduledStagesFromFactory\s*\(\s*\)').Count -ge 2))
  if(-not$r.sourceReadback){throw 'CENTRAL_FACTORY_SOURCE_READBACK_FAILED'}

  $r.stage='UPDATE_EXISTING_DEPLOYMENT_ONLY'
  UpdateDeploymentStrict $verify $DeploymentId ('Central factory V14 tablet remote '+(Get-Date -Format 'yyyyMMdd_HHmmss'))
  $r.deploymentAfter=GetDeployments $scriptId
  AssertDeployments $deployBefore $r.deploymentAfter
  $r.ok=$true;$r.stage='DONE_WAIT_NATURAL_FACTORY_WAKE'
}catch{
  $r.error=$_.Exception.Message;$r.stage='ERROR'
  if($pushed-and$scriptId-and(Test-Path $snapshot)){
    $r.rollbackAttempted=$true
    try{
      Push-Location $snapshot
      try{& clasp push --force;if($LASTEXITCODE-ne0){throw 'ROLLBACK_PUSH_FAILED'}}finally{Pop-Location}
      UpdateDeploymentStrict $snapshot $DeploymentId ('Central factory V14 rollback '+(Get-Date -Format 'yyyyMMdd_HHmmss'))
      AssertDeployments $deployBefore (GetDeployments $scriptId)
      CloneScript $scriptId $rollbackVerify
      if((Fingerprint $rollbackVerify)-ne$snapshotFingerprint){throw 'ROLLBACK_FINGERPRINT_MISMATCH'}
      $r.rollbackOk=$true
    }catch{$r.error+=';ROLLBACK='+$_.Exception.Message}
  }
}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}
