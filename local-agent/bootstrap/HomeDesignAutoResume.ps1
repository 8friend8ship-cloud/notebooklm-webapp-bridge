param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Log=Join-Path $Root 'auto-resume.log'
$ResumeUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1'
$ResumeLocal=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Log([string]$m){Add-Content -LiteralPath $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}

Log 'AUTO_RESUME_START'
# Give Wi-Fi/Ethernet and Windows user profile a short chance to settle after wake/logon.
for($i=0;$i -lt 12;$i++){
  try{
    Invoke-WebRequest -UseBasicParsing -Uri ('https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Method Head -TimeoutSec 5 | Out-Null
    break
  }catch{Start-Sleep -Seconds 5}
}

try{
  $tmp=$ResumeLocal+'.download'
  $url=$ResumeUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 60
  Move-Item -LiteralPath $tmp -Destination $ResumeLocal -Force
  Log 'RESUME_SCRIPT_REFRESHED'
}catch{
  Log ('RESUME_DOWNLOAD_FAILED '+$_.Exception.Message)
  if(-not(Test-Path -LiteralPath $ResumeLocal)){exit 2}
}

try{
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ResumeLocal
  $rc=$LASTEXITCODE
  Log ("RESUME_EXIT=$rc HOST_HEALTH="+(HostHealthy))
  exit $rc
}catch{
  Log ('RESUME_EXCEPTION '+$_.Exception.Message)
  exit 3
}
