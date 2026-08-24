param([switch]$KickStableAgent,[switch]$StatusOnly)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$AgentRoot=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$StateFile=Join-Path $GovRoot 'state.json'
$InventoryFile=Join-Path $GovRoot 'inventory.json'
$AgentState=Join-Path $AgentRoot 'state.json'
$OneShotFile=Join-Path $GovRoot 'ChromeExtensionGovernorOneShot.ps1'
$OneShotUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/ChromeExtensionGovernorOneShot.ps1'
$AgentMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
New-Item -ItemType Directory -Force -Path $GovRoot,$AgentRoot|Out-Null

function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Refresh-File([string]$Url,[string]$Path){try{$tmp=$Path+'.readback.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 30;Move-Item -LiteralPath $tmp -Destination $Path -Force;return $true}catch{return $false}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
function Run-Bounded([string]$ScriptPath,[int]$TimeoutMs=60000){
  if(-not(Test-Path -LiteralPath $ScriptPath)){return [ordered]@{attempted=$false;reason='SCRIPT_MISSING';path=$ScriptPath}}
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$ScriptPath+'"'
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit($TimeoutMs)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{try{$p.Kill()}catch{}};return [ordered]@{attempted=$true;timedOut=$true;exitCode=124;stdout='';stderr='GOVERNOR_READBACK_TIMEOUT';path=$ScriptPath}}
  $p.WaitForExit();return [ordered]@{attempted=$true;timedOut=$false;exitCode=$p.ExitCode;stdout=$outTask.Result.Trim();stderr=$errTask.Result.Trim();path=$ScriptPath}
}
function Find-Central{
  $names=@(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue|ForEach-Object{[string]$_.Name})
  foreach($driveName in $names){foreach($candidate in @("$driveName`:\My Drive\00_중앙에이전트","$driveName`:\내 드라이브\00_중앙에이전트","$driveName`:\Google Drive\00_중앙에이전트","$driveName`:\00_중앙에이전트")){if(Test-Path -LiteralPath $candidate){return $candidate}}}
  foreach($letter in 'D'..'Z'){foreach($candidate in @("$letter`:\My Drive\00_중앙에이전트","$letter`:\내 드라이브\00_중앙에이전트","$letter`:\Google Drive\00_중앙에이전트","$letter`:\00_중앙에이전트")){if(Test-Path -LiteralPath $candidate){return $candidate}}}
  foreach($candidate in @((Join-Path $env:USERPROFILE 'My Drive\00_중앙에이전트'),(Join-Path $env:USERPROFILE '내 드라이브\00_중앙에이전트'),(Join-Path $env:USERPROFILE 'Google Drive\00_중앙에이전트'))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  return ''
}

if($StatusOnly){
  try{$agent=Read-Json $AgentState;$manifest=Read-Json (Join-Path $ExtensionRoot 'manifest.json');$host=$null;try{$host=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{}
    [ordered]@{ok=$true;action='LOCAL_RUNTIME_STATUS_ONLY';at=(Get-Date).ToString('o');agentVersion=$(if($agent){$agent.agentVersion}else{$null});agentStatus=$(if($agent){$agent.status}else{$null});manifestVersion=$(if($manifest){$manifest.version}else{$null});commandHostVersion=$(if($agent){$agent.commandHostVersion}else{$null});hostHealth=[bool]$(if($host){$host.ok}else{$false});hostReportedVersion=$(if($host){$host.version}else{$null});hostTransport=$(if($host){$host.transport}else{$null});hostAsyncJobs=$(if($host){$host.asyncJobs}else{$false});dedicatedChromeRunning=$(if($agent){$agent.dedicatedChromeRunning}else{$null});lastError=$(if($agent){$agent.lastError}else{$null})}|ConvertTo-Json -Depth 8 -Compress;exit 0
  }catch{[ordered]@{ok=$false;action='LOCAL_RUNTIME_STATUS_ONLY';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}
}

if($KickStableAgent){
  try{
    $nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $meta=Invoke-RestMethod -Uri (Bust $AgentMetaUrl $nonce) -Method Get -TimeoutSec 15
    if(-not $meta.enabled){throw 'Local Agent stable channel disabled.'}
    $target=[string]$meta.version
    $expectedSha=([string]$meta.gitBlobSha1).ToLowerInvariant()
    if(-not $target -or -not $expectedSha){throw 'Stable Agent metadata incomplete.'}
    $agent=Read-Json $AgentState
    $current=if($agent){[string]$agent.agentVersion}else{''}
    if($current -and $current -eq $target){
      [ordered]@{ok=$true;action='KICK_STABLE_AGENT_NOT_NEEDED';currentAgent=$current;targetAgent=$target;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
      exit 0
    }
    $kickPath=Join-Path $env:TEMP 'HomeDesign-Kick-Stable-Agent-Direct.ps1'
    $kick=@'
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
  $all=New-Object byte[] ($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
$log=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.log'
$statusPath=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.status.json'
try{
  Start-Sleep -Seconds 3
  $metaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
  $nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
  $meta=Invoke-RestMethod -Uri (Bust $metaUrl $nonce) -Method Get -TimeoutSec 20
  if(-not $meta.enabled){throw 'Local Agent stable channel disabled.'}
  $target=[string]$meta.version
  $expected=([string]$meta.gitBlobSha1).ToLowerInvariant()
  $agentUrl="https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/$target/HomeDesignLocalAgent.ps1"
  $root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
  New-Item -ItemType Directory -Force -Path $root|Out-Null
  $agentFile=Join-Path $root 'HomeDesignLocalAgent.ps1'
  $tmp=$agentFile+'.direct.download'
  Invoke-WebRequest -UseBasicParsing -Uri (Bust $agentUrl ($expected+'-'+$nonce)) -OutFile $tmp -TimeoutSec 60
  $actual=GitBlobSha1 $tmp
  if($actual -ne $expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "Agent SHA mismatch actual=$actual expected=$expected"}
  Move-Item -LiteralPath $tmp -Destination $agentFile -Force
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentFile *> $log
  $rc=$LASTEXITCODE
  [ordered]@{ok=($rc -eq 0);targetAgent=$target;expectedSha=$expected;actualSha=$actual;exitCode=$rc;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statusPath -Encoding UTF8
}catch{
  Add-Content -LiteralPath $log -Value ('DIRECT_KICK_ERROR: '+$_.Exception.Message) -Encoding UTF8
  [ordered]@{ok=$false;error=$_.Exception.Message;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statusPath -Encoding UTF8
}
'@
    Set-Content -LiteralPath $kickPath -Value $kick -Encoding UTF8
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$kickPath`"") -WindowStyle Hidden|Out-Null
    [ordered]@{ok=$true;action='KICK_STABLE_AGENT_DIRECT_BACKGROUND';currentAgent=$current;targetAgent=$target;expectedSha=$expectedSha;delaySeconds=3;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='KICK_STABLE_AGENT_DIRECT_BACKGROUND';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

$refreshed=Refresh-File $OneShotUrl $OneShotFile
$run=Run-Bounded $OneShotFile 60000
$state=Read-Json $StateFile
$inventory=@(Read-Json $InventoryFile)
$central=Find-Central;$driveSyncOk=$false;$outDir=''
if($central -and $state -and (Test-Path -LiteralPath $InventoryFile)){$outDir=Join-Path $central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $outDir|Out-Null;Copy-Item -LiteralPath $StateFile -Destination (Join-Path $outDir 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force;Copy-Item -LiteralPath $InventoryFile -Destination (Join-Path $outDir 'CHROME_EXTENSION_INVENTORY.json') -Force;$driveSyncOk=(Test-Path (Join-Path $outDir 'CHROME_EXTENSION_GOVERNOR_RESULT.json')) -and (Test-Path (Join-Path $outDir 'CHROME_EXTENSION_INVENTORY.json'))}
$managed=@();$issues=@();$dups=@();if($state -and $state.extensions){$managed=@($state.extensions|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}|Select-Object name,id,profile,installedVersion,expectedVersion,action,fileIntegrityOk);$issues=@($state.extensions|Where-Object{$_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT','NO_AUTO_CHANGE','OBSERVE_ONLY')}|Select-Object name,id,profile,installedVersion,expectedVersion,classification,action,fileIntegrityOk)};if($state -and $state.duplicates){$dups=@($state.duplicates|Select-Object name,count)}
$result=[ordered]@{ok=([bool]$state -and $run.exitCode -eq 0);action='CHROME_GOVERNOR_NODE_FAST_READBACK';at=(Get-Date).ToString('o');governorRefreshed=$refreshed;run=$run;driveSyncOk=$driveSyncOk;centralPath=$central;outDir=$outDir;scanEngine=$(if($state){$state.scanEngine}else{$null});scanError=$(if($state){$state.scanError}else{$null});summary=$(if($state){$state.summary}else{$null});managedExtensions=$managed;issues=$issues;duplicates=$dups;inventoryCount=$inventory.Count;stateGeneratedAt=$(if($state){$state.generatedAt}else{$null})}
$result|ConvertTo-Json -Depth 12 -Compress
if($result.ok){exit 0}else{exit 2}
