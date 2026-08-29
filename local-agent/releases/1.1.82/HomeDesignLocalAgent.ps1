param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.82'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Helper=Join-Path $Root 'Test-NotebookLMFreshNotebookSourceCDPV3.ps1'
$ExpectedHelperSha='5e80c0ee3e809f573ee3f9b5af28dedbdb700b82'
$OldNotebookId='69e055e5-c8d0-4e9c-8686-58cc6da35a51'
$Marker='NLM_FRESH_ALL_20260829_1915'
$DispatchMarker=Join-Path $Root 'AGENT_1.1.82_FRESH_NOTEBOOK_V3.dispatched'
$ResultMarker=Join-Path $Root 'AGENT_1.1.82_FRESH_NOTEBOOK_V3_RESULT.json'
$Stdout=Join-Path $Root 'AGENT_1.1.82_FRESH_NOTEBOOK_V3.stdout.log'
$Stderr=Join-Path $Root 'AGENT_1.1.82_FRESH_NOTEBOOK_V3.stderr.log'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($myDriveKo+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
function SaveCentral([string]$Name,$Object){try{$central=FindCentral;if(-not $central){return ''};$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}}
function FetchHelper{
  $headers=@{'User-Agent'='HomeDesign-Local-Agent-1.1.82';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/local-agent/diagnostics/Test-NotebookLMFreshNotebookSourceCDPV3.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $r=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
  $apiSha=([string]$r.sha).ToLowerInvariant();if($apiSha -ne $ExpectedHelperSha){throw "HELPER_API_SHA_MISMATCH actual=$apiSha expected=$ExpectedHelperSha"}
  $tmp=$Helper+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')))
  $localSha=(GitBlobSha1 $tmp).ToLowerInvariant();if($localSha -ne $ExpectedHelperSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "HELPER_LOCAL_SHA_MISMATCH actual=$localSha expected=$ExpectedHelperSha"}
  Move-Item -LiteralPath $tmp -Destination $Helper -Force
}
function KillTree([int]$Pid){try{& taskkill.exe /PID $Pid /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue}catch{}}}

$mutex=New-Object Threading.Mutex($false,'HomeDesignFreshNotebook1182V3')
$locked=$false
try{$locked=$mutex.WaitOne(0,$false)}catch{$locked=$false}
if(-not $locked){$skip=[ordered]@{ok=$false;action='AGENT_1.1.82_FRESH_NOTEBOOK_V3';state='SKIP_CONCURRENT';version=$Version;at=(Get-Date).ToString('o');normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false};$skip|ConvertTo-Json -Compress;exit 0}

$prior=ReadJson $ResultMarker
if($prior){[void](SaveCentral 'AGENT_1.1.82_FRESH_NOTEBOOK_V3_RESULT.json' $prior);$prior|ConvertTo-Json -Depth 40 -Compress;if([bool]$prior.ok){exit 0}else{exit 2}}
if(Test-Path -LiteralPath $DispatchMarker){$pending=[ordered]@{ok=$false;action='AGENT_1.1.82_FRESH_NOTEBOOK_V3';state='DISPATCH_MARKER_PRESENT_NO_RESULT';version=$Version;at=(Get-Date).ToString('o');normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false};[void](SaveCentral 'AGENT_1.1.82_FRESH_NOTEBOOK_V3_PENDING.json' $pending);$pending|ConvertTo-Json -Compress;try{$mutex.ReleaseMutex()}catch{};exit 2}

$result=[ordered]@{ok=$false;action='AGENT_1.1.82_FRESH_NOTEBOOK_V3';state='STARTING';version=$Version;taskId='LOCAL_NLM_FRESH_NOTEBOOK_SOURCE_CDP_V2_20260829_2132_01';helperSha=$ExpectedHelperSha;startedAt=(Get-Date).ToString('o');freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;notebookUrl='';notebookId='';previousNotebookId=$OldNotebookId;marker=$Marker;adoptedExistingFreshTab=$false;helperExit=$null;helperTimedOut=$false;helperStage='';normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
try{
  FetchHelper
  $dispatch=[ordered]@{ok=$true;action='AGENT_1.1.82_FRESH_NOTEBOOK_V3_DISPATCH';state='DISPATCHED_ONCE';version=$Version;at=(Get-Date).ToString('o');taskId=$result.taskId;helperSha=$ExpectedHelperSha;bridgeGenerationLane='0.2.39_UNCHANGED';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $dispatch|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $DispatchMarker -Encoding UTF8
  [void](SaveCentral 'AGENT_1.1.82_FRESH_NOTEBOOK_V3_DISPATCH.json' $dispatch)
  Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
  $argLine='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Helper+'" -Title "2026-08-29 NotebookLM Fresh E2E 전체 산출물 검증" -SourceText "2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 고유 마커: NLM_FRESH_ALL_20260829_1915." -ExpectedOldNotebookId "'+$OldNotebookId+'" -RemoteDebuggingPort 9223 -TimeoutSeconds 120 -CdpCommandTimeoutSeconds 8'
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden
  $done=$p.WaitForExit(180000)
  if(-not $done){$result.helperTimedOut=$true;KillTree ([int]$p.Id);throw 'FRESH_V3_PROCESS_TIMEOUT_180S'}
  $result.helperExit=[int]$p.ExitCode
  $combined='';if(Test-Path $Stdout){$combined+=Get-Content -LiteralPath $Stdout -Raw -Encoding UTF8};if(Test-Path $Stderr){$e=Get-Content -LiteralPath $Stderr -Raw -Encoding UTF8;if($e){$combined+="`n"+$e}}
  $lines=@($combined -split "`r?`n"|Where-Object{$_ -and $_.Trim()});$payload=$null
  for($i=$lines.Count-1;$i -ge 0;$i--){try{$payload=([string]$lines[$i])|ConvertFrom-Json;if($payload){break}}catch{}}
  if(-not $payload){throw ('FRESH_V3_RESULT_JSON_NOT_FOUND: '+($combined.Trim()))}
  $result.freshNotebook=[bool]$payload.freshNotebook;$result.sourceAdded=[bool]$payload.sourceAdded;$result.sourceVerified=[bool]$payload.sourceVerified;$result.notebookUrl=[string]$payload.notebookUrl;$result.notebookId=[string]$payload.notebookId;$result.adoptedExistingFreshTab=[bool]$payload.adoptedExistingFreshTab;$result.helperStage=[string]$payload.stage
  if($payload.error){$result.error=[string]$payload.error}
  $validId=([bool][string]$result.notebookId -and [string]$result.notebookId -ne $OldNotebookId)
  $validUrl=([string]$result.notebookUrl -match '^https://notebook\.google\.com/notebook/[0-9a-fA-F-]+')
  $result.ok=([int]$result.helperExit -eq 0 -and [bool]$payload.ok -and $result.freshNotebook -and $result.sourceAdded -and $result.sourceVerified -and $validId -and $validUrl)
  $result.state=if($result.ok){'PASS'}else{'FAIL'}
  if(-not $result.ok -and -not $result.error){$result.error='FRESH_NOTEBOOK_V3_GATE_FAILED'}
}catch{$result.state='ERROR';$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $ResultMarker -Encoding UTF8;$result.centralPath=SaveCentral 'AGENT_1.1.82_FRESH_NOTEBOOK_V3_RESULT.json' $result;$result|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $ResultMarker -Encoding UTF8;if($locked){try{$mutex.ReleaseMutex()}catch{}};try{$mutex.Dispose()}catch{}}
$result|ConvertTo-Json -Depth 40 -Compress
if($result.ok){exit 0}else{exit 2}
