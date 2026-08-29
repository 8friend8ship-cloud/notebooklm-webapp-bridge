param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.61'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$A59=Join-Path $Root 'HomeDesignLocalAgent-1.1.59.ps1'
$A60=Join-Path $Root 'HomeDesignLocalAgent-1.1.60.ps1'
$Blob59='5351129b3b524bda5b7c5ad63c75f74fea1d32a3'
$Blob60='6880f7aaba46222be6d88274c54e5728edb14bd9'
$LocalReceipt=Join-Path $Root 'FLOW_COMPAT_MERGE_1.1.61.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FetchBlob([string]$Sha,[string]$Destination){$headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'};$r=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/git/blobs/'+$Sha+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -Method Get -TimeoutSec 20;$tmp=$Destination+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')));$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Sha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('PINNED_BLOB_MISMATCH:'+ $actual+':'+$Sha)};Move-Item -LiteralPath $tmp -Destination $Destination -Force;return $actual}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function SaveJson([string]$Path,$Object){$par=Split-Path -Parent $Path;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};$Object|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $Path -Encoding UTF8}
function FindCentralRoot{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $target),(Join-Path $d.Root ('My Drive\'+$target)),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function RunPinned([string]$Path,[int]$TimeoutMs){$p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"`"$Path`"") -WindowStyle Hidden -PassThru;$done=$p.WaitForExit($TimeoutMs);if(-not $done){try{Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}catch{};return [pscustomobject]@{exited=$false;exitCode=$null;timeout=$true}};return [pscustomobject]@{exited=$true;exitCode=$p.ExitCode;timeout=$false}}
$errors=@();$sha59='';$sha60='';$r59=$null;$r60=$null
try{$sha59=FetchBlob $Blob59 $A59;$r59=RunPinned $A59 180000;if($r59.timeout){$errors+='AGENT_1.1.59_TIMEOUT'}}catch{$errors+=('AGENT_1.1.59:'+$_.Exception.Message)}
try{$sha60=FetchBlob $Blob60 $A60;$r60=RunPinned $A60 240000;if($r60.timeout){$errors+='AGENT_1.1.60_TIMEOUT'}}catch{$errors+=('AGENT_1.1.60:'+$_.Exception.Message)}
$flow=ReadJson (Join-Path $Root 'FLOW_UNIFIED_RECOVERY_1.1.60.json')
$image=ReadJson (Join-Path $Root 'CHATGPT_IMAGE_AUTO_LIVE_READBACK.json')
$flowOk=[bool]($flow -and $flow.ok -eq $true -and [string]$flow.bridgeVersion -eq '0.2.74' -and [string]$flow.hostVersion -eq '1.3.0')
$imageRecorded=[bool]($image -and [string]$image.agentVersion -eq '1.1.59')
$ok=[bool]($errors.Count -eq 0 -and $r60 -and $r60.exitCode -eq 0 -and $flowOk -and $imageRecorded)
$central=FindCentralRoot
$receipt=[ordered]@{ok=$ok;action='PRESERVE_1.1.59_THEN_FLOW_1.1.60';agentVersion=$AgentVersion;agent159Blob=$sha59;agent159Exit=$(if($r59){$r59.exitCode}else{$null});agent160Blob=$sha60;agent160Exit=$(if($r60){$r60.exitCode}else{$null});chatgptImageReadbackRecorded=$imageRecorded;chatgptImageStatus=$(if($image){[string]$image.status}else{''});flowRecoveryOk=$flowOk;bridgeVersion=$(if($flow){[string]$flow.bridgeVersion}else{''});hostVersion=$(if($flow){[string]$flow.hostVersion}else{''});dedicatedCftRestarted=$(if($flow){[bool]$flow.dedicatedCftRestarted}else{$false});normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;errors=$errors;at=(Get-Date).ToString('o')}
SaveJson $LocalReceipt $receipt
if($central){try{SaveJson (Join-Path $central 'Runtime_Readback\FLOW_COMPAT_MERGE_1.1.61.json') $receipt}catch{}}
try{$s=ReadJson $State;if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member status $(if($ok){'FLOW_COMPAT_MERGE_PASS'}else{'FLOW_COMPAT_MERGE_FAILED'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $State $s}catch{}
$receipt|ConvertTo-Json -Depth 60 -Compress
if($ok){exit 0}else{exit 2}
