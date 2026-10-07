param(
  [switch]$Apply,
  [ValidateSet('CHECK','CAPTURE','RESTORE')]
  [string]$Mode='CHECK',
  [string]$OwnerRunId=''
)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='OPENAI_WEB_SYNC_GUARD_V3_ACTIVE_CHAT_CONTINUITY_20261007'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StatePath=Join-Path $Root 'OPENAI_WEB_SYNC_GUARD_STATE.json'
$ReceiptPath=Join-Path $Root 'OPENAI_WEB_SYNC_GUARD_LAST.json'
$ContinuityPath=Join-Path $env:USERPROFILE 'HomeDesignAutomationV7\\CentralRemotePack\\OPENAI_CHAT_CONTINUITY_STATE_V1.json'
$CooldownSeconds=900
$MinIdleSeconds=120
New-Item -ItemType Directory -Force -Path $Root|Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class OaiSyncWin {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
 [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
 [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
}
'@ -ErrorAction SilentlyContinue

function Save-Json([string]$Path,$Obj){try{$Obj|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function Read-ContinuityState{
  try{if(Test-Path -LiteralPath $ContinuityPath){return Get-Content -LiteralPath $ContinuityPath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
  return $null
}
function Get-IdleSeconds{
  try{
    $x=New-Object OaiSyncWin+LASTINPUTINFO
    $x.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($x)
    if([OaiSyncWin]::GetLastInputInfo([ref]$x)){
      return [math]::Max(0,[int](([Environment]::TickCount64-[int64]$x.dwTime)/1000))
    }
  }catch{}
  return 0
}
function Test-Port([string]$HostName,[int]$Port){
  try{
    $c=New-Object Net.Sockets.TcpClient
    $ar=$c.BeginConnect($HostName,$Port,$null,$null)
    if(-not$ar.AsyncWaitHandle.WaitOne(3000)){try{$c.Close()}catch{};return $false}
    $c.EndConnect($ar);$c.Close();return $true
  }catch{return $false}
}
function Get-ChatWindows{
  $rows=@();$root=$null
  try{$root=[System.Windows.Automation.AutomationElement]::RootElement}catch{}
  if(-not$root){return @()}
  try{$tops=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)}catch{return @()}
  $fg=[OaiSyncWin]::GetForegroundWindow().ToInt64()
  foreach($e in @($tops)){
    try{
      $c=$e.Current;$procId=[int]$c.ProcessId;$hwnd=[int64]$c.NativeWindowHandle;$title=[string]$c.Name
      if($procId-le0-or$hwnd-le0-or[string]::IsNullOrWhiteSpace($title)){continue}
      $p=Get-Process -Id $procId -ErrorAction Stop
      $name=[string]$p.ProcessName
      # Edge is explicitly excluded from the canonical OpenAI interactive lane.
      if($name-notmatch'(?i)^(chrome|chatgpt)$'){continue}
      if($title-notmatch'(?i)(ChatGPT|OpenAI)'){continue}
      $rows+=[pscustomobject]@{
        pid=$procId;hwnd=$hwnd;process=$name;title=$title;
        foreground=($fg-eq$hwnd);
        canonicalRank=$(if($name-match'(?i)^chatgpt$'){0}else{1})
      }
    }catch{}
  }
  return @($rows)
}
function Select-PreferredChatWindow($wins,$previous){
  if(-not$wins-or$wins.Count-eq0){return $null}
  $fg=@($wins|Where-Object{$_.foreground}|Sort-Object canonicalRank|Select-Object -First 1)
  if($fg){return $fg}
  if($previous -and $previous.hwnd){
    $same=@($wins|Where-Object{[int64]$_.hwnd-eq[int64]$previous.hwnd}|Select-Object -First 1)
    if($same){return $same}
  }
  $native=@($wins|Where-Object{$_.process-match'(?i)^chatgpt$'}|Select-Object -First 1)
  if($native){return $native}
  $chrome=@($wins|Where-Object{$_.process-match'(?i)^chrome$'}|Select-Object -First 1)
  if($chrome){return $chrome}
  return $null
}

$now=Get-Date
$prev=$null
try{if(Test-Path $StatePath){$prev=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$previousChat=$(if($prev-and$prev.activeUserChat){$prev.activeUserChat}else{$null})
$lastRefresh=$null
try{if($prev.lastRefreshAt){$lastRefresh=[datetimeoffset]::Parse([string]$prev.lastRefreshAt)}}catch{}
$elapsed=$(if($lastRefresh){([datetimeoffset]::Now-$lastRefresh).TotalSeconds}else{999999})
$wsReachable=Test-Port 'ws.chatgpt.com' 443
$webReachable=Test-Port 'chatgpt.com' 443
$wins=@(Get-ChatWindows)
$idle=Get-IdleSeconds
$preferred=Select-PreferredChatWindow $wins $previousChat
$captureOk=$false
$restoreAttempted=$false
$restoreOk=$false
$guardError=''
$activeUserChat=$previousChat
$continuity=Read-ContinuityState

if($Mode-eq'CAPTURE'){
  if($preferred){
    $activeUserChat=[ordered]@{
      pid=[int]$preferred.pid
      hwnd=[int64]$preferred.hwnd
      process=[string]$preferred.process
      title=[string]$preferred.title
      conversationIdentity=([string]$preferred.process+'|PID='+[string]$preferred.pid+'|HWND='+[string]$preferred.hwnd+'|TITLE='+[string]$preferred.title)
      url=''
      continuityStateRef=$ContinuityPath
      lastReceivedInstructionSnapshotRef=$(if($continuity){$ContinuityPath+'#last_received_user_instruction_summary'}else{''})
      lastGood=$(if($continuity){@($continuity.last_good)}else{@()})
      firstUnfinished=$(if($continuity){[string]$continuity.first_unfinished}else{''})
      continuityStatus=$(if($continuity){[string]$continuity.status}else{'UNKNOWN'})
      ownerRunId=$OwnerRunId
      capturedAt=(Get-Date).ToString('o')
      source='OPENAI_PACK_TO_OPENAI_MANAGEMENT_PACK'
    }
    $captureOk=$true
  }else{
    $guardError='NO_CANONICAL_CHATGPT_WINDOW_TO_CAPTURE'
  }
}
elseif($Mode-eq'RESTORE'){
  $restoreAttempted=$true
  $target=$null
  if($activeUserChat-and$activeUserChat.hwnd){
    $target=@($wins|Where-Object{
      [int64]$_.hwnd-eq[int64]$activeUserChat.hwnd -and
      [string]$_.process-eq[string]$activeUserChat.process -and
      [string]$_.title-eq[string]$activeUserChat.title
    }|Select-Object -First 1)
  }
  if($target){
    try{
      $restoreOk=[OaiSyncWin]::SetForegroundWindow([IntPtr][int64]$target.hwnd)
      Start-Sleep -Milliseconds 250
      $restoreOk=$restoreOk-and([OaiSyncWin]::GetForegroundWindow().ToInt64()-eq[int64]$target.hwnd)
      if(-not$restoreOk){$guardError='SET_FOREGROUND_DID_NOT_STICK'}
    }catch{$guardError=$_.Exception.Message}
  }else{
    $guardError='CAPTURED_EXACT_CHAT_WINDOW_NOT_FOUND'
  }
}

$eligible=[bool](
  $Mode-eq'CHECK' -and $Apply -and $preferred -and
  $wsReachable-and$webReachable-and$elapsed-ge$CooldownSeconds-and$idle-ge$MinIdleSeconds
)
$refreshAttempted=$false;$refreshOk=$false;$refreshTarget=$null
if($eligible){
  try{
    $refreshTarget=$preferred
    $before=[OaiSyncWin]::GetForegroundWindow()
    [void][OaiSyncWin]::SetForegroundWindow([IntPtr][int64]$refreshTarget.hwnd)
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('^r')
    $refreshAttempted=$true
    Start-Sleep -Seconds 2
    $refreshOk=$true
    if($before-ne[IntPtr]::Zero-and$before.ToInt64()-ne[int64]$refreshTarget.hwnd){
      [void][OaiSyncWin]::SetForegroundWindow($before)
    }
  }catch{$guardError=$_.Exception.Message}
}

$state=[ordered]@{
  version=$Version
  lastCheckAt=$now.ToString('o')
  lastRefreshAt=$(if($refreshOk){(Get-Date).ToString('o')}elseif($prev){[string]$prev.lastRefreshAt}else{''})
  refreshCount=$(if($prev){[int]$prev.refreshCount}else{0})+$(if($refreshOk){1}else{0})
  activeUserChat=$activeUserChat
  continuityStateRef=$ContinuityPath
  continuityStatus=$(if($continuity){[string]$continuity.status}else{'UNKNOWN'})
  lastReceivedInstructionSnapshotRef=$(if($continuity){$ContinuityPath+'#last_received_user_instruction_summary'}else{''})
  lastGood=$(if($continuity){@($continuity.last_good)}else{@()})
  firstUnfinished=$(if($continuity){[string]$continuity.first_unfinished}else{''})
}
Save-Json $StatePath $state

$out=[ordered]@{
  ok=[bool]($webReachable-and$wsReachable-and(
    ($Mode-eq'CHECK')-or
    ($Mode-eq'CAPTURE'-and$captureOk)-or
    ($Mode-eq'RESTORE'-and$restoreOk)
  ))
  version=$Version
  time=(Get-Date).ToString('o')
  mode=$Mode
  ownerRunId=$OwnerRunId
  apply=[bool]$Apply
  chatWindowCount=$wins.Count
  windows=$wins
  edgeExcluded=$true
  canonicalPreference='NATIVE_CHATGPT_THEN_CHROME_CHATGPT__NEVER_EDGE'
  activeUserChat=$activeUserChat
  continuityStateRef=$ContinuityPath
  continuityStatus=$(if($continuity){[string]$continuity.status}else{'UNKNOWN'})
  lastReceivedInstructionSnapshotRef=$(if($continuity){$ContinuityPath+'#last_received_user_instruction_summary'}else{''})
  lastGood=$(if($continuity){@($continuity.last_good)}else{@()})
  firstUnfinished=$(if($continuity){[string]$continuity.first_unfinished}else{''})
  captureOk=$captureOk
  restoreAttempted=$restoreAttempted
  restoreOk=$restoreOk
  web443Reachable=$webReachable
  ws443Reachable=$wsReachable
  idleSeconds=$idle
  cooldownSeconds=$CooldownSeconds
  secondsSinceLastRefresh=[math]::Round($elapsed,0)
  eligible=$eligible
  refreshAttempted=$refreshAttempted
  refreshOk=$refreshOk
  target=$refreshTarget
  guardError=$guardError
  policy='P0_ACTIVE_OPENAI_CHAT_CAPTURE_BEFORE_SUPPORT_TABS__RESTORE_EXACT_SAME_PID_HWND_PROCESS_TITLE__CONTINUITY_STATE_REF__NO_NEW_CHAT__NO_NEW_WINDOW__NO_EDGE_CHATGPT_TARGET__NO_SIGNOUT__NO_COOKIE_CLEAR'
}
Save-Json $ReceiptPath $out
try{
  $persisted=Get-Content $ReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json
  if([string]$persisted.version-ne$Version){throw 'PERSISTED_RECEIPT_VERSION_MISMATCH'}
}catch{Write-Error $_;exit 5}
$out|ConvertTo-Json -Depth 30 -Compress
if($out.ok){exit 0}else{exit 4}