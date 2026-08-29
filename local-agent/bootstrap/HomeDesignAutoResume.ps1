param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Log=Join-Path $Root 'auto-resume.log'
$ResumeLocal=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1'
$BootstrapLocal=Join-Path $Root 'AgentBootstrap.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Log([string]$m){Add-Content -LiteralPath $Log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function GitBlobSha1([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0));$all=New-Object byte[]($header.Length+$bytes.Length);[Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length);$sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}}
function ApiContent([string]$Path){$headers=@{'User-Agent'='HomeDesign-AutoResume';'Accept'='application/vnd.github+json'};$url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30}
function RefreshApiFile([string]$RepoPath,[string]$Dest,[string]$Label){$r=ApiContent $RepoPath;$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$actual=(GitBlobSha1 $tmp).ToLowerInvariant();$expected=([string]$r.sha).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw("${Label}_SHA_MISMATCH actual=$actual expected=$expected")};Move-Item -LiteralPath $tmp -Destination $Dest -Force;Log ($Label+'_REFRESHED_API sha='+$expected);return $expected}
function BootstrapLoopPresent{try{return @((Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'})).Count -gt 0}catch{return $false}}

Log 'AUTO_RESUME_START_CONTENTS_API_V4_MULTILANE_REFRESH'
$networkReady=$false
for($i=0;$i-lt12;$i++){try{$r=ApiContent 'local-agent/stable/agent.json';if($r.sha){$networkReady=$true;break}}catch{Start-Sleep -Seconds 5}}
if(-not$networkReady){Log 'CONTENTS_API_NETWORK_NOT_READY'}
try{[void](RefreshApiFile 'local-agent/bootstrap/AgentBootstrap.ps1' $BootstrapLocal 'BOOTSTRAP')}catch{Log ('BOOTSTRAP_API_DOWNLOAD_FAILED '+$_.Exception.Message);if(-not(Test-Path -LiteralPath $BootstrapLocal)){exit 2}}
try{[void](RefreshApiFile 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1' $ResumeLocal 'RESUME_SCRIPT')}catch{Log ('RESUME_API_DOWNLOAD_FAILED '+$_.Exception.Message);if(-not(Test-Path -LiteralPath $ResumeLocal)){exit 2}}
if(-not(BootstrapLoopPresent)){
  try{Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapLocal`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 2;Log ('BOOTSTRAP_LOOP_DIRECT_START='+(BootstrapLoopPresent))}catch{Log ('BOOTSTRAP_LOOP_START_FAILED '+$_.Exception.Message)}
}else{Log 'BOOTSTRAP_LOOP_ALREADY_PRESENT'}
try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ResumeLocal;$rc=$LASTEXITCODE;Log ("RESUME_EXIT=$rc HOST_HEALTH="+(HostHealthy)+" BOOTSTRAP_LOOP="+(BootstrapLoopPresent));exit $rc}catch{Log ('RESUME_EXCEPTION '+$_.Exception.Message);exit 3}
