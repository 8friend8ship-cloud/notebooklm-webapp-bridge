param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.147-bootstrap-maintenance-sentinel'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ExpectedBootstrapSha='728d39aa7e3d78457263e3a585a5e6945bd1362a'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Marker=Join-Path $Root 'BOOTSTRAP_MAINTENANCE_SENTINEL_147.json'
$Receipt='BOOTSTRAP_MAINTENANCE_SENTINEL_1.1.147.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function Save($o){$j=$o|ConvertTo-Json -Depth 30;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;action='BOOTSTRAP_MAINTENANCE_SENTINEL';version=$Version;alreadyDone=$false;bootstrapExpectedSha=$ExpectedBootstrapSha;bootstrapActualSha='';parentPid=0;parentValidated=$false;helperStarted=$false;normalChromeTouched=$false;hostTouched=$false;tabletLockTouched=$false;oauthChanged=$false;scopeChanged=$false;newTask=$false;newTrigger=$false;newDeployment=$false;startedAt=(Get-Date).ToString('o');completedAt='';error=''}
try{
  $already=$false
  if(Test-Path -LiteralPath $Marker){try{$mj=Get-Content -LiteralPath $Marker -Raw -Encoding UTF8|ConvertFrom-Json;if([bool]$mj.done -and [string]$mj.bootstrapSha -eq $ExpectedBootstrapSha){$already=$true;$r.ok=$true;$r.alreadyDone=$true;$r.bootstrapActualSha=[string]$mj.bootstrapSha}}catch{}}
  if(-not$already){
    $headers=@{'User-Agent'='HomeDesign-Bootstrap-Maintenance-Sentinel';'Accept'='application/vnd.github+json'}
    $url='https://api.github.com/repos/'+$Repo+'/contents/local-agent/bootstrap/AgentBootstrap.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $meta=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
    if(([string]$meta.sha).ToLowerInvariant() -ne $ExpectedBootstrapSha){throw('BOOTSTRAP_API_SHA_MISMATCH:'+([string]$meta.sha))}
    $tmp=$Bootstrap+'.refresh147';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$meta.content-replace'\s','')))
    $actual=(GitBlobSha1 $tmp).ToLowerInvariant();$r.bootstrapActualSha=$actual;if($actual-ne$ExpectedBootstrapSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('BOOTSTRAP_LOCAL_SHA_MISMATCH:'+ $actual)}
    Move-Item -LiteralPath $tmp -Destination $Bootstrap -Force
    $self=Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID) -ErrorAction Stop
    $parentPid=[int]$self.ParentProcessId;$parent=Get-CimInstance Win32_Process -Filter ('ProcessId='+$parentPid) -ErrorAction Stop;$pcmd=[string]$parent.CommandLine
    if($parent.Name -notmatch '(?i)powershell|pwsh' -or $pcmd -notmatch '(?i)AgentBootstrap\.ps1' -or $pcmd -notmatch '(?i)(?:^|\s)-Loop(?:\s|$)'){throw('PARENT_NOT_AGENTBOOTSTRAP_LOOP:PID='+$parentPid+' CMD='+$pcmd)}
    $r.parentPid=$parentPid;$r.parentValidated=$true
    [ordered]@{done=$true;bootstrapSha=$ExpectedBootstrapSha;oldPid=$parentPid;at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $Marker -Encoding UTF8
    $helper=Join-Path $Root 'RESTART_AGENTBOOTSTRAP_LOOP_147.ps1'
    $helperText=@'
param([int]$OldPid,[string]$Bootstrap,[string]$Root)
$ErrorActionPreference='SilentlyContinue'
Start-Sleep -Seconds 3
try{$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$OldPid);if($p -and [string]$p.CommandLine -match '(?i)AgentBootstrap\.ps1' -and [string]$p.CommandLine -match '(?i)(?:^|\s)-Loop(?:\s|$)'){Stop-Process -Id $OldPid -Force -ErrorAction SilentlyContinue}}catch{}
Start-Sleep -Seconds 2
try{Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$Bootstrap+'"'),'-Loop') -WindowStyle Hidden|Out-Null}catch{}
try{[ordered]@{ok=$true;action='AGENTBOOTSTRAP_LOOP_RESTART_HELPER_147';oldPid=$OldPid;bootstrap=$Bootstrap;at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Root 'BOOTSTRAP_LOOP_RESTART_HELPER_147.json') -Encoding UTF8}catch{}
'@
    Set-Content -LiteralPath $helper -Value $helperText -Encoding UTF8
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$helper+'"'),'-OldPid',[string]$parentPid,'-Bootstrap',('"'+$Bootstrap+'"'),'-Root',('"'+$Root+'"')) -WindowStyle Hidden|Out-Null
    $r.helperStarted=$true;$r.ok=$true
  }
}catch{$r.error=$_.Exception.Message}
$r.completedAt=(Get-Date).ToString('o');Save $r
$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 2}
