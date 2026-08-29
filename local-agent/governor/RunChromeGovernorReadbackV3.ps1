param(
  [switch]$KickStableAgent,
  [switch]$StatusOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentRoot = Join-Path $Base 'LocalAgent'
$AgentFile = Join-Path $AgentRoot 'HomeDesignLocalAgent.ps1'
$AgentStatePath = Join-Path $AgentRoot 'state.json'
$KickReceiptPath = Join-Path $AgentRoot 'STABLE_AGENT_KICK_V3.json'
New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

function Read-Json([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Get-GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
  $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create()
  try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

function Invoke-GitHubContents([string]$Path,[int]$TimeoutSec=12) {
  $headers = @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
  $url = "https://api.github.com/repos/$Repo/contents/$Path?ref=main"
  return Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec $TimeoutSec
}

function Decode-GitHubContents($Response) {
  $raw = ([string]$Response.content -replace '\s','')
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))
}

function Get-RawText([string]$Path,[int]$TimeoutSec=15) {
  $url = 'https://raw.githubusercontent.com/' + $Repo + '/main/' + $Path + '?cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec $TimeoutSec).Content
}

function Save-Receipt($Object) {
  try { $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $KickReceiptPath -Encoding UTF8 } catch {}
}

function Get-StableMeta {
  $path = 'local-agent/stable/agent.json'
  try {
    $resp = Invoke-GitHubContents $path
    $meta = (Decode-GitHubContents $resp) | ConvertFrom-Json
    return [pscustomobject]@{ meta=$meta; source='GITHUB_CONTENTS_API'; error='' }
  } catch {
    $apiError = $_.Exception.Message
    try {
      $meta = (Get-RawText $path) | ConvertFrom-Json
      return [pscustomobject]@{ meta=$meta; source='RAW_GITHUB_FALLBACK'; error=$apiError }
    } catch {
      throw ('STABLE_META_FETCH_FAILED:api=' + $apiError + ';raw=' + $_.Exception.Message)
    }
  }
}

function Download-StableAgent([string]$Version,[string]$ExpectedSha) {
  $path = "local-agent/releases/$Version/HomeDesignLocalAgent.ps1"
  $tmp = $AgentFile + '.v3.download'
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $source = ''
  $apiError = ''
  try {
    $resp = Invoke-GitHubContents $path
    if (([string]$resp.sha).ToLowerInvariant() -ne $ExpectedSha.ToLowerInvariant()) {
      throw ('AGENT_API_SHA_MISMATCH:api=' + [string]$resp.sha + ';expected=' + $ExpectedSha)
    }
    [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$resp.content -replace '\s','')))
    $source = 'GITHUB_CONTENTS_API'
  } catch {
    $apiError = $_.Exception.Message
    try {
      $rawUrl = 'https://raw.githubusercontent.com/' + $Repo + '/main/' + $path + '?cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $tmp -TimeoutSec 20
      $source = 'RAW_GITHUB_FALLBACK'
    } catch {
      throw ('AGENT_DOWNLOAD_FAILED:api=' + $apiError + ';raw=' + $_.Exception.Message)
    }
  }
  if (-not (Test-Path -LiteralPath $tmp -PathType Leaf)) { throw 'AGENT_DOWNLOAD_TEMP_MISSING' }
  if ((Get-Item -LiteralPath $tmp).Length -le 0) { throw 'AGENT_DOWNLOAD_ZERO_BYTES' }
  $actual = (Get-GitBlobSha1 $tmp).ToLowerInvariant()
  if ($actual -ne $ExpectedSha.ToLowerInvariant()) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw ('AGENT_FILE_SHA_MISMATCH:actual=' + $actual + ';expected=' + $ExpectedSha + ';source=' + $source)
  }
  Move-Item -LiteralPath $tmp -Destination $AgentFile -Force
  return [pscustomobject]@{ source=$source; sha=$actual; apiError=$apiError }
}

if ($StatusOnly) {
  $state = Read-Json $AgentStatePath
  [ordered]@{
    ok = $true
    action = 'STABLE_AGENT_STATUS_V3'
    agentVersion = $(if($state){[string]$state.agentVersion}else{'UNKNOWN'})
    agentStatus = $(if($state){[string]$state.status}else{'UNKNOWN'})
    localAgentExists = [bool](Test-Path -LiteralPath $AgentFile -PathType Leaf)
    localAgentSha = $(if(Test-Path -LiteralPath $AgentFile -PathType Leaf){Get-GitBlobSha1 $AgentFile}else{''})
    at = (Get-Date).ToString('o')
  } | ConvertTo-Json -Compress
  exit 0
}

if ($KickStableAgent) {
  $stage = 'START'
  try {
    $stage = 'FETCH_META'
    $metaResult = Get-StableMeta
    $meta = $metaResult.meta
    if (-not $meta.enabled) { throw 'LOCAL_AGENT_STABLE_DISABLED' }
    $target = [string]$meta.version
    $expected = ([string]$meta.gitBlobSha1).ToLowerInvariant()
    if (-not $target -or -not $expected) { throw 'STABLE_META_INCOMPLETE' }

    $state = Read-Json $AgentStatePath
    $current = $(if($state){[string]$state.agentVersion}else{''})
    $localSha = $(if(Test-Path -LiteralPath $AgentFile -PathType Leaf){(Get-GitBlobSha1 $AgentFile).ToLowerInvariant()}else{''})
    $downloadSource = 'LOCAL_ALREADY_MATCHED'
    $downloadApiError = ''

    if ($current -ne $target -or $localSha -ne $expected) {
      $stage = 'DOWNLOAD_AGENT'
      $download = Download-StableAgent $target $expected
      $localSha = $download.sha
      $downloadSource = $download.source
      $downloadApiError = $download.apiError
    }

    $stage = 'START_AGENT'
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $AgentFile.Replace('"','\"') + '"'
    $proc = [Diagnostics.Process]::Start($psi)
    if (-not $proc) { throw 'AGENT_PROCESS_START_RETURNED_NULL' }

    $receipt = [ordered]@{
      ok = $true
      action = 'KICK_STABLE_AGENT_V3'
      stage = 'DISPATCHED'
      currentAgent = $current
      targetAgent = $target
      expectedSha = $expected
      localAgentSha = $localSha
      metaSource = $metaResult.source
      metaApiError = $metaResult.error
      downloadSource = $downloadSource
      downloadApiError = $downloadApiError
      childPid = $proc.Id
      normalChromeTouched = $false
      generateClicked = $false
      creditSpend = $false
      at = (Get-Date).ToString('o')
    }
    Save-Receipt $receipt
    $receipt | ConvertTo-Json -Depth 20 -Compress
    exit 0
  } catch {
    $receipt = [ordered]@{
      ok = $false
      action = 'KICK_STABLE_AGENT_V3'
      stage = $stage
      error = $_.Exception.Message
      normalChromeTouched = $false
      generateClicked = $false
      creditSpend = $false
      at = (Get-Date).ToString('o')
    }
    Save-Receipt $receipt
    $receipt | ConvertTo-Json -Depth 20 -Compress
    exit 2
  }
}

[ordered]@{ok=$false;action='RUN_CHROME_GOVERNOR_READBACK_V3';error='NO_ACTION_SELECTED';at=(Get-Date).ToString('o')} | ConvertTo-Json -Compress
exit 2
