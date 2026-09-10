param([switch]$Apply)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WORKLOAD_ADMISSION_GOVERNOR_V2_PID_SAFE_20260910'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$ReceiptPath=Join-Path $Root 'WORKLOAD_ADMISSION_GOVERNOR_LAST.json'
$InactiveGovernor=Join-Path $Root 'InactiveProcessGovernor.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$ProtectedNames='(?i)^(googledrivefs|chrome|chatgpt|codex|explorer|dwm|taskmgr|commonagent|phoneexperiencehost|textinputhost|searchhost|startmenuexperiencehost|shellexperiencehost|msedgewebview2)$'
$ProtectedCmd='(?i)desktop-commander|HomeDesignLocalWatchdog|CentralAgent(Tab|Power|Auto)|CentralTabAutoRecovery|AgentBootstrap|PowerContinuity|GoogleDriveFS|codex|NotebookAuditPack|HomeDesignLocalAgent|HomeDesignLocalCommandHost'

function Save-Json($o){try{$o|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{}}
function Get-ProcSnapshot{
  $perf=@{};try{Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue|ForEach-Object{$perf[[int]$_.IDProcess]=$_}}catch{}
  $cim=@{};try{Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|ForEach-Object{$cim[[int]$_.ProcessId]=$_}}catch{}
  $rows=@();foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){
    try{$procId=[int]$p.Id;if($procId-le4){continue};$pf=$perf[$procId];$ci=$cim[$procId];$cmd=$(if($ci){[string]$ci.CommandLine}else{''});$name=[string]$p.ProcessName;$main=[int64]$p.MainWindowHandle;$protected=[bool]($name-match$ProtectedNames-or$cmd-match$ProtectedCmd);$rows+=[pscustomobject]@{pid=$procId;name=$name;cpuPct=$(if($pf){[double]$pf.PercentProcessorTime}else{0});workingSetMb=[math]::Round($p.WorkingSet64/1MB,1);ioBytesSec=$(if($pf){[double]$pf.IODataBytesPersec+[double]$pf.IOOtherBytesPersec}else{0});mainHwnd=$main;hasWindow=[bool]($main-ne0);protected=$protected;cmd=$cmd}}
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
function Admission([array]$s){
  $cpu=($s|Measure-Object cpuPct -Average).Average;$mem=($s|Measure-Object memoryUsedPct -Average).Average;$disk=($s|Measure-Object diskPct -Average).Average
  $level='GREEN';$reason=@()
  if($cpu-ge85-or$mem-ge90-or$disk-ge90){$level='RED'}elseif($cpu-ge70-or$mem-ge82-or$disk-ge75){$level='YELLOW'}
  if($cpu-ge70){$reason+='CPU'};if($mem-ge82){$reason+='MEMORY'};if($disk-ge75){$reason+='DISK'}
  [pscustomobject]@{level=$level;avgCpuPct=[math]::Round($cpu,1);avgMemoryUsedPct=[math]::Round($mem,1);avgDiskPct=[math]::Round($disk,1);reason=@($reason);parallelPolicy=$(switch($level){'GREEN'{'PARALLEL_OK'}'YELLOW'{'LIGHT_PARALLEL_ONLY'}default{'BLOCK_NEW_PARALLEL_AND_CLEAN_STALE'}})}
}
function Edge-State([array]$procs){
  $edge=@($procs|Where-Object{$_.name-eq'msedge'});$web=@($procs|Where-Object{$_.name-eq'msedgewebview2'});$visible=@($edge|Where-Object{$_.hasWindow});$roots=@($edge|Where-Object{[string]$_.cmd-notmatch'(?i)--type='})
  $pol='HKCU:\Software\Policies\Microsoft\Edge';$sb=$null;$bg=$null;try{$x=Get-ItemProperty $pol -ErrorAction SilentlyContinue;$sb=$x.StartupBoostEnabled;$bg=$x.BackgroundModeEnabled}catch{}
  [pscustomobject]@{edgeProcessCount=$edge.Count;edgeRootCount=$roots.Count;visibleEdgeWindows=$visible.Count;webView2ProcessCount=$web.Count;startupBoostPolicy=$sb;backgroundModePolicy=$bg;standaloneAutostartCandidate=[bool]($edge.Count-gt0-and$visible.Count-eq0);webView2Protected=$true}
}
function Apply-EdgeNoAutostart{
  $o=[ordered]@{applied=$false;startupBoostDisabled=$false;backgroundModeDisabled=$false;error=''}
  try{$pol='HKCU:\Software\Policies\Microsoft\Edge';New-Item -Path $pol -Force|Out-Null;New-ItemProperty -Path $pol -Name StartupBoostEnabled -PropertyType DWord -Value 0 -Force|Out-Null;New-ItemProperty -Path $pol -Name BackgroundModeEnabled -PropertyType DWord -Value 0 -Force|Out-Null;$o.applied=$true;$o.startupBoostDisabled=$true;$o.backgroundModeDisabled=$true}catch{$o.error=$_.Exception.Message};[pscustomobject]$o
}

$samples=@();for($i=0;$i-lt3;$i++){$samples+=Get-SystemSnapshot;if($i-lt2){Start-Sleep -Seconds 2}}
$proc=Get-ProcSnapshot;$ad=Admission $samples;$edgeBefore=Edge-State $proc
$edgeApply=$(if($Apply){Apply-EdgeNoAutostart}else{[pscustomobject]@{applied=$false;startupBoostDisabled=$false;backgroundModeDisabled=$false;error='NOT_REQUESTED'}})
$cleanup=$null
if($Apply-and$ad.level-eq'RED'-and(Test-Path $InactiveGovernor)){
  try{$raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $InactiveGovernor 2>&1|Out-String;try{$cleanup=$raw|ConvertFrom-Json}catch{$cleanup=[pscustomobject]@{ok=$false;raw=$raw}}}catch{$cleanup=[pscustomobject]@{ok=$false;error=$_.Exception.Message}}
}
$afterSamples=@();for($i=0;$i-lt2;$i++){$afterSamples+=Get-SystemSnapshot;if($i-lt1){Start-Sleep -Seconds 2}}
$afterProc=Get-ProcSnapshot;$edgeAfter=Edge-State $afterProc;$afterAd=Admission $afterSamples
$top=@($afterProc|Sort-Object @{Expression='cpuPct';Descending=$true},@{Expression='workingSetMb';Descending=$true}|Select-Object -First 20 pid,name,cpuPct,workingSetMb,ioBytesSec,mainHwnd,hasWindow,protected,cmd)
$out=[ordered]@{ok=$true;version=$Version;time=(Get-Date).ToString('o');apply=[bool]$Apply;beforeSamples=$samples;admissionBefore=$ad;edgeBefore=$edgeBefore;edgePolicyApply=$edgeApply;cleanupInvoked=[bool]($null-ne$cleanup);cleanup=$cleanup;afterSamples=$afterSamples;admissionAfter=$afterAd;edgeAfter=$edgeAfter;topProcesses=$top;protectedRule='RemoteDC/current HomeDesign run/Drive/Chrome/ChatGPT/Codex/watchdog/PowerShell lineage protected; msedgewebview2 protected; no process-name broad kill';policy='3_SAMPLE_ADMISSION;GREEN_PARALLEL;YELLOW_LIGHT_ONLY;RED_BLOCK_NEW_PARALLEL+RUN_EXISTING_SAFE_INACTIVE_GOVERNOR;EDGE_STARTUP_BOOST_AND_BACKGROUND_MODE_DISABLED_WHEN_APPLY;NO_WEBVIEW2_BROAD_KILL'}
Save-Json $out
try{$r=Get-Content $ReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$r.version-ne$Version){throw 'PERSISTED_RECEIPT_VERSION_MISMATCH'}}catch{Write-Error $_;exit 5}
$out|ConvertTo-Json -Depth 40 -Compress;exit 0
