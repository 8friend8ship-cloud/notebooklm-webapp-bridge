param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$AgentVersion='1.1.79'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$FreshScript=Join-Path $Root 'NotebookLM-Fresh-Notebook-Source-CDP-V3.ps1'
$DispatchMarker=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3.dispatched'
$ResultMarker=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3_RESULT.json'
$ExpectedFreshSha='5e80c0ee3e809f573ee3f9b5af28dedbdb700b82'
$OldNotebookId='69e055e5-c8d0-4e9c-8686-58cc6da35a51'
$ProcessTimeoutSeconds=180
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function SetProp($Obj,[string]$Name,$Value){if($Obj.PSObject.Properties[$Name]){$Obj.$Name=$Value}else{$Obj|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}}
function FindCentralRoot{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $rr=[string]$drv.Root;if(-not $rr){continue}
    foreach($cand in @((Join-Path $rr $centralName),(Join-Path $rr ($myDriveKo+'\'+$centralName)),(Join-Path $rr ('My Drive\'+$centralName)),(Join-Path $rr ('Google Drive\'+$centralName)))){
      if(Test-Path -LiteralPath $cand -PathType Container){return $cand}
    }
  }
  return ''
}
function SaveCentral([string]$Name,$Object){
  try{
    $central=FindCentralRoot;if(-not $central){return ''}
    $dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null
    $p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $p -Encoding UTF8;return $p
  }catch{return ''}
}
function WriteAgentState([string]$Mode){
  $s=ReadJson $StateFile
  if(-not $s){$s=[pscustomobject]@{ok=$true;status='AGENT_APPLIED';agentVersion=$AgentVersion;agentMode=$Mode;updatedAt=(Get-Date).ToString('o')}}
  else{SetProp $s 'agentVersion' $AgentVersion;SetProp $s 'agentMode' $Mode;SetProp $s 'updatedAt' (Get-Date).ToString('o')}
  $tmp=$StateFile+'.1179.tmp';$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}
function FetchFreshScript{
  $headers=@{'User-Agent'='HomeDesign-Local-Agent-1.1.79';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/local-agent/diagnostics/Test-NotebookLMFreshNotebookSourceCDPV3.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $r=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
  $apiSha=([string]$r.sha).ToLowerInvariant();if($apiSha -ne $ExpectedFreshSha){throw "FRESH_V3_API_SHA_MISMATCH actual=$apiSha expected=$ExpectedFreshSha"}
  $tmp=$FreshScript+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')))
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $ExpectedFreshSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "FRESH_V3_LOCAL_SHA_MISMATCH actual=$actual expected=$ExpectedFreshSha"}
  Move-Item -LiteralPath $tmp -Destination $FreshScript -Force
}
function StopOnlyStaleFreshHelpers{
  $needles=@('Test-NotebookLMClaimStartBridge.ps1','NotebookLM-Fresh-Notebook-Source-CDP-V2.ps1','Test-NotebookLMFreshNotebookSourceCDPV2.ps1')
  try{
    foreach($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine})){
      $hit=$false;foreach($n in $needles){if([string]$p.CommandLine -like ('*'+$n+'*')){$hit=$true;break}}
      if($hit){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}}
    }
  }catch{}
}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function ReleaseLock($Mutex,[bool]$Locked){if($Locked){try{$Mutex.ReleaseMutex()}catch{}};try{$Mutex.Dispose()}catch{}}

$mutex=New-Object System.Threading.Mutex($false,'HomeDesignFreshNotebook1179V3')
$locked=$false
try{$locked=$mutex.WaitOne(0,$false)}catch{$locked=$false}
if(-not $locked){
  $skip=[ordered]@{ok=$false;action='AGENT_1.1.79_FRESH_NOTEBOOK_V3';state='SKIP_CONCURRENT';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $skip|ConvertTo-Json -Depth 20 -Compress;ReleaseLock $mutex $locked;exit 0
}

if(Test-Path -LiteralPath $ResultMarker){
  $prior=ReadJson $ResultMarker
  if($prior){[void](SaveCentral 'AGENT_1.1.79_FRESH_NOTEBOOK_V3_RESULT.json' $prior);$prior|ConvertTo-Json -Depth 40 -Compress;$priorOk=[bool]$prior.ok;ReleaseLock $mutex $locked;if($priorOk){exit 0}else{exit 2}}
}
if(Test-Path -LiteralPath $DispatchMarker){
  $pending=[ordered]@{ok=$false;action='AGENT_1.1.79_FRESH_NOTEBOOK_V3';state='DISPATCH_MARKER_PRESENT_NO_RESULT';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  [void](SaveCentral 'AGENT_1.1.79_FRESH_NOTEBOOK_V3_PENDING.json' $pending);$pending|ConvertTo-Json -Depth 20 -Compress;ReleaseLock $mutex $locked;exit 2
}

$result=[ordered]@{ok=$false;action='AGENT_1.1.79_FRESH_NOTEBOOK_V3';state='STARTING';agentVersion=$AgentVersion;startedAt=(Get-Date).ToString('o');helperSha=$ExpectedFreshSha;freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;notebookUrl='';notebookId='';previousNotebookId=$OldNotebookId;marker='NLM_FRESH_ALL_20260829_1915';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;helperExit=$null;helperTimedOut=$false;helperStage='';adoptedExistingFreshTab=$false;error='';centralPath=''}
try{
  WriteAgentState 'FRESH_NOTEBOOK_V3_ONE_SHOT'
  StopOnlyStaleFreshHelpers
  FetchFreshScript
  $dispatch=[ordered]@{ok=$true;action='AGENT_1.1.79_FRESH_NOTEBOOK_V3_DISPATCH';state='DISPATCHED_ONCE';agentVersion=$AgentVersion;helperSha=$ExpectedFreshSha;at=(Get-Date).ToString('o');oldNotebookId=$OldNotebookId;marker='NLM_FRESH_ALL_20260829_1915';processTimeoutSeconds=$ProcessTimeoutSeconds;bridgeGenerationLane='0.2.39_UNCHANGED';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $dispatch|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $DispatchMarker -Encoding UTF8
  [void](SaveCentral 'AGENT_1.1.79_FRESH_NOTEBOOK_V3_DISPATCH.json' $dispatch)

  $stdout=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3.stdout.log';$stderr=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3.stderr.log'
  Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
  $quotedFresh='"'+$FreshScript+'"'
  $proc=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$quotedFresh) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  $finished=$proc.WaitForExit($ProcessTimeoutSeconds*1000)
  if(-not $finished){$result.helperTimedOut=$true;KillTree ([int]$proc.Id);try{[void]$proc.WaitForExit(5000)}catch{};throw ('FRESH_V3_PROCESS_TIMEOUT seconds='+$ProcessTimeoutSeconds)}
  $result.helperExit=[int]$proc.ExitCode
  $combined='';if(Test-Path $stdout){$combined+=(Get-Content -LiteralPath $stdout -Raw -Encoding UTF8)};if(Test-Path $stderr){$e=Get-Content -LiteralPath $stderr -Raw -Encoding UTF8;if($e){$combined+="`n"+$e}}
  $lines=@($combined -split "`r?`n"|Where-Object{$_ -and $_.Trim()});$payload=$null
  for($i=$lines.Count-1;$i -ge 0;$i--){try{$payload=([string]$lines[$i])|ConvertFrom-Json;if($payload){break}}catch{}}
  if(-not $payload){throw ('FRESH_V3_RESULT_JSON_NOT_FOUND: '+($combined.Trim()))}
  $result.freshNotebook=[bool]$payload.freshNotebook;$result.sourceAdded=[bool]$payload.sourceAdded;$result.sourceVerified=[bool]$payload.sourceVerified;$result.notebookUrl=[string]$payload.notebookUrl;$result.notebookId=[string]$payload.notebookId;$result.helperStage=[string]$payload.stage;$result.adoptedExistingFreshTab=[bool]$payload.adoptedExistingFreshTab
  if($payload.error){$result.error=[string]$payload.error}
  $validId=([bool][string]$result.notebookId -and [string]$result.notebookId -ne $OldNotebookId)
  $validUrl=([string]$result.notebookUrl -match '^https://notebook\.google\.com/notebook/[0-9a-fA-F-]+')
  $result.ok=([int]$result.helperExit -eq 0 -and [bool]$payload.ok -and $result.freshNotebook -and $result.sourceAdded -and $result.sourceVerified -and $validId -and $validUrl)
  $result.state=if($result.ok){'PASS'}else{'FAIL'}
  if(-not $result.ok -and -not $result.error){$result.error='FRESH_NOTEBOOK_V3_GATE_FAILED'}
}catch{$result.state='ERROR';$result.error=$_.Exception.Message}
finally{
  try{WriteAgentState 'FRESH_NOTEBOOK_V3_TERMINAL'}catch{}
  $result.completedAt=(Get-Date).ToString('o')
  $result|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $ResultMarker -Encoding UTF8
  $result.centralPath=SaveCentral 'AGENT_1.1.79_FRESH_NOTEBOOK_V3_RESULT.json' $result
  $result|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $ResultMarker -Encoding UTF8
  ReleaseLock $mutex $locked
}
$result|ConvertTo-Json -Depth 40 -Compress
if($result.ok){exit 0}else{exit 2}
