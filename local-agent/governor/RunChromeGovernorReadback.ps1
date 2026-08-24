param([switch]$KickStableAgent,[switch]$StatusOnly)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$AgentRoot=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$GovFile=Join-Path $GovRoot 'ChromeExtensionGovernor.ps1'
$SyncFile=Join-Path $GovRoot 'GovernorDriveSync.ps1'
$StateFile=Join-Path $GovRoot 'state.json'
$InventoryFile=Join-Path $GovRoot 'inventory.json'
$SyncState=Join-Path $GovRoot 'drive-sync.json'
$AgentState=Join-Path $AgentRoot 'state.json'
$GovUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/ChromeExtensionGovernor.ps1'
$SyncUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/GovernorDriveSync.ps1'
New-Item -ItemType Directory -Force -Path $GovRoot|Out-Null

if($StatusOnly){
  try{
    $agent=$null;if(Test-Path -LiteralPath $AgentState){try{$agent=Get-Content -LiteralPath $AgentState -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
    $manifest=$null;$manifestPath=Join-Path $ExtensionRoot 'manifest.json';if(Test-Path -LiteralPath $manifestPath){try{$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
    $host=$null;try{$host=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{}
    [ordered]@{
      ok=$true;action='LOCAL_RUNTIME_STATUS_ONLY';at=(Get-Date).ToString('o');
      agentVersion=$(if($agent){$agent.agentVersion}else{$null});agentStatus=$(if($agent){$agent.status}else{$null});
      stateInstalledVersion=$(if($agent){$agent.installedVersion}else{$null});manifestVersion=$(if($manifest){$manifest.version}else{$null});
      commandHostVersion=$(if($agent){$agent.commandHostVersion}else{$null});hostHealth=[bool]$(if($host){$host.ok}else{$false});
      hostReportedVersion=$(if($host){$host.version}else{$null});hostTransport=$(if($host){$host.transport}else{$null});hostAsyncJobs=$(if($host){$host.asyncJobs}else{$false});
      chromeGovernorRunning=$(if($agent){$agent.chromeGovernorRunning}else{$null});chromeGovernorDriveSyncRunning=$(if($agent){$agent.chromeGovernorDriveSyncRunning}else{$null});
      dedicatedChromeRunning=$(if($agent){$agent.dedicatedChromeRunning}else{$null});lastError=$(if($agent){$agent.lastError}else{$null})
    }|ConvertTo-Json -Depth 8 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='LOCAL_RUNTIME_STATUS_ONLY';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

# Fast handoff used by an older synchronous Bridge/Host to bootstrap a newer stable stack.
# The current queue task must finish before the delayed resume stops/replaces the old host.
if($KickStableAgent){
  try{
    $kickPath=Join-Path $env:TEMP 'HomeDesign-Kick-Stable-Agent.ps1'
    $kick=@'
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
Start-Sleep -Seconds 6
try{
  $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1'
  $dst=Join-Path $env:TEMP 'RESUME_LOCAL_AGENT_ONCE.latest.ps1'
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dst -TimeoutSec 60
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dst *> (Join-Path $env:TEMP 'HomeDesign-Stable-Kick.log')
}catch{
  Add-Content -LiteralPath (Join-Path $env:TEMP 'HomeDesign-Stable-Kick.log') -Value ("KICK_ERROR: "+$_.Exception.Message) -Encoding UTF8
}
'@
    Set-Content -LiteralPath $kickPath -Value $kick -Encoding UTF8
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$kickPath`"") -WindowStyle Hidden|Out-Null
    [ordered]@{ok=$true;action='KICK_STABLE_AGENT_BACKGROUND';delaySeconds=6;note='Current synchronous queue call may complete before host replacement.';at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='KICK_STABLE_AGENT_BACKGROUND';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function ProcList([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function Refresh-File([string]$Url,[string]$Path){
  try{$tmp=$Path+'.readback.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 20;Move-Item -LiteralPath $tmp -Destination $Path -Force;return $true}catch{return $false}
}
function Run-Bounded([string]$ScriptPath,[int]$TimeoutMs=30000){
  if(-not(Test-Path -LiteralPath $ScriptPath)){return [ordered]@{attempted=$false;reason='SCRIPT_MISSING';path=$ScriptPath}}
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$ScriptPath+'"'
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start()
  if(-not $p.WaitForExit($TimeoutMs)){
    try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{try{$p.Kill()}catch{}}
    return [ordered]@{attempted=$true;timedOut=$true;exitCode=$null;path=$ScriptPath}
  }
  return [ordered]@{attempted=$true;timedOut=$false;exitCode=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd().Trim();stderr=$p.StandardError.ReadToEnd().Trim();path=$ScriptPath}
}

$govRefreshed=Refresh-File $GovUrl $GovFile
$syncRefreshed=Refresh-File $SyncUrl $SyncFile
$state=Read-Json $StateFile
$inventory=@(Read-Json $InventoryFile)
$govRunning=(ProcList 'ChromeGovernor*ChromeExtensionGovernor.ps1').Count -gt 0
$oneShot=$null
if(-not $state){$oneShot=Run-Bounded $GovFile 30000;$state=Read-Json $StateFile;$inventory=@(Read-Json $InventoryFile)}
if(-not $govRunning -and (Test-Path -LiteralPath $GovFile)){
  try{Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$GovFile`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Milliseconds 800}catch{}
  $govRunning=(ProcList 'ChromeGovernor*ChromeExtensionGovernor.ps1').Count -gt 0
}
$syncOneShot=$null;if($state -and (Test-Path -LiteralPath $SyncFile)){$syncOneShot=Run-Bounded $SyncFile 20000}
$agent=Read-Json $AgentState;$sync=Read-Json $SyncState;$managed=@();$issues=@();$dups=@()
if($state -and $state.extensions){
  $managed=@($state.extensions|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}|Select-Object name,id,profile,installedVersion,expectedVersion,action,fileIntegrityOk)
  $issues=@($state.extensions|Where-Object{$_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT','NO_AUTO_CHANGE','OBSERVE_ONLY')}|Select-Object name,id,profile,installedVersion,expectedVersion,classification,action,fileIntegrityOk)
}
if($state -and $state.duplicates){$dups=@($state.duplicates|Select-Object name,count)}
$result=[ordered]@{
  ok=([bool]$state);action='CHROME_GOVERNOR_READBACK_V2';at=(Get-Date).ToString('o');governorRefreshed=$govRefreshed;driveSyncRefreshed=$syncRefreshed;
  governorRunning=$govRunning;governorStatePresent=[bool]$state;inventoryPresent=(Test-Path -LiteralPath $InventoryFile);oneShot=$oneShot;driveSyncOneShot=$syncOneShot;
  agent=[ordered]@{agentVersion=$(if($agent){$agent.agentVersion}else{$null});installedVersion=$(if($agent){$agent.installedVersion}else{$null});status=$(if($agent){$agent.status}else{$null});commandHostVersion=$(if($agent){$agent.commandHostVersion}else{$null});commandHostRunning=$(if($agent){$agent.commandHostRunning}else{$null});chromeGovernorRunning=$(if($agent){$agent.chromeGovernorRunning}else{$null});chromeGovernorDriveSyncRunning=$(if($agent){$agent.chromeGovernorDriveSyncRunning}else{$null})};
  summary=$(if($state){$state.summary}else{$null});managedExtensions=$managed;issues=$issues;duplicates=$dups;inventoryCount=$inventory.Count;
  driveSync=$(if($sync){[ordered]@{ok=$sync.ok;status=$sync.status;path=$sync.path;outDir=$sync.outDir;at=$sync.at}}else{$null});stateGeneratedAt=$(if($state){$state.generatedAt}else{$null})
}
$result|ConvertTo-Json -Depth 12 -Compress
if($result.ok){exit 0}else{exit 2}
