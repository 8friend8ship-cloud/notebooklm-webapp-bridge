param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.58'
$TargetHostVersion='1.3.0'
$ExpectedHostSha='274aef614763cfe1d886fd16c5641e0b64ab6176'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$HostPath=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$ResultRoot=Join-Path $Root 'CommandResults'
$X2='LOCAL_FLOW_BRIDGE_SMOKE_X2_20260829_1505_01'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlob([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function ApiContent([string]$Path){$headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'};$u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 20}
function SaveJson([string]$Path,$Obj){$p=Split-Path -Parent $Path;if($p){New-Item -ItemType Directory -Force -Path $p|Out-Null};$Obj|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{$null}}
function FindCentralRoot{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $target),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('My Drive\'+$target)),(Join-Path $d.Root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function CaptureTask($Central,[string]$TaskId){
  if(-not $Central){return $null};$dir=Join-Path $ResultRoot $TaskId;$s=ReadJson (Join-Path $dir 'status.json');$r=ReadJson (Join-Path $dir 'result.json');$o=[ordered]@{taskId=$TaskId;status=$s;result=$r;capturedAt=(Get-Date).ToString('o')};SaveJson (Join-Path $Central ('Runtime_Readback\CHROME\'+$TaskId+'_COMMAND_RESULT_CAPTURE.json')) $o;return $o
}

$central=FindCentralRoot;$errors=@();$x2Capture=$null;$hostApiSha='';$hostLocalSha='';$oldPids=@();$handoffPid=$null
try{$x2Capture=CaptureTask $central $X2}catch{$errors+=('X2_CAPTURE:'+$_.Exception.Message)}
try{
  $r=ApiContent 'local-agent/releases/1.3.0/HomeDesignLocalCommandHost.final.ps1'
  $hostApiSha=([string]$r.sha).ToLowerInvariant();if($hostApiSha -ne $ExpectedHostSha){throw ('HOST_API_SHA_MISMATCH:'+ $hostApiSha)}
  $tmp=$HostPath+'.1.3.0.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')));$hostLocalSha=(GitBlob $tmp).ToLowerInvariant();if($hostLocalSha -ne $ExpectedHostSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('HOST_FILE_SHA_MISMATCH:'+ $hostLocalSha)};Move-Item -LiteralPath $tmp -Destination $HostPath -Force

  try{$rows=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*LocalAgent*HomeDesignLocalCommandHost.ps1*'});$oldPids=@($rows|ForEach-Object{[int]$_.ProcessId});foreach($p in $oldPids){try{Stop-Process -Id $p -Force -ErrorAction SilentlyContinue}catch{}}}catch{$errors+=('HOST_STOP:'+ $_.Exception.Message)}

  $helper=Join-Path $Root 'Start-Host130-Delayed.ps1';$receiptPath=$(if($central){Join-Path $central 'Runtime_Readback\CHROME\HOST_1.3.0_CONTENTS_API_HANDOFF.json'}else{Join-Path $Root 'HOST_1.3.0_CONTENTS_API_HANDOFF.json'})
  $code=@'
param([string]$HostPath,[string]$ReceiptPath,[string]$ExpectedSha)
$ErrorActionPreference='Continue'
Start-Sleep -Seconds 2
$p=$null;$err=''
try{$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$HostPath+'"';$p=[Diagnostics.Process]::Start($psi)}catch{$err=$_.Exception.Message}
Start-Sleep -Seconds 2
$health=$null
try{$health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 5}catch{$err=($err+';HEALTH:'+ $_.Exception.Message).Trim(';')}
try{$par=Split-Path -Parent $ReceiptPath;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};[ordered]@{ok=[bool]($p -and $health -and [string]$health.version -eq '1.3.0');action='HOST_1.3.0_CONTENTS_API_HANDOFF';pid=$(if($p){[int]$p.Id}else{$null});health=$health;expectedSha=$ExpectedSha;error=$err;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{}
'@
  Set-Content -LiteralPath $helper -Value $code -Encoding UTF8
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -HostPath "'+$HostPath+'" -ReceiptPath "'+$receiptPath+'" -ExpectedSha "'+$ExpectedHostSha+'"';$p=[Diagnostics.Process]::Start($psi);$handoffPid=[int]$p.Id
}catch{$errors+=$_.Exception.Message}
$ok=($errors.Count -eq 0 -and $hostApiSha -eq $ExpectedHostSha -and $hostLocalSha -eq $ExpectedHostSha -and $handoffPid)
$receipt=[ordered]@{ok=[bool]$ok;action='HOST_1.3.0_CONTENTS_API_RECOVERY_DISPATCHED';agentVersion=$AgentVersion;targetHostVersion=$TargetHostVersion;expectedHostSha=$ExpectedHostSha;hostApiSha=$hostApiSha;hostLocalSha=$hostLocalSha;oldHostPids=$oldPids;handoffPid=$handoffPid;x2Capture=$x2Capture;normalChromeTouched=$false;dedicatedChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;errors=$errors;at=(Get-Date).ToString('o')}
SaveJson (Join-Path $Root 'HOST_1.3.0_CONTENTS_API_RECOVERY_DISPATCHED.json') $receipt
if($central){try{SaveJson (Join-Path $central 'Runtime_Readback\CHROME\HOST_1.3.0_CONTENTS_API_RECOVERY_DISPATCHED.json') $receipt}catch{}}
$receipt|ConvertTo-Json -Depth 50 -Compress
if($ok){exit 0}else{exit 2}
