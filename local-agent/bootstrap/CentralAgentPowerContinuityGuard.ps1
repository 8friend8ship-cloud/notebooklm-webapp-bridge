param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='POWER_CONTINUITY_GUARD_V7_REMOTE_AND_WORK_AWAKE_20260910'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'POWER_CONTINUITY_GUARD_LAST.json'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$HeartbeatSeconds=30
$RemoteGraceSeconds=600
$WorkGraceSeconds=300
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
function Get-AllProc{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{return @()}}
function Remote-Present([array]$All){
  try{return (@($All|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and [string]$_.CommandLine-match'(?i)desktop-commander' -and [string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'}).Count-gt0)}catch{return $false}
}
function Expand-Registry($Node){
  $result=@();$stack=New-Object System.Collections.Stack
  foreach($n in @($Node)){$stack.Push($n)}
  while($stack.Count-gt0){$x=$stack.Pop();if($null-eq$x){continue};if($x-is[System.Array]){foreach($a in $x){$stack.Push($a)};continue};$names=@($x.PSObject.Properties.Name);if($names-contains'runId'){$result+=,$x;continue};if($names-contains'value'){foreach($a in @($x.value)){$stack.Push($a)}}}
  return @($result)
}
function Get-WorkEvidence([array]$All){
  $terminal='(?i)^(COMPLETE|COMPLETED|DONE|CLOSED|STALE|SUPERSEDED|ABANDONED|EXPIRED|FAILED|CANCELLED|CANCELED)$'
  $evidence=@()
  try{
    if(Test-Path $Registry){$raw=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;foreach($r in @(Expand-Registry $raw)){try{$state=[string]$r.state;$pid=0;try{$pid=[int]$r.pid}catch{};if($state-and$state-notmatch$terminal-and$pid-gt0-and@($All|Where-Object{[int]$_.ProcessId-eq$pid}).Count-gt0){$evidence+=('REGISTRY:'+[string]$r.runId+':PID='+$pid+':STATE='+$state)}}catch{}}}
  }catch{}
  $activeCmd='(?i)(HomeDesignLocalAgent(?:-flow|-image|-appscript)?\.ps1|NotebookAuditPack\.ps1|HomeDesignRecoveryCoordinator\.ps1|RESUME_LOCAL_AGENT_ONCE\.ps1|Apply-EmbeddedHost129\.ps1)'
  foreach($p in @($All|Where-Object{([string]$_.Name)-match'(?i)^(powershell|pwsh)(?:\.exe)?$' -and [string]$_.CommandLine-match$activeCmd})){try{$evidence+=('PROCESS:'+([string]$p.Name)+':PID='+[string]$p.ProcessId)}catch{}}
  return @($evidence|Select-Object -Unique)
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignPowerContinuityGuardV7')
if(-not$mutex.WaitOne(0,$false)){exit 0}
$ES_CONTINUOUS=[Convert]::ToUInt32('80000000',16)
$ES_SYSTEM_REQUIRED=[uint32]1
$ES_DISPLAY_REQUIRED=[uint32]2
$systemHeld=$false;$displayHeld=$false
$started=(Get-Date).ToString('o')
$remoteLeaseUntil=[datetime]::MinValue;$workLeaseUntil=[datetime]::MinValue
try{
  while($true){
    $now=Get-Date;$power=Power-State;$all=Get-AllProc
    $remote=Remote-Present $all
    $workEvidence=@(Get-WorkEvidence $all);$work=($workEvidence.Count-gt0)
    if($remote){$remoteLeaseUntil=$now.AddSeconds($RemoteGraceSeconds)}
    if($work){$workLeaseUntil=$now.AddSeconds($WorkGraceSeconds)}
    $remoteLease=[bool]($remote-or$now-lt$remoteLeaseUntil)
    $workLease=[bool]($work-or$now-lt$workLeaseUntil)
    $mode=$(if($remoteLease){'REMOTE_ACTIVE'}elseif($workLease){'WORK_ACTIVE'}else{'IDLE_SAFE'})
    [uint32]$callResult=0;$lastError=0
    if($mode-eq'REMOTE_ACTIVE'){
      try{$flags=$ES_CONTINUOUS-bor$ES_SYSTEM_REQUIRED-bor$ES_DISPLAY_REQUIRED;$callResult=[HDPowerGuard]::SetThreadExecutionState($flags);if($callResult-eq0){$lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()};$systemHeld=($callResult-ne0);$displayHeld=$systemHeld}catch{$systemHeld=$false;$displayHeld=$false;$lastError=-1}
    }elseif($mode-eq'WORK_ACTIVE'){
      try{$flags=$ES_CONTINUOUS-bor$ES_SYSTEM_REQUIRED;$callResult=[HDPowerGuard]::SetThreadExecutionState($flags);if($callResult-eq0){$lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()};$systemHeld=($callResult-ne0);$displayHeld=$false}catch{$systemHeld=$false;$displayHeld=$false;$lastError=-1}
    }else{
      try{$callResult=[HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS);if($callResult-eq0){$lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}}catch{$lastError=-1};$systemHeld=$false;$displayHeld=$false
    }
    $remoteRemain=$(if($remoteLeaseUntil-gt$now){[Math]::Max(0,[int][Math]::Ceiling(($remoteLeaseUntil-$now).TotalSeconds))}else{0})
    $workRemain=$(if($workLeaseUntil-gt$now){[Math]::Max(0,[int][Math]::Ceiling(($workLeaseUntil-$now).TotalSeconds))}else{0})
    $expectedOk=$(if($mode-eq'REMOTE_ACTIVE'){$systemHeld-and$displayHeld}elseif($mode-eq'WORK_ACTIVE'){$systemHeld}else{$true})
    $o=[ordered]@{
      ok=[bool]$expectedOk;version=$Version;pid=$PID;startedAt=$started;heartbeatAt=$now.ToString('o');mode=$mode
      acPower=[bool]$power.ac;batteryPercent=$power.batteryPercent
      remoteProcessPresent=$remote;remoteLeaseActive=$remoteLease;remoteGraceSeconds=$RemoteGraceSeconds;remoteLeaseRemainingSeconds=$remoteRemain
      workProcessPresent=$work;workLeaseActive=$workLease;workGraceSeconds=$WorkGraceSeconds;workLeaseRemainingSeconds=$workRemain;workEvidence=@($workEvidence|Select-Object -First 30)
      systemRequiredHeld=$systemHeld;displayRequiredHeld=$displayHeld;screenOffAllowed=[bool](-not$displayHeld);trueSleepAllowed=[bool](-not$systemHeld)
      executionStateCallResult=[uint64]$callResult;lastWin32Error=$lastError
      policy='REMOTE=>SYSTEM+DISPLAY_REQUIRED;WORK=>SYSTEM_REQUIRED_ONLY;IDLE=>RELEASE;TRUE_SLEEP_NEVER_DURING_REMOTE_OR_WORK'
      powercfgChanged=$false;sleepTimeoutChanged=$false;monitorTimeoutChanged=$false;hibernateChanged=$false;lidPolicyChanged=$false;adminRequired=$false
      batteryDrainRisk=[bool](($remoteLease-or$workLease)-and-not[bool]$power.ac);newTrigger=$false;newOAuth=$false
      canonicalInstruction='REMOTE_NO_SLEEP_NO_DISPLAY_OFF;WORK_NO_TRUE_SLEEP;IDLE_RELEASE_TO_WINDOWS_POLICY'
    }
    Save $o
    Start-Sleep -Seconds $HeartbeatSeconds
  }
}finally{try{[void][HDPowerGuard]::SetThreadExecutionState($ES_CONTINUOUS)}catch{};try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
