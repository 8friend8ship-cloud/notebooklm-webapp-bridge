param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor,[switch]$ApplyStableBridge,[switch]$BridgeStatusOnly,[switch]$BridgeLocalEvidence,[switch]$VideoFailureDiagnostic,[switch]$FlowDirectRecoveryDiagnostic,[switch]$CaptureBridgeSmoke,[switch]$InteriorAppsScriptSync,[switch]$InspectNotebookLMDownloads,[switch]$DownloadExistingNotebookArtifactViaCDP,[string]$CentralRelativePath='',[string]$SmokeFile='',[string]$ExpectedBridge='0.2.18')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$V2=Join-Path $Root 'RunChromeGovernorReadbackV2.ps1'
$AgentFile=Join-Path $Root 'HomeDesignLocalAgent.ps1'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Api="https://api.github.com/repos/$Repo/contents/local-agent/governor/RunChromeGovernorReadbackV2.ps1?ref=main"
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function ReadTail([string]$Path,[int]$Max=12000){if(-not(Test-Path -LiteralPath $Path)){return ''};try{$T=Get-Content -LiteralPath $Path -Raw -Encoding UTF8;if($T.Length -gt $Max){return $T.Substring([Math]::Max(0,$T.Length-$Max))};return $T}catch{return ('READ_ERROR: '+$_.Exception.Message)}}
function FindCentralRoot {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($candidate in @((Join-Path $r $target),(Join-Path $r ('My Drive\\'+$target)),(Join-Path $r ('내 드라이브\\'+$target)),(Join-Path $r ('Google Drive\\'+$target)))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  }
  return ''
}
function VideoFailureEvidence {
  $StatePath=Join-Path $Root 'video-job-state.json';$MetaPath=Join-Path $Root 'video-production-job.json';$ConsolePath=Join-Path $Root 'video-job-console.log';$Prod=Join-Path $Base 'VideoProduction';$Recent=@()
  if(Test-Path -LiteralPath $Prod){foreach($D in @(Get-ChildItem -LiteralPath $Prod -Directory -Filter 'AUTO_QA_V3_*' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 4)){$QaLogs=@();foreach($Q in @('QA_PASS_1','QA_PASS_2')){$P=Join-Path $D.FullName ('out\\'+$Q+'\\qa-console.log');if(Test-Path -LiteralPath $P){$QaLogs+=[ordered]@{pass=$Q;path=$P;text=(ReadTail $P 8000)}}};$Recent+=[ordered]@{path=$D.FullName;lastWrite=$D.LastWriteTime.ToString('o');autoQaLog=(ReadTail (Join-Path $D.FullName 'auto-qa.log') 8000);qaLogs=$QaLogs}}}
  return [ordered]@{jobState=(ReadJson $StatePath);jobMeta=(ReadJson $MetaPath);workerConsole=(ReadTail $ConsolePath 12000);recentRuns=$Recent}
}
function GitBlobSha1([string]$Path){$B=[IO.File]::ReadAllBytes($Path);$H=[Text.Encoding]::ASCII.GetBytes(('blob '+$B.Length+[char]0));$A=New-Object byte[] ($H.Length+$B.Length);[Buffer]::BlockCopy($H,0,$A,0,$H.Length);[Buffer]::BlockCopy($B,0,$A,$H.Length,$B.Length);$S=[Security.Cryptography.SHA1]::Create();try{return (($S.ComputeHash($A)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$S.Dispose()}}
function GetBridgeReleaseRaw {
  $Url='https://raw.githubusercontent.com/'+$Repo+'/main/runtime/stable/release.json?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $Text=(Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 10).Content
  $Rel=$Text|ConvertFrom-Json
  if(-not $Rel.enabled){throw 'BRIDGE_STABLE_DISABLED'}
  if([string]$Rel.action -ne 'apply'){throw 'BRIDGE_STABLE_ACTION_NOT_APPLY'}
  if([bool]$Rel.requiresUserApproval){throw 'BRIDGE_RELEASE_REQUIRES_USER_APPROVAL'}
  return $Rel
}
function TestBridgeRelease($Rel){foreach($F in @($Rel.files)){$Rp=[string]$F.path;if($Rp -match '\\.\\.' -or [IO.Path]::IsPathRooted($Rp)){return $false};$P=Join-Path $ExtensionRoot $Rp.Replace('/','\\');if(-not(Test-Path -LiteralPath $P)){return $false};if((GitBlobSha1 $P).ToLowerInvariant() -ne ([string]$F.gitBlobSha1).ToLowerInvariant()){return $false}};return $true}
function DedicatedRunning {try{return (@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"}).Count -gt 0)}catch{return $false}}
function RefreshV2 {
  try{
    $Headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
    $Resp=Invoke-RestMethod -Uri $Api -Headers $Headers -Method Get -TimeoutSec 10
    $Bytes=[Convert]::FromBase64String(([string]$Resp.content -replace '\s',''))
    $Tmp=$V2+'.download'
    [IO.File]::WriteAllBytes($Tmp,$Bytes)
    Move-Item -LiteralPath $Tmp -Destination $V2 -Force
    return $true
  }catch{
    return (Test-Path -LiteralPath $V2)
  }
}
function StopStaleAgentProcesses([int]$MaxAgeSeconds=600){$Killed=@();$Now=Get-Date;try{foreach($P in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)){$Cmd=[string]$P.CommandLine;if(-not $Cmd){continue};if($Cmd -notmatch '(?i)HomeDesignLocalAgent(?:-1\\.1\\.\\d+-patched)?\\.ps1'){continue};$Created=$null;try{$Created=[datetime]$P.CreationDate}catch{};if(-not $Created){continue};$Age=[Math]::Floor(($Now-$Created).TotalSeconds);if($Age -le $MaxAgeSeconds){continue};try{& taskkill.exe /PID ([int]$P.ProcessId) /T /F 2>$null|Out-Null;$Killed+=[ordered]@{pid=[int]$P.ProcessId;ageSeconds=[int]$Age;commandLine=$Cmd}}catch{}}}catch{};return @($Killed)}
function KickStableAgentRaw {
  if(-not(RefreshV2)){throw 'V2_API_STABLE_HELPER_REFRESH_FAILED'}
  $OldEap=$ErrorActionPreference
  $ErrorActionPreference='Continue'
  try{
    $Out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $V2 -KickStableAgent 2>&1 | Out-String
    $Rc=$LASTEXITCODE
  }finally{
    $ErrorActionPreference=$OldEap
  }
  if($Rc -ne 0){throw ('V2_API_STABLE_KICK_FAILED_EXIT_'+$Rc+': '+$Out.Trim())}
  $Parsed=$null
  foreach($Line in @($Out -split "`r?`n")){
    if(-not $Line -or -not $Line.Trim()){continue}
    try{$Candidate=$Line.Trim()|ConvertFrom-Json;if($Candidate -and $null -ne $Candidate.ok){$Parsed=$Candidate}}catch{}
  }
  if(-not $Parsed -or -not [bool]$Parsed.ok){throw ('V2_API_STABLE_KICK_NO_PASS_JSON: '+$Out.Trim())}
  return $Parsed
}

if($DownloadExistingNotebookArtifactViaCDP){
  try{
    $helper=Join-Path $Root 'RunNotebookLMExistingDownloadViaCDP.ps1'
    $url='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/RunNotebookLMExistingDownloadViaCDP.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $tmp=$helper+'.download'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 20
    Move-Item -LiteralPath $tmp -Destination $helper -Force
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper
    $rc=$LASTEXITCODE
    if($rc -ne 0){exit $rc}
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_EXISTING_DOWNLOAD_CDP_TRUSTED_CLICK';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($InspectNotebookLMDownloads){
  try{
    $dir=Join-Path $env:USERPROFILE 'Downloads'
    if(-not(Test-Path -LiteralPath $dir)){throw 'WINDOWS_DOWNLOADS_NOT_FOUND'}
    $ext=@('.xlsx','.xls','.csv','.pdf','.pptx','.ppt','.mp3','.m4a','.wav','.mp4','.webm','.txt','.docx','.doc','.png','.jpg','.jpeg')
    $now=Get-Date
    $items=@(Get-ChildItem -LiteralPath $dir -File -ErrorAction Stop | Where-Object {$ext -contains $_.Extension.ToLowerInvariant()} | Sort-Object LastWriteTime -Descending | Select-Object -First 30 | ForEach-Object {
      [ordered]@{name=$_.Name;fullName=$_.FullName;size=[int64]$_.Length;lastWriteTime=$_.LastWriteTime.ToString('o');ageSeconds=[int][Math]::Max(0,($now-$_.LastWriteTime).TotalSeconds)}
    })
    $target=@($items | Where-Object {$_.name -ieq 'contentos-stage-table.xlsx'})
    [ordered]@{ok=$true;action='NOTEBOOKLM_DOWNLOADS_INSPECT';folder=$dir;targetName='contentos-stage-table.xlsx';targetFound=(@($target).Count -gt 0);target=$target;recent=$items;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 20 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_DOWNLOADS_INSPECT';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($InteriorAppsScriptSync){
  try{
    $ScriptId='1nj9yVonD6rVBdpPMqI2Qzsi7LYGruZMi8XYt6_07xHMI9HH4NEMXHIZQ'
    $Branch='feat/estimate-marketplace-personalization-20260825'
    $Stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $Work=Join-Path $env:TEMP ('INTERIOR_APPS_SCRIPT_SYNC_'+$Stamp)
    $Backup=Join-Path $env:USERPROFILE ('Downloads\\INTERIOR_APPS_SCRIPT_BACKUP_'+$Stamp+'.zip')
    New-Item -ItemType Directory -Force -Path $Work|Out-Null
    Set-Content -LiteralPath (Join-Path $Work '.clasp.json') -Value ('{"scriptId":"'+$ScriptId+'","rootDir":"."}') -Encoding UTF8
    Push-Location $Work
    try{
      & npx --yes '@google/clasp@latest' pull
      if($LASTEXITCODE -ne 0){throw 'CLASP_PULL_FAILED'}
      $pulled=Get-ChildItem -LiteralPath $Work -File -Recurse|Where-Object{$_.Name -ne '.clasp.json'}
      if(@($pulled).Count -lt 1){throw 'CLASP_PULL_EMPTY'}
      Compress-Archive -Path (Join-Path $Work '*') -DestinationPath $Backup -Force
      $src='https://raw.githubusercontent.com/8friend8ship-cloud/interior/'+$Branch+'/apps-script/InteriorMarketplaceRuntime_20260825.gs?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      $target=Get-ChildItem -LiteralPath $Work -File|Where-Object{$_.BaseName -eq 'InteriorMarketplaceRuntime_20260825'}|Select-Object -First 1
      if(-not $target){$target=Get-Item -LiteralPath (New-Item -ItemType File -Path (Join-Path $Work 'InteriorMarketplaceRuntime_20260825.gs') -Force)}
      Invoke-WebRequest -UseBasicParsing -Uri $src -OutFile $target.FullName -TimeoutSec 20
      $code=Get-Content -LiteralPath $target.FullName -Raw -Encoding UTF8
      if($code -notmatch 'INTERIOR_MARKETPLACE_RUNTIME_V2_20260827'){throw 'INTERIOR_RUNTIME_V2_MARKER_MISSING'}
      & npx --yes '@google/clasp@latest' push --force
      if($LASTEXITCODE -ne 0){throw 'CLASP_PUSH_FAILED'}
      & npx --yes '@google/clasp@latest' run inspectInteriorMarketplaceTriggers
      $inspect1=$LASTEXITCODE
      if($inspect1 -eq 0){
        & npx --yes '@google/clasp@latest' run installInteriorMarketplaceTriggers
        $install=$LASTEXITCODE
        if($install -eq 0){& npx --yes '@google/clasp@latest' run inspectInteriorMarketplaceTriggers;$inspect2=$LASTEXITCODE}else{$inspect2=-1}
      }else{$install=-1;$inspect2=-1}
      [ordered]@{ok=$true;action='INTERIOR_APPS_SCRIPT_SYNC';sourcePush=$true;scriptId=$ScriptId;runtimeMarker='INTERIOR_MARKETPLACE_RUNTIME_V2_20260827';backup=$Backup;targetFile=$target.Name;inspectBeforeExit=$inspect1;installExit=$install;inspectAfterExit=$inspect2;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
      exit 0
    } finally { Pop-Location }
  } catch {
    [ordered]@{ok=$false;action='INTERIOR_APPS_SCRIPT_SYNC';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}
if($FlowDirectRecoveryDiagnostic){
  $taskId='FLOW_SCRIPT_ID_DIRECT_RECOVERY_20260825_02';$hostResult=$null;$hostError=''
  try{$hostResult=Invoke-RestMethod -Uri ('http://127.0.0.1:8765/result?taskId='+[Uri]::EscapeDataString($taskId)) -Method Get -TimeoutSec 5}catch{$hostError=$_.Exception.Message}
  $central=FindCentralRoot;$readbackPath='';$readback=$null
  if($central){$candidate=Join-Path (Join-Path $central 'Runtime_Readback') 'FLOW_SCRIPT_ID_RECOVERY_RESULT_20260825_R2.json';if(Test-Path -LiteralPath $candidate){$readbackPath=$candidate;$readback=ReadJson $candidate}}
  [ordered]@{ok=$true;action='FLOW_DIRECT_RECOVERY_DIAGNOSTIC';at=(Get-Date).ToString('o');taskId=$taskId;hostResult=$hostResult;hostError=$hostError;centralRoot=$central;readbackPath=$readbackPath;readback=$readback}|ConvertTo-Json -Depth 40 -Compress
  exit 0
}
if($CaptureBridgeSmoke){
  try{
    $central=FindCentralRoot;if(-not $central){throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'}
    $rel=[string]$CentralRelativePath
    $rel=$rel.Trim()
    $rel=$rel -replace '^[\\/]+',''
    $prefix='00_중앙에이전트\\';if($rel.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$rel=$rel.Substring($prefix.Length)}
    $rel=$rel.Replace('/','\\')
    if(-not $rel.StartsWith('CaptureBridge\\',[StringComparison]::OrdinalIgnoreCase)){throw 'CAPTUREBRIDGE_PATH_NOT_ALLOWLISTED'}
    if($rel -match '(^|\\)\.\.(\\|$)' -or [IO.Path]::IsPathRooted($rel)){throw 'CAPTUREBRIDGE_PATH_INVALID'}
    $name=[string]$SmokeFile;if([string]::IsNullOrWhiteSpace($name)){throw 'SMOKE_FILE_REQUIRED'}
    if($name -ne [IO.Path]::GetFileName($name) -or $name -notmatch '^_SMOKE_CAPTUREBRIDGE_[A-Za-z0-9_.-]+\.txt$'){throw 'SMOKE_FILE_NOT_ALLOWLISTED'}
    $dir=Join-Path $central $rel;New-Item -ItemType Directory -Force -Path $dir|Out-Null
    $path=Join-Path $dir $name;$body=('CAPTUREBRIDGE_SMOKE_PASS '+(Get-Date).ToString('o'));Set-Content -LiteralPath $path -Value $body -Encoding UTF8
    $exists=Test-Path -LiteralPath $path;$len=$(if($exists){(Get-Item -LiteralPath $path).Length}else{0})
    [ordered]@{ok=[bool]$exists;action='CAPTUREBRIDGE_SMOKE_WRITE';at=(Get-Date).ToString('o');centralRoot=$central;relativePath=$rel;localPath=$path;fileName=$name;exists=[bool]$exists;size=[int64]$len}|ConvertTo-Json -Depth 10 -Compress
    exit $(if($exists){0}else{2})
  }catch{[ordered]@{ok=$false;action='CAPTUREBRIDGE_SMOKE_WRITE';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}
}
if($BridgeLocalEvidence){$Manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$Apply=ReadJson (Join-Path $Root 'NOTEBOOKLM_BRIDGE_APPLY_RESULT.json');$State=ReadJson (Join-Path $Root 'state.json');$Health=$null;try{$Health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{};$Dedicated=DedicatedRunning;$BridgeVersion=$(if($Manifest){[string]$Manifest.version}else{'UNKNOWN'});$Rel=$null;$ReleaseError='';$IntegrityEvidence=$false;try{$Rel=GetBridgeReleaseRaw;$IntegrityEvidence=TestBridgeRelease $Rel}catch{$ReleaseError=$_.Exception.Message};$Target=$(if($Rel){[string]$Rel.version}else{$ExpectedBridge});$Healthy=($BridgeVersion -eq $Target -and $IntegrityEvidence -and $Health -and [bool]$Health.ok -and [bool]$Health.asyncJobs -and $Dedicated);[ordered]@{ok=$true;transportOk=$true;healthy=[bool]$Healthy;action='BRIDGE_LOCAL_EVIDENCE';at=(Get-Date).ToString('o');expectedBridge=$ExpectedBridge;targetBridge=$Target;bridgeVersion=$BridgeVersion;integrityEvidence=[bool]$IntegrityEvidence;integritySource='RAW_RELEASE_LIVE';releaseError=$ReleaseError;hostHealthy=$(if($Health){[bool]$Health.ok}else{$false});hostVersion=$(if($Health){[string]$Health.version}else{'UNKNOWN'});hostAsyncJobs=$(if($Health){[bool]$Health.asyncJobs}else{$false});dedicatedChromeRunning=[bool]$Dedicated;agentVersion=$(if($State){[string]$State.agentVersion}else{'UNKNOWN'});agentStatus=$(if($State){[string]$State.status}else{'UNKNOWN'});applyResult=$Apply}|ConvertTo-Json -Depth 30 -Compress;exit 0}
if($BridgeStatusOnly){try{$Rel=GetBridgeReleaseRaw;$Manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$Health=$null;try{$Health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{};$Integrity=TestBridgeRelease $Rel;$Dedicated=DedicatedRunning;$Apply=ReadJson (Join-Path $Root 'NOTEBOOKLM_BRIDGE_APPLY_RESULT.json');$Healthy=($Manifest -and [string]$Manifest.version -eq [string]$Rel.version -and $Integrity -and $Health -and [bool]$Health.ok -and [bool]$Health.asyncJobs -and $Dedicated);[ordered]@{ok=[bool]$Healthy;transportOk=$true;healthy=[bool]$Healthy;action='BRIDGE_STATUS_ONLY';at=(Get-Date).ToString('o');targetBridge=[string]$Rel.version;bridgeVersion=$(if($Manifest){[string]$Manifest.version}else{'UNKNOWN'});integrityOk=[bool]$Integrity;integritySource='RAW_RELEASE_LIVE';hostHealthy=$(if($Health){[bool]$Health.ok}else{$false});hostVersion=$(if($Health){[string]$Health.version}else{'UNKNOWN'});hostAsyncJobs=$(if($Health){[bool]$Health.asyncJobs}else{$false});dedicatedChromeRunning=[bool]$Dedicated;applyResult=$Apply}|ConvertTo-Json -Depth 30 -Compress}catch{[ordered]@{ok=$false;transportOk=$true;healthy=$false;action='BRIDGE_STATUS_ONLY';integritySource='RAW_RELEASE_LIVE';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress};exit 0}
if($VideoFailureDiagnostic){[ordered]@{ok=$true;action='VIDEO_FAILURE_DIAGNOSTIC';at=(Get-Date).ToString('o');videoFailureDiagnostic=(VideoFailureEvidence)}|ConvertTo-Json -Depth 30 -Compress;exit 0}
if($StatusOnly){$A=ReadJson (Join-Path $Root 'state.json');$J=ReadJson (Join-Path $Root 'video-job-state.json');$G=ReadJson (Join-Path $Base 'ChromeGovernor\\state.json');$M=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$H=$null;try{$H=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{};[ordered]@{ok=$true;action='LOCAL_RUNTIME_STATUS_FAST_V2';at=(Get-Date).ToString('o');agentVersion=$(if($A){[string]$A.agentVersion}else{'UNKNOWN'});agentStatus=$(if($A){[string]$A.status}else{'UNKNOWN'});agentMode=$(if($A){[string]$A.agentMode}else{''});hostHealthy=$(if($H){[bool]$H.ok}else{$false});hostVersion=$(if($H){[string]$H.version}else{'UNKNOWN'});hostAsyncJobs=$(if($H){[bool]$H.asyncJobs}else{$false});bridgeVersion=$(if($M){[string]$M.version}else{'UNKNOWN'});videoWorkerVersion=$(if($A -and $A.videoWorkerVersion){[string]$A.videoWorkerVersion}elseif($J -and $J.workerVersion){[string]$J.workerVersion}else{''});videoWorkerInstalled=$(if($A -and $null -ne $A.videoWorkerInstalled){[bool]$A.videoWorkerInstalled}else{$false});videoWorkerRunning=$(if($A -and $null -ne $A.videoWorkerRunning){[bool]$A.videoWorkerRunning}else{$false});videoJobState=$J;governorRun=$null;governorCycleOk=$(if($A -and $null -ne $A.governorCycleOk){[bool]$A.governorCycleOk}elseif($G -and $null -ne $G.ok){[bool]$G.ok}else{$false});governorSummary=$(if($G){$G.summary}else{$null});governorDriveSyncOk=$(if($A -and $null -ne $A.governorDriveSyncOk){[bool]$A.governorDriveSyncOk}else{$false});governorCentralPath=$(if($A){[string]$A.governorCentralPath}else{''});errors=$(if($A){$A.errors}else{$null});lastError=$(if($A){[string]$A.lastError}else{''});videoFailureDiagnostic=(VideoFailureEvidence)}|ConvertTo-Json -Depth 30 -Compress;exit 0}
if($KickStableAgent){try{(KickStableAgentRaw)|ConvertTo-Json -Depth 10 -Compress;exit 0}catch{[ordered]@{ok=$false;action='KICK_STABLE_AGENT_RAW_BACKGROUND';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}}
$NeedRefresh=($RunGovernor -or $ApplyStableBridge -or $BridgeStatusOnly -or -not(Test-Path -LiteralPath $V2));if($NeedRefresh){if(-not(RefreshV2)){[ordered]@{ok=$false;action='V2_FAST_CONTROL_BOOTSTRAP';error='V2_FETCH_FAILED_AND_NO_LOCAL_COPY';at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}}
$ChildArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$V2);if($RunGovernor){$ChildArgs+='-RunGovernor'};if($ApplyStableBridge){$ChildArgs+='-ApplyStableBridge'};if($BridgeStatusOnly){$ChildArgs+='-BridgeStatusOnly'};& powershell.exe @ChildArgs;$Rc=$LASTEXITCODE;if($BridgeStatusOnly){exit 0};exit $Rc