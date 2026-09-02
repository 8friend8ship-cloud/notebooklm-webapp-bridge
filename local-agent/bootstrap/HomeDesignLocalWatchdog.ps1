param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WATCHDOG_V10_TABLET_HOLD_RAW_FALLBACK_BOOTSTRAP_REFRESH_20260902'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$LegacyBlob='ecd3a75d2ad8314a44772d91df1905632eeec94d'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$Receipt=Join-Path $Root 'WATCHDOG_LAST.json'
$Entry=Join-Path $Root 'WATCHDOG_ENTRY_LATEST.json'
$BootstrapLocal=Join-Path $Root 'AgentBootstrap.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function GitBlobSha1([string]$Path){return GitBlobSha1Bytes ([IO.File]::ReadAllBytes($Path))}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save([string]$Local,[string]$Name,$o){try{$j=$o|ConvertTo-Json -Depth 50;$j|Set-Content -LiteralPath $Local -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Name) -Encoding UTF8}}catch{}}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 3;[bool]$h.ok}catch{$false}}
function BootstrapProcesses{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name-match'(?i)powershell|pwsh'-and[string]$_.CommandLine-match'(?i)AgentBootstrap\.ps1'-and[string]$_.CommandLine-match'(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
function BootstrapPresent{return (@(BootstrapProcesses).Count-gt0)}
function CurrentVersion{try{if(Test-Path (Join-Path $Root 'state.json')){[string]((Get-Content (Join-Path $Root 'state.json') -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}else{''}}catch{''}}
function DedicatedNotebookProcesses{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine-and([string]$_.CommandLine-like('*'+$DedicatedUserData+'*'))})}catch{return @()}}
function StopDedicatedNotebookLM{$before=@(DedicatedNotebookProcesses);foreach($p in $before){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}};if($before.Count-gt0){Start-Sleep -Seconds 2};$after=@(DedicatedNotebookProcesses);[pscustomobject]@{before=[int]$before.Count;after=[int]$after.Count;stopped=[int]([Math]::Max(0,$before.Count-$after.Count));ok=([int]$after.Count-eq0)}}
function FetchRepoBytes([string]$Path,[int]$TimeoutSec=20){
  $o=[ordered]@{ok=$false;mode='';bytes=$null;sha='';error=''}
  try{
    $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Watchdog-V10';'Accept'='application/vnd.github+json'} -TimeoutSec $TimeoutSec
    $b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''));$actual=(GitBlobSha1Bytes $b).ToLowerInvariant();$expected=([string]$x.sha).ToLowerInvariant();if(-not$expected-or$actual-ne$expected){throw 'API_GIT_BLOB_SHA_MISMATCH'}
    $o.ok=$true;$o.mode='API';$o.bytes=$b;$o.sha=$actual;return [pscustomobject]$o
  }catch{$o.error='API='+$_.Exception.Message}
  try{
    $raw='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Watchdog-V10';$b=$wc.DownloadData($raw)}finally{$wc.Dispose()}
    if(-not$b-or$b.Length-eq0){throw 'RAW_EMPTY'}
    $o.ok=$true;$o.mode='RAW';$o.bytes=$b;$o.sha=(GitBlobSha1Bytes $b).ToLowerInvariant();$o.error='';return [pscustomobject]$o
  }catch{$o.error+=';RAW='+$_.Exception.Message}
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
      $tmp=$BootstrapLocal+'.watchdog-v10';[IO.File]::WriteAllBytes($tmp,[byte[]]$f.bytes);if((GitBlobSha1 $tmp).ToLowerInvariant()-ne([string]$f.sha).ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw 'BOOTSTRAP_SHA_MISMATCH'}
      Move-Item $tmp $BootstrapLocal -Force;$o.refreshed=$true
      foreach($p in @(BootstrapProcesses)){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}
      Start-Sleep -Milliseconds 500
    }
    if(-not(BootstrapPresent)){Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$BootstrapLocal`"",'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 2;$o.restarted=$true}
    $o.ok=(BootstrapPresent)
  }catch{$o.error=$_.Exception.Message}
  [pscustomobject]$o
}

$start=(Get-Date).ToString('o');Save $Entry 'WATCHDOG_ENTRY_LATEST.json' ([ordered]@{ok=$true;action='WATCHDOG_ENTRY_V10_RAW_FALLBACK';version=$Version;pid=$PID;startedAt=$start;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false})
$s=StableMeta
$hold=[bool]($s.ok-and-not$s.enabled-and([string]$s.notes-match'TABLET_PRIMARY_HOLD|TABLET_OWNER_LOCK_ACTIVE'))
if($hold){
  $shutdown=StopDedicatedNotebookLM;$bootstrap=EnsureBootstrapLatest;$ok=[bool]($shutdown.ok-and$bootstrap.ok)
  Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$ok;action='WATCHDOG_TABLET_PRIMARY_HOLD_V10_RAW_FALLBACK_BOOTSTRAP_REFRESH';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');hostHealthy=(HostHealthy);stableMetaReachable=$true;stableMetaTransport=[string]$s.transport;stableEnabled=$false;stableNotes=[string]$s.notes;bootstrapBefore=[bool]$bootstrap.beforePresent;bootstrapRefreshed=[bool]$bootstrap.refreshed;bootstrapRestarted=[bool]$bootstrap.restarted;bootstrapOk=[bool]$bootstrap.ok;bootstrapSha=[string]$bootstrap.sha;bootstrapTransport=[string]$bootstrap.transport;bootstrapError=[string]$bootstrap.error;currentVersion=(CurrentVersion);notebooklmRuntimeChecked=$true;dedicatedNotebookChromeBefore=[int]$shutdown.before;dedicatedNotebookChromeStopped=[int]$shutdown.stopped;dedicatedNotebookChromeAfter=[int]$shutdown.after;autoResumeInvoked=$false;independentLanesExpected='FLOW,IMAGE,APPSCRIPT';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;exitCode=($(if($ok){0}else{4}))})
  if($ok){exit 0}else{exit 4}
}
if(-not$s.ok){Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$true;action='WATCHDOG_STABLE_API_AND_RAW_UNREACHABLE_FAIL_CLOSED_V10';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');hostHealthy=(HostHealthy);bootstrapLoopPresent=(BootstrapPresent);currentVersion=(CurrentVersion);stableMetaReachable=$false;autoResumeInvoked=$false;normalChromeTouched=$false;error=[string]$s.error;exitCode=0});exit 0}
try{
  $raw='https://raw.githubusercontent.com/'+$Repo+'/'+$LegacyBlob+'/local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'
  $wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Watchdog-V10';$legacy=$wc.DownloadData($raw)}finally{$wc.Dispose()}
  if(-not$legacy-or$legacy.Length-eq0){throw 'LEGACY_WATCHDOG_RAW_EMPTY'}
  $p=Join-Path $Root 'HomeDesignLocalWatchdog-V6-delegate.ps1';[IO.File]::WriteAllBytes($p,$legacy);& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $p;exit $LASTEXITCODE
}catch{Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$false;action='WATCHDOG_V10_DELEGATE_ERROR';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');autoResumeInvoked=$false;error=$_.Exception.Message;exitCode=3});exit 3}
