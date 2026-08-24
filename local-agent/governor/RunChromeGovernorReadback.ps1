param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$AgentRoot=Join-Path $Base 'LocalAgent'
$GovFile=Join-Path $GovRoot 'ChromeExtensionGovernor.ps1'
$SyncFile=Join-Path $GovRoot 'GovernorDriveSync.ps1'
$StateFile=Join-Path $GovRoot 'state.json'
$InventoryFile=Join-Path $GovRoot 'inventory.json'
$SyncState=Join-Path $GovRoot 'drive-sync.json'
$AgentState=Join-Path $AgentRoot 'state.json'
$GovBase='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor'
New-Item -ItemType Directory -Force -Path $GovRoot|Out-Null

function Download-Latest([string]$Name,[string]$Path){
  try{
    $tmp=$Path+'.readback.download'
    Invoke-WebRequest -UseBasicParsing -Uri "$GovBase/$Name" -OutFile $tmp -TimeoutSec 60
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    return $true
  }catch{return $false}
}
function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function ProcCount([string]$Needle){
  try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"}).Count}catch{return 0}
}

$govDownloaded=Download-Latest 'ChromeExtensionGovernor.ps1' $GovFile
$syncDownloaded=Download-Latest 'GovernorDriveSync.ps1' $SyncFile

$govRunning=(ProcCount 'ChromeGovernor*ChromeExtensionGovernor.ps1') -gt 0
if(-not $govRunning -and (Test-Path -LiteralPath $GovFile)){
  try{
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$GovFile`"",'-Loop') -WindowStyle Hidden|Out-Null
    Start-Sleep -Seconds 3
  }catch{}
}
$govRunning=(ProcCount 'ChromeGovernor*ChromeExtensionGovernor.ps1') -gt 0

$deadline=(Get-Date).AddSeconds(20)
while((Get-Date)-lt $deadline -and -not(Test-Path -LiteralPath $StateFile)){Start-Sleep -Milliseconds 500}

$syncExit=$null
if(Test-Path -LiteralPath $SyncFile){
  try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SyncFile; $syncExit=$LASTEXITCODE}catch{$syncExit=99}
}

$state=Read-Json $StateFile
$inventory=@(Read-Json $InventoryFile)
$sync=Read-Json $SyncState
$agent=Read-Json $AgentState

$managed=@()
$issues=@()
if($state -and $state.extensions){
  $managed=@($state.extensions|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}|Select-Object name,id,profile,installedVersion,expectedVersion,action,fileIntegrityOk)
  $issues=@($state.extensions|Where-Object{$_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT','NO_AUTO_CHANGE','OBSERVE_ONLY')}|Select-Object name,id,profile,installedVersion,expectedVersion,classification,action,fileIntegrityOk)
}

$result=[ordered]@{
  ok=([bool]$state -and $govRunning)
  action='CHROME_GOVERNOR_READBACK'
  at=(Get-Date).ToString('o')
  governorDownloaded=$govDownloaded
  syncDownloaded=$syncDownloaded
  governorRunning=$govRunning
  governorStatePresent=[bool]$state
  inventoryPresent=(Test-Path -LiteralPath $InventoryFile)
  syncExitCode=$syncExit
  driveSync=$sync
  agent=[ordered]@{
    agentVersion=$(if($agent){$agent.agentVersion}else{$null})
    installedVersion=$(if($agent){$agent.installedVersion}else{$null})
    status=$(if($agent){$agent.status}else{$null})
    chromeGovernorRunning=$(if($agent){$agent.chromeGovernorRunning}else{$null})
    chromeGovernorDriveSyncRunning=$(if($agent){$agent.chromeGovernorDriveSyncRunning}else{$null})
  }
  summary=$(if($state){$state.summary}else{$null})
  managedExtensions=$managed
  issues=$issues
  inventoryCount=$inventory.Count
  stateGeneratedAt=$(if($state){$state.generatedAt}else{$null})
}
$result|ConvertTo-Json -Depth 12 -Compress
if($result.ok){exit 0}else{exit 2}
