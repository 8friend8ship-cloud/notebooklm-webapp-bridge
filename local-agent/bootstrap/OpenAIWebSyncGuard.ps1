param([switch]$Apply)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='OPENAI_WEB_SYNC_GUARD_V2_20260910'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StatePath=Join-Path $Root 'OPENAI_WEB_SYNC_GUARD_STATE.json'
$ReceiptPath=Join-Path $Root 'OPENAI_WEB_SYNC_GUARD_LAST.json'
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
function Get-IdleSeconds{try{$x=New-Object OaiSyncWin+LASTINPUTINFO;$x.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($x);if([OaiSyncWin]::GetLastInputInfo([ref]$x)){return [math]::Max(0,[int](([Environment]::TickCount64-[int64]$x.dwTime)/1000))}}catch{};return 0}
function Test-Port([string]$HostName,[int]$Port){try{$c=New-Object Net.Sockets.TcpClient;$ar=$c.BeginConnect($HostName,$Port,$null,$null);if(-not$ar.AsyncWaitHandle.WaitOne(3000)){try{$c.Close()}catch{};return $false};$c.EndConnect($ar);$c.Close();return $true}catch{return $false}}
function Get-ChatWindows{
 $rows=@();$root=$null;try{$root=[System.Windows.Automation.AutomationElement]::RootElement}catch{}
 if(-not$root){return @()};try{$tops=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)}catch{return @()}
 foreach($e in @($tops)){try{$c=$e.Current;$procId=[int]$c.ProcessId;$hwnd=[int64]$c.NativeWindowHandle;$title=[string]$c.Name;if($procId-le0-or$hwnd-le0-or[string]::IsNullOrWhiteSpace($title)){continue};$p=Get-Process -Id $procId -ErrorAction Stop;$name=[string]$p.ProcessName;if($name-notmatch'(?i)^(chrome|msedge|chatgpt)$'){continue};if($title-match'(?i)(ChatGPT|OpenAI)'){$rows+=[pscustomobject]@{pid=$procId;hwnd=$hwnd;process=$name;title=$title;foreground=([OaiSyncWin]::GetForegroundWindow().ToInt64()-eq$hwnd)}}}catch{}}
 return @($rows)
}
$now=Get-Date;$prev=$null;try{if(Test-Path $StatePath){$prev=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$lastRefresh=$null;try{if($prev.lastRefreshAt){$lastRefresh=[datetimeoffset]::Parse([string]$prev.lastRefreshAt)}}catch{}
$elapsed=$(if($lastRefresh){([datetimeoffset]::Now-$lastRefresh).TotalSeconds}else{999999})
$wsReachable=Test-Port 'ws.chatgpt.com' 443
$webReachable=Test-Port 'chatgpt.com' 443
$wins=@(Get-ChatWindows);$idle=Get-IdleSeconds
$eligible=[bool]($Apply-and$wins.Count-gt0-and$wsReachable-and$webReachable-and$elapsed-ge$CooldownSeconds-and$idle-ge$MinIdleSeconds)
$refreshAttempted=$false;$refreshOk=$false;$target=$null;$guardError=''
if($eligible){
 try{
  $target=@($wins|Where-Object{-not$_.foreground}|Select-Object -First 1);if(-not$target){$target=$wins|Select-Object -First 1}
  $before=[OaiSyncWin]::GetForegroundWindow();[void][OaiSyncWin]::SetForegroundWindow([IntPtr][int64]$target.hwnd);Start-Sleep -Milliseconds 250;[System.Windows.Forms.SendKeys]::SendWait('^r');$refreshAttempted=$true;Start-Sleep -Seconds 2;$refreshOk=$true;if($before-ne[IntPtr]::Zero-and$before.ToInt64()-ne[int64]$target.hwnd){[void][OaiSyncWin]::SetForegroundWindow($before)}
 }catch{$guardError=$_.Exception.Message}
}
$state=[ordered]@{version=$Version;lastCheckAt=$now.ToString('o');lastRefreshAt=$(if($refreshOk){(Get-Date).ToString('o')}elseif($prev){[string]$prev.lastRefreshAt}else{''});refreshCount=$(if($prev){[int]$prev.refreshCount}else{0})+$(if($refreshOk){1}else{0})};Save-Json $StatePath $state
$out=[ordered]@{ok=[bool]($webReachable-and$wsReachable);version=$Version;time=(Get-Date).ToString('o');apply=[bool]$Apply;chatWindowCount=$wins.Count;windows=$wins;web443Reachable=$webReachable;ws443Reachable=$wsReachable;idleSeconds=$idle;cooldownSeconds=$CooldownSeconds;secondsSinceLastRefresh=[math]::Round($elapsed,0);eligible=$eligible;refreshAttempted=$refreshAttempted;refreshOk=$refreshOk;target=$target;guardError=$guardError;policy='NO_NEW_CHAT;NO_NEW_WINDOW;NO_SIGNOUT;NO_COOKIE_CLEAR;EXISTING_CHATGPT_WINDOW_EXACT_REFRESH_ONLY_WHEN_IDLE+COOLDOWN+NETWORK_OK;RESTORE_FOREGROUND;WEB_UI_NOT_RECOVERY_AUTHORITY'}
Save-Json $ReceiptPath $out
try{$persisted=Get-Content $ReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$persisted.version-ne$Version){throw 'PERSISTED_RECEIPT_VERSION_MISMATCH'}}catch{Write-Error $_;exit 5}
$out|ConvertTo-Json -Depth 30 -Compress;if($out.ok){exit 0}else{exit 4}
