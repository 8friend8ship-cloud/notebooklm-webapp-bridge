param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='POWER_CONTINUITY_GUARD_V3_PS51_UINT32_FIX_20260909'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$HeartbeatSeconds=30
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
function On-AC{
  try{$s=New-Object HDPowerGuard+SYSTEM_POWER_STATUS;if([HDPowerGuard]::GetSystemPowerStatus([ref]$s)){return ([int]$s.ACLineStatus -eq 1)}}catch{}
  try{return ((Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue|Select-Object -First 1).BatteryStatus -in 2,6,7,8,9,11)}catch{return $true}
}
function Remote-Present{
  try{return (@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -match '(?i)desktop-commander' -and [string]$_.CommandLine -match '(?i)(?:^|\s)remote(?:\s|$)'}).Count -gt 0)}catch{return $false}
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignPowerContinuityGuardV2')
if(-not $mutex.WaitOne(0,$false)){exit 0}
# PowerShell 5.1 parses 0x80000000 as signed Int32; Convert.ToUInt32 avoids InvalidCastIConvertible.
$ES_CONTINUOUS=[Convert]::ToUInt32('80000000',16)
$ES_SYSTEM_REQUIRED=[uint32]1
$held=$false
$started=(Get-Date).ToString('o')
try{
  while($true){
    $ac=On-AC
    $remote=Remote-Present
    $shouldHold=[bool]($ac -and $remote)
    [uint32]$callResult=0
    $lastError=0
    if($shouldHold){
      try{
        $flags=$ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
        $callResult=[HDPowerGuard]::SetThreadExecutionState($flags)
        $lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $held=($callResult -ne 0)
      }catch{$held=$false;$lastError=-1}
    }else{
      if($held){try{[void][HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS)}catch{}}
      $held=$false
    }
    $o=[ordered]@{
      ok=$true;version=$Version;pid=$PID;startedAt=$started;heartbeatAt=(Get-Date).ToString('o');acPower=$ac;remoteProcessPresent=$remote
      systemRequiredHeld=$held;displayRequiredHeld=$false;executionStateCallResult=[uint64]$callResult;lastWin32Error=$lastError
      mode='AC_ONLY_WHILE_REMOTE_DC_PRESENT;ALLOW_DISPLAY_OFF;PREVENT_MODERN_STANDBY_DURING_REMOTE_AUTOMATION'
      powercfgChanged=$false;sleepTimeoutChanged=$false;hibernateChanged=$false;lidPolicyChanged=$false;adminRequired=$false
      batteryPolicy='ON_DC_CLEAR_ES_SYSTEM_REQUIRED';newTrigger=$false;newOAuth=$false;ps51UInt32Fix=$true
    }
    Save $o
    Start-Sleep -Seconds $HeartbeatSeconds
  }
}finally{
  try{[void][HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS)}catch{}
  try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()
}
