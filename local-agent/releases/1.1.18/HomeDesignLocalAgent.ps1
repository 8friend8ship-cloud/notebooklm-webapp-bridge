param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.18'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$JobStateFile=Join-Path $Root 'video-job-state.json'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$WorkerFile=Join-Path $Root 'HomeDesignVideoAutoWorkerV2.ps1'
$NodeGov=Join-Path $GovRoot 'chromeGovernorFast.js'
$Policy=Join-Path $GovRoot 'policy.json'
$Release=Join-Path $GovRoot 'release.json'
$GovState=Join-Path $GovRoot 'state.json'
$Inventory=Join-Path $GovRoot 'inventory.json'
$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.2/HomeDesignLocalCommandHost.ps1'
$HostSha='4704cbf9c8c4d8b702bdd819635a1b420e21a1b7'
$WorkerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/worker/HomeDesignVideoAutoWorkerV2.ps1'
$WorkerSha='7c428ae1f897d0409925bc3479ebaedea577665e'
$NodeUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/chromeGovernorFast.js'
$NodeSha='6b2cc50985e72bfc1d271bcfde675bfb4a77427c'
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
New-Item -ItemType Directory -Force -Path $Root,$GovRoot|Out-Null
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Bust([string]$Url){$Sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$Sep+'hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
function RefreshVerified([string]$Url,[string]$Path,[string]$Expected,[int]$Timeout=20){$Tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri (Bust $Url) -OutFile $Tmp -TimeoutSec $Timeout;$Actual=(GitBlobSha1 $Tmp).ToLowerInvariant();if($Actual -ne $Expected.ToLowerInvariant()){Remove-Item $Tmp -Force -ErrorAction SilentlyContinue;throw "HASH_MISMATCH path=$Path actual=$Actual expected=$Expected"};Move-Item $Tmp $Path -Force}
function RefreshOptional([string]$Url,[string]$Path,[int]$Timeout=12){$Tmp=$Path+'.download';try{Invoke-WebRequest -UseBasicParsing -Uri (Bust $Url) -OutFile $Tmp -TimeoutSec $Timeout;Move-Item $Tmp $Path -Force;return $true}catch{Remove-Item $Tmp -Force -ErrorAction SilentlyContinue;return (Test-Path -LiteralPath $Path)}}
function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function Host122{ $H=HostHealth; return ($H -and [bool]$H.ok -and [string]$H.version -eq '1.2.2' -and [bool]$H.asyncJobs) }
function StartHost{Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$HostFile`"") -WindowStyle Hidden|Out-Null}
function StartWorker{Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$WorkerFile`"") -WindowStyle Hidden|Out-Null}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function RunNode{
  if(-not(Test-Path -LiteralPath $NodeGov) -or -not(Test-Path -LiteralPath $Policy) -or -not(Test-Path -LiteralPath $Release)){return [ordered]@{ok=$false;exitCode=2;error='GOVERNOR_INPUT_MISSING'}}
  $Node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $Node){$Node=Get-Command node -ErrorAction SilentlyContinue};if(-not $Node){return [ordered]@{ok=$false;exitCode=127;error='NODE_NOT_FOUND'}}
  $Args=@($NodeGov,'--normalRoot',$NormalRoot,'--dedicatedUserData',$DedicatedUserData,'--dedicatedExtensionRoot',$ExtensionRoot,'--policy',$Policy,'--release',$Release,'--agentState',$StateFile,'--report',$GovState,'--inventory',$Inventory)
  $Psi=New-Object Diagnostics.ProcessStartInfo;$Psi.FileName=$Node.Source;$Psi.UseShellExecute=$false;$Psi.CreateNoWindow=$true;$Psi.RedirectStandardOutput=$true;$Psi.RedirectStandardError=$true;$Psi.Arguments=QuoteArgs $Args
  $P=New-Object Diagnostics.Process;$P.StartInfo=$Psi;[void]$P.Start();$OT=$P.StandardOutput.ReadToEndAsync();$ET=$P.StandardError.ReadToEndAsync();if(-not $P.WaitForExit(30000)){KillTree ([int]$P.Id);try{[void]$P.WaitForExit(3000)}catch{};return [ordered]@{ok=$false;exitCode=124;error='NODE_GOVERNOR_TIMEOUT_30S'}};$P.WaitForExit();return [ordered]@{ok=($P.ExitCode -eq 0);exitCode=$P.ExitCode;stdout=$(if($OT.IsCompleted){$OT.Result.Trim()}else{''});stderr=$(if($ET.IsCompleted){$ET.Result.Trim()}else{''})}
}
function FindCentral{$Target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($D in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$R=[string]$D.Root;if(-not $R){continue};foreach($C in @((Join-Path $R $Target),(Join-Path $R ('My Drive\'+$Target)),(Join-Path $R ('내 드라이브\'+$Target)),(Join-Path $R ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}};foreach($C in @((Join-Path $env:USERPROFILE ('My Drive\'+$Target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$Target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}};return ''}
$Mutex=New-Object System.Threading.Mutex($false,'HomeDesignLocalAgent118');if(-not $Mutex.WaitOne(0,$false)){exit 0}
try{
  $Errors=@();$HostInstallOk=$false;$WorkerInstallOk=$false
  try{RefreshVerified $HostUrl $HostFile $HostSha 20;$HostInstallOk=$true}catch{$Errors+=('HOST_INSTALL: '+$_.Exception.Message)}
  if($HostInstallOk -and -not(Host122)){foreach($P in @(Proc 'HomeDesignLocalCommandHost')){KillTree ([int]$P.ProcessId)};Start-Sleep -Milliseconds 700;StartHost;$Deadline=(Get-Date).AddSeconds(18);do{Start-Sleep -Milliseconds 500}while(-not(Host122) -and (Get-Date)-lt $Deadline)}
  if(-not(Host122)){$Errors+='HOST_1.2.2_HEALTH_FAILED'}
  try{RefreshVerified $WorkerUrl $WorkerFile $WorkerSha 20;$WorkerInstallOk=$true}catch{$Errors+=('WORKER_INSTALL: '+$_.Exception.Message)}
  if($WorkerInstallOk){foreach($P in @(Proc 'HomeDesignVideoAutoWorker.ps1')){KillTree ([int]$P.ProcessId)};$V2=@(Proc 'HomeDesignVideoAutoWorkerV2.ps1');if($V2.Count -eq 0){StartWorker}}
  $NodeReady=$false;try{RefreshVerified $NodeUrl $NodeGov $NodeSha 15;$NodeReady=$true}catch{$Errors+=('NODE_FETCH: '+$_.Exception.Message);$NodeReady=(Test-Path -LiteralPath $NodeGov)}
  $PolicyReady=RefreshOptional $PolicyUrl $Policy 10;$ReleaseReady=RefreshOptional $ReleaseUrl $Release 10
  $GovRun=$(if($NodeReady -and $PolicyReady -and $ReleaseReady){RunNode}else{[ordered]@{ok=$false;exitCode=2;error='GOVERNOR_INPUT_REFRESH_FAILED'}})
  $H=HostHealth;$Manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json');$Job=ReadJson $JobStateFile;$Gov=ReadJson $GovState;$Central=FindCentral;$DriveOk=$false
  $S=[ordered]@{ok=([bool]($H -and $H.ok));status=$(if($Errors.Count -eq 0 -and $GovRun.ok){'THIN_COORDINATOR_PASS'}else{'THIN_COORDINATOR_DEGRADED'});agentVersion=$AgentVersion;agentMode='THIN_DIRECT_NO_RECURSIVE_BASE_AGENT';commandHostVersion=$(if($H){[string]$H.version}else{''});hostHealthy=$(if($H){[bool]$H.ok}else{$false});hostAsyncJobs=$(if($H){[bool]$H.asyncJobs}else{$false});extensionVersion=$(if($Manifest){[string]$Manifest.version}else{''});videoWorkerVersion='VIDEO_AUTO_WORKER_V2';videoWorkerInstalled=$WorkerInstallOk;videoWorkerRunning=(@(Proc 'HomeDesignVideoAutoWorkerV2.ps1').Count -gt 0);videoJobState=$Job;governorCycleOk=[bool]$GovRun.ok;governorExitCode=$GovRun.exitCode;governorError=$(if($GovRun.error){[string]$GovRun.error}else{[string]$GovRun.stderr});governorSummary=$(if($Gov){$Gov.summary}else{$null});errors=$Errors;updatedAt=(Get-Date).ToString('o')}
  $S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8;$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
  if($Central){try{$R=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $R|Out-Null;$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $R 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8;if(Test-Path $GovState){$G=Join-Path $Central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $G|Out-Null;Copy-Item $GovState (Join-Path $G 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force;Copy-Item $Inventory (Join-Path $G 'CHROME_EXTENSION_INVENTORY.json') -Force};$DriveOk=$true}catch{$Errors+=('DRIVE_SYNC: '+$_.Exception.Message)}}
  if($DriveOk){$S.governorDriveSyncOk=$true;$S.governorCentralPath=$Central;$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8;$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8}
  if($S.hostHealthy -and $GovRun.ok){exit 0}else{exit 18}
}finally{try{$Mutex.ReleaseMutex()}catch{};$Mutex.Dispose()}
