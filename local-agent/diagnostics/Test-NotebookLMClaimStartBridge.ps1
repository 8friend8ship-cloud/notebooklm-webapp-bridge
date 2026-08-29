param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]{1,180}$')][string]$TaskId,
  [ValidateSet('AUTO','TEXT','IMAGE','AUDIO','VIDEO')][string]$TaskKind='AUTO',
  [int]$ExpectedMediaSeconds=0,
  [int]$ClaimedAgeSeconds=0,
  [int]$StartGraceSeconds=60,
  [string]$ExpectedOutputPath='',
  [int]$HostPort=8765,
  [switch]$WriteCentralReadback,
  [switch]$CreateLocalSaveSmoke,
  [switch]$SetupCaptureBridgeAutoSync,
  [switch]$KickAgent1141HostRepair,
  [switch]$KickAgent1155HostRepair
)

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ResultRoot=Join-Path $Root 'CommandResults'
$TaskRoot=Join-Path $ResultRoot $TaskId
$StatusPath=Join-Path $TaskRoot 'status.json'
$ResultPath=Join-Path $TaskRoot 'result.json'

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Find-CentralRoot {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($candidate in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  }
  return ''
}

if($KickAgent1155HostRepair){
  try{
    New-Item -ItemType Directory -Force -Path $Root|Out-Null
    $agent=Join-Path $Root 'HomeDesignLocalAgent-1.1.55-direct.ps1'
    $expected='90acc698096e3d94f2f6a695410b8344f79c60ab'
    $headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
    $resp=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/git/blobs/'+$expected+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -Method Get -TimeoutSec 20
    $tmp=$agent+'.download'
    [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$resp.content -replace '\s','')))
    $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
    if($actual -ne $expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('AGENT1155_BLOB_MISMATCH actual='+$actual+' expected='+$expected)}
    Move-Item -LiteralPath $tmp -Destination $agent -Force
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$agent+'"';$proc=[Diagnostics.Process]::Start($psi)
    [ordered]@{ok=$true;action='AGENT1155_IMMUTABLE_HOST_RECOVERY_DISPATCHED';taskId=$TaskId;agentSha=$actual;pid=[int]$proc.Id;expectedAgent='1.1.55';expectedHost='1.2.9';sourceFetchMode='IMMUTABLE_GIT_BLOB_API';normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='AGENT1155_IMMUTABLE_HOST_RECOVERY_DISPATCHED';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($KickAgent1141HostRepair){
  try{
    New-Item -ItemType Directory -Force -Path $Root|Out-Null
    $agent=Join-Path $Root 'HomeDesignLocalAgent-1.1.41-direct.ps1'
    $helper=Join-Path $Root 'Kick-Agent1141-AfterHostTask.ps1'
    $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.41/HomeDesignLocalAgent.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $agent -TimeoutSec 20
    $expected='b24b470dfc439a09446164091d392f886cb8f71e';$actual=(GitBlobSha1 $agent).ToLowerInvariant()
    if($actual -ne $expected){Remove-Item $agent -Force -ErrorAction SilentlyContinue;throw ('AGENT1141_SHA_MISMATCH actual='+$actual+' expected='+$expected)}
    $helperCode=@'
param([string]$AgentPath,[string]$ReceiptPath)
$ErrorActionPreference='Continue'
Start-Sleep -Seconds 4
$started=(Get-Date).ToString('o')
$p=$null;$err=''
try{$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$AgentPath+'"';$p=[Diagnostics.Process]::Start($psi)}catch{$err=$_.Exception.Message}
try{if($ReceiptPath){$o=[ordered]@{ok=[bool]$p;action='AGENT1141_DELAYED_HANDOFF';pid=$(if($p){[int]$p.Id}else{$null});agentPath=$AgentPath;startedAt=$started;error=$err;at=(Get-Date).ToString('o')};$o|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}}catch{}
'@
    Set-Content -LiteralPath $helper -Value $helperCode -Encoding UTF8
    $central=Find-CentralRoot;$receipt=$(if($central){Join-Path $central 'Runtime_Readback\AGENT_1.1.41_DELAYED_HANDOFF.json'}else{''})
    if($central){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $receipt)|Out-Null}
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -AgentPath "'+$agent+'" -ReceiptPath "'+$receipt+'"';$p=[Diagnostics.Process]::Start($psi)
    [ordered]@{ok=$true;action='AGENT1141_HOST128_DELAYED_HANDOFF_DISPATCHED';taskId=$TaskId;agentSha=$actual;handoffPid=[int]$p.Id;delaySeconds=4;expectedAgent='1.1.41';expectedHost='1.2.8';normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='AGENT1141_HOST128_DELAYED_HANDOFF_DISPATCHED';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($SetupCaptureBridgeAutoSync){
  try{
    $setupDir=Join-Path $Root 'capture'
    New-Item -ItemType Directory -Force -Path $setupDir|Out-Null
    $setup=Join-Path $setupDir 'Setup-NotebookLMCaptureBridgeAutoSync.ps1'
    $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/capture/Setup-NotebookLMCaptureBridgeAutoSync.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $setup -TimeoutSec 20
    $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $setup 2>&1
    $rc=$LASTEXITCODE
    $text=($output|Out-String).Trim()
    if($rc -ne 0){throw ('CAPTUREBRIDGE_SETUP_FAILED rc='+$rc+' output='+$text)}
    [ordered]@{ok=$true;action='NOTEBOOKLM_CAPTUREBRIDGE_AUTOSYNC_SETUP';taskId=$TaskId;output=$text;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_CAPTUREBRIDGE_AUTOSYNC_SETUP';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($CreateLocalSaveSmoke){
  try{
    $dir='C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM'
    New-Item -ItemType Directory -Force -Path $dir|Out-Null
    $file=Join-Path $dir '_TEST_NOTEBOOKLM_LOCAL_SAVE.txt'
    Set-Content -LiteralPath $file -Value ('NOTEBOOKLM_LOCAL_SAVE_TEST '+(Get-Date).ToString('o')) -Encoding UTF8
    $item=Get-Item -LiteralPath $file -ErrorAction Stop
    [ordered]@{ok=$true;action='NOTEBOOKLM_LOCAL_SAVE_SMOKE';folder=$dir;file=$file;size=[int64]$item.Length;exists=$true;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_LOCAL_SAVE_SMOKE';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Get-WorkBudgetSeconds([string]$Kind,[int]$MediaSeconds){
  $m=[Math]::Max(0,$MediaSeconds)
  switch($Kind){
    'AUDIO' { return [Math]::Max(120,[int]([Math]::Ceiling($m*1.5)+60)) }
    'VIDEO' { return [Math]::Max(300,[int]([Math]::Ceiling($m*3.0)+180)) }
    'IMAGE' { return 180 }
    'TEXT'  { return 120 }
    default { return $(if($m -gt 0){[Math]::Max(180,[int]([Math]::Ceiling($m*2.0)+120))}else{180}) }
  }
}
function Read-OutputProgress([string]$Path){
  $o=[ordered]@{configured=$false;exists=$false;kind='';sizeBytes=0;lastWrite='';ageSeconds=$null;progressing=$false}
  if([string]::IsNullOrWhiteSpace($Path)){return $o}
  $o.configured=$true
  try{
    if(Test-Path -LiteralPath $Path){
      $o.exists=$true;$item=Get-Item -LiteralPath $Path -ErrorAction Stop
      if($item.PSIsContainer){$o.kind='DIRECTORY'}else{$o.kind='FILE';$o.sizeBytes=[int64]$item.Length;$o.lastWrite=$item.LastWriteTime.ToString('o');$o.ageSeconds=[int][Math]::Floor(((Get-Date)-$item.LastWriteTime).TotalSeconds)}
      if($null -ne $o.ageSeconds -and $o.ageSeconds -le 90){$o.progressing=$true}
    }
  }catch{}
  return $o
}
$health=$null;$healthError='';try{$health=Invoke-RestMethod -Uri ("http://127.0.0.1:$HostPort/health") -Method Get -TimeoutSec 3}catch{$healthError=$_.Exception.Message}
$hostResult=$null;$hostResultError='';try{$hostResult=Invoke-RestMethod -Uri ("http://127.0.0.1:$HostPort/result?taskId="+[Uri]::EscapeDataString($TaskId)) -Method Get -TimeoutSec 3}catch{$hostResultError=$_.Exception.Message}
$status=Read-Json $StatusPath;$result=Read-Json $ResultPath;$wrapperPid=$null;$wrapperAlive=$false
if($status -and $status.wrapperPid){try{$wrapperPid=[int]$status.wrapperPid;$wrapperAlive=[bool](Get-Process -Id $wrapperPid -ErrorAction SilentlyContinue)}catch{}}
$resolvedKind=$TaskKind;if($resolvedKind -eq 'AUTO'){if($ExpectedMediaSeconds -gt 0){$resolvedKind='VIDEO'}else{$resolvedKind='TEXT'}}
$workBudget=Get-WorkBudgetSeconds $resolvedKind $ExpectedMediaSeconds;$startedAt=$null;$runAgeSeconds=$null
if($status -and $status.startedAt){try{$startedAt=[datetime]$status.startedAt;$runAgeSeconds=[int][Math]::Floor(((Get-Date)-$startedAt).TotalSeconds)}catch{}}
$outputProgress=Read-OutputProgress $ExpectedOutputPath
$state='UNKNOWN';$ok=$false;$problem=''
if(-not $health -or -not [bool]$health.ok){$state='HOST_DOWN';$problem='Local Command Host health check failed.'}
elseif($result -or ($hostResult -and [string]$hostResult.state -eq 'DONE')){$state='DONE';$ok=$true}
elseif(($hostResult -and [string]$hostResult.state -eq 'RUNNING') -or ($status -and $wrapperAlive)){if($outputProgress.progressing){$state='PROGRESSING';$ok=$true}elseif($null -ne $runAgeSeconds -and $runAgeSeconds -gt $workBudget){$state='RUNNING_OVER_BUDGET';$problem='Work started but exceeded media-aware budget without recent output progress.'}else{$state='START_CONFIRMED';$ok=$true}}
elseif($status -and -not $wrapperAlive){$state='START_LOST';$problem='status.json exists but wrapper process is not alive and no result.json exists.'}
elseif($hostResult -and [string]$hostResult.state -eq 'ERROR'){$state='HOST_TASK_ERROR';$problem=[string]$hostResult.error}
else{if($ClaimedAgeSeconds -ge $StartGraceSeconds){$state='CLAIMED_START_DELAY';$problem='Claimed but no Host RUNNING/DONE evidence within start grace window.'}else{$state='CLAIMED_PENDING_START';$problem='Claimed and still inside the short start grace window.'}}
$out=[ordered]@{ok=$ok;action='NOTEBOOKLM_CLAIM_START_BRIDGE_TEST_V2';taskId=$TaskId;state=$state;checkedAt=(Get-Date).ToString('o');hostHealthy=$(if($health){[bool]$health.ok}else{$false});hostVersion=$(if($health){[string]$health.version}else{''});hostAsyncJobs=$(if($health){[bool]$health.asyncJobs}else{$false});problem=$problem}
$out|ConvertTo-Json -Depth 30 -Compress
if($state -in @('DONE','PROGRESSING','START_CONFIRMED','CLAIMED_PENDING_START')){exit 0}else{exit 2}
