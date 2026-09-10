param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='NOTEBOOK_AUDIT_PACK_LOCAL_V6_RECEIPT_PATH_FIX_20260910'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$AuditRoot=Join-Path $Base 'NotebookAudit'
$DcRoot=Join-Path $Base 'DesktopCommander'
$DcCache=Join-Path $DcRoot 'npm-cache'
$DcOutLog=Join-Path $DcRoot 'remote.stdout.log'
$DcErrLog=Join-Path $DcRoot 'remote.stderr.log'
$DcMarker=Join-Path $DcRoot 'cache-ready-0.2.48.marker'
$ReceiptPath=Join-Path $AuditRoot 'NOTEBOOK_AUDIT_PACK_LAST.json'
$RemoteReceipt=Join-Path $AuditRoot 'REMOTE_DC_SELF_HEAL_LAST.json'
$Package='@wonderwhy-er/desktop-commander@0.2.48'
New-Item -ItemType Directory -Force -Path $Root,$AuditRoot,$DcRoot,$DcCache|Out-Null

function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveJson([string]$Local,[string]$Name,$Object){
  try{
    $json=$Object|ConvertTo-Json -Depth 50
    $json|Set-Content -LiteralPath $Local -Encoding UTF8
    $central=FindCentral
    if($central){
      $dir=Join-Path $central 'Runtime_Readback'
      New-Item -ItemType Directory -Force -Path $dir|Out-Null
      $json|Set-Content -LiteralPath (Join-Path $dir $Name) -Encoding UTF8
    }
  }catch{}
}
function GetCommandProcesses{
  try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{return @()}
}
function GetRemoteProcesses{
  param([array]$Processes)
  return @($Processes|Where-Object{
    $cmd=[string]$_.CommandLine
    ([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and $cmd -and $cmd -match '(?i)desktop-commander' -and $cmd -match '(?i)(?:^|\s)remote(?:\s|$)'
  })
}
function GetLegacyGlobalRemoteProcesses{
  param([array]$Processes)
  return @(GetRemoteProcesses $Processes|Where-Object{([string]$_.CommandLine) -match '(?i)AppData\\Local\\npm-cache\\_npx'})
}
function GetIsolatedRemoteProcesses{
  param([array]$Processes)
  $escaped=[regex]::Escape($DcCache)
  return @(GetRemoteProcesses $Processes|Where-Object{([string]$_.CommandLine) -match $escaped})
}
function GetRemoteTcpEstablished{
  param([array]$Processes)
  $ids=@($Processes|ForEach-Object{try{[int]$_.ProcessId}catch{0}}|Where-Object{$_ -gt 0})
  if($ids.Count-eq0){return 0}
  try{return [int](@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids -contains [int]$_.OwningProcess}).Count)}catch{return 0}
}
function StopExactProcesses{
  param([array]$Processes)
  $stopped=@()
  foreach($p in $Processes){
    try{
      $pidValue=[int]$p.ProcessId
      if($pidValue -le 0){continue}
      & taskkill.exe /PID $pidValue /T /F 2>$null|Out-Null
      if($LASTEXITCODE -eq 0){$stopped+=$pidValue}
    }catch{}
  }
  return @($stopped)
}
function WarmIsolatedCache{
  $old=$env:npm_config_cache
  try{
    $env:npm_config_cache=$DcCache
    $out=@(& npm.cmd exec --yes --package=$Package -- node -e "console.log('DC_CACHE_READY')" 2>&1)
    $rc=$LASTEXITCODE
    return [pscustomobject]@{ok=($rc-eq0);exitCode=$rc;output=($out -join "`n")}
  }catch{return [pscustomobject]@{ok=$false;exitCode=1;output=$_.Exception.Message}}
  finally{$env:npm_config_cache=$old}
}
function ResetIsolatedNpxCache{
  param([array]$Processes)
  $isolated=@(GetIsolatedRemoteProcesses $Processes)
  $stopped=StopExactProcesses $isolated
  $npx=Join-Path $DcCache '_npx'
  $removed=$false
  if(Test-Path -LiteralPath $npx){
    try{Remove-Item -LiteralPath $npx -Recurse -Force -ErrorAction Stop;$removed=$true}catch{}
  }else{$removed=$true}
  return [pscustomobject]@{stopped=$stopped;removed=$removed}
}
function StartRemoteHidden{
  $old=$env:npm_config_cache
  try{
    $env:npm_config_cache=$DcCache
    $args=@('--yes',$Package,'remote','--persist-session')
    $p=Start-Process -FilePath 'npx.cmd' -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $DcOutLog -RedirectStandardError $DcErrLog -PassThru
    Start-Sleep -Seconds 4
    $all=GetCommandProcesses
    $remote=@(GetRemoteProcesses $all)
    return [pscustomobject]@{started=$true;launcherPid=[int]$p.Id;remoteCount=[int]$remote.Count;remotePids=@($remote|ForEach-Object{[int]$_.ProcessId})}
  }catch{return [pscustomobject]@{started=$false;launcherPid=0;remoteCount=0;remotePids=@();error=$_.Exception.Message}}
  finally{$env:npm_config_cache=$old}
}
function EnsureRemoteDc{
  $startedAt=(Get-Date).ToString('o')
  $all=GetCommandProcesses
  $remote=@(GetRemoteProcesses $all)
  $legacy=@(GetLegacyGlobalRemoteProcesses $all)
  $isolated=@(GetIsolatedRemoteProcesses $all)
  $tcpBefore=GetRemoteTcpEstablished $isolated
  $actions=@();$errors=@();$warm=$null;$launch=$null
  if($legacy.Count-gt0){
    $ids=StopExactProcesses $legacy
    $actions+=('STOP_LEGACY_GLOBAL_REMOTE:'+($ids -join ','))
    Start-Sleep -Seconds 1
    $all=GetCommandProcesses;$remote=@(GetRemoteProcesses $all);$isolated=@(GetIsolatedRemoteProcesses $all);$tcpBefore=GetRemoteTcpEstablished $isolated
  }
  if($isolated.Count-eq0){
    $warm=WarmIsolatedCache
    if(-not$warm.ok){
      $actions+='WARM_FAIL_RESET_ISOLATED_NPX_ONCE'
      $reset=ResetIsolatedNpxCache (GetCommandProcesses)
      if(-not$reset.removed){$errors+='ISOLATED_NPX_REMOVE_FAILED'}
      $warm=WarmIsolatedCache
    }
    if($warm.ok){
      try{[ordered]@{version='0.2.48';readyAt=(Get-Date).ToString('o');cache=$DcCache}|ConvertTo-Json|Set-Content -LiteralPath $DcMarker -Encoding UTF8}catch{}
      $actions+='ISOLATED_CACHE_READY'
      $launch=StartRemoteHidden
      if($launch.started){$actions+='REMOTE_HIDDEN_START'}else{$errors+=('REMOTE_START:'+[string]$launch.error)}
    }else{$errors+=('CACHE_WARM:'+[string]$warm.output)}
  }elseif($tcpBefore-gt0){
    $actions+='ISOLATED_REMOTE_ALREADY_PRESENT_HEALTHY'
  }else{
    $ids=StopExactProcesses $isolated
    if($ids.Count-eq0){
      $errors+='STALE_REMOTE_EXACT_STOP_FAILED'
    }else{
      $actions+=('RESTART_STALE_ISOLATED_REMOTE_NO_TCP:'+($ids -join ','))
      Start-Sleep -Seconds 2
      $launch=StartRemoteHidden
      if($launch.started){$actions+='REMOTE_HIDDEN_RESTART'}else{$errors+=('REMOTE_RESTART:'+[string]$launch.error)}
    }
  }
  Start-Sleep -Milliseconds 500
  $finalAll=GetCommandProcesses
  $finalRemote=@(GetRemoteProcesses $finalAll)
  $finalIsolated=@(GetIsolatedRemoteProcesses $finalAll)
  $tcpAfter=GetRemoteTcpEstablished $finalIsolated
  if($finalIsolated.Count-eq0 -or $tcpAfter-eq0){
    Start-Sleep -Seconds 2
    $confirmAll=GetCommandProcesses
    $confirmRemote=@(GetRemoteProcesses $confirmAll)
    $confirmIsolated=@(GetIsolatedRemoteProcesses $confirmAll)
    $confirmTcp=GetRemoteTcpEstablished $confirmIsolated
    if($confirmIsolated.Count-eq0 -or $confirmTcp-eq0){
      if($confirmIsolated.Count-gt0){
        $ids=StopExactProcesses $confirmIsolated
        if($ids.Count-gt0){$actions+=('POSTCHECK_COMMAND_PLANE_DROP_STOP:'+($ids -join ','))}else{$errors+='POSTCHECK_EXACT_STOP_FAILED'}
        Start-Sleep -Seconds 2
      }else{$actions+='POSTCHECK_REMOTE_PROCESS_DROPPED'}
      $launch=StartRemoteHidden
      if($launch.started){$actions+='POSTCHECK_REMOTE_HIDDEN_RESTART'}else{$errors+=('POSTCHECK_REMOTE_RESTART:'+[string]$launch.error)}
      Start-Sleep -Milliseconds 500
      $finalAll=GetCommandProcesses
      $finalRemote=@(GetRemoteProcesses $finalAll)
      $finalIsolated=@(GetIsolatedRemoteProcesses $finalAll)
      $tcpAfter=GetRemoteTcpEstablished $finalIsolated
    }else{
      $actions+='POSTCHECK_COMMAND_PLANE_RECOVERED_WITHOUT_RESTART'
      $finalAll=$confirmAll;$finalRemote=$confirmRemote;$finalIsolated=$confirmIsolated;$tcpAfter=$confirmTcp
    }
  }
  $result=[ordered]@{
    ok=([int]$finalIsolated.Count-gt0 -and [int]$tcpAfter-gt0)
    action='REMOTE_DC_LOCK_AWARE_ISOLATED_SELF_HEAL'
    version=$Version
    startedAt=$startedAt
    completedAt=(Get-Date).ToString('o')
    package=$Package
    isolatedCache=$DcCache
    remoteBefore=[int]$remote.Count
    legacyGlobalBefore=[int]$legacy.Count
    isolatedBefore=[int]$isolated.Count
    tcpEstablishedBefore=[int]$tcpBefore
    isolatedAfter=[int]$finalIsolated.Count
    remoteAfter=[int]$finalRemote.Count
    tcpEstablishedAfter=[int]$tcpAfter
    remotePids=@($finalRemote|ForEach-Object{[int]$_.ProcessId})
    actions=$actions
    errors=$errors
    warmExit=$(if($warm){[int]$warm.exitCode}else{$null})
    launch=$launch
    globalNpmCacheTouched=$false
    globalExecutionPolicyChanged=$false
    broadNodeKill=$false
    cloudDataPlaneVerified=$false
    cloudVerificationRequired='DIRECTORY_READ+TEST_WRITE+READBACK_X2_FROM_CHATGPT_REMOTE_TOOL'
  }
  SaveJson $RemoteReceipt 'REMOTE_DC_SELF_HEAL_LAST.json' $result
  return [pscustomobject]$result
}
function PowerReadback{
  $o=[ordered]@{}
  foreach($item in @(@('VIDEOIDLE','SUB_VIDEO'),@('STANDBYIDLE','SUB_SLEEP'),@('HIBERNATEIDLE','SUB_SLEEP'))){
    $name=$item[0];$sub=$item[1]
    try{$o[$name]=((& powercfg.exe /query SCHEME_CURRENT $sub $name 2>&1) -join "`n")}catch{$o[$name]='ERROR:'+ $_.Exception.Message}
  }
  return [pscustomobject]$o
}
function NicReadback{
  try{return @(Get-NetAdapterPowerManagement -ErrorAction Stop|Select-Object Name,InterfaceDescription,AllowComputerToTurnOffDevice,SelectiveSuspend,DeviceSleepOnDisconnect,WakeOnMagicPacket,WakeOnPattern)}catch{return @([pscustomobject]@{error=$_.Exception.Message})}
}
function WindowInventory{
  $rows=@()
  $cim=GetCommandProcesses
  $byPid=@{};foreach($p in $cim){$byPid[[int]$p.ProcessId]=$p}
  foreach($p in @(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.MainWindowHandle -ne 0})){
    $cmd='';if($byPid.ContainsKey([int]$p.Id)){$cmd=[string]$byPid[[int]$p.Id].CommandLine}
    $rows+=[pscustomobject]@{pid=[int]$p.Id;process=[string]$p.ProcessName;title=[string]$p.MainWindowTitle;hwnd=[int64]$p.MainWindowHandle;automationHint=[bool]($cmd-match'(?i)desktop-commander|Chrome for Testing|HomeDesignAutomationV7|--remote-debugging-port');commandLine=$cmd}
  }
  return @($rows)
}
function RuntimeReadbackSummary{
  $central=FindCentral
  if(-not$central){return [pscustomobject]@{centralFound=$false;runtimeDir='';recentFiles=0;openLikeFiles=@()}}
  $dir=Join-Path $central 'Runtime_Readback'
  if(-not(Test-Path -LiteralPath $dir)){return [pscustomobject]@{centralFound=$true;runtimeDir=$dir;recentFiles=0;openLikeFiles=@()}}
  $since=(Get-Date).AddDays(-1);$files=@(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTime-ge$since})
  $open=@()
  foreach($f in $files){
    try{$t=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop;if($t-match'(?i)OPEN_RETRYABLE|DEGRADED|HOLD|PENDING|BLOCKED'){$open+=$f.Name}}catch{}
  }
  return [pscustomobject]@{centralFound=$true;runtimeDir=$dir;recentFiles=[int]$files.Count;openLikeFiles=@($open|Select-Object -First 100)}
}

$runStart=(Get-Date).ToString('o')
$remote=EnsureRemoteDc
$windows=WindowInventory
$power=PowerReadback
$nic=NicReadback
$runtime=RuntimeReadbackSummary
$driveFs=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName-match'(?i)GoogleDriveFS'}).Count
$bootstrap=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine-and([string]$_.CommandLine-match'(?i)AgentBootstrap\.ps1')}).Count
$receipt=[ordered]@{
  ok=[bool]$remote.ok
  action='NOTEBOOK_AUDIT_PACK_LOCAL_V6'
  version=$Version
  startedAt=$runStart
  completedAt=(Get-Date).ToString('o')
  device=$env:COMPUTERNAME
  remoteDc=$remote
  power=$power
  nic=$nic
  windowCount=[int]$windows.Count
  automationHintWindowCount=[int](@($windows|Where-Object{$_.automationHint}).Count)
  windows=@($windows|Select-Object -First 200)
  driveFsProcessCount=[int]$driveFs
  bootstrapProcessCount=[int]$bootstrap
  phoneRemote='SEPARATE_CLOUD_CHANNEL_NOT_LOCALLY_OBSERVABLE_DO_NOT_INFER_FROM_REMOTE_DC'
  runtimeReadback=$runtime
  completedBrowserGraceSeconds=300
  remoteDcVisibleShellHardCapSeconds=300
  powerPolicyExpected='DISPLAY_OFF=1800;SLEEP=0;HIBERNATE=0'
  manualPowerShellTarget='ZERO'
  localAuditOnly=$true
  remoteCloudX2Pending=$true
}
SaveJson $ReceiptPath 'NOTEBOOK_AUDIT_PACK_LAST.json' $receipt
$receiptPersisted=$false
try{
  $saved=Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
  $receiptPersisted=([string]$saved.version -eq $Version -and [string]$saved.completedAt -eq [string]$receipt.completedAt)
}catch{}
if(-not $receiptPersisted){exit 5}
if($remote.ok){exit 0}else{exit 4}
