param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Log=Join-Path $Root 'watchdog.log'
$Receipt=Join-Path $Root 'WATCHDOG_LAST.json'
$MaxStateAgeSeconds=420
$AutoResumeTimeoutSeconds=180
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
function SaveReceipt($o){
  try{
    $json=$o|ConvertTo-Json -Depth 20
    $json|Set-Content -LiteralPath $Receipt -Encoding UTF8
    $central=FindCentralRoot
    if($central){$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest 'WATCHDOG_LAST.json') -Encoding UTF8}
  }catch{}
}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function BootstrapLoopPresent{
  try{return @((Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)' })).Count -gt 0}catch{return $false}
}
function StateFresh{
  if(-not(Test-Path -LiteralPath $StateFile)){return $false}
  try{$item=Get-Item -LiteralPath $StateFile -ErrorAction Stop;return (((Get-Date)-$item.LastWriteTime).TotalSeconds -le $MaxStateAgeSeconds)}catch{return $false}
}
function CurrentAgentVersion{if(-not(Test-Path -LiteralPath $StateFile)){return ''};try{return [string]((Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}catch{return ''}}
function StableTargetVersion{try{$meta=Invoke-RestMethod -Uri ($StableMetaUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Method Get -TimeoutSec 5;if($meta -and $meta.enabled){return [string]$meta.version}}catch{};return ''}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}

$started=(Get-Date).ToString('o')
$hostOk=HostHealthy
$bootstrapOk=BootstrapLoopPresent
$stateOk=StateFresh
$currentVersion=CurrentAgentVersion
$targetVersion=StableTargetVersion
$versionOk=(!$targetVersion -or ($currentVersion -eq $targetVersion))

# HomeDesignLocalAgent.ps1 is intentionally a one-shot apply script. Do not require
# that process to remain alive. Persistent health is Host + Bootstrap loop + fresh state + stable version.
if($hostOk -and $bootstrapOk -and $stateOk -and $versionOk){
  Log ('PASS host=1 bootstrap=1 stateFresh=1 current='+$currentVersion+' target='+$targetVersion)
  SaveReceipt ([ordered]@{ok=$true;action='WATCHDOG_PASS_V2';version='WATCHDOG_ONE_SHOT_AGENT_FIX_20260829';startedAt=$started;completedAt=(Get-Date).ToString('o');hostHealthy=$true;bootstrapLoopPresent=$true;stateFresh=$true;currentVersion=$currentVersion;targetVersion=$targetVersion;autoResumeInvoked=$false;timedOut=$false;exitCode=0})
  exit 0
}

Log ("RECOVERY_NEEDED host="+[int]$hostOk+" bootstrap="+[int]$bootstrapOk+" stateFresh="+[int]$stateOk+" versionOk="+[int]$versionOk+" current="+$currentVersion+" target="+$targetVersion)
if(-not(Test-Path -LiteralPath $AutoResume)){
  Log 'AUTO_RESUME_MISSING'
  SaveReceipt ([ordered]@{ok=$false;action='AUTO_RESUME_MISSING';startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;autoResumeInvoked=$false;timedOut=$false;exitCode=2})
  exit 2
}

try{
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$AutoResume+'"'
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$finished=$p.WaitForExit($AutoResumeTimeoutSeconds*1000)
  if(-not $finished){$pidToKill=[int]$p.Id;KillTree $pidToKill;try{[void]$p.WaitForExit(5000)}catch{};Log ('AUTO_RESUME_TIMEOUT seconds='+$AutoResumeTimeoutSeconds+' pid='+$pidToKill);SaveReceipt ([ordered]@{ok=$false;action='AUTO_RESUME_TIMEOUT';startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;autoResumeInvoked=$true;timedOut=$true;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=124;hostAfter=(HostHealthy)});exit 124}
  $rc=$p.ExitCode;$hostAfter=HostHealthy;$bootstrapAfter=BootstrapLoopPresent;Log ("AUTO_RESUME_EXIT=$rc hostAfter="+[int]$hostAfter+" bootstrapAfter="+[int]$bootstrapAfter)
  SaveReceipt ([ordered]@{ok=[bool]($rc -eq 0);action='AUTO_RESUME_COMPLETED_V2';version='WATCHDOG_ONE_SHOT_AGENT_FIX_20260829';startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;autoResumeInvoked=$true;timedOut=$false;timeoutSeconds=$AutoResumeTimeoutSeconds;exitCode=$rc;hostAfter=$hostAfter;bootstrapAfter=$bootstrapAfter})
  exit $rc
}catch{Log ('WATCHDOG_EXCEPTION '+$_.Exception.Message);SaveReceipt ([ordered]@{ok=$false;action='WATCHDOG_EXCEPTION';startedAt=$started;completedAt=(Get-Date).ToString('o');currentVersion=$currentVersion;targetVersion=$targetVersion;autoResumeInvoked=$true;timedOut=$false;exitCode=3;error=$_.Exception.Message});exit 3}
