param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.141-image-task203-host130-rawrepair'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$HostCommit='c89a1ab4e5f118c6ef90910b1c67d2a866f59316'
$HostPathRepo='local-agent/releases/1.3.0/HomeDesignLocalCommandHost.final.ps1'
$HostBaseSha='274aef614763cfe1d886fd16c5641e0b64ab6176'
$RepairCommit='bcb3d6d8c04c54e1723938a82aa4f195c66eee82'
$RepairSha='a0b7bddb37f6c2623a2d56dc3750c02c244aa90a'
$ChildCommit='6615fd683d547f0eadf50202967a5c3574e9ebf6'
$ChildPathRepo='local-agent/releases/1.1.136-image-task203/HomeDesignLocalAgent.ps1'
$ChildSha='f08f8a586f3405ce9019c370fe504557d03b3b70'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$HostPath=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save([string]$name,$o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $name) -Encoding UTF8;try{$c=Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $name) -Encoding UTF8}}catch{}}
function RawVerified([string]$Commit,[string]$RepoPath,[string]$Dest,[string]$Expected){$u='https://raw.githubusercontent.com/'+$Repo+'/'+$Commit+'/'+$RepoPath+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$tmp=$Dest+'.download';Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{'User-Agent'='HomeDesign-Image-Task203-Host130'} -OutFile $tmp -TimeoutSec 30;$actual=(Blob $tmp).ToLowerInvariant();if($actual-ne$Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('RAW_SHA_MISMATCH:'+ $RepoPath+':'+$actual)};Move-Item $tmp $Dest -Force;return $actual}
function Health{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
$r=[ordered]@{ok=$false;action='IMAGE_TASK203_HOST130_PINNED_REPAIR_RECOVERY_AND_RUN';version=$Version;targetHost='1.3.0';hostBaseSha=$HostBaseSha;hostPatchedSha='';repairCommit=$RepairCommit;repairSha=$RepairSha;childSha=$ChildSha;oldHealth=$null;newHealth=$null;oldHostPids=@();newHostPid=$null;childExit=$null;stage='START';error='';duplicateTaskCreated=$false;newAppsScriptProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;startedAt=(Get-Date).ToString('o')}
try{
  $r.oldHealth=Health
  $base=Join-Path $Root 'HomeDesignLocalCommandHost.1.3.0.base.ps1'
  $r.stage='FETCH_VERIFIED_HOST130_BASE'
  [void](RawVerified $HostCommit $HostPathRepo $base $HostBaseSha)
  $text=Get-Content -LiteralPath $base -Raw -Encoding UTF8
  $old=@'
$apiUrl='https://api.github.com/repos/'+[string]$rule.repo+'/contents/'+$safeScript+'?ref='+[Uri]::EscapeDataString([string]$rule.branch)+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$headers=@{'User-Agent'='HomeDesign-Local-Command-Host';'Accept'='application/vnd.github+json'};$resp=Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -TimeoutSec 15;if(-not $resp.content){throw 'SCRIPT_CONTENTS_API_EMPTY'};$localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));[IO.File]::WriteAllBytes($localScript,[Convert]::FromBase64String(([string]$resp.content -replace '\s','')));$apiSha=([string]$resp.sha).ToLowerInvariant();$localSha=(GitBlobSha1 $localScript).ToLowerInvariant();if(-not $apiSha -or $apiSha -ne $localSha){Remove-Item -LiteralPath $localScript -Force -ErrorAction SilentlyContinue;throw ('SCRIPT_CONTENTS_API_SHA_MISMATCH api='+$apiSha+' local='+$localSha)}
'@
  $new=@'
$localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));$apiSha=''
  if([string]$rule.repo -eq '8friend8ship-cloud/contents-os-git' -and [string]$rule.branch -eq 'main' -and $safeScript -eq 'tools/Repair-ContentOS-DriveCacheAppsScript.ps1'){
    $pinnedCommit='bcb3d6d8c04c54e1723938a82aa4f195c66eee82';$pinnedSha='a0b7bddb37f6c2623a2d56dc3750c02c244aa90a'
    $rawUrl='https://raw.githubusercontent.com/'+[string]$rule.repo+'/'+$pinnedCommit+'/'+$safeScript+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -Headers @{'User-Agent'='HomeDesign-Local-Command-Host'} -OutFile $localScript -TimeoutSec 30
    $apiSha=$pinnedSha
  }else{
    $apiUrl='https://api.github.com/repos/'+[string]$rule.repo+'/contents/'+$safeScript+'?ref='+[Uri]::EscapeDataString([string]$rule.branch)+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$headers=@{'User-Agent'='HomeDesign-Local-Command-Host';'Accept'='application/vnd.github+json'};$resp=Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -TimeoutSec 15;if(-not $resp.content){throw 'SCRIPT_CONTENTS_API_EMPTY'};[IO.File]::WriteAllBytes($localScript,[Convert]::FromBase64String(([string]$resp.content -replace '\s','')));$apiSha=([string]$resp.sha).ToLowerInvariant()
  }
  $localSha=(GitBlobSha1 $localScript).ToLowerInvariant();if(-not $apiSha -or $apiSha -ne $localSha){Remove-Item -LiteralPath $localScript -Force -ErrorAction SilentlyContinue;throw ('SCRIPT_SOURCE_SHA_MISMATCH expected='+$apiSha+' local='+$localSha)}
'@
  if(-not $text.Contains($old)){throw 'HOST130_FETCH_BLOCK_NOT_FOUND_EXACTLY'}
  $patched=$text.Replace($old,$new)
  Set-Content -LiteralPath $HostPath -Value $patched -Encoding UTF8
  $r.hostPatchedSha=(Blob $HostPath).ToLowerInvariant()
  $r.stage='RESTART_PATCHED_HOST130'
  try{$rows=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*LocalAgent*HomeDesignLocalCommandHost.ps1*'});$r.oldHostPids=@($rows|ForEach-Object{[int]$_.ProcessId});foreach($p in $r.oldHostPids){try{Stop-Process -Id $p -Force -ErrorAction SilentlyContinue}catch{}}}catch{}
  Start-Sleep -Milliseconds 700
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$HostPath+'"';$hp=[Diagnostics.Process]::Start($psi);$r.newHostPid=[int]$hp.Id
  for($i=0;$i-lt30;$i++){Start-Sleep -Milliseconds 500;$h=Health;if($h -and [string]$h.version -eq '1.3.0' -and [bool]$h.asyncJobs){$r.newHealth=$h;break}}
  if(-not $r.newHealth){throw('PATCHED_HOST130_START_HEALTH_FAILED:'+((Health|ConvertTo-Json -Compress -Depth 10)))}
  $r.stage='FETCH_TASK203_CHILD_RAW'
  $child=Join-Path $Root 'HomeDesignLocalAgent-image-task203-child-1.1.136.ps1'
  [void](RawVerified $ChildCommit $ChildPathRepo $child $ChildSha)
  $r.stage='RUN_TASK203_CHILD'
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child
  $r.childExit=$LASTEXITCODE
  if($LASTEXITCODE-ne0){throw('TASK203_CHILD_EXIT_'+$LASTEXITCODE)}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save 'IMAGE_TASK203_HOST130_PINNED_REPAIR_1.1.141.json' $r}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}
