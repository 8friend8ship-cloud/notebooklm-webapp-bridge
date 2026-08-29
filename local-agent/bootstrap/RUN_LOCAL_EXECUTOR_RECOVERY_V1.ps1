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

$startedAt=Get-Date;$started=$startedAt.ToString('o');$errors=@();$installed=@{};$loopStarted=$false;$resumeExit=$null
$autoResumeInstallExit=$null;$autoResumeReceiptFresh=$false;$autoResumeImmediateVerified=$false;$autoResumeDirectWatchdogExit=$null;$taskCreated=$false;$runKeySet=$false;$persistenceReady=$false
$flowCanonicalExit=$null;$flowCanonicalOk=$false;$flowCanonicalSelected='';$flowDirectExit=$null;$flowFallbackInvoked=$false;$flowReceiptFresh=$false;$flowReceiptOk=$false
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1';$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1';$Resume=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1';$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$AutoResumeInstaller=Join-Path $Root 'INSTALL_AUTO_RESUME_TASK.ps1';$AutoResumeReceipt=Join-Path $Root 'AUTO_RESUME_INSTALL_V3.json'
$FlowVerifier=Join-Path $Root 'Test-FlowCanonicalExtension.ps1';$FlowAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.69-recovery.ps1';$FlowReceipt=Join-Path $Root 'FLOW_DIRECT_BOOTSTRAP_R10_1.1.69.json'
try{$installed.bootstrap=Install 'local-agent/bootstrap/AgentBootstrap.ps1' $Bootstrap}catch{$errors+=('BOOTSTRAP:'+ $_.Exception.Message)}
try{$installed.autoResume=Install 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $AutoResume}catch{$errors+=('AUTORESUME:'+ $_.Exception.Message)}
try{$installed.resume=Install 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1' $Resume}catch{$errors+=('RESUME:'+ $_.Exception.Message)}
try{$installed.watchdog=Install 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog}catch{$errors+=('WATCHDOG:'+ $_.Exception.Message)}
try{$installed.autoResumeInstaller=Install 'local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1' $AutoResumeInstaller}catch{$errors+=('AUTORESUME_INSTALLER:'+ $_.Exception.Message)}
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
    $taskCreated=[bool]$ar.scheduledTaskCreated
    $runKeySet=[bool]$ar.hkcuRunRegistered
    $persistenceReady=[bool]$ar.persistenceReady
    $autoResumeImmediateVerified=[bool]$ar.immediateExecutionVerified
    if($ar.directWatchdogExit-ne$null){$autoResumeDirectWatchdogExit=[int]$ar.directWatchdogExit}
    if(-not$autoResumeImmediateVerified){$errors+='AUTORESUME_V3_IMMEDIATE_NOT_VERIFIED'}
  }catch{$errors+=('AUTORESUME_RECEIPT_READ:'+ $_.Exception.Message)}
}else{$errors+='AUTORESUME_V3_RECEIPT_NOT_FRESH'}

try{
  foreach($p in @(BootstrapLoops)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Seconds 1
  if(Test-Path -LiteralPath $Bootstrap){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 3;$loopStarted=(@(BootstrapLoops).Count-gt0)}
}catch{$errors+=('BOOTSTRAP_LOOP:'+ $_.Exception.Message)}

try{
  if(Test-Path -LiteralPath $Resume){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Resume;$resumeExit=$LASTEXITCODE}else{throw'RESUME_FILE_MISSING'}
}catch{$errors+=('RESUME_RUN:'+ $_.Exception.Message)}

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

Start-Sleep -Seconds 8
$flowReceiptFresh=FreshReceipt $FlowReceipt $startedAt
if(-not$flowReceiptFresh -and $flowCanonicalOk -and $autoResumeImmediateVerified -and (Test-Path -LiteralPath $FlowAgent -PathType Leaf)){
  $flowFallbackInvoked=$true
  try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FlowAgent;$flowDirectExit=$LASTEXITCODE;if($flowDirectExit-ne0){$errors+=('FLOW_DIRECT_EXIT_'+$flowDirectExit)}}catch{$errors+=('FLOW_DIRECT:'+ $_.Exception.Message)}
}
$flowReceiptFresh=FreshReceipt $FlowReceipt $startedAt
if($flowReceiptFresh){try{$fr=Get-Content -LiteralPath $FlowReceipt -Raw -Encoding UTF8|ConvertFrom-Json;$flowReceiptOk=[bool]$fr.ok}catch{$errors+=('FLOW_RECEIPT_READ:'+ $_.Exception.Message)}}

Start-Sleep -Seconds 3
$state=$null;try{$sp=Join-Path $Root 'state.json';if(Test-Path $sp){$state=Get-Content $sp -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$bootstrapLoopPresent=[bool](@(BootstrapLoops).Count-gt0)
$ok=[bool]($installed.bootstrap -and $installed.autoResume -and $installed.resume -and $installed.watchdog -and $installed.autoResumeInstaller -and $installed.flowCanonicalVerifier -and $installed.flowAgent169 -and $autoResumeReceiptFresh -and $persistenceReady -and $autoResumeImmediateVerified -and $bootstrapLoopPresent -and $flowCanonicalOk -and $flowReceiptFresh -and $flowReceiptOk)
$rec=[ordered]@{ok=$ok;action='LOCAL_EXECUTOR_RECOVERY_V1';recoveryRevision='V1.3_AUTOREUME_V3_FLOW_CANONICAL_R10_GATE';startedAt=$started;completedAt=(Get-Date).ToString('o');installed=$installed;autoResumeInstallerVersion='V3';autoResumeInstallExit=$autoResumeInstallExit;autoResumeReceiptFresh=$autoResumeReceiptFresh;scheduledTaskCreated=$taskCreated;hkcuRunRegistered=$runKeySet;persistenceReady=$persistenceReady;autoResumeImmediateExecutionVerified=$autoResumeImmediateVerified;autoResumeDirectWatchdogExit=$autoResumeDirectWatchdogExit;bootstrapLoopPresent=$bootstrapLoopPresent;bootstrapLoopStartedThisRun=$loopStarted;resumeExit=$resumeExit;hostHealthy=(HostHealthy);flowCanonicalExit=$flowCanonicalExit;flowCanonicalOk=$flowCanonicalOk;flowCanonicalSelectedPath=$flowCanonicalSelected;flowFallbackInvoked=$flowFallbackInvoked;flowDirectExit=$flowDirectExit;flowReceiptFresh=$flowReceiptFresh;flowReceiptOk=$flowReceiptOk;flowExecutionSequence='FLOW_PROJECT_LIST_NEW_PROJECT_V8_20260829';flowExtensionVersion='0.1.0';flowExtensionId='lgedgmpcikglaajhfclcihicgafimlna';alwaysOnBridgeSourceVersion='1.0.2';alwaysOnBridgeRuntimeState='LOCAL_RELOAD_PENDING';stateAgentVersion=$(if($state){[string]$state.agentVersion}else{''});stateStatus=$(if($state){[string]$state.status}else{''});normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;generateClicked=$false;creditSpend=$false;errors=$errors};Save $rec;$rec|ConvertTo-Json -Depth 50 -Compress;if($ok){exit 0}else{exit 2}
