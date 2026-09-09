param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='REPAIR_NOTEBOOK_AUTORECOVERY_ONCE_V1_20260909'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Coordinator=Join-Path $Root 'HomeDesignRecoveryCoordinator.ps1'
$Audit=Join-Path $Root 'NotebookAuditPack.ps1'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$Receipt=Join-Path $Root 'NOTEBOOK_AUTORECOVERY_REPAIR_LAST.json'
$TaskName='HomeDesignAutomation-AutoResume'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function Save($o){
  $j=$o|ConvertTo-Json -Depth 50
  $j|Set-Content -LiteralPath $Receipt -Encoding UTF8
  try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'NOTEBOOK_AUTORECOVERY_REPAIR_LAST.json') -Encoding UTF8}}catch{}
}
function GitBlob([byte[]]$b){
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function InstallVerified([string]$RepoPath,[string]$Dest){
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $x=Invoke-RestMethod -Uri $url -Headers @{'User-Agent'='HomeDesign-Notebook-Recovery-Repair';'Accept'='application/vnd.github+json'} -TimeoutSec 30
  $b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$expected=([string]$x.sha).ToLowerInvariant();$actual=(GitBlob $b).ToLowerInvariant()
  if(-not$expected-or$actual-ne$expected){throw ('SHA_MISMATCH:'+ $RepoPath)}
  $tmp=$Dest+'.install';[IO.File]::WriteAllBytes($tmp,$b);Move-Item -LiteralPath $tmp -Destination $Dest -Force
  return $actual
}

$r=[ordered]@{ok=$false;action='REPAIR_EXISTING_AUTORECOVERY_TASK';version=$Version;startedAt=(Get-Date).ToString('o');completedAt='';taskName=$TaskName;taskReused=$true;newPhysicalTask=$false;coordinatorSha='';auditSha='';watchdogSha='';hkcuRun=$false;taskCreated=$false;taskRunExit=$null;errors=@()}
try{
  $r.coordinatorSha=InstallVerified 'local-agent/bootstrap/HomeDesignRecoveryCoordinator.ps1' $Coordinator
  $r.auditSha=InstallVerified 'local-agent/bootstrap/NotebookAuditPack.ps1' $Audit
  $r.watchdogSha=InstallVerified 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog

  $runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';$runName='HomeDesignAutomationAutoResume'
  $runCommand='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Coordinator+'"'
  New-Item -Path $runKey -Force|Out-Null
  Set-ItemProperty -Path $runKey -Name $runName -Value $runCommand -Type String
  $r.hkcuRun=$true

  $userSid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $start=(Get-Date).Date.ToString('s')
  $xml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>HomeDesign notebook audit + existing watchdog + Remote DC self-heal. Reuses existing task name; no duplicate task.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$userSid</UserId><Delay>PT10S</Delay></LogonTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription><Delay>PT15S</Delay></EventTrigger>
    <CalendarTrigger><StartBoundary>$start</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay><Repetition><Interval>PT5M</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$userSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT15M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$Coordinator&quot;</Arguments></Exec></Actions>
</Task>
"@
  $tmpXml=Join-Path $env:TEMP 'HomeDesignAutomation-AutoResume-notebook-audit-v1.xml'
  $xml|Set-Content -LiteralPath $tmpXml -Encoding Unicode
  & schtasks.exe /Create /TN $TaskName /XML $tmpXml /F | Out-Null
  if($LASTEXITCODE-ne0){throw ('SCHTASKS_CREATE_'+$LASTEXITCODE)}
  $r.taskCreated=$true
  Remove-Item $tmpXml -Force -ErrorAction SilentlyContinue
  & schtasks.exe /Run /TN $TaskName | Out-Null
  $r.taskRunExit=$LASTEXITCODE
  if($r.taskRunExit-ne0){throw ('SCHTASKS_RUN_'+$r.taskRunExit)}
  $r.ok=$true
}catch{$r.errors+=($_.Exception.Message);$r.ok=$false}
$r.completedAt=(Get-Date).ToString('o')
Save $r
$r|ConvertTo-Json -Depth 50 -Compress
if($r.ok){exit 0}else{exit 2}
