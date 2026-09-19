param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Version='APPSCRIPT_RECOVERY_LANE_0.3.17_REMOTE_INDEPENDENT_20260919'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt=Join-Path $Root 'APPSCRIPT_RECOVERY_LANE_0.3.17.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FetchVerified([string]$RepoPath,[string]$Dest){$u='https://api.github.com/repos/'+$Repo+'/contents/'+$RepoPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Recovery-Lane';'Accept'='application/vnd.github+json';'Cache-Control'='no-cache'} -TimeoutSec 30;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$actual=(GitBlobSha1Bytes $b).ToLowerInvariant();$expected=([string]$x.sha).ToLowerInvariant();if(-not$expected-or$actual-ne$expected){throw ('SHA_MISMATCH:'+ $RepoPath)};[IO.File]::WriteAllBytes(($Dest+'.download'),$b);Move-Item ($Dest+'.download') $Dest -Force;return $actual}
function RunPs([string]$Path,[int]$TimeoutSec){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Path+'"';$p=[Diagnostics.Process]::Start($psi);if(-not$p.WaitForExit($TimeoutSec*1000)){try{& taskkill.exe /PID ([int]$p.Id) /T /F 2>$null|Out-Null}catch{};return 124};try{return [int]$p.ExitCode}catch{return 1}}
$r=[ordered]@{ok=$false;version=$Version;startedAt=(Get-Date).ToString('o');installerSha='';coordinatorSha='';installerExit=$null;coordinatorExit=$null;remoteDcDependency=$false;reboot=$false;reauth=$false;oauth=$false;broadKill=$false;completedAt='';errors=@()}
try{$installer=Join-Path $Root 'INSTALL_AUTO_RESUME_TASK.ps1';$coord=Join-Path $Root 'HomeDesignRecoveryCoordinator.ps1';$r.installerSha=FetchVerified 'local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1' $installer;$r.coordinatorSha=FetchVerified 'local-agent/bootstrap/HomeDesignRecoveryCoordinator.ps1' $coord;$r.installerExit=RunPs $installer 700;$r.coordinatorExit=RunPs $coord 900;$r.ok=([int]$r.installerExit-eq0 -and [int]$r.coordinatorExit-eq0)}catch{$r.errors+=$_.Exception.Message}finally{$r.completedAt=(Get-Date).ToString('o');$r|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Receipt -Encoding UTF8}
$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 2}
