param([string]$BeforeReopenFamily='')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WINDOW_ACTIVITY_SUPERVISOR_V6_WIN32_DPI_FLATREG_20260909'
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
using System.Runtime.InteropServices;
public static class HDWinV6 {
 public delegate bool EnumWindowsProc(IntPtr h,IntPtr l);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb,IntPtr l);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
}
'@ -ErrorAction SilentlyContinue
function Save-Json([string]$Path,$Object){try{$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function Sha256-Bytes([byte[]]$Bytes){$s=[Security.Cryptography.SHA256]::Create();try{return (($s.ComputeHash($Bytes)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Bitmap-Hash($Bitmap){try{$ms=New-Object IO.MemoryStream;try{$Bitmap.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png);return Sha256-Bytes $ms.ToArray()}finally{$ms.Dispose()}}catch{return ''}}
function Family-FromTitle([string]$Title){
 if($Title-match'(?i)Desktop Commander Remote MCP|mcp\.desktopcommander\.app.*verify'){return 'REMOTE_DC_AUTH'}
 if($Title-match'(?i)(네이버|NAVER).*(로그인|인증|QR|계정)|(?:로그인|인증|QR).*(네이버|NAVER)'){return 'NAVER_AUTH'}
 if($Title-match'(?i)NICE|나이스|본인.?인증|휴대폰.?인증|아이핀|i-?PIN'){return 'NICE_AUTH'}
 if($Title-match'(?i)Google 계정|Sign in.*Google|Google Accounts|accounts\.google'){return 'GOOGLE_AUTH'}
 if($Title-match'(?i)(카카오|Kakao).*(로그인|인증|계정)|(?:로그인|인증).*(카카오|Kakao)'){return 'KAKAO_AUTH'}
 return ''
}
function Expand-Registry($Node){
 $list=New-Object System.Collections.Generic.List[object]
 function Walk-Registry($x){
  if($null-eq$x){return}
  if($x -is [System.Array]){foreach($a in $x){Walk-Registry $a};return}
  $names=@($x.PSObject.Properties.Name)
  if($names -contains 'runId'){$list.Add($x);return}
  if($names -contains 'value'){Walk-Registry $x.value}
 }
 Walk-Registry $Node
 return @($list)
}
function Rect-Intersect([int]$l1,[int]$t1,[int]$r1,[int]$b1,[int]$l2,[int]$t2,[int]$r2,[int]$b2){$l=[math]::Max($l1,$l2);$t=[math]::Max($t1,$t2);$r=[math]::Min($r1,$r2);$b=[math]::Min($b1,$b2);if($r-le$l-or$b-le$t){return $null};return [System.Drawing.Rectangle]::FromLTRB($l,$t,$r,$b)}
function Get-Title([int64]$Hwnd){$sb=New-Object Text.StringBuilder 2048;[void][HDWinV6]::GetWindowText([IntPtr]$Hwnd,$sb,$sb.Capacity);return $sb.ToString()}
function Close-Exact([int64]$Hwnd,[int]$ExpectedPid,[string]$ExpectedFamily){
 $h=[IntPtr]$Hwnd;if(-not[HDWinV6]::IsWindow($h)){return [pscustomobject]@{closed=$true;state='ALREADY_CLOSED'}}
 [uint32]$actual=0;[void][HDWinV6]::GetWindowThreadProcessId($h,[ref]$actual);if([int]$actual-ne$ExpectedPid){return [pscustomobject]@{closed=$false;state='PID_MISMATCH_PROTECTED'}}
 $title=Get-Title $Hwnd;$fam=Family-FromTitle $title;if($ExpectedFamily-and$fam-ne$ExpectedFamily){return [pscustomobject]@{closed=$false;state='FAMILY_MISMATCH_PROTECTED'}}
 [void][HDWinV6]::PostMessage($h,0x0010,[IntPtr]::Zero,[IntPtr]::Zero);Start-Sleep -Milliseconds 800;$left=[HDWinV6]::IsWindow($h);return [pscustomobject]@{closed=(-not$left);state=$(if($left){'CLOSE_SENT_STILL_VISIBLE'}else{'CLOSED_EXACT_HWND'})}
}
function Find-Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
$prev=$null;try{if(Test-Path $StatePath){$prev=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{};$prevByKey=@{};if($prev-and$prev.windows){foreach($w in @($prev.windows)){$prevByKey[[string]$w.key]=$w}}
$rawRegistry=$null;$registryItems=@();$registryError='';try{if(Test-Path $Registry){$rawRegistry=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;$registryItems=@(Expand-Registry $rawRegistry)}}catch{$registryError=$_.Exception.Message}
$registeredHwnd=@{};foreach($ri in $registryItems){try{if([int64]$ri.hwnd-gt0){$registeredHwnd[[string][int64]$ri.hwnd]=$ri}}catch{}}
$virtual=[System.Windows.Forms.SystemInformation]::VirtualScreen;$fullBmp=$null;$fullGraphics=$null;$captureSetupError='';try{$fullBmp=New-Object System.Drawing.Bitmap($virtual.Width,$virtual.Height);$fullGraphics=[System.Drawing.Graphics]::FromImage($fullBmp);$fullGraphics.CopyFromScreen($virtual.Left,$virtual.Top,0,0,$fullBmp.Size)}catch{$captureSetupError=$_.Exception.Message}
$windows=New-Object System.Collections.Generic.List[object];$enumErrors=New-Object System.Collections.Generic.List[string];$nativeVisibleCount=0;$fg=[HDWinV6]::GetForegroundWindow().ToInt64()
$cb=[HDWinV6+EnumWindowsProc]{param($h,$l)
 try{
  if(-not[HDWinV6]::IsWindowVisible($h)){return $true};$title=Get-Title $h.ToInt64();if([string]::IsNullOrWhiteSpace($title)){return $true};$script:nativeVisibleCount++
  [uint32]$winPid=0;[void][HDWinV6]::GetWindowThreadProcessId($h,[ref]$winPid);$p=Get-Process -Id ([int]$winPid) -ErrorAction Stop
  $rect=New-Object HDWinV6+RECT;if(-not[HDWinV6]::GetWindowRect($h,[ref]$rect)){return $true};$lft=[int]$rect.Left;$top=[int]$rect.Top;$rgt=[int]$rect.Right;$btm=[int]$rect.Bottom;if(($rgt-$lft)-lt120-or($btm-$top)-lt80){return $true}
  $family=Family-FromTitle $title;$key=([string]$winPid+':'+[string]$h.ToInt64());$contentHash='';$shouldHash=($family-ne''-or$p.ProcessName-match'(?i)chrome|msedge|powershell|pwsh|cmd|windowsterminal')
  if($shouldHash-and$fullBmp){$ix=Rect-Intersect $lft $top $rgt $btm $virtual.Left $virtual.Top ($virtual.Left+$virtual.Width) ($virtual.Top+$virtual.Height);if($ix){try{$rel=New-Object System.Drawing.Rectangle(($ix.Left-$virtual.Left),($ix.Top-$virtual.Top),$ix.Width,$ix.Height);$crop=$fullBmp.Clone($rel,$fullBmp.PixelFormat);try{$contentHash=Bitmap-Hash $crop}finally{$crop.Dispose()}}catch{}}}
  $shape=Sha256-Bytes ([Text.Encoding]::UTF8.GetBytes(($title+'|'+$lft+'|'+$top+'|'+$rgt+'|'+$btm+'|'+$family)));$nowIso=(Get-Date).ToUniversalTime().ToString('o');$first=$nowIso;$last=$nowIso;$unchanged=0
  if($prevByKey.ContainsKey($key)){$old=$prevByKey[$key];$first=[string]$old.firstSeenUtc;if([string]$old.shapeHash-eq$shape-and(([string]$old.contentHash-eq$contentHash)-or-not$contentHash)){$unchanged=[int]$old.unchangedSamples+1;$last=[string]$old.lastChangedUtc}}
  $reg=$null;if($registeredHwnd.ContainsKey([string]$h.ToInt64())){$reg=$registeredHwnd[[string]$h.ToInt64()]}
  $windows.Add([pscustomobject][ordered]@{key=$key;pid=[int]$winPid;hwnd=[int64]$h.ToInt64();process=[string]$p.ProcessName;processStartUtc=$(try{$p.StartTime.ToUniversalTime().ToString('o')}catch{''});title=$title;family=$family;left=$lft;top=$top;right=$rgt;bottom=$btm;foreground=([int64]$h.ToInt64()-eq$fg);shapeHash=$shape;contentHash=$contentHash;unchangedSamples=$unchanged;firstSeenUtc=$first;lastChangedUtc=$last;registered=[bool]($null-ne$reg);registeredState=$(if($reg){[string]$reg.state}else{''});registeredOwner=$(if($reg){[string]$reg.owner}else{''});registeredKeepOpen=$(if($reg){[bool]$reg.keepOpen}else{$false})})
 }catch{$enumErrors.Add($_.Exception.GetType().FullName+':'+$_.Exception.Message)}
 return $true
}
[void][HDWinV6]::EnumWindows($cb,[IntPtr]::Zero)
$nowUtc=(Get-Date).ToUniversalTime();$visualDue=$true;try{if($prev.lastVisualCaptureUtc){$visualDue=(($nowUtc-[datetime]::Parse([string]$prev.lastVisualCaptureUtc).ToUniversalTime()).TotalSeconds-ge$VisualIntervalSec)}}catch{};$captures=@()
if($visualDue-and$fullBmp){$idx=0;foreach($s in @([System.Windows.Forms.Screen]::AllScreens)){$idx++;$b=$s.Bounds;try{$rel=New-Object System.Drawing.Rectangle(($b.Left-$virtual.Left),($b.Top-$virtual.Top),$b.Width,$b.Height);$shot=$fullBmp.Clone($rel,$fullBmp.PixelFormat);try{$rawHash=Bitmap-Hash $shot;$g=[System.Drawing.Graphics]::FromImage($shot);try{foreach($w in @($windows|Where-Object{$_.family-ne''})){$ix=Rect-Intersect $w.left $w.top $w.right $w.bottom $b.Left $b.Top $b.Right $b.Bottom;if($ix){$mask=New-Object System.Drawing.Rectangle(($ix.Left-$b.Left),($ix.Top-$b.Top),$ix.Width,$ix.Height);$g.FillRectangle([System.Drawing.Brushes]::Gray,$mask)}}}finally{$g.Dispose()};$last=Join-Path $CaptureDir ("MONITOR_${idx}_LAST.png");$old=Join-Path $CaptureDir ("MONITOR_${idx}_PREV.png");if(Test-Path $last){Copy-Item $last $old -Force};$shot.Save($last,[System.Drawing.Imaging.ImageFormat]::Png);$captures+=[pscustomobject]@{monitor=$idx;bounds=$b.ToString();rawHash=$rawHash;maskedPath=$last;masked=$true}}finally{$shot.Dispose()}}catch{$enumErrors.Add('CAPTURE:'+ $_.Exception.Message)}}}
if($fullGraphics){$fullGraphics.Dispose()};if($fullBmp){$fullBmp.Dispose()}
$closed=@();$expiredSingle=@();$stale=@();$duplicateFamilies=@()
foreach($grp in @($windows|Where-Object{$_.family-ne''}|Group-Object family)){
 $arr=@($grp.Group);if($arr.Count-gt1){$duplicateFamilies+=$grp.Name;$canonical=@($arr|Where-Object{$_.foreground}|Select-Object -First 1);if($canonical.Count-eq0){$canonical=@($arr|Sort-Object firstSeenUtc -Descending|Select-Object -First 1)};$c=$canonical[0]
 foreach($w in $arr){if($w.hwnd-eq$c.hwnd){continue};$age=0;try{$age=($nowUtc-[datetime]::Parse([string]$w.firstSeenUtc).ToUniversalTime()).TotalSeconds}catch{};$inactive=([int]$w.unchangedSamples-ge1-and-not[bool]$w.foreground);if(($age-ge$AuthWindowTtlSec-or$inactive)-and-not$w.registeredKeepOpen-and$w.registeredState-ne'WAITING_USER'){$x=Close-Exact ([int64]$w.hwnd) ([int]$w.pid) ([string]$w.family);$closed+=[pscustomobject]@{family=$grp.Name;hwnd=$w.hwnd;pid=$w.pid;reason=$(if($age-ge$AuthWindowTtlSec){'AUTH_TTL_EXPIRED_10M'}else{'STALE_DUPLICATE'});ageSec=[math]::Round($age,0);closeState=$x.state;closed=$x.closed}}}}
 elseif($arr.Count-eq1){$w=$arr[0];$age=0;try{$age=($nowUtc-[datetime]::Parse([string]$w.firstSeenUtc).ToUniversalTime()).TotalSeconds}catch{};if($age-ge$AuthWindowTtlSec-and-not$w.foreground-and-not$w.registeredKeepOpen-and$w.registeredState-ne'WAITING_USER'){$x=Close-Exact ([int64]$w.hwnd) ([int]$w.pid) ([string]$w.family);$rec=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='SINGLE_AUTH_TTL_EXPIRED_10M';ageSec=[math]::Round($age,0);closeState=$x.state;closed=$x.closed};$expiredSingle+=$rec;$closed+=$rec}elseif([int]$w.unchangedSamples-ge$StaleSamples){$stale+=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;reason='WAIT_AUTH_TTL_OR_PROTECTED';ageSec=[math]::Round($age,0)}}}
}
$preReopenClosed=@();if($BeforeReopenFamily){$target=$BeforeReopenFamily.ToUpperInvariant();foreach($w in @($windows|Where-Object{([string]$_.family).ToUpperInvariant()-eq$target-and-not$_.registeredKeepOpen-and$_.registeredState-ne'WAITING_USER'})){$x=Close-Exact ([int64]$w.hwnd) ([int]$w.pid) ([string]$w.family);$preReopenClosed+=[pscustomobject]@{family=$w.family;hwnd=$w.hwnd;pid=$w.pid;closeState=$x.state;closed=$x.closed}}}
$remainingDup=0;foreach($grp in @($windows|Where-Object{$_.family-ne''}|Group-Object family)){$alive=@($grp.Group|Where-Object{[HDWinV6]::IsWindow([IntPtr][int64]$_.hwnd)});if($alive.Count-gt1){$remainingDup++}}
$ttlCloseFailures=@($expiredSingle|Where-Object{-not$_.closed}).Count;$falsePass=($nativeVisibleCount-gt0-and$windows.Count-eq0);$nowText=$nowUtc.ToString('s')+'Z';$lastCaptureText=$(if($visualDue){$nowText}elseif($prev){[string]$prev.lastVisualCaptureUtc}else{''})
$state=[ordered]@{version=$Version;timeUtc=$nowText;lastVisualCaptureUtc=$lastCaptureText;windows=$windows.ToArray();captures=$captures;registryFlatCount=$registryItems.Count;nativeVisibleCount=$nativeVisibleCount;enumerationErrorCount=$enumErrors.Count};Save-Json $StatePath $state
$out=[ordered]@{ok=([string]::IsNullOrEmpty($registryError)-and-not$falsePass-and$remainingDup-eq0-and$ttlCloseFailures-eq0);version=$Version;time=(Get-Date).ToString('o');visualDue=$visualDue;monitorCount=@([System.Windows.Forms.Screen]::AllScreens).Count;captureCount=$captures.Count;windowCount=$windows.Count;nativeVisibleCount=$nativeVisibleCount;enumerationErrorCount=$enumErrors.Count;enumerationErrors=@($enumErrors|Select-Object -First 20);registryRawCount=$(if($rawRegistry){@($rawRegistry).Count}else{0});registryFlatCount=$registryItems.Count;registryError=$registryError;falsePassDetected=$falsePass;authWindowCount=@($windows|Where-Object{$_.family-ne''}).Count;authWindowTtlSec=$AuthWindowTtlSec;duplicateFamilies=@($duplicateFamilies|Sort-Object -Unique);duplicateFamiliesRemaining=$remainingDup;closedSuperseded=$closed;closedSupersededCount=@($closed|Where-Object{$_.closed}).Count;expiredSingleAuth=$expiredSingle;expiredSingleAuthCount=@($expiredSingle|Where-Object{$_.closed}).Count;ttlCloseFailures=$ttlCloseFailures;staleBeforeTtl=$stale;preReopenFamily=$BeforeReopenFamily;preReopenClosed=$preReopenClosed;geometrySource='WIN32_GETWINDOWRECT_PHYSICAL_PIXELS';activityRule='VISIBLE_NATIVE_TOPLEVEL+WIN32_RECT+PIXEL_HASH+FOREGROUND+FIRST_SEEN';closeRule='AUTH_TTL_600S;EXACT_HWND_PID_FAMILY_RECHECK;WAITING_USER_KEEP_OPEN_PROTECTED';capturePolicy='ALL_MONITORS_10M;MASK_AUTH_WINDOWS;KEEP_LAST_PREV'}
$json=$out|ConvertTo-Json -Depth 50;$json|Set-Content -LiteralPath $Receipt -Encoding UTF8;try{$c=Find-Central;if($c){$d=Join-Path $c 'Runtime_Readback\WindowActivity';New-Item -ItemType Directory -Force -Path $d|Out-Null;$json|Set-Content -LiteralPath (Join-Path $d 'WINDOW_ACTIVITY_LAST.json') -Encoding UTF8;foreach($cap in $captures){$idx=[int]$cap.monitor;$src=[string]$cap.maskedPath;$dst=Join-Path $d ("MONITOR_${idx}_LAST.png");$old=Join-Path $d ("MONITOR_${idx}_PREV.png");if(Test-Path $dst){Copy-Item $dst $old -Force};if(Test-Path $src){Copy-Item $src $dst -Force}}}}catch{};$out|ConvertTo-Json -Depth 50 -Compress;if($out.ok){exit 0}else{exit 4}
