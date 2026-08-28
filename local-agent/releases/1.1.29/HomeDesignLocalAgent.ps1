param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.29'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$BaseAgentFile=Join-Path $Root 'HomeDesignLocalAgent-1.1.28-base.ps1'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$RecoveryFile=Join-Path $Root 'AGENT_1.1.29_RECOVERY.json'
$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1'
$HostExpected='e6a79fbb113a79e19650b2864072f6abde5bcffb'
$BaseAgentUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.28/HomeDesignLocalAgent.ps1'
$BaseAgentExpected='60b072c8bb5fa1d268684c74108aedaeae37545a'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function RefreshVerified([string]$Url,[string]$Path,[string]$Expected){
  $tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "SHA_MISMATCH path=$Path actual=$actual expected=$Expected"}
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function StopHost{
  try{foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -match 'HomeDesignLocalCommandHost'})){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}}catch{}
}
function StartHost125{
  $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$HostFile+'"'))
  Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden|Out-Null
  $deadline=(Get-Date).AddSeconds(20)
  do{
    Start-Sleep -Milliseconds 500
    $h=HostHealth
    if($h -and [bool]$h.ok -and [string]$h.version -eq '1.2.5' -and [bool]$h.asyncJobs){return $h}
  }while((Get-Date)-lt $deadline)
  throw 'HOST_1.2.5_START_FAILED'
}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  return ''
}
function PromoteState{
  if(-not(Test-Path -LiteralPath $StateFile)){return $false}
  try{$s=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $false}
  if($s.PSObject.Properties.Name -contains 'agentVersion'){$s.agentVersion=$AgentVersion}else{$s|Add-Member -NotePropertyName agentVersion -NotePropertyValue $AgentVersion}
  if($s.PSObject.Properties.Name -contains 'agentMode'){$s.agentMode='HOST_FIRST_125_THEN_AGENT128_AUTORESUME_1.1.29'}else{$s|Add-Member -NotePropertyName agentMode -NotePropertyValue 'HOST_FIRST_125_THEN_AGENT128_AUTORESUME_1.1.29'}
  if($s.PSObject.Properties.Name -contains 'commandHostVersion'){$s.commandHostVersion='1.2.5'}else{$s|Add-Member -NotePropertyName commandHostVersion -NotePropertyValue '1.2.5'}
  if($s.PSObject.Properties.Name -contains 'hostHealthy'){$s.hostHealthy=$true}else{$s|Add-Member -NotePropertyName hostHealthy -NotePropertyValue $true}
  if($s.PSObject.Properties.Name -contains 'hostAsyncJobs'){$s.hostAsyncJobs=$true}else{$s|Add-Member -NotePropertyName hostAsyncJobs -NotePropertyValue $true}
  if($s.PSObject.Properties.Name -contains 'updatedAt'){$s.updatedAt=(Get-Date).ToString('o')}else{$s|Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date).ToString('o')}
  $json=$s|ConvertTo-Json -Depth 30
  $json|Set-Content -LiteralPath $StateFile -Encoding UTF8
  $json|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
  $central=FindCentral
  if($central){try{$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}catch{}}
  return $true
}

$r=[ordered]@{
  action='AGENT_1.1.29_HOST_FIRST_125_AUTORESUME'
  startedAt=(Get-Date).ToString('o')
  hostBefore=$null
  hostRecovered=$false
  hostVersionAfter=''
  baseAgentExit=$null
  statePromoted=$false
  ok=$false
  error=''
}
try{
  $before=HostHealth;$r.hostBefore=$before
  $hostReady=($before -and [bool]$before.ok -and [bool]$before.asyncJobs -and [string]$before.version -eq '1.2.5')
  if(-not $hostReady){
    RefreshVerified $HostUrl $HostFile $HostExpected
    StopHost
    Start-Sleep -Milliseconds 700
    $started=StartHost125
    $r.hostRecovered=$true
  }
  $host=HostHealth
  if(-not($host -and [bool]$host.ok -and [bool]$host.asyncJobs -and [string]$host.version -eq '1.2.5')){throw 'HOST_1.2.5_NOT_HEALTHY'}
  $r.hostVersionAfter=[string]$host.version

  RefreshVerified $BaseAgentUrl $BaseAgentFile $BaseAgentExpected
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BaseAgentFile
  $r.baseAgentExit=$LASTEXITCODE
  if($r.baseAgentExit -ne 0){throw "BASE_AGENT_1.1.28_EXIT_$($r.baseAgentExit)"}

  $host2=HostHealth
  if(-not($host2 -and [bool]$host2.ok -and [bool]$host2.asyncJobs -and [string]$host2.version -eq '1.2.5')){throw 'HOST_1.2.5_LOST_AFTER_BASE_AGENT'}
  $r.statePromoted=PromoteState
  if(-not $r.statePromoted){throw 'STATE_PROMOTION_FAILED'}
  $r.ok=$true
}catch{
  $r.error=$_.Exception.Message
  $r.ok=$false
}
$r.completedAt=(Get-Date).ToString('o')
$r|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $RecoveryFile -Encoding UTF8
if($r.ok){exit 0}else{exit 2}
