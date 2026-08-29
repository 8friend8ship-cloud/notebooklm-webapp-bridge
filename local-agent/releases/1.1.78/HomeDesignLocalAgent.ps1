param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$AgentVersion='1.1.78'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$FreshScript=Join-Path $Root 'NotebookLM-Fresh-Notebook-Source-CDP-V2.ps1'
$DispatchMarker=Join-Path $Root 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT.dispatched'
$ResultMarker=Join-Path $Root 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_RESULT.json'
$ExpectedFreshSha='123ae76e0e9a282a2b37e397be28295c04f5e052'
$Title='2026-08-29 NotebookLM Fresh E2E 전체 산출물 검증'
$SourceText='2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 이 노트북은 기존 프로젝트와 완전히 분리한다. 핵심 흐름은 FRESH_NOTEBOOK → SOURCE → AUDIO_OVERVIEW → SLIDES → VIDEO_OVERVIEW → REPORT → MIND_MAP → FLASHCARDS → QUIZ → INFOGRAPHIC → DATA_TABLE → NATIVE_DOWNLOAD → DRIVE_READBACK 이다. 고유 마커: NLM_FRESH_ALL_20260829_1915.'
$OldNotebookId='69e055e5-c8d0-4e9c-8686-58cc6da35a51'
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
    $p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $p -Encoding UTF8;return $p
  }catch{return ''}
}
function WriteAgentState{
  $s=ReadJson $StateFile
  if(-not $s){$s=[pscustomobject]@{ok=$true;status='AGENT_APPLIED';agentVersion=$AgentVersion;agentMode='FRESH_NOTEBOOK_DIRECT_1.1.78';updatedAt=(Get-Date).ToString('o')}}
  else{SetProp $s 'agentVersion' $AgentVersion;SetProp $s 'agentMode' 'FRESH_NOTEBOOK_DIRECT_1.1.78';SetProp $s 'updatedAt' (Get-Date).ToString('o')}
  $tmp=$StateFile+'.1178.tmp';$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}
function FetchFreshScript{
  $headers=@{'User-Agent'='HomeDesign-Local-Agent-1.1.78';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $r=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
  if(([string]$r.sha).ToLowerInvariant() -ne $ExpectedFreshSha){throw "FRESH_SCRIPT_API_SHA_MISMATCH actual=$($r.sha) expected=$ExpectedFreshSha"}
  $tmp=$FreshScript+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')))
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $ExpectedFreshSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "FRESH_SCRIPT_LOCAL_SHA_MISMATCH actual=$actual expected=$ExpectedFreshSha"}
  Move-Item -LiteralPath $tmp -Destination $FreshScript -Force
}

$mutex=New-Object System.Threading.Mutex($false,'HomeDesignFreshNotebook1178')
$locked=$false
try{$locked=$mutex.WaitOne(0,$false)}catch{$locked=$false}
if(-not $locked){
  $skip=[ordered]@{ok=$false;action='AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT';state='SKIP_CONCURRENT';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $skip|ConvertTo-Json -Depth 20 -Compress;exit 0
}

$result=[ordered]@{ok=$false;action='AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT';state='STARTING';agentVersion=$AgentVersion;startedAt=(Get-Date).ToString('o');freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;notebookUrl='';notebookId='';previousNotebookId=$OldNotebookId;marker='NLM_FRESH_ALL_20260829_1915';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;freshExit=$null;error='';centralPath=''}
try{
  WriteAgentState
  if(Test-Path -LiteralPath $ResultMarker){
    $prior=ReadJson $ResultMarker
    if($prior){$prior.centralPath=SaveCentral 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_RESULT.json' $prior;$prior|ConvertTo-Json -Depth 30 -Compress;exit $(if([bool]$prior.ok){0}else{2})}
  }
  if(Test-Path -LiteralPath $DispatchMarker){
    $pending=[ordered]@{ok=$false;action='AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT';state='DISPATCH_MARKER_PRESENT_NO_RESULT';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
    [void](SaveCentral 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_PENDING.json' $pending);$pending|ConvertTo-Json -Depth 20 -Compress;exit 2
  }

  $dispatch=[ordered]@{ok=$true;action='AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_DISPATCH';state='DISPATCHED_ONCE';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');oldNotebookId=$OldNotebookId;marker='NLM_FRESH_ALL_20260829_1915';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $dispatch|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $DispatchMarker -Encoding UTF8
  [void](SaveCentral 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_DISPATCH.json' $dispatch)

  FetchFreshScript
  $combined=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FreshScript -Title $Title -SourceText $SourceText -ExpectedOldNotebookId $OldNotebookId -TimeoutSeconds 120 2>&1 | Out-String
  $result.freshExit=$LASTEXITCODE
  $lines=@($combined -split "`r?`n"|Where-Object{$_ -and $_.Trim()});$payload=$null
  for($i=$lines.Count-1;$i -ge 0;$i--){try{$payload=([string]$lines[$i])|ConvertFrom-Json;if($payload){break}}catch{}}
  if(-not $payload){throw ('FRESH_RESULT_JSON_NOT_FOUND: '+($combined.Trim()))}
  $result.freshNotebook=[bool]$payload.freshNotebook;$result.sourceAdded=[bool]$payload.sourceAdded;$result.sourceVerified=[bool]$payload.sourceVerified;$result.notebookUrl=[string]$payload.notebookUrl;$result.notebookId=[string]$payload.notebookId
  if($payload.error){$result.error=[string]$payload.error}
  $validId=([bool][string]$result.notebookId -and [string]$result.notebookId -ne $OldNotebookId)
  $validUrl=([string]$result.notebookUrl -match '^https://notebook\.google\.com/notebook/[0-9a-fA-F-]+')
  $result.ok=([int]$result.freshExit -eq 0 -and [bool]$payload.ok -and $result.freshNotebook -and $result.sourceAdded -and $result.sourceVerified -and $validId -and $validUrl)
  $result.state=if($result.ok){'PASS'}else{'FAIL'}
  if(-not $result.ok -and -not $result.error){$result.error='FRESH_NOTEBOOK_GATE_FAILED'}
}catch{$result.state='ERROR';$result.error=$_.Exception.Message}
finally{
  try{WriteAgentState}catch{}
  $result.completedAt=(Get-Date).ToString('o')
  $result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ResultMarker -Encoding UTF8
  $result.centralPath=SaveCentral 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_RESULT.json' $result
  $result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ResultMarker -Encoding UTF8
  if($locked){try{$mutex.ReleaseMutex()}catch{}};try{$mutex.Dispose()}catch{}
}
$result|ConvertTo-Json -Depth 30 -Compress
if($result.ok){exit 0}else{exit 2}
