param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Log=Join-Path $Root 'watchdog.log'
$MaxStateAgeSeconds=420
$StableMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
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
function CurrentAgentVersion{
  if(-not(Test-Path -LiteralPath $StateFile)){return ''}
  try{return [string]((Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}catch{return ''}
}
function StableTargetVersion{
  try{
    $meta=Invoke-RestMethod -Uri ($StableMetaUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Method Get -TimeoutSec 5
    if($meta -and $meta.enabled){return [string]$meta.version}
  }catch{}
  return ''
}

$hostOk=HostHealthy
$agentOk=AgentProcessPresent
$stateOk=StateFresh
$currentVersion=CurrentAgentVersion
$targetVersion=StableTargetVersion
$versionOk=(!$targetVersion -or ($currentVersion -eq $targetVersion))

# Healthy runtime is not enough: if the stable channel has advanced, run the
# existing safe AutoResume once so the new agent/governor can bind without
# creating a new OAuth, project, deployment, trigger, or Chrome profile.
if($hostOk -and $agentOk -and $stateOk -and $versionOk){
  Log ('PASS host=1 agent=1 stateFresh=1 current='+$currentVersion+' target='+$targetVersion)
  exit 0
}

Log ("RECOVERY_NEEDED host="+[int]$hostOk+" agent="+[int]$agentOk+" stateFresh="+[int]$stateOk+" versionOk="+[int]$versionOk+" current="+$currentVersion+" target="+$targetVersion)
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
