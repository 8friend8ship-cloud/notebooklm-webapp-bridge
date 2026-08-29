param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.66'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Pinned1165='1153728d85e091ae5a914a4b67a5f494a14d675b'
$ExpectedBootstrap='321114c59e2cf0393be2c990971977fdc14ceb8c'
$ExpectedResume='288a157387f1ae896a7121d77b58fefe75db6cd0'
$ExpectedAutoResume='a9ffb2f7399efc3943958d35dfcd7e01f3f1e4cb'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Resume=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1'
$AutoResume=Join-Path $Root 'HomeDesignAutoResume.ps1'
$Receipt=Join-Path $Root 'BOOTSTRAP_CONTENTS_API_RECOVERY_1.1.66.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Api([string]$p){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$p+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'} -TimeoutSec 20}
function InstallApi([string]$repoPath,[string]$dest,[string]$expected){$r=Api $repoPath;$apiSha=([string]$r.sha).ToLowerInvariant();if($apiSha-ne$expected){throw('API_SHA:'+ $repoPath+':'+$apiSha+':'+$expected)};$tmp=$dest+'.1166';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$actual=(Blob $tmp).ToLowerInvariant();if($actual-ne$expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('LOCAL_SHA:'+ $repoPath+':'+$actual+':'+$expected)};Move-Item $tmp $dest -Force;return $actual}
function ReadJ([string]$p){if(Test-Path $p){try{return Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}}
function SaveJ([string]$p,$o){$d=Split-Path $p -Parent;if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null};$o|ConvertTo-Json -Depth 60|Set-Content $p -Encoding UTF8}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c){return $c}}};''}
$errors=@();$baseOk=$false;$bootstrapOk=$false;$resumeOk=$false;$autoResumeOk=$false;$replacementScheduled=$false;$central=Central
try{$r=Api 'local-agent/releases/1.1.65/HomeDesignLocalAgent.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$Pinned1165){throw('BASE_1165_API_SHA:'+[string]$r.sha)};$tmp=Join-Path $Root 'HomeDesignLocalAgent-1.1.65-pinned.ps1';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$Pinned1165){throw'BASE_1165_LOCAL_SHA'};& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp;$rc=$LASTEXITCODE;$baseOk=($rc-eq0);if(-not$baseOk){throw('BASE_1165_EXIT_'+$rc)}}catch{$errors+=('BASE:'+ $_.Exception.Message)}
try{[void](InstallApi 'local-agent/bootstrap/AgentBootstrap.ps1' $Bootstrap $ExpectedBootstrap);$bootstrapOk=$true}catch{$errors+=('BOOTSTRAP:'+ $_.Exception.Message)}
try{[void](InstallApi 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1' $Resume $ExpectedResume);$resumeOk=$true}catch{$errors+=('RESUME:'+ $_.Exception.Message)}
try{[void](InstallApi 'local-agent/bootstrap/HomeDesignAutoResume.ps1' $AutoResume $ExpectedAutoResume);$autoResumeOk=$true}catch{$errors+=('AUTO_RESUME:'+ $_.Exception.Message)}
try{
  $helper=Join-Path $Root 'ReplaceBootstrapLoop-1.1.66.ps1'
  @'
Start-Sleep -Seconds 7
try{
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*AgentBootstrap.ps1*' -and $_.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)' })){
    try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}
  }
}catch{}
Start-Sleep -Seconds 2
$bootstrap=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent\AgentBootstrap.ps1'
if(Test-Path -LiteralPath $bootstrap){Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$bootstrap`"",'-Loop') -WindowStyle Hidden|Out-Null}
'@ | Set-Content -LiteralPath $helper -Encoding ASCII
  Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$helper`"") -WindowStyle Hidden|Out-Null
  $replacementScheduled=$true
}catch{$errors+=('LOOP_REPLACE:'+ $_.Exception.Message)}
try{$s=ReadJ $State;if(-not$s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member bootstrapSha $ExpectedBootstrap -Force;$s|Add-Member resumeSha $ExpectedResume -Force;$s|Add-Member autoResumeSha $ExpectedAutoResume -Force;$s|Add-Member stableResolution 'GITHUB_CONTENTS_API_SHA_PINNED' -Force;$s|Add-Member status $(if($baseOk-and$bootstrapOk-and$resumeOk-and$autoResumeOk-and$replacementScheduled){'BOOTSTRAP_CONTENTS_API_RECOVERY_APPLIED'}else{'BOOTSTRAP_CONTENTS_API_RECOVERY_FAILED'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJ $State $s}catch{$errors+=('STATE:'+ $_.Exception.Message)}
$ok=($baseOk-and$bootstrapOk-and$resumeOk-and$autoResumeOk-and$replacementScheduled-and$errors.Count-eq0)
$rec=[ordered]@{ok=$ok;action='BOOTSTRAP_CONTENTS_API_RECOVERY';agentVersion=$AgentVersion;baseAgent='1.1.65';baseAgentSha=$Pinned1165;bootstrapSha=$ExpectedBootstrap;resumeSha=$ExpectedResume;autoResumeSha=$ExpectedAutoResume;stableResolution='GITHUB_CONTENTS_API_SHA_PINNED';bootstrapLoopReplacementScheduled=$replacementScheduled;targetBridge='0.2.76';targetHost='1.3.0';normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;errors=$errors;at=(Get-Date).ToString('o')};SaveJ $Receipt $rec;if($central){SaveJ (Join-Path $central 'Runtime_Readback\BOOTSTRAP_CONTENTS_API_RECOVERY_1.1.66.json') $rec};$rec|ConvertTo-Json -Depth 60 -Compress;if($ok){exit 0}else{exit 2}
