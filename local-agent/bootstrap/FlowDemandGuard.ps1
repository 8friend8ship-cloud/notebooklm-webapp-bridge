param([switch]$Apply)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='FLOW_DEMAND_GUARD_V1_20260910'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
$Receipt=Join-Path $Root 'FLOW_DEMAND_GUARD_LAST.json'
$StaleMinutes=15
$NoDemandCloseMinutes=5
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Terminal='(?i)^(COMPLETE|COMPLETED|DONE|CLOSED|STALE|SUPERSEDED|ABANDONED|EXPIRED|FAILED|CANCELLED|CANCELED)$'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class HDForeground { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId); }
"@ -ErrorAction SilentlyContinue
function Save($o){try{$o|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Receipt -Encoding UTF8}catch{}}
function Flatten($n){$out=@();$stack=New-Object System.Collections.Stack;foreach($x in @($n)){$stack.Push($x)};while($stack.Count){$x=$stack.Pop();if($null-eq$x){continue};if($x-is[System.Array]){foreach($a in $x){$stack.Push($a)};continue};$out+=,$x;foreach($p in @($x.PSObject.Properties)){if($p.Value -is [System.Management.Automation.PSCustomObject] -or $p.Value -is [System.Array]){$stack.Push($p.Value)}}};@($out)}
function ObjText($o){try{return (($o.PSObject.Properties|ForEach-Object{[string]$_.Name+'='+[string]$_.Value})-join';')}catch{return ''}}
function ObjState($o){foreach($k in @('state','status','runState','jobState')){try{$v=[string]$o.$k;if($v){return $v}}catch{}};return ''}
function ObjTime($o){$best=$null;foreach($k in @('progressAt','heartbeatAt','updatedAt','lastActivityAt','claimedAt','startedAt','createdAt')){try{$v=$o.$k;if($v){$d=[datetime]$v;if(-not$best-or$d-gt$best){$best=$d}}}catch{}};return $best}
function FlowDemand{
 $items=@();try{if(Test-Path $Registry){$raw=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;foreach($o in @(Flatten $raw)){$text=ObjText $o;if($text-match'(?i)(\bFLOW\b|labs\.google/fx/tools/flow|flowlane|flow_job|flow-worker)'){$state=ObjState $o;if(-not$state-or$state-notmatch$Terminal){$t=ObjTime $o;$age=$(if($t){[math]::Round(((Get-Date)-$t).TotalMinutes,1)}else{$null});$items+=[pscustomobject]@{state=$state;ageMinutes=$age;text=$text.Substring(0,[Math]::Min(500,$text.Length))}}}}}}catch{}
 $fresh=@($items|Where-Object{$null-ne$_.ageMinutes-and[double]$_.ageMinutes-le$StaleMinutes});[pscustomobject]@{active=@($items).Count;fresh=@($fresh).Count;items=@($items|Select-Object -First 20)}
}
function DedicatedFlowProc{
 try{@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine-like('*'+$DedicatedUserData+'*') -and [string]$_.CommandLine-match'(?i)--remote-debugging-port=9224'})}catch{@()}
}
function RootFlowProc([array]$p){@($p|Where-Object{[string]$_.CommandLine-notmatch'(?i)--type='})}
function ForegroundPid{try{$h=[HDForeground]::GetForegroundWindow();[uint32]$p=0;[void][HDForeground]::GetWindowThreadProcessId($h,[ref]$p);return [int]$p}catch{return 0}}
function CdpHealthy{try{$v=Invoke-RestMethod 'http://127.0.0.1:9224/json/version' -TimeoutSec 2;[bool]$v.Browser}catch{$false}}
function PreviousHoldSince([string]$decision){try{if(Test-Path $Receipt){$j=Get-Content $Receipt -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$j.decision-eq$decision-and$j.holdSince){return [datetime]$j.holdSince}}}catch{};return (Get-Date)}
$d=FlowDemand;$procs=@(DedicatedFlowProc);$roots=@(RootFlowProc $procs);$fg=ForegroundPid;$foregroundOwned=[bool](@($procs|Where-Object{[int]$_.ProcessId-eq$fg}).Count-gt0);$cdp=CdpHealthy
$decision='HOLD_NO_DEMAND';$allowOpen=$false
if($d.active-gt0-and$d.fresh-gt0){$decision='ALLOW_FLOW_RUNTIME';$allowOpen=$true}elseif($d.active-gt0){$decision='HOLD_STALE_PROGRESS'}
$holdSince=$(if($allowOpen){$null}else{PreviousHoldSince $decision});$holdMin=$(if($holdSince){[math]::Round(((Get-Date)-$holdSince).TotalMinutes,1)}else{0});$stopped=@()
if($Apply-and-not$allowOpen-and-not$foregroundOwned-and$holdMin-ge$NoDemandCloseMinutes){foreach($r in $roots){try{$pid=[int]$r.ProcessId;if($pid-gt0){& taskkill.exe /PID $pid /T /F 2>$null|Out-Null;if($LASTEXITCODE-eq0){$stopped+=$pid}}}catch{}};if($stopped.Count){Start-Sleep -Seconds 1;$procs=@(DedicatedFlowProc);$roots=@(RootFlowProc $procs);$cdp=CdpHealthy}}
$out=[ordered]@{ok=$true;version=$Version;time=(Get-Date).ToString('o');decision=$decision;allowOpen=$allowOpen;activeFlowDemand=$d.active;freshFlowDemand=$d.fresh;demandEvidence=$d.items;staleMinutes=$StaleMinutes;holdSince=$(if($holdSince){$holdSince.ToString('o')}else{''});holdMinutes=$holdMin;dedicatedFlowProcessCount=$procs.Count;dedicatedFlowRootCount=$roots.Count;dedicatedFlowRootPids=@($roots|ForEach-Object{[int]$_.ProcessId});cdp9224Healthy=$cdp;foregroundPid=$fg;automationFlowForeground=$foregroundOwned;apply=[bool]$Apply;stoppedExactRootPids=$stopped;manualWindowProtected=$true;normalChromeTouched=$false;policy='NO_ACTIVE_DEMAND=>NO_REOPEN;STALE_PROGRESS=>CIRCUIT_BREAKER;ACTIVE_FRESH=>REUSE_OR_OPEN_ONE;ONLY_DEDICATED_9224_PROFILE_MANAGED;FOREGROUND_MANUAL_USE_PROTECTED'}
Save $out;$out|ConvertTo-Json -Depth 40 -Compress;exit 0