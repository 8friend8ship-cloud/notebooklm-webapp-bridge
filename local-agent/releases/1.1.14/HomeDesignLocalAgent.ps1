param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.14'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$JobStateFile=Join-Path $Root 'video-job-state.json'
$BaseAgentFile=Join-Path $Root 'HomeDesignLocalAgent-1.1.13-base.ps1'
$WorkerFile=Join-Path $Root 'HomeDesignVideoAutoWorker.ps1'
$BaseAgentUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.13/HomeDesignLocalAgent.ps1'
$BaseAgentSha='90219a1d738b341bfaee89385c634524d11b3947'
$WorkerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/worker/HomeDesignVideoAutoWorker.ps1'
$WorkerSha='0a76ad5ce2d64305bba7dc492511380900aebcf1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function GitBlobSha1([string]$Path){$Bytes=[IO.File]::ReadAllBytes($Path);$Header=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$All=New-Object byte[] ($Header.Length+$Bytes.Length);[Buffer]::BlockCopy($Header,0,$All,0,$Header.Length);[Buffer]::BlockCopy($Bytes,0,$All,$Header.Length,$Bytes.Length);$Sha=[Security.Cryptography.SHA1]::Create();try{return (($Sha.ComputeHash($All)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$Sha.Dispose()}}
function RefreshVerified([string]$Url,[string]$Path,[string]$Expected){$Tmp=$Path+'.download';$Sep=if($Url.Contains('?')){'&'}else{'?'};$U=$Url+$Sep+'hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $U -OutFile $Tmp -TimeoutSec 60;$Actual=(GitBlobSha1 $Tmp).ToLowerInvariant();if($Actual -ne $Expected.ToLowerInvariant()){Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue;throw ('HASH_MISMATCH expected='+$Expected+' actual='+$Actual)};Move-Item -LiteralPath $Tmp -Destination $Path -Force}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$S=[string]$_;if($S -match '[\s"]'){'"'+($S -replace '"','\"')+'"'}else{$S}})-join ' ')}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function RunBounded([string]$File,[string[]]$Args,[int]$Timeout){$Psi=New-Object Diagnostics.ProcessStartInfo;$Psi.FileName=$File;$Psi.UseShellExecute=$false;$Psi.CreateNoWindow=$true;$Psi.RedirectStandardOutput=$true;$Psi.RedirectStandardError=$true;$Psi.Arguments=QuoteArgs $Args;$P=New-Object Diagnostics.Process;$P.StartInfo=$Psi;[void]$P.Start();$OT=$P.StandardOutput.ReadToEndAsync();$ET=$P.StandardError.ReadToEndAsync();if(-not $P.WaitForExit($Timeout*1000)){KillTree ([int]$P.Id);try{[void]$P.WaitForExit(3000)}catch{};return [ordered]@{ok=$false;exitCode=124;timedOut=$true;stderr='BASE_AGENT_TIMEOUT'}};$P.WaitForExit();return [ordered]@{ok=($P.ExitCode -eq 0);exitCode=$P.ExitCode;timedOut=$false;stdout=$OT.Result;stderr=$ET.Result}}
function ProcWorker(){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$WorkerFile*"})}catch{return @()}}
function StartWorker(){Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$WorkerFile`"") -WindowStyle Hidden|Out-Null}
function FindCentral(){$Target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($D in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$R=[string]$D.Root;if(-not $R){continue};foreach($C in @((Join-Path $R $Target),(Join-Path $R ('My Drive\'+$Target)),(Join-Path $R ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}};foreach($C in @((Join-Path $env:USERPROFILE ('My Drive\'+$Target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}};return ''}
$BaseRun=[ordered]@{ok=$false;exitCode=1;timedOut=$false;stderr='NOT_RUN'}
try{RefreshVerified $BaseAgentUrl $BaseAgentFile $BaseAgentSha;$BaseRun=RunBounded 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$BaseAgentFile) 180}catch{$BaseRun=[ordered]@{ok=$false;exitCode=1;timedOut=$false;stderr=$_.Exception.Message}}
$WorkerInstallOk=$false
try{RefreshVerified $WorkerUrl $WorkerFile $WorkerSha;$WorkerInstallOk=$true}catch{$WorkerInstallError=$_.Exception.Message}
$JobState=ReadJson $JobStateFile
$WorkerRunning=((ProcWorker).Count -gt 0)
$WorkerLaunched=$false
if($WorkerInstallOk -and -not $WorkerRunning){$Status=$(if($JobState){[string]$JobState.status}else{'NONE'});$Attempts=$(if($JobState -and $JobState.attempts){[int]$JobState.attempts}else{0});if($Status -ne 'PASS' -and $Attempts -lt 6){StartWorker;$WorkerLaunched=$true;Start-Sleep -Milliseconds 500;$WorkerRunning=((ProcWorker).Count -gt 0)}}
$State=@{};$Existing=ReadJson $StateFile;if($Existing){foreach($P in $Existing.PSObject.Properties){$State[$P.Name]=$P.Value}}
$State.agentVersion=$AgentVersion;$State.baseAgentVersion='1.1.13';$State.baseAgentOk=[bool]$BaseRun.ok;$State.baseAgentExitCode=$BaseRun.exitCode;$State.baseAgentError=[string]$BaseRun.stderr;$State.videoWorkerVersion='VIDEO_AUTO_WORKER_V1';$State.videoWorkerHash=$WorkerSha;$State.videoWorkerInstalled=$WorkerInstallOk;$State.videoWorkerRunning=$WorkerRunning;$State.videoWorkerLaunchedThisCycle=$WorkerLaunched;$State.videoWorkerStatus=$(if($JobState){[string]$JobState.status}elseif($WorkerLaunched){'STARTED'}else{'PENDING'});$State.videoWorkerAttempts=$(if($JobState -and $JobState.attempts){[int]$JobState.attempts}else{0});$State.updatedAt=(Get-Date).ToString('o')
$State|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8;$State|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
$Central=FindCentral
if($Central){try{$Dir=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $Dir|Out-Null;$State|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $Dir 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}catch{}}
if(-not $WorkerInstallOk){exit 12}
exit 0
