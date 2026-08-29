param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Api='https://api.github.com/repos/'+$Repo+'/contents'
$Raw='https://raw.githubusercontent.com/'+$Repo+'/main'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$headers=@{'User-Agent'='HomeDesign-Hardened-Recovery';'Accept'='application/vnd.github+json'}
$installRc=99;$watchdogRc=99;$agentRc=99;$version=''
try{
  $installer=Join-Path $Root 'INSTALL_AUTO_RESUME_TASK.ps1'
  $cb=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri ($Raw+'/local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1?hdcb='+$cb) -OutFile $installer -TimeoutSec 60
  try { & schtasks.exe /End /TN 'HomeDesignAutomation-AutoResume' | Out-Null } catch {}
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
  $installRc=$LASTEXITCODE

  $watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
  if(Test-Path -LiteralPath $watchdog){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $watchdog
    $watchdogRc=$LASTEXITCODE
  } else {$watchdogRc=98}

  $stable=Invoke-RestMethod -Uri ($Api+'/local-agent/stable/agent.json?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -TimeoutSec 30
  $stableJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$stable.content -replace '\s',''))) | ConvertFrom-Json
  if(-not $stableJson.enabled){throw 'STABLE_AGENT_DISABLED'}
  $version=[string]$stableJson.version
  $expected=[string]$stableJson.gitBlobSha1
  $agentMeta=Invoke-RestMethod -Uri ($Api+'/local-agent/releases/'+$version+'/HomeDesignLocalAgent.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -TimeoutSec 30
  if(([string]$agentMeta.sha).ToLowerInvariant() -ne $expected.ToLowerInvariant()){
    throw ('STABLE_AGENT_SHA_MISMATCH api='+[string]$agentMeta.sha+' expected='+$expected)
  }
  $agent=Join-Path $Root ('HomeDesignLocalAgent-'+$version+'-stable.ps1')
  [IO.File]::WriteAllBytes($agent,[Convert]::FromBase64String(([string]$agentMeta.content -replace '\s','')))
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $agent
  $agentRc=$LASTEXITCODE
} catch {
  Write-Host ('RECOVERY_EXCEPTION='+$_.Exception.Message)
}
$state=Join-Path $Root 'state.json'
$receipt=Join-Path $Root 'WATCHDOG_LAST.json'
Write-Host ('INSTALL_RC='+$installRc)
Write-Host ('WATCHDOG_RC='+$watchdogRc)
Write-Host ('STABLE_AGENT_VERSION='+$version)
Write-Host ('STABLE_AGENT_RC='+$agentRc)
if(Test-Path -LiteralPath $state){Write-Host ('STATE='+(Get-Content -LiteralPath $state -Raw -Encoding UTF8))}
if(Test-Path -LiteralPath $receipt){Write-Host ('WATCHDOG_RECEIPT='+(Get-Content -LiteralPath $receipt -Raw -Encoding UTF8))}
if($installRc -eq 0 -and $watchdogRc -eq 0 -and $agentRc -eq 0){exit 0}else{exit 2}
