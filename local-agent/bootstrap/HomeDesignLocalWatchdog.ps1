param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WATCHDOG_V7_CONTENTS_API_TABLET_HOLD_GUARD_20260901'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$LegacyBlob='ecd3a75d2ad8314a44772d91df1905632eeec94d'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Receipt=Join-Path $Root 'WATCHDOG_LAST.json'
$Entry=Join-Path $Root 'WATCHDOG_ENTRY_LATEST.json'
$State=Join-Path $Root 'state.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save([string]$Local,[string]$Name,$o){try{$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content -LiteralPath $Local -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Name) -Encoding UTF8}}catch{}}
function HostHealthy{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 3;[bool]$h.ok}catch{$false}}
function BootstrapPresent{try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name-match'(?i)powershell|pwsh'-and[string]$_.CommandLine-match'(?i)AgentBootstrap\.ps1'-and[string]$_.CommandLine-match'(?i)(?:^|\s)-Loop(?:\s|$)'}).Count-gt0}catch{$false}}
function CurrentVersion{try{if(Test-Path $State){[string]((Get-Content $State -Raw -Encoding UTF8|ConvertFrom-Json).agentVersion)}else{''}}catch{''}}
function StableViaApi{
  $o=[ordered]@{ok=$false;enabled=$true;version='';notes='';sha='';error=''}
  try{$u='https://api.github.com/repos/'+$Repo+'/contents/local-agent/stable/agent.json?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$x=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Watchdog-V7';'Accept'='application/vnd.github+json'} -TimeoutSec 10;$o.sha=[string]$x.sha;$j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$x.content-replace'\s','')))|ConvertFrom-Json;$o.enabled=[bool]$j.enabled;$o.version=[string]$j.version;$o.notes=[string]$j.notes;$o.ok=$true}catch{$o.error=$_.Exception.Message};[pscustomobject]$o
}
$start=(Get-Date).ToString('o');Save $Entry 'WATCHDOG_ENTRY_LATEST.json' ([ordered]@{ok=$true;action='WATCHDOG_ENTRY_V7_API_GUARD';version=$Version;pid=$PID;startedAt=$start;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false})
$s=StableViaApi
$hold=[bool]($s.ok-and-not$s.enabled-and([string]$s.notes-match'TABLET_PRIMARY_HOLD'))
if($hold){Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$true;action='WATCHDOG_TABLET_PRIMARY_HOLD_V7_API_GUARD';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');hostHealthy=(HostHealthy);bootstrapLoopPresent=(BootstrapPresent);currentVersion=(CurrentVersion);targetVersion=[string]$s.version;stableMetaReachable=$true;stableMetaTransport='GITHUB_CONTENTS_API';stableContentSha=[string]$s.sha;stableEnabled=$false;stableNotes=[string]$s.notes;notebooklmRuntimeChecked=$false;autoResumeInvoked=$false;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;exitCode=0});exit 0}
# If API is unreachable, fail closed instead of recovering NotebookLM while tablet ownership may exist.
if(-not$s.ok){Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$true;action='WATCHDOG_STABLE_API_UNREACHABLE_FAIL_CLOSED_V7';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');hostHealthy=(HostHealthy);bootstrapLoopPresent=(BootstrapPresent);currentVersion=(CurrentVersion);stableMetaReachable=$false;stableMetaTransport='GITHUB_CONTENTS_API';autoResumeInvoked=$false;normalChromeTouched=$false;error=[string]$s.error;exitCode=0});exit 0}
# Non-hold mode delegates byte-for-byte to the previously verified V6 watchdog.
try{$u='https://api.github.com/repos/'+$Repo+'/git/blobs/'+$LegacyBlob;$b=Invoke-RestMethod -Uri $u -Headers @{'User-Agent'='HomeDesign-Watchdog-V7';'Accept'='application/vnd.github+json'} -TimeoutSec 20;$p=Join-Path $Root 'HomeDesignLocalWatchdog-V6-delegate.ps1';[IO.File]::WriteAllBytes($p,[Convert]::FromBase64String(([string]$b.content-replace'\s','')));if((GitBlobSha1 $p).ToLowerInvariant()-ne$LegacyBlob){throw 'WATCHDOG_V6_BLOB_MISMATCH'};& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $p;exit $LASTEXITCODE}catch{Save $Receipt 'WATCHDOG_LAST.json' ([ordered]@{ok=$false;action='WATCHDOG_V7_DELEGATE_ERROR';version=$Version;startedAt=$start;completedAt=(Get-Date).ToString('o');autoResumeInvoked=$false;error=$_.Exception.Message;exitCode=3});exit 3}
