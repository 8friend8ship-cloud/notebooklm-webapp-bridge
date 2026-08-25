param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor,[switch]$ApplyStableBridge,[switch]$BridgeStatusOnly,[switch]$BridgeLocalEvidence,[string]$ExpectedBridge='0.2.18')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$V2=Join-Path $Root 'RunChromeGovernorReadbackV2.ps1'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Api="https://api.github.com/repos/$Repo/contents/local-agent/governor/RunChromeGovernorReadbackV2.ps1?ref=main"
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function RefreshV2 {
  try {
    $Headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
    $R=Invoke-RestMethod -Uri $Api -Headers $Headers -Method Get -TimeoutSec 10
    if(-not $R.content){throw 'V2_CONTENT_EMPTY'}
    $Bytes=[Convert]::FromBase64String(([string]$R.content -replace '\s',''))
    $Tmp=$V2+'.download'
    [IO.File]::WriteAllBytes($Tmp,$Bytes)
    Move-Item -LiteralPath $Tmp -Destination $V2 -Force
    return $true
  } catch {
    return (Test-Path -LiteralPath $V2)
  }
}

if($BridgeLocalEvidence){
  $Manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json')
  $Apply=ReadJson (Join-Path $Root 'NOTEBOOKLM_BRIDGE_APPLY_RESULT.json')
  $State=ReadJson (Join-Path $Root 'state.json')
  $Health=$null;try{$Health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{}
  $Dedicated=$false;try{$Dedicated=(@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"}).Count -gt 0)}catch{}
  $BridgeVersion=$(if($Manifest){[string]$Manifest.version}else{'UNKNOWN'})
  $IntegrityEvidence=($Apply -and [bool]$Apply.integrityOk -and [string]$Apply.targetVersion -eq $ExpectedBridge -and [string]$Apply.installedAfter -eq $ExpectedBridge)
  $Healthy=($BridgeVersion -eq $ExpectedBridge -and $IntegrityEvidence -and $Health -and [bool]$Health.ok -and [bool]$Health.asyncJobs -and $Dedicated)
  [ordered]@{ok=$true;transportOk=$true;healthy=[bool]$Healthy;action='BRIDGE_LOCAL_EVIDENCE';at=(Get-Date).ToString('o');expectedBridge=$ExpectedBridge;bridgeVersion=$BridgeVersion;integrityEvidence=[bool]$IntegrityEvidence;hostHealthy=$(if($Health){[bool]$Health.ok}else{$false});hostVersion=$(if($Health){[string]$Health.version}else{'UNKNOWN'});hostAsyncJobs=$(if($Health){[bool]$Health.asyncJobs}else{$false});dedicatedChromeRunning=[bool]$Dedicated;agentVersion=$(if($State){[string]$State.agentVersion}else{'UNKNOWN'});agentStatus=$(if($State){[string]$State.status}else{'UNKNOWN'});applyResult=$Apply}|ConvertTo-Json -Depth 30 -Compress
  exit 0
}

$NeedRefresh=($KickStableAgent -or $RunGovernor -or $ApplyStableBridge -or $BridgeStatusOnly -or -not(Test-Path -LiteralPath $V2))
if($NeedRefresh){
  if(-not(RefreshV2)){
    [ordered]@{ok=$false;action='V2_FAST_CONTROL_BOOTSTRAP';error='V2_FETCH_FAILED_AND_NO_LOCAL_COPY';at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

$ChildArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$V2)
if($KickStableAgent){$ChildArgs+='-KickStableAgent'}
if($StatusOnly){$ChildArgs+='-StatusOnly'}
if($RunGovernor){$ChildArgs+='-RunGovernor'}
if($ApplyStableBridge){$ChildArgs+='-ApplyStableBridge'}
if($BridgeStatusOnly){$ChildArgs+='-BridgeStatusOnly'}
& powershell.exe @ChildArgs
$Rc=$LASTEXITCODE
if($BridgeStatusOnly){exit 0}
exit $Rc
