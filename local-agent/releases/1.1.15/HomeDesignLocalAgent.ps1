param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.15'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$WorkerFile=Join-Path $Root 'HomeDesignVideoAutoWorker.ps1'
$JobStateFile=Join-Path $Root 'video-job-state.json'
$WorkerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/worker/HomeDesignVideoAutoWorker.ps1'
$WorkerSha='0a76ad5ce2d64305bba7dc492511380900aebcf1'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function GitBlobSha1([string]$Path){$Bytes=[IO.File]::ReadAllBytes($Path);$Header=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$All=New-Object byte[] ($Header.Length+$Bytes.Length);[Buffer]::BlockCopy($Header,0,$All,0,$Header.Length);[Buffer]::BlockCopy($Bytes,0,$All,$Header.Length,$Bytes.Length);$Sha=[Security.Cryptography.SHA1]::Create();try{return (($Sha.ComputeHash($All)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$Sha.Dispose()}}
function RefreshVerified([string]$Url,[string]$Path,[string]$Expected){$Tmp=$Path+'.download';$Sep=if($Url.Contains('?')){'&'}else{'?'};$U=$Url+$Sep+'hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $U -OutFile $Tmp -TimeoutSec 45;$Actual=(GitBlobSha1 $Tmp).ToLowerInvariant();if($Actual -ne $Expected.ToLowerInvariant()){Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue;throw ('HASH_MISMATCH expected='+$Expected+' actual='+$Actual)};Move-Item -LiteralPath $Tmp -Destination $Path -Force}
function ProcWorker(){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$WorkerFile*"})}catch{return @()}}
function StartWorker(){Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$WorkerFile`"") -WindowStyle Hidden|Out-Null}
function FindCentral(){$Target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($D in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$R=[string]$D.Root;if(-not $R){continue};foreach($C in @((Join-Path $R $Target),(Join-Path $R ('My Drive\'+$Target)),(Join-Path $R ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}};foreach($C in @((Join-Path $env:USERPROFILE ('My Drive\'+$Target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}};return ''}
$Existing=ReadJson $StateFile
$Host=$null;try{$Host=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{}
$Manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json')
$WorkerInstalled=$false;$WorkerInstallError=''
try{RefreshVerified $WorkerUrl $WorkerFile $WorkerSha;$WorkerInstalled=$true}catch{$WorkerInstallError=$_.Exception.Message}
$JobState=ReadJson $JobStateFile
$WorkerRunning=((ProcWorker).Count -gt 0)
$WorkerLaunched=$false
if($WorkerInstalled -and -not $WorkerRunning){$Status=$(if($JobState){[string]$JobState.status}else{'NONE'});$Attempts=$(if($JobState -and $JobState.attempts){[int]$JobState.attempts}else{0});if($Status -ne 'PASS' -and $Attempts -lt 6){StartWorker;$WorkerLaunched=$true;Start-Sleep -Milliseconds 400;$WorkerRunning=((ProcWorker).Count -gt 0)}}
$S=@{}
if($Existing){foreach($P in $Existing.PSObject.Properties){$S[$P.Name]=$P.Value}}
$S.ok=$WorkerInstalled
$S.status=$(if($WorkerInstalled){'THIN_COORDINATOR_PASS'}else{'THIN_COORDINATOR_FAILED'})
$S.agentVersion=$AgentVersion
$S.agentMode='THIN_COORDINATOR_NO_RECURSIVE_BASE_AGENT'
$S.hostHealthy=$(if($Host){[bool]$Host.ok}else{$false})
$S.commandHostVersion=$(if($Host){[string]$Host.version}else{''})
$S.commandHostAsyncJobs=$(if($Host){[bool]$Host.asyncJobs}else{$false})
$S.extensionVersion=$(if($Manifest){[string]$Manifest.version}else{''})
$S.videoWorkerVersion='VIDEO_AUTO_WORKER_V1'
$S.videoWorkerHash=$WorkerSha
$S.videoWorkerInstalled=$WorkerInstalled
$S.videoWorkerInstallError=$WorkerInstallError
$S.videoWorkerRunning=$WorkerRunning
$S.videoWorkerLaunchedThisCycle=$WorkerLaunched
$S.videoWorkerStatus=$(if($JobState){[string]$JobState.status}elseif($WorkerLaunched){'STARTED'}else{'PENDING'})
$S.videoWorkerAttempts=$(if($JobState -and $JobState.attempts){[int]$JobState.attempts}else{0})
$S.updatedAt=(Get-Date).ToString('o')
$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StateFile -Encoding UTF8
$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
$Central=FindCentral
if($Central){try{$Dir=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $Dir|Out-Null;$S|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $Dir 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}catch{}}
if($WorkerInstalled){exit 0}else{exit 12}
