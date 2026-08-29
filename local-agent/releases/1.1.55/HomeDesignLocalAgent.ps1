param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.55'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$PreviousPath=Join-Path $Root 'HomeDesignLocalAgent-1.1.54.ps1'
$PreviousBlob='cf7a9a42275c427bf48cd777a5bde82eea0607ab'
$HostInstaller=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.9.ps1'
$HostBlob='2b58e72d35fb8b8e56b179fc89dbc7ba7ac3a577'
$ExpectedHost='1.2.9'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function GitHubBlob([string]$Sha){$headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'};return Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/git/blobs/'+$Sha+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -Method Get -TimeoutSec 20}
function FetchBlob([string]$Sha,[string]$Destination){$r=GitHubBlob $Sha;$tmp=$Destination+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')));$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Sha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('PINNED_BLOB_MISMATCH:'+ $actual+':'+$Sha)};Move-Item -LiteralPath $tmp -Destination $Destination -Force;return $actual}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function SaveJson([string]$Path,$Object){$par=Split-Path -Parent $Path;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};$Object|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $Path -Encoding UTF8}
function FindCentralRoot{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $target),(Join-Path $d.Root ('My Drive\'+$target)),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function StopHost{try{foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)){if([string]$p.CommandLine -match '(?i)HomeDesignLocalCommandHost(?:-1\.2\.\d+|-1\.2\.\d+-patched)?\.ps1'){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}}}catch{};Start-Sleep -Seconds 1}
function StartHost([string]$Path){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Path`"") -WindowStyle Hidden|Out-Null;$deadline=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 500;$h=HostHealth;if($h -and [bool]$h.ok -and [string]$h.version -eq $ExpectedHost){return $h}}while((Get-Date)-lt $deadline);return (HostHealth)}
$errors=@();$hostBefore=HostHealth;$previousSha='';$hostSha='';$hostAfter=$null;$previousStarted=$false;$central=FindCentralRoot
try{$hostSha=FetchBlob $HostBlob $HostInstaller;StopHost;$hostAfter=StartHost $HostInstaller;if(-not $hostAfter -or -not [bool]$hostAfter.ok -or [string]$hostAfter.version -ne $ExpectedHost){throw ('HOST_1.2.9_READBACK_FAILED:'+($hostAfter|ConvertTo-Json -Compress))}}catch{$errors+=('HOST_RECOVERY:'+$_.Exception.Message)}
try{$previousSha=FetchBlob $PreviousBlob $PreviousPath;Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$PreviousPath`"") -WindowStyle Hidden|Out-Null;$previousStarted=$true}catch{$errors+=('PREVIOUS_AGENT_START:'+$_.Exception.Message)}
$ok=[bool]($hostSha -eq $HostBlob -and $hostAfter -and [bool]$hostAfter.ok -and [string]$hostAfter.version -eq $ExpectedHost)
$receipt=[ordered]@{ok=$ok;action='AGENT_1.1.55_HOST_SOURCE_CACHE_RECOVERY';agentVersion=$AgentVersion;hostBefore=$hostBefore;hostAfter=$hostAfter;hostInstallerBlob=$hostSha;expectedHostVersion=$ExpectedHost;previousAgentBlob=$previousSha;previousAgentStarted=$previousStarted;sourceFetchMode='IMMUTABLE_GIT_BLOB_API';normalChromeTouched=$false;newOAuth=$false;newProject=$false;newDeployment=$false;newTrigger=$false;generateClicked=$false;creditSpend=$false;errors=$errors;at=(Get-Date).ToString('o')}
try{$s=ReadJson $State;if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member agentMode 'HOST_SOURCE_CACHE_RECOVERY_1.1.55' -Force;$s|Add-Member hostVersion $(if($hostAfter){[string]$hostAfter.version}else{'UNKNOWN'}) -Force;$s|Add-Member hostHealthy $ok -Force;$s|Add-Member status $(if($ok){'HOST_1.2.9_IMMUTABLE_RECOVERY_PASS'}else{'HOST_RECOVERY_HOLD'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $State $s}catch{}
if($central){try{$rr=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $rr|Out-Null;SaveJson (Join-Path $rr 'AGENT_1.1.55_HOST_SOURCE_CACHE_RECOVERY.json') $receipt}catch{}}
$receipt|ConvertTo-Json -Depth 60 -Compress
if($ok){exit 0}else{exit 2}
