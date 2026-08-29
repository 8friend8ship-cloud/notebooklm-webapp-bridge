param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Runner=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Api([string]$Path){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-AutoResume-Installer';'Accept'='application/vnd.github+json'} -TimeoutSec 30}
function Blob([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function InstallVerified([string]$RepoPath,[string]$Dest){$r=Api $RepoPath;$tmp=$Dest+'.install';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$expected=([string]$r.sha).ToLowerInvariant();$actual=(Blob $tmp).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SHA_MISMATCH:'+ $RepoPath)};Move-Item $tmp $Dest -Force;return $expected}
function FindCentral{$name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $name),(Join-Path $d.Root ('My Drive\'+$name)),(Join-Path $d.Root ($myDriveKo+'\'+$name)),(Join-Path $d.Root ('Google Drive\'+$name)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveReceipt($o){$json=$o|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath (Join-Path $Root 'AUTO_RESUME_INSTALL_V3.json') -Encoding UTF8;$central=FindCentral;if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir 'AUTO_RESUME_INSTALL_V3.json') -Encoding UTF8}}
function RunDirectWatchdog([int]$TimeoutSeconds=210){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Watchdog+'"';$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();if(-not $p.WaitForExit($TimeoutSeconds*1000)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{};return 124};return [int]$p.ExitCode}

$started=(Get-Date).ToString('o');$errors=@();$runnerSha='';$watchdogSha='';$taskCreated=$false;$runKeySet=$false;$scheduledRunExit=$null;$directExit=$null;$immediateMode=''
try{$runnerSha=InstallVerified 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $Runner}catch{$errors+=('RUNNER_INSTALL:'+ $_.Exception.Message)}
try{$watchdogSha=InstallVerified 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $Watchdog}catch{$errors+=('WATCHDOG_INSTALL:'+ $_.Exception.Message)}

$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';$runName='HomeDesignAutomationAutoResume';$runCommand='powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Watchdog+'"'
try{New-Item -Path $runKey -Force|Out-Null;Set-ItemProperty -Path $runKey -Name $runName -Value $runCommand -Type String;$runVerify=(Get-ItemProperty -Path $runKey -Name $runName -ErrorAction Stop).$runName;if([string]$runVerify-ne$runCommand){throw'HKCU_RUN_FALLBACK_VERIFY_FAILED'};$runKeySet=$true}catch{$errors+=('HKCU_RUN:'+ $_.Exception.Message)}

$taskName='HomeDesignAutomation-AutoResume'
try{
  $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$Watchdog+'"')
  $trigger=New-ScheduledTaskTrigger -AtLogOn
  $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
  $taskCreated=$true
}catch{$errors+=('SCHEDULED_TASK_CREATE:'+ $_.Exception.Message)}

if($taskCreated){try{& schtasks.exe /Run /TN $taskName | Out-Null;$scheduledRunExit=$LASTEXITCODE;if($scheduledRunExit-ne0){throw('SCHTASKS_RUN_'+$scheduledRunExit)}}catch{$errors+=('SCHEDULED_TASK_RUN:'+ $_.Exception.Message)}}

if(Test-Path -LiteralPath $Watchdog -PathType Leaf){
  try{$directExit=RunDirectWatchdog 210;$immediateMode='DIRECT_WATCHDOG_ALWAYS';if($directExit-ne0){$errors+=('DIRECT_WATCHDOG_EXIT_'+$directExit)}}catch{$errors+=('DIRECT_WATCHDOG:'+ $_.Exception.Message);$directExit=3}
}else{$errors+='WATCHDOG_FILE_MISSING_AFTER_INSTALL'}

$persistenceReady=[bool]($taskCreated-or$runKeySet)
$immediateStarted=[bool]($directExit-ne$null)
$ok=[bool]($runnerSha-and$watchdogSha-and$persistenceReady-and$immediateStarted-and($directExit-eq0))
$rec=[ordered]@{ok=$ok;action='INSTALL_AUTO_RESUME_V3';startedAt=$started;completedAt=(Get-Date).ToString('o');runnerSha=$runnerSha;watchdogSha=$watchdogSha;scheduledTaskCreated=$taskCreated;scheduledRunExit=$scheduledRunExit;hkcuRunRegistered=$runKeySet;persistenceReady=$persistenceReady;immediateMode=$immediateMode;directWatchdogExit=$directExit;immediateExecutionVerified=[bool]($directExit-eq0);normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;errors=$errors}
SaveReceipt $rec
$rec|ConvertTo-Json -Depth 30 -Compress
if($ok){exit 0}else{exit 2}
