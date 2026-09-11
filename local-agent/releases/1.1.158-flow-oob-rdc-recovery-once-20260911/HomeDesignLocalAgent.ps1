param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.158-flow-oob-rdc-recovery-once-20260911'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$KeepAlive=Join-Path $Root 'DesktopCommanderKeepAlive.ps1'
$Receipt=Join-Path $Root 'FLOW_OOB_RDC_RECOVERY_1.1.158.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 30;try{$j|Set-Content -LiteralPath $Receipt -Encoding UTF8}catch{};try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'FLOW_OOB_RDC_RECOVERY_1.1.158.json') -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;version=$Version;startedAt=(Get-Date).ToString('o');keepAliveFetched=$false;keepAliveExit=$null;errors=@();newTrigger=$false;newOAuth=$false;normalChromeTouched=$false;broadNodeKill=$false;globalExecutionPolicyChanged=$false}
try{
 $tmp=$KeepAlive+'.download';$u='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/bootstrap/DesktopCommanderKeepAlive.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{'User-Agent'='HomeDesign-Flow-OOB-RdcRecovery'} -OutFile $tmp -TimeoutSec 30;Move-Item -LiteralPath $tmp -Destination $KeepAlive -Force;$r.keepAliveFetched=$true
 $raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $KeepAlive 2>&1|Out-String;$r.keepAliveExit=$LASTEXITCODE;$r.keepAliveOutput=$raw.Trim();$r.ok=([int]$LASTEXITCODE-eq0)
}catch{$r.errors+=$_.Exception.Message}
$r.completedAt=(Get-Date).ToString('o');Save $r;$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 4}
