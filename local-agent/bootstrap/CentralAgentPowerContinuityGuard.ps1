param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='POWER_CONTINUITY_GUARD_V8_FAILSAFE_NO_TRUE_SLEEP_20260910'
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
  try{$j=$o|ConvertTo-Json -Depth 30;$j|Set-Content -LiteralPath $Receipt -Encoding UTF8;$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'POWER_CONTINUITY_GUARD_LAST.json') -Encoding UTF8}}catch{}
}
function Power-State{
  $o=[ordered]@{ac=$true;batteryPercent=$null}
  try{$s=New-Object HDPowerGuard+SYSTEM_POWER_STATUS;if([HDPowerGuard]::GetSystemPowerStatus([ref]$s)){$o.ac=([int]$s.ACLineStatus-eq1);if([int]$s.BatteryLifePercent-le100){$o.batteryPercent=[int]$s.BatteryLifePercent};return [pscustomobject]$o}}catch{}
  try{$b=Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue|Select-Object -First 1;if($b){$o.ac=([int]$b.BatteryStatus-in 2,6,7,8,9,11);$o.batteryPercent=[int]$b.EstimatedChargeRemaining}}catch{}
  return [pscustomobject]$o
}
function Remote-Present{
  try{return (@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and [string]$_.CommandLine-match'(?i)desktop-commander' -and [string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'}).Count-gt0)}catch{return $false}
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignPowerContinuityGuardV8')
if(-not$mutex.WaitOne(0,$false)){exit 0}
$ES_CONTINUOUS=[Convert]::ToUInt32('80000000',16)
$ES_SYSTEM_REQUIRED=[uint32]1
$ES_DISPLAY_REQUIRED=[uint32]2
$started=(Get-Date).ToString('o')
$remoteLeaseUntil=[datetime]::MinValue
try{
  while($true){
    $now=Get-Date;$power=Power-State;$remote=Remote-Present
    if($remote){$remoteLeaseUntil=$now.AddSeconds($RemoteGraceSeconds)}
    $remoteLease=[bool]($remote-or$now-lt$remoteLeaseUntil)
    [uint32]$flags=$ES_CONTINUOUS-bor$ES_SYSTEM_REQUIRED
    if($remoteLease){$flags=$flags-bor$ES_DISPLAY_REQUIRED}
    [uint32]$callResult=0;$lastError=0
    try{$callResult=[HDPowerGuard]::SetThreadExecutionState($flags);if($callResult-eq0){$lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}}catch{$lastError=-1}
    $systemHeld=($callResult-ne0);$displayHeld=[bool]($remoteLease-and$systemHeld)
    $remoteRemain=$(if($remoteLeaseUntil-gt$now){[Math]::Max(0,[int][Math]::Ceiling(($remoteLeaseUntil-$now).TotalSeconds))}else{0})
    $o=[ordered]@{
      ok=[bool]($systemHeld-and((-not$remoteLease)-or$displayHeld));version=$Version;pid=$PID;startedAt=$started;heartbeatAt=$now.ToString('o')
      acPower=[bool]$power.ac;batteryPercent=$power.batteryPercent;remoteProcessPresent=$remote;remoteLeaseActive=$remoteLease;remoteGraceSeconds=$RemoteGraceSeconds;remoteLeaseRemainingSeconds=$remoteRemain
      systemRequiredHeld=$systemHeld;displayRequiredHeld=$displayHeld;screenOffAllowed=[bool](-not$displayHeld);trueSleepAllowed=$false
      executionStateCallResult=[uint64]$callResult;lastWin32Error=$lastError
      mode=$(if($remoteLease){'FAILSAFE_NO_TRUE_SLEEP+REMOTE_DISPLAY_AWAKE'}else{'FAILSAFE_NO_TRUE_SLEEP+DISPLAY_MAY_OFF'})
      policy='CENTRAL_GUARD_RUNNING=>TRUE_SLEEP_DISABLED_ALWAYS;REMOTE=>DISPLAY_OFF_DISABLED;NON_REMOTE=>DISPLAY_MAY_OFF'
      powercfgChanged=$false;sleepTimeoutChanged=$false;monitorTimeoutChanged=$false;hibernateChanged=$false;lidPolicyChanged=$false;adminRequired=$false
      batteryDrainRisk=[bool](-not[bool]$power.ac);newTrigger=$false;newOAuth=$false
      canonicalInstruction='REPEATED_REMOTE_OFFLINE_FAILSAFE: NEVER_TRUE_SLEEP_WHILE_CENTRAL_GUARD_RUNNING'
    }
    Save $o
    Start-Sleep -Seconds $HeartbeatSeconds
  }
}finally{try{[void][HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS)}catch{};try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
