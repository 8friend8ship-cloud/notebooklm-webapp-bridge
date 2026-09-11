param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='REMOTE_DC_DATA_PLANE_GUARD_V1_20260911'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DcRoot=Join-Path $Base 'DesktopCommander'
$DcCache=Join-Path $DcRoot 'npm-cache'
$StatePath=Join-Path $DcRoot 'data-plane-guard-state.json'
$ReceiptPath=Join-Path $DcRoot 'REMOTE_DC_DATA_PLANE_GUARD_LAST.json'
$OutLog=Join-Path $DcRoot 'remote.stdout.log'
$ErrLog=Join-Path $DcRoot 'remote.stderr.log'
$Package='@wonderwhy-er/desktop-commander@0.2.48'
New-Item -ItemType Directory -Force -Path $Root,$DcRoot,$DcCache|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function SaveReceipt($o){try{$j=$o|ConvertTo-Json -Depth 20;$j|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'REMOTE_DC_DATA_PLANE_GUARD_LAST.json') -Encoding UTF8}}catch{}}
function GetAll{try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{@()}}
function GetRemote([array]$all){$esc=[regex]::Escape($DcCache);@($all|Where-Object{$cmd=[string]$_.CommandLine;([string]$_.Name)-match'(?i)^node(?:\.exe)?$'-and$cmd-and$cmd-match'(?i)desktop-commander'-and$cmd-match'(?i)(?:^|\s)remote(?:\s|$)'-and$cmd-match$esc})}
function TcpCount([array]$p){$ids=@($p|ForEach-Object{[int]$_.ProcessId});if($ids.Count-eq0){return 0};try{[int](@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains[int]$_.OwningProcess}).Count)}catch{0}}
function StopExact([array]$p){$ids=@();foreach($x in $p){try{$id=[int]$x.ProcessId;if($id-gt0){& taskkill.exe /PID $id /T /F 2>$null|Out-Null;if($LASTEXITCODE-eq0){$ids+=$id}}}catch{}};@($ids)}
function StartRemote{$old=$env:npm_config_cache;try{$env:npm_config_cache=$DcCache;$args=@('--yes',$Package,'remote','--persist-session');$p=Start-Process -FilePath 'npx.cmd' -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -PassThru;Start-Sleep -Seconds 5;[pscustomobject]@{ok=$true;launcherPid=[int]$p.Id}}catch{[pscustomobject]@{ok=$false;launcherPid=0;error=$_.Exception.Message}}finally{$env:npm_config_cache=$old}}
function FetchControl{try{$u='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/control/remote-dc-recovery.json?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-RestMethod -Uri $u -TimeoutSec 15}catch{$null}}
$control=FetchControl
$state=$null;try{if(Test-Path $StatePath){$state=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$requestId=if($control){[string]$control.requestId}else{''};$enabled=[bool]($control-and$control.enabled)
$already=([string]$state.completedRequestId-eq$requestId-and$requestId)
$before=GetRemote (GetAll);$tcpBefore=TcpCount $before
$o=[ordered]@{ok=$true;action='REMOTE_DC_DATA_PLANE_ONE_SHOT_RECOVERY';version=$Version;requestId=$requestId;enabled=$enabled;alreadyCompleted=[bool]$already;remoteBefore=[int]$before.Count;tcpBefore=[int]$tcpBefore;stopped=@();started=$false;remoteAfter=0;tcpAfter=0;cloudDataPlaneVerified=$false;cloudVerificationRequired='GET_CONFIG_OR_LIST_PROCESSES_PLUS_FILE_RW_X2';broadNodeKill=$false;globalNpmCacheTouched=$false;globalExecutionPolicyChanged=$false;startedAt=(Get-Date).ToString('o');completedAt='';error=''}
if($enabled-and$requestId-and-not$already){try{$o.stopped=@(StopExact $before);Start-Sleep -Seconds 2;$launch=StartRemote;$o.started=[bool]$launch.ok;if(-not$launch.ok){throw [string]$launch.error};$after=GetRemote (GetAll);$o.remoteAfter=[int]$after.Count;$o.tcpAfter=[int](TcpCount $after);$o.ok=($o.remoteAfter-gt0-and$o.tcpAfter-gt0);if($o.ok){[ordered]@{completedRequestId=$requestId;completedAt=(Get-Date).ToString('o');version=$Version}|ConvertTo-Json|Set-Content -LiteralPath $StatePath -Encoding UTF8}}catch{$o.ok=$false;$o.error=$_.Exception.Message}}
$o.completedAt=(Get-Date).ToString('o');SaveReceipt $o;$o|ConvertTo-Json -Depth 20
if($o.ok){exit 0}else{exit 4}