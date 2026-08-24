param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$AgentStatePath=Join-Path $AgentRoot 'state.json'
$GovStatePath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$NodeGovPath=Join-Path $GovRoot 'chromeGovernorFast.js'
$PolicyPath=Join-Path $GovRoot 'policy.json'
$ReleasePath=Join-Path $GovRoot 'release.json'
$KickStatusPath=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.status.json'
$AgentMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
$NodeGovUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/chromeGovernorFast.js'
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
New-Item -ItemType Directory -Force -Path $AgentRoot,$GovRoot|Out-Null

function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
function Refresh([string]$Url,[string]$Path){$tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri (Bust $Url ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString())) -OutFile $tmp -TimeoutSec 60;Move-Item -LiteralPath $tmp -Destination $Path -Force}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  foreach($c in @((Join-Path $env:USERPROFILE ('My Drive\'+$target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  return ''
}
function GetHostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function CopyGovernorToCentral([string]$Central){
  $ok=$false;$out=''
  if($Central -and (Test-Path -LiteralPath $GovStatePath) -and (Test-Path -LiteralPath $InventoryPath)){
    try{$out=Join-Path $Central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $out|Out-Null;Copy-Item -LiteralPath $GovStatePath -Destination (Join-Path $out 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force;Copy-Item -LiteralPath $InventoryPath -Destination (Join-Path $out 'CHROME_EXTENSION_INVENTORY.json') -Force;$ok=(Test-Path (Join-Path $out 'CHROME_EXTENSION_GOVERNOR_RESULT.json')) -and (Test-Path (Join-Path $out 'CHROME_EXTENSION_INVENTORY.json'))}catch{}
  }
  return [ordered]@{ok=$ok;outDir=$out}
}
function RunNodeGovernor{
  try{
    Refresh $NodeGovUrl $NodeGovPath;Refresh $PolicyUrl $PolicyPath;Refresh $ReleaseUrl $ReleasePath
    $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $node){$node=Get-Command node -ErrorAction SilentlyContinue};if(-not $node){return [ordered]@{ok=$false;exitCode=127;error='NODE_NOT_FOUND'}}
    $args=@($NodeGovPath,'--normalRoot',$NormalRoot,'--dedicatedUserData',$DedicatedUserData,'--dedicatedExtensionRoot',$ExtensionRoot,'--policy',$PolicyPath,'--release',$ReleasePath,'--agentState',$AgentStatePath,'--report',$GovStatePath,'--inventory',$InventoryPath)
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$node.Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Arguments=QuoteArgs $args
    $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit(60000)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{};return [ordered]@{ok=$false;exitCode=124;error='NODE_GOVERNOR_TIMEOUT'}}
    $p.WaitForExit();return [ordered]@{ok=($p.ExitCode -eq 0);exitCode=$p.ExitCode;stdout=$ot.Result.Trim();stderr=$et.Result.Trim()}
  }catch{return [ordered]@{ok=$false;exitCode=1;error=$_.Exception.Message}}
}
function RuntimeStatus($GovernorRun=$null){
  $agentStateObj=ReadJson $AgentStatePath;$bridgeManifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$hostInfo=GetHostHealth;$kickInfo=ReadJson $KickStatusPath;$govStateObj=ReadJson $GovStatePath;$central=FindCentral;$copyInfo=CopyGovernorToCentral $central
  $managed=@();$issues=@();$dups=@()
  if($govStateObj -and $govStateObj.extensions){$managed=@($govStateObj.extensions|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}|Select-Object name,id,profile,installedVersion,expectedVersion,action,fileIntegrityOk,path);$issues=@($govStateObj.extensions|Where-Object{$_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT','NO_AUTO_CHANGE','OBSERVE_ONLY')}|Select-Object name,id,profile,installedVersion,expectedVersion,classification,action,fileIntegrityOk,path)}
  if($govStateObj -and $govStateObj.duplicates){$dups=@($govStateObj.duplicates|Select-Object name,count,ids,profiles)}
  return [ordered]@{
    ok=$true;action='LOCAL_RUNTIME_STATUS_LIGHTWEIGHT';at=(Get-Date).ToString('o')
    agentVersion=$(if($agentStateObj){[string]$agentStateObj.agentVersion}else{'UNKNOWN'});agentStatus=$(if($agentStateObj){[string]$agentStateObj.status}else{'UNKNOWN'})
    bridgeVersion=$(if($bridgeManifest){[string]$bridgeManifest.version}else{'UNKNOWN'});hostHealthy=$(if($hostInfo){[bool]$hostInfo.ok}else{$false});hostVersion=$(if($hostInfo){[string]$hostInfo.version}else{'UNKNOWN'});hostAsyncJobs=$(if($hostInfo){[bool]$hostInfo.asyncJobs}else{$false})
    governorPresent=[bool]$govStateObj;governorRun=$GovernorRun;governorCycleOk=$(if($govStateObj -and $null -ne $govStateObj.ok){[bool]$govStateObj.ok}elseif($agentStateObj -and $null -ne $agentStateObj.governorCycleOk){[bool]$agentStateObj.governorCycleOk}else{$false});governorDriveSyncOk=[bool]$copyInfo.ok;governorCentralPath=$central
    governorSummary=$(if($govStateObj){$govStateObj.summary}else{$null});governorScanEngine=$(if($govStateObj){[string]$govStateObj.scanEngine}else{''});governorScanError=$(if($govStateObj){[string]$govStateObj.scanError}else{''});managedExtensions=$managed;issues=$issues;duplicates=$dups
    kickStatus=$kickInfo;lastError=$(if($agentStateObj){[string]$agentStateObj.lastError}else{''})
  }
}

if($StatusOnly){RuntimeStatus|ConvertTo-Json -Depth 30 -Compress;exit 0}
if($RunGovernor){$run=RunNodeGovernor;$status=RuntimeStatus $run;$status|ConvertTo-Json -Depth 30 -Compress;if($run.ok){exit 0}else{exit 2}}

if($KickStableAgent){
  try{
    $nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString();$meta=Invoke-RestMethod -Uri (Bust $AgentMetaUrl $nonce) -Method Get -TimeoutSec 20
    if(-not $meta.enabled){throw 'Local Agent stable channel disabled'}
    $target=[string]$meta.version;$expected=([string]$meta.gitBlobSha1).ToLowerInvariant();$agentStateObj=ReadJson $AgentStatePath;$current=$(if($agentStateObj){[string]$agentStateObj.agentVersion}else{''})
    if($current -eq $target){[ordered]@{ok=$true;action='KICK_STABLE_AGENT_NOT_NEEDED';currentAgent=$current;targetAgent=$target;expectedSha=$expected;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 0}
    $kickPath=Join-Path $env:TEMP ('HomeDesign-Kick-Stable-Agent-Direct-'+$nonce+'.ps1')
    $template=@'
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
$runId=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString();$log=Join-Path $env:TEMP ('HomeDesign-Stable-Kick-'+$runId+'.log');$status=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.status.json'
try{
  Start-Sleep -Seconds 2;$metaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json';$n=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString();$m=Invoke-RestMethod -Uri (Bust $metaUrl $n) -Method Get -TimeoutSec 20
  if(-not $m.enabled){throw 'stable disabled'};$v=[string]$m.version;$expected=([string]$m.gitBlobSha1).ToLowerInvariant();$url="https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/$v/HomeDesignLocalAgent.ps1"
  $root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent';New-Item -ItemType Directory -Force -Path $root|Out-Null;$dst=Join-Path $root 'HomeDesignLocalAgent.ps1';$tmp=$dst+'.direct.download';Invoke-WebRequest -UseBasicParsing -Uri (Bust $url ($expected+'-'+$n)) -OutFile $tmp -TimeoutSec 60;$actual=GitBlobSha1 $tmp
  if($actual -ne $expected){throw "SHA_MISMATCH actual=$actual expected=$expected"};Move-Item -LiteralPath $tmp -Destination $dst -Force
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dst 2>&1|Set-Content -LiteralPath $log -Encoding UTF8;$rc=$LASTEXITCODE
  [ordered]@{ok=($rc -eq 0);targetAgent=$v;expectedSha=$expected;actualSha=$actual;exitCode=$rc;log=$log;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $status -Encoding UTF8
}catch{[ordered]@{ok=$false;error=$_.Exception.Message;log=$log;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $status -Encoding UTF8;Add-Content -LiteralPath $log -Value ('KICK_ERROR: '+$_.Exception.Message) -Encoding UTF8}
'@
    Set-Content -LiteralPath $kickPath -Value $template -Encoding UTF8;Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$kickPath`"") -WindowStyle Hidden|Out-Null
    [ordered]@{ok=$true;action='KICK_STABLE_AGENT_DIRECT_BACKGROUND';currentAgent=$current;targetAgent=$target;expectedSha=$expected;delaySeconds=2;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 0
  }catch{[ordered]@{ok=$false;action='KICK_STABLE_AGENT_DIRECT_BACKGROUND';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}
}
RuntimeStatus|ConvertTo-Json -Depth 30 -Compress
exit 0
