param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Hub=Join-Path $Root 'CentralNotebookRuntimeHub.ps1'
$HubUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/CentralNotebookRuntimeHub.ps1'
$Log=Join-Path $Root 'watchdog.log'
$MaxStateAgeSeconds=420
$HubRefreshHours=6
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Log([string]$m){Add-Content -LiteralPath $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function AgentProcessPresent{
  try{return @((Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -match '(?i)HomeDesignLocalAgent(?:-1\.1\.\d+-patched)?\.ps1' })).Count -gt 0}catch{return $false}
}
function StateFresh{
  if(-not(Test-Path -LiteralPath $StateFile)){return $false}
  try{
    $item=Get-Item -LiteralPath $StateFile -ErrorAction Stop
    return (((Get-Date)-$item.LastWriteTime).TotalSeconds -le $MaxStateAgeSeconds)
  }catch{return $false}
}
function EnsureHub{
  $need=-not(Test-Path -LiteralPath $Hub)
  if(-not $need){try{$need=(((Get-Date)-(Get-Item -LiteralPath $Hub).LastWriteTime).TotalHours -ge $HubRefreshHours)}catch{$need=$true}}
  if(-not $need){return $true}
  try{
    $tmp=$Hub+'.download';$url=$HubUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 30
    Move-Item -LiteralPath $tmp -Destination $Hub -Force
    Log 'NOTEBOOK_HUB_REFRESHED';return $true
  }catch{Log ('NOTEBOOK_HUB_REFRESH_FAILED '+$_.Exception.Message);return (Test-Path -LiteralPath $Hub)}
}
function RunHubQuick{
  if(-not(EnsureHub)){return}
  try{
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Hub -Quick | Out-Null
    $rc=$LASTEXITCODE
    Log ("NOTEBOOK_HUB_EXIT=$rc")
  }catch{Log ('NOTEBOOK_HUB_EXCEPTION '+$_.Exception.Message)}
}

$hostOk=HostHealthy
$agentOk=AgentProcessPresent
$stateOk=StateFresh
if($hostOk -and $agentOk -and $stateOk){
  Log 'PASS host=1 agent=1 stateFresh=1'
  RunHubQuick
  exit 0
}

Log ("RECOVERY_NEEDED host="+[int]$hostOk+" agent="+[int]$agentOk+" stateFresh="+[int]$stateOk)
if(-not(Test-Path -LiteralPath $AutoResume)){
  Log 'AUTO_RESUME_MISSING'
  RunHubQuick
  exit 2
}
try{
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AutoResume
  $rc=$LASTEXITCODE
  Log ("AUTO_RESUME_EXIT=$rc hostAfter="+[int](HostHealthy))
  RunHubQuick
  exit $rc
}catch{
  Log ('WATCHDOG_EXCEPTION '+$_.Exception.Message)
  RunHubQuick
  exit 3
}
