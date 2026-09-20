param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='REMOTE_DC_DATA_PLANE_GUARD_V10_0251_20260921'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DcRoot=Join-Path $Base 'DesktopCommander'
$DcCache=Join-Path $DcRoot 'npm-cache'
$StatePath=Join-Path $DcRoot 'data-plane-guard-state.json'
$ReceiptPath=Join-Path $DcRoot 'REMOTE_DC_DATA_PLANE_GUARD_LAST.json'
$OutLog=Join-Path $DcRoot 'remote.stdout.log'
$ErrLog=Join-Path $DcRoot 'remote.stderr.log'
$AllowedPackage='@wonderwhy-er/desktop-commander@0.2.51'
New-Item -ItemType Directory -Force -Path $Root,$DcRoot,$DcCache|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function SaveReceipt($o){try{$j=$o|ConvertTo-Json -Depth 20;$j|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'REMOTE_DC_DATA_PLANE_GUARD_LAST.json') -Encoding UTF8}}catch{}}
function GetAll{try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{@()}}
function GetRemote([array]$all){$esc=[regex]::Escape($DcCache);@($all|Where-Object{$cmd=[string]$_.CommandLine;([string]$_.Name)-match'(?i)^node(?:\.exe)?$'-and$cmd-and$cmd-match'(?i)desktop-commander'-and$cmd-match'(?i)(?:^|\s)remote(?:\s|$)'-and$cmd-match$esc})}
function TcpCount([array]$p){$ids=@($p|ForEach-Object{[int]$_.ProcessId});if($ids.Count-eq0){return 0};try{[int](@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains[int]$_.OwningProcess}).Count)}catch{0}}
function StopExact([array]$p){$ids=@();foreach($x in $p){try{$id=[int]$x.ProcessId;if($id-gt0){& taskkill.exe /PID $id /T /F 2>$null|Out-Null;if($LASTEXITCODE-eq0){$ids+=$id}}}catch{}};@($ids)}
function WarmCache([string]$Package){$old=$env:npm_config_cache;try{$env:npm_config_cache=$DcCache;$out=@(& npm.cmd exec --yes --package=$Package -- node -e "console.log('DC_CACHE_READY_STABLE_HOLD')" 2>&1);$rc=$LASTEXITCODE;[pscustomobject]@{ok=($rc-eq0);exitCode=[int]$rc;output=($out-join"`n")}}catch{[pscustomobject]@{ok=$false;exitCode=1;output=$_.Exception.Message}}finally{$env:npm_config_cache=$old}}
function StartRemote([string]$Package){$old=$env:npm_config_cache;try{$env:npm_config_cache=$DcCache;$args=@('--yes',$Package,'remote','--persist-session');$p=Start-Process -FilePath 'npx.cmd' -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -PassThru;Start-Sleep -Seconds 7;[pscustomobject]@{ok=$true;launcherPid=[int]$p.Id}}catch{[pscustomobject]@{ok=$false;launcherPid=0;error=$_.Exception.Message}}finally{$env:npm_config_cache=$old}}
function FetchControl{
  try{
    $headers=@{'User-Agent'='HomeDesign-RemoteGuard-V7';'Accept'='application/vnd.github+json';'Cache-Control'='no-cache'}
    $u='https://api.github.com/repos/'+$Repo+'/contents/local-agent/control/remote-dc-recovery.json?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $x=Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 15
    if(-not$x.content){throw 'CONTROL_API_EMPTY'}
    $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$x.content-replace'\s','')))
    return ($json|ConvertFrom-Json)
  }catch{return $null}
}
function RunPythonControlWorker{
  $o=[ordered]@{ok=$false;fetched=$false;ran=$false;exitCode=$null;error=''}
  try{
    $h=@{'User-Agent'='HomeDesign-RdcGuard-V9';'Accept'='application/vnd.github+json';'Cache-Control'='no-cache'}
    $u='https://api.github.com/repos/'+$Repo+'/contents/local-agent/python/central_control_worker_v1.py?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $x=Invoke-RestMethod -Uri $u -Headers $h -Method Get -TimeoutSec 15
    if(-not$x.content){throw 'PY_WORKER_API_EMPTY'}
    $b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''))
    $p=Join-Path $Root 'central_control_worker_v1.py'
    [IO.File]::WriteAllBytes(($p+'.download'),$b);Move-Item ($p+'.download') $p -Force
    $o.fetched=$true
    $py=(Get-Command python.exe -ErrorAction SilentlyContinue);if(-not$py){$py=Get-Command python -ErrorAction SilentlyContinue}
    if(-not$py){throw 'PYTHON_NOT_FOUND'}
    & $py.Source $p | Out-Null
    $o.exitCode=$LASTEXITCODE;$o.ran=$true;$o.ok=([int]$o.exitCode-eq0)
  }catch{$o.error=$_.Exception.Message}
  return [pscustomobject]$o
}
$pyControl=RunPythonControlWorker
$control=FetchControl
$state=$null;try{if(Test-Path $StatePath){$state=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$requestId=if($control){[string]$control.requestId}else{''};$enabled=[bool]($control-and$control.enabled);$target=if($control){[string]$control.target}else{''};$localComputerName=if([string]$env:COMPUTERNAME){[string]$env:COMPUTERNAME}else{[Environment]::MachineName};$targetOk=[bool]((-not$target)-or($target.Trim()-eq([string]$localComputerName).Trim()));$Package=if($control-and[string]$control.package){[string]$control.package}else{$AllowedPackage};$packageOk=($Package-eq$AllowedPackage);$expiresAt=if($control){[string]$control.expiresAt}else{''};$expired=$false;if($expiresAt){try{$expired=([DateTimeOffset]::Parse($expiresAt).UtcDateTime-lt[DateTime]::UtcNow)}catch{$expired=$true}}
$already=([string]$state.completedRequestId-eq$requestId-and$requestId)
$attempted=([string]$state.attemptedRequestId-eq$requestId-and$requestId)
$before=GetRemote (GetAll);$tcpBefore=TcpCount $before
$o=[ordered]@{ok=$true;action='REMOTE_DC_DATA_PLANE_ONE_SHOT_RECOVERY';version=$Version;package=$Package;allowedPackage=$AllowedPackage;pythonControlOk=[bool]$pyControl.ok;pythonControlFetched=[bool]$pyControl.fetched;pythonControlRan=[bool]$pyControl.ran;pythonControlExit=$pyControl.exitCode;pythonControlError=[string]$pyControl.error;requestId=$requestId;enabled=$enabled;target=$target;targetOk=$targetOk;packageOk=$packageOk;expiresAt=$expiresAt;expired=$expired;alreadyCompleted=[bool]$already;alreadyAttempted=[bool]$attempted;prewarmOk=$false;prewarmExit=$null;remoteBefore=[int]$before.Count;tcpBefore=[int]$tcpBefore;stopped=@();started=$false;remoteAfter=0;tcpAfter=0;cloudDataPlaneVerified=$false;cloudVerificationRequired='LIST_DEVICES+PING+REAL_COMMAND+FILE_RW_X2';broadNodeKill=$false;globalNpmCacheTouched=$false;globalExecutionPolicyChanged=$false;versionMutationAllowed=$false;startedAt=(Get-Date).ToString('o');completedAt='';error=''}
if($enabled-and$requestId-and-not$already-and-not$attempted-and-not$expired){
  try{
    if(-not$targetOk){throw 'TARGET_MISMATCH'}
    if(-not$packageOk){throw 'PACKAGE_MUTATION_BLOCKED_STABLE_HOLD'}
    $warm=WarmCache $Package;$o.prewarmOk=[bool]$warm.ok;$o.prewarmExit=[int]$warm.exitCode
    if(-not$warm.ok){throw ('PREWARM_FAILED:'+([string]$warm.output))}
    $o.stopped=@(StopExact $before);Start-Sleep -Seconds 2
    $launch=StartRemote $Package;$o.started=[bool]$launch.ok
    if(-not$launch.ok){throw [string]$launch.error}
    $after=GetRemote (GetAll);$o.remoteAfter=[int]$after.Count;$o.tcpAfter=[int](TcpCount $after)
    $o.ok=($o.remoteAfter-gt0-and$o.tcpAfter-gt0)
  }catch{$o.ok=$false;$o.error=$_.Exception.Message}
  finally{
    try{
      $st=[ordered]@{
        attemptedRequestId=$requestId
        attemptedAt=(Get-Date).ToString('o')
        attemptOk=[bool]$o.ok
        completedRequestId=$(if($o.ok){$requestId}else{if($state){[string]$state.completedRequestId}else{''}})
        completedAt=$(if($o.ok){(Get-Date).ToString('o')}else{if($state){[string]$state.completedAt}else{''}})
        version=$Version
        package=$Package
      }
      $st|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $StatePath -Encoding UTF8
    }catch{}
  }
}elseif($enabled-and$attempted-and-not$already){
  $o.ok=$false;$o.error='REQUEST_ALREADY_ATTEMPTED_NEW_REQUEST_ID_REQUIRED'
}elseif($enabled-and$expired){$o.ok=$false;$o.error='CONTROL_EXPIRED_FAIL_CLOSED'}
$o.completedAt=(Get-Date).ToString('o');SaveReceipt $o;$o|ConvertTo-Json -Depth 20
if($o.ok){exit 0}else{exit 4}