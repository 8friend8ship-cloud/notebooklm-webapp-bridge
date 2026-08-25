param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor,[switch]$ApplyStableBridge,[switch]$ApplyStableBridgeChild,[switch]$BridgeStatusOnly)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$BackupRoot=Join-Path $AgentRoot 'Backups'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$AgentStatePath=Join-Path $AgentRoot 'state.json'
$VideoJobStatePath=Join-Path $AgentRoot 'video-job-state.json'
$GovStatePath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$NodeGovPath=Join-Path $GovRoot 'chromeGovernorFast.js'
$PolicyPath=Join-Path $GovRoot 'policy.json'
$ReleasePath=Join-Path $GovRoot 'release.json'
$AgentFile=Join-Path $AgentRoot 'HomeDesignLocalAgent.ps1'
$BridgeApplyResultPath=Join-Path $AgentRoot 'NOTEBOOKLM_BRIDGE_APPLY_RESULT.json'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
New-Item -ItemType Directory -Force -Path $AgentRoot,$GovRoot,$ExtensionRoot,$BackupRoot|Out-Null
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function GitHubContent([string]$Path,[string]$Ref='main',[int]$Timeout=10){$Headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'};$Url="https://api.github.com/repos/$Repo/contents/$Path?ref=$([Uri]::EscapeDataString($Ref))";return Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get -TimeoutSec $Timeout}
function DecodeGitHubText($Response){$Raw=([string]$Response.content -replace '\s','');return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Raw))}
function FindChrome(){if(-not(Test-Path -LiteralPath $CftRoot)){return $null};return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}
function Dedicated(){try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"})}catch{return @()}}
function StopDedicated(){foreach($P in @(Dedicated)){try{Stop-Process -Id ([int]$P.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}};Start-Sleep -Seconds 2}
function LaunchDedicated([string]$Front){$C=FindChrome;if(-not $C){throw 'Chrome for Testing executable not found'};$Args=@("--user-data-dir=$DedicatedUserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$Front);$Psi=New-Object Diagnostics.ProcessStartInfo;$Psi.FileName=$C.FullName;$Psi.WorkingDirectory=$C.Directory.FullName;$Psi.UseShellExecute=$false;$Psi.Arguments=QuoteArgs $Args;[void][Diagnostics.Process]::Start($Psi);$Deadline=(Get-Date).AddSeconds(12);do{Start-Sleep -Milliseconds 500}while((Dedicated).Count -le 0 -and (Get-Date)-lt $Deadline);if((Dedicated).Count -le 0){throw 'Dedicated Chrome did not remain running'}}
function GetBridgeRelease{$Resp=GitHubContent 'runtime/stable/release.json' 'main' 10;$Rel=(DecodeGitHubText $Resp)|ConvertFrom-Json;if(-not $Rel.enabled){throw 'BRIDGE_STABLE_DISABLED'};if([string]$Rel.action -ne 'apply'){throw 'BRIDGE_STABLE_ACTION_NOT_APPLY'};if([bool]$Rel.requiresUserApproval){throw 'BRIDGE_RELEASE_REQUIRES_USER_APPROVAL'};return $Rel}
function TestBridgeRelease($Rel){foreach($F in @($Rel.files)){$Rp=[string]$F.path;if($Rp -match '\.\.' -or [IO.Path]::IsPathRooted($Rp)){return $false};$P=Join-Path $ExtensionRoot $Rp.Replace('/','\');if(-not(Test-Path -LiteralPath $P)){return $false};if((GitBlobSha1 $P).ToLowerInvariant() -ne ([string]$F.gitBlobSha1).ToLowerInvariant()){return $false}};return $true}
function FindCentral{
  $Target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($D in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$R=[string]$D.Root;if(-not $R){continue};foreach($C in @((Join-Path $R $Target),(Join-Path $R ('My Drive\'+$Target)),(Join-Path $R ('내 드라이브\'+$Target)),(Join-Path $R ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}}
  foreach($C in @((Join-Path $env:USERPROFILE ('My Drive\'+$Target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$Target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}
  return ''
}
function WriteBridgeResult($Result){
  $Result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $BridgeApplyResultPath -Encoding UTF8
  $Central=FindCentral
  if($Central){try{$D=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $D|Out-Null;$Result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $D 'NOTEBOOKLM_BRIDGE_APPLY_RESULT.json') -Encoding UTF8;$Result.driveWritebackOk=$true;$Result.centralPath=$Central;$Result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $BridgeApplyResultPath -Encoding UTF8}catch{}}
}
function RunBridgeApply{
  $Started=(Get-Date).ToString('o');$Result=[ordered]@{ok=$false;action='APPLY_STABLE_NOTEBOOKLM_BRIDGE_116_LINEAGE';startedAt=$Started;targetVersion='';installedBefore='';installedAfter='';releaseActionId='';integrityOk=$false;dedicatedChromeRunning=$false;normalChromeUntouched=$true;rollbackUsed=$false;driveWritebackOk=$false;centralPath='';backupPath='';error=''}
  $BackupExtension='';$Front='https://notebooklm-webapp-bridge.vercel.app'
  try{
    $Rel=GetBridgeRelease;$Result.targetVersion=[string]$Rel.version;$Result.releaseActionId=[string]$Rel.actionId;$Front=[string]$Rel.frontUrl
    $OldManifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');if($OldManifest){$Result.installedBefore=[string]$OldManifest.version}
    if((TestBridgeRelease $Rel) -and $Result.installedBefore -eq [string]$Rel.version){if((Dedicated).Count -le 0){LaunchDedicated $Front};$Result.ok=$true;$Result.installedAfter=$Result.installedBefore;$Result.integrityOk=$true;$Result.dedicatedChromeRunning=((Dedicated).Count -gt 0);$Result.completedAt=(Get-Date).ToString('o');WriteBridgeResult $Result;return $Result}
    $Stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff';$Stage=Join-Path $AgentRoot ('BridgeStage\'+$Stamp);$Backup=Join-Path $BackupRoot ('Bridge_'+$Stamp);$BackupExtension=Join-Path $Backup 'extension';New-Item -ItemType Directory -Force -Path $Stage,$Backup|Out-Null;$Result.backupPath=$BackupExtension
    foreach($F in @($Rel.files)){
      $Rp=[string]$F.path;if($Rp -match '\.\.' -or [IO.Path]::IsPathRooted($Rp)){throw "Unsafe release path: $Rp"}
      $Dst=Join-Path $Stage $Rp.Replace('/','\');$Par=Split-Path $Dst -Parent;if($Par){New-Item -ItemType Directory -Force -Path $Par|Out-Null}
      $Url=([string]$Rel.baseUrl).TrimEnd('/')+'/'+$Rp+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dst -TimeoutSec 12
      $Actual=(GitBlobSha1 $Dst).ToLowerInvariant();$Expected=([string]$F.gitBlobSha1).ToLowerInvariant();if($Actual -ne $Expected){throw "Extension hash mismatch path=$Rp actual=$Actual expected=$Expected"}
    }
    if(Test-Path -LiteralPath $ExtensionRoot){Copy-Item -LiteralPath $ExtensionRoot -Destination $BackupExtension -Recurse -Force}
    StopDedicated
    try{
      Get-ChildItem -LiteralPath $ExtensionRoot -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force
      Copy-Item (Join-Path $Stage '*') $ExtensionRoot -Recurse -Force
      if(-not(TestBridgeRelease $Rel)){throw 'Installed extension verification failed'}
      $NewManifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');if(-not $NewManifest -or [string]$NewManifest.version -ne [string]$Rel.version){throw 'Installed manifest version mismatch'}
      LaunchDedicated $Front
    }catch{
      $InstallError=$_.Exception.Message
      if(Test-Path -LiteralPath $BackupExtension){$Result.rollbackUsed=$true;StopDedicated;Get-ChildItem -LiteralPath $ExtensionRoot -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force;Copy-Item (Join-Path $BackupExtension '*') $ExtensionRoot -Recurse -Force;try{LaunchDedicated $Front}catch{} }
      throw $InstallError
    }
    $FinalManifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$Result.installedAfter=$(if($FinalManifest){[string]$FinalManifest.version}else{''});$Result.integrityOk=TestBridgeRelease $Rel;$Result.dedicatedChromeRunning=((Dedicated).Count -gt 0);$Result.ok=($Result.installedAfter -eq [string]$Rel.version -and $Result.integrityOk -and $Result.dedicatedChromeRunning);if(-not $Result.ok){throw 'BRIDGE_POST_APPLY_VERIFY_FAILED'}
  }catch{$Result.error=$_.Exception.Message;$Result.ok=$false;$Final=ReadJson (Join-Path $ExtensionRoot 'manifest.json');if($Final){$Result.installedAfter=[string]$Final.version};$Result.dedicatedChromeRunning=((Dedicated).Count -gt 0)}
  $Result.completedAt=(Get-Date).ToString('o');WriteBridgeResult $Result;return $Result
}
function RuntimeStatus($GovernorRun=$null){
  $A=ReadJson $AgentStatePath;$J=ReadJson $VideoJobStatePath;$G=ReadJson $GovStatePath;$M=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$H=HostHealth
  return [ordered]@{
    ok=$true;action='LOCAL_RUNTIME_STATUS_FAST_V2';at=(Get-Date).ToString('o')
    agentVersion=$(if($A){[string]$A.agentVersion}else{'UNKNOWN'});agentStatus=$(if($A){[string]$A.status}else{'UNKNOWN'});agentMode=$(if($A){[string]$A.agentMode}else{''})
    hostHealthy=$(if($H){[bool]$H.ok}else{$false});hostVersion=$(if($H){[string]$H.version}else{'UNKNOWN'});hostAsyncJobs=$(if($H){[bool]$H.asyncJobs}else{$false})
    bridgeVersion=$(if($M){[string]$M.version}else{'UNKNOWN'});videoWorkerVersion=$(if($A -and $A.videoWorkerVersion){[string]$A.videoWorkerVersion}elseif($J -and $J.workerVersion){[string]$J.workerVersion}else{''});videoWorkerInstalled=$(if($A -and $null -ne $A.videoWorkerInstalled){[bool]$A.videoWorkerInstalled}else{$false});videoWorkerRunning=$(if($A -and $null -ne $A.videoWorkerRunning){[bool]$A.videoWorkerRunning}else{$false});videoJobState=$J
    governorRun=$GovernorRun;governorCycleOk=$(if($A -and $null -ne $A.governorCycleOk){[bool]$A.governorCycleOk}elseif($G -and $null -ne $G.ok){[bool]$G.ok}else{$false});governorSummary=$(if($G){$G.summary}else{$null});governorDriveSyncOk=$(if($A -and $null -ne $A.governorDriveSyncOk){[bool]$A.governorDriveSyncOk}else{$false});governorCentralPath=$(if($A){[string]$A.governorCentralPath}else{''});errors=$(if($A){$A.errors}else{$null});lastError=$(if($A){[string]$A.lastError}else{''})
  }
}
function RunNodeLocal{
  if(-not(Test-Path $NodeGovPath) -or -not(Test-Path $PolicyPath) -or -not(Test-Path $ReleasePath)){return [ordered]@{ok=$false;exitCode=2;error='LOCAL_GOVERNOR_INPUT_MISSING'}}
  $Node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $Node){$Node=Get-Command node -ErrorAction SilentlyContinue};if(-not $Node){return [ordered]@{ok=$false;exitCode=127;error='NODE_NOT_FOUND'}}
  $Args=@($NodeGovPath,'--normalRoot',$NormalRoot,'--dedicatedUserData',$DedicatedUserData,'--dedicatedExtensionRoot',$ExtensionRoot,'--policy',$PolicyPath,'--release',$ReleasePath,'--agentState',$AgentStatePath,'--report',$GovStatePath,'--inventory',$InventoryPath)
  $Psi=New-Object Diagnostics.ProcessStartInfo;$Psi.FileName=$Node.Source;$Psi.UseShellExecute=$false;$Psi.CreateNoWindow=$true;$Psi.RedirectStandardOutput=$true;$Psi.RedirectStandardError=$true;$Psi.Arguments=QuoteArgs $Args
  $P=New-Object Diagnostics.Process;$P.StartInfo=$Psi;[void]$P.Start();$OT=$P.StandardOutput.ReadToEndAsync();$ET=$P.StandardError.ReadToEndAsync();if(-not $P.WaitForExit(30000)){KillTree ([int]$P.Id);try{[void]$P.WaitForExit(3000)}catch{};return [ordered]@{ok=$false;exitCode=124;timedOut=$true;error='NODE_GOVERNOR_LOCAL_TIMEOUT_30S';stdout=$(if($OT.IsCompleted){$OT.Result.Trim()}else{''});stderr=$(if($ET.IsCompleted){$ET.Result.Trim()}else{''})}};$P.WaitForExit();return [ordered]@{ok=($P.ExitCode -eq 0);exitCode=$P.ExitCode;timedOut=$false;stdout=$(if($OT.IsCompleted){$OT.Result.Trim()}else{''});stderr=$(if($ET.IsCompleted){$ET.Result.Trim()}else{''})}
}
if($ApplyStableBridgeChild){$R=RunBridgeApply;$R|ConvertTo-Json -Depth 30 -Compress;if($R.ok){exit 0}else{exit 2}}
if($ApplyStableBridge){
  $Args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$PSCommandPath`"",'-ApplyStableBridgeChild')
  $P=Start-Process powershell.exe -ArgumentList $Args -WindowStyle Hidden -PassThru
  [ordered]@{ok=$true;action='APPLY_STABLE_BRIDGE_BACKGROUND_START';childPid=$P.Id;resultPath=$BridgeApplyResultPath;lineage='AGENT_1.1.6_INSTALL_RELEASE';normalChromeUntouched=$true;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
  exit 0
}
if($BridgeStatusOnly){
  try{$Rel=GetBridgeRelease;$M=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$H=HostHealth;$Integrity=TestBridgeRelease $Rel;$Apply=ReadJson $BridgeApplyResultPath;$S=[ordered]@{ok=([bool]($M -and [string]$M.version -eq [string]$Rel.version -and $Integrity -and $H -and $H.ok));action='BRIDGE_STATUS_ONLY';at=(Get-Date).ToString('o');targetBridge=[string]$Rel.version;bridgeVersion=$(if($M){[string]$M.version}else{'UNKNOWN'});integrityOk=[bool]$Integrity;hostHealthy=$(if($H){[bool]$H.ok}else{$false});hostVersion=$(if($H){[string]$H.version}else{'UNKNOWN'});hostAsyncJobs=$(if($H){[bool]$H.asyncJobs}else{$false});dedicatedChromeRunning=((Dedicated).Count -gt 0);applyResult=$Apply};$S|ConvertTo-Json -Depth 30 -Compress;if($S.ok){exit 0}else{exit 2}}catch{[ordered]@{ok=$false;action='BRIDGE_STATUS_ONLY';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}
}
if($StatusOnly){RuntimeStatus|ConvertTo-Json -Depth 30 -Compress;exit 0}
if($RunGovernor){$R=RunNodeLocal;$S=RuntimeStatus $R;$S|ConvertTo-Json -Depth 30 -Compress;if($R.ok){exit 0}else{exit 2}}
if($KickStableAgent){
  try{
    $MetaResp=GitHubContent 'local-agent/stable/agent.json' 'main' 10;$Meta=(DecodeGitHubText $MetaResp)|ConvertFrom-Json;if(-not $Meta.enabled){throw 'LOCAL_AGENT_STABLE_DISABLED'}
    $Target=[string]$Meta.version;$Expected=([string]$Meta.gitBlobSha1).ToLowerInvariant();$A=ReadJson $AgentStatePath;$Current=$(if($A){[string]$A.agentVersion}else{''});$LocalSha=$(if(Test-Path $AgentFile){(GitBlobSha1 $AgentFile).ToLowerInvariant()}else{''})
    $Action='KICK_STABLE_AGENT_COORDINATOR_CYCLE_API'
    if($Current -ne $Target -or $LocalSha -ne $Expected){
      $ReleaseResp=GitHubContent ("local-agent/releases/$Target/HomeDesignLocalAgent.ps1") 'main' 10;if(([string]$ReleaseResp.sha).ToLowerInvariant() -ne $Expected){throw "AGENT_API_SHA_MISMATCH api=$($ReleaseResp.sha) expected=$Expected"}
      $Bytes=[Convert]::FromBase64String(([string]$ReleaseResp.content -replace '\s',''));$Tmp=$AgentFile+'.api.download';[IO.File]::WriteAllBytes($Tmp,$Bytes);$Actual=(GitBlobSha1 $Tmp).ToLowerInvariant();if($Actual -ne $Expected){Remove-Item $Tmp -Force -ErrorAction SilentlyContinue;throw "AGENT_FILE_SHA_MISMATCH actual=$Actual expected=$Expected"};Move-Item $Tmp $AgentFile -Force;$LocalSha=$Actual;$Action='KICK_STABLE_AGENT_APPLY_API'
    }
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$AgentFile`"") -WindowStyle Hidden|Out-Null
    [ordered]@{ok=$true;action=$Action;currentAgent=$Current;targetAgent=$Target;expectedSha=$Expected;localAgentSha=$LocalSha;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 0
  }catch{[ordered]@{ok=$false;action='KICK_STABLE_AGENT_API';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}
}
RuntimeStatus|ConvertTo-Json -Depth 30 -Compress
exit 0
