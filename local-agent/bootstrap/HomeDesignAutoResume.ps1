param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Version='HOME_DESIGN_AUTO_RESUME_V13_PINNED_RDC_CHAIN_20260921'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Log=Join-Path $Root 'auto-resume.log'
$ResumeLocal=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1'
$BootstrapLocal=Join-Path $Root 'AgentBootstrap.ps1'
$WatchdogLocal=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$OpenAISyncLocal=Join-Path $Root 'OpenAIWebSyncGuard.ps1'
$DriveMirrorFixLocal=Join-Path $Root 'DriveMirrorExactDiffFinalize.py'
$PythonControlLocal=Join-Path $Root 'central_control_worker_v1.py'
$WatchdogCommit='cc5fd27f5d53344a79a82662fc5cec5029326246'
$WatchdogBlob='8bf8038fe4a9fc13c553da4c68c2da40df8ba443'
$ResumeCommit='5d4a789fb9744598f1f3c211b1d970a42297f793'
$ResumeBlob='62f3153a9e746ad1c83ebea294cd1e6c952d90d5'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Log([string]$m){Add-Content -LiteralPath $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function GitBlobSha1([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0));$all=New-Object byte[]($header.Length+$bytes.Length);[Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length);$sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}}
function ApiContent([string]$Path){$headers=@{'User-Agent'='HomeDesign-AutoResume';'Accept'='application/vnd.github+json'};$url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30}
function RawUrl([string]$Path){'https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
function RefreshFile([string]$RepoPath,[string]$Dest,[string]$Label){
  $tmp=$Dest+'.download';$mode='';$expected=''
  try{Invoke-WebRequest -UseBasicParsing -Uri (RawUrl $RepoPath) -Headers @{'User-Agent'='HomeDesign-AutoResume-V9'} -OutFile $tmp -TimeoutSec 30;$mode='RAW'}catch{$r=ApiContent $RepoPath;[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$expected=([string]$r.sha).ToLowerInvariant();$mode='API_FALLBACK'}
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($expected -and $actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw("${Label}_SHA_MISMATCH actual=$actual expected=$expected")}
  Move-Item -LiteralPath $tmp -Destination $Dest -Force;Log ($Label+'_REFRESHED_'+$mode+' sha='+$actual);return $actual
}
function RefreshPinnedFile([string]$Commit,[string]$Blob,[string]$RepoPath,[string]$Dest,[string]$Label){
  $tmp=$Dest+'.download';$u='https://raw.githubusercontent.com/'+$Repo+'/'+$Commit+'/'+$RepoPath
  Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{'User-Agent'='HomeDesign-AutoResume-V13-Pinned'} -OutFile $tmp -TimeoutSec 30
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual-ne$Blob.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw("${Label}_PIN_SHA_MISMATCH actual=$actual expected=$Blob")}
  Move-Item -LiteralPath $tmp -Destination $Dest -Force;Log ($Label+'_PINNED sha='+$actual);return $actual
}
function BootstrapLoopPresent{try{return @((Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})).Count -gt 0}catch{return $false}}
function DriveMirrorFixRunning{try{return @((Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like '*DriveMirrorExactDiffFinalize.py*'})).Count -gt 0}catch{return $false}}
function DriveMirrorAlreadyVerified{try{$p='F:\CENTRAL_AGENT_DATA\00_CONTROL\DRIVE_MIRROR_EXACT_DIFF_FINALIZE_LAST.json';if(Test-Path -LiteralPath $p){$j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json;return ([string]$j.status -eq 'VERIFIED_COMPLETE_X2')}else{return $false}}catch{return $false}}

Log ('AUTO_RESUME_START '+$Version)
try{[void](RefreshPinnedFile $WatchdogCommit $WatchdogBlob 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' $WatchdogLocal 'WATCHDOG')}catch{Log ('WATCHDOG_REFRESH_FAILED '+$_.Exception.Message);if(-not(Test-Path -LiteralPath $WatchdogLocal)){exit 2}}
try{[void](RefreshFile 'local-agent/bootstrap/AgentBootstrap.ps1' $BootstrapLocal 'BOOTSTRAP')}catch{Log ('BOOTSTRAP_REFRESH_FAILED '+$_.Exception.Message);if(-not(Test-Path -LiteralPath $BootstrapLocal)){exit 2}}
try{[void](RefreshPinnedFile $ResumeCommit $ResumeBlob 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1' $ResumeLocal 'RESUME_SCRIPT')}catch{Log ('RESUME_REFRESH_FAILED '+$_.Exception.Message);if(-not(Test-Path -LiteralPath $ResumeLocal)){exit 2}}
try{[void](RefreshFile 'local-agent/bootstrap/OpenAIWebSyncGuard.ps1' $OpenAISyncLocal 'OPENAI_WEB_SYNC')}catch{Log ('OPENAI_WEB_SYNC_REFRESH_FAILED '+$_.Exception.Message)}
try{[void](RefreshFile 'local-agent/bootstrap/DriveMirrorExactDiffFinalize.py' $DriveMirrorFixLocal 'DRIVE_MIRROR_EXACT_DIFF')}catch{Log ('DRIVE_MIRROR_FIX_REFRESH_FAILED '+$_.Exception.Message)}
try{[void](RefreshFile 'local-agent/python/central_control_worker_v1.py' $PythonControlLocal 'PYTHON_CONTROL')}catch{Log ('PYTHON_CONTROL_REFRESH_FAILED '+$_.Exception.Message)}
if(Test-Path -LiteralPath $PythonControlLocal){
  try{
    $pyc=(Get-Command python.exe -ErrorAction SilentlyContinue).Source
    if(-not$pyc){$pyc=(Get-Command python -ErrorAction SilentlyContinue).Source}
    if($pyc){
      $pyRaw=& $pyc $PythonControlLocal 2>&1|Out-String
      $pyRc=$LASTEXITCODE
      Log ('PYTHON_CONTROL_EXIT='+$pyRc+' '+($pyRaw.Trim()))
    }else{Log 'PYTHON_CONTROL_PYTHON_MISSING'}
  }catch{Log ('PYTHON_CONTROL_EXCEPTION '+$_.Exception.Message)}
}
if(Test-Path -LiteralPath $OpenAISyncLocal){
  try{$syncRaw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $OpenAISyncLocal -Apply 2>&1|Out-String;$syncRc=$LASTEXITCODE;Log ('OPENAI_WEB_SYNC_EXIT='+$syncRc+' '+($syncRaw.Trim()))}catch{Log ('OPENAI_WEB_SYNC_EXCEPTION '+$_.Exception.Message)}
}
if((Test-Path -LiteralPath $DriveMirrorFixLocal) -and -not(DriveMirrorAlreadyVerified) -and -not(DriveMirrorFixRunning)){
  try{$py=(Get-Command python.exe -ErrorAction SilentlyContinue).Source;if(-not$py){$py=(Get-Command python -ErrorAction SilentlyContinue).Source};if($py){Start-Process -FilePath $py -ArgumentList @("`"$DriveMirrorFixLocal`"") -WindowStyle Hidden|Out-Null;Log 'DRIVE_MIRROR_EXACT_DIFF_STARTED'}else{Log 'DRIVE_MIRROR_EXACT_DIFF_PYTHON_MISSING'}}catch{Log ('DRIVE_MIRROR_EXACT_DIFF_START_FAILED '+$_.Exception.Message)}
}else{Log ('DRIVE_MIRROR_EXACT_DIFF_SKIP verified='+(DriveMirrorAlreadyVerified)+' running='+(DriveMirrorFixRunning))}
try{
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$BootstrapLocal`""
  $bp=[Diagnostics.Process]::Start($psi)
  Log ('BOOTSTRAP_ONESHOT_STARTED pid='+$bp.Id)
}catch{Log ('BOOTSTRAP_ONESHOT_START_FAILED '+$_.Exception.Message)}
try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ResumeLocal;$rc=$LASTEXITCODE;Log ("RESUME_EXIT=$rc HOST_HEALTH="+(HostHealthy)+" BOOTSTRAP_LOOP="+(BootstrapLoopPresent));exit $rc}catch{Log ('RESUME_EXCEPTION '+$_.Exception.Message);exit 3}
