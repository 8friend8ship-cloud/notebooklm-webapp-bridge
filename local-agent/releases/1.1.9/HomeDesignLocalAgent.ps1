param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.9'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$BaseAgentFile=Join-Path $Root 'HomeDesignLocalAgent-1.1.7-base.ps1'
$GovernorFile=Join-Path $GovRoot 'ChromeExtensionGovernorOneShot.ps1'
$BaseAgentUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.7/HomeDesignLocalAgent.ps1'
$GovernorUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/ChromeExtensionGovernorOneShot.ps1'
New-Item -ItemType Directory -Force -Path $Root,$GovRoot|Out-Null

function Read-Json([string]$FilePath){if(-not(Test-Path -LiteralPath $FilePath)){return $null};try{return Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Kill-Tree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function Find-Processes([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function Refresh-File([string]$Url,[string]$Path){$tmp=$Path+'.119.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 60;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function Run-Bounded([string]$ScriptPath,[int]$TimeoutSeconds){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$ScriptPath+'"'
  $proc=New-Object Diagnostics.Process;$proc.StartInfo=$psi;[void]$proc.Start()
  $outTask=$proc.StandardOutput.ReadToEndAsync();$errTask=$proc.StandardError.ReadToEndAsync()
  $finished=$proc.WaitForExit($TimeoutSeconds*1000)
  if(-not $finished){$processId=$proc.Id;Kill-Tree $processId;return [ordered]@{ok=$false;timedOut=$true;exitCode=124;stdout='';stderr='GOVERNOR_TIMEOUT'}}
  $proc.WaitForExit();return [ordered]@{ok=($proc.ExitCode -eq 0);timedOut=$false;exitCode=$proc.ExitCode;stdout=$outTask.Result;stderr=$errTask.Result}
}
function Find-Central{
  $names=@(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue|ForEach-Object{[string]$_.Name})
  foreach($driveName in $names){foreach($candidate in @("$driveName`:\My Drive\00_중앙에이전트","$driveName`:\내 드라이브\00_중앙에이전트","$driveName`:\Google Drive\00_중앙에이전트","$driveName`:\00_중앙에이전트")){if(Test-Path -LiteralPath $candidate){return $candidate}}}
  foreach($letter in 'D'..'Z'){foreach($candidate in @("$letter`:\My Drive\00_중앙에이전트","$letter`:\내 드라이브\00_중앙에이전트","$letter`:\Google Drive\00_중앙에이전트","$letter`:\00_중앙에이전트")){if(Test-Path -LiteralPath $candidate){return $candidate}}}
  foreach($candidate in @((Join-Path $env:USERPROFILE 'My Drive\00_중앙에이전트'),(Join-Path $env:USERPROFILE '내 드라이브\00_중앙에이전트'),(Join-Path $env:USERPROFILE 'Google Drive\00_중앙에이전트'))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  return ''
}
function Write-State($BaseState,$GovernorResult,[string]$CentralPath,[bool]$DriveSyncOk){
  $state=@{}
  if($BaseState){foreach($p in $BaseState.PSObject.Properties){$state[$p.Name]=$p.Value}}
  $state.agentVersion=$AgentVersion
  $state.governorMode='AGENT_5MIN_ONESHOT'
  $state.governorCycleOk=[bool]$GovernorResult.ok
  $state.governorExitCode=$GovernorResult.exitCode
  $state.governorTimedOut=[bool]$GovernorResult.timedOut
  $state.governorError=[string]$GovernorResult.stderr
  $state.chromeGovernorRunning=$false
  $state.chromeGovernorDriveSyncRunning=$false
  $state.governorDriveSyncOk=$DriveSyncOk
  $state.governorCentralPath=$CentralPath
  $state.updatedAt=(Get-Date).ToString('o')
  $state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8
  $state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
  if($CentralPath){$runtimeDir=Join-Path $CentralPath 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null;$state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $runtimeDir 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}
}

# 1) Preserve known-good NotebookLM/Host/Dedicated-CFT self-heal behavior.
Refresh-File $BaseAgentUrl $BaseAgentFile
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BaseAgentFile
$baseExit=$LASTEXITCODE
if($baseExit -ne 0){throw "Base Local Agent 1.1.7 self-heal failed exit=$baseExit"}
$baseState=Read-Json $StateFile

# 2) Remove only obsolete Governor loop processes. Normal Chrome, CFT and Local Host remain untouched.
foreach($p in (Find-Processes 'ChromeExtensionGovernor.ps1')){Kill-Tree ([int]$p.ProcessId)}
foreach($p in (Find-Processes 'GovernorDriveSync.ps1')){Kill-Tree ([int]$p.ProcessId)}
Start-Sleep -Milliseconds 500

# 3) Run one mutex-free full inventory cycle. It is bounded so bootstrap can never hang indefinitely.
Refresh-File $GovernorUrl $GovernorFile
$governorResult=Run-Bounded $GovernorFile 120

# 4) Copy actual state/inventory directly into the existing central Drive folder.
$central=Find-Central
$driveSyncOk=$false
if($central -and $governorResult.ok){
  $outDir=Join-Path $central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $outDir|Out-Null
  $report=Join-Path $GovRoot 'state.json';$inventory=Join-Path $GovRoot 'inventory.json'
  if(Test-Path -LiteralPath $report){Copy-Item -LiteralPath $report -Destination (Join-Path $outDir 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force}
  if(Test-Path -LiteralPath $inventory){Copy-Item -LiteralPath $inventory -Destination (Join-Path $outDir 'CHROME_EXTENSION_INVENTORY.json') -Force}
  $driveSyncOk=(Test-Path -LiteralPath (Join-Path $outDir 'CHROME_EXTENSION_GOVERNOR_RESULT.json')) -and (Test-Path -LiteralPath (Join-Path $outDir 'CHROME_EXTENSION_INVENTORY.json'))
}
Write-State $baseState $governorResult $central $driveSyncOk
if(-not $governorResult.ok){throw "Governor one-shot failed exit=$($governorResult.exitCode) error=$($governorResult.stderr)"}
if(-not $driveSyncOk){throw 'Governor completed but central Drive copy was not verified'}
