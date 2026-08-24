param([switch]$KickStableAgent,[switch]$StatusOnly)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$AgentStatePath=Join-Path $AgentRoot 'state.json'
$GovStatePath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$KickStatusPath=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.status.json'
$KickLogPath=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.log'
$AgentMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
New-Item -ItemType Directory -Force -Path $AgentRoot,$GovRoot|Out-Null

function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDDspJHsl5DsnojspITtirjsnIQ='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  foreach($c in @((Join-Path $env:USERPROFILE ('My Drive\'+$target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  return ''
}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function CopyGovernorToCentral([string]$Central){
  $ok=$false;$out=''
  if($Central -and (Test-Path -LiteralPath $GovStatePath) -and (Test-Path -LiteralPath $InventoryPath)){
    try{$out=Join-Path $Central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $out|Out-Null;Copy-Item -LiteralPath $GovStatePath -Destination (Join-Path $out 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force;Copy-Item -LiteralPath $InventoryPath -Destination (Join-Path $out 'CHROME_EXTENSION_INVENTORY.json') -Force;$ok=$true}catch{}
  }
  return [ordered]@{ok=$ok;outDir=$out}
}
function RuntimeStatus{
  $agent=ReadJson $AgentStatePath;$manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$host=HostHealth;$kick=ReadJson $KickStatusPath;$gov=ReadJson $GovStatePath;$central=FindCentral;$copy=CopyGovernorToCentral $central
  return [ordered]@{
    ok=$true;action='LOCAL_RUNTIME_STATUS_LIGHTWEIGHT';at=(Get-Date).ToString('o')
    agentVersion=$(if($agent){[string]$agent.agentVersion}else{'UNKNOWN'});agentStatus=$(if($agent){[string]$agent.status}else{'UNKNOWN'})
    bridgeVersion=$(if($manifest){[string]$manifest.version}else{'UNKNOWN'});hostHealthy=$(if($host){[bool]$host.ok}else{$false});hostVersion=$(if($host){[string]$host.version}else{'UNKNOWN'});hostAsyncJobs=$(if($host){[bool]$host.asyncJobs}else{$false})
    governorPresent=[bool]$gov;governorCycleOk=$(if($agent -and $null -ne $agent.governorCycleOk){[bool]$agent.governorCycleOk}elseif($gov -and $null -ne $gov.ok){[bool]$gov.ok}else{$false});governorDriveSyncOk=[bool]$copy.ok;governorCentralPath=$central
    governorSummary=$(if($gov){$gov.summary}else{$null});governorScanEngine=$(if($gov){[string]$gov.scanEngine}else{''});governorScanError=$(if($gov){[string]$gov.scanError}else{''})
    kickStatus=$kick;kickLogExists=(Test-Path -LiteralPath $KickLogPath)
    lastError=$(if($agent){[string]$agent.lastError}else{''})
  }
}

if($StatusOnly){RuntimeStatus|ConvertTo-Json -Depth 20 -Compress;exit 0}

if($KickStableAgent){
  try{
    $nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString();$meta=Invoke-RestMethod -Uri (Bust $AgentMetaUrl $nonce) -Method Get -TimeoutSec 20
    if(-not $meta.enabled){throw 'Local Agent stable channel disabled'}
    $target=[string]$meta.version;$expected=([string]$meta.gitBlobSha1).ToLowerInvariant();$agent=ReadJson $AgentStatePath;$current=$(if($agent){[string]$agent.agentVersion}else{''})
    if($current -eq $target){[ordered]@{ok=$true;action='KICK_STABLE_AGENT_NOT_NEEDED';currentAgent=$current;targetAgent=$target;expectedSha=$expected;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 0}
    $kickPath=Join-Path $env:TEMP 'HomeDesign-Kick-Stable-Agent-Direct.ps1'
    $template=@'
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
$log=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.log';$status=Join-Path $env:TEMP 'HomeDesign-Stable-Kick.status.json'
try{
  Start-Sleep -Seconds 2
  $metaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json';$n=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString();$m=Invoke-RestMethod -Uri (Bust $metaUrl $n) -Method Get -TimeoutSec 20
  if(-not $m.enabled){throw 'stable disabled'};$v=[string]$m.version;$expected=([string]$m.gitBlobSha1).ToLowerInvariant();$url="https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/$v/HomeDesignLocalAgent.ps1"
  $root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent';New-Item -ItemType Directory -Force -Path $root|Out-Null;$dst=Join-Path $root 'HomeDesignLocalAgent.ps1';$tmp=$dst+'.direct.download';Invoke-WebRequest -UseBasicParsing -Uri (Bust $url ($expected+'-'+$n)) -OutFile $tmp -TimeoutSec 60;$actual=GitBlobSha1 $tmp
  if($actual -ne $expected){throw "SHA_MISMATCH actual=$actual expected=$expected"};Move-Item -LiteralPath $tmp -Destination $dst -Force
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dst *> $log;$rc=$LASTEXITCODE
  [ordered]@{ok=($rc -eq 0);targetAgent=$v;expectedSha=$expected;actualSha=$actual;exitCode=$rc;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $status -Encoding UTF8
}catch{[ordered]@{ok=$false;error=$_.Exception.Message;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $status -Encoding UTF8;Add-Content -LiteralPath $log -Value ('KICK_ERROR: '+$_.Exception.Message) -Encoding UTF8}
'@
    Set-Content -LiteralPath $kickPath -Value $template -Encoding UTF8;Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$kickPath`"") -WindowStyle Hidden|Out-Null
    [ordered]@{ok=$true;action='KICK_STABLE_AGENT_DIRECT_BACKGROUND';currentAgent=$current;targetAgent=$target;expectedSha=$expected;delaySeconds=2;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 0
  }catch{[ordered]@{ok=$false;action='KICK_STABLE_AGENT_DIRECT_BACKGROUND';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress;exit 2}
}

RuntimeStatus|ConvertTo-Json -Depth 20 -Compress
exit 0
