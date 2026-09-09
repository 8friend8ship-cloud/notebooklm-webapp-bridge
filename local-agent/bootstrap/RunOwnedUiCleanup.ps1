param([switch]$PreflightAuth)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='RUN_OWNED_UI_CLEANUP_V7_STACK_FLATTEN_20260910'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$Receipt=Join-Path $Root 'RUN_OWNED_UI_CLEANUP_LAST.json'
$GraceSeconds=300
$AllowedOwners=@('CENTRAL_AGENT','REMOTE_DC','LOCAL_RUNNER','CFT_WORKER')
New-Item -ItemType Directory -Force -Path $Root|Out-Null
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class UiWinV6 {
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
}
'@ -ErrorAction SilentlyContinue
function Save-Json([string]$Path,$Object){try{$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function Parse-Time($x){foreach($n in @('verifiedAt','completedAt','resultAckAt','openedAt','createdAt')){try{$v=$x.$n;if($v){return [datetimeoffset]::Parse([string]$v)}}catch{}};return $null}
function Grace-Passed($x){$t=Parse-Time $x;if(-not$t){return $true};return (((Get-Date).ToUniversalTime()-$t.UtcDateTime).TotalSeconds-ge$GraceSeconds)}
function Expand-Registry($Node){
 $result=@()
 $stack=New-Object System.Collections.Stack
 foreach($n in @($Node)){$stack.Push($n)}
 while($stack.Count-gt0){
  $x=$stack.Pop();if($null-eq$x){continue}
  if($x -is [System.Array]){foreach($a in $x){$stack.Push($a)};continue}
  $names=@($x.PSObject.Properties.Name)
  if($names -contains 'runId'){$result+=,$x;continue}
  if($names -contains 'value'){foreach($a in @($x.value)){$stack.Push($a)}}
 }
 return @($result)
}
function Close-Hwnd([int64]$Hwnd,[int]$ExpectedPid){
 $h=[IntPtr]$Hwnd
 if(-not[UiWinV6]::IsWindow($h)){return [pscustomobject]@{state='ALREADY_CLOSED';closed=$true}}
 [uint32]$actual=0;[void][UiWinV6]::GetWindowThreadProcessId($h,[ref]$actual)
 if([int]$actual-ne$ExpectedPid){return [pscustomobject]@{state='HWND_OWNER_MISMATCH_PROTECTED';closed=$false}}
 [void][UiWinV6]::PostMessage($h,0x0010,[IntPtr]::Zero,[IntPtr]::Zero);Start-Sleep -Milliseconds 800
 $left=[UiWinV6]::IsWindow($h);return [pscustomobject]@{state=$(if($left){'STILL_VISIBLE'}else{'CLOSED_EXACT_HWND'});closed=(-not$left)}
}
function Close-Cdp([int]$Port,[string]$TargetId){try{if($Port-le0-or-not$TargetId){return 'BAD_TARGET'};$list=@(Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 3);if(-not($list|Where-Object{[string]$_.id-eq$TargetId})){return 'ALREADY_CLOSED'};[void](Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/json/close/$TargetId" -TimeoutSec 5);Start-Sleep -Milliseconds 500;$left=@(Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 3|Where-Object{[string]$_.id-eq$TargetId});if($left.Count-eq0){return 'CLOSED'}else{return 'STILL_OPEN'}}catch{return 'ERROR:'+ $_.Exception.Message}}
$raw=$null;$items=@();$parseError=''
try{if(Test-Path $Registry){$raw=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;$items=@(Expand-Registry $raw)}}catch{$parseError=$_.Exception.Message}
$results=@();$eligible=0;$closed=0
foreach($i in $items){
 $owner=[string]$i.owner;if($AllowedOwners-notcontains$owner){continue};$kind=[string]$i.kind;$keep=[bool]$i.keepOpen;$complete=[bool]$i.completed;$ack=[bool]$i.resultAckReadback
 $remoteShell=($owner-eq'REMOTE_DC'-and$kind-eq'PROCESS_WINDOW'-and([string]$i.processName-match'(?i)powershell|pwsh|cmd|windowsterminal'))
 $eligibleNow=(($complete-and$ack-and-not$keep-and(Grace-Passed $i))-or($remoteShell-and-not$keep-and(Grace-Passed $i)))
 if(-not$eligibleNow){continue};$eligible++
 if($kind-eq'PROCESS_WINDOW'){$pidValue=0;$hwndValue=0;try{$pidValue=[int]$i.pid}catch{};try{$hwndValue=[int64]$i.hwnd}catch{};if($pidValue-le0-or$hwndValue-le0){$results+=[pscustomobject]@{runId=[string]$i.runId;state='AMBIGUOUS_PROTECTED'};continue};$r=Close-Hwnd $hwndValue $pidValue;if($r.closed){$closed++};$results+=[pscustomobject]@{runId=[string]$i.runId;kind=$kind;pid=$pidValue;hwnd=$hwndValue;state=$r.state;closed=$r.closed}}
 elseif($kind-eq'CDP_TARGET'){$port=0;try{$port=[int]$i.port}catch{};$state=Close-Cdp $port ([string]$i.targetId);if($state-eq'CLOSED'){$closed++};$results+=[pscustomobject]@{runId=[string]$i.runId;kind=$kind;port=$port;targetId=[string]$i.targetId;state=$state}}
}
$out=[ordered]@{ok=([string]::IsNullOrEmpty($parseError));version=$Version;time=(Get-Date).ToString('o');registryRawCount=$(if($raw){@($raw).Count}else{0});registryFlatCount=$items.Count;parseError=$parseError;eligibleCount=$eligible;closedCount=$closed;results=$results;falseClosePolicy='EXACT_HWND_OWNER_RECHECK_OR_EXACT_CDP_TARGET;NO_PROCESS_FORCE_KILL';closeMethod='WM_CLOSE_EXACT_HWND_OR_CDP_TARGET_ONLY'}
Save-Json $Receipt $out;$out|ConvertTo-Json -Depth 50 -Compress;if($out.ok){exit 0}else{exit 4}
