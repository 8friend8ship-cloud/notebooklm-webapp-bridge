param([switch]$ForceRestart)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='REMOTE_DC_KEEPALIVE_V2_TRANSPORT_AWARE_20260909'
$Package='@wonderwhy-er/desktop-commander@0.2.48'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DcRoot=Join-Path $Base 'DesktopCommander'
$DcCache=Join-Path $DcRoot 'npm-cache'
$OutLog=Join-Path $DcRoot 'remote.stdout.log'
$ErrLog=Join-Path $DcRoot 'remote.stderr.log'
$Receipt=Join-Path $Root 'REMOTE_DC_KEEPALIVE_LAST.json'
$CooldownSeconds=120
New-Item -ItemType Directory -Force -Path $Root,$DcRoot,$DcCache|Out-Null

function Find-Central{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function Save-Receipt($o){
  try{
    $j=$o|ConvertTo-Json -Depth 40
    $j|Set-Content -LiteralPath $Receipt -Encoding UTF8
    $c=Find-Central
    if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'REMOTE_DC_KEEPALIVE_LAST.json') -Encoding UTF8}
  }catch{}
}
function Get-AllProc{try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{@()}}
function Get-RemoteProc([array]$p){@($p|Where-Object{([string]$_.CommandLine)-match'(?i)desktop-commander' -and ([string]$_.CommandLine)-match'(?i)(?:^|\s)remote(?:\s|$)'})}
function Get-IsolatedRemote([array]$p){$e=[regex]::Escape($DcCache);@(Get-RemoteProc $p|Where-Object{([string]$_.CommandLine)-match$e})}
function Get-LegacyRemote([array]$p){@(Get-RemoteProc $p|Where-Object{([string]$_.CommandLine)-match'(?i)AppData\\Local\\npm-cache\\_npx'})}
function Get-TcpCount([array]$p){
  try{$ids=@($p|ForEach-Object{[int]$_.ProcessId});if($ids.Count-eq0){return 0};return [int](@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count)}catch{return 0}
}
function Read-Tail([string]$Path,[int]$Lines=120){try{if(Test-Path $Path){return ((Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction Stop)-join"`n")}}catch{};return ''}
function Has-NewerFailure([string]$Text){
  if(-not$Text){return $false}
  $ready=[Math]::Max($Text.LastIndexOf('Device ready',[StringComparison]::OrdinalIgnoreCase),$Text.LastIndexOf('Channel subscribed',[StringComparison]::OrdinalIgnoreCase))
  $err=-1
  foreach($s in @('Channel closed','socket 1006','IncreaseConnectionPool','Channel subscription timed out','Device startup failed','Failed to set session','terminated','No valid session','Tool call channel subscription timed out')){$err=[Math]::Max($err,$Text.LastIndexOf($s,[StringComparison]::OrdinalIgnoreCase))}
  return ($err-gt$ready)
}
function Test-Internet443{
  $c=New-Object Net.Sockets.TcpClient
  try{$a=$c.BeginConnect('mcp.desktopcommander.app',443,$null,$null);if(-not$a.AsyncWaitHandle.WaitOne(3500)){return $false};$c.EndConnect($a);return $true}catch{return $false}finally{try{$c.Close()}catch{}}
}
function Stop-Exact([array]$p){$ids=@();foreach($x in $p){try{$id=[int]$x.ProcessId;if($id-gt0){& taskkill.exe /PID $id /T /F 2>$null|Out-Null;if($LASTEXITCODE-eq0){$ids+=$id}}}catch{}};return @($ids)}
function Warm-Cache{
  $old=$env:npm_config_cache
  try{$env:npm_config_cache=$DcCache;$o=@(& npm.cmd exec --yes --package=$Package -- node -e "console.log('DC_CACHE_READY')" 2>&1);$rc=$LASTEXITCODE;[pscustomobject]@{ok=($rc-eq0);exitCode=$rc;output=($o-join"`n")}}
  catch{[pscustomobject]@{ok=$false;exitCode=1;output=$_.Exception.Message}}
  finally{$env:npm_config_cache=$old}
}
function Reset-IsolatedNpx([array]$all){
  $stopped=Stop-Exact (Get-IsolatedRemote $all)
  $npx=Join-Path $DcCache '_npx';$removed=$true
  if(Test-Path $npx){try{Remove-Item -LiteralPath $npx -Recurse -Force -ErrorAction Stop}catch{$removed=$false}}
  [pscustomobject]@{stopped=$stopped;removed=$removed}
}
function Start-Remote{
  $old=$env:npm_config_cache
  try{
    $env:npm_config_cache=$DcCache
    $p=Start-Process -FilePath 'npx.cmd' -ArgumentList @('--yes',$Package,'remote','--persist-session') -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -PassThru
    Start-Sleep -Seconds 5
    [pscustomobject]@{ok=$true;launcherPid=[int]$p.Id}
  }catch{[pscustomobject]@{ok=$false;launcherPid=0;error=$_.Exception.Message}}
  finally{$env:npm_config_cache=$old}
}
function Cooldown-Active{
  try{if(-not(Test-Path $Receipt)){return $false};$j=Get-Content $Receipt -Raw -Encoding UTF8|ConvertFrom-Json;if(-not$j.restartAttempted){return $false};$t=[datetime]$j.completedAt;return (((Get-Date)-$t).TotalSeconds-lt$CooldownSeconds)}catch{return $false}
}

$started=(Get-Date).ToString('o')
$all=Get-AllProc;$remote=Get-RemoteProc $all;$isolated=Get-IsolatedRemote $all;$legacy=Get-LegacyRemote $all
$tcpBefore=Get-TcpCount $remote
$tail=((Read-Tail $OutLog)+"`n"+(Read-Tail $ErrLog))
$logFailure=Has-NewerFailure $tail
$internet=Test-Internet443
$reason='HEALTHY_LOCAL_TRANSPORT'
if($remote.Count-eq0){$reason='REMOTE_PROCESS_ABSENT'}elseif($tcpBefore-eq0){$reason='REMOTE_PROCESS_NO_ESTABLISHED_TCP'}elseif($logFailure){$reason='REMOTE_CHANNEL_ERROR_AFTER_LAST_READY'}
$restartNeeded=[bool]($ForceRestart-or$reason-ne'HEALTHY_LOCAL_TRANSPORT')
$cooldown=Cooldown-Active
$actions=@();$errors=@();$restartAttempted=$false;$humanGate=$false

if($legacy.Count-gt0){$ids=Stop-Exact $legacy;$actions+=('STOP_LEGACY_GLOBAL_REMOTE:'+($ids-join','));Start-Sleep -Seconds 1}
if($restartNeeded){
  if(-not$internet){$actions+='HOLD_NO_INTERNET_443';$errors+='REMOTE_ENDPOINT_443_UNREACHABLE'}
  elseif($cooldown-and-not$ForceRestart){$actions+='HOLD_RESTART_COOLDOWN'}
  else{
    $restartAttempted=$true
    $all=Get-AllProc;$exact=Get-RemoteProc $all
    if($exact.Count-gt0){$ids=Stop-Exact $exact;$actions+=('STOP_EXACT_REMOTE:'+($ids-join','));Start-Sleep -Seconds 2}
    $warm=Warm-Cache
    if(-not$warm.ok){
      $actions+='WARM_FAIL_RESET_ISOLATED_NPX_ONCE'
      $reset=Reset-IsolatedNpx (Get-AllProc)
      if(-not$reset.removed){$errors+='ISOLATED_NPX_REMOVE_FAILED'}
      $warm=Warm-Cache
    }
    if($warm.ok){$actions+='ISOLATED_CACHE_READY';$launch=Start-Remote;if($launch.ok){$actions+='REMOTE_HIDDEN_START'}else{$errors+=('REMOTE_START:'+([string]$launch.error))}}
    else{$errors+=('CACHE_WARM:'+([string]$warm.output))}
  }
}
Start-Sleep -Seconds 2
$finalAll=Get-AllProc;$finalRemote=Get-RemoteProc $finalAll;$tcpAfter=Get-TcpCount $finalRemote
$finalTail=((Read-Tail $OutLog)+"`n"+(Read-Tail $ErrLog))
if($finalTail-match'(?i)Starting device authorization flow|Please complete authentication|Requesting device code'){$humanGate=$true}
$ok=[bool]($finalRemote.Count-gt0-and$tcpAfter-gt0-and-not$humanGate)
$status=if($humanGate){'HUMAN_GATE_REMOTE_DEVICE_AUTH'}elseif($ok){'LOCAL_TRANSPORT_RECOVERED_OR_HEALTHY'}elseif(-not$internet){'WAIT_NETWORK'}else{'RETRYABLE_TRANSPORT_FAILURE'}
$out=[ordered]@{
  ok=$ok;version=$Version;startedAt=$started;completedAt=(Get-Date).ToString('o');device=$env:COMPUTERNAME
  triggerReason=$Reason;diagnosticReason=$reason;forceRestart=[bool]$ForceRestart;restartNeeded=$restartNeeded;restartAttempted=$restartAttempted;restartCooldown=$cooldown
  internet443=$internet;remoteProcessBefore=[int]$remote.Count;isolatedBefore=[int]$isolated.Count;legacyBefore=[int]$legacy.Count;tcpEstablishedBefore=$tcpBefore
  remoteProcessAfter=[int]$finalRemote.Count;tcpEstablishedAfter=$tcpAfter;remotePids=@($finalRemote|ForEach-Object{[int]$_.ProcessId})
  logFailureAfterLastReady=$logFailure;actions=$actions;errors=$errors;status=$status;humanGate=$humanGate
  package=$Package;isolatedCache=$DcCache;globalNpmCacheTouched=$false;broadNodeKill=$false;globalExecutionPolicyChanged=$false;newOAuthRequested=$false
  cloudDataPlaneVerified=$false;cloudVerificationRequired='REMOTE_TOOL_PING+POWERSHELL+FILE_WRITE_READ_X2'
}
Save-Receipt $out
$out|ConvertTo-Json -Depth 40 -Compress
if($ok){exit 0}elseif($humanGate){exit 5}else{exit 4}
