param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='POWER_CONTINUITY_GUARD_V5_REMOTE_SYSTEM_AWAKE_SCREEN_OFF_20260909'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$HeartbeatSeconds=30
$RemoteGraceSeconds=600
New-Item -ItemType Directory -Force -Path $Root|Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HDPowerGuard {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern uint SetThreadExecutionState(uint esFlags);
  [StructLayout(LayoutKind.Sequential)]
  public struct SYSTEM_POWER_STATUS {
    public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag;
    public uint BatteryLifeTime; public uint BatteryFullLifeTime;
  }
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);
}
"@ -ErrorAction SilentlyContinue

function Find-Central{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
function Save($o){
  try{$j=$o|ConvertTo-Json -Depth 20;$j|Set-Content -LiteralPath $Receipt -Encoding UTF8;$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'POWER_CONTINUITY_GUARD_LAST.json') -Encoding UTF8}}catch{}
}
function Power-State{
  $o=[ordered]@{ac=$true;batteryPercent=$null}
  try{$s=New-Object HDPowerGuard+SYSTEM_POWER_STATUS;if([HDPowerGuard]::GetSystemPowerStatus([ref]$s)){$o.ac=([int]$s.ACLineStatus-eq1);if([int]$s.BatteryLifePercent-le100){$o.batteryPercent=[int]$s.BatteryLifePercent};return [pscustomobject]$o}}catch{}
  try{$b=Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue|Select-Object -First 1;if($b){$o.ac=([int]$b.BatteryStatus-in 2,6,7,8,9,11);$o.batteryPercent=[int]$b.EstimatedChargeRemaining}}catch{}
  return [pscustomobject]$o
}
function Remote-Present{
  try{return (@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -match '(?i)desktop-commander' -and [string]$_.CommandLine -match '(?i)(?:^|\s)remote(?:\s|$)'}).Count -gt 0)}catch{return $false}
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignPowerContinuityGuardV3')
if(-not $mutex.WaitOne(0,$false)){exit 0}
$ES_CONTINUOUS=[Convert]::ToUInt32('80000000',16)
$ES_SYSTEM_REQUIRED=[uint32]1
$systemHeld=$false
$displayHeld=$false
$started=(Get-Date).ToString('o')
$remoteLeaseUntil=[datetime]::MinValue
try{
  while($true){
    $now=Get-Date
    $power=Power-State
    $remote=Remote-Present
    if($remote){$remoteLeaseUntil=$now.AddSeconds($RemoteGraceSeconds)}
    $leaseActive=[bool]($remote-or$now-lt$remoteLeaseUntil)
    $remaining=0
    if($leaseActive-and$remoteLeaseUntil-gt$now){$remaining=[Math]::Max(0,[int][Math]::Ceiling(($remoteLeaseUntil-$now).TotalSeconds))}
    [uint32]$callResult=0
    $lastError=0
    if($leaseActive){
      try{
        $flags=$ES_CONTINUOUS-bor$ES_SYSTEM_REQUIRED
        $callResult=[HDPowerGuard]::SetThreadExecutionState($flags)
        if($callResult-eq0){$lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}else{$lastError=0}
        $systemHeld=($callResult-ne0)
        $displayHeld=$false
      }catch{$systemHeld=$false;$displayHeld=$false;$lastError=-1}
    }else{
      if($systemHeld){try{[void][HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS)}catch{}}
      $systemHeld=$false;$displayHeld=$false
    }
    $o=[ordered]@{
      ok=[bool]((-not$leaseActive)-or$systemHeld);version=$Version;pid=$PID;startedAt=$started;heartbeatAt=$now.ToString('o')
      acPower=[bool]$power.ac;batteryPercent=$power.batteryPercent;remoteProcessPresent=$remote;remoteLeaseActive=$leaseActive;remoteGraceSeconds=$RemoteGraceSeconds;remoteLeaseRemainingSeconds=$remaining
      systemRequiredHeld=$systemHeld;displayRequiredHeld=$false;screenOffAllowed=$true;executionStateCallResult=[uint64]$callResult;lastWin32Error=$lastError
      mode='REMOTE_DC_ACTIVE_OR_10M_GRACE;PREVENT_SYSTEM_SLEEP;ALLOW_DISPLAY_OFF;NO_GLOBAL_POWERCFG_MUTATION'
      powercfgChanged=$false;sleepTimeoutChanged=$false;monitorTimeoutChanged=$false;hibernateChanged=$false;lidPolicyChanged=$false;adminRequired=$false
      batteryPolicy='REMOTE_SESSION_HAS_PRIORITY;SYSTEM_HELD_EVEN_ON_BATTERY;DISPLAY_ALLOWED_OFF;RELEASE_AFTER_10M_GRACE';batteryDrainRisk=[bool]($leaseActive-and-not[bool]$power.ac)
      newTrigger=$false;newOAuth=$false;ps51UInt32Fix=$true
    }
    Save $o
    Start-Sleep -Seconds $HeartbeatSeconds
  }
}finally{
  try{[void][HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS)}catch{}
  try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()
}
