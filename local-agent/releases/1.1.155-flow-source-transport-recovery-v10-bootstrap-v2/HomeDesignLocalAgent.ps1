param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.155-flow-source-transport-recovery-v10-bootstrap-v2'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Receipt='FLOW_SOURCE_TRANSPORT_RECOVERY_V10_BOOTSTRAP_V2_1.1.155.json'
$ExpectedWatchdog='1e0ad6f23a172e67fc8e2503f0aeb96ae0f93eea'
$ExpectedBootstrap='c0a0093ccfb52aa8ab5b534d43852c837e5304fc'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function GitBlobSha1([string]$Path){return GitBlobSha1Bytes ([IO.File]::ReadAllBytes($Path))}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 50;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function RawBytes([string]$Path){$u='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Flow-Transport-Recovery-1.1.155';return $wc.DownloadData($u)}finally{$wc.Dispose()}}
function BootstrapProcesses{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name-match'(?i)powershell|pwsh'-and[string]$_.CommandLine-match'(?i)AgentBootstrap\.ps1'-and[string]$_.CommandLine-match'(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
function ReplaceVerified([string]$RepoPath,[string]$Dest,[string]$Expected,[string]$BackupSuffix){$b=RawBytes $RepoPath;if(-not$b-or$b.Length-eq0){throw ('RAW_EMPTY:'+ $RepoPath)};$sha=(GitBlobSha1Bytes $b).ToLowerInvariant();if($sha-ne$Expected.ToLowerInvariant()){throw ('RAW_BLOB_MISMATCH:'+ $RepoPath+':'+$sha)};$before='';if(Test-Path -LiteralPath $Dest -PathType Leaf){$before=(GitBlobSha1 $Dest).ToLowerInvariant();if($before-ne$Expected.ToLowerInvariant()){Copy-Item -LiteralPath $Dest -Destination ($Dest+$BackupSuffix) -Force}};if($before-ne$Expected.ToLowerInvariant()){$tmp=$Dest+'.recovery155';[IO.File]::WriteAllBytes($tmp,$b);if((GitBlobSha1 $tmp).ToLowerInvariant()-ne$Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('LOCAL_VERIFY_FAILED:'+ $RepoPath)};Move-Item $tmp $Dest -Force};[pscustomobject]@{before=$before;after=(GitBlobSha1 $Dest).ToLowerInvariant();changed=($before-ne$Expected.ToLowerInvariant())}}

$r=[ordered]@{ok=$false;action='FLOW_SOURCE_TRANSPORT_RECOVERY_V10_BOOTSTRAP_V2';version=$Version;stage='START';watchdogExpected=$ExpectedWatchdog;bootstrapExpected=$ExpectedBootstrap;watchdogBefore='';watchdogAfter='';watchdogChanged=$false;bootstrapBefore='';bootstrapAfter='';bootstrapChanged=$false;bootstrapProcessesBefore=0;bootstrapProcessesStopped=0;bootstrapProcessesAfter=0;bootstrapRestarted=$false;normalChromeTouched=$false;flowGenerateClicked=$false;hostTouched=$false;oauthChanged=$false;scopeChanged=$false;creditSpend=$false;error='';startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $stamp='.backup_1.1.155_'+(Get-Date -Format 'yyyyMMdd_HHmmss')
  $r.stage='RAW_FETCH_AND_VERIFY'
  $w=ReplaceVerified 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog $ExpectedWatchdog $stamp;$r.watchdogBefore=$w.before;$r.watchdogAfter=$w.after;$r.watchdogChanged=[bool]$w.changed
  $b=ReplaceVerified 'local-agent/bootstrap/AgentBootstrap.ps1' $Bootstrap $ExpectedBootstrap $stamp;$r.bootstrapBefore=$b.before;$r.bootstrapAfter=$b.after;$r.bootstrapChanged=[bool]$b.changed
  $r.stage='RESTART_BOOTSTRAP_LOOP_ONLY'
  $before=@(BootstrapProcesses);$r.bootstrapProcessesBefore=[int]$before.Count
  foreach($p in $before){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null;$r.bootstrapProcessesStopped++}catch{}}
  Start-Sleep -Milliseconds 700
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop') -WindowStyle Hidden|Out-Null
  Start-Sleep -Seconds 2;$after=@(BootstrapProcesses);$r.bootstrapProcessesAfter=[int]$after.Count;$r.bootstrapRestarted=($after.Count-ge1)
  if(-not$r.bootstrapRestarted){throw 'BOOTSTRAP_LOOP_RESTART_NOT_OBSERVED'}
  if($r.watchdogAfter-ne$ExpectedWatchdog-or$r.bootstrapAfter-ne$ExpectedBootstrap){throw 'FINAL_BLOB_READBACK_MISMATCH'}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 50 -Compress
if($r.ok){exit 0}else{exit 2}
