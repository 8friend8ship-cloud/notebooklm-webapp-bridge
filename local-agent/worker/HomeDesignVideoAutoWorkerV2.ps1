param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$WorkerVersion='VIDEO_AUTO_WORKER_V2'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StatePath=Join-Path $Root 'video-job-state.json'
$ConsolePath=Join-Path $Root 'video-job-console.log'
$MetaPath=Join-Path $Root 'video-production-job.json'
$ScriptPath=Join-Path $Root 'Run-VideoProductionAutoJob.ps1'
$MetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/jobs/video-production.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Refresh([string]$Url,[string]$Path,[int]$Timeout=30){$Tmp=$Path+'.download';$Sep=if($Url.Contains('?')){'&'}else{'?'};$U=$Url+$Sep+'hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $U -OutFile $Tmp -TimeoutSec $Timeout;Move-Item -LiteralPath $Tmp -Destination $Path -Force}
function GitBlobSha1([string]$Path){$Bytes=[IO.File]::ReadAllBytes($Path);$Header=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$All=New-Object byte[] ($Header.Length+$Bytes.Length);[Buffer]::BlockCopy($Header,0,$All,0,$Header.Length);[Buffer]::BlockCopy($Bytes,0,$All,$Header.Length,$Bytes.Length);$Sha=[Security.Cryptography.SHA1]::Create();try{return (($Sha.ComputeHash($All)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$Sha.Dispose()}}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$S=[string]$_;if($S -match '[\s"]'){'"'+($S -replace '"','\"')+'"'}else{$S}})-join ' ')}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function RunProcess([string]$File,[string[]]$Args,[int]$Timeout,[string]$Cwd,[string]$LogPath){
  $Psi=New-Object Diagnostics.ProcessStartInfo;$Psi.FileName=$File;$Psi.WorkingDirectory=$Cwd;$Psi.UseShellExecute=$false;$Psi.CreateNoWindow=$true;$Psi.RedirectStandardOutput=$true;$Psi.RedirectStandardError=$true;$Psi.Arguments=QuoteArgs $Args
  $P=New-Object Diagnostics.Process;$P.StartInfo=$Psi;[void]$P.Start();$OT=$P.StandardOutput.ReadToEndAsync();$ET=$P.StandardError.ReadToEndAsync()
  if(-not $P.WaitForExit($Timeout*1000)){
    KillTree ([int]$P.Id);try{[void]$P.WaitForExit(3000)}catch{}
    $O=$(if($OT.IsCompleted){try{$OT.Result}catch{''}}else{'[stdout stream did not close before timeout]'})
    $E=$(if($ET.IsCompleted){try{$ET.Result}catch{''}}else{'[stderr stream did not close before timeout]'})
    ($O+"`r`n"+$E)|Set-Content -LiteralPath $LogPath -Encoding UTF8
    return [ordered]@{ok=$false;exitCode=124;timedOut=$true;stdout=$O;stderr=$E}
  }
  $P.WaitForExit();$O=$OT.Result;$E=$ET.Result;($O+"`r`n"+$E)|Set-Content -LiteralPath $LogPath -Encoding UTF8
  return [ordered]@{ok=($P.ExitCode -eq 0);exitCode=$P.ExitCode;timedOut=$false;stdout=$O;stderr=$E}
}
function FindCentral(){$Target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($D in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$R=[string]$D.Root;if(-not $R){continue};foreach($C in @((Join-Path $R $Target),(Join-Path $R ('My Drive\'+$Target)),(Join-Path $R ('내 드라이브\'+$Target)),(Join-Path $R ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}};foreach($C in @((Join-Path $env:USERPROFILE ('My Drive\'+$Target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$Target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}};return ''}
function WriteState($State,[string]$Central){$State.workerVersion=$WorkerVersion;$State|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $StatePath -Encoding UTF8;if($Central){try{$Dir=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $Dir|Out-Null;$State|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $Dir 'VIDEO_AUTO_JOB_STATE.json') -Encoding UTF8;if(Test-Path -LiteralPath $ConsolePath){Copy-Item -LiteralPath $ConsolePath -Destination (Join-Path $Dir 'VIDEO_AUTO_JOB_CONSOLE.log') -Force}}catch{}}}
$Central=FindCentral
try{
  Refresh $MetaUrl $MetaPath 20;$Job=ReadJson $MetaPath
  if(-not $Job -or -not $Job.enabled){WriteState ([ordered]@{status='DISABLED';ok=$true;updatedAt=(Get-Date).ToString('o')}) $Central;exit 0}
  $Old=ReadJson $StatePath;$Reset=($null -eq $Old -or [string]$Old.jobId -ne [string]$Job.jobId -or [string]$Old.scriptBlobSha1 -ne [string]$Job.scriptBlobSha1);$Attempts=0;if(-not $Reset -and $Old.attempts){$Attempts=[int]$Old.attempts}
  if(-not $Reset -and [string]$Old.status -eq 'PASS'){WriteState $Old $Central;exit 0}
  $Max=[Math]::Max(1,[int]$Job.maxAttempts);if($Attempts -ge $Max){WriteState ([ordered]@{jobId=[string]$Job.jobId;scriptBlobSha1=[string]$Job.scriptBlobSha1;attempts=$Attempts;status='MAX_ATTEMPTS_REACHED';ok=$false;updatedAt=(Get-Date).ToString('o')}) $Central;exit 12}
  $Attempts++;$Running=[ordered]@{jobId=[string]$Job.jobId;scriptBlobSha1=[string]$Job.scriptBlobSha1;attempts=$Attempts;status='RUNNING';ok=$false;startedAt=(Get-Date).ToString('o');successReadback=[string]$Job.successReadback};WriteState $Running $Central
  $Raw='https://raw.githubusercontent.com/'+[string]$Job.scriptRepo+'/'+[string]$Job.scriptRef+'/'+[string]$Job.scriptPath;Refresh $Raw $ScriptPath 30
  $Actual=(GitBlobSha1 $ScriptPath).ToLowerInvariant();$Expected=([string]$Job.scriptBlobSha1).ToLowerInvariant();if($Actual -ne $Expected){throw ('VIDEO_JOB_HASH_MISMATCH expected='+$Expected+' actual='+$Actual)}
  $Timeout=[Math]::Max(60,[Math]::Min(1800,[int]$Job.timeoutSeconds));$Run=RunProcess 'powershell.exe' @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$ScriptPath) $Timeout $Root $ConsolePath
  $Status=$(if($Run.ok){'PASS'}elseif($Run.timedOut){'TIMEOUT'}else{'ERROR'});$Final=[ordered]@{jobId=[string]$Job.jobId;scriptBlobSha1=$Expected;attempts=$Attempts;status=$Status;ok=[bool]$Run.ok;exitCode=$Run.exitCode;timedOut=[bool]$Run.timedOut;startedAt=$Running.startedAt;completedAt=(Get-Date).ToString('o');successReadback=[string]$Job.successReadback;error=$(if($Run.ok){''}else{[string]$Run.stderr})};WriteState $Final $Central
  if($Run.ok){exit 0}else{exit 12}
}catch{
  $Old=ReadJson $StatePath;$Attempts=$(if($Old -and $Old.attempts){[int]$Old.attempts}else{1});$Fail=[ordered]@{jobId=$(if($Old){[string]$Old.jobId}else{''});scriptBlobSha1=$(if($Old){[string]$Old.scriptBlobSha1}else{''});attempts=$Attempts;status='ERROR';ok=$false;exitCode=1;timedOut=$false;completedAt=(Get-Date).ToString('o');error=$_.Exception.Message};WriteState $Fail $Central;exit 12
}
