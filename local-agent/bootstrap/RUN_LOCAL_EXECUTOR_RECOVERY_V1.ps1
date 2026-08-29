param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$CentralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
$PinnedFlowAgent169='9dce2a7bb83d96a3d846a92e24f468b7a67cb38a'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Api([string]$Path){
  $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Local-Executor-Recovery';'Accept'='application/vnd.github+json'} -TimeoutSec 30
}
function Blob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function Install([string]$RepoPath,[string]$Dest){
  $r=Api $RepoPath;$tmp=$Dest+'.recover';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$actual=(Blob $tmp).ToLowerInvariant();$expected=([string]$r.sha).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SHA_MISMATCH '+$RepoPath+' '+$actual+' '+$expected)};Move-Item $tmp $Dest -Force;return $expected
}
function FindCentral{
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $CentralName),(Join-Path $d.Root ('My Drive\'+$CentralName)),(Join-Path $d.Root ($myDriveKo+'\'+$CentralName)),(Join-Path $d.Root ('Google Drive\'+$CentralName)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  };return ''
}
function Save($o){
  $json=$o|ConvertTo-Json -Depth 50;$json|Set-Content -LiteralPath (Join-Path $Root 'LOCAL_EXECUTOR_RECOVERY_V1.json') -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'LOCAL_EXECUTOR_RECOVERY_V1.json') -Encoding UTF8}
}
function BootstrapLoops{try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
function HostHealthy{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function FreshReceipt([string]$Path,[datetime]$Since){try{return ((Test-Path -LiteralPath $Path -PathType Leaf) -and ((Get-Item -LiteralPath $Path).LastWriteTime -ge $Since.AddSeconds(-2)))}catch{return $false}}

$startedAt=Get-Date;$started=$startedAt.ToString('o');$errors=@();$installed=@{};$loopStarted=$false;$resumeExit=$null;$resumeSkippedBecauseAutoResumeVerified=$false
$autoResumeInstallExit=$null;$autoResumeReceiptFresh=$false;$autoResumeInstallerRevision='';$autoResumeImmediateVerified=$false;$autoResumeDirectWatchdogExit=$null;$taskCreated=$false;$runKeySet=$false;$persistenceReady=$false;$periodicTriggerReady=$false;$fullTriggerContractReady=$false;$triggerContract='';$taskMode='';$multipleInstancesPolicy='';$scheduledEntryObserved=$false;$directWatchdogLaunched=$false
$alwaysOnSyncExit=$null;$alwaysOnReceiptFresh=$false;$alwaysOnSyncOk=$false;$alwaysOnReloadVerified=$false;$alwaysOnReloadPending=$true;$alwaysOnRuntimeVersion='';$alwaysOnUpdatedTargetCount=0;$alwaysOnRuntimeState='AUX_SYNC_NOT_RUN'
$flowCanonicalExit=$null;$flowCanonicalOk=$false;$flowCanonicalSelected='';$flowDirectExit=$null;$flowFallbackInvoked=$false;$flowReceiptFresh=$false;$flowReceiptOk=$false
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1';$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1';$Resume=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1';$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$AutoResumeInstaller=Join-Path $Root 'INSTALL_AUTO_RESUME_TASK.ps1';$AutoResumeReceipt=Join-Path $Root 'AUTO_RESUME_INSTALL_V3.json'
$AlwaysOnUpdater=Join-Path $Root 'Sync-GoogleAIAlwaysOnBridgeV102.ps1';$AlwaysOnReceipt=Join-Path $Root 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC.json'
$FlowVerifier=Join-Path $Root 'Test-FlowCanonicalExtension.ps1';$FlowAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.69-recovery.ps1';$FlowReceipt=Join-Path $Root 'FLOW_DIRECT_BOOTSTRAP_R10_1.1.69.json'
try{$installed.bootstrap=Install 'local-agent/bootstrap/AgentBootstrap.ps1' $Bootstrap}catch{$errors+=('BOOTSTRAP:'+ $_.Exception.Message)}
try{$installed.autoResume=Install 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $AutoResume}catch{$errors+=('AUTORESUME:'+ $_.Exception.Message)}
try{$installed.resume=Install 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1' $Resume}catch{$errors+=('RESUME:'+ $_.Exception.Message)}
try{$installed.watchdog=Install 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog}catch{$errors+=('WATCHDOG:'+ $_.Exception.Message)}
try{$installed.autoResumeInstaller=Install 'local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1' $AutoResumeInstaller}catch{$errors+=('AUTORESUME_INSTALLER:'+ $_.Exception.Message)}
try{$installed.alwaysOnUpdater=Install 'local-agent/governor/Sync-GoogleAIAlwaysOnBridgeV102.ps1' $AlwaysOnUpdater}catch{$errors+=('ALWAYS_ON_UPDATER:'+ $_.Exception.Message)}
try{$installed.flowCanonicalVerifier=Install 'local-agent/governor/Test-FlowCanonicalExtension.ps1' $FlowVerifier}catch{$errors+=('FLOW_VERIFIER:'+ $_.Exception.Message)}
try{$sha=Install 'local-agent/releases/1.1.69/HomeDesignLocalAgent.ps1' $FlowAgent;if($sha.ToLowerInvariant()-ne$PinnedFlowAgent169){throw('FLOW_AGENT_169_PIN_MISMATCH:'+ $sha)};$installed.flowAgent169=$sha}catch{$errors+=('FLOW_AGENT_169:'+ $_.Exception.Message)}

try{
  if(Test-Path -LiteralPath $AutoResumeInstaller -PathType Leaf){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AutoResumeInstaller
    $autoResumeInstallExit=$LASTEXITCODE
    if($autoResumeInstallExit-ne0){$errors+=('AUTORESUME_INSTALL_EXIT_'+$autoResumeInstallExit)}
  }else{throw'AUTORESUME_INSTALLER_MISSING'}
}catch{$errors+=('AUTORESUME_INSTALL_RUN:'+ $_.Exception.Message)}

$autoResumeReceiptFresh=FreshReceipt $AutoResumeReceipt $startedAt
if($autoResumeReceiptFresh){
  try{
    $ar=Get-Content -LiteralPath $AutoResumeReceipt -Raw -Encoding UTF8|ConvertFrom-Json
    $autoResumeInstallerRevision=[string]$ar.installerRevision
    $taskCreated=[bool]$ar.scheduledTaskCreated
    $runKeySet=[bool]$ar.hkcuRunRegistered
    $persistenceReady=[bool]$ar.persistenceReady
    $periodicTriggerReady=[bool]$ar.periodicTriggerReady
    $fullTriggerContractReady=[bool]$ar.fullTriggerContractReady
    $triggerContract=[string]$ar.triggerContract
    $taskMode=[string]$ar.taskMode
    $multipleInstancesPolicy=[string]$ar.multipleInstancesPolicy
    $scheduledEntryObserved=[bool]$ar.scheduledEntryObserved
    $directWatchdogLaunched=[bool]$ar.directWatchdogLaunched
    $autoResumeImmediateVerified=[bool]$ar.immediateExecutionVerified
    if($ar.directWatchdogExit-ne$null){$autoResumeDirectWatchdogExit=[int]$ar.directWatchdogExit}
    if(-not$periodicTriggerReady){$errors+='AUTORESUME_V3_PERIODIC_TRIGGER_NOT_READY'}
    if(-not$persistenceReady){$errors+='AUTORESUME_V3_PERSISTENCE_NOT_READY'}
    if(-not$autoResumeImmediateVerified){$errors+='AUTORESUME_V3_IMMEDIATE_NOT_VERIFIED'}
    if($multipleInstancesPolicy-and$multipleInstancesPolicy-ne'IgnoreNew'){$errors+=('AUTORESUME_MULTIPLE_INSTANCES_POLICY_'+$multipleInstancesPolicy)}
  }catch{$errors+=('AUTORESUME_RECEIPT_READ:'+ $_.Exception.Message)}
}else{$errors+='AUTORESUME_V3_RECEIPT_NOT_FRESH'}

$bootstrapLoopPresent=[bool](@(BootstrapLoops).Count-gt0)
if($autoResumeInstallExit-eq0 -and $autoResumeReceiptFresh -and $periodicTriggerReady -and $persistenceReady -and $autoResumeImmediateVerified){
  $resumeSkippedBecauseAutoResumeVerified=$true
  if(-not$bootstrapLoopPresent){
    try{if(Test-Path -LiteralPath $Bootstrap){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 3;$loopStarted=(@(BootstrapLoops).Count-gt0);$bootstrapLoopPresent=[bool](@(BootstrapLoops).Count-gt0)}}catch{$errors+=('BOOTSTRAP_LOOP_REPAIR:'+ $_.Exception.Message)}
  }
}else{
  $errors+='AUTORESUME_GATE_BLOCKED_FLOW_RECOVERY'
}

# Auxiliary Always-On repair. It preserves the existing unpacked path, config.js and
# NotebookLM content, never restarts normal Chrome, and never spends Flow credits.
# A failure here is recorded but does not block the canonical Flow 0.1.0 / R10 path.
if($autoResumeInstallExit-eq0 -and $periodicTriggerReady -and $persistenceReady -and $autoResumeImmediateVerified -and $bootstrapLoopPresent -and (Test-Path -LiteralPath $AlwaysOnUpdater -PathType Leaf)){
  try{
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AlwaysOnUpdater
    $alwaysOnSyncExit=$LASTEXITCODE
    if($alwaysOnSyncExit-ne0){$errors+=('ALWAYS_ON_AUX_SYNC_EXIT_'+$alwaysOnSyncExit)}
  }catch{$errors+=('ALWAYS_ON_AUX_SYNC_RUN:'+ $_.Exception.Message)}
  $alwaysOnReceiptFresh=FreshReceipt $AlwaysOnReceipt $startedAt
  if($alwaysOnReceiptFresh){
    try{
      $ao=Get-Content -LiteralPath $AlwaysOnReceipt -Raw -Encoding UTF8|ConvertFrom-Json
      $alwaysOnSyncOk=[bool]$ao.ok
      $alwaysOnReloadVerified=[bool]$ao.cdpReloadVerified
      $alwaysOnReloadPending=[bool]$ao.reloadPending
      $alwaysOnRuntimeVersion=[string]$ao.runtimeVersion
      $alwaysOnUpdatedTargetCount=@($ao.updatedTargets).Count
      if($alwaysOnSyncOk-and$alwaysOnReloadVerified-and$alwaysOnRuntimeVersion-eq'1.0.2'){$alwaysOnRuntimeState='V1.0.2_RUNTIME_VERIFIED'}elseif($alwaysOnSyncOk){$alwaysOnRuntimeState='V1.0.2_FILES_SYNCED_RELOAD_PENDING'}else{$alwaysOnRuntimeState='AUX_SYNC_RECEIPT_FAILED'}
    }catch{$errors+=('ALWAYS_ON_AUX_RECEIPT_READ:'+ $_.Exception.Message);$alwaysOnRuntimeState='AUX_SYNC_RECEIPT_READ_FAILED'}
  }else{$errors+='ALWAYS_ON_AUX_RECEIPT_NOT_FRESH';$alwaysOnRuntimeState='AUX_SYNC_NO_FRESH_RECEIPT'}
}else{$alwaysOnRuntimeState='AUX_SYNC_SKIPPED_CORE_GATE_NOT_READY'}

if($autoResumeInstallExit-eq0 -and $periodicTriggerReady -and $persistenceReady -and $autoResumeImmediateVerified -and $bootstrapLoopPresent){
  try{
    if(Test-Path -LiteralPath $FlowVerifier){
      $central=FindCentral
      $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$FlowVerifier)
      if($central){$args+=@('-CentralRootOverride',$central)}
      $out=& powershell.exe @args 2>&1;$flowCanonicalExit=$LASTEXITCODE
      $last=($out|Select-Object -Last 1|Out-String).Trim();if($last){try{$j=$last|ConvertFrom-Json;$flowCanonicalOk=[bool]$j.ok;$flowCanonicalSelected=[string]$j.selectedPath}catch{}}
      if($flowCanonicalExit-ne0-or-not$flowCanonicalOk){$errors+=('FLOW_CANONICAL_EXIT_'+$flowCanonicalExit)}
    }
  }catch{$errors+=('FLOW_CANONICAL:'+ $_.Exception.Message)}
}

Start-Sleep -Seconds 8
$flowReceiptFresh=FreshReceipt $FlowReceipt $startedAt
if(-not$flowReceiptFresh -and $autoResumeInstallExit-eq0 -and $periodicTriggerReady -and $persistenceReady -and $autoResumeImmediateVerified -and $bootstrapLoopPresent -and $flowCanonicalOk -and (Test-Path -LiteralPath $FlowAgent -PathType Leaf)){
  $flowFallbackInvoked=$true
  try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FlowAgent;$flowDirectExit=$LASTEXITCODE;if($flowDirectExit-ne0){$errors+=('FLOW_DIRECT_EXIT_'+$flowDirectExit)}}catch{$errors+=('FLOW_DIRECT:'+ $_.Exception.Message)}
}
$flowReceiptFresh=FreshReceipt $FlowReceipt $startedAt
if($flowReceiptFresh){try{$fr=Get-Content -LiteralPath $FlowReceipt -Raw -Encoding UTF8|ConvertFrom-Json;$flowReceiptOk=[bool]$fr.ok}catch{$errors+=('FLOW_RECEIPT_READ:'+ $_.Exception.Message)}}

Start-Sleep -Seconds 3
$state=$null;try{$sp=Join-Path $Root 'state.json';if(Test-Path $sp){$state=Get-Content $sp -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$bootstrapLoopPresent=[bool](@(BootstrapLoops).Count-gt0)
$hostHealthy=HostHealthy
$coreOk=[bool]($installed.bootstrap -and $installed.autoResume -and $installed.resume -and $installed.watchdog -and $installed.autoResumeInstaller -and $installed.flowCanonicalVerifier -and $installed.flowAgent169 -and ($autoResumeInstallExit-eq0) -and $autoResumeReceiptFresh -and $periodicTriggerReady -and $persistenceReady -and $autoResumeImmediateVerified -and $bootstrapLoopPresent -and $flowCanonicalOk -and $flowReceiptFresh -and $flowReceiptOk)
$rec=[ordered]@{ok=$coreOk;action='LOCAL_EXECUTOR_RECOVERY_V1';recoveryRevision='V1.5_ALWAYS_ON_AUX_SYNC_FLOW_GATE';startedAt=$started;completedAt=(Get-Date).ToString('o');installed=$installed;autoResumeInstallerVersion='V3';autoResumeInstallerRevision=$autoResumeInstallerRevision;autoResumeInstallExit=$autoResumeInstallExit;autoResumeReceiptFresh=$autoResumeReceiptFresh;scheduledTaskCreated=$taskCreated;taskMode=$taskMode;triggerContract=$triggerContract;periodicTriggerReady=$periodicTriggerReady;fullTriggerContractReady=$fullTriggerContractReady;multipleInstancesPolicy=$multipleInstancesPolicy;scheduledEntryObserved=$scheduledEntryObserved;directWatchdogLaunched=$directWatchdogLaunched;hkcuRunRegistered=$runKeySet;persistenceReady=$persistenceReady;autoResumeImmediateExecutionVerified=$autoResumeImmediateVerified;autoResumeDirectWatchdogExit=$autoResumeDirectWatchdogExit;resumeSkippedBecauseAutoResumeVerified=$resumeSkippedBecauseAutoResumeVerified;resumeExit=$resumeExit;bootstrapLoopPresent=$bootstrapLoopPresent;bootstrapLoopStartedThisRun=$loopStarted;hostHealthy=$hostHealthy;alwaysOnUpdaterInstalled=[bool]$installed.alwaysOnUpdater;alwaysOnSyncExit=$alwaysOnSyncExit;alwaysOnReceiptFresh=$alwaysOnReceiptFresh;alwaysOnSyncOk=$alwaysOnSyncOk;alwaysOnUpdatedTargetCount=$alwaysOnUpdatedTargetCount;alwaysOnReloadVerified=$alwaysOnReloadVerified;alwaysOnReloadPending=$alwaysOnReloadPending;alwaysOnRuntimeVersion=$alwaysOnRuntimeVersion;alwaysOnBridgeSourceVersion='1.0.2';alwaysOnBridgeRuntimeState=$alwaysOnRuntimeState;alwaysOnAuxiliaryOnly=$true;flowCanonicalExit=$flowCanonicalExit;flowCanonicalOk=$flowCanonicalOk;flowCanonicalSelectedPath=$flowCanonicalSelected;flowFallbackInvoked=$flowFallbackInvoked;flowDirectExit=$flowDirectExit;flowReceiptFresh=$flowReceiptFresh;flowReceiptOk=$flowReceiptOk;flowExecutionSequence='FLOW_PROJECT_LIST_NEW_PROJECT_V8_20260829';flowExtensionVersion='0.1.0';flowExtensionId='lgedgmpcikglaajhfclcihicgafimlna';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;generateClicked=$false;creditSpend=$false;errors=$errors};Save $rec;$rec|ConvertTo-Json -Depth 50 -Compress;if($coreOk){exit 0}else{exit 2}
