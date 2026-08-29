param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Runner=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$WatchdogEntry=Join-Path $Root 'WATCHDOG_ENTRY_LATEST.json'
$WatchdogReceipt=Join-Path $Root 'WATCHDOG_LAST.json'
$DirectWatchdogTimeoutSeconds=420
$ScheduledEntryWaitSeconds=15
$ScheduledExecutionLimitMinutes=10
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Api([string]$Path){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-AutoResume-Installer';'Accept'='application/vnd.github+json'} -TimeoutSec 30}
function Blob([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function InstallVerified([string]$RepoPath,[string]$Dest){$r=Api $RepoPath;$tmp=$Dest+'.install';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$expected=([string]$r.sha).ToLowerInvariant();$actual=(Blob $tmp).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SHA_MISMATCH:'+ $RepoPath)};Move-Item $tmp $Dest -Force;return $expected}
function FindCentral{$name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $name),(Join-Path $d.Root ('My Drive\'+$name)),(Join-Path $d.Root ($myDriveKo+'\'+$name)),(Join-Path $d.Root ('Google Drive\'+$name)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveReceipt($o){$json=$o|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath (Join-Path $Root 'AUTO_RESUME_INSTALL_V3.json') -Encoding UTF8;$central=FindCentral;if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir 'AUTO_RESUME_INSTALL_V3.json') -Encoding UTF8}}
function FreshReceipt([string]$Path,[datetime]$Since){try{return ((Test-Path -LiteralPath $Path -PathType Leaf) -and ((Get-Item -LiteralPath $Path).LastWriteTime -ge $Since.AddSeconds(-2)))}catch{return $false}}
function RunDirectWatchdog([int]$TimeoutSeconds=$DirectWatchdogTimeoutSeconds){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Watchdog+'"';$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();if(-not $p.WaitForExit($TimeoutSeconds*1000)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{};return 124};return [int]$p.ExitCode}

$startedAt=Get-Date;$started=$startedAt.ToString('o');$errors=@();$runnerSha='';$watchdogSha='';$taskCreated=$false;$runKeySet=$false;$scheduledRunExit=$null;$immediateExit=$null;$immediateMode='';$triggerContract='LOGON+RESUME+5MIN';$scheduledEntryObserved=$false;$directWatchdogLaunched=$false
try{$runnerSha=InstallVerified 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $Runner}catch{$errors+=('RUNNER_INSTALL:'+ $_.Exception.Message)}
try{$watchdogSha=InstallVerified 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog}catch{$errors+=('WATCHDOG_INSTALL:'+ $_.Exception.Message)}

$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';$runName='HomeDesignAutomationAutoResume';$runCommand='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Watchdog+'"'
try{New-Item -Path $runKey -Force|Out-Null;Set-ItemProperty -Path $runKey -Name $runName -Value $runCommand -Type String;$runVerify=(Get-ItemProperty -Path $runKey -Name $runName -ErrorAction Stop).$runName;if([string]$runVerify-ne$runCommand){throw'HKCU_RUN_FALLBACK_VERIFY_FAILED'};$runKeySet=$true}catch{$errors+=('HKCU_RUN:'+ $_.Exception.Message)}

$taskName='HomeDesignAutomation-AutoResume'
$userSid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$start=(Get-Date).Date.ToString('s')
$xml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>HomeDesign automation watchdog/self-heal. Existing user scope only. Runs at logon, resume from sleep, and every 5 minutes.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$userSid</UserId><Delay>PT10S</Delay></LogonTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription><Delay>PT15S</Delay></EventTrigger>
    <CalendarTrigger><StartBoundary>$start</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay><Repetition><Interval>PT5M</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$userSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>StopExisting</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT10M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$Watchdog&quot;</Arguments></Exec></Actions>
</Task>
"@
$tmpXml=Join-Path $env:TEMP 'HomeDesignAutomation-AutoResume-v3.xml'
try{$xml|Set-Content -LiteralPath $tmpXml -Encoding Unicode;& schtasks.exe /Create /TN $taskName /XML $tmpXml /F | Out-Null;if($LASTEXITCODE-ne0){throw('SCHTASKS_CREATE_'+$LASTEXITCODE)};$taskCreated=$true}catch{$errors+=('SCHEDULED_TASK_CREATE:'+ $_.Exception.Message)}finally{Remove-Item $tmpXml -Force -ErrorAction SilentlyContinue}

$immediateAttemptStart=Get-Date
if($taskCreated){try{& schtasks.exe /Run /TN $taskName | Out-Null;$scheduledRunExit=$LASTEXITCODE;if($scheduledRunExit-ne0){throw('SCHTASKS_RUN_'+$scheduledRunExit)}}catch{$errors+=('SCHEDULED_TASK_RUN:'+ $_.Exception.Message)}}

if($taskCreated -and $scheduledRunExit-eq0){
  $entryDeadline=(Get-Date).AddSeconds($ScheduledEntryWaitSeconds)
  while((Get-Date)-lt$entryDeadline){if(FreshReceipt $WatchdogEntry $immediateAttemptStart){$scheduledEntryObserved=$true;break};Start-Sleep -Seconds 1}
}

if($scheduledEntryObserved){
  $immediateMode='SCHEDULED_WATCHDOG_RECEIPT'
  $doneDeadline=(Get-Date).AddSeconds($DirectWatchdogTimeoutSeconds)
  while((Get-Date)-lt$doneDeadline){
    if(FreshReceipt $WatchdogReceipt $immediateAttemptStart){
      try{$wr=Get-Content -LiteralPath $WatchdogReceipt -Raw -Encoding UTF8|ConvertFrom-Json;$immediateExit=[int]$wr.exitCode;if(-not[bool]$wr.ok -or $immediateExit-ne0){$errors+=('SCHEDULED_WATCHDOG_RECEIPT_EXIT_'+$immediateExit)};break}catch{$errors+=('SCHEDULED_WATCHDOG_RECEIPT_READ:'+ $_.Exception.Message);break}
    }
    Start-Sleep -Seconds 2
  }
  if($immediateExit-eq$null){$immediateExit=124;$errors+='SCHEDULED_WATCHDOG_RECEIPT_TIMEOUT'}
}elseif(Test-Path -LiteralPath $Watchdog -PathType Leaf){
  $directWatchdogLaunched=$true;$immediateMode='DIRECT_WATCHDOG_FALLBACK_ONLY'
  try{$immediateExit=RunDirectWatchdog $DirectWatchdogTimeoutSeconds;if($immediateExit-ne0){$errors+=('DIRECT_WATCHDOG_EXIT_'+$immediateExit)}}catch{$errors+=('DIRECT_WATCHDOG:'+ $_.Exception.Message);$immediateExit=3}
}else{$errors+='WATCHDOG_FILE_MISSING_AFTER_INSTALL'}

$persistenceReady=[bool]($taskCreated-or$runKeySet)
$immediateStarted=[bool]($immediateExit-ne$null)
$immediateVerified=[bool]($immediateExit-eq0)
$ok=[bool]($runnerSha-and$watchdogSha-and$persistenceReady-and$immediateStarted-and$immediateVerified)
$rec=[ordered]@{ok=$ok;action='INSTALL_AUTO_RESUME_V3';installerRevision='V3.3_SINGLE_EXECUTOR_TRIGGER_TIMEOUT_ALIGNED';startedAt=$started;completedAt=(Get-Date).ToString('o');runnerSha=$runnerSha;watchdogSha=$watchdogSha;scheduledTaskCreated=$taskCreated;scheduledRunExit=$scheduledRunExit;scheduledEntryObserved=$scheduledEntryObserved;scheduledEntryWaitSeconds=$ScheduledEntryWaitSeconds;scheduledExecutionLimitMinutes=$ScheduledExecutionLimitMinutes;triggerContract=$triggerContract;triggerLogon=$true;triggerResume=$true;triggerIntervalMinutes=5;hkcuRunRegistered=$runKeySet;persistenceReady=$persistenceReady;immediateMode=$immediateMode;directWatchdogLaunched=$directWatchdogLaunched;directWatchdogTimeoutSeconds=$DirectWatchdogTimeoutSeconds;directWatchdogExit=$immediateExit;immediateExecutionVerified=$immediateVerified;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;errors=$errors}
SaveReceipt $rec
$rec|ConvertTo-Json -Depth 30 -Compress
if($ok){exit 0}else{exit 2}
