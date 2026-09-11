param([switch]$ForceRestart)
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='REMOTE_DC_KEEPALIVE_V11_PINNED_GUARD_V8_20260912'
$Package='@wonderwhy-er/desktop-commander@0.2.48'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DcRoot=Join-Path $Base 'DesktopCommander'
$DcCache=Join-Path $DcRoot 'npm-cache'
$OutLog=Join-Path $DcRoot 'remote.stdout.log'
$ErrLog=Join-Path $DcRoot 'remote.stderr.log'
$Receipt=Join-Path $Root 'REMOTE_DC_KEEPALIVE_LAST.json'
$Guard=Join-Path $Root 'RemoteVerifyPreventionGuard.ps1'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$GuardCommit='1a8365b79b6a2a3f85eec68cf88978bd1224c76b'
$GuardBlob='99147e45158e6c506a93318264a72a94db3b8dfe'
New-Item -ItemType Directory -Force -Path $Root,$DcRoot,$DcCache|Out-Null
$Mutex=New-Object Threading.Mutex($false,'HomeDesignDesktopCommanderKeepAliveV8Preflight')
$held=$false;try{$held=$Mutex.WaitOne(30000,$false)}catch [Threading.AbandonedMutexException]{$held=$true};if(-not$held){exit 6}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{(($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not$d.Root){continue};foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c -PathType Container){return $c}}};''}
function Save($o){try{$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content $Receipt -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content (Join-Path $d 'REMOTE_DC_KEEPALIVE_LAST.json') -Encoding UTF8}}catch{}}
function RefreshGuard{try{$u='https://raw.githubusercontent.com/'+$Repo+'/'+$GuardCommit+'/local-agent/bootstrap/RemoteVerifyPreventionGuard.ps1';$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Remote-Preflight-V11';$b=$wc.DownloadData($u)}finally{$wc.Dispose()};if(-not$b-or$b.Length-eq0){throw 'RAW_EMPTY'};$sha=(GitBlob $b).ToLowerInvariant();if($sha-ne$GuardBlob){throw 'GUARD_BLOB_MISMATCH'};$tmp=$Guard+'.download';[IO.File]::WriteAllBytes($tmp,$b);Move-Item $tmp $Guard -Force;return $sha}catch{return ''}}
function RunGuard{try{if(-not(Test-Path $Guard)){return $null};$raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Guard 2>&1|Out-String;try{return $raw|ConvertFrom-Json}catch{$lines=@($raw-split"`r?`n"|Where-Object{$_.Trim().StartsWith('{')});if($lines.Count){return $lines[-1]|ConvertFrom-Json}}}catch{};return $null}
function AllProc{try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)}catch{@()}}
function RemoteProc([array]$p){@($p|Where-Object{([string]$_.Name)-match'(?i)^node(?:\.exe)?$' -and ([string]$_.CommandLine)-match'(?i)desktop-commander' -and ([string]$_.CommandLine)-match'(?i)(?:^|\s)remote(?:\s|$)'})}
function StopRoots([array]$ids){$out=@();foreach($id in @($ids|Select-Object -Unique)){try{$pid=[int]$id;if($pid-gt0){& taskkill.exe /PID $pid /T /F 2>$null|Out-Null;if($LASTEXITCODE-eq0){$out+=$pid}}}catch{}};@($out)}
function WarmCache{$old=$env:npm_config_cache;try{$env:npm_config_cache=$DcCache;$o=@(& npm.cmd exec --yes --package=$Package -- node -e "console.log('DC_CACHE_READY')" 2>&1);[pscustomobject]@{ok=($LASTEXITCODE-eq0);output=$o-join"`n"}}catch{[pscustomobject]@{ok=$false;output=$_.Exception.Message}}finally{$env:npm_config_cache=$old}}
function StartRemote{$old=$env:npm_config_cache;try{$env:npm_config_cache=$DcCache;$p=Start-Process npx.cmd -ArgumentList @('--yes',$Package,'remote','--persist-session') -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -PassThru;[pscustomobject]@{ok=$true;pid=[int]$p.Id}}catch{[pscustomobject]@{ok=$false;pid=0;error=$_.Exception.Message}}finally{$env:npm_config_cache=$old}}
$started=(Get-Date).ToString('o');$guardSha=RefreshGuard;$pre=RunGuard;$actions=@();$errors=@();$restart=$false
if(-not$pre){$decision='HOLD_PREFLIGHT_UNAVAILABLE';$actions+='NO_RESTART_FAIL_CLOSED'}else{$decision=[string]$pre.decision}
if($ForceRestart-and$pre-and([string]$pre.decision-ne'HOLD_INSTALL_CHANGE_WINDOW')-and-not[bool]$pre.humanGate-and[bool]$pre.internet443-and[bool]$pre.clockOk){$decision='ALLOW_RESTART_ONCE';$actions+='FORCE_RESTART_ACCEPTED_AFTER_PREFLIGHT'}
if($decision-eq'ALLOW_RESTART_ONCE'){$restart=$true;$stopped=StopRoots @($pre.remoteChainRoots);if($stopped.Count){$actions+=('STOP_EXACT_CHAIN_ROOTS:'+($stopped-join','));Start-Sleep -Seconds 2};$warm=WarmCache;if($warm.ok){$actions+='ISOLATED_CACHE_READY';$launch=StartRemote;if($launch.ok){$actions+='REMOTE_HIDDEN_START_ONCE';Start-Sleep -Seconds 7}else{$errors+=('START='+$launch.error)}}else{$errors+=('CACHE='+$warm.output)}}else{$actions+=('PREFLIGHT_'+$decision+'_NO_RESTART')}
$post=RunGuard;if(-not$post){$post=$pre}
$ok=[bool]($post-and[string]$post.decision-eq'KEEP_SESSION'-and[int]$post.remoteChainRootCount-eq1-and[int]$post.tcpEstablished-gt0-and-not[bool]$post.humanGate)
$human=[bool]($post-and$post.humanGate);$status=$(if($ok){'LOCAL_TRANSPORT_HEALTHY_PREFLIGHT_KEEP_SESSION'}elseif($human){'WAIT_SINGLE_VERIFY_DEVICE_NO_RESTART'}elseif($post){[string]$post.decision}else{'HOLD_PREFLIGHT_UNAVAILABLE'})
$out=[ordered]@{ok=$ok;version=$Version;startedAt=$started;completedAt=(Get-Date).ToString('o');device=$env:COMPUTERNAME;preflightVersion=$(if($pre){[string]$pre.version}else{''});preflightGuardSha=$guardSha;preflightDecision=$(if($pre){[string]$pre.decision}else{'UNAVAILABLE'});postflightDecision=$(if($post){[string]$post.decision}else{'UNAVAILABLE'});triggerReason=$(if($pre){[string]$pre.reason}else{'PREFLIGHT_UNAVAILABLE'});restartNeeded=[bool]($decision-eq'ALLOW_RESTART_ONCE');restartAttempted=$restart;humanGate=$human;sessionRestored=$(if($post){[bool]$post.sessionRestored}else{$false});remoteProcessAfter=$(if($post){[int]$post.remoteProcessCount}else{0});remoteChainRootCountAfter=$(if($post){[int]$post.remoteChainRootCount}else{0});remoteChainRootsAfter=$(if($post){@($post.remoteChainRoots)}else{@()});tcpEstablishedAfter=$(if($post){[int]$post.tcpEstablished}else{0});internet443=$(if($post){[bool]$post.internet443}else{$false});clockOk=$(if($post){[bool]$post.clockOk}else{$false});clockSkewSec=$(if($post){$post.clockSkewSec}else{$null});actions=$actions;errors=$errors;status=$status;package=$Package;isolatedCache=$DcCache;humanGatePolicy='PREVENT_BEFORE_VERIFY;ONE_VERIFY_FLOW_ONLY;NEVER_AUTO_CLICK_SECURITY_APPROVAL;KEEP_EXISTING_SESSION_AND_CHAIN';duplicatePolicy='ONE_PRODUCER_CHAIN;NO_RAW_NODE_COUNT_RESTART';globalNpmCacheTouched=$false;broadNodeKill=$false;globalExecutionPolicyChanged=$false;newOAuthRequested=$false;cloudVerificationRequired='REMOTE_TOOL_PING+POWERSHELL+FILE_WRITE_READ_X2'}
Save $out;$out|ConvertTo-Json -Depth 40 -Compress
try{$Mutex.ReleaseMutex();$Mutex.Dispose()}catch{}
if($ok){exit 0}elseif($human){exit 5}else{exit 4}