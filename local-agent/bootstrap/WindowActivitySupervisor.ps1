param(
 [string]$BeforeReopenFamily=''
)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WINDOW_ACTIVITY_SUPERVISOR_V1_SEQUENCE_DUAL_MONITOR_20260909'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StatePath=Join-Path $Root 'WINDOW_ACTIVITY_STATE.json'
$Receipt=Join-Path $Root 'WINDOW_ACTIVITY_LAST.json'
$CaptureDir=Join-Path $Root 'WindowActivity'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$VisualIntervalSec=600
$StaleSamples=2
New-Item -ItemType Directory -Force -Path $Root,$CaptureDir|Out-Null
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WinActivityV1 {
 public delegate bool EnumWindowsProc(IntPtr h,IntPtr l);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
'@ -ErrorAction SilentlyContinue
function Save-Json([string]$Path,$Object){try{$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function Sha256-Bytes([byte[]]$Bytes){$s=[Security.Cryptography.SHA256]::Create();try{return (($s.ComputeHash($Bytes)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Bitmap-Hash($Bitmap){try{$ms=New-Object IO.MemoryStream;try{$Bitmap.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png);return Sha256-Bytes $ms.ToArray()}finally{$ms.Dispose()}}catch{return ''}}
function Family-FromTitle([string]$Title){
 if($Title-match'(?i)Desktop Commander Remote MCP|mcp\.desktopcommander\.app.*verify'){return'REMOTE_DC_AUTH'}
 if($Title-match'(?i)(네이버|NAVER).*(로그인|인증|QR|계정)|(?:로그인|인증|QR).*(네이버|NAVER)'){return'NAVER_AUTH'}
 if($Title-match'(?i)NICE|나이스|본인.?인증|휴대폰.?인증|아이핀|i-?PIN'){return'NICE_AUTH'}
 if($Title-match'(?i)Google 계정|Sign in.*Google|Google Accounts|accounts\.google'){return'GOOGLE_AUTH'}
 if($Title-match'(?i)(카카오|Kakao).*(로그인|인증|계정)|(?:로그인|인증).*(카카오|Kakao)'){return'KAKAO_AUTH'}
 return''
}
function Get-ProcessMeta([int]$Pid){
 $o=[ordered]@{name='';startUtc='';commandLine=''}
 try{$p=Get-Process -Id $Pid -ErrorAction Stop;$o.name=[string]$p.ProcessName;$o.startUtc=$p.StartTime.ToUniversalTime().ToString('o')}catch{}
 try{$c=Get-CimInstance Win32_Process -Filter ("ProcessId="+$Pid) -ErrorAction Stop;$o.commandLine=[string]$c.CommandLine}catch{}
 return[pscustomobject]$o
}
function Rect-Intersect([int]$l1,[int]$t1,[int]$r1,[int]$b1,[int]$l2,[int]$t2,[int]$r2,[int]$b2){
 $l=[math]::Max($l1,$l2);$t=[math]::Max($t1,$t2);$r=[math]::Min($r1,$r2);$b=[math]::Min($b1,$b2)
 if($r-le$l-or$b-le$t){return $null};return[System.Drawing.Rectangle]::FromLTRB($l,$t,$r,$b)
}
function Close-Exact([int64]$Hwnd){
 try{$h=[IntPtr]$Hwnd;if(-not[WinActivityV1]::IsWindow($h)){return[pscustomobject]@{closed=$true;state='ALREADY_CLOSED'}};$sent=[WinActivityV1]::PostMessage($h,0x0010,[IntPtr]::Zero,[IntPtr]::Zero);Start-Sleep -Milliseconds 700;$left=[WinActivityV1]::IsWindow($h);return[pscustomobject]@{closed=(-not$left);state=$(if(-not$left){'CLOSED_EXACT_HWND'}elseif($sent){'CLOSE_SENT_STILL_VISIBLE'}else{'CLOSE_SEND_FAIL'})}}catch{return[pscustomobject]@{closed=$false;state=('ERROR:'+$_.Exception.Message)}}
}
function Find-Central{
 $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
 foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return''
}
$prev=$null;try{if(Test-Path $StatePath){$prev=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$prevByKey=@{};if($prev-and$prev.windows){foreach($w in @($prev.windows)){$prevByKey[[string]$w.key]=$w}}
$registryItems=@();try{if(Test-Path $Registry){$registryItems=@(Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json)}}catch{}
$registeredHwnd=@{};foreach($ri in $registryItems){try{if([int64]$ri.hwnd-gt0){$registeredHwnd[[string][int64]$ri.hwnd]=$ri}}catch{}}
$virtual=[System.Windows.Forms.SystemInformation]::VirtualScreen
$fullBmp=$null;$fullGraphics=$null
try{$fullBmp=New-Object System.Drawing.Bitmap($virtual.Width,$virtual.Height);$fullGraphics=[System.Drawing.Graphics]::FromImage($fullBmp);$fullGraphics.CopyFromScreen($virtual.Left,$virtual.Top,0,0,$fullBmp.Size)}catch{}
$fg=[WinActivityV1]::GetForegroundWindow().ToInt64()
$windows=New-Object System.Collections.Generic.List[object]
$cb=[WinActivityV1+EnumWindowsProc]{param($h,$l)
 try{
  if(-not[WinActivityV1]::IsWindowVisible($h)){return $true};$sb=New-Object Text.StringBuilder 2048;[void][WinActivityV1]::GetWindowText($h,$sb,$sb.Capacity);$title=$sb.ToString();if([string]::IsNullOrWhiteSpace($title)){return $true}
  [uint32]$pid=0;[void][WinActivityV1]::GetWindowThreadProcessId($h,[ref]$pid);$r=New-Object WinActivityV1+RECT;if(-not[WinActivityV1]::GetWindowRect($h,[ref]$r)){return $true};if(($r.Right-$r.Left)-lt120-or($r.Bottom-$r.Top)-lt80){return $true}
  $meta=Get-ProcessMeta ([int]$pid);$family=Family-FromTitle $title;$key=([string]$pid+':'+$h.ToInt64());$contentHash=''
  $shouldHash=($family-ne''-or$meta.name-match'(?i)chrome|msedge|powershell|pwsh|cmd|windowsterminal')
  if($shouldHash-and$fullBmp){$ix=Rect-Intersect $r.Left $r.Top $r.Right $r.Bottom $virtual.Left $virtual.Top ($virtual.Left+$virtual.Width) ($virtual.Top+$virtual.Height);if($ix){try{$rel=New-Object System.Drawing.Rectangle(($ix.Left-$virtual.Left),($ix.Top-$virtual.Top),$ix.Width,$ix.Height);$crop=$fullBmp.Clone($rel,$fullBmp.PixelFormat);try{$contentHash=Bitmap-Hash $crop}finally{$crop.Dispose()}}catch{}}}
  $shape=Sha256-Bytes ([Text.Encoding]::UTF8.GetBytes(($title+'|'+$r.Left+'|'+$r.Top+'|'+$r.Right+'|'+$r.Bottom+'|'+$family)))
  $unchanged=0;$lastChanged=(Get-Date).ToUniversalTime().ToString('o');$firstSeen=$lastChanged
  if($prevByKey.ContainsKey($key)){$p=$prevByKey[$key];$firstSeen=[string]$p.firstSeenUtc;if([string]$p.shapeHash-eq$shape-and([string]$p.contentHash-eq$contentHash-or-not$contentHash)){$unchanged=[int]$p.unchangedSamples+1;$lastChanged=[string]$p.lastChangedUtc}}
  $reg=$null;if($registeredHwnd.ContainsKey([string]$h.ToInt64())){$reg=$registeredHwnd[[string]$h.ToInt64()]}
  $windows.Add([pscustomobject][ordered]@{key=$key;pid=[int]$pid;hwnd=$h.ToInt64();process=[string]$meta.name;processStartUtc=[string]$meta.startUtc;title=$title;family=$family;left=$r.Left;top=$r.Top;right=$r.Right;bottom=$r.Bottom;foreground=($h.ToInt64()-eq$fg);shapeHash=$shape;contentHash=$contentHash;unchangedSamples=$unchanged;firstSeenUtc=$firstSeen;lastChangedUtc=$lastChanged;registered=[bool]($null-ne$reg);registeredState=$(if($reg){[string]$reg.state}else{''});registeredOwner=$(if($reg){[string]$reg.owner}else{''})})
 }catch{}
 return $true
}
[WinActivityV1]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$nowUtc=(Get-Date).ToUniversalTime();$visualDue=$true
try{if($prev.lastVisualCaptureUtc){$visualDue=(($nowUtc-[datetime]::Parse([string]$prev.lastVisualCaptureUtc).ToUniversalTime()).TotalSeconds-ge$VisualIntervalSec)}}catch{}
$captures=@();$screenMotion=@{}
if($visualDue-and$fullBmp){
 $screens=@([System.Windows.Forms.Screen]::AllScreens);$idx=0
 foreach($s in $screens){$idx++;$b=$s.Bounds;$rel=New-Object System.Drawing.Rectangle(($b.Left-$virtual.Left),($b.Top-$virtual.Top),$b.Width,$b.Height);try{$shot=$fullBmp.Clone($rel,$fullBmp.PixelFormat);try{$rawHash=Bitmap-Hash $shot;$g=[System.Drawing.Graphics]::FromImage($shot);try{foreach($w in @($windows|Where-Object{$_.family-ne''})){ $ix=Rect-Intersect $w.left $w.top $w.right $w.bottom $b.Left $b.Top $b.Right $b.Bottom;if($ix){$mask=New-Object System.Drawing.Rectangle(($ix.Left-$b.Left),($ix.Top-$b.Top),$ix.Width,$ix.Height);$g.FillRectangle([System.Drawing.Brushes]::Gray,$mask)}}}finally{$g.Dispose()};$last=Join-Path $CaptureDir ("MONITOR_${idx}_LAST.png");$prevCap=Join-Path $CaptureDir ("MONITOR_${idx}_PREV.png");if(Test-Path $last){Copy-Item $last $prevCap -Force};$shot.Save($last,[System.Drawing.Imaging.ImageFormat]::Png);$captures+=[pscustomobject]@{monitor=$idx;bounds=($b.ToString());rawHash=$rawHash;maskedPath=$last;masked=$true};$screenMotion[[string]$idx]=$rawHash}finally{$shot.Dispose()}}catch{}
 }
}
if($fullGraphics){$fullGraphics.Dispose()};if($fullBmp){$fullBmp.Dispose()}
$closed=@();$stale=@();$duplicateFamilies=@();$families=@($windows|Where-Object{$_.family-ne''}|Group-Object family)
foreach($grp in $families){
 $arr=@($grp.Group);if($arr.Count-gt1){$duplicateFamilies+=$grp.Name
  $canonical=@($arr|Where-Object{$_.foreground}|Select-Object -First 1);if($canonical.Count-eq0){$canonical=@($arr|Sort-Object @{Expression={try{[datetime]$_.processStartUtc}catch{[datetime]::MinValue}};Descending=$true},@{Expression={$_.hwnd};Descending=$true}|Select-Object -First 1)};$c=$canonical[0]
  foreach($w in $arr){if($w.hwnd-eq$c.hwnd){continue};$older=$false;try{$older=([datetime]$w.processStartUtc-lt[datetime]$c.processStartUtc)}catch{};$inactive=([int]$w.unchangedSamples-ge1-and-not[bool]$w.foreground);if($older-or$inactive){$r=Close-Exact ([int64]$w.hwnd);$closed+=[pscustomobject]@{family=$grp.Name;hwnd=$w.hwnd;pid=$w.pid;canonicalHwnd=$c.hwnd;reason='SUPERSEDED_STALE_DUPLICATE';unchangedSamples=$w.unchangedSamples;registered=$w.registered;registeredState=$w.registeredState;closeState=$r.state;closed=$r.closed}}}
 }elseif($arr.Count-eq1){$w=$arr[0];if([int]$w.unchangedSamples-ge$StaleSamples-and-not[bool]$w.foreground){$stale+=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='STALE_REOPEN_REQUIRED';unchangedSamples=$w.unchangedSamples;registered=$w.registered;registeredState=$w.registeredState}}}
}
$preReopenClosed=@();if($BeforeReopenFamily){$target=$BeforeReopenFamily.ToUpperInvariant();foreach($w in @($windows|Where-Object{([string]$_.family).ToUpperInvariant()-eq$target})){if(-not$w.foreground-or$w.unchangedSamples-ge1){$r=Close-Exact ([int64]$w.hwnd);$preReopenClosed+=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='PRE_REOPEN_CLOSE_OLD_WINDOW';closeState=$r.state;closed=$r.closed}}}}
$remainingDup=0;foreach($grp in @($windows|Where-Object{$_.family-ne''}|Group-Object family)){try{$alive=@($grp.Group|Where-Object{[WinActivityV1]::IsWindow([IntPtr][int64]$_.hwnd)});if($alive.Count-gt1){$remainingDup++}}catch{}}
$state=[ordered]@{version=$Version;timeUtc=$nowUtc.ToString('o');lastVisualCaptureUtc=$(if($visualDue){$nowUtc.ToString('o')}elseif($prev){[string]$prev.lastVisualCaptureUtc}else{''});windows=@($windows);captures=$captures}
Save-Json $StatePath $state
$out=[ordered]@{ok=($remainingDup-eq0);version=$Version;time=(Get-Date).ToString('o');visualDue=$visualDue;monitorCount=@([System.Windows.Forms.Screen]::AllScreens).Count;captureCount=$captures.Count;captures=$captures;windowCount=$windows.Count;authWindowCount=@($windows|Where-Object{$_.family-ne''}).Count;duplicateFamilies=@($duplicateFamilies|Sort-Object -Unique);duplicateFamiliesRemaining=$remainingDup;closedSuperseded=@($closed);closedSupersededCount=@($closed|Where-Object{$_.closed}).Count;staleReopenRequired=@($stale);preReopenFamily=$BeforeReopenFamily;preReopenClosed=@($preReopenClosed);activityRule='VISIBLE_NOT_EQUAL_WORKING;SEQUENTIAL_WINDOW_CONTENT_HASH+FOREGROUND+PROCESS_START;LATEST_ACTIVE_CANONICAL';closeRule='NEW_CANONICAL_ACTIVE=>OLDER_UNCHANGED_DUPLICATE_CLOSE_EXACT_HWND;WAITING_USER_DOES_NOT_PROTECT_SUPERSEDED_WINDOW;SINGLE_STALE=>REOPEN_REQUIRED_ONLY';capturePolicy='DUAL_OR_ALL_MONITORS_10M;RAW_HASH_ONLY;SAVED_SCREENSHOTS_MASK_AUTH_WINDOWS;KEEP_LAST_AND_PREV'}
$json=$out|ConvertTo-Json -Depth 50
$json|Set-Content -LiteralPath $Receipt -Encoding UTF8
try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback\WindowActivity';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'WINDOW_ACTIVITY_LAST.json') -Encoding UTF8;foreach($cap in $captures){$idx=[int]$cap.monitor;$src=[string]$cap.maskedPath;$dst=Join-Path $d ("MONITOR_${idx}_LAST.png");$old=Join-Path $d ("MONITOR_${idx}_PREV.png");if(Test-Path $dst){Copy-Item $dst $old -Force};if(Test-Path $src){Copy-Item $src $dst -Force}}}}catch{}
$out|ConvertTo-Json -Depth 50 -Compress
if($out.ok){exit 0}else{exit 4}
