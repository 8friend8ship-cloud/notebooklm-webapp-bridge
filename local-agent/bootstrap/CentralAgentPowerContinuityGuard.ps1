param([switch]$SelfTest)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='POWER_CONTINUITY_GUARD_V10_MODERN_STANDBY_EXECUTION_REQUIRED_20260912'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$HeartbeatSeconds=30
$RemoteGraceSeconds=600
New-Item -ItemType Directory -Force -Path $Root|Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HDPowerGuardV10 {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern uint SetThreadExecutionState(uint esFlags);
  [StructLayout(LayoutKind.Sequential)]
  public struct SYSTEM_POWER_STATUS {
    public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag;
    public uint BatteryLifeTime; public uint BatteryFullLifeTime;
  }
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct REASON_CONTEXT {
    public uint Version;
    public uint Flags;
    public IntPtr SimpleReasonString;
  }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr PowerCreateRequest(ref REASON_CONTEXT Context);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool PowerSetRequest(IntPtr PowerRequest, int RequestType);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool PowerClearRequest(IntPtr PowerRequest, int RequestType);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool CloseHandle(IntPtr hObject);
}
"@ -ErrorAction Stop

function Find-Central{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
function Write-AtomicUtf8([string]$Path,[string]$Text){
  $tmp=$Path+'.tmp.'+$PID+'.'+[guid]::NewGuid().ToString('N')
  try{[IO.File]::WriteAllText($tmp,$Text,(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $tmp -Destination $Path -Force}
  catch{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue;throw}
}
function Save($o){
  try{$j=$o|ConvertTo-Json -Depth 30;Write-AtomicUtf8 $Receipt $j;$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;Write-AtomicUtf8 (Join-Path $d 'POWER_CONTINUITY_GUARD_LAST.json') $j}}catch{}
}
function Power-State{
  $o=[ordered]@{ac=$true;batteryPercent=$null}
  try{$s=New-Object HDPowerGuardV10+SYSTEM_POWER_STATUS;if([HDPowerGuardV10]::GetSystemPowerStatus([ref]$s)){$o.ac=([int]$s.ACLineStatus-eq1);if([int]$s.BatteryLifePercent-le100){$o.batteryPercent=[int]$s.BatteryLifePercent};return [pscustomobject]$o}}catch{}
  try{$b=Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue|Select-Object -First 1;if($b){$o.ac=([int]$b.BatteryStatus-in 2,6,7,8,9,11);$o.batteryPercent=[int]$b.EstimatedChargeRemaining}}catch{}
  return [pscustomobject]$o
}
function Remote-Present{
  try{return (@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and [string]$_.CommandLine-match'(?i)desktop-commander' -and [string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'}).Count-gt0)}catch{return $false}
}
function New-ExplicitPowerRequest{
  $o=[ordered]@{handle=[IntPtr]::Zero;created=$false;systemHeld=$false;executionHeld=$false;createError=0;systemError=0;executionError=0}
  $reasonPtr=[IntPtr]::Zero
  try{
    $reasonPtr=[Runtime.InteropServices.Marshal]::StringToHGlobalUni('HomeDesign central automation continuity; display may turn off')
    $ctx=New-Object HDPowerGuardV10+REASON_CONTEXT;$ctx.Version=0;$ctx.Flags=1;$ctx.SimpleReasonString=$reasonPtr
    $h=[HDPowerGuardV10]::PowerCreateRequest([ref]$ctx);$o.handle=$h
    if($h-eq[IntPtr]::Zero-or$h-eq([IntPtr](-1))){$o.createError=[Runtime.InteropServices.Marshal]::GetLastWin32Error();return [pscustomobject]$o}
    $o.created=$true
    $o.systemHeld=[HDPowerGuardV10]::PowerSetRequest($h,1);if(-not$o.systemHeld){$o.systemError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
    $o.executionHeld=[HDPowerGuardV10]::PowerSetRequest($h,3);if(-not$o.executionHeld){$o.executionError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
    return [pscustomobject]$o
  }finally{if($reasonPtr-ne[IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeHGlobal($reasonPtr)}}
}
function Clear-ExplicitPowerRequest($pr){
  if(-not$pr-or-not$pr.created){return}
  try{if($pr.executionHeld){[void][HDPowerGuardV10]::PowerClearRequest($pr.handle,3)}}catch{}
  try{if($pr.systemHeld){[void][HDPowerGuardV10]::PowerClearRequest($pr.handle,1)}}catch{}
  try{[void][HDPowerGuardV10]::CloseHandle($pr.handle)}catch{}
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignPowerContinuityGuardV10')
if(-not$mutex.WaitOne(0,$false)){exit 0}
$ES_CONTINUOUS=[Convert]::ToUInt32('80000000',16)
$ES_SYSTEM_REQUIRED=[uint32]1
$started=(Get-Date).ToString('o')
$remoteLeaseUntil=[datetime]::MinValue
$pr=$null
try{
  $pr=New-ExplicitPowerRequest
  do{
    $now=Get-Date;$power=Power-State;$remote=Remote-Present
    if($remote){$remoteLeaseUntil=$now.AddSeconds($RemoteGraceSeconds)}
    $remoteLease=[bool]($remote-or$now-lt$remoteLeaseUntil)
    [uint32]$flags=$ES_CONTINUOUS-bor$ES_SYSTEM_REQUIRED
    [uint32]$callResult=0;$lastError=0
    try{$callResult=[HDPowerGuardV10]::SetThreadExecutionState($flags);if($callResult-eq0){$lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}}catch{$lastError=-1}
    $threadSystemHeld=($callResult-ne0);$explicitSystemHeld=[bool]($pr-and$pr.created-and$pr.systemHeld);$executionHeld=[bool]($pr-and$pr.created-and$pr.executionHeld)
    $systemHeld=[bool]($threadSystemHeld-and$explicitSystemHeld);$displayHeld=$false
    $remoteRemain=$(if($remoteLeaseUntil-gt$now){[Math]::Max(0,[int][Math]::Ceiling(($remoteLeaseUntil-$now).TotalSeconds))}else{0})
    $o=[ordered]@{
      ok=[bool]($systemHeld-and$executionHeld);version=$Version;pid=$PID;startedAt=$started;heartbeatAt=$now.ToString('o');selfTest=[bool]$SelfTest
      acPower=[bool]$power.ac;batteryPercent=$power.batteryPercent;remoteProcessPresent=$remote;remoteLeaseActive=$remoteLease;remoteGraceSeconds=$RemoteGraceSeconds;remoteLeaseRemainingSeconds=$remoteRemain
      threadSystemRequiredHeld=$threadSystemHeld;explicitPowerRequestCreated=[bool]($pr-and$pr.created);powerRequestSystemHeld=$explicitSystemHeld;powerRequestExecutionHeld=$executionHeld
      systemRequiredHeld=$systemHeld;executionRequiredHeld=$executionHeld;displayRequiredHeld=$false;screenOffAllowed=$true;trueSleepAllowed=$false
      executionStateCallResult=[uint64]$callResult;lastWin32Error=$lastError;powerRequestCreateError=$(if($pr){[int]$pr.createError}else{-1});powerRequestSystemError=$(if($pr){[int]$pr.systemError}else{-1});powerRequestExecutionError=$(if($pr){[int]$pr.executionError}else{-1})
      mode='FAILSAFE_NO_TRUE_SLEEP+POWER_REQUEST_SYSTEM+EXECUTION+DISPLAY_MAY_OFF_ALWAYS'
      policy='CENTRAL_GUARD_RUNNING=>SYSTEM_AND_PROCESS_EXECUTION_REQUIRED;DISPLAY_MAY_OFF_ALWAYS;REMOTE_LEASE_DIAGNOSTIC_ONLY'
      powercfgChanged=$false;sleepTimeoutChanged=$false;monitorTimeoutChanged=$false;hibernateChanged=$false;lidPolicyChanged=$false;adminRequired=$false
      batteryDrainRisk=[bool](-not[bool]$power.ac);newTrigger=$false;newOAuth=$false
      canonicalInstruction='NIGHT_DISPLAY_ONLY_V1: KEEP_SYSTEM_NETWORK_AUTOMATION_RUNNING;ALLOW_DISPLAY_OFF_ALWAYS'
    }
    Save $o
    if($SelfTest){if($o.ok){exit 0}else{exit 4}}
    Start-Sleep -Seconds $HeartbeatSeconds
  }while($true)
}finally{Clear-ExplicitPowerRequest $pr;try{[void][HDPowerGuardV10]::SetThreadExecutionState($ES_CONTINUOUS)}catch{};try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
