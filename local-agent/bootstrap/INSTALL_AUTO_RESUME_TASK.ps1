param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Runner=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Api([string]$Path){
  Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-AutoResume-Installer';'Accept'='application/vnd.github+json'} -TimeoutSec 30
}
function Blob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function InstallVerified([string]$RepoPath,[string]$Dest){
  $r=Api $RepoPath;$tmp=$Dest+'.install';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$expected=([string]$r.sha).ToLowerInvariant();$actual=(Blob $tmp).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SHA_MISMATCH:'+ $RepoPath+':'+$actual+':'+$expected)};Move-Item $tmp $Dest -Force;return $expected
}
function FindCentral{
  $name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $name),(Join-Path $d.Root ('My Drive\'+$name)),(Join-Path $d.Root ($myDriveKo+'\'+$name)),(Join-Path $d.Root ('Google Drive\'+$name)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''
}
function SaveReceipt($o){
  $json=$o|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath (Join-Path $Root 'AUTO_RESUME_INSTALL_V2.json') -Encoding UTF8;$central=FindCentral;if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir 'AUTO_RESUME_INSTALL_V2.json') -Encoding UTF8}
}

$started=(Get-Date).ToString('o');$errors=@();$runnerSha='';$watchdogSha='';$taskCreated=$false;$runKeySet=$false;$immediateMode='';$immediateExit=$null
try{$runnerSha=InstallVerified 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $Runner}catch{$errors+=('RUNNER_INSTALL:'+ $_.Exception.Message)}
try{$watchdogSha=InstallVerified 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog}catch{$errors+=('WATCHDOG_INSTALL:'+ $_.Exception.Message)}

$taskName='HomeDesignAutomation-AutoResume'
$userSid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$userName=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$start=(Get-Date).Date.ToString('s')
$xml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>HomeDesign automation watchdog/self-heal. Reuses persistent ChromeUserData profile; no OAuth reset. Runs at logon, resume from sleep, and every 5 minutes while the user session is active.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$userSid</UserId><Delay>PT10S</Delay></LogonTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription><Delay>PT15S</Delay></EventTrigger>
    <CalendarTrigger><StartBoundary>$start</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay><Repetition><Interval>PT5M</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$userSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>StopExisting</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT5M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$Watchdog&quot;</Arguments></Exec></Actions>
</Task>
"@
$tmp=Join-Path $env:TEMP 'HomeDesignAutomation-AutoResume.xml'
try{
  $xml|Set-Content -LiteralPath $tmp -Encoding Unicode
  & schtasks.exe /Create /TN $taskName /XML $tmp /F | Out-Null
  if($LASTEXITCODE-ne0){throw('SCHTASKS_CREATE_'+$LASTEXITCODE)}
  $taskCreated=$true
}catch{$errors+=('SCHEDULED_TASK:'+ $_.Exception.Message)}finally{Remove-Item $tmp -Force -ErrorAction SilentlyContinue}

$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';$runName='HomeDesignAutomationAutoResume';$runCommand='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Watchdog+'"'
try{
  New-Item -Path $runKey -Force|Out-Null
  Set-ItemProperty -Path $runKey -Name $runName -Value $runCommand -Type String
  $runVerify=(Get-ItemProperty -Path $runKey -Name $runName -ErrorAction Stop).$runName
  if([string]$runVerify-ne$runCommand){throw'HKCU_RUN_FALLBACK_VERIFY_FAILED'}
  $runKeySet=$true
}catch{$errors+=('HKCU_RUN:'+ $_.Exception.Message)}

if(Test-Path -LiteralPath $Watchdog -PathType Leaf){
  if($taskCreated){
    try{& schtasks.exe /Run /TN $taskName | Out-Null;$immediateMode='SCHEDULED_TASK';$immediateExit=0}catch{$errors+=('SCHEDULED_TASK_RUN:'+ $_.Exception.Message)}
  } else {
    try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Watchdog;$immediateExit=$LASTEXITCODE;$immediateMode='DIRECT_WATCHDOG_FALLBACK'}catch{$errors+=('DIRECT_WATCHDOG:'+ $_.Exception.Message)}
  }
}

$persistenceReady=[bool]($taskCreated-or$runKeySet)
$ok=[bool]($runnerSha-and$watchdogSha-and$persistenceReady)
$rec=[ordered]@{ok=$ok;action='INSTALL_AUTO_RESUME_V2';startedAt=$started;completedAt=(Get-Date).ToString('o');runnerSha=$runnerSha;watchdogSha=$watchdogSha;scheduledTaskCreated=$taskCreated;hkcuRunRegistered=$runKeySet;persistenceReady=$persistenceReady;immediateMode=$immediateMode;immediateExit=$immediateExit;user=$userName;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;errors=$errors}
SaveReceipt $rec
$rec|ConvertTo-Json -Depth 30 -Compress
if($ok){exit 0}else{exit 2}
