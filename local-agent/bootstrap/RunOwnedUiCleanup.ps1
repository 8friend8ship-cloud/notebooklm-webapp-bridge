param([switch]$PreflightAuth)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='RUN_OWNED_UI_CLEANUP_V4_AUTH_DEDUP_MULTI_HWND_5M_20260909'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$Receipt=Join-Path $Root 'RUN_OWNED_UI_CLEANUP_LAST.json'
$AuthReceipt=Join-Path $Root 'AUTH_UI_DEDUP_LAST.json'
$GraceSeconds=300
$AllowedOwners=@('CENTRAL_AGENT','REMOTE_DC','LOCAL_RUNNER','CFT_WORKER')
New-Item -ItemType Directory -Force -Path $Root|Out-Null
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class UiWinV4 {
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@ -ErrorAction SilentlyContinue
function Save-Json([string]$Path,$Object){try{$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function Parse-Time($x){foreach($n in @('verifiedAt','completedAt','resultAckAt','openedAt','createdAt')){try{$v=$x.$n;if($v){return [datetimeoffset]::Parse([string]$v)}}catch{}};return $null}
function Grace-Passed($x){$t=Parse-Time $x;if(-not$t){return $true};return (((Get-Date).ToUniversalTime()-$t.UtcDateTime).TotalSeconds -ge $GraceSeconds)}
function Get-TopWindows([int]$ProcessId){
  $rows=New-Object System.Collections.Generic.List[object]
  $cb=[UiWinV4+EnumWindowsProc]{param($h,$l);[uint32]$winPid=0;[void][UiWinV4]::GetWindowThreadProcessId($h,[ref]$winPid);if([int]$winPid -eq $ProcessId -and [UiWinV4]::IsWindowVisible($h)){$sb=New-Object Text.StringBuilder 2048;[void][UiWinV4]::GetWindowText($h,$sb,$sb.Capacity);$rows.Add([pscustomobject]@{pid=[int]$winPid;hwnd=$h.ToInt64();title=$sb.ToString()})};return $true}
  [UiWinV4]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null;return @($rows)
}
function Close-Hwnd([int64]$Hwnd){$h=[IntPtr]$Hwnd;$before=[UiWinV4]::IsWindow($h);$sent=$false;if($before){$sent=[UiWinV4]::PostMessage($h,0x0010,[IntPtr]::Zero,[IntPtr]::Zero);Start-Sleep -Milliseconds 800};$after=[UiWinV4]::IsWindow($h);[pscustomobject]@{before=$before;sent=$sent;after=$after;closed=($before-and-not$after)}}
function Close-CdpTarget([int]$Port,[string]$TargetId){try{if($Port-le0-or-not$TargetId){return [pscustomobject]@{state='BAD_TARGET'}};$list=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 3);if(-not($list|Where-Object{[string]$_.id-eq$TargetId})){return [pscustomobject]@{state='ALREADY_CLOSED'}};[void](Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$Port/json/close/$TargetId") -TimeoutSec 5);Start-Sleep -Milliseconds 500;$left=@(Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/json/list") -TimeoutSec 3|Where-Object{[string]$_.id-eq$TargetId});[pscustomobject]@{state=$(if($left.Count-eq0){'CLOSED'}else{'STILL_OPEN'})}}catch{[pscustomobject]@{state=('ERROR:'+$_.Exception.Message)}}}
function Remote-ProcessPresent{try{return (@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)desktop-commander'-and[string]$_.CommandLine-match'(?i)(?:^|\s)remote(?:\s|$)'}).Count-gt0)}catch{return $false}}
function Waiting-AuthPid([int]$Pid,$Items){foreach($i in @($Items)){try{if([int]$i.pid-eq$Pid-and[string]$i.state-eq'WAITING_USER'-and-not[bool]$i.completed){return $true}}catch{}};return $false}
$items=@();if(Test-Path $Registry){try{$items=@(Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json)}catch{}}
$results=@();$eligible=0;$closed=0
foreach($i in $items){
 $owner=[string]$i.owner;if($AllowedOwners-notcontains$owner){continue};$kind=[string]$i.kind;$keep=[bool]$i.keepOpen;$complete=[bool]$i.completed;$ack=[bool]$i.resultAckReadback
 $isRemoteShell=($owner-eq'REMOTE_DC'-and$kind-eq'PROCESS_WINDOW'-and([string]$i.processName-match'(?i)powershell|pwsh|cmd|windowsterminal'))
 $normalEligible=($complete-and$ack-and-not$keep-and(Grace-Passed $i));$remoteShellEligible=($isRemoteShell-and-not$keep-and(Grace-Passed $i))
 if(-not($normalEligible-or$remoteShellEligible)){continue};$eligible++
 if($kind-eq'PROCESS_WINDOW'){$procId=0;try{$procId=[int]$i.pid}catch{};if($procId-le0){continue};$wins=Get-TopWindows $procId;if($wins.Count-eq0){$results+=[pscustomobject]@{runId=[string]$i.runId;kind=$kind;pid=$procId;state='ALREADY_NOT_VISIBLE';closed=0};continue};$n=0;foreach($w in $wins){$r=Close-Hwnd ([int64]$w.hwnd);if($r.closed){$n++;$closed++}};$results+=[pscustomobject]@{runId=[string]$i.runId;kind=$kind;pid=$procId;topWindowsBefore=$wins.Count;closed=$n;state=$(if($n-eq$wins.Count){'CLOSED_ALL_HWND'}else{'PARTIAL'})}}
 elseif($kind-eq'CDP_TARGET'){$port=0;try{$port=[int]$i.port}catch{};$r=Close-CdpTarget $port ([string]$i.targetId);if($r.state-eq'CLOSED'){$closed++};$results+=[pscustomobject]@{runId=[string]$i.runId;kind=$kind;port=$port;targetId=[string]$i.targetId;state=$r.state}}
}
$authPattern='(?i)Desktop Commander Remote MCP|NAVER|네이버|NICE|i-?PIN|본인.?인증|Google 계정|카카오계정|카카오 계정'
$autoEdge=@();try{$autoEdge=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-match'(?i)mcp\.desktopcommander\.app/device/verify|device/verify\?user_code'})}catch{}
$authActions=@();$fg=[UiWinV4]::GetForegroundWindow().ToInt64()
foreach($ep in $autoEdge){$procId=[int]$ep.ProcessId;$wins=@(Get-TopWindows $procId|Where-Object{[string]$_.title-match$authPattern});if($wins.Count-eq0){continue};$waiting=Waiting-AuthPid $procId $items;$procAge=0;try{$procAge=((Get-Date)-[Management.ManagementDateTimeConverter]::ToDateTime([string]$ep.CreationDate)).TotalSeconds}catch{};if($waiting){$authActions+=[pscustomobject]@{pid=$procId;found=$wins.Count;action='PROTECT_WAITING_USER_CANONICAL';closed=0};continue};$toClose=@();if($wins.Count-gt1){$toClose=@($wins|Where-Object{[int64]$_.hwnd-ne$fg});if($toClose.Count-eq0){$toClose=@($wins|Select-Object -Skip 1)}}elseif(-not$PreflightAuth-and$procAge-ge$GraceSeconds-and(Remote-ProcessPresent)-and([string]$wins[0].title-match'(?i)Desktop Commander Remote MCP')){$toClose=@($wins)};$n=0;foreach($w in $toClose){$r=Close-Hwnd ([int64]$w.hwnd);if($r.closed){$n++;$closed++}};$authActions+=[pscustomobject]@{pid=$procId;found=$wins.Count;foregroundHwnd=$fg;processAgeSec=[math]::Round($procAge,0);action=$(if($toClose.Count-gt0){'DEDUP_CLOSE_NONCANONICAL'}elseif($wins.Count-gt1){'DUPLICATE_FOUND_CANONICAL_ONLY'}else{'SINGLE_UNREGISTERED_AUTH_PROTECTED'});closed=$n}}
Save-Json $AuthReceipt ([ordered]@{ok=$true;version=$Version;time=(Get-Date).ToString('o');preflight=[bool]$PreflightAuth;actions=$authActions})
$out=[ordered]@{ok=$true;version=$Version;time=(Get-Date).ToString('o');registryCount=$items.Count;eligibleCount=$eligible;closedCount=$closed;authProcessCount=$autoEdge.Count;authActions=$authActions;results=$results;falseClosePolicy='USER_CHROME_CHATGPT_PINTEREST_KEEP_OPEN_WAITING_USER_PROTECTED';closeMethod='HWND_WM_CLOSE_OR_CDP_TARGET_ONLY_NO_BROWSER_ROOT_KILL'}
Save-Json $Receipt $out;$out|ConvertTo-Json -Depth 50 -Compress;exit 0
