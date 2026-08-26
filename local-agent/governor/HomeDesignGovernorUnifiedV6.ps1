param([switch]$Interactive)

$ErrorActionPreference='SilentlyContinue'

$Base       = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Control    = Join-Path $Base 'Control'
$StateDir   = Join-Path $Control 'State'
$Logs       = Join-Path $Control 'Logs'
$Archive    = Join-Path $Control 'DesktopArchive'
$Readback   = Join-Path $Control 'Readback'
$RuntimeDir = Join-Path $Base 'LocalAgent'
$GovPath    = Join-Path $Control 'HomeDesignGovernorUnifiedV6.ps1'
$LatestJson = Join-Path $StateDir 'LATEST_STATUS.json'
$LatestTxt  = Join-Path $StateDir 'LATEST_STATUS.txt'
$History    = Join-Path $StateDir 'ERROR_HISTORY.jsonl'
$Log        = Join-Path $Logs ('GOVERNOR_V6_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')

@($Control,$StateDir,$Logs,$Archive,$Readback,$RuntimeDir) | ForEach-Object {
  New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

function Log([string]$m){
  $line='['+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'] '+$m
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
  if($Interactive){ Write-Host $line }
}

function ReadJson([string]$p){
  try { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

function WriteHistory([string]$code,[string]$layer,[string]$detail,[string]$action){
  $obj=[ordered]@{at=(Get-Date).ToString('o');code=$code;layer=$layer;detail=$detail;action=$action}
  ($obj|ConvertTo-Json -Compress) | Add-Content -LiteralPath $History -Encoding UTF8
}

function GetRecentSameError([string]$code){
  if(-not (Test-Path $History)){ return 0 }
  $count=0
  foreach($line in Get-Content $History -Tail 50){
    try{$o=$line|ConvertFrom-Json;if($o.code -eq $code){$count++}}catch{}
  }
  return $count
}

function GetChromeInventory {
  $userData=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  $out=@()
  if(-not (Test-Path $userData)){ return @() }
  $profiles=Get-ChildItem $userData -Directory | Where-Object {$_.Name -eq 'Default' -or $_.Name -like 'Profile *'}
  foreach($profile in $profiles){
    $pref=ReadJson (Join-Path $profile.FullName 'Preferences')
    $settings=$null
    if($pref -and $pref.extensions -and $pref.extensions.settings){$settings=$pref.extensions.settings}
    $root=Join-Path $profile.FullName 'Extensions'
    if(-not (Test-Path $root)){continue}
    foreach($idDir in Get-ChildItem $root -Directory){
      $verDir=Get-ChildItem $idDir.FullName -Directory | Sort-Object Name -Descending | Select-Object -First 1
      if(-not $verDir){continue}
      $m=ReadJson (Join-Path $verDir.FullName 'manifest.json')
      if(-not $m){continue}
      $name=[string]$m.name
      if($name -like '__MSG_*__' -and $m.default_locale){
        $key=$name.Trim('_');if($key.StartsWith('MSG_')){$key=$key.Substring(4)}
        $msgs=ReadJson (Join-Path $verDir.FullName ("_locales\"+[string]$m.default_locale+"\messages.json"))
        if($msgs -and ($msgs.PSObject.Properties.Name -contains $key)){$name=[string]$msgs.$key.message}
      }
      $enabled=$null;$state=$null
      if($settings -and ($settings.PSObject.Properties.Name -contains $idDir.Name)){
        $entry=$settings.($idDir.Name)
        if($entry.PSObject.Properties.Name -contains 'state'){$state=$entry.state;try{$enabled=([int]$state -eq 1)}catch{}}
      }
      $out += [pscustomobject]@{profile=$profile.Name;id=$idDir.Name;name=$name;version=[string]$m.version;enabled=$enabled;state=$state;path=$verDir.FullName}
    }
  }
  @($out|Sort-Object name,version,profile)
}

function GetRuntime {
  $all=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'chrome|powershell|pwsh|node'} | Select-Object Name,ProcessId,ExecutablePath,CommandLine)
  $agent=@($all|Where-Object {$_.CommandLine -match 'HomeDesignLocalAgent|CommandHost|ChromeGovernor|CentralAppsScriptRunner|notebooklm-webapp-bridge|HomeDesignAutoResume'})
  $ded=@($all|Where-Object {$_.Name -match '^chrome' -and $_.CommandLine -match 'remote-debugging-port|HomeDesignAutomationV7|Chrome for Testing|CentralAppsScriptRunner|user-data-dir'})
  [ordered]@{agent_running=($agent.Count -gt 0);agent_processes=$agent;dedicated_chrome_running=($ded.Count -gt 0);dedicated_chrome_processes=$ded}
}

function InvokeSafeResume {
  $resume=Join-Path $RuntimeDir 'HomeDesignAutoResume.ps1'
  $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/HomeDesignAutoResume.ps1'
  try{
    if(-not (Test-Path $resume)){$u=$url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $resume -TimeoutSec 45;Log 'Downloaded safe resume runtime.'}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $resume | Out-Null
    Log 'Safe runtime self-heal invoked.';return $true
  }catch{Log ('Safe runtime self-heal failed: '+$_.Exception.Message);return $false}
}

function MoveDesktopArtifacts {
  $desktop=[Environment]::GetFolderPath('Desktop');if(-not (Test-Path $desktop)){return @()}
  $stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$moved=@()
  foreach($pat in @('CHROME_ALL_EXTENSIONS_*','CHROME_FLOW_HEALTH_RESULT*','RUN_AUDIT*.cmd','RUN_CHROME_FLOW_CONNECT*.cmd','FIND_AND_RUN_CHROME_FLOW_CONNECT*.cmd','RESUME_LOCAL_AGENT*.cmd','FINAL_RESUME_AGENT*.cmd','RUN_VIDEO_RUNTIME_RECOVERY*.cmd','VIDEO_RUNTIME_RECOVERY*_RESULT*')){
    foreach($i in Get-ChildItem $desktop -Filter $pat -Force -ErrorAction SilentlyContinue){if($i.PSIsContainer){continue};try{$dest=Join-Path $Archive ($stamp+'_'+$i.Name);Move-Item $i.FullName $dest -Force;$moved+=$i.FullName}catch{}}
  }
  foreach($pat in @('HomeDesignChromeAudit*','ChromeAudit*','ChromeFlowHealth*','LocalAgentRecovery*','VideoRuntimeRecovery*')){
    foreach($i in Get-ChildItem $desktop -Directory -Filter $pat -Force -ErrorAction SilentlyContinue){try{$dest=Join-Path $Archive ($stamp+'_'+$i.Name);Move-Item $i.FullName $dest;$moved+=$i.FullName}catch{}}
  }
  return $moved
}

function GetDriveCandidates {
  $list=[System.Collections.ArrayList]@()
  function Add([string]$p,[string]$src){if([string]::IsNullOrWhiteSpace($p)){return};try{$full=[IO.Path]::GetFullPath($p)}catch{$full=$p};if(Test-Path $full){if(-not ($list|Where-Object {$_.path -eq $full})){[void]$list.Add([pscustomobject]@{path=$full;source=$src})}}}
  foreach($d in Get-PSDrive -PSProvider FileSystem){foreach($p in @($d.Root,(Join-Path $d.Root 'My Drive'),(Join-Path $d.Root '내 드라이브'),(Join-Path $d.Root 'Google Drive'))){Add $p ('PSDrive:'+ $d.Name)}}
  foreach($p in @((Join-Path $env:USERPROFILE 'Google Drive'),(Join-Path $env:USERPROFILE 'My Drive'),(Join-Path $env:USERPROFILE '내 드라이브'))){Add $p 'CommonPath'}
  foreach($rp in @('HKCU:\Software\Google\DriveFS','HKCU:\Software\Google\Drive')){if(Test-Path $rp){try{$o=Get-ItemProperty $rp;foreach($prop in $o.PSObject.Properties){if($prop.Name -match 'mount|path|root|drive'){$v=[string]$prop.Value;if($v -and $v.Length -lt 260){Add $v ('Registry:'+ $prop.Name)}}}}catch{}}}
  foreach($d in Get-PSDrive -PSProvider FileSystem){foreach($p in @((Join-Path $d.Root '00_중앙에이전트'),(Join-Path $d.Root 'My Drive\00_중앙에이전트'),(Join-Path $d.Root '내 드라이브\00_중앙에이전트'),(Join-Path $d.Root 'Google Drive\00_중앙에이전트'))){if(Test-Path $p){Add (Split-Path $p -Parent) ('CentralFolder:'+ $d.Name)}}}
  return @($list)
}

function ScoreDrive($c){$p=$c.path;$score=0;if($p -match 'Google Drive|My Drive|내 드라이브'){$score+=50};if(Test-Path (Join-Path $p '00_중앙에이전트')){$score+=100};if($c.source -match 'Registry|DriveFS'){$score+=30};if($p -match '^[G-Z]:\\'){$score+=20};if($p -match '^C:\\$'){$score-=200};if($p -eq $env:USERPROFILE){$score-=100};$score}

function SyncReadback {
  if(-not (Test-Path $LatestJson)){WriteHistory 'LATEST_STATUS_MISSING' 'STATE' 'status file missing before sync' 'self-create state first';return [ordered]@{ok=$false;reason='LATEST_STATUS_MISSING';target=$null;candidates=@()}}
  Copy-Item $LatestJson (Join-Path $Readback 'CHROME_GOVERNOR_LATEST.json') -Force;if(Test-Path $LatestTxt){Copy-Item $LatestTxt (Join-Path $Readback 'CHROME_GOVERNOR_LATEST.txt') -Force}
  $cands=@(GetDriveCandidates | ForEach-Object {[pscustomobject]@{path=$_.path;source=$_.source;score=(ScoreDrive $_)}} | Sort-Object score -Descending)
  $best=$cands|Where-Object {$_.score -ge 20}|Select-Object -First 1
  if(-not $best){WriteHistory 'DRIVE_NOT_DETECTED' 'DRIVE' 'no high-confidence Google Drive root found' 'keep local readback and retry later';return [ordered]@{ok=$false;reason='GOOGLE_DRIVE_MOUNT_NOT_DETECTED';target=$null;candidates=$cands}}
  try{$dest=Join-Path (Join-Path $best.path '00_중앙에이전트') 'RUNTIME_READBACK\CHROME';New-Item -ItemType Directory -Force -Path $dest|Out-Null;Copy-Item (Join-Path $Readback 'CHROME_GOVERNOR_LATEST.json') (Join-Path $dest 'CHROME_GOVERNOR_LATEST.json') -Force;if(Test-Path (Join-Path $Readback 'CHROME_GOVERNOR_LATEST.txt')){Copy-Item (Join-Path $Readback 'CHROME_GOVERNOR_LATEST.txt') (Join-Path $dest 'CHROME_GOVERNOR_LATEST.txt') -Force};return [ordered]@{ok=$true;reason='SYNCED';target=$dest;candidates=$cands}}catch{WriteHistory 'DRIVE_WRITE_FAILED' 'DRIVE' $_.Exception.Message 'retry after mount/access recovery';return [ordered]@{ok=$false;reason=('WRITE_FAILED: '+$_.Exception.Message);target=$dest;candidates=$cands}}
}

function EnsureScheduledTask {
  try{$taskName='HomeDesignAutomation-GovernorV6';$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$GovPath+'"');$triggers=@();$triggers += New-ScheduledTaskTrigger -AtLogOn;$triggers += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 30);Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Description 'HomeDesign unified governor: diagnose, safe-heal, recheck, readback' -Force | Out-Null;return $true}catch{WriteHistory 'TASK_REGISTER_FAILED' 'SCHEDULER' $_.Exception.Message 'retry later';return $false}
}

Log '===== PRE_CHECK ====='
$sameMissing=GetRecentSameError 'LATEST_STATUS_MISSING'
if($sameMissing -ge 2){Log 'Repeated same error detected. Blind retry blocked; switching to root-cause self-create path.'}
$moved=@(MoveDesktopArtifacts);Log ('Desktop cleanup moved '+$moved.Count+' items.')
$runtimeBefore=GetRuntime;$healInvoked=$false
if(-not $runtimeBefore.agent_running -or -not $runtimeBefore.dedicated_chrome_running){$healInvoked=InvokeSafeResume;Start-Sleep -Seconds 6}
$extensions=GetChromeInventory;$runtime=GetRuntime
$known=[ordered]@{'NotebookLM WebApp Bridge'=@('NotebookLM WebApp Bridge','notebooklm');'Google AI Local Bridge'=@('Google AI Local Bridge','Google AI Local Bridge v1');'Flow Agent Bridge'=@('Flow Agent Bridge','Flow Bridge');'AI Studio Bridge'=@('AI Studio Bridge');'Front App Test Bridge'=@('Front App Test Bridge');'SketchUp Plan Template Bridge'=@('SketchUp Plan Template Bridge');'ChatGPT Image Auto'=@('ChatGPT Image Auto');'UniConverter'=@('UniConverter');'Save to Google Drive'=@('Save to Google Drive')}
$checks=@()
foreach($kv in $known.GetEnumerator()){$matches=@($extensions|Where-Object{$n=[string]$_.name;$hit=$false;foreach($needle in $kv.Value){if($n -like "*$needle*"){$hit=$true;break}};$hit});if($matches.Count -eq 0){$s=if($kv.Key -eq 'Save to Google Drive'){'PASS_NOT_INSTALLED'}elseif($kv.Key -eq 'UniConverter'){'OPTIONAL_NOT_INSTALLED'}else{'LIVE_READBACK_REQUIRED'};$checks += [pscustomobject]@{name=$kv.Key;status=$s;version='';enabled=$null};continue};$best=$matches|Sort-Object version -Descending|Select-Object -First 1;if($kv.Key -eq 'Save to Google Drive'){$s='APPROVAL_REQUIRED_REMOVE'}elseif($kv.Key -eq 'UniConverter'){$s='OPTIONAL_OR_REMOVE'}elseif($best.enabled -eq $false){$s='FAIL_DISABLED'}elseif($null -eq $best.enabled){$s='LIVE_READBACK_REQUIRED'}else{$s='PASS_INSTALLED_ENABLED'};$checks += [pscustomobject]@{name=$kv.Key;status=$s;version=$best.version;enabled=$best.enabled}}
$runtimeChecks=@([pscustomobject]@{name='Local Agent / Host';status=$(if($runtime.agent_running){'PASS_RUNNING'}else{'FAIL_NOT_RUNNING'})},[pscustomobject]@{name='Dedicated Chrome';status=$(if($runtime.dedicated_chrome_running){'PASS_RUNNING'}else{'FAIL_NOT_RUNNING'})})
$blocking=@($checks+$runtimeChecks|Where-Object {$_.status -match '^FAIL'});$approval=@($checks|Where-Object {$_.status -match '^APPROVAL_REQUIRED'});$live=@($checks+$runtimeChecks|Where-Object {$_.status -eq 'LIVE_READBACK_REQUIRED'})
$overall=if($blocking.Count -gt 0){'FAIL'}elseif($approval.Count -gt 0){'APPROVAL_REQUIRED'}elseif($live.Count -gt 0){'LIVE_READBACK_REQUIRED'}else{'PASS'}
$result=[ordered]@{overall=$overall;generated_at=(Get-Date).ToString('o');precheck=[ordered]@{same_error_count=$sameMissing;blind_retry_blocked=($sameMissing -ge 2)};auto_heal_invoked=$healInvoked;desktop_items_archived=$moved;extensions=$checks;runtime=$runtimeChecks;blockers=$blocking;approval_required=$approval;live_readback_required=$live;rule='PRE_CHECK -> diagnose -> safe auto-fix -> same-condition recheck -> state -> Drive readback'}
$result|ConvertTo-Json -Depth 12|Set-Content $LatestJson -Encoding UTF8
$lines=@('HomeDesign Unified Governor V6',('OVERALL: '+$overall),('TIME: '+$result.generated_at),('AUTO HEAL INVOKED: '+$healInvoked),'');$lines+='[RUNTIME]';foreach($x in $runtimeChecks){$lines+=("{0,-30} {1}" -f $x.name,$x.status)};$lines+='';$lines+='[CHROME EXTENSIONS]';foreach($x in $checks){$lines+=("{0,-34} {1,-28} v={2}" -f $x.name,$x.status,$x.version)};$lines+='';$lines+='Only destructive/high-risk changes require approval.';$lines|Set-Content $LatestTxt -Encoding UTF8
$sync=SyncReadback;$taskOk=EnsureScheduledTask
$syncStatus=[ordered]@{generated_at=(Get-Date).ToString('o');synced=$sync.ok;reason=$sync.reason;target=$sync.target;task_registered=$taskOk};$syncStatus|ConvertTo-Json -Depth 6|Set-Content (Join-Path $Readback 'READBACK_SYNC_STATUS.json') -Encoding UTF8
Log ('OVERALL='+$overall);Log ('DRIVE_SYNC='+$sync.ok+' / '+$sync.reason);Log ('TASK_REGISTERED='+$taskOk)
if($Interactive){Write-Host '';Write-Host '============================================================';Write-Host 'HomeDesign Unified Governor V6';Write-Host ('OVERALL: '+$overall);Write-Host ('DRIVE_SYNCED: '+$sync.ok);Write-Host ('DRIVE_REASON: '+$sync.reason);Write-Host ('STATE: '+$LatestJson);Write-Host '============================================================'}
if($overall -eq 'PASS' -and $sync.ok){exit 0};if($approval.Count -gt 0){exit 3};if($blocking.Count -gt 0){exit 1};exit 2
