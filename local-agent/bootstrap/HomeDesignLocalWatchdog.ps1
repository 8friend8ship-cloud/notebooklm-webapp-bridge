param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Log=Join-Path $Root 'watchdog.log'
$MaxStateAgeSeconds=420
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

$hostOk=HostHealthy
$agentOk=AgentProcessPresent
$stateOk=StateFresh
if($hostOk -and $agentOk -and $stateOk){Log 'PASS host=1 agent=1 stateFresh=1';exit 0}

Log ("RECOVERY_NEEDED host="+[int]$hostOk+" agent="+[int]$agentOk+" stateFresh="+[int]$stateOk)
if(-not(Test-Path -LiteralPath $AutoResume)){
  Log 'AUTO_RESUME_MISSING'
  exit 2
}
try{
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AutoResume
  $rc=$LASTEXITCODE
  Log ("AUTO_RESUME_EXIT=$rc hostAfter="+[int](HostHealthy))
  exit $rc
}catch{
  Log ('WATCHDOG_EXCEPTION '+$_.Exception.Message)
  exit 3
}
