param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.84'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Helper=Join-Path $Root 'BindSourceToExistingFreshNotebookLMCDPV4.ps1'
$ExpectedHelperSha='6b28ae232bfd306db501166a134d78befd5bccba'
$HelperRaw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/diagnostics/BindSourceToExistingFreshNotebookLMCDPV4.ps1'
$HelperContents='https://api.github.com/repos/8friend8ship-cloud/notebooklm-webapp-bridge/contents/local-agent/diagnostics/BindSourceToExistingFreshNotebookLMCDPV4.ps1?ref=main'
$ResultMarker=Join-Path $Root 'AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4_RESULT.json'
$Stdout=Join-Path $Root 'AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4.stdout.log'
$Stderr=Join-Path $Root 'AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4.stderr.log'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($myDriveKo+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveCentral([string]$Name,$Object){try{$central=FindCentral;if(-not $central){return ''};$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}}
function EnsureHelper{
  if(Test-Path -LiteralPath $Helper){try{if((GitBlobSha1 $Helper).ToLowerInvariant() -eq $ExpectedHelperSha){return 'LOCAL_VERIFIED'}}catch{}}
  $tmp=$Helper+'.download';Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  $rawOk=$false
  try{Invoke-WebRequest -UseBasicParsing -Uri ($HelperRaw+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30;$rawOk=$true}catch{}
  if(-not $rawOk){
    $r=Invoke-RestMethod -UseBasicParsing -Uri ($HelperContents+'&hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -TimeoutSec 30
    if(-not $r.content){throw 'HELPER_CONTENTS_API_NO_CONTENT'}
    [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')))
  }
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $ExpectedHelperSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "HELPER_SHA_MISMATCH actual=$actual expected=$ExpectedHelperSha"}
  Move-Item -LiteralPath $tmp -Destination $Helper -Force
  return $(if($rawOk){'RAW_VERIFIED'}else{'CONTENTS_API_VERIFIED'})
}
function KillTree([int]$Pid){try{& taskkill.exe /PID $Pid /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue}catch{}}}

$mutex=New-Object Threading.Mutex($false,'HomeDesignExistingFreshSourceBind1184V4');$locked=$false;try{$locked=$mutex.WaitOne(0,$false)}catch{$locked=$false}
if(-not $locked){$skip=[ordered]@{ok=$false;action='AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4';state='SKIP_CONCURRENT';version=$Version;at=(Get-Date).ToString('o')};$skip|ConvertTo-Json -Compress;exit 0}
$prior=ReadJson $ResultMarker
if($prior){[void](SaveCentral 'AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4_RESULT.json' $prior);$prior|ConvertTo-Json -Depth 50 -Compress;if([bool]$prior.ok){exit 0}else{exit 2}}

$result=[ordered]@{ok=$false;action='AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4';state='STARTING';version=$Version;helperSha=$ExpectedHelperSha;helperFetch='';startedAt=(Get-Date).ToString('o');notebookUrl='';notebookId='';sourceAdded=$false;sourceVerified=$false;promptFilled=$false;promptSubmitted=$false;studioSelected=$false;createdNotebook=$false;helperExit=$null;helperTimedOut=$false;helperStage='';normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
try{
  $result.helperFetch=EnsureHelper
  Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
  $argLine='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Helper+'" -RemoteDebuggingPort 9223 -TimeoutSeconds 120 -CdpCommandTimeoutSeconds 8'
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden
  $done=$p.WaitForExit(180000);if(-not $done){$result.helperTimedOut=$true;KillTree ([int]$p.Id);throw 'SOURCE_BIND_V4_PROCESS_TIMEOUT_180S'}
  $result.helperExit=[int]$p.ExitCode
  $combined='';if(Test-Path $Stdout){$combined+=Get-Content -LiteralPath $Stdout -Raw -Encoding UTF8};if(Test-Path $Stderr){$e=Get-Content -LiteralPath $Stderr -Raw -Encoding UTF8;if($e){$combined+="`n"+$e}}
  $lines=@($combined -split "`r?`n"|Where-Object{$_ -and $_.Trim()});$payload=$null;for($i=$lines.Count-1;$i -ge 0;$i--){try{$payload=([string]$lines[$i])|ConvertFrom-Json;if($payload){break}}catch{}}
  if(-not $payload){throw ('SOURCE_BIND_V4_RESULT_JSON_NOT_FOUND: '+($combined.Trim()))}
  $result.notebookUrl=[string]$payload.notebookUrl;$result.notebookId=[string]$payload.notebookId;$result.sourceAdded=[bool]$payload.sourceAdded;$result.sourceVerified=[bool]$payload.sourceVerified;$result.promptFilled=[bool]$payload.promptFilled;$result.promptSubmitted=[bool]$payload.promptSubmitted;$result.studioSelected=[bool]$payload.studioSelected;$result.createdNotebook=[bool]$payload.createdNotebook;$result.helperStage=[string]$payload.stage;if($payload.error){$result.error=[string]$payload.error}
  $validUrl=([string]$result.notebookUrl -match '^https://notebook\.google\.com/notebook/[0-9a-fA-F-]+')
  $result.ok=([int]$result.helperExit -eq 0 -and [bool]$payload.ok -and $result.sourceVerified -and $validUrl -and -not $result.createdNotebook)
  $result.state=if($result.ok){'PASS'}else{'FAIL'};if(-not $result.ok -and -not $result.error){$result.error='EXISTING_FRESH_SOURCE_BIND_V4_GATE_FAILED'}
}catch{$result.state='ERROR';$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.84_EXISTING_FRESH_SOURCE_BIND_V4_RESULT.json' $result;$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $ResultMarker -Encoding UTF8;if($locked){try{$mutex.ReleaseMutex()}catch{}};try{$mutex.Dispose()}catch{}}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}else{exit 2}
