param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.10'
$SourceCommit='eceb6ce92d5a93a80266701bd83853115ee95503'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$BaseAgentFile=Join-Path $Root 'HomeDesignLocalAgent-1.1.7-base.ps1'
$NodeGovernor=Join-Path $GovRoot 'chromeGovernorFast.js'
$PolicyFile=Join-Path $GovRoot 'policy.json'
$ReleaseFile=Join-Path $GovRoot 'release.json'
$ReportFile=Join-Path $GovRoot 'state.json'
$InventoryFile=Join-Path $GovRoot 'inventory.json'
$ImmutableBase="https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$SourceCommit"
$BaseAgentUrl="$ImmutableBase/local-agent/releases/1.1.7/HomeDesignLocalAgent.ps1"
$NodeGovernorUrl="$ImmutableBase/local-agent/governor/chromeGovernorFast.js"
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$DedicatedExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
New-Item -ItemType Directory -Force -Path $Root,$GovRoot|Out-Null

function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Refresh-File([string]$Url,[string]$Path){$tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 45;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function Quote-Args([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function Kill-Tree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function Run-Node([string[]]$Args,[int]$TimeoutSeconds=45){
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $node){$node=Get-Command node -ErrorAction SilentlyContinue};if(-not $node){return [ordered]@{ok=$false;exitCode=127;timedOut=$false;stdout='';stderr='NODE_NOT_FOUND'}}
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$node.Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Arguments=Quote-Args $Args
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit($TimeoutSeconds*1000)){Kill-Tree ([int]$p.Id);return [ordered]@{ok=$false;exitCode=124;timedOut=$true;stdout='';stderr='NODE_GOVERNOR_TIMEOUT'}}
  $p.WaitForExit();return [ordered]@{ok=($p.ExitCode -eq 0);exitCode=$p.ExitCode;timedOut=$false;stdout=$outTask.Result.Trim();stderr=$errTask.Result.Trim()}
}
function Find-Central{
  $names=@(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue|ForEach-Object{[string]$_.Name})
  foreach($driveName in $names){foreach($candidate in @("$driveName`:\My Drive\00_중앙에이전트","$driveName`:\내 드라이브\00_중앙에이전트","$driveName`:\Google Drive\00_중앙에이전트","$driveName`:\00_중앙에이전트")){if(Test-Path -LiteralPath $candidate){return $candidate}}}
  foreach($letter in 'D'..'Z'){foreach($candidate in @("$letter`:\My Drive\00_중앙에이전트","$letter`:\내 드라이브\00_중앙에이전트","$letter`:\Google Drive\00_중앙에이전트","$letter`:\00_중앙에이전트")){if(Test-Path -LiteralPath $candidate){return $candidate}}}
  foreach($candidate in @((Join-Path $env:USERPROFILE 'My Drive\00_중앙에이전트'),(Join-Path $env:USERPROFILE '내 드라이브\00_중앙에이전트'),(Join-Path $env:USERPROFILE 'Google Drive\00_중앙에이전트'))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  return ''
}
function Write-FinalState($BaseState,$NodeResult,[string]$Central,[bool]$DriveOk){
  $s=@{};if($BaseState){foreach($p in $BaseState.PSObject.Properties){$s[$p.Name]=$p.Value}}
  $s.agentVersion=$AgentVersion;$s.agentSourceCommit=$SourceCommit;$s.governorMode='AGENT_5MIN_NODE_DIRECT';$s.governorCycleOk=[bool]$NodeResult.ok;$s.governorExitCode=$NodeResult.exitCode;$s.governorTimedOut=[bool]$NodeResult.timedOut;$s.governorError=[string]$NodeResult.stderr;$s.governorDriveSyncOk=$DriveOk;$s.governorCentralPath=$Central;$s.updatedAt=(Get-Date).ToString('o')
  $s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8;$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
  if($Central){$runtimeDir=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null;$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $runtimeDir 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}
}

$baseState=$null;$nodeResult=[ordered]@{ok=$false;exitCode=1;timedOut=$false;stdout='';stderr='NOT_RUN'};$central='';$driveOk=$false
try{
  Refresh-File $BaseAgentUrl $BaseAgentFile
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BaseAgentFile
  if($LASTEXITCODE -ne 0){throw "Base Local Agent 1.1.7 failed exit=$LASTEXITCODE"}
  $baseState=Read-Json $StateFile
  Refresh-File $NodeGovernorUrl $NodeGovernor;Refresh-File $PolicyUrl $PolicyFile;Refresh-File $ReleaseUrl $ReleaseFile
  $args=@($NodeGovernor,'--normalRoot',$NormalRoot,'--dedicatedUserData',$DedicatedUserData,'--dedicatedExtensionRoot',$DedicatedExtensionRoot,'--policy',$PolicyFile,'--release',$ReleaseFile,'--agentState',$StateFile,'--report',$ReportFile,'--inventory',$InventoryFile)
  $nodeResult=Run-Node $args 45
  $central=Find-Central
  if($central -and $nodeResult.ok -and (Test-Path -LiteralPath $ReportFile) -and (Test-Path -LiteralPath $InventoryFile)){$out=Join-Path $central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $out|Out-Null;Copy-Item -LiteralPath $ReportFile -Destination (Join-Path $out 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force;Copy-Item -LiteralPath $InventoryFile -Destination (Join-Path $out 'CHROME_EXTENSION_INVENTORY.json') -Force;$driveOk=(Test-Path (Join-Path $out 'CHROME_EXTENSION_GOVERNOR_RESULT.json')) -and (Test-Path (Join-Path $out 'CHROME_EXTENSION_INVENTORY.json'))}
}catch{$nodeResult=[ordered]@{ok=$false;exitCode=1;timedOut=$false;stdout='';stderr=$_.Exception.Message};if(-not $baseState){$baseState=Read-Json $StateFile};if(-not $central){$central=Find-Central}}
Write-FinalState $baseState $nodeResult $central $driveOk
if(-not $nodeResult.ok){throw "Node Governor failed: $($nodeResult.stderr)"}
if(-not $driveOk){throw 'Node Governor succeeded but central Drive copy was not verified'}
