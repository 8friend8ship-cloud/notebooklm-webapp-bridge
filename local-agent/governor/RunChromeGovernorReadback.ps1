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
function GitBlobSha1([string]$Path){$B=[IO.File]::ReadAllBytes($Path);$H=[Text.Encoding]::ASCII.GetBytes(('blob '+$B.Length+[char]0));$A=New-Object byte[] ($H.Length+$B.Length);[Buffer]::BlockCopy($H,0,$A,0,$H.Length);[Buffer]::BlockCopy($B,0,$A,$H.Length,$B.Length);$S=[Security.Cryptography.SHA1]::Create();try{return (($S.ComputeHash($A)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$S.Dispose()}}
function GetBridgeReleaseRaw {
  $Url='https://raw.githubusercontent.com/'+$Repo+'/main/runtime/stable/release.json?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $Text=(Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 10).Content
  $Rel=$Text|ConvertFrom-Json
  if(-not $Rel.enabled){throw 'BRIDGE_STABLE_DISABLED'}
  if([string]$Rel.action -ne 'apply'){throw 'BRIDGE_STABLE_ACTION_NOT_APPLY'}
  if([bool]$Rel.requiresUserApproval){throw 'BRIDGE_RELEASE_REQUIRES_USER_APPROVAL'}
  return $Rel
}
function TestBridgeRelease($Rel){
  foreach($F in @($Rel.files)){
    $Rp=[string]$F.path
    if($Rp -match '\.\.' -or [IO.Path]::IsPathRooted($Rp)){return $false}
    $P=Join-Path $ExtensionRoot $Rp.Replace('/','\')
    if(-not(Test-Path -LiteralPath $P)){return $false}
    if((GitBlobSha1 $P).ToLowerInvariant() -ne ([string]$F.gitBlobSha1).ToLowerInvariant()){return $false}
  }
  return $true
}
function DedicatedRunning {
  try{return (@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"}).Count -gt 0)}catch{return $false}
}
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
  $Dedicated=DedicatedRunning
  $BridgeVersion=$(if($Manifest){[string]$Manifest.version}else{'UNKNOWN'})
  $Rel=$null;$ReleaseError='';$IntegrityEvidence=$false
  try{$Rel=GetBridgeReleaseRaw;$IntegrityEvidence=TestBridgeRelease $Rel}catch{$ReleaseError=$_.Exception.Message}
  $Target=$(if($Rel){[string]$Rel.version}else{$ExpectedBridge})
  $Healthy=($BridgeVersion -eq $Target -and $IntegrityEvidence -and $Health -and [bool]$Health.ok -and [bool]$Health.asyncJobs -and $Dedicated)
  [ordered]@{ok=$true;transportOk=$true;healthy=[bool]$Healthy;action='BRIDGE_LOCAL_EVIDENCE';at=(Get-Date).ToString('o');expectedBridge=$ExpectedBridge;targetBridge=$Target;bridgeVersion=$BridgeVersion;integrityEvidence=[bool]$IntegrityEvidence;integritySource='RAW_RELEASE_LIVE';releaseError=$ReleaseError;hostHealthy=$(if($Health){[bool]$Health.ok}else{$false});hostVersion=$(if($Health){[string]$Health.version}else{'UNKNOWN'});hostAsyncJobs=$(if($Health){[bool]$Health.asyncJobs}else{$false});dedicatedChromeRunning=[bool]$Dedicated;agentVersion=$(if($State){[string]$State.agentVersion}else{'UNKNOWN'});agentStatus=$(if($State){[string]$State.status}else{'UNKNOWN'});applyResult=$Apply}|ConvertTo-Json -Depth 30 -Compress
  exit 0
}
if($BridgeStatusOnly){
  try{
    $Rel=GetBridgeReleaseRaw
    $Manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json')
    $Health=$null;try{$Health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{}
    $Integrity=TestBridgeRelease $Rel
    $Dedicated=DedicatedRunning
    $Apply=ReadJson (Join-Path $Root 'NOTEBOOKLM_BRIDGE_APPLY_RESULT.json')
    $Healthy=($Manifest -and [string]$Manifest.version -eq [string]$Rel.version -and $Integrity -and $Health -and [bool]$Health.ok -and [bool]$Health.asyncJobs -and $Dedicated)
    [ordered]@{ok=[bool]$Healthy;transportOk=$true;healthy=[bool]$Healthy;action='BRIDGE_STATUS_ONLY';at=(Get-Date).ToString('o');targetBridge=[string]$Rel.version;bridgeVersion=$(if($Manifest){[string]$Manifest.version}else{'UNKNOWN'});integrityOk=[bool]$Integrity;integritySource='RAW_RELEASE_LIVE';hostHealthy=$(if($Health){[bool]$Health.ok}else{$false});hostVersion=$(if($Health){[string]$Health.version}else{'UNKNOWN'});hostAsyncJobs=$(if($Health){[bool]$Health.asyncJobs}else{$false});dedicatedChromeRunning=[bool]$Dedicated;applyResult=$Apply}|ConvertTo-Json -Depth 30 -Compress
  }catch{
    [ordered]@{ok=$false;transportOk=$true;healthy=$false;action='BRIDGE_STATUS_ONLY';integritySource='RAW_RELEASE_LIVE';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
  }
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
