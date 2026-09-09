param(
 [string]$BeforeReopenFamily=''
)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WINDOW_ACTIVITY_SUPERVISOR_V3_ENUM_AUTH_TTL10M_20260909'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StatePath=Join-Path $Root 'WINDOW_ACTIVITY_STATE.json'
$Receipt=Join-Path $Root 'WINDOW_ACTIVITY_LAST.json'
$CaptureDir=Join-Path $Root 'WindowActivity'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$VisualIntervalSec=600
$AuthWindowTtlSec=600
$StaleSamples=2
New-Item -ItemType Directory -Force -Path $Root,$CaptureDir|Out-Null
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class HDWindowRowV3 {
 public long hwnd; public int pid; public string title; public int left; public int top; public int right; public int bottom;
}
public static class HDWindowEnumV3 {
 public delegate bool EnumWindowsProc(IntPtr h,IntPtr l);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb,IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
 public static HDWindowRowV3[] GetWindows(){
  var rows=new List<HDWindowRowV3>();
  EnumWindows(delegate(IntPtr h,IntPtr l){
   try{
    if(!IsWindowVisible(h)) return true;
    var sb=new StringBuilder(2048); GetWindowText(h,sb,sb.Capacity); var t=sb.ToString(); if(String.IsNullOrWhiteSpace(t)) return true;
    uint p=0; GetWindowThreadProcessId(h,out p); RECT r; if(!GetWindowRect(h,out r)) return true; if((r.Right-r.Left)<120||(r.Bottom-r.Top)<80) return true;
    rows.Add(new HDWindowRowV3{hwnd=h.ToInt64(),pid=(int)p,title=t,left=r.Left,top=r.Top,right=r.Right,bottom=r.Bottom});
   }catch{} return true;
  },IntPtr.Zero);
  return rows.ToArray();
 }
 public static long Foreground(){return GetForegroundWindow().ToInt64();}
 public static bool Alive(long h){return IsWindow(new IntPtr(h));}
 public static bool Close(long h){var p=new IntPtr(h); if(!IsWindow(p)) return true; PostMessage(p,0x0010,IntPtr.Zero,IntPtr.Zero); return true;}
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
 return [pscustomobject]$o
}
function Rect-Intersect([int]$l1,[int]$t1,[int]$r1,[int]$b1,[int]$l2,[int]$t2,[int]$r2,[int]$b2){
 $l=[math]::Max($l1,$l2);$t=[math]::Max($t1,$t2);$r=[math]::Min($r1,$r2);$b=[math]::Min($b1,$b2);if($r-le$l-or$b-le$t){return $null};return [System.Drawing.Rectangle]::FromLTRB($l,$t,$r,$b)
}
function Close-Exact([int64]$Hwnd){
 try{if(-not[HDWindowEnumV3]::Alive($Hwnd)){return [pscustomobject]@{closed=$true;state='ALREADY_CLOSED'}};[void][HDWindowEnumV3]::Close($Hwnd);Start-Sleep -Milliseconds 700;$left=[HDWindowEnumV3]::Alive($Hwnd);return [pscustomobject]@{closed=(-not$left);state=$(if(-not$left){'CLOSED_EXACT_HWND'}else{'CLOSE_SENT_STILL_VISIBLE'})}}catch{return [pscustomobject]@{closed=$false;state=('ERROR:'+$_.Exception.Message)}}
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
$fg=[HDWindowEnumV3]::Foreground();$windows=New-Object System.Collections.Generic.List[object]
foreach($wr in @([HDWindowEnumV3]::GetWindows())){
 try{$meta=Get-ProcessMeta ([int]$wr.pid);$family=Family-FromTitle ([string]$wr.title);$key=([string]$wr.pid+':'+[string]$wr.hwnd);$contentHash='';$shouldHash=($family-ne''-or$meta.name-match'(?i)chrome|msedge|powershell|pwsh|cmd|windowsterminal')
  if($shouldHash-and$fullBmp){$ix=Rect-Intersect $wr.left $wr.top $wr.right $wr.bottom $virtual.Left $virtual.Top ($virtual.Left+$virtual.Width) ($virtual.Top+$virtual.Height);if($ix){try{$rel=New-Object System.Drawing.Rectangle(($ix.Left-$virtual.Left),($ix.Top-$virtual.Top),$ix.Width,$ix.Height);$crop=$fullBmp.Clone($rel,$fullBmp.PixelFormat);try{$contentHash=Bitmap-Hash $crop}finally{$crop.Dispose()}}catch{}}}
  $shape=Sha256-Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$wr.title+'|'+$wr.left+'|'+$wr.top+'|'+$wr.right+'|'+$wr.bottom+'|'+$family)))
  $unchanged=0;$nowIso=(Get-Date).ToUniversalTime().ToString('o');$firstSeen=$nowIso;$lastChanged=$nowIso
  if($prevByKey.ContainsKey($key)){$p=$prevByKey[$key];$firstSeen=[string]$p.firstSeenUtc;if([string]$p.shapeHash-eq$shape-and(([string]$p.contentHash-eq$contentHash)-or-not$contentHash)){$unchanged=[int]$p.unchangedSamples+1;$lastChanged=[string]$p.lastChangedUtc}}
  $reg=$null;if($registeredHwnd.ContainsKey([string]$wr.hwnd)){$reg=$registeredHwnd[[string]$wr.hwnd]}
  $windows.Add([pscustomobject][ordered]@{key=$key;pid=[int]$wr.pid;hwnd=[int64]$wr.hwnd;process=[string]$meta.name;processStartUtc=[string]$meta.startUtc;title=[string]$wr.title;family=$family;left=$wr.left;top=$wr.top;right=$wr.right;bottom=$wr.bottom;foreground=([int64]$wr.hwnd-eq$fg);shapeHash=$shape;contentHash=$contentHash;unchangedSamples=$unchanged;firstSeenUtc=$firstSeen;lastChangedUtc=$lastChanged;registered=[bool]($null-ne$reg);registeredState=$(if($reg){[string]$reg.state}else{''});registeredOwner=$(if($reg){[string]$reg.owner}else{''})})
 }catch{}
}
$nowUtc=(Get-Date).ToUniversalTime();$visualDue=$true;try{if($prev.lastVisualCaptureUtc){$visualDue=(($nowUtc-[datetime]::Parse([string]$prev.lastVisualCaptureUtc).ToUniversalTime()).TotalSeconds-ge$VisualIntervalSec)}}catch{}
$captures=@();if($visualDue-and$fullBmp){$screens=@([System.Windows.Forms.Screen]::AllScreens);$idx=0;foreach($s in $screens){$idx++;$b=$s.Bounds;$rel=New-Object System.Drawing.Rectangle(($b.Left-$virtual.Left),($b.Top-$virtual.Top),$b.Width,$b.Height);try{$shot=$fullBmp.Clone($rel,$fullBmp.PixelFormat);try{$rawHash=Bitmap-Hash $shot;$g=[System.Drawing.Graphics]::FromImage($shot);try{foreach($w in @($windows|Where-Object{$_.family-ne''})){$ix=Rect-Intersect $w.left $w.top $w.right $w.bottom $b.Left $b.Top $b.Right $b.Bottom;if($ix){$mask=New-Object System.Drawing.Rectangle(($ix.Left-$b.Left),($ix.Top-$b.Top),$ix.Width,$ix.Height);$g.FillRectangle([System.Drawing.Brushes]::Gray,$mask)}}}finally{$g.Dispose()};$last=Join-Path $CaptureDir ("MONITOR_${idx}_LAST.png");$old=Join-Path $CaptureDir ("MONITOR_${idx}_PREV.png");if(Test-Path $last){Copy-Item $last $old -Force};$shot.Save($last,[System.Drawing.Imaging.ImageFormat]::Png);$captures+=[pscustomobject]@{monitor=$idx;bounds=$b.ToString();rawHash=$rawHash;maskedPath=$last;masked=$true}}finally{$shot.Dispose()}}catch{}}}
if($fullGraphics){$fullGraphics.Dispose()};if($fullBmp){$fullBmp.Dispose()}
$closed=@();$expiredSingle=@();$stale=@();$duplicateFamilies=@();$families=@($windows|Where-Object{$_.family-ne''}|Group-Object family)
foreach($grp in $families){$arr=@($grp.Group);if($arr.Count-gt1){$duplicateFamilies+=$grp.Name;$canonical=@($arr|Where-Object{$_.foreground}|Select-Object -First 1);if($canonical.Count-eq0){$canonical=@($arr|Sort-Object @{Expression={try{[datetime]$_.firstSeenUtc}catch{[datetime]::MinValue}};Descending=$true},@{Expression={$_.hwnd};Descending=$true}|Select-Object -First 1)};$c=$canonical[0];foreach($w in $arr){if($w.hwnd-eq$c.hwnd){continue};$ageSec=0;try{$ageSec=($nowUtc-[datetime]::Parse([string]$w.firstSeenUtc).ToUniversalTime()).TotalSeconds}catch{};$older=$false;try{$older=([datetime]$w.firstSeenUtc-lt[datetime]$c.firstSeenUtc)}catch{};$inactive=([int]$w.unchangedSamples-ge1-and-not[bool]$w.foreground);if($ageSec-ge$AuthWindowTtlSec-or$older-or$inactive){$r=Close-Exact ([int64]$w.hwnd);$closed+=[pscustomobject]@{family=$grp.Name;hwnd=$w.hwnd;pid=$w.pid;canonicalHwnd=$c.hwnd;reason=$(if($ageSec-ge$AuthWindowTtlSec){'AUTH_TTL_EXPIRED_10M'}else{'SUPERSEDED_STALE_DUPLICATE'});ageSec=[math]::Round($ageSec,0);closeState=$r.state;closed=$r.closed}}}}
 elseif($arr.Count-eq1){$w=$arr[0];$ageSec=0;try{$ageSec=($nowUtc-[datetime]::Parse([string]$w.firstSeenUtc).ToUniversalTime()).TotalSeconds}catch{try{$ageSec=($nowUtc-[datetime]::Parse([string]$w.processStartUtc).ToUniversalTime()).TotalSeconds}catch{}};if($ageSec-ge$AuthWindowTtlSec){$r=Close-Exact ([int64]$w.hwnd);$rec=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='SINGLE_AUTH_TTL_EXPIRED_10M';ageSec=[math]::Round($ageSec,0);foreground=$w.foreground;closeState=$r.state;closed=$r.closed};$expiredSingle+=$rec;$closed+=$rec}elseif([int]$w.unchangedSamples-ge$StaleSamples){$stale+=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='WAIT_AUTH_TTL_LT10M';ageSec=[math]::Round($ageSec,0)}}}}
$preReopenClosed=@();if($BeforeReopenFamily){$target=$BeforeReopenFamily.ToUpperInvariant();foreach($w in @($windows|Where-Object{([string]$_.family).ToUpperInvariant()-eq$target})){$r=Close-Exact ([int64]$w.hwnd);$preReopenClosed+=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='PRE_REOPEN_CLOSE_OLD_WINDOW';closeState=$r.state;closed=$r.closed}}}
$remainingDup=0;foreach($grp in @($windows|Where-Object{$_.family-ne''}|Group-Object family)){try{$alive=@($grp.Group|Where-Object{[HDWindowEnumV3]::Alive([int64]$_.hwnd)});if($alive.Count-gt1){$remainingDup++}}catch{}}
$ttlCloseFailures=@($expiredSingle|Where-Object{-not$_.closed}).Count
$nowText=$nowUtc.ToString('s')+'Z';$lastCaptureText='';if($visualDue){$lastCaptureText=$nowText}elseif($prev){$lastCaptureText=[string]$prev.lastVisualCaptureUtc}
$state=[ordered]@{version=$Version;timeUtc=$nowText;lastVisualCaptureUtc=$lastCaptureText;windows=$windows.ToArray();captures=$captures};Save-Json $StatePath $state
$out=[ordered]@{ok=($remainingDup-eq0-and$ttlCloseFailures-eq0);version=$Version;time=(Get-Date).ToString('o');visualDue=$visualDue;monitorCount=@([System.Windows.Forms.Screen]::AllScreens).Count;captureCount=$captures.Count;captures=$captures;windowCount=$windows.Count;authWindowCount=@($windows|Where-Object{$_.family-ne''}).Count;authWindowTtlSec=$AuthWindowTtlSec;duplicateFamilies=@($duplicateFamilies|Sort-Object -Unique);duplicateFamiliesRemaining=$remainingDup;closedSuperseded=@($closed);closedSupersededCount=@($closed|Where-Object{$_.closed}).Count;expiredSingleAuth=@($expiredSingle);expiredSingleAuthCount=@($expiredSingle|Where-Object{$_.closed}).Count;ttlCloseFailures=$ttlCloseFailures;staleBeforeTtl=@($stale);preReopenFamily=$BeforeReopenFamily;preReopenClosed=@($preReopenClosed);activityRule='VISIBLE_NOT_EQUAL_WORKING;ENUM_WINDOWS+SEQUENTIAL_CONTENT_HASH+FOREGROUND+FIRST_SEEN;LATEST_ACTIVE_CANONICAL';closeRule='AUTH_WINDOW_HARD_TTL_10M;SINGLE_OR_DUPLICATE_EXPIRED_CLOSE_EXACT_HWND;NEW_CANONICAL_ACTIVE=>OLDER_DUPLICATE_CLOSE;WAITING_USER_DOES_NOT_OVERRIDE_TTL;PRE_REOPEN_CLOSE_OLD_FAMILY';capturePolicy='ALL_MONITORS_10M;RAW_HASH_ONLY;SAVED_SCREENSHOTS_MASK_AUTH_WINDOWS;KEEP_LAST_AND_PREV'}
$json=$out|ConvertTo-Json -Depth 50;$json|Set-Content -LiteralPath $Receipt -Encoding UTF8
try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback\WindowActivity';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'WINDOW_ACTIVITY_LAST.json') -Encoding UTF8;foreach($cap in $captures){$idx=[int]$cap.monitor;$src=[string]$cap.maskedPath;$dst=Join-Path $d ("MONITOR_${idx}_LAST.png");$old=Join-Path $d ("MONITOR_${idx}_PREV.png");if(Test-Path $dst){Copy-Item $dst $old -Force};if(Test-Path $src){Copy-Item $src $dst -Force}}}}catch{}
$out|ConvertTo-Json -Depth 50 -Compress
if($out.ok){exit 0}else{exit 4}
