param([switch]$Loop)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$AgentFile = Join-Path $Root 'HomeDesignLocalAgent.ps1'
$StateFile = Join-Path $Root 'state.json'
$FlowAgentFile = Join-Path $Root 'HomeDesignLocalAgent-flow.ps1'
$FlowLaneStateFile = Join-Path $Root 'state-flow.json'
$BootstrapLog = Join-Path $Root 'bootstrap.log'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function BLog([string]$m) { Add-Content -LiteralPath $BootstrapLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8 }
function GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path); $header = [Text.Encoding]::ASCII.GetBytes(("blob " + $bytes.Length + [char]0)); $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length); [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create(); try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}
function ApiContent([string]$Path){
  $headers=@{'User-Agent'='HomeDesign-Local-Agent-Bootstrap';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
}
function DecodeText($Response){
  $raw=([string]$Response.content -replace '\s','')
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))
}
function WriteApiFile($Response,[string]$Path){
  $bytes=[Convert]::FromBase64String(([string]$Response.content -replace '\s',''))
  [IO.File]::WriteAllBytes($Path,$bytes)
}
function CurrentStateVersion {
  if(-not(Test-Path -LiteralPath $StateFile)){ return '' }
  try { return [string]((Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json).agentVersion) } catch { return '' }
}
function CurrentLaneVersion([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){ return '' }
  try { return [string]((Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json).appliedVersion) } catch { return '' }
}
function SaveLaneState([string]$Path,[string]$Lane,[string]$Version,[int]$ExitCode){
  try{[ordered]@{lane=$Lane;appliedVersion=$Version;exitCode=$ExitCode;updatedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}
}
function StopStaleAgentProcesses([int]$MaxAgeSeconds=1800){
  $killed=@();$now=Get-Date
  try{
    foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)){
      $cmd=[string]$p.CommandLine;if(-not $cmd){continue}
      if($cmd -notmatch '(?i)HomeDesignLocalAgent(?:-1\.1\.\d+-patched)?\.ps1'){continue}
      $created=$null;try{$created=[datetime]$p.CreationDate}catch{}
      if(-not $created){continue}
      $age=[Math]::Floor(($now-$created).TotalSeconds);if($age -le $MaxAgeSeconds){continue}
      try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null;$killed+=[int]$p.ProcessId;BLog "Killed stale Local Agent pid=$($p.ProcessId) ageSec=$age."}catch{}
    }
  }catch{}
  return @($killed)
}
function RunAgentBounded([string]$Path,[int]$TimeoutSeconds=900){
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Path`""
  $proc=[Diagnostics.Process]::Start($psi)
  if(-not $proc.WaitForExit($TimeoutSeconds*1000)){
    try{& taskkill.exe /PID ([int]$proc.Id) /T /F 2>$null|Out-Null}catch{}
    BLog "Agent cycle timeout after ${TimeoutSeconds}s; killed pid=$($proc.Id)."
    return 124
  }
  try{return [int]$proc.ExitCode}catch{return 1}
}
function ApplyIndependentLane([string]$MetaPath,[string]$LaneName,[string]$Dest,[string]$LaneStatePath){
  try{
    $mResp=ApiContent $MetaPath;$m=(DecodeText $mResp)|ConvertFrom-Json
    if(-not$m.enabled){BLog "Lane $LaneName disabled.";return}
    $expected=([string]$m.gitBlobSha1).ToLowerInvariant();$version=[string]$m.version
    $releasePath='local-agent/releases/'+$version+'/HomeDesignLocalAgent.ps1';$r=ApiContent $releasePath
    if(([string]$r.sha).ToLowerInvariant()-ne$expected){throw "Lane $LaneName API blob mismatch"}
    $needsFile= -not(Test-Path -LiteralPath $Dest);if(-not$needsFile){$needsFile=((GitBlobSha1 $Dest)-ne$expected)}
    if($needsFile){$tmp=$Dest+'.download';WriteApiFile $r $tmp;$actual=GitBlobSha1 $tmp;if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "Lane $LaneName local SHA mismatch"};Move-Item $tmp $Dest -Force;BLog "Lane $LaneName updated to $version sha=$expected."}
    $laneVersion=CurrentLaneVersion $LaneStatePath
    if($needsFile -or $laneVersion-ne$version){$timeout=300;if($m.maxCycleSeconds){$timeout=[Math]::Max(180,[Math]::Min(1800,[int]$m.maxCycleSeconds))};$rc=RunAgentBounded $Dest $timeout;SaveLaneState $LaneStatePath $LaneName $version $rc;if($rc-ne0){BLog "Lane $LaneName exit=$rc version=$version."}else{BLog "Lane $LaneName apply complete version=$version."}}
    else{BLog "Lane $LaneName unchanged; skip reapply version=$version."}
  }catch{BLog("Lane $LaneName error: "+$_.Exception.Message)}
}

$mutex = New-Object System.Threading.Mutex($false,'HomeDesignLocalAgentBootstrapV1')
if (-not $mutex.WaitOne(0,$false)) { exit 0 }

try {
  do {
    $pollSeconds = 300
    $maxCycleSeconds = 900
    try {
      $metaResp=ApiContent 'local-agent/stable/agent.json'
      $meta=(DecodeText $metaResp)|ConvertFrom-Json
      if ($meta.pollSeconds) { $pollSeconds = [Math]::Max(60,[int]$meta.pollSeconds) }
      if ($meta.maxCycleSeconds) { $maxCycleSeconds = [Math]::Max(180,[Math]::Min(1800,[int]$meta.maxCycleSeconds)) }

      if ($meta.enabled) {
        $expected=([string]$meta.gitBlobSha1).ToLowerInvariant()
        $releasePath='local-agent/releases/'+[string]$meta.version+'/HomeDesignLocalAgent.ps1'
        $releaseResp=ApiContent $releasePath
        $apiSha=([string]$releaseResp.sha).ToLowerInvariant()
        if($apiSha -ne $expected){throw "Agent API blob mismatch: api=$apiSha expected=$expected"}

        $needsFile = -not (Test-Path -LiteralPath $AgentFile)
        if (-not $needsFile) { $needsFile = (GitBlobSha1 $AgentFile) -ne $expected }
        if ($needsFile) {
          $tmp = $AgentFile + '.download'
          WriteApiFile $releaseResp $tmp
          $actual=GitBlobSha1 $tmp
          if ($actual -ne $expected) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw "Agent local Git blob SHA1 mismatch: actual=$actual expected=$expected" }
          Move-Item -LiteralPath $tmp -Destination $AgentFile -Force
          BLog "Agent updated via Contents API to $($meta.version) sha=$expected."
        }

        $stateVersion=CurrentStateVersion
        $needsApply = $needsFile -or ($stateVersion -ne [string]$meta.version)
        [void](StopStaleAgentProcesses ([Math]::Max(1800,$maxCycleSeconds+300)))
        if($needsApply){
          $rc=RunAgentBounded $AgentFile $maxCycleSeconds
          if($rc -ne 0){BLog "Agent cycle exit=$rc maxCycleSeconds=$maxCycleSeconds."}
          else{BLog "Agent apply complete version=$($meta.version)."}
        }else{
          BLog "Stable unchanged; skip one-shot Agent reapply version=$($meta.version)."
        }
      } else { BLog 'Agent stable channel is disabled.' }
    } catch { BLog ("Bootstrap cycle error: " + $_.Exception.Message) }

    # Independent Flow lane prevents task-specific NotebookLM stable releases from starving Flow.
    # It has its own state marker and never changes normal Chrome/OAuth/Generate policy.
    ApplyIndependentLane 'local-agent/stable/flow.json' 'FLOW' $FlowAgentFile $FlowLaneStateFile

    if ($Loop) { Start-Sleep -Seconds $pollSeconds }
  } while ($Loop)
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
}
