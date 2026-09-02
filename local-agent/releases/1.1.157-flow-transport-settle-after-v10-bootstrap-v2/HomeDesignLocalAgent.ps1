param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.157-flow-transport-settle-after-v10-bootstrap-v2'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Watchdog=Join-Path $Root 'HomeDesignLocalWatchdog.ps1'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$Receipt='FLOW_TRANSPORT_SETTLE_V10_BOOTSTRAP_V2_1.1.157.json'
$ExpectedWatchdog='1e0ad6bc6e11d295f9f89762523fb04392dada06'
$ExpectedBootstrap='c0a009215590835abcd5b867ca1af0a85bbb2f3b'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 30;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function BootstrapProcesses{try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name-match'(?i)powershell|pwsh'-and[string]$_.CommandLine-match'(?i)AgentBootstrap\.ps1'-and[string]$_.CommandLine-match'(?i)(?:^|\s)-Loop(?:\s|$)'})}catch{return @()}}
$r=[ordered]@{ok=$false;action='FLOW_TRANSPORT_SETTLE_V10_BOOTSTRAP_V2';version=$Version;watchdogExpected=$ExpectedWatchdog;watchdogActual='';watchdogOk=$false;bootstrapExpected=$ExpectedBootstrap;bootstrapActual='';bootstrapOk=$false;bootstrapLoopPresent=$false;parentKillAttempted=$false;bootstrapRestartAttempted=$false;normalChromeTouched=$false;flowGenerateClicked=$false;hostTouched=$false;oauthChanged=$false;scopeChanged=$false;creditSpend=$false;stage='START';error='';startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $r.stage='VERIFY_ALREADY_APPLIED_V10_V2'
  if(-not(Test-Path -LiteralPath $Watchdog -PathType Leaf)){throw 'WATCHDOG_FILE_MISSING'}
  if(-not(Test-Path -LiteralPath $Bootstrap -PathType Leaf)){throw 'BOOTSTRAP_FILE_MISSING'}
  $r.watchdogActual=(GitBlobSha1 $Watchdog).ToLowerInvariant();$r.watchdogOk=($r.watchdogActual-eq$ExpectedWatchdog)
  $r.bootstrapActual=(GitBlobSha1 $Bootstrap).ToLowerInvariant();$r.bootstrapOk=($r.bootstrapActual-eq$ExpectedBootstrap)
  $r.bootstrapLoopPresent=(@(BootstrapProcesses).Count-ge1)
  if(-not$r.watchdogOk){throw ('WATCHDOG_SHA_MISMATCH:'+ $r.watchdogActual)}
  if(-not$r.bootstrapOk){throw ('BOOTSTRAP_SHA_MISMATCH:'+ $r.bootstrapActual)}
  if(-not$r.bootstrapLoopPresent){throw 'BOOTSTRAP_LOOP_NOT_PRESENT'}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 2}
