param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='REMOTE_VERIFY_PREVENTION_GUARD_V2_FAILOVER_20260910'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DcRoot=Join-Path $Base 'DesktopCommander'
$Receipt=Join-Path $Root 'REMOTE_VERIFY_PREVENTION_LAST.json'
$KeepReceipt=Join-Path $Root 'REMOTE_DC_KEEPALIVE_LAST.json'
$OutLog=Join-Path $DcRoot 'remote.stdout.log'
$ErrLog=Join-Path $DcRoot 'remote.stderr.log'
$FallbackScript=Join-Path $Root 'RemoteFallbackOrchestrator.ps1'
$FallbackBlob='1b953465c0092b6de42c1d1e51a8b042ac24cb19'
$RestartBackoffSec=1800
$ChannelGraceSec=180
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Save($o){try{$o|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $Receipt -Encoding UTF8}catch{}}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{(($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function RefreshFallback{try{$u='https://api.github.com/repos/8friend8ship-cloud/notebooklm-webapp-bridge/contents/local-agent/bootstrap/RemoteFallbackOrchestrator.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod $u -Headers @{'User-Agent'='HomeDesign-Remote-Failover-V2';'Accept'='application/vnd.github+json'} -TimeoutSec 10;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$sha=(GitBlob $b).ToLowerInvariant();if($sha-ne$FallbackBlob){throw'FALLBACK_SHA_MISMATCH'};$tmp=$FallbackScript+'.download';[IO.File]::WriteAllBytes($tmp,$b);Move-Item $tmp $FallbackScript -Force;return $true}catch{return $false}}
function RunFallback{try{if(-not(RefreshFallback)){return $null};$raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FallbackScript 2>&1|Out-String;try{return $raw|ConvertFrom-Json}catch{$lines=@($raw-split"`r?`n"|Where-Object{$_.Trim().StartsWith('{')});if($lines.Count){return $lines[-1]|ConvertFrom-Json}}}catch{};return $null}
function AllProc{try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{@()}}
function RemoteProc([array]$p){@($p|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and ([string]$_.CommandLine)-match'(?i)desktop-commander' -and ([string]$_.CommandLine)-match'(?i)(?:^|\s)remote(?:\s|$)'})}
function ChainRoots([array]$all,[array]$remote){$map=@{};foreach($x in $all){$map[[int]$x.ProcessId]=$x};$roots=@();foreach($r in $remote){$cur=$r;$rid=[int]$r.ProcessId;for($i=0;$i-lt12;$i++){$pp=[int]$cur.ParentProcessId;if($pp-le0-or-not$map.ContainsKey($pp)){break};$par=$map[$pp];$cmd=[string]$par.CommandLine;$name=[string]$par.Name;if(-not($cmd-match'(?i)(desktop-commander|@wonderwhy-er/desktop-commander|npx(?:-cli\.js|\.cmd).*remote)' -or ($name-match'(?i)^cmd(?:\.exe)?$' -and $cmd-match'(?i)(desktop-commander|npx\.cmd)'))){break};$rid=$pp;$cur=$par};$roots+=$rid};return @($roots|Select-Object -Unique)}
function TcpCount([array]$p){try{$ids=@($p|ForEach-Object{[int]$_.ProcessId});if(-not$ids){return 0};[int](@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids-contains$_.OwningProcess}).Count)}catch{0}}
function Tail([string]$p){try{if(Test-Path $p){(Get-Content $p -Tail 220 -ErrorAction Stop)-join"`n"}else{''}}catch{''}}
function LastIdx([string]$t,[string[]]$marks){$x=-1;foreach($m in $marks){$x=[Math]::Max($x,$t.LastIndexOf($m,[StringComparison]::OrdinalIgnoreCase))};$x}
function NetTime{
 $o=[ordered]@{reachable=$false;serverDate='';skewSec=$null;timeOk=$true;error=''}
 try{$r=Invoke-WebRequest -UseBasicParsing -Uri 'https://mcp.desktopcommander.app' -Method Head -TimeoutSec 8;$o.reachable=$true;$d=[string]$r.Headers['Date'];if($d){$sd=[DateTimeOffset]::Parse($d);$o.serverDate=$sd.ToString('o');$o.skewSec=[math]::Round([math]::Abs(([DateTimeOffset]::UtcNow-$sd).TotalSeconds),1);$o.timeOk=([double]$o.skewSec-lt300)}}catch{$o.error=$_.Exception.Message;try{$c=New-Object Net.Sockets.TcpClient;$a=$c.BeginConnect('mcp.desktopcommander.app',443,$null,$null);if($a.AsyncWaitHandle.WaitOne(3500)){$c.EndConnect($a);$o.reachable=$true};$c.Close()}catch{}}
 [pscustomobject]$o
}
function LastRestartAge{try{if(Test-Path $KeepReceipt){$j=Get-Content $KeepReceipt -Raw -Encoding UTF8|ConvertFrom-Json;if([bool]$j.restartAttempted){return [int]((Get-Date)-([datetime]$j.completedAt)).TotalSeconds}}}catch{};return 999999}
$now=Get-Date;$all=AllProc;$rp=@(RemoteProc $all);$roots=@(ChainRoots $all $rp);$tcp=TcpCount $rp;$tail=(Tail $OutLog)+"`n"+(Tail $ErrLog)
$ready=LastIdx $tail @('Device ready','Channel subscribed');$restore=LastIdx $tail @('Session restored');$gate=LastIdx $tail @('Starting device authorization flow','Requesting device code','Verify Device','Please complete authentication');$revoked=LastIdx $tail @('Device not found','No valid session','SIGNED_OUT','revoked persisted device');$failure=LastIdx $tail @('Channel closed','socket 1006','Channel subscription timed out','Remote session expired','Cannot recreate channel','Failed to update transport capability')
$humanGate=($gate-gt$ready);$revokedAfterReady=($revoked-gt$ready);$failureAfterReady=($failure-gt$ready);$net=NetTime;$restartAge=LastRestartAge
$decision='KEEP_SESSION';$reason='HEALTHY_SINGLE_CHAIN';$allowRestart=$false
if($humanGate-or$revokedAfterReady){$decision='REQUIRE_HUMAN_VERIFY_ONCE';$reason='AUTH_GATE_OR_REVOKED_SESSION'}
elseif($roots.Count-gt1){$decision='HOLD_MULTIPLE_CHAINS';$reason='MULTIPLE_PRODUCER_CHAINS'}
elseif(-not$net.reachable){$decision='HOLD_NETWORK';$reason='REMOTE_ENDPOINT_443_UNREACHABLE'}
elseif(-not$net.timeOk){$decision='HOLD_CLOCK_SKEW';$reason='LOCAL_SERVER_TIME_SKEW_GE_300S'}
elseif($rp.Count-gt0-and$roots.Count-eq1-and$tcp-gt0-and-not$failureAfterReady){$decision='KEEP_SESSION';$reason='HEALTHY_SINGLE_CHAIN'}
elseif($rp.Count-gt0-and$roots.Count-eq1-and($tcp-eq0-or$failureAfterReady)){$decision='WAIT_CHANNEL_SELF_RECOVERY';$reason='PROCESS_PRESENT_CHANNEL_UNHEALTHY';if($restartAge-ge$RestartBackoffSec){$decision='ALLOW_RESTART_ONCE';$allowRestart=$true;$reason='CHANNEL_UNHEALTHY_BACKOFF_EXPIRED'}}
elseif($rp.Count-eq0){if($restartAge-lt$RestartBackoffSec){$decision='HOLD_RESTART_BACKOFF';$reason='PROCESS_ABSENT_RECENT_RESTART'}else{$decision='ALLOW_RESTART_ONCE';$allowRestart=$true;$reason='PROCESS_ABSENT_PREFLIGHT_CLEAN'}}
$fallback=RunFallback
$out=[ordered]@{ok=$true;version=$Version;time=$now.ToString('o');decision=$decision;reason=$reason;allowRestartOnce=$allowRestart;remoteProcessCount=$rp.Count;remoteChainRootCount=$roots.Count;remoteChainRoots=$roots;tcpEstablished=$tcp;sessionRestored=[bool]($restore-ge0-and$ready-gt$restore);humanGate=$humanGate;revokedMarkerAfterReady=$revokedAfterReady;failureAfterReady=$failureAfterReady;internet443=[bool]$net.reachable;serverDate=[string]$net.serverDate;clockSkewSec=$net.skewSec;clockOk=[bool]$net.timeOk;secondsSinceLastRestartAttempt=$restartAge;restartBackoffSec=$RestartBackoffSec;channelGraceSec=$ChannelGraceSec;fallbackOrchestratorLoaded=[bool]$fallback;fallbackActiveStage=$(if($fallback){[string]$fallback.activeStage}else{'UNAVAILABLE'});fallbackDecision=$(if($fallback){[string]$fallback.decision}else{'UNAVAILABLE'});fallbackNextAction=$(if($fallback){[string]$fallback.nextAction}else{'NONE'});tailscaleReady=$(if($fallback){[bool]$fallback.tailscale.ready}else{$false});rustdeskReady=$(if($fallback){[bool]$fallback.rustdesk.ready}else{$false});policy='PRECHECK_FIRST;KEEP_HEALTHY_SESSION;NO_BROWSER_START;NO_AUTO_APPROVAL;NO_NEW_AUTH_FLOW_WHILE_GATE_PENDING;ONE_RESTART_ONLY_AFTER_BACKOFF;FAILOVER_ORDER_REMOTE_DC_THEN_TAILSCALE_THEN_RUSTDESK'}
Save $out;$out|ConvertTo-Json -Depth 40 -Compress;exit 0