param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$AgentFile=Join-Path $Root 'HomeDesignLocalAgent.ps1'
$StateFile=Join-Path $Root 'state.json'
$BootstrapUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/AgentBootstrap.ps1'
$AgentMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
$AgentBaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases'
$BridgeReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function StopTarget([string]$Needle){foreach($procItem in @(Proc $Needle)){KillTree -ProcessId ([int]$procItem.ProcessId)}}
function GitBlobSha1([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0));$all=New-Object byte[] ($header.Length+$bytes.Length);[Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length);$sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}}
function TestHostHealth(){try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
function SafeKey([string]$Value){return ([string]$Value -replace '[^A-Za-z0-9_.-]','_')}
function FindCentralRoot{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $rr=[string]$drv.Root;if(-not $rr){continue}
    foreach($cand in @((Join-Path $rr $centralName),(Join-Path $rr ($myDriveKo+'\'+$centralName)),(Join-Path $rr ('My Drive\'+$centralName)),(Join-Path $rr ('Google Drive\'+$centralName)))){
      if(Test-Path -LiteralPath $cand -PathType Container){return $cand}
    }
  }
  return ''
}
function WriteResumeHeartbeat([string]$Stage){
  try{
    $hb=[ordered]@{ok=$true;action='AUTO_RESUME_ENTRY_HEARTBEAT';version='RESUME_TELEMETRY_V2_20260829';stage=$Stage;pid=$PID;hostHealthy=(TestHostHealth);newOAuth=$false;newScope=$false;newProjectCreated=$false;newDeployment=$false;newTrigger=$false;normalChromeRestarted=$false;at=(Get-Date).ToString('o')}
    $json=$hb|ConvertTo-Json -Depth 20
    $local=Join-Path $Root 'AUTO_RESUME_ENTRY_1.1.46.json'
    $json|Set-Content -LiteralPath $local -Encoding UTF8
    $central=FindCentralRoot
    if($central){
      $dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null
      $json|Set-Content -LiteralPath (Join-Path $dest 'AUTO_RESUME_ENTRY_1.1.46.json') -Encoding UTF8
    }
  }catch{}
}
function BootstrapLoopProcesses{
  try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{
    $_.Name -match 'powershell|pwsh' -and $_.CommandLine -and
    $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'
  })}catch{return @()}
}
function EnsureBootstrapLoop([string]$BootstrapPath,[int]$TimeoutSeconds=120){
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
  $attempts=0
  while((Get-Date)-lt $deadline){
    $loops=@(BootstrapLoopProcesses)
    if($loops.Count -gt 0){
      Start-Sleep -Milliseconds 900
      $loops2=@(BootstrapLoopProcesses)
      if($loops2.Count -gt 0){return [ordered]@{ok=$true;state='EXISTING_LOOP_VERIFIED';attempts=$attempts;pids=@($loops2|ForEach-Object{[int]$_.ProcessId})}}
    }

    # AgentBootstrap uses this mutex. If a one-shot bootstrap currently owns it,
    # starting a new -Loop process immediately would exit. Wait until it is free,
    # release our test acquisition, then start exactly one loop and verify it lives.
    $m=$null;$free=$false
    try{
      $m=New-Object System.Threading.Mutex($false,'HomeDesignLocalAgentBootstrapV1')
      $free=$m.WaitOne(0,$false)
      if($free){try{$m.ReleaseMutex()}catch{}}
    }catch{$free=$false}
    finally{if($m){$m.Dispose()}}

    if($free){
      $attempts++
      Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapPath`"",'-Loop') -WindowStyle Hidden
      Start-Sleep -Seconds 2
      $started=@(BootstrapLoopProcesses)
      if($started.Count -gt 0){
        Start-Sleep -Seconds 2
        $stable=@(BootstrapLoopProcesses)
        if($stable.Count -gt 0){return [ordered]@{ok=$true;state='NEW_LOOP_STARTED_VERIFIED';attempts=$attempts;pids=@($stable|ForEach-Object{[int]$_.ProcessId})}}
      }
    }
    Start-Sleep -Seconds 3
  }
  return [ordered]@{ok=$false;state='BOOTSTRAP_LOOP_VERIFY_TIMEOUT';attempts=$attempts;pids=@()}
}

Write-Host 'HomeDesign Local Agent - SAFE DIRECT RESUME'
Write-Host 'No reinstall / no new OAuth / no Apps Script redeploy / normal Chrome untouched.'
WriteResumeHeartbeat 'ENTRY_BEFORE_NETWORK_AND_AGENT_APPLY'

# Only stale governor/readback processes are cleaned. Healthy Host/Bootstrap stay alive.
StopTarget 'RunChromeGovernorReadback.ps1'
StopTarget 'ChromeExtensionGovernor.ps1'
StopTarget 'GovernorDriveSync.ps1'
Start-Sleep -Milliseconds 500

$nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
Write-Host '[1/5] Refreshing bootstrap without stopping the current loop...'
$tmp=$Bootstrap+'.download'
Invoke-WebRequest -UseBasicParsing -Uri (Bust $BootstrapUrl $nonce) -OutFile $tmp -TimeoutSec 60
Move-Item -LiteralPath $tmp -Destination $Bootstrap -Force

Write-Host '[2/5] Resolving current stable Agent + Bridge...'
$meta=Invoke-RestMethod -Uri (Bust $AgentMetaUrl ($nonce+'-agent')) -Method Get -TimeoutSec 30
$bridge=Invoke-RestMethod -Uri (Bust $BridgeReleaseUrl ($nonce+'-bridge')) -Method Get -TimeoutSec 30
if(-not $meta.enabled){throw 'Local Agent stable channel disabled.'}
if(-not $bridge.enabled){throw 'NotebookLM bridge stable channel disabled.'}
$targetAgent=[string]$meta.version
$targetBridge=[string]$bridge.version
Write-Host ("targetAgent="+$targetAgent+" targetBridge="+$targetBridge)

Write-Host '[3/5] Downloading and SHA-verifying stable Agent...'
$agentTmp=$AgentFile+'.resume.download'
$expectedSha=([string]$meta.gitBlobSha1).ToLowerInvariant()
$agentUrl=Bust ("$AgentBaseUrl/$targetAgent/HomeDesignLocalAgent.ps1") ($expectedSha+'-'+$nonce)
Invoke-WebRequest -UseBasicParsing -Uri $agentUrl -OutFile $agentTmp -TimeoutSec 60
$actualSha=GitBlobSha1 $agentTmp
if($actualSha -ne $expectedSha){Remove-Item $agentTmp -Force -ErrorAction SilentlyContinue;throw "Agent SHA mismatch: actual=$actualSha expected=$expectedSha"}
Move-Item -LiteralPath $agentTmp -Destination $AgentFile -Force

Write-Host '[4/5] Applying stable Agent directly...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AgentFile
$directExit=$LASTEXITCODE
Write-Host ("directAgentExit="+$directExit)

# Version-keyed independent CDP download verification.
# The exact Agent+Bridge condition is attempted at most once, so same-condition blind retry is blocked.
# A later Agent or Bridge version creates a new key and therefore permits exactly one changed-condition retest.
# Existing Chrome user data/download configuration is preserved and no NotebookLM artifact is generated.
$verifyKey='A'+(SafeKey $targetAgent)+'_B'+(SafeKey $targetBridge)
$verifyMarker=Join-Path $Root ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.attempted')
$verifyResult=Join-Path $Root ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.json')
if(-not(Test-Path -LiteralPath $verifyMarker)){
  $attempt=[ordered]@{
    ok=$false
    action='NOTEBOOKLM_CDP_DOWNLOAD_VERSIONED_RETEST'
    changedCondition=$true
    agentVersion=$targetAgent
    bridgeVersion=$targetBridge
    releaseActionId=[string]$bridge.actionId
    verifyKey=$verifyKey
    startedAt=(Get-Date).ToString('o')
    stdout=''
    exitCode=$null
    error=''
  }
  try{
    $helper=Join-Path $Root 'RunNotebookLMExistingDownloadViaCDP.ps1'
    $helperUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/RunNotebookLMExistingDownloadViaCDP.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $helperUrl -OutFile $helper -TimeoutSec 30
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper 2>&1 | Out-String
    $attempt.stdout=$out.Trim()
    $attempt.exitCode=$LASTEXITCODE
    $attempt.ok=($LASTEXITCODE -eq 0)
  }catch{
    $attempt.error=$_.Exception.Message
    $attempt.ok=$false
  }
  $attempt.completedAt=(Get-Date).ToString('o')
  $json=$attempt|ConvertTo-Json -Depth 30
  $json|Set-Content -LiteralPath $verifyResult -Encoding UTF8
  Set-Content -LiteralPath $verifyMarker -Value $attempt.completedAt -Encoding ASCII
  try{
    $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
    foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
      $rr=[string]$drv.Root
      if(-not $rr){continue}
      foreach($cand in @((Join-Path $rr $centralName),(Join-Path $rr ($myDriveKo+'\'+$centralName)),(Join-Path $rr ('My Drive\'+$centralName)),(Join-Path $rr ('Google Drive\'+$centralName)))){
        if(Test-Path -LiteralPath $cand){
          $dest=Join-Path $cand 'Runtime_Readback'
          New-Item -ItemType Directory -Force -Path $dest|Out-Null
          $json|Set-Content -LiteralPath (Join-Path $dest ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.json')) -Encoding UTF8
          break
        }
      }
    }
  }catch{}
}else{
  Write-Host ('CDP versioned retest already attempted for '+$verifyKey+'; same-condition retry blocked.')
}

Write-Host '[5/5] Ensuring future bootstrap loop (mutex-safe)...'
$loopState=EnsureBootstrapLoop $Bootstrap 120
Write-Host ('bootstrapLoop='+($loopState|ConvertTo-Json -Compress))
if(-not $loopState.ok){throw ('BOOTSTRAP_LOOP_NOT_VERIFIED:'+($loopState|ConvertTo-Json -Compress))}
WriteResumeHeartbeat ('BOOTSTRAP_LOOP_'+[string]$loopState.state)

$deadline=(Get-Date).AddSeconds(180)
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 3
  if(Test-Path -LiteralPath $StateFile){
    try{
      $last=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json
      $av=[string]$last.agentVersion
      $hv=[string]$last.commandHostVersion
      $hr=TestHostHealth
      $bv=[string]$last.extensionVersion
      if(-not $bv){$bv=[string]$last.installedVersion}
      $gov=[bool]$last.governorCycleOk
      $sync=[bool]$last.governorDriveSyncOk
      Write-Host ("agent="+$av+" host="+$hv+" hostHealth="+$hr+" bridge="+$bv+" status="+[string]$last.status+" governor="+$gov+" driveSync="+$sync)
      if($av -eq $targetAgent -and $hr -and $bv -eq $targetBridge -and $gov -and $sync){
        Write-Host 'RESUME RESULT: ACTIVE + GOVERNOR VERIFIED'
        exit 0
      }
      if($av -eq $targetAgent -and $hr -and $bv -eq $targetBridge -and $directExit -eq 0){
        Write-Host 'RESUME RESULT: ACTIVE; GOVERNOR READBACK STILL SYNCING'
        exit 0
      }
    }catch{}
  }
}
Write-Host 'RESUME RESULT: STARTED, RUNTIME READBACK STILL PENDING'
Write-Host 'Do not reinstall or reauthorize. Bootstrap loop was verified and remains enabled.'
exit 2