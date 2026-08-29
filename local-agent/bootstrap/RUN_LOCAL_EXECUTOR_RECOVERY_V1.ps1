param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$CentralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Api([string]$Path){
  $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Local-Executor-Recovery';'Accept'='application/vnd.github+json'} -TimeoutSec 30
}
function Blob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function Install([string]$RepoPath,[string]$Dest){
  $r=Api $RepoPath;$tmp=$Dest+'.recover';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$actual=(Blob $tmp).ToLowerInvariant();$expected=([string]$r.sha).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SHA_MISMATCH '+$RepoPath+' '+$actual+' '+$expected)};Move-Item $tmp $Dest -Force;return $expected
}
function FindCentral{
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $CentralName),(Join-Path $d.Root ('My Drive\'+$CentralName)),(Join-Path $d.Root ($myDriveKo+'\'+$CentralName)),(Join-Path $d.Root ('Google Drive\'+$CentralName)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  };return ''
}
function Save($o){
  $json=$o|ConvertTo-Json -Depth 40;$json|Set-Content -LiteralPath (Join-Path $Root 'LOCAL_EXECUTOR_RECOVERY_V1.json') -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'LOCAL_EXECUTOR_RECOVERY_V1.json') -Encoding UTF8}
}
function BootstrapLoops{try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
function HostHealthy{try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}

$started=(Get-Date).ToString('o');$errors=@();$installed=@{};$taskCreated=$false;$loopStarted=$false;$resumeExit=$null
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1';$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1';$Resume=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1';$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
try{$installed.bootstrap=Install 'local-agent/bootstrap/AgentBootstrap.ps1' $Bootstrap}catch{$errors+=('BOOTSTRAP:'+ $_.Exception.Message)}
try{$installed.autoResume=Install 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $AutoResume}catch{$errors+=('AUTORESUME:'+ $_.Exception.Message)}
try{$installed.resume=Install 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1' $Resume}catch{$errors+=('RESUME:'+ $_.Exception.Message)}
try{$installed.watchdog=Install 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog}catch{$errors+=('WATCHDOG:'+ $_.Exception.Message)}

try{
  $task='HomeDesignAutomation-AutoResume';$tr='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Watchdog+'"';& schtasks.exe /Create /F /SC MINUTE /MO 5 /TN $task /TR $tr | Out-Null;if($LASTEXITCODE-ne0){throw('SCHTASKS_CREATE_'+$LASTEXITCODE)};$taskCreated=$true
  $rk='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';New-Item -Path $rk -Force|Out-Null;Set-ItemProperty -Path $rk -Name 'HomeDesignAutomationAutoResume' -Value $tr -Type String
}catch{$errors+=('PERSISTENCE:'+ $_.Exception.Message)}

try{
  foreach($p in @(BootstrapLoops)){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  Start-Sleep -Seconds 1
  if(Test-Path -LiteralPath $Bootstrap){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 3;$loopStarted=(@(BootstrapLoops).Count-gt0)}
}catch{$errors+=('BOOTSTRAP_LOOP:'+ $_.Exception.Message)}

try{
  if(Test-Path -LiteralPath $Resume){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Resume;$resumeExit=$LASTEXITCODE}else{throw'RESUME_FILE_MISSING'}
}catch{$errors+=('RESUME_RUN:'+ $_.Exception.Message)}

try{& schtasks.exe /Run /TN 'HomeDesignAutomation-AutoResume' | Out-Null}catch{}
Start-Sleep -Seconds 3
$state=$null;try{$sp=Join-Path $Root 'state.json';if(Test-Path $sp){$state=Get-Content $sp -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$ok=[bool]($installed.bootstrap -and $installed.autoResume -and $installed.resume -and $installed.watchdog -and $taskCreated -and (@(BootstrapLoops).Count-gt0))
$rec=[ordered]@{ok=$ok;action='LOCAL_EXECUTOR_RECOVERY_V1';startedAt=$started;completedAt=(Get-Date).ToString('o');installed=$installed;scheduledTaskCreated=$taskCreated;bootstrapLoopPresent=(@(BootstrapLoops).Count-gt0);bootstrapLoopStartedThisRun=$loopStarted;resumeExit=$resumeExit;hostHealthy=(HostHealthy);stateAgentVersion=$(if($state){[string]$state.agentVersion}else{''});stateStatus=$(if($state){[string]$state.status}else{''});normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;generateClicked=$false;creditSpend=$false;errors=$errors};Save $rec;$rec|ConvertTo-Json -Depth 40 -Compress;if($ok){exit 0}else{exit 2}
