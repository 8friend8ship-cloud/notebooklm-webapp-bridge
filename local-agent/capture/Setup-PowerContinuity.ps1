param(
  [switch]$Install,
  [switch]$StatusOnly,
  [string]$NightStart='02:00',
  [string]$NightEnd='05:00',
  [int]$IdleDisplayMinutes=30
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'PowerContinuity'
$Watchdog=Join-Path $Root 'PowerContinuity-Watchdog.ps1'
$State=Join-Path $Root 'state.json'
$NightStamp=Join-Path $Root 'night-display-last-date.txt'
$RunKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName='HomeDesign-PowerContinuity-Watchdog'
$UsbSubGroup='2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSelectiveSuspend='48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function ReadState{if(Test-Path -LiteralPath $State){try{return Get-Content -LiteralPath $State -Raw -Encoding UTF8|ConvertFrom-Json}catch{}};return $null}
function WriteState($obj){$obj|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $State -Encoding UTF8}
function Test-NightWindow([string]$StartText,[string]$EndText){
  $now=Get-Date;$start=[datetime]::Today.Add([TimeSpan]::Parse($StartText));$end=[datetime]::Today.Add([TimeSpan]::Parse($EndText))
  if($end -gt $start){return ($now -ge $start -and $now -lt $end)};return ($now -ge $start -or $now -lt $end)
}
function WatchdogProcessInfo{
  $pids=@();try{foreach($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)){if($p.Name -match 'powershell|pwsh' -and $p.CommandLine -and $p.CommandLine -like ('*'+$Watchdog+'*')){$pids+=[int]$p.ProcessId}}}catch{}
  return [ordered]@{exists=($pids.Count -gt 0);pids=$pids}
}
function RunRegistrationInfo{
  $expected='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$Watchdog+'"'
  $actual='';try{$actual=[string](Get-ItemPropertyValue -LiteralPath $RunKey -Name $RunName -ErrorAction Stop)}catch{}
  return [ordered]@{exists=([bool]$actual -and $actual -eq $expected);name=$RunName;path=$RunKey;command=$actual;expected=$expected}
}
function RuntimeInfo{
  $reg=RunRegistrationInfo;$proc=WatchdogProcessInfo;$ok=[bool]($reg.exists -and $proc.exists)
  return [ordered]@{watchdog=[ordered]@{name=$RunName;exists=$ok;registration=$reg;process=$proc;persistence='HKCU_RUN'};night=[ordered]@{name='HomeDesign-Night-Display-Off';exists=$ok;mode='RESIDENT_WATCHER_WINDOW';nightStart=$NightStart;nightEnd=$NightEnd}}
}

if($StatusOnly){
  $runtime=RuntimeInfo;$out=[ordered]@{ok=$true;action='POWER_CONTINUITY_STATUS';watchdog=$runtime.watchdog;night=$runtime.night;state=(ReadState);at=(Get-Date).ToString('o')}
  $out|ConvertTo-Json -Depth 24 -Compress;exit 0
}
if(-not $Install){throw 'INSTALL_OR_STATUS_REQUIRED'}
if($IdleDisplayMinutes -lt 1 -or $IdleDisplayMinutes -gt 1440){throw 'IDLE_DISPLAY_MINUTES_OUT_OF_RANGE'}

# Persistent user-session watcher: no Task Scheduler creation and no elevation requirement.
$template=@'
$ErrorActionPreference='SilentlyContinue'
$NightStart='__NIGHT_START__'
$NightEnd='__NIGHT_END__'
$NightStamp='__NIGHT_STAMP__'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HDPowerResident {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
  [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct SYSTEM_POWER_STATUS {
    public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag;
    public uint BatteryLifeTime; public uint BatteryFullLifeTime;
  }
}
"@
$ES_CONTINUOUS=0x80000000
$ES_SYSTEM_REQUIRED=0x00000001
$HWND_BROADCAST=[IntPtr]0xffff
$WM_SYSCOMMAND=0x0112
$SC_MONITORPOWER=0xF170
function InNightWindow{
  $now=Get-Date;$start=[datetime]::Today.Add([TimeSpan]::Parse($NightStart));$end=[datetime]::Today.Add([TimeSpan]::Parse($NightEnd))
  if($end -gt $start){return ($now -ge $start -and $now -lt $end)};return ($now -ge $start -or $now -lt $end)
}
while($true){
  $s=New-Object HDPowerResident+SYSTEM_POWER_STATUS
  [void][HDPowerResident]::GetSystemPowerStatus([ref]$s)
  if($s.ACLineStatus -eq 1){[void][HDPowerResident]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)}else{[void][HDPowerResident]::SetThreadExecutionState($ES_CONTINUOUS)}
  if(InNightWindow){
    $today=(Get-Date).ToString('yyyy-MM-dd');$last='';try{$last=(Get-Content -LiteralPath $NightStamp -Raw -ErrorAction SilentlyContinue).Trim()}catch{}
    if($last -ne $today){[void][HDPowerResident]::SendMessage($HWND_BROADCAST,$WM_SYSCOMMAND,[IntPtr]$SC_MONITORPOWER,[IntPtr]2);Set-Content -LiteralPath $NightStamp -Value $today -Encoding ASCII}
  }
  Start-Sleep -Seconds 30
}
'@
$watchdogBody=$template.Replace('__NIGHT_START__',$NightStart).Replace('__NIGHT_END__',$NightEnd).Replace('__NIGHT_STAMP__',($NightStamp -replace "'","''"))
Set-Content -LiteralPath $Watchdog -Value $watchdogBody -Encoding UTF8

# Native Windows power rules. Display timeout changes on AC/DC; system sleep/hibernate and USB selective suspend are changed only on AC.
& powercfg.exe /change monitor-timeout-ac $IdleDisplayMinutes|Out-Null;if($LASTEXITCODE -ne 0){throw ('DISPLAY_TIMEOUT_AC_FAILED:'+$LASTEXITCODE)}
& powercfg.exe /change monitor-timeout-dc $IdleDisplayMinutes|Out-Null;if($LASTEXITCODE -ne 0){throw ('DISPLAY_TIMEOUT_DC_FAILED:'+$LASTEXITCODE)}
& powercfg.exe /change standby-timeout-ac 0|Out-Null;if($LASTEXITCODE -ne 0){throw ('STANDBY_TIMEOUT_AC_FAILED:'+$LASTEXITCODE)}
& powercfg.exe /change hibernate-timeout-ac 0|Out-Null;if($LASTEXITCODE -ne 0){throw ('HIBERNATE_TIMEOUT_AC_FAILED:'+$LASTEXITCODE)}
& powercfg.exe /setacvalueindex SCHEME_CURRENT $UsbSubGroup $UsbSelectiveSuspend 0|Out-Null;if($LASTEXITCODE -ne 0){throw ('USB_SELECTIVE_SUSPEND_AC_DISABLE_FAILED:'+$LASTEXITCODE)}
& powercfg.exe /setactive SCHEME_CURRENT|Out-Null;if($LASTEXITCODE -ne 0){throw ('POWER_SCHEME_REACTIVATE_FAILED:'+$LASTEXITCODE)}

# User-level startup persistence; avoids creating a new scheduled task that standard-user automation cannot register.
$runCmd='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$Watchdog+'"'
New-Item -Path $RunKey -Force|Out-Null
Set-ItemProperty -LiteralPath $RunKey -Name $RunName -Value $runCmd -Type String
$existing=WatchdogProcessInfo
if(-not $existing.exists){Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Watchdog`"") -WindowStyle Hidden;Start-Sleep -Milliseconds 1200}

$currentWindowTriggered=$false
if(Test-NightWindow $NightStart $NightEnd){
  $today=(Get-Date).ToString('yyyy-MM-dd');$last='';try{$last=(Get-Content -LiteralPath $NightStamp -Raw -ErrorAction SilentlyContinue).Trim()}catch{}
  if($last -ne $today){
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HDMonitorInstall { [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, IntPtr lParam); }
"@
    [void][HDMonitorInstall]::SendMessage([IntPtr]0xffff,0x0112,[IntPtr]0xF170,[IntPtr]2);Set-Content -LiteralPath $NightStamp -Value $today -Encoding ASCII;$currentWindowTriggered=$true
  }
}

$displayReadback=((& powercfg.exe /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>&1)|Out-String).Trim()
$sleepReadback=((& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1)|Out-String).Trim()
$usbReadback=((& powercfg.exe /query SCHEME_CURRENT $UsbSubGroup $UsbSelectiveSuspend 2>&1)|Out-String).Trim()
$runtime=RuntimeInfo
$stateObj=[ordered]@{
  ok=[bool]($runtime.watchdog.exists -and $runtime.night.exists);mode='AC_SYSTEM_AWAKE_DISPLAY_MAY_OFF';persistenceMode='HKCU_RUN_RESIDENT_WATCHER';scheduledTaskCreationRequired=$false;
  batteryPolicy='DISPLAY_30_MIN_SLEEP_AND_USB_POLICY_NO_OVERRIDE';nightStart=$NightStart;nightEnd=$NightEnd;nightTriggerMode='RESIDENT_WINDOW_ONCE_PER_DAY';
  idleDisplayMinutes=$IdleDisplayMinutes;idleDisplayApplies='AC_AND_BATTERY';acAutomaticSleep='DISABLED';acAutomaticHibernate='DISABLED';acUsbSelectiveSuspend='DISABLED';
  keyboardMouseWake='DISPLAY_WAKE_NATIVE_WINDOWS_NO_SYSTEM_SLEEP';keyboardFreezeGuard='NO_AC_SLEEP_RESUME_PLUS_USB_SELECTIVE_SUSPEND_DISABLED';
  currentNightWindow=(Test-NightWindow $NightStart $NightEnd);currentWindowDisplayOffTriggered=$currentWindowTriggered;
  powercfgDisplayReadback=$displayReadback;powercfgSleepReadback=$sleepReadback;powercfgUsbSelectiveSuspendReadback=$usbReadback;watchdog=$runtime.watchdog;night=$runtime.night;
  note='After 30 minutes idle Windows turns only the display off. AC automatic sleep and hibernate are disabled and the resident user-session watcher holds SYSTEM_REQUIRED on AC. AC USB selective suspend is disabled. Battery system-sleep and USB policies are not overridden. The resident watcher turns the display off once per day inside 02:00-05:00 without forcing it on at 05:00. Keyboard/mouse activity wakes only the display, avoiding a system sleep/resume path.';
  installedAt=(Get-Date).ToString('o')
}
WriteState $stateObj
$stateObj|ConvertTo-Json -Depth 24 -Compress
if($stateObj.ok){exit 0}else{exit 2}
