param([switch]$Loop)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$AgentFile = Join-Path $Root 'HomeDesignLocalAgent.ps1'
$AgentMetaUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
$AgentBaseUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases'
$BootstrapLog = Join-Path $Root 'bootstrap.log'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function BLog([string]$m) {
  Add-Content -LiteralPath $BootstrapLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8
}

function Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$mutex = New-Object System.Threading.Mutex($false,'HomeDesignLocalAgentBootstrapV1')
if (-not $mutex.WaitOne(0,$false)) { exit 0 }

try {
  do {
    $pollSeconds = 300
    try {
      $meta = Invoke-RestMethod -Uri $AgentMetaUrl -Method Get -TimeoutSec 30
      if ($meta.pollSeconds) { $pollSeconds = [Math]::Max(60,[int]$meta.pollSeconds) }

      if ($meta.enabled) {
        $needs = -not (Test-Path -LiteralPath $AgentFile)
        if (-not $needs) {
          $needs = (Sha256 $AgentFile) -ne ([string]$meta.sha256).ToLowerInvariant()
        }

        if ($needs) {
          $tmp = $AgentFile + '.download'
          $url = "$AgentBaseUrl/$($meta.version)/HomeDesignLocalAgent.ps1"
          Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
          if ((Sha256 $tmp) -ne ([string]$meta.sha256).ToLowerInvariant()) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            throw 'Agent SHA256 mismatch.'
          }
          Move-Item -LiteralPath $tmp -Destination $AgentFile -Force
          BLog "Agent updated to $($meta.version)."
        }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AgentFile
      } else {
        BLog 'Agent stable channel is disabled.'
      }
    } catch {
      BLog ("Bootstrap cycle error: " + $_.Exception.Message)
    }

    if ($Loop) { Start-Sleep -Seconds $pollSeconds }
  } while ($Loop)
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
}
