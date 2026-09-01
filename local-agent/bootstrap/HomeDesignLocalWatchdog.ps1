param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$WatchdogVersion='WATCHDOG_V6_TABLET_PRIMARY_HOLD_AWARE_20260901'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Log=Join-Path $Root 'watchdog.log'
$Receipt=Join-Path $Root 'WATCHDOG_LAST.json'
$EntryReceipt=Join-Path $Root 'WATCHDOG_ENTRY_LATEST.json'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$NotebookLMCdpUrl='http://127.0.0.1:9223/json/list'
$MaxStateAgeSeconds=420
$AutoResumeTimeoutSeconds=360
$StableMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Log([string]$m){Add-Content -LiteralPath $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
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
function SaveJsonEvidence([string]$LocalPath,[string]$CentralName,$o){
  try{
    $json=$o|ConvertTo-Json -Depth 30
    $json|Set-Content -LiteralPath $LocalPath -Encoding UTF8
    $central=FindCentralRoot
    if($central){$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest $CentralName) -Encoding UTF8}
  }catch{}
}
function SaveReceipt($o){SaveJsonEvidence $Receipt 'WATCHDOG_LAST.json' $o}
function SaveEntryReceipt($o){SaveJsonEvidence $EntryReceipt 'WATCHDOG_ENTRY_LATEST.json' $o}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function BootstrapLoopPresent{
  try{return @((Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})).Count -gt 0}catch{return $false}
}
function StateFresh{
  if(-not(Test-Path -LiteralPath $StateFile)){return $false}
  try{$item=Get-Item -LiteralPath $StateFile -ErrorAction Stop;return (((Get-Date)-$item.LastWriteTime).TotalSeconds -le $MaxStateAgeSeconds)}catch{return $false}
}
function CurrentAgentVersion{if(-not(Test-Path -LiteralPath $StateFile)){return ''};try{return [string]((Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}catch{return ''}}
function StableTargetState{
  $result=[ordered]@{reachable=$false;enabled=$true;version='';notes='';error=''}
  try{
    $meta=Invoke-RestMethod -Uri ($StableMetaUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Method Get -TimeoutSec 5
    if($meta){
      $result.reachable=$true
      $result.enabled=[bool]$meta.enabled
      $result.version=[string]$meta.version
      $result.notes=[string]$meta.notes
    }
  }catch{$result.error=$_.Exception.Message}
  return [pscustomobject]$result
}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function NotebookLMRuntimeHealth{
  $result=[ordered]@{ok=$false;dedicatedProcessCount=0;cdpReachable=$false;serviceWorkerFound=$false;extensionId='';pageTargetFound=$false;error=''}
  try{
    $procs=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"})
    $result.dedicatedProcessCount=$procs.Count
    if($procs.Count-lt1){$result.error='DEDICATED_CHROME_PROCESS_MISSING';return [pscustomobject]$result}
    $targets=@(Invoke-RestMethod -Uri $NotebookLMCdpUrl -TimeoutSec 3)
    $result.cdpReachable=$true
    $sw=@($targets|Where-Object{$_.type-eq'service_worker'-and$_.url-like'chrome-extension://*/worker.js'}|Select-Object -First 1)
    if($sw.Count-gt0){
      $result.serviceWorkerFound=$true
      if([string]$sw[0].url-match'^chrome-extension://([^/]+)/'){$result.extensionId=$Matches[1]}
    }
    $result.pageTargetFound=[bool](@($targets|Where-Object{$_.type-eq'page'-and($_.url-like'https://notebook.google.com/*'-or$_.url-like'https://notebooklm.google.com/*')}).Count-gt0)
    $result.ok=[bool]($result.dedicatedProcessCount-gt0 -and $result.cdpReachable -and $result.serviceWorkerFound)
    if(-not$result.ok-and-not$result.error){$result.error='NOTEBOOKLM_SERVICE_WORKER_MISSING'}
  }catch{$result.error=$_.Exception.Message}
  return [pscustomobject]$result
}

$startedAt=Get-Date
$started=$startedAt.ToString('o')
SaveEntryReceipt ([ordered]@{ok=$true;action='WATCHDOG_ENTRY_V6';version=$WatchdogVersion;pid=$PID;startedAt=$started;autoResumeTimeoutSeconds=$AutoResumeTimeoutSeconds;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false})

$hostOk=HostHealthy
$bootstrapOk=BootstrapLoopPresent
$stateOk=StateFresh
$currentVersion=CurrentAgentVersion
$stable=StableTargetState
$tabletPrimaryHold=[bool]($stable.reachable -and -not $stable.enabled -and ([string]$stable.notes -match 'TABLET_PRIMARY_HOLD'))
if($tabletPrimaryHold){
  Log ('TABLET_PRIMARY_HOLD stableEnabled=0 current='+$currentVersion+' stableVersion='+[string]$stable.version)
  SaveReceipt ([ordered]@{ok=$true;action='WATCHDOG_TABLET_PRIMARY_HOLD_V6';version=$WatchdogVersion;startedAt=$started;completedAt=(Get-Date).ToString('o');hostHealthy=$hostOk;bootstrapLoopPresent=$bootstrapOk;stateFresh=$stateOk;currentVersion=$currentVersion;targetVersion=[string]$stable.version;stableMetaReachable=$true;stableEnabled=$false;stableNotes=[string]$stable.notes;notebooklmRuntimeChecked=$false;autoResumeInvoked=$false;timedOut=$false;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=0})
  exit 0
}

$targetVersion=if($stable.enabled){[string]$stable.version}else{''}
$versionOk=(!$targetVersion -or ($currentVersion -eq $targetVersion))
$nlm=NotebookLMRuntimeHealth
$notebooklmRuntimeOk=[bool]$nlm.ok

if($hostOk -and $bootstrapOk -and $stateOk -and $versionOk -and $notebooklmRuntimeOk){
  Log ('PASS host=1 bootstrap=1 stateFresh=1 notebooklmRuntime=1 current='+$currentVersion+' target='+$targetVersion)
  SaveReceipt ([ordered]@{ok=$true;action='WATCHDOG_PASS_V6';version=$WatchdogVersion;startedAt=$started;completedAt=(Get-Date).ToString('o');hostHealthy=$true;bootstrapLoopPresent=$true;stateFresh=$true;notebooklmRuntimeHealthy=$true;notebooklmRuntime=$nlm;currentVersion=$currentVersion;targetVersion=$targetVersion;stableMetaReachable=[bool]$stable.reachable;stableEnabled=[bool]$stable.enabled;autoResumeInvoked=$false;timedOut=$false;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=0})
  exit 0
}

Log ("RECOVERY_NEEDED host="+[int]$hostOk+" bootstrap="+[int]$bootstrapOk+" stateFresh="+[int]$stateOk+" versionOk="+[int]$versionOk+" notebooklmRuntime="+[int]$notebooklmRuntimeOk+" current="+$currentVersion+" target="+$targetVersion+" nlmError="+[string]$nlm.error)
if(-not(Test-Path -LiteralPath $AutoResume)){
  Log 'AUTO_RESUME_MISSING'
  SaveReceipt ([ordered]@{ok=$false;action='AUTO_RESUME_MISSING';version=$WatchdogVersion;startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;notebooklmRuntimeHealthy=$notebooklmRuntimeOk;notebooklmRuntime=$nlm;autoResumeInvoked=$false;timedOut=$false;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=2})
  exit 2
}

try{
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$AutoResume+'"'
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$finished=$p.WaitForExit($AutoResumeTimeoutSeconds*1000)
  if(-not$finished){
    $pidToKill=[int]$p.Id;KillTree $pidToKill;try{[void]$p.WaitForExit(5000)}catch{}
    $nlmAfterTimeout=NotebookLMRuntimeHealth
    Log ('AUTO_RESUME_TIMEOUT seconds='+$AutoResumeTimeoutSeconds+' pid='+$pidToKill)
    SaveReceipt ([ordered]@{ok=$false;action='AUTO_RESUME_TIMEOUT';version=$WatchdogVersion;startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;notebooklmRuntimeBefore=$nlm;notebooklmRuntimeAfter=$nlmAfterTimeout;autoResumeInvoked=$true;timedOut=$true;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=124;hostAfter=(HostHealthy)})
    exit 124
  }
  $rc=$p.ExitCode
  $hostAfter=HostHealthy
  $bootstrapAfter=BootstrapLoopPresent
  $nlmAfter=NotebookLMRuntimeHealth
  $recovered=[bool]($rc-eq0 -and $hostAfter -and $bootstrapAfter -and $nlmAfter.ok)
  Log ("AUTO_RESUME_EXIT=$rc hostAfter="+[int]$hostAfter+" bootstrapAfter="+[int]$bootstrapAfter+" notebooklmAfter="+[int][bool]$nlmAfter.ok)
  SaveReceipt ([ordered]@{ok=$recovered;action='AUTO_RESUME_COMPLETED_V6';version=$WatchdogVersion;startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;notebooklmRuntimeBefore=$nlm;notebooklmRuntimeAfter=$nlmAfter;autoResumeInvoked=$true;timedOut=$false;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=$rc;hostAfter=$hostAfter;bootstrapAfter=$bootstrapAfter})
  if($recovered){exit 0}else{exit 2}
}catch{
  $nlmAfterException=NotebookLMRuntimeHealth
  Log ('WATCHDOG_EXCEPTION '+$_.Exception.Message)
  SaveReceipt ([ordered]@{ok=$false;action='WATCHDOG_EXCEPTION';version=$WatchdogVersion;startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;notebooklmRuntimeBefore=$nlm;notebooklmRuntimeAfter=$nlmAfterException;autoResumeInvoked=$true;timedOut=$false;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=3;error=$_.Exception.Message})
  exit 3
}
