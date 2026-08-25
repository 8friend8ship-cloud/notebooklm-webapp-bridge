param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$AgentStatePath=Join-Path $AgentRoot 'state.json'
$VideoJobStatePath=Join-Path $AgentRoot 'video-job-state.json'
$GovStatePath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$NodeGovPath=Join-Path $GovRoot 'chromeGovernorFast.js'
$PolicyPath=Join-Path $GovRoot 'policy.json'
$ReleasePath=Join-Path $GovRoot 'release.json'
$AgentFile=Join-Path $AgentRoot 'HomeDesignLocalAgent.ps1'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
New-Item -ItemType Directory -Force -Path $AgentRoot,$GovRoot|Out-Null
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function GitHubContent([string]$Path,[string]$Ref='main',[int]$Timeout=10){$Headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'};$Url="https://api.github.com/repos/$Repo/contents/$Path?ref=$([Uri]::EscapeDataString($Ref))";return Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get -TimeoutSec $Timeout}
function DecodeGitHubText($Response){$Raw=([string]$Response.content -replace '\s','');return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Raw))}
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
