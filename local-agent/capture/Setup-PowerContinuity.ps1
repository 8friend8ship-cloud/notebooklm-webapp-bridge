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
$Night=Join-Path $Root 'NightDisplayOff.ps1'
$State=Join-Path $Root 'state.json'
$TaskWatch='HomeDesign-PowerContinuity-Watchdog'
$TaskNight='HomeDesign-Night-Display-Off'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function TaskInfo([string]$Name){
  $raw=& schtasks.exe /Query /TN $Name /FO LIST /V 2>&1
  [ordered]@{name=$Name;exists=($LASTEXITCODE -eq 0);text=(($raw|Out-String).Trim())}
}
function WriteState($obj){$obj|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $State -Encoding UTF8}
function Test-NightWindow([string]$StartText,[string]$EndText){
  $now=Get-Date
  $start=[datetime]::Today.Add([TimeSpan]::Parse($StartText))
  $end=[datetime]::Today.Add([TimeSpan]::Parse($EndText))
  if($end -gt $start){return ($now -ge $start -and $now -lt $end)}
  return ($now -ge $start -or $now -lt $end)
}

if($StatusOnly){
  $out=[ordered]@{ok=$true;action='POWER_CONTINUITY_STATUS';watchdog=(TaskInfo $TaskWatch);night=(TaskInfo $TaskNight);state=$null;at=(Get-Date).ToString('o')}
  if(Test-Path -LiteralPath $State){try{$out.state=Get-Content -LiteralPath $State -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
  $out|ConvertTo-Json -Depth 16 -Compress;exit 0
}

if(-not $Install){throw 'INSTALL_OR_STATUS_REQUIRED'}
if($IdleDisplayMinutes -lt 1 -or $IdleDisplayMinutes -gt 1440){throw 'IDLE_DISPLAY_MINUTES_OUT_OF_RANGE'}

$watchdogBody=@'
$ErrorActionPreference='SilentlyContinue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HDPower {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
  [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);
  [StructLayout(LayoutKind.Sequential)] public struct SYSTEM_POWER_STATUS {
    public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag;
    public uint BatteryLifeTime; public uint BatteryFullLifeTime;
  }
}
"@
$ES_CONTINUOUS=0x80000000
$ES_SYSTEM_REQUIRED=0x00000001
while($true){
  $s=New-Object HDPower+SYSTEM_POWER_STATUS
  [void][HDPower]::GetSystemPowerStatus([ref]$s)
  if($s.ACLineStatus -eq 1){[void][HDPower]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)}
  else{[void][HDPower]::SetThreadExecutionState($ES_CONTINUOUS)}
  Start-Sleep -Seconds 45
}
'@
Set-Content -LiteralPath $Watchdog -Value $watchdogBody -Encoding UTF8

$nightBody=@'
$ErrorActionPreference='SilentlyContinue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HDMonitor {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, IntPtr lParam);
}
"@
$HWND_BROADCAST=[IntPtr]0xffff
$WM_SYSCOMMAND=0x0112
$SC_MONITORPOWER=0xF170
# Display only. The system remains awake because the AC-safe watchdog owns SYSTEM_REQUIRED.
[void][HDMonitor]::SendMessage($HWND_BROADCAST,$WM_SYSCOMMAND,[IntPtr]$SC_MONITORPOWER,[IntPtr]2)
'@
Set-Content -LiteralPath $Night -Value $nightBody -Encoding UTF8

# Native Windows idle rule: after N minutes without keyboard/mouse use, turn only the display off.
# Display timeout applies on AC and battery. Automatic system sleep/hibernate is disabled only on AC
# so automation keeps running while plugged in; the existing battery sleep policy remains untouched.
& powercfg.exe /change monitor-timeout-ac $IdleDisplayMinutes | Out-Null
if($LASTEXITCODE -ne 0){throw ('DISPLAY_TIMEOUT_AC_FAILED:'+ $LASTEXITCODE)}
& powercfg.exe /change monitor-timeout-dc $IdleDisplayMinutes | Out-Null
if($LASTEXITCODE -ne 0){throw ('DISPLAY_TIMEOUT_DC_FAILED:'+ $LASTEXITCODE)}
& powercfg.exe /change standby-timeout-ac 0 | Out-Null
if($LASTEXITCODE -ne 0){throw ('STANDBY_TIMEOUT_AC_FAILED:'+ $LASTEXITCODE)}
& powercfg.exe /change hibernate-timeout-ac 0 | Out-Null
if($LASTEXITCODE -ne 0){throw ('HIBERNATE_TIMEOUT_AC_FAILED:'+ $LASTEXITCODE)}

# Current-user logon watchdog. It is intentionally AC-safe: battery mode releases the sleep block.
$watchCmd='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$Watchdog+'"'
& schtasks.exe /Create /F /SC ONLOGON /TN $TaskWatch /TR $watchCmd | Out-Null
if($LASTEXITCODE -ne 0){throw ('WATCHDOG_TASK_CREATE_FAILED:'+ $LASTEXITCODE)}

# Daily display-off at NightStart. Keyboard/mouse immediately wakes the display because Windows itself is not sleeping.
$nightCmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$Night+'"'
& schtasks.exe /Create /F /SC DAILY /ST $NightStart /TN $TaskNight /TR $nightCmd /IT | Out-Null
if($LASTEXITCODE -ne 0){
  # Some systems reject /IT from a background host. Fall back to non-interactive registration; keep evidence explicit.
  & schtasks.exe /Create /F /SC DAILY /ST $NightStart /TN $TaskNight /TR $nightCmd | Out-Null
  if($LASTEXITCODE -ne 0){throw ('NIGHT_TASK_CREATE_FAILED:'+ $LASTEXITCODE)}
}

# Start watchdog now without waiting for next logon.
& schtasks.exe /Run /TN $TaskWatch | Out-Null
Start-Sleep -Milliseconds 800

# If installation happens after NightStart but before NightEnd, run display-off once now instead of waiting until tomorrow.
$currentWindowTriggered=$false
if(Test-NightWindow $NightStart $NightEnd){
  & schtasks.exe /Run /TN $TaskNight | Out-Null
  if($LASTEXITCODE -eq 0){$currentWindowTriggered=$true}
  Start-Sleep -Milliseconds 400
}

$displayReadback=((& powercfg.exe /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>&1)|Out-String).Trim()
$sleepReadback=((& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1)|Out-String).Trim()
$watch=TaskInfo $TaskWatch;$nightInfo=TaskInfo $TaskNight
$stateObj=[ordered]@{
  ok=$true;mode='AC_SYSTEM_AWAKE_DISPLAY_MAY_OFF';batteryPolicy='DISPLAY_30_MIN_SLEEP_POLICY_NO_OVERRIDE';nightStart=$NightStart;nightEnd=$NightEnd;
  idleDisplayMinutes=$IdleDisplayMinutes;idleDisplayApplies='AC_AND_BATTERY';acAutomaticSleep='DISABLED';acAutomaticHibernate='DISABLED';
  keyboardMouseWake='DISPLAY_WAKE_NATIVE_WINDOWS_NO_SYSTEM_SLEEP';currentNightWindow=(Test-NightWindow $NightStart $NightEnd);currentWindowDisplayOffTriggered=$currentWindowTriggered;
  powercfgDisplayReadback=$displayReadback;powercfgSleepReadback=$sleepReadback;watchdog=$watch;night=$nightInfo;
  note='After the configured idle period Windows turns only the display off. While on AC, automatic sleep and hibernate are disabled so NotebookLM/download/Drive/triggers keep running. Battery system-sleep policy is not overridden. NightStart still forces a display-off run; NightEnd does not force the screen on. Normal keyboard/mouse activity wakes the display.';
  installedAt=(Get-Date).ToString('o')
}
WriteState $stateObj
$stateObj|ConvertTo-Json -Depth 16 -Compress
exit 0
