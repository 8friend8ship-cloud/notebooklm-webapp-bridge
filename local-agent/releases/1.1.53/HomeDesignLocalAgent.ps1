param()

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.53'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$PreviousAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.52.ps1'
$PreviousAgentUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.52/HomeDesignLocalAgent.ps1'
$PreviousAgentSha='a268a843ab4c51b72b044a5fefdeb2433a9fefd5'
$Binder=Join-Path $Root 'Bind-FrontPersonaOrchestrationAppsScriptV2.ps1'
$BinderUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/Bind-FrontPersonaOrchestrationAppsScriptV2.ps1'
$BinderSha='10882d60d84106a9554c04bee019a7d77cf96121'
$State=Join-Path $Root 'state.json'

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
function FetchPinned([string]$Url,[string]$Destination,[string]$ExpectedSha){
  $tmp=$Destination+'.download'
  Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
  if($actual -ne $ExpectedSha.ToLowerInvariant()){
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw ('SHA_MISMATCH:'+$actual+':'+$ExpectedSha)
  }
  Move-Item -LiteralPath $tmp -Destination $Destination -Force
  return $actual
}
function FindCentralRoot{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not $drv.Root){continue}
    foreach($cand in @(
      (Join-Path $drv.Root $centralName),
      (Join-Path $drv.Root ($myDriveKo+'\'+$centralName)),
      (Join-Path $drv.Root ('My Drive\'+$centralName)),
      (Join-Path $drv.Root ('Google Drive\'+$centralName))
    )){
      if(Test-Path -LiteralPath $cand -PathType Container){return $cand}
    }
  }
  return ''
}
function SaveJson([string]$Path,$Object){
  if(-not $Path){return}
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  $Object|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding UTF8
}
function ReadJson([string]$Path){
  if(-not $Path -or -not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function InvokeChild([string]$Path,[string[]]$Args=@()){
  $argList=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Path)+$Args
  $out=& powershell.exe @argList 2>&1|Out-String
  return [ordered]@{exitCode=$LASTEXITCODE;stdout=$out.Trim()}
}
function LastJson([string]$Text){
  $parsed=$null
  foreach($line in @($Text -split "`r?`n")){
    if(-not $line -or -not $line.Trim()){continue}
    try{$candidate=$line.Trim()|ConvertFrom-Json;if($candidate -and $null -ne $candidate.ok){$parsed=$candidate}}catch{}
  }
  return $parsed
}
function IsTerminalPersonaV2($Receipt){
  if(-not $Receipt){return $false}
  return [bool]([string]$Receipt.status -in @('PUSH_PULL_READBACK_X2_PASS','FAILED','FAILED_ROLLED_BACK'))
}

$central=FindCentralRoot
$runtimeRoot=if($central){Join-Path $central 'Runtime_Readback'}else{''}
$personaFolder=if($runtimeRoot){Join-Path $runtimeRoot 'AppsScript_Persona'}else{''}
$v1Path=if($personaFolder){Join-Path $personaFolder 'WEBAPP_TEMPLATE_05_PERSONA_BIND_V1.json'}else{Join-Path $Root 'WEBAPP_TEMPLATE_05_PERSONA_BIND_V1.json'}
$v2Path=if($personaFolder){Join-Path $personaFolder 'WEBAPP_TEMPLATE_05_PERSONA_BIND_V2.json'}else{Join-Path $Root 'WEBAPP_TEMPLATE_05_PERSONA_BIND_V2.json'}
$agentReceipt=if($runtimeRoot){Join-Path $runtimeRoot 'AGENT_1.1.53_PERSONA_SCRIPT_ID_DISCOVERY_BIND.json'}else{Join-Path $Root 'AGENT_1.1.53_PERSONA_SCRIPT_ID_DISCOVERY_BIND.json'}

$errors=@()
$previousSha=''
$previousRun=$null
$previousParsed=$null
$binderSha=''
$binderRun=$null
$binderParsed=$null
$dispatch='NOT_EVALUATED'

try{
  $previousSha=FetchPinned $PreviousAgentUrl $PreviousAgent $PreviousAgentSha
  $previousRun=InvokeChild $PreviousAgent
  $previousParsed=LastJson ([string]$previousRun.stdout)
}catch{$errors+=('PREVIOUS_AGENT:'+$_.Exception.Message)}
$previousOk=[bool]($previousSha -eq $PreviousAgentSha -and $previousRun -and [int]$previousRun.exitCode -eq 0 -and $previousParsed -and [bool]$previousParsed.ok)

$v1=ReadJson $v1Path
$v2=ReadJson $v2Path
if(-not $previousOk){
  $dispatch='PREVIOUS_AGENT_HOLD'
}elseif(IsTerminalPersonaV2 $v2){
  $dispatch=if([bool]$v2.ok -and [string]$v2.status -eq 'PUSH_PULL_READBACK_X2_PASS'){'PERSONA_V2_ALREADY_PASS'}else{'PERSONA_V2_TERMINAL_FAILURE_HOLD'}
}elseif(-not $v1){
  $dispatch='PERSONA_V1_RECEIPT_MISSING_HOLD'
}elseif([bool]$v1.ok){
  $dispatch='PERSONA_V1_ALREADY_PASS_NO_V2_REQUIRED'
}elseif([string]$v1.error -ne 'TARGET_DEPLOYMENT_MATCH_COUNT:0'){
  $dispatch='PERSONA_V1_ERROR_NOT_ELIGIBLE_FOR_V2'
}else{
  try{
    $binderSha=FetchPinned $BinderUrl $Binder $BinderSha
    $binderRun=InvokeChild $Binder
    $binderParsed=LastJson ([string]$binderRun.stdout)
    $v2=ReadJson $v2Path
    if($v2 -and [bool]$v2.ok -and [string]$v2.status -eq 'PUSH_PULL_READBACK_X2_PASS'){
      $dispatch='PERSONA_V2_BIND_PASS'
    }elseif(IsTerminalPersonaV2 $v2){
      $dispatch='PERSONA_V2_BIND_FAILED_HOLD'
    }else{
      $dispatch='PERSONA_V2_NO_TERMINAL_RECEIPT_HOLD'
    }
  }catch{$errors+=('PERSONA_BIND_V2:'+$_.Exception.Message);$dispatch='PERSONA_V2_EXCEPTION_HOLD'}
}

$personaVerified=[bool]($v2 -and [bool]$v2.ok -and [string]$v2.status -eq 'PUSH_PULL_READBACK_X2_PASS')
$receipt=[ordered]@{
  ok=$previousOk
  governanceOk=$previousOk
  personaBindVerified=$personaVerified
  action='AGENT_1.1.53_PERSONA_EXACT_EXISTING_SCRIPT_DISCOVERY_BIND'
  agentVersion=$AgentVersion
  status=$dispatch
  previousAgentVersion='1.1.52'
  previousAgentSha=$previousSha
  previousExitCode=if($previousRun){$previousRun.exitCode}else{$null}
  previousResult=$previousParsed
  personaV1Receipt=$v1
  personaV2Receipt=$v2
  binderSha=$binderSha
  binderExitCode=if($binderRun){$binderRun.exitCode}else{$null}
  binderResult=$binderParsed
  newProjectCreated=$false
  oauthChanged=$false
  scopeChanged=$false
  newDeployment=$false
  newTrigger=$false
  paidGeminiApiCalled=$false
  blindRetry=$false
  errors=$errors
  at=(Get-Date).ToString('o')
}
try{SaveJson $agentReceipt $receipt}catch{}
try{
  $s=ReadJson $State
  if(-not $s){$s=[pscustomobject]@{}}
  $s|Add-Member agentVersion $AgentVersion -Force
  $s|Add-Member agentMode 'PERSONA_EXACT_EXISTING_SCRIPT_DISCOVERY_BIND_1.1.53' -Force
  $s|Add-Member ok $previousOk -Force
  $s|Add-Member governanceOk $previousOk -Force
  $s|Add-Member personaBindVerified $personaVerified -Force
  $s|Add-Member status $dispatch -Force
  $s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force
  SaveJson $State $s
}catch{}
$receipt|ConvertTo-Json -Depth 100 -Compress
if($previousOk){exit 0}else{exit 2}
