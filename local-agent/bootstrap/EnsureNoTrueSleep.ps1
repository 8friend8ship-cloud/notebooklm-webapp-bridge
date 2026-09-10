param([switch]$Apply)
$ErrorActionPreference='Continue'
$Version='ENSURE_NO_TRUE_SLEEP_V1_20260910'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt=Join-Path $Root 'NO_TRUE_SLEEP_AUDIT_LAST.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Get-TaskActionsText($Task){
  try{return (($Task.Actions|ForEach-Object{([string]$_.Execute+' '+[string]$_.Arguments)}) -join ' | ')}catch{return ''}
}
function Is-NightTrigger($Task){
  try{foreach($t in @($Task.Triggers)){if($t.StartBoundary){$d=[datetime]$t.StartBoundary;if($d.Hour-ge1-and$d.Hour-lt5){return $true}}}}catch{}
  return $false
}
function Is-HomeDesignOwned($Task){
  $s=([string]$Task.TaskPath+[string]$Task.TaskName)
  return [bool]($s-match'(?i)HomeDesign|CentralAgent|DesktopCommander|NotebookAudit|AutoResume|LocalWatchdog')
}
function Is-SleepAction([string]$Action){
  return [bool]($Action-match'(?i)SetSuspendState|powrprof|shutdown\s+/h|shutdown\s+-h|psshutdown.*(?:-d|-h)|rundll32.*sleep|powercfg.*hibernate|sleepstudy.*hibernate')
}

$before=@();$disabled=@();$errors=@()
try{
  foreach($task in @(Get-ScheduledTask -ErrorAction Stop)){
    $a=Get-TaskActionsText $task
    $night=Is-NightTrigger $task
    $owned=Is-HomeDesignOwned $task
    $sleep=Is-SleepAction $a
    if($night-or$sleep){$before+=[pscustomobject]@{taskPath=$task.TaskPath;taskName=$task.TaskName;state=[string]$task.State;night0105=$night;homeDesignOwned=$owned;sleepAction=$sleep;action=$a}}
    if($Apply-and$owned-and$sleep){try{Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop|Out-Null;$disabled+=([string]$task.TaskPath+[string]$task.TaskName)}catch{$errors+=('TASK_DISABLE:'+$task.TaskName+':'+$_.Exception.Message)}}
  }
}catch{$errors+=('TASK_ENUM:'+$_.Exception.Message)}

$powerBefore='';$powerAfter=''
try{$powerBefore=(powercfg /getactivescheme 2>&1|Out-String)}catch{$errors+=('POWERCFG_READ:'+$_.Exception.Message)}
if($Apply){
  foreach($cmd in @(@('/change','standby-timeout-ac','0'),@('/change','standby-timeout-dc','0'),@('/change','hibernate-timeout-ac','0'),@('/change','hibernate-timeout-dc','0'))){try{& powercfg @cmd 2>&1|Out-Null;if($LASTEXITCODE-ne0){$errors+=('POWERCFG_EXIT_'+$LASTEXITCODE+':'+($cmd-join' '))}}catch{$errors+=('POWERCFG:'+($cmd-join' ')+':'+$_.Exception.Message)}}
}
try{$powerAfter=(powercfg /getactivescheme 2>&1|Out-String)}catch{$errors+=('POWERCFG_READ_AFTER:'+$_.Exception.Message)}

$out=[ordered]@{ok=($errors.Count-eq0);version=$Version;time=(Get-Date).ToString('o');apply=[bool]$Apply;nightOrSleepTasks=$before;disabledOwnedSleepTasks=$disabled;powerSchemeBefore=$powerBefore.Trim();powerSchemeAfter=$powerAfter.Trim();policy='SYSTEM_SLEEP_TIMEOUT_AC_DC=0;HIBERNATE_TIMEOUT_AC_DC=0;DISPLAY_TIMEOUT_UNCHANGED;ONLY_HOMEDESIGN_OWNED_SLEEP_TASKS_DISABLED;01_TO_05_AUDITED';errors=$errors}
$out|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $Receipt -Encoding UTF8
$out|ConvertTo-Json -Depth 20 -Compress
if($out.ok){exit 0}else{exit 4}
