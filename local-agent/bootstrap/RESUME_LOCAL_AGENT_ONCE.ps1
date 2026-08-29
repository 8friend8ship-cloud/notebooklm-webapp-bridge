param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$AgentFile=Join-Path $Root 'HomeDesignLocalAgent.ps1'
$StateFile=Join-Path $Root 'state.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function ApiContent([string]$Path){
  $headers=@{'User-Agent'='HomeDesign-Local-Agent-Resume';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
}
function DecodeText($R){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$R.content-replace'\s','')))}
function WriteApiFile($R,[string]$Path){[IO.File]::WriteAllBytes($Path,[Convert]::FromBase64String(([string]$R.content-replace'\s','')))}
function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function StopTarget([string]$Needle){foreach($procItem in @(Proc $Needle)){KillTree -ProcessId ([int]$procItem.ProcessId)}}
function GitBlobSha1([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0));$all=New-Object byte[] ($header.Length+$bytes.Length);[Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length);$sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}}
function TestHostHealth(){try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function SafeKey([string]$Value){return ([string]$Value -replace '[^A-Za-z0-9_.-]','_')}
function FindCentralRoot{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $rr=[string]$drv.Root;if(-not $rr){continue}
    foreach($cand in @((Join-Path $rr $centralName),(Join-Path $rr ($myDriveKo+'\'+$centralName)),(Join-Path $rr ('My Drive\'+$centralName)),(Join-Path $rr ('Google Drive\'+$centralName)))){if(Test-Path -LiteralPath $cand -PathType Container){return $cand}}
  };return ''
}
function WriteResumeHeartbeat([string]$Stage){
  try{$hb=[ordered]@{ok=$true;action='AUTO_RESUME_ENTRY_HEARTBEAT';version='RESUME_CONTENTS_API_V3_20260829';stage=$Stage;pid=$PID;hostHealthy=(TestHostHealth);newOAuth=$false;newScope=$false;newProjectCreated=$false;newDeployment=$false;newTrigger=$false;normalChromeRestarted=$false;at=(Get-Date).ToString('o')};$json=$hb|ConvertTo-Json -Depth 20;$local=Join-Path $Root 'AUTO_RESUME_ENTRY_LATEST.json';$json|Set-Content -LiteralPath $local -Encoding UTF8;$central=FindCentralRoot;if($central){$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest 'AUTO_RESUME_ENTRY_LATEST.json') -Encoding UTF8}}catch{}
}
function BootstrapLoopProcesses{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
function EnsureBootstrapLoop([string]$BootstrapPath,[int]$TimeoutSeconds=120){
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds);$attempts=0
  while((Get-Date)-lt $deadline){$loops=@(BootstrapLoopProcesses);if($loops.Count -gt 0){Start-Sleep -Milliseconds 900;$loops2=@(BootstrapLoopProcesses);if($loops2.Count -gt 0){return [ordered]@{ok=$true;state='EXISTING_LOOP_VERIFIED';attempts=$attempts;pids=@($loops2|ForEach-Object{[int]$_.ProcessId})}}};$m=$null;$free=$false;try{$m=New-Object System.Threading.Mutex($false,'HomeDesignLocalAgentBootstrapV1');$free=$m.WaitOne(0,$false);if($free){try{$m.ReleaseMutex()}catch{}}}catch{$free=$false}finally{if($m){$m.Dispose()}};if($free){$attempts++;Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapPath`"",'-Loop') -WindowStyle Hidden;Start-Sleep -Seconds 2;$started=@(BootstrapLoopProcesses);if($started.Count -gt 0){Start-Sleep -Seconds 2;$stable=@(BootstrapLoopProcesses);if($stable.Count -gt 0){return [ordered]@{ok=$true;state='NEW_LOOP_STARTED_VERIFIED';attempts=$attempts;pids=@($stable|ForEach-Object{[int]$_.ProcessId})}}}};Start-Sleep -Seconds 3}
  [ordered]@{ok=$false;state='BOOTSTRAP_LOOP_VERIFY_TIMEOUT';attempts=$attempts;pids=@()}
}

WriteResumeHeartbeat 'ENTRY_BEFORE_CONTENTS_API_RESOLVE'
StopTarget 'RunChromeGovernorReadback.ps1';StopTarget 'ChromeExtensionGovernor.ps1';StopTarget 'GovernorDriveSync.ps1';Start-Sleep -Milliseconds 500

Write-Host '[1/5] Refreshing bootstrap through GitHub Contents API...'
$b=ApiContent 'local-agent/bootstrap/AgentBootstrap.ps1';$tmp=$Bootstrap+'.download';WriteApiFile $b $tmp;if((GitBlobSha1 $tmp).ToLowerInvariant()-ne([string]$b.sha).ToLowerInvariant()){throw'BOOTSTRAP_CONTENTS_API_SHA_MISMATCH'};Move-Item $tmp $Bootstrap -Force

Write-Host '[2/5] Resolving current stable Agent + Bridge through GitHub Contents API...'
$metaResp=ApiContent 'local-agent/stable/agent.json';$meta=(DecodeText $metaResp)|ConvertFrom-Json
$bridgeResp=ApiContent 'runtime/stable/release.json';$bridge=(DecodeText $bridgeResp)|ConvertFrom-Json
if(-not $meta.enabled){throw'Local Agent stable channel disabled.'};if(-not $bridge.enabled){throw'NotebookLM bridge stable channel disabled.'}
$targetAgent=[string]$meta.version;$targetBridge=[string]$bridge.version;Write-Host ("targetAgent="+$targetAgent+" targetBridge="+$targetBridge)

Write-Host '[3/5] Downloading and SHA-verifying stable Agent from Contents API...'
$expectedSha=([string]$meta.gitBlobSha1).ToLowerInvariant();$agentResp=ApiContent ('local-agent/releases/'+$targetAgent+'/HomeDesignLocalAgent.ps1');if(([string]$agentResp.sha).ToLowerInvariant()-ne$expectedSha){throw('AGENT_CONTENTS_API_SHA_MISMATCH api='+[string]$agentResp.sha+' expected='+$expectedSha)};$agentTmp=$AgentFile+'.resume.download';WriteApiFile $agentResp $agentTmp;$actualSha=GitBlobSha1 $agentTmp;if($actualSha-ne$expectedSha){Remove-Item $agentTmp -Force -ErrorAction SilentlyContinue;throw("Agent SHA mismatch: actual=$actualSha expected=$expectedSha")};Move-Item $agentTmp $AgentFile -Force

Write-Host '[4/5] Applying stable Agent directly...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AgentFile;$directExit=$LASTEXITCODE;Write-Host ("directAgentExit="+$directExit)

$verifyKey='A'+(SafeKey $targetAgent)+'_B'+(SafeKey $targetBridge);$verifyMarker=Join-Path $Root ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.attempted');$verifyResult=Join-Path $Root ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.json')
if(-not(Test-Path -LiteralPath $verifyMarker)){
  $attempt=[ordered]@{ok=$false;action='NOTEBOOKLM_CDP_DOWNLOAD_VERSIONED_RETEST';changedCondition=$true;agentVersion=$targetAgent;bridgeVersion=$targetBridge;releaseActionId=[string]$bridge.actionId;verifyKey=$verifyKey;startedAt=(Get-Date).ToString('o');stdout='';exitCode=$null;error=''}
  try{$helper=Join-Path $Root 'RunNotebookLMExistingDownloadViaCDP.ps1';$hr=ApiContent 'local-agent/governor/RunNotebookLMExistingDownloadViaCDP.ps1';WriteApiFile $hr $helper;if((GitBlobSha1 $helper).ToLowerInvariant()-ne([string]$hr.sha).ToLowerInvariant()){throw'CDP_HELPER_CONTENTS_API_SHA_MISMATCH'};$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper 2>&1|Out-String;$attempt.stdout=$out.Trim();$attempt.exitCode=$LASTEXITCODE;$attempt.ok=($LASTEXITCODE-eq0)}catch{$attempt.error=$_.Exception.Message;$attempt.ok=$false};$attempt.completedAt=(Get-Date).ToString('o');$json=$attempt|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath $verifyResult -Encoding UTF8;Set-Content -LiteralPath $verifyMarker -Value $attempt.completedAt -Encoding ASCII;try{$central=FindCentralRoot;if($central){$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.json')) -Encoding UTF8}}catch{}
}else{Write-Host ('CDP versioned retest already attempted for '+$verifyKey+'; same-condition retry blocked.')}

Write-Host '[5/5] Ensuring future bootstrap loop (mutex-safe)...'
$loopState=EnsureBootstrapLoop $Bootstrap 120;Write-Host ('bootstrapLoop='+($loopState|ConvertTo-Json -Compress));if(-not $loopState.ok){throw('BOOTSTRAP_LOOP_NOT_VERIFIED:'+($loopState|ConvertTo-Json -Compress))};WriteResumeHeartbeat ('BOOTSTRAP_LOOP_'+[string]$loopState.state)

$deadline=(Get-Date).AddSeconds(180)
while((Get-Date)-lt$deadline){Start-Sleep -Seconds 3;if(Test-Path -LiteralPath $StateFile){try{$last=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;$av=[string]$last.agentVersion;$hv=[string]$last.commandHostVersion;$hr=TestHostHealth;$bv=[string]$last.extensionVersion;if(-not$bv){$bv=[string]$last.installedVersion};$gov=[bool]$last.governorCycleOk;$sync=[bool]$last.governorDriveSyncOk;Write-Host("agent="+$av+" host="+$hv+" hostHealth="+$hr+" bridge="+$bv+" status="+[string]$last.status+" governor="+$gov+" driveSync="+$sync);if($av-eq$targetAgent-and$hr-and$bv-eq$targetBridge-and$gov-and$sync){Write-Host'RESUME RESULT: ACTIVE + GOVERNOR VERIFIED';exit 0};if($av-eq$targetAgent-and$hr-and$bv-eq$targetBridge-and$directExit-eq0){Write-Host'RESUME RESULT: ACTIVE; GOVERNOR READBACK STILL SYNCING';exit 0}}catch{}}}
Write-Host 'RESUME RESULT: STARTED, RUNTIME READBACK STILL PENDING';Write-Host 'Do not reinstall or reauthorize. Bootstrap loop was verified and remains enabled.';exit 2
