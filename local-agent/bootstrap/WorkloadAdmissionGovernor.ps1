param([switch]$Apply,[switch]$ShowTaskManager)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WORKLOAD_ADMISSION_GOVERNOR_V3_DUPLICATE_WINDOW_GUARD_20260910'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$ReceiptPath=Join-Path $Root 'WORKLOAD_ADMISSION_GOVERNOR_LAST.json'
$InactiveGovernor=Join-Path $Root 'InactiveProcessGovernor.ps1'
$WindowStatePath=Join-Path $Root 'WINDOW_ACTIVITY_STATE.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$ProtectedNames='(?i)^(googledrivefs|chrome|chatgpt|codex|explorer|dwm|taskmgr|commonagent|phoneexperiencehost|textinputhost|searchhost|startmenuexperiencehost|shellexperiencehost|msedgewebview2)$'
$ProtectedCmd='(?i)desktop-commander|HomeDesignLocalWatchdog|CentralAgent(Tab|Power|Auto)|CentralTabAutoRecovery|AgentBootstrap|PowerContinuity|GoogleDriveFS|codex|NotebookAuditPack|HomeDesignLocalAgent|HomeDesignLocalCommandHost'
$TerminalStates='(?i)^(COMPLETE|COMPLETED|DONE|CLOSED|STALE|SUPERSEDED|ABANDONED|EXPIRED|FAILED|CANCELLED|CANCELED)$'

function Save-Json($o){try{$o|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{}}
function Get-ProcSnapshot{
  $perf=@{};try{Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue|ForEach-Object{$perf[[int]$_.IDProcess]=$_}}catch{}
  $cim=@{};try{Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|ForEach-Object{$cim[[int]$_.ProcessId]=$_}}catch{}
  $rows=@();foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){
    try{$procId=[int]$p.Id;if($procId-le4){continue};$pf=$perf[$procId];$ci=$cim[$procId];$cmd=$(if($ci){[string]$ci.CommandLine}else{''});$name=[string]$p.ProcessName;$main=[int64]$p.MainWindowHandle;$protected=[bool]($name-match$ProtectedNames-or$cmd-match$ProtectedCmd);$rows+=[pscustomobject]@{pid=$procId;parentPid=$(if($ci){[int]$ci.ParentProcessId}else{0});name=$name;cpuPct=$(if($pf){[double]$pf.PercentProcessorTime}else{0});workingSetMb=[math]::Round($p.WorkingSet64/1MB,1);ioBytesSec=$(if($pf){[double]$pf.IODataBytesPersec+[double]$pf.IOOtherBytesPersec}else{0});mainHwnd=$main;hasWindow=[bool]($main-ne0);protected=$protected;cmd=$cmd}}
    catch{}
  };return @($rows)
}
function Get-SystemSnapshot{
  $os=Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
  $cpu=Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue|Measure-Object LoadPercentage -Average
  $disk=0;try{$d=Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue|Where-Object{$_.Name-eq'_Total'}|Select-Object -First 1;if($d){$disk=[double]$d.PercentDiskTime}}catch{}
  $net=0;try{$n=Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue;$net=[double](($n|Measure-Object BytesTotalPersec -Sum).Sum)}catch{}
  [pscustomobject]@{time=(Get-Date).ToString('o');cpuPct=[math]::Round([double]$cpu.Average,1);memoryUsedPct=$(if($os){[math]::Round((1-($os.FreePhysicalMemory/$os.TotalVisibleMemorySize))*100,1)}else{0});freeMb=$(if($os){[math]::Round($os.FreePhysicalMemory/1024,0)}else{0});diskPct=[math]::Round($disk,1);networkBytesSec=[math]::Round($net,0);processCount=@(Get-Process -ErrorAction SilentlyContinue).Count}
}
function Admission([array]$s,[int]$DuplicatePressure){
  $cpu=($s|Measure-Object cpuPct -Average).Average;$mem=($s|Measure-Object memoryUsedPct -Average).Average;$disk=($s|Measure-Object diskPct -Average).Average
  $level='GREEN';$reason=@()
  if($cpu-ge85-or$mem-ge90-or$disk-ge90-or$DuplicatePressure-ge3){$level='RED'}elseif($cpu-ge70-or$mem-ge82-or$disk-ge75-or$DuplicatePressure-gt0){$level='YELLOW'}
  if($cpu-ge70){$reason+='CPU'};if($mem-ge82){$reason+='MEMORY'};if($disk-ge75){$reason+='DISK'};if($DuplicatePressure-gt0){$reason+=('AUTOMATION_DUPLICATES='+$DuplicatePressure)}
  [pscustomobject]@{level=$level;avgCpuPct=[math]::Round($cpu,1);avgMemoryUsedPct=[math]::Round($mem,1);avgDiskPct=[math]::Round($disk,1);duplicatePressure=$DuplicatePressure;reason=@($reason);parallelPolicy=$(switch($level){'GREEN'{'PARALLEL_OK'}'YELLOW'{'LIGHT_PARALLEL_ONLY'}default{'BLOCK_NEW_PARALLEL_AND_CLEAN_STALE'}})}
}
function Edge-State([array]$procs){
  $edge=@($procs|Where-Object{$_.name-eq'msedge'});$web=@($procs|Where-Object{$_.name-eq'msedgewebview2'});$visible=@($edge|Where-Object{$_.hasWindow});$roots=@($edge|Where-Object{[string]$_.cmd-notmatch'(?i)--type='})
  $pol='HKCU:\Software\Policies\Microsoft\Edge';$sb=$null;$bg=$null;try{$x=Get-ItemProperty $pol -ErrorAction SilentlyContinue;$sb=$x.StartupBoostEnabled;$bg=$x.BackgroundModeEnabled}catch{}
  [pscustomobject]@{edgeProcessCount=$edge.Count;edgeRootCount=$roots.Count;visibleEdgeWindows=$visible.Count;webView2ProcessCount=$web.Count;startupBoostPolicy=$sb;backgroundModePolicy=$bg;standaloneAutostartCandidate=[bool]($edge.Count-gt0-and$visible.Count-eq0);webView2Protected=$true;note='Edge multi-process children are normal and are not treated as duplicates; only standalone root/visible duplicate windows are audited.'}
}
function Apply-EdgeNoAutostart{
  $o=[ordered]@{applied=$false;startupBoostDisabled=$false;backgroundModeDisabled=$false;error=''}
  try{$pol='HKCU:\Software\Policies\Microsoft\Edge';New-Item -Path $pol -Force|Out-Null;New-ItemProperty -Path $pol -Name StartupBoostEnabled -PropertyType DWord -Value 0 -Force|Out-Null;New-ItemProperty -Path $pol -Name BackgroundModeEnabled -PropertyType DWord -Value 0 -Force|Out-Null;$o.applied=$true;$o.startupBoostDisabled=$true;$o.backgroundModeDisabled=$true}catch{$o.error=$_.Exception.Message};[pscustomobject]$o
}
function Normalize-Title([string]$Title){if([string]::IsNullOrWhiteSpace($Title)){return ''};return (($Title.Trim().ToLowerInvariant()-replace'\s+',' '))}
function Get-DuplicateWindowState{
  $state=$null;try{if(Test-Path $WindowStatePath){$state=Get-Content $WindowStatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
  if(-not$state-or-not$state.windows){return [pscustomobject]@{windowStateAvailable=$false;allDuplicateGroups=@();automationDuplicateGroups=@();automationDuplicatePressure=0;openReuseRequired=$false;safeCleanupCandidates=0}}
  $rows=@($state.windows|Where-Object{$_.title}|ForEach-Object{[pscustomobject]@{key=[string]$_.key;pid=[int]$_.pid;hwnd=[int64]$_.hwnd;process=[string]$_.process;title=[string]$_.title;norm=(Normalize-Title ([string]$_.title));foreground=[bool]$_.foreground;registered=[bool]$_.registered;registeredState=[string]$_.registeredState;registeredOwner=[string]$_.registeredOwner;unchangedSamples=[int]$_.unchangedSamples;firstSeenUtc=[string]$_.firstSeenUtc}})
  $all=@();$auto=@();$pressure=0;$safe=0
  foreach($g in @($rows|Group-Object -Property {([string]$_.process).ToLowerInvariant()+'|'+[string]$_.norm}|Where-Object{$_.Count-gt1})){
    $members=@($g.Group|Sort-Object firstSeenUtc);$registered=@($members|Where-Object{$_.registered});$terminal=@($registered|Where-Object{$_.registeredState-match$TerminalStates-and-not$_.foreground});$owners=@($registered|Select-Object -ExpandProperty registeredOwner -Unique)
    $item=[pscustomobject]@{signature=[string]$g.Name;count=$members.Count;process=[string]$members[0].process;title=[string]$members[0].title;registeredCount=$registered.Count;owners=$owners;terminalCleanupCandidates=$terminal.Count;hwnds=@($members|Select-Object -ExpandProperty hwnd);pids=@($members|Select-Object -ExpandProperty pid);reuseExistingActive=[bool](@($registered|Where-Object{$_.registeredState-notmatch$TerminalStates}).Count-gt0)}
    $all+=$item
    if($registered.Count-gt1){$auto+=$item;$pressure+=($registered.Count-1);$safe+=$terminal.Count}
  }
  [pscustomobject]@{windowStateAvailable=$true;allDuplicateGroups=$all;automationDuplicateGroups=$auto;automationDuplicatePressure=$pressure;openReuseRequired=[bool]($pressure-gt0);safeCleanupCandidates=$safe}
}
function Get-AutomationSingletonWarnings([array]$procs){
  $rules=@(
    @{name='POWER_GUARD';pattern='(?i)CentralAgentPowerContinuityGuard\.ps1'},
    @{name='BOOTSTRAP_LOOP';pattern='(?i)AgentBootstrap\.ps1.*(?:^|\s)-Loop(?:\s|$)'},
    @{name='LOCAL_WATCHDOG';pattern='(?i)HomeDesignLocalWatchdog\.ps1'}
  );$out=@();foreach($r in $rules){$m=@($procs|Where-Object{[string]$_.cmd-match$r.pattern});if($m.Count-gt1){$out+=[pscustomobject]@{family=$r.name;count=$m.Count;pids=@($m|Select-Object -ExpandProperty pid);action='REPORT_ONLY_UNTIL_OWNER_LINEAGE_RECHECK'}}};return @($out)
}
function Invoke-ExistingInactiveCleanup{
  if(-not(Test-Path $InactiveGovernor)){return [pscustomobject]@{ok=$false;error='INACTIVE_GOVERNOR_MISSING'}}
  try{$raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $InactiveGovernor 2>&1|Out-String;try{return $raw|ConvertFrom-Json}catch{return [pscustomobject]@{ok=$false;raw=$raw}}}catch{return [pscustomobject]@{ok=$false;error=$_.Exception.Message}}
}

$taskmgrOpenedByUs=$false;$taskmgrPid=0
if($ShowTaskManager){try{$existing=@(Get-Process taskmgr -ErrorAction SilentlyContinue);if($existing.Count-eq0){$tp=Start-Process taskmgr.exe -PassThru;$taskmgrOpenedByUs=$true;$taskmgrPid=[int]$tp.Id;Start-Sleep -Seconds 2}}catch{}}
$proc=Get-ProcSnapshot;$dupBefore=Get-DuplicateWindowState
$samples=@();for($i=0;$i-lt3;$i++){$samples+=Get-SystemSnapshot;if($i-lt2){Start-Sleep -Seconds 2}}
$ad=Admission $samples ([int]$dupBefore.automationDuplicatePressure);$edgeBefore=Edge-State $proc
$edgeApply=$(if($Apply){Apply-EdgeNoAutostart}else{[pscustomobject]@{applied=$false;startupBoostDisabled=$false;backgroundModeDisabled=$false;error='NOT_REQUESTED'}})
$cleanup=$null
if($Apply-and(($ad.level-eq'RED')-or([int]$dupBefore.safeCleanupCandidates-gt0))){$cleanup=Invoke-ExistingInactiveCleanup}
if($taskmgrOpenedByUs-and$taskmgrPid-gt0){try{Stop-Process -Id $taskmgrPid -ErrorAction SilentlyContinue}catch{}}
$afterSamples=@();for($i=0;$i-lt2;$i++){$afterSamples+=Get-SystemSnapshot;if($i-lt1){Start-Sleep -Seconds 2}}
$afterProc=Get-ProcSnapshot;$dupAfter=Get-DuplicateWindowState;$edgeAfter=Edge-State $afterProc;$afterAd=Admission $afterSamples ([int]$dupAfter.automationDuplicatePressure)
$top=@($afterProc|Sort-Object @{Expression='cpuPct';Descending=$true},@{Expression='workingSetMb';Descending=$true}|Select-Object -First 20 pid,parentPid,name,cpuPct,workingSetMb,ioBytesSec,mainHwnd,hasWindow,protected,cmd)
$singletons=Get-AutomationSingletonWarnings $afterProc
$out=[ordered]@{ok=$true;version=$Version;time=(Get-Date).ToString('o');apply=[bool]$Apply;taskManagerVisualAuditRequested=[bool]$ShowTaskManager;taskManagerOpenedByGovernor=$taskmgrOpenedByUs;taskManagerOpenedPid=$taskmgrPid;beforeSamples=$samples;admissionBefore=$ad;duplicateWindowsBefore=$dupBefore;edgeBefore=$edgeBefore;edgePolicyApply=$edgeApply;cleanupInvoked=[bool]($null-ne$cleanup);cleanup=$cleanup;afterSamples=$afterSamples;admissionAfter=$afterAd;duplicateWindowsAfter=$dupAfter;automationSingletonWarnings=$singletons;edgeAfter=$edgeAfter;topProcesses=$top;protectedRule='RemoteDC/current HomeDesign run/Drive/Chrome/ChatGPT/Codex/watchdog/PowerShell lineage protected; msedgewebview2 protected; no process-name broad kill';duplicatePreventionRule='BEFORE_OPEN_REUSE_EXISTING_ACTIVE_AUTOMATION_WINDOW;REGISTERED_TERMINAL+INACTIVE>=300S MAY_CLOSE VIA EXISTING EXACT-PID/HWND GOVERNOR;UNREGISTERED/USER DUPLICATES REPORT_ONLY;EDGE CHILD PROCESSES NOT DUPLICATES';policy='3_SAMPLE_ADMISSION;GREEN_PARALLEL;YELLOW_LIGHT_ONLY;RED_BLOCK_NEW_PARALLEL;AUTOMATION_DUPLICATE_PRESSURE_AFFECTS_ADMISSION;EDGE_STARTUP_BOOST_AND_BACKGROUND_MODE_DISABLED_WHEN_APPLY;OPTIONAL_TASKMGR_VISUAL_AUDIT_CLOSES_ONLY_TASKMGR_OPENED_BY_US'}
Save-Json $out
try{$r=Get-Content $ReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$r.version-ne$Version){throw 'PERSISTED_RECEIPT_VERSION_MISMATCH'}}catch{Write-Error $_;exit 5}
$out|ConvertTo-Json -Depth 50 -Compress;exit 0
