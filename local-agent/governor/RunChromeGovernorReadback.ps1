param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor,[switch]$ApplyStableBridge,[switch]$BridgeStatusOnly)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$V2=Join-Path $Root 'RunChromeGovernorReadbackV2.ps1'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Api="https://api.github.com/repos/$Repo/contents/local-agent/governor/RunChromeGovernorReadbackV2.ps1?ref=main"
New-Item -ItemType Directory -Force -Path $Root|Out-Null

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

$NeedRefresh=($KickStableAgent -or $RunGovernor -or $ApplyStableBridge -or $BridgeStatusOnly -or -not(Test-Path -LiteralPath $V2))
if($NeedRefresh){
  if(-not(RefreshV2)){
    [ordered]@{ok=$false;action='V2_FAST_CONTROL_BOOTSTRAP';error='V2_FETCH_FAILED_AND_NO_LOCAL_COPY';at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

$Args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$V2)
if($KickStableAgent){$Args+='-KickStableAgent'}
if($StatusOnly){$Args+='-StatusOnly'}
if($RunGovernor){$Args+='-RunGovernor'}
if($ApplyStableBridge){$Args+='-ApplyStableBridge'}
if($BridgeStatusOnly){$Args+='-BridgeStatusOnly'}
$P=Start-Process powershell.exe -ArgumentList $Args -WindowStyle Hidden -Wait -PassThru
exit $P.ExitCode
