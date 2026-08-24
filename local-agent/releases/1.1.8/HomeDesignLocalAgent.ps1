param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.8'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$GovernorRoot=Join-Path $Base 'ChromeGovernor'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$Source17=Join-Path $Root 'HomeDesignLocalAgent-1.1.7-source.ps1'
$Source17Url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.7/HomeDesignLocalAgent.ps1'
$GovUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/ChromeExtensionGovernor.ps1'
$SyncUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/GovernorDriveSync.ps1'
$GovFile=Join-Path $GovernorRoot 'ChromeExtensionGovernor.ps1'
$SyncFile=Join-Path $GovernorRoot 'GovernorDriveSync.ps1'
New-Item -ItemType Directory -Force -Path $Root,$GovernorRoot|Out-Null

function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function StartHidden([string]$File,[string[]]$Extra=@()){$args=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$File`"")+$Extra;Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden|Out-Null}
function RefreshFile([string]$Url,[string]$Path){$tmp=$Path+'.118.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 60;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function FindCentral(){
  $letters=@(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue|ForEach-Object{[string]$_.Name})
  foreach($l in $letters){foreach($p in @("$l`:\My Drive\00_중앙에이전트","$l`:\내 드라이브\00_중앙에이전트","$l`:\Google Drive\00_중앙에이전트","$l`:\00_중앙에이전트")){if(Test-Path -LiteralPath $p){return $p}}}
  foreach($p in @((Join-Path $env:USERPROFILE 'My Drive\00_중앙에이전트'),(Join-Path $env:USERPROFILE '내 드라이브\00_중앙에이전트'),(Join-Path $env:USERPROFILE 'Google Drive\00_중앙에이전트'))){if(Test-Path -LiteralPath $p){return $p}}
  return ''
}
function UpdateReadback(){
  $state=@{}
  if(Test-Path -LiteralPath $StateFile){try{$o=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;foreach($p in $o.PSObject.Properties){$state[$p.Name]=$p.Value}}catch{}}
  $state.agentVersion=$AgentVersion
  $state.chromeGovernorRunning=((Proc 'ChromeExtensionGovernor.ps1').Count -gt 0)
  $state.chromeGovernorDriveSyncRunning=((Proc 'GovernorDriveSync.ps1').Count -gt 0)
  $state.governorStartupOrder='ONE_SHOT_THEN_LOOP_VERIFIED'
  $state.updatedAt=(Get-Date).ToString('o')
  $state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8
  $state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
  $central=FindCentral
  if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $dir 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}
}

# Preserve all 1.1.7 self-heal behavior first: Host 1.2.0, latest stable Bridge, dedicated CFT, Drive path fix.
Invoke-WebRequest -UseBasicParsing -Uri $Source17Url -OutFile $Source17 -TimeoutSec 60
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Source17
if($LASTEXITCODE -ne 0){throw "Local Agent 1.1.7 base self-heal failed exit=$LASTEXITCODE"}

# Refresh current Governor sources.
RefreshFile $GovUrl $GovFile
RefreshFile $SyncUrl $SyncFile

# Remove only Governor loops so mutex ownership is deterministic. Normal Chrome and Local Host are untouched.
foreach($p in (Proc 'ChromeExtensionGovernor.ps1')){KillTree ([int]$p.ProcessId)}
foreach($p in (Proc 'GovernorDriveSync.ps1')){KillTree ([int]$p.ProcessId)}
Start-Sleep -Milliseconds 700

# Generate state and perform one Drive sync before starting persistent loops.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GovFile | Out-Null
$govRc=$LASTEXITCODE
if($govRc -ne 0){throw "Chrome Governor one-shot failed exit=$govRc"}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SyncFile | Out-Null
$syncRc=$LASTEXITCODE
if($syncRc -ne 0){throw "Governor Drive sync one-shot failed exit=$syncRc"}

StartHidden $GovFile @('-Loop')
StartHidden $SyncFile @('-Loop','-PollSeconds','900')
Start-Sleep -Seconds 2

if((Proc 'ChromeExtensionGovernor.ps1').Count -eq 0){StartHidden $GovFile @('-Loop');Start-Sleep -Seconds 1}
if((Proc 'GovernorDriveSync.ps1').Count -eq 0){StartHidden $SyncFile @('-Loop','-PollSeconds','900');Start-Sleep -Seconds 1}

UpdateReadback
if((Proc 'ChromeExtensionGovernor.ps1').Count -eq 0){throw 'Chrome Governor loop failed to remain running after deterministic startup'}
if((Proc 'GovernorDriveSync.ps1').Count -eq 0){throw 'Governor Drive Sync loop failed to remain running after deterministic startup'}
