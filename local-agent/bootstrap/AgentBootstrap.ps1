param([switch]$Loop)

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$BootstrapVersion='BOOTSTRAP_V8_TASK203_APPSCRIPT_FIRST_20260903'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$AgentFile=Join-Path $Root 'HomeDesignLocalAgent.ps1'
$StateFile=Join-Path $Root 'state.json'
$FlowAgentFile=Join-Path $Root 'HomeDesignLocalAgent-flow.ps1'
$FlowLaneStateFile=Join-Path $Root 'state-flow.json'
$ImageAgentFile=Join-Path $Root 'HomeDesignLocalAgent-image.ps1'
$ImageLaneStateFile=Join-Path $Root 'state-image.json'
$AppScriptAgentFile=Join-Path $Root 'HomeDesignLocalAgent-appscript.ps1'
$AppScriptLaneStateFile=Join-Path $Root 'state-appscript.json'
$BootstrapLog=Join-Path $Root 'bootstrap.log'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function BLog([string]$m){Add-Content -LiteralPath $BootstrapLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$BootstrapVersion] $m" -Encoding UTF8}
function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function GitBlobSha1([string]$Path){return GitBlobSha1Bytes ([IO.File]::ReadAllBytes($Path))}
function FetchContent([string]$Path){
  $o=[ordered]@{ok=$false;mode='';bytes=$null;sha='';error=''}
  try{
    $headers=@{'User-Agent'='HomeDesign-Local-Agent-Bootstrap-V2';'Accept'='application/vnd.github+json'}
    $url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $x=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 20
    $b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$actual=(GitBlobSha1Bytes $b).ToLowerInvariant();$expected=([string]$x.sha).ToLowerInvariant();if(-not$expected-or$actual-ne$expected){throw 'API_GIT_BLOB_SHA_MISMATCH'}
    $o.ok=$true;$o.mode='API';$o.bytes=$b;$o.sha=$actual;return [pscustomobject]$o
  }catch{$o.error='API='+$_.Exception.Message}
  try{
    $raw='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Local-Agent-Bootstrap-V2';$b=$wc.DownloadData($raw)}finally{$wc.Dispose()}
    if(-not$b-or$b.Length-eq0){throw 'RAW_EMPTY'}
    $o.ok=$true;$o.mode='RAW';$o.bytes=$b;$o.sha=(GitBlobSha1Bytes $b).ToLowerInvariant();$o.error='';return [pscustomobject]$o
  }catch{$o.error+=';RAW='+$_.Exception.Message}
  return [pscustomobject]$o
}
function ReadJsonResource([string]$Path){$r=FetchContent $Path;if(-not$r.ok){throw ($Path+':'+$r.error)};$j=[Text.Encoding]::UTF8.GetString([byte[]]$r.bytes)|ConvertFrom-Json;return [pscustomobject]@{json=$j;mode=$r.mode;sha=$r.sha}}
function CurrentStateVersion{if(-not(Test-Path -LiteralPath $StateFile)){return ''};try{return [string]((Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}catch{return ''}}
function CurrentLaneVersion([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return ''};try{$state=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json;if($null-ne$state.exitCode-and[int]$state.exitCode-ne0){return ''};return [string]$state.appliedVersion}catch{return ''}}
function SaveLaneState([string]$Path,[string]$Lane,[string]$Version,[int]$ExitCode,[string]$Transport){try{[ordered]@{lane=$Lane;appliedVersion=$Version;exitCode=$ExitCode;transport=$Transport;bootstrapVersion=$BootstrapVersion;updatedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function StopStaleAgentProcesses([int]$MaxAgeSeconds=1800){$killed=@();$now=Get-Date;try{foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)){$cmd=[string]$p.CommandLine;if(-not$cmd-or$cmd-notmatch'(?i)HomeDesignLocalAgent(?:-1\.1\.\d+-patched)?\.ps1'){continue};$created=$null;try{$created=[datetime]$p.CreationDate}catch{};if(-not$created){continue};$age=[Math]::Floor(($now-$created).TotalSeconds);if($age-le$MaxAgeSeconds){continue};try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null;$killed+=[int]$p.ProcessId;BLog "Killed stale Local Agent pid=$($p.ProcessId) ageSec=$age."}catch{}}}catch{};return @($killed)}
function RunAgentBounded([string]$Path,[int]$TimeoutSeconds=900){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Path`"";$proc=[Diagnostics.Process]::Start($psi);if(-not$proc.WaitForExit($TimeoutSeconds*1000)){try{& taskkill.exe /PID ([int]$proc.Id) /T /F 2>$null|Out-Null}catch{};BLog "Agent cycle timeout after ${TimeoutSeconds}s; killed pid=$($proc.Id).";return 124};try{return [int]$proc.ExitCode}catch{return 1}}
function WriteVerifiedResource($Resource,[string]$Dest,[string]$ExpectedSha){$actual=([string]$Resource.sha).ToLowerInvariant();if($ExpectedSha-and$actual-ne$ExpectedSha.ToLowerInvariant()){throw "RESOURCE_SHA_MISMATCH actual=$actual expected=$ExpectedSha"};$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,[byte[]]$Resource.bytes);$written=(GitBlobSha1 $tmp).ToLowerInvariant();if($ExpectedSha-and$written-ne$ExpectedSha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw 'LOCAL_SHA_MISMATCH'};Move-Item $tmp $Dest -Force;return $written}
function ApplyIndependentLane([string]$MetaPath,[string]$LaneName,[string]$Dest,[string]$LaneStatePath){
  try{
    $mr=ReadJsonResource $MetaPath;$m=$mr.json;if(-not$m.enabled){BLog "Lane $LaneName disabled transport=$($mr.mode).";return}
    $expected=([string]$m.gitBlobSha1).ToLowerInvariant();$version=[string]$m.version;$releasePath='local-agent/releases/'+$version+'/HomeDesignLocalAgent.ps1';$r=FetchContent $releasePath;if(-not$r.ok){throw $r.error};if(([string]$r.sha).ToLowerInvariant()-ne$expected){throw "Lane $LaneName blob mismatch"}
    $needsFile=-not(Test-Path -LiteralPath $Dest);if(-not$needsFile){$needsFile=((GitBlobSha1 $Dest).ToLowerInvariant()-ne$expected)}
    if($needsFile){[void](WriteVerifiedResource $r $Dest $expected);BLog "Lane $LaneName updated to $version transport=$($r.mode) sha=$expected."}
    $laneVersion=CurrentLaneVersion $LaneStatePath
    if($needsFile-or$laneVersion-ne$version){$timeout=300;if($m.maxCycleSeconds){$timeout=[Math]::Max(180,[Math]::Min(1800,[int]$m.maxCycleSeconds))};$rc=RunAgentBounded $Dest $timeout;SaveLaneState $LaneStatePath $LaneName $version $rc ([string]$r.mode);if($rc-ne0){BLog "Lane $LaneName exit=$rc version=$version; retry remains enabled."}else{BLog "Lane $LaneName apply complete version=$version."}}
    else{BLog "Lane $LaneName unchanged; skip reapply version=$version."}
  }catch{BLog("Lane $LaneName error: "+$_.Exception.Message)}
}

$mutex=New-Object System.Threading.Mutex($false,'HomeDesignLocalAgentBootstrapV1')
if(-not$mutex.WaitOne(0,$false)){exit 0}
try{
  do{
    $pollSeconds=300;$maxCycleSeconds=900
    try{
      $mr=ReadJsonResource 'local-agent/stable/agent.json';$meta=$mr.json;if($meta.pollSeconds){$pollSeconds=[Math]::Max(60,[int]$meta.pollSeconds)};if($meta.maxCycleSeconds){$maxCycleSeconds=[Math]::Max(180,[Math]::Min(1800,[int]$meta.maxCycleSeconds))}
      if($meta.enabled){
        $expected=([string]$meta.gitBlobSha1).ToLowerInvariant();$releasePath='local-agent/releases/'+[string]$meta.version+'/HomeDesignLocalAgent.ps1';$r=FetchContent $releasePath;if(-not$r.ok){throw $r.error};if(([string]$r.sha).ToLowerInvariant()-ne$expected){throw "Agent blob mismatch"}
        $needsFile=-not(Test-Path -LiteralPath $AgentFile);if(-not$needsFile){$needsFile=((GitBlobSha1 $AgentFile).ToLowerInvariant()-ne$expected)};if($needsFile){[void](WriteVerifiedResource $r $AgentFile $expected);BLog "Agent updated to $($meta.version) transport=$($r.mode) sha=$expected."}
        $stateVersion=CurrentStateVersion;$needsApply=$needsFile-or($stateVersion-ne[string]$meta.version);[void](StopStaleAgentProcesses ([Math]::Max(1800,$maxCycleSeconds+300)));if($needsApply){$rc=RunAgentBounded $AgentFile $maxCycleSeconds;if($rc-ne0){BLog "Agent cycle exit=$rc maxCycleSeconds=$maxCycleSeconds."}else{BLog "Agent apply complete version=$($meta.version)."}}else{BLog "Stable unchanged; skip one-shot Agent reapply version=$($meta.version)."}
      }else{BLog "Agent stable channel disabled transport=$($mr.mode)."}
    }catch{BLog("Bootstrap cycle error: "+$_.Exception.Message)}
    ApplyIndependentLane 'local-agent/stable/appscript.json' 'APPSCRIPT' $AppScriptAgentFile $AppScriptLaneStateFile
    ApplyIndependentLane 'local-agent/stable/flow.json' 'FLOW' $FlowAgentFile $FlowLaneStateFile
    ApplyIndependentLane 'local-agent/stable/image.json' 'IMAGE' $ImageAgentFile $ImageLaneStateFile
    if($Loop){Start-Sleep -Seconds $pollSeconds}
  }while($Loop)
}finally{try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}