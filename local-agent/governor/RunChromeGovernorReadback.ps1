param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$AgentRoot=Join-Path $Base 'LocalAgent'
$GovFile=Join-Path $GovRoot 'ChromeExtensionGovernor.ps1'
$StateFile=Join-Path $GovRoot 'state.json'
$InventoryFile=Join-Path $GovRoot 'inventory.json'
$SyncState=Join-Path $GovRoot 'drive-sync.json'
$AgentState=Join-Path $AgentRoot 'state.json'
$GovUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/ChromeExtensionGovernor.ps1'
New-Item -ItemType Directory -Force -Path $GovRoot|Out-Null

function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function ProcList([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function Refresh-Governor {
  try{$tmp=$GovFile+'.readback.download';Invoke-WebRequest -UseBasicParsing -Uri $GovUrl -OutFile $tmp -TimeoutSec 20;Move-Item -LiteralPath $tmp -Destination $GovFile -Force;return $true}catch{return $false}
}
function Run-OneBounded {
  if(-not(Test-Path -LiteralPath $GovFile)){return [ordered]@{attempted=$false;reason='GOVERNOR_FILE_MISSING'}}
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$GovFile+'"'
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start()
  if(-not $p.WaitForExit(30000)){
    try{$p.Kill()}catch{}
    return [ordered]@{attempted=$true;timedOut=$true;exitCode=$null}
  }
  return [ordered]@{attempted=$true;timedOut=$false;exitCode=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd().Trim();stderr=$p.StandardError.ReadToEnd().Trim()}
}

$refreshed=Refresh-Governor
$state=Read-Json $StateFile
$inventory=@(Read-Json $InventoryFile)
$govRunning=(ProcList 'ChromeGovernor*ChromeExtensionGovernor.ps1').Count -gt 0
$oneShot=$null
if(-not $state){
  $oneShot=Run-OneBounded
  $state=Read-Json $StateFile
  $inventory=@(Read-Json $InventoryFile)
}
if(-not $govRunning -and (Test-Path -LiteralPath $GovFile)){
  try{Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$GovFile`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Milliseconds 800}catch{}
  $govRunning=(ProcList 'ChromeGovernor*ChromeExtensionGovernor.ps1').Count -gt 0
}

$agent=Read-Json $AgentState
$sync=Read-Json $SyncState
$managed=@();$issues=@();$dups=@()
if($state -and $state.extensions){
  $managed=@($state.extensions|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}|Select-Object name,id,profile,installedVersion,expectedVersion,action,fileIntegrityOk)
  $issues=@($state.extensions|Where-Object{$_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT','NO_AUTO_CHANGE','OBSERVE_ONLY')}|Select-Object name,id,profile,installedVersion,expectedVersion,classification,action,fileIntegrityOk)
}
if($state -and $state.duplicates){$dups=@($state.duplicates|Select-Object name,count)}

$result=[ordered]@{
  ok=([bool]$state)
  action='CHROME_GOVERNOR_READBACK_FAST'
  at=(Get-Date).ToString('o')
  governorRefreshed=$refreshed
  governorRunning=$govRunning
  governorStatePresent=[bool]$state
  inventoryPresent=(Test-Path -LiteralPath $InventoryFile)
  oneShot=$oneShot
  agent=[ordered]@{
    agentVersion=$(if($agent){$agent.agentVersion}else{$null})
    installedVersion=$(if($agent){$agent.installedVersion}else{$null})
    status=$(if($agent){$agent.status}else{$null})
    commandHostVersion=$(if($agent){$agent.commandHostVersion}else{$null})
    chromeGovernorRunning=$(if($agent){$agent.chromeGovernorRunning}else{$null})
    chromeGovernorDriveSyncRunning=$(if($agent){$agent.chromeGovernorDriveSyncRunning}else{$null})
  }
  summary=$(if($state){$state.summary}else{$null})
  managedExtensions=$managed
  issues=$issues
  duplicates=$dups
  inventoryCount=$inventory.Count
  driveSync=$(if($sync){[ordered]@{ok=$sync.ok;status=$sync.status;outDir=$sync.outDir;at=$sync.at}}else{$null})
  stateGeneratedAt=$(if($state){$state.generatedAt}else{$null})
}
$result|ConvertTo-Json -Depth 12 -Compress
if($result.ok){exit 0}else{exit 2}
