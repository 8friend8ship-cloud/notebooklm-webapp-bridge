param()
$ErrorActionPreference='Stop'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Runner=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$RunnerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/HomeDesignAutoResume.ps1'
$WatchdogUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$cb=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri ($RunnerUrl+'?hdcb='+$cb) -OutFile $Runner -TimeoutSec 60
Invoke-WebRequest -UseBasicParsing -Uri ($WatchdogUrl+'?hdcb='+$cb) -OutFile $Watchdog -TimeoutSec 60

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
    <EventTrigger>
      <Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT15S</Delay>
    </EventTrigger>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
      <Repetition><Interval>PT5M</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
    </CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$userSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$Watchdog&quot;</Arguments></Exec></Actions>
</Task>
"@
$tmp=Join-Path $env:TEMP 'HomeDesignAutomation-AutoResume.xml'
$xml|Set-Content -LiteralPath $tmp -Encoding Unicode
& schtasks.exe /Create /TN $taskName /XML $tmp /F | Out-Host
if($LASTEXITCODE -ne 0){throw "schtasks create failed: $LASTEXITCODE"}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

# D99: install an independent per-user logon fallback at bootstrap time too.
# Agent 1.1.30 also repairs this key, but the installer must not depend on the Agent
# having already run successfully. This breaks the Scheduled-Task-only bootstrap
# dependency without adding a new OAuth, service, admin privilege, or browser profile.
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName='HomeDesignAutomationAutoResume'
$runCommand='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Watchdog+'"'
New-Item -Path $runKey -Force|Out-Null
Set-ItemProperty -Path $runKey -Name $runName -Value $runCommand -Type String
$runVerify=(Get-ItemProperty -Path $runKey -Name $runName -ErrorAction Stop).$runName
if([string]$runVerify -ne $runCommand){throw 'HKCU_RUN_FALLBACK_VERIFY_FAILED'}

# Run once immediately so installation/update is also an end-to-end watchdog check.
& schtasks.exe /Run /TN $taskName | Out-Host
Write-Host 'AUTO RESUME WATCHDOG INSTALLED'
Write-Host ('Task: '+$taskName)
Write-Host ('AutoResume: '+$Runner)
Write-Host ('Watchdog: '+$Watchdog)
Write-Host ('User: '+$userName)
Write-Host 'Triggers: Windows logon + resume from sleep + every 5 minutes'
Write-Host ('HKCU Run fallback: '+$runName)
Write-Host 'Chrome login policy: preserve HomeDesignAutomationV7\ChromeUserData; never create a new automation profile during normal recovery.'
