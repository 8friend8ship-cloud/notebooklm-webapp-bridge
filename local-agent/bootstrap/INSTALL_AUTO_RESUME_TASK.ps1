param()
$ErrorActionPreference='Stop'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Runner=Join-Path $Root 'HomeDesignAutoResume.ps1'
$RunnerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/HomeDesignAutoResume.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
Invoke-WebRequest -UseBasicParsing -Uri ($RunnerUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Runner -TimeoutSec 60

$taskName='HomeDesignAutomation-AutoResume'
$taskCmd="powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Runner`""
$userSid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$userName=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$xml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>HomeDesign automation self-heal on Windows logon and resume from sleep. Reuses persistent ChromeUserData profile; no OAuth reset.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$userSid</UserId><Delay>PT10S</Delay></LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT15S</Delay>
    </EventTrigger>
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
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$Runner&quot;</Arguments></Exec></Actions>
</Task>
"@
$tmp=Join-Path $env:TEMP 'HomeDesignAutomation-AutoResume.xml'
$xml|Set-Content -LiteralPath $tmp -Encoding Unicode
& schtasks.exe /Create /TN $taskName /XML $tmp /F | Out-Host
if($LASTEXITCODE -ne 0){throw "schtasks create failed: $LASTEXITCODE"}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

# Run once immediately so installation is also an end-to-end check.
& schtasks.exe /Run /TN $taskName | Out-Host
Write-Host 'AUTO RESUME INSTALLED'
Write-Host ('Task: '+$taskName)
Write-Host ('Runner: '+$Runner)
Write-Host ('User: '+$userName)
Write-Host 'Triggers: Windows logon + resume from sleep (Power-Troubleshooter Event ID 1)'
Write-Host 'Chrome login policy: preserve HomeDesignAutomationV7\ChromeUserData; never create a new automation profile during normal recovery.'
