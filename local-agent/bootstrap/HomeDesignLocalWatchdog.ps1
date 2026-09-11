param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WATCHDOG_V16_RAW_FIRST_20260911'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$LegacyBlob='ecd3a75d2ad8314a44772d91df1905632eeec94d'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$Receipt=Join-Path $Root 'WATCHDOG_LAST.json'
$Entry=Join-Path $Root 'WATCHDOG_ENTRY_LATEST.json'
$BootstrapLocal=Join-Path $Root 'AgentBootstrap.ps1'
$FlowGuardLocal=Join-Path $Root 'FlowDemandGuard.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function GitBlobSha1([string]$Path){return GitBlobSha1Bytes ([IO.File]::ReadAllBytes($Path))}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save([string]$Local,[string]$Name,$o){try{$j=$o|ConvertTo-Json -Depth 50;$j|Set-Content -LiteralPath $Local -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Name) -Encoding UTF8}}catch{}}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 3;[bool]$h.ok}catch{$false}}
function EnsureHost129{$o=[ordered]@{before=(HostHealthy);restarted=$false;ok=$false;error=''};if($o.before){$o.ok=$true;return [pscustomobject]$o};try{$apply=Join-Path $Root 'Apply-EmbeddedHost129.ps1';$host129=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.9.ps1';$rec=Join-Path $Root 'EMBEDDED_HOST129_WATCHDOG_AUTORESTORE.json';if(-not(Test-Path $apply)){throw 'APPLY_HOST129_MISSING'};if(-not(Test-Path $host129)){throw 'HOST129_MISSING'};& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $apply -HostPath $host129 -ReceiptPath $rec|Out-Null;$o.restarted=$true;$o.ok=(HostHealthy)}catch{$o.error=$_.Exception.Message};[pscustomobject]$o}
function FlowCdpHealthy{try{$v=Invoke-RestMethod -Uri 'http://127.0.0.1:9224/json/version' -TimeoutSec 3;[bool]$v.Browser}catch{$false}}
function EnsureFlowCdp{
  $before=FlowCdpHealthy
  $guard=$null
  try{
    $gf=FetchRepoBytes 'local-agent/bootstrap/FlowDemandGuard.ps1' 12
    if($gf.ok){$need=(-not(Test-Path $FlowGuardLocal));if(-not$need){$need=((GitBlobSha1 $FlowGuardLocal).ToLowerInvariant()-ne([string]$gf.sha).ToLowerInvariant())};if($need){[IO.File]::WriteAllBytes(($FlowGuardLocal+'.download'),[byte[]]$gf.bytes);Move-Item ($FlowGuardLocal+'.download') $FlowGuardLocal -Force}}
    if(Test-Path $FlowGuardLocal){$raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FlowGuardLocal -Apply 2>&1|Out-String;try{$guard=$raw|ConvertFrom-Json}catch{}}
  }catch{}
  if($guard-and-not[bool]$guard.allowOpen){return [pscustomobject]@{before=$before;started=$false;ok=$true;error='';demandGuard=[string]$guard.decision;allowOpen=$false}}
  $o=[ordered]@{before=$before;started=$false;ok=$false;error='';demandGuard=$(if($guard){[string]$guard.decision}else{'GUARD_UNAVAILABLE_FAIL_CLOSED'});allowOpen=[bool]($guard-and$guard.allowOpen)}
  if(-not$guard){$o.ok=$true;return [pscustomobject]$o}
  if($before){$o.ok=$true;return [pscustomobject]$o}
  try{$chrome=Get-ChildItem -LiteralPath (Join-Path $Base 'ChromeForTesting') -Recurse -Filter chrome.exe -File -ErrorAction Stop|Sort-Object FullName -Descending|Select-Object -First 1;if(-not$chrome){throw 'FLOW_CFT_CHROME_MISSING'};$ext=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge';if(-not(Test-Path $ext)){throw 'FLOW_EXTENSION_MISSING'};$args=@("--user-data-dir=$DedicatedUserData",'--profile-directory=Default',"--load-extension=$ext",'--remote-debugging-port=9224','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble','https://labs.google/fx/tools/flow');Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.DirectoryName|Out-Null;$o.started=$true;$deadline=(Get-Date).AddSeconds(20);while((Get-Date)-lt$deadline){Start-Sleep -Milliseconds 500;if(FlowCdpHealthy){$o.ok=$true;break}};if(-not$o.ok){throw 'FLOW_CDP_9224_START_TIMEOUT'}}catch{$o.error=$_.Exception.Message};[pscustomobject]$o
}
function BootstrapProcesses{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name-match'(?i)powershell|pwsh'-and[string]$_.CommandLine-match'(?i)AgentBootstrap\.ps1'-and[string]$_.CommandLine-match'(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
function BootstrapPresent{return (@(BootstrapProcesses).Count-gt0)}
function CurrentVersion{try{if(Test-Path (Join-Path $Root 'state.json')){[string]((Get-Content (Join-Path $Root 'state.json') -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}else{''}}catch{''}}
function DedicatedNotebookProcesses{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine-and([string]$_.CommandLine-like('*'+$DedicatedUserData+'*'))-and(([string]$_.CommandLine-match'(?i)notebooklm\.google\.com')-or([string]$_.CommandLine-match'(?i)--remote-debugging-port=9223'))})}catch{return @()}}
function StopDedicatedNotebookLM{$before=@(DedicatedNotebookProcesses);foreach($p in $before){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}};if($before.Count-gt0){Start-Sleep -Seconds 2};$after=@(DedicatedNotebookProcesses);[pscustomobject]@{before=[int]$before.Count;after=[int]$after.Count;stopped=[int]([Math]::Max(0,$before.Count-$after.Count));ok=([int]$after.Count-eq0)}}
function FetchRepoBytes([string]$Path,[int]$TimeoutSec=20){
  $o=[ordered]@{ok=$false;mode='';bytes=$null;sha='';error=''}
  try{$raw='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Watchdog-V16';$b=$wc.DownloadData($raw)}finally{$wc.Dispose()};if(-not$b-or$b.Length-eq0){throw 'RAW_EMPTY'};$o.ok=$true;$o.mode='RAW';$o.bytes=$b;$o.sha=(GitBlobSha1Bytes $b).ToLowerInvariant();return [pscustomobject]$o}catch{$o.error='RAW='+$_.Exception.Message}
  try{$headers=@{'User-Agent'='HomeDesign-Watchdog-V16';'Accept'='application/vnd.github+json'};$url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main';$x=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec $TimeoutSec;$b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$actual=(GitBlobSha1Bytes $b).ToLowerInvariant();$expected=([string]$x.sha).ToLowerInvariant();if(-not$expected-or$actual-ne$expected){throw 'API_GIT_BLOB_SHA_MISMATCH'};$o.ok=$true;$o.mode='API_FALLBACK';$o.bytes=$b;$o.sha=$actual;$o.error='';return [pscustomobject]$o}catch{$o.error+=';API='+$_.Exception.Message}
  return [pscustomobject]$o
}
function StableMeta{
  $o=[ordered]@{ok=$false;enabled=$true;version='';notes='';sha='';transport='';error=''}
  $f=FetchRepoBytes 'local-agent/stable/agent.json' 12
  if(-not$f.ok){$o.error=$f.error;return [pscustomobject]$o}
  try{$j=[Text.Encoding]::UTF8.GetString([byte[]]$f.bytes)|ConvertFrom-Json;$o.enabled=[bool]$j.enabled;$o.version=[string]$j.version;$o.notes=[string]$j.notes;$o.sha=[string]$f.sha;$o.transport=[string]$f.mode;$o.ok=$true}catch{$o.error='META_PARSE='+$_.Exception.Message}
  [pscustomobject]$o
}
function EnsureBootstrapLatest{
  $o=[ordered]@{ok=$false;beforePresent=(BootstrapPresent);refreshed=$false;restarted=$false;sha='';transport='';error=''}
  try{
    $f=FetchRepoBytes 'local-agent/bootstrap/AgentBootstrap.ps1' 20;if(-not$f.ok){throw $f.error}
    $o.sha=[string]$f.sha;$o.transport=[string]$f.mode
    $needs= -not(Test-Path -LiteralPath $BootstrapLocal -PathType Leaf)
    if(-not$needs){$needs=((GitBlobSha1 $BootstrapLocal).ToLowerInvariant()-ne([string]$f.sha).ToLowerInvariant())}
    if($needs){
      $tmp=$BootstrapLocal+'.watchdog-v15';[IO.File]::WriteAllBytes($tmp,[byte[]]$f.bytes);if((GitBlobSha1 $tmp).ToLowerInvariant()-ne([string]$f.sha).ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw 'BOOTSTRAP_SHA_MISMATCH'}
      Move-Item $tmp $BootstrapLocal -Force;$o.refreshed=$true
      foreach($p in @(BootstrapProcesses)){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}
      Start-Sleep -Milliseconds 500
    }
    if(-not(BootstrapPresent)){Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapLocal`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 2;$o.restarted=$true}
    $o.ok=(BootstrapPresent)
  }catch{$o.error=$_.Exception.Message}
  [pscustomobject]$o
}

$start=(Get-Date).ToString('o');Save $Entry 'WATCHDOG_ENTRY_LATEST.json' ([ordered]@{ok=$true;action='WATCHDOG_ENTRY_V15_FLOW_DEMAND_GATED';version=$Version;pid=$PID;startedAt=$start;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false})
Save (Join-Path $Root 'CENTRAL_INTERNAL_HEARTBEAT.json') 'CENTRAL_INTERNAL_HEARTBEAT.json' ([ordered]@{ok=$true;status='ACTIVE_INTERNAL_ALIVE';timestamp=(Get-Date).ToString('o');displayOffSeconds=1800;sleepTimeoutAc=0;sleepTimeoutDc=0;hibernateTimeoutAc=0;hibernateTimeoutDc=0;source='HomeDesignAutomation-AutoResume';normalChromeTouched=$false})
try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'HeavyAppRunOwnedWatchdog.ps1')|Out-Null}catch{}
try{
$cleanupLocal=Join-Path $Root 'RunOwnedUiCleanup.ps1'
$cf=FetchRepoBytes 'local-agent/bootstrap/RunOwnedUiCleanup.ps1' 15
if($cf.ok){$needs=(-not(Test-Path $cleanupLocal));$fetchedText=[Text.Encoding]::UTF8.GetString([byte[]]$cf.bytes);$localArrayFix=$false;if(Test-Path $cleanupLocal){try{$localArrayFix=[bool](Select-String -LiteralPath $cleanupLocal -Pattern '\$parsed=Get-Content' -Quiet)}catch{}};if($localArrayFix-and$fetchedText-notmatch '\$parsed=Get-Content'){$needs=$false}elseif(-not$needs){$needs=((GitBlobSha1 $cleanupLocal).ToLowerInvariant()-ne([string]$cf.sha).ToLowerInvariant())};if($needs){[IO.File]::WriteAllBytes(($cleanupLocal+'.download'),[byte[]]$cf.bytes);Move-Item ($cleanupLocal+'.download') $cleanupLocal -Force}}
$supervisorLocal=Join-Path $Root 'CentralAgentTabSupervisor.ps1'
$recoveryLocal=Join-Path $Root 'CentralTabAutoRecovery.ps1'
foreach($spec in @(@('local-agent/bootstrap/CentralAgentTabSupervisor.ps1',$supervisorLocal),@('local-agent/bootstrap/CentralTabAutoRecovery.ps1',$recoveryLocal))){try{$f=FetchRepoBytes $spec[0] 12;if($f.ok){$need=(-not(Test-Path $spec[1]));if(-not$need){$need=((GitBlobSha1 $spec[1]).ToLowerInvariant()-ne([string]$f.sha).ToLowerInvariant())};if($need){[IO.File]::WriteAllBytes(($spec[1]+'.download'),[byte[]]$f.bytes);Move-Item ($spec[1]+'.download') $spec[1] -Force}}}catch{}}
if(Test-Path $supervisorLocal){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $supervisorLocal|Out-Null}elseif(Test-Path $cleanupLocal){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cleanupLocal|Out-Null}
}catch{}
try{
  $auditLocal=Join-Path $Root 'NotebookAuditPack.ps1'
  if(Test-Path -LiteralPath $auditLocal -PathType Leaf){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $auditLocal | Out-Null}
}catch{}
$chatgptAutoOpenDisabled=$true
$s=StableMeta
$hold=[bool]($s.ok-and-not$s.enabled-and([string]$s.notes-match'TABLET_PRIMARY_HOLD|TABLET_OWNER_LOCK_ACTIVE'))
if($hold){
  $shutdown=StopDedicatedNotebookLM;$hostRestore=EnsureHost129;$flowRestore=EnsureFlowCdp;$bootstrap=EnsureBootstrapLatest;$ok=[bool]($shutdown.ok-and$hostRestore.ok-and$flowRestore.ok-and$bootstrap.ok)
  Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$ok;action='WATCHDOG_TABLET_PRIMARY_HOLD_V15_FLOW_DEMAND_GATED';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');hostHealthy=(HostHealthy);hostRestoreBefore=[bool]$hostRestore.before;hostRestoreRestarted=[bool]$hostRestore.restarted;hostRestoreOk=[bool]$hostRestore.ok;hostRestoreError=[string]$hostRestore.error;flowCdp9224Before=[bool]$flowRestore.before;flowCdp9224Started=[bool]$flowRestore.started;flowCdp9224Ok=[bool]$flowRestore.ok;flowCdp9224Error=[string]$flowRestore.error;flowDemandGuard=[string]$flowRestore.demandGuard;flowAutoOpenAllowed=[bool]$flowRestore.allowOpen;tabletPrimaryOwner=$true;notebookLaptopHeld=$true;flowLaptopFallbackEnabled=[bool]$flowRestore.allowOpen;stableMetaReachable=$true;stableMetaTransport=[string]$s.transport;stableEnabled=$false;stableNotes=[string]$s.notes;bootstrapBefore=[bool]$bootstrap.beforePresent;bootstrapRefreshed=[bool]$bootstrap.refreshed;bootstrapRestarted=[bool]$bootstrap.restarted;bootstrapOk=[bool]$bootstrap.ok;bootstrapSha=[string]$bootstrap.sha;bootstrapTransport=[string]$bootstrap.transport;bootstrapError=[string]$bootstrap.error;currentVersion=(CurrentVersion);notebooklmRuntimeChecked=$true;dedicatedNotebookChromeBefore=[int]$shutdown.before;dedicatedNotebookChromeStopped=[int]$shutdown.stopped;dedicatedNotebookChromeAfter=[int]$shutdown.after;autoResumeInvoked=$false;independentLanesExpected='FLOW,IMAGE,APPSCRIPT';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;exitCode=($(if($ok){0}else{4}))})
  if($ok){exit 0}else{exit 4}
}
if(-not$s.ok){Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$true;action='WATCHDOG_STABLE_API_AND_RAW_UNREACHABLE_FAIL_CLOSED_V15';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');hostHealthy=(HostHealthy);bootstrapLoopPresent=(BootstrapPresent);currentVersion=(CurrentVersion);stableMetaReachable=$false;autoResumeInvoked=$false;normalChromeTouched=$false;error=[string]$s.error;exitCode=0});exit 0}
try{
  $raw='https://raw.githubusercontent.com/'+$Repo+'/'+$LegacyBlob+'/local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'
  $wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Watchdog-V15';$legacy=$wc.DownloadData($raw)}finally{$wc.Dispose()}
  if(-not$legacy-or$legacy.Length-eq0){throw 'LEGACY_WATCHDOG_RAW_EMPTY'}
  $p=Join-Path $Root 'HomeDesignLocalWatchdog-V6-delegate.ps1';[IO.File]::WriteAllBytes($p,$legacy);& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $p;exit $LASTEXITCODE
}catch{Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$false;action='WATCHDOG_V15_DELEGATE_ERROR';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');autoResumeInvoked=$false;error=$_.Exception.Message;exitCode=3});exit 3}