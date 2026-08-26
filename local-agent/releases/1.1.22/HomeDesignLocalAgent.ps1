param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.22'

$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$RecoveryFile=Join-Path $Root 'AGENT_1.1.22_RECOVERY.json'
$PrevFile=Join-Path $Root 'HomeDesignLocalAgent-1.1.21.ps1'
$PrevUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.21/HomeDesignLocalAgent.ps1'
$PrevExpected='e3b8ba053fdb39518ec8a5bcf857f67c88a25e66'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$Runner=Join-Path $GovRoot 'RunChromeGovernorReadbackV2.ps1'
$RunnerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/RunChromeGovernorReadbackV2.ps1'
New-Item -ItemType Directory -Force -Path $Root,$GovRoot|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path)
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[] ($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}
  finally{$s.Dispose()}
}
function Refresh([string]$Url,[string]$Path,[string]$Expected=''){
  $tmp=$Path+'.download'
  Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30
  if($Expected){
    $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
    if($actual -ne $Expected.ToLowerInvariant()){
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      throw "SHA_MISMATCH path=$Path actual=$actual expected=$Expected"
    }
  }
  Move-Item $tmp $Path -Force
}
function ReadState{
  if(-not(Test-Path $StateFile)){return $null}
  try{return Get-Content $StateFile -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function StateHealthy($s){
  return ($s -and [bool]$s.hostHealthy -and [bool]$s.dedicatedChromeRunning -and [bool]$s.governorCycleOk)
}
function WriteRecovery($o){$o|ConvertTo-Json -Depth 20|Set-Content $RecoveryFile -Encoding UTF8}

$r=[ordered]@{
  action='AGENT_1.1.22_AUTONOMOUS_RECOVERY'
  startedAt=(Get-Date).ToString('o')
  previousRunExit=$null
  stateBefore=$null
  governorRepairAttempted=$false
  governorRepairExit=$null
  bridgeRepairAttempted=$false
  bridgeRepairExit=$null
  secondRunExit=$null
  stateAfter=$null
  ok=$false
  error=''
}

try{
  Refresh $PrevUrl $PrevFile $PrevExpected
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PrevFile
  $r.previousRunExit=$LASTEXITCODE
  Start-Sleep -Seconds 2
  $s=ReadState
  $r.stateBefore=$s

  if(-not(StateHealthy $s)){
    Refresh $RunnerUrl $Runner
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Runner,[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){throw ('GOVERNOR_RUNNER_PARSE_FAILED: '+($errors[0].Message))}

    $r.governorRepairAttempted=$true
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Runner -RunGovernor | Out-Null
    $r.governorRepairExit=$LASTEXITCODE

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Runner -BridgeStatusOnly | Out-Null
    $bridgeStatus=$LASTEXITCODE
    if($bridgeStatus -ne 0){
      $r.bridgeRepairAttempted=$true
      & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Runner -ApplyStableBridge | Out-Null
      $r.bridgeRepairExit=$LASTEXITCODE
    }

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PrevFile
    $r.secondRunExit=$LASTEXITCODE
    Start-Sleep -Seconds 2
  }

  $final=ReadState
  $r.stateAfter=$final
  $r.ok=[bool](StateHealthy $final)
  if(-not $r.ok){$r.error='POST_RECOVERY_STATE_NOT_VERIFIED'}
}catch{
  $r.error=$_.Exception.Message
  $r.ok=$false
}
$r.completedAt=(Get-Date).ToString('o')
WriteRecovery $r
if($r.ok){exit 0}else{exit 2}
