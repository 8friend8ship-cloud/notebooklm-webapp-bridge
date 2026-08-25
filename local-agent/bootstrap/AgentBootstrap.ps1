param([switch]$Loop)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$AgentFile = Join-Path $Root 'HomeDesignLocalAgent.ps1'
$AgentMetaUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
$AgentBaseUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases'
$BootstrapLog = Join-Path $Root 'bootstrap.log'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function BLog([string]$m) { Add-Content -LiteralPath $BootstrapLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8 }
function GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path); $header = [Text.Encoding]::ASCII.GetBytes(("blob " + $bytes.Length + [char]0)); $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length); [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create(); try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}
function StopStaleAgentProcesses([int]$MaxAgeSeconds=600){
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
function RunAgentBounded([string]$Path,[int]$TimeoutSeconds=180){
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

$mutex = New-Object System.Threading.Mutex($false,'HomeDesignLocalAgentBootstrapV1')
if (-not $mutex.WaitOne(0,$false)) { exit 0 }

try {
  do {
    $pollSeconds = 300
    try {
      $nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
      $meta = Invoke-RestMethod -Uri (Bust $AgentMetaUrl $nonce) -Method Get -TimeoutSec 30
      if ($meta.pollSeconds) { $pollSeconds = [Math]::Max(60,[int]$meta.pollSeconds) }

      if ($meta.enabled) {
        $expected=([string]$meta.gitBlobSha1).ToLowerInvariant()
        $needs = -not (Test-Path -LiteralPath $AgentFile)
        if (-not $needs) { $needs = (GitBlobSha1 $AgentFile) -ne $expected }

        if ($needs) {
          $tmp = $AgentFile + '.download'
          $url = Bust ("$AgentBaseUrl/$($meta.version)/HomeDesignLocalAgent.ps1") $expected
          Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
          if ((GitBlobSha1 $tmp) -ne $expected) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw 'Agent Git blob SHA1 mismatch.' }
          Move-Item -LiteralPath $tmp -Destination $AgentFile -Force
          BLog "Agent updated to $($meta.version) sha=$expected."
        }

        [void](StopStaleAgentProcesses 600)
        $rc=RunAgentBounded $AgentFile 180
        if($rc -ne 0){BLog "Agent cycle exit=$rc."}
      } else { BLog 'Agent stable channel is disabled.' }
    } catch { BLog ("Bootstrap cycle error: " + $_.Exception.Message) }

    if ($Loop) { Start-Sleep -Seconds $pollSeconds }
  } while ($Loop)
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
}
