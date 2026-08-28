param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$BaseAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.34-base.ps1'
$StatePath=Join-Path $Root 'state.json'
$Base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.34/HomeDesignLocalAgent.ps1'
$Expected='ad2adc3c1eeb9c3b9a6620069af8a64b9e8218ad'
$TaskId='CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01'
$HostBase='http://127.0.0.1:8765'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  return ''
}
function WriteCentral([string]$Name,$Object){$central=FindCentral;if(-not $central){return $false};$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$Object|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $dest $Name) -Encoding UTF8;return $true}
function FinishState([bool]$Ok,[string]$Status,[string]$ErrorText){
  $state=$null;try{if(Test-Path -LiteralPath $StatePath){$state=Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
  if(-not $state){$state=[pscustomobject]@{}}
  $state|Add-Member -NotePropertyName agentVersion -NotePropertyValue '1.1.35' -Force
  $state|Add-Member -NotePropertyName agentMode -NotePropertyValue 'HOST127_CONTENTOS_TASK203_DIRECT_1.1.35' -Force
  $state|Add-Member -NotePropertyName ok -NotePropertyValue $Ok -Force
  $state|Add-Member -NotePropertyName status -NotePropertyValue $Status -Force
  $state|Add-Member -NotePropertyName updatedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
  if($ErrorText){$state|Add-Member -NotePropertyName errors -NotePropertyValue @($ErrorText) -Force}
  $state|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $StatePath -Encoding UTF8
}

Invoke-WebRequest -UseBasicParsing -Uri ($Base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $BaseAgent -TimeoutSec 30
$Actual=(GitBlobSha1 $BaseAgent).ToLowerInvariant();if($Actual -ne $Expected){throw "Agent 1.1.34 base hash mismatch actual=$Actual expected=$Expected"}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BaseAgent
if($LASTEXITCODE -ne 0){throw ('BASE_AGENT_1.1.34_FAILED:'+ $LASTEXITCODE)}
$health=Invoke-RestMethod -Method Get -Uri ($HostBase+'/health') -TimeoutSec 5
if(-not $health.ok -or [string]$health.version -ne '1.2.7' -or -not [bool]$health.asyncJobs){throw ('HOST127_HEALTH_GATE_FAILED:'+($health|ConvertTo-Json -Compress))}
$sourceText=(@{repo='8friend8ship-cloud/contents-os-git';branch='main';script='tools/Repair-ContentOS-DriveCacheAppsScript.ps1';args=@{}}|ConvertTo-Json -Compress)
$task=[ordered]@{taskId=$TaskId;taskType='LOCAL_POWERSHELL';sourceText=$sourceText;timeoutSeconds=600}
$submit=Invoke-RestMethod -Method Post -Uri ($HostBase+'/run') -ContentType 'application/json' -Body (@{task=$task}|ConvertTo-Json -Depth 12 -Compress) -TimeoutSec 10
if(-not $submit.ok -or @('STARTED','RUNNING','DONE') -notcontains [string]$submit.state){throw ('HOST127_TASK203_SUBMIT_FAILED:'+($submit|ConvertTo-Json -Depth 12 -Compress))}
$result=$null
for($i=0;$i -lt 10;$i++){
  $result=Invoke-RestMethod -Method Get -Uri ($HostBase+'/result?taskId='+[Uri]::EscapeDataString($TaskId)) -TimeoutSec 5
  if([string]$result.state -eq 'DONE'){break}
  if([string]$result.state -eq 'ERROR'){break}
  Start-Sleep -Seconds 2
}
$receipt=[ordered]@{ok=$true;action='CONTENTOS_TASK203_HOST_DIRECT';agentVersion='1.1.35';hostVersion='1.2.7';taskId=$TaskId;submit=$submit;result=$result;idempotent=$true;repo='8friend8ship-cloud/contents-os-git';branch='main';script='tools/Repair-ContentOS-DriveCacheAppsScript.ps1';newOAuth=$false;newScope=$false;newProject=$false;newDeployment=$false;newTrigger=$false;vercelAction=$false;at=(Get-Date).ToString('o')}
if($result -and [string]$result.state -eq 'DONE'){
  $ok=[bool]$result.result.ok
  $receipt.ok=$ok
  [void](WriteCentral 'AGENT_1.1.35_CONTENTOS_TASK203_DIRECT.json' $receipt)
  if($ok){FinishState $true 'SELF_HEAL_PASS' '';exit 0}else{FinishState $false 'CONTENTOS_TASK203_FAILED' ([string]$result.result.stderr);exit 2}
}
if($result -and [string]$result.state -eq 'ERROR'){
  $receipt.ok=$false
  [void](WriteCentral 'AGENT_1.1.35_CONTENTOS_TASK203_DIRECT.json' $receipt)
  FinishState $false 'CONTENTOS_TASK203_HOST_ERROR' ([string]$result.error)
  exit 2
}
# Keep state on 1.1.34 while the Host wrapper is still running. The stable poll will rerun this exact idempotent wrapper and collect the same task result later.
[void](WriteCentral 'AGENT_1.1.35_CONTENTOS_TASK203_SUBMITTED.json' $receipt)
exit 0
