param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$AgentVersion='1.1.77'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$BaseRoot=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $BaseRoot 'LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$BaseAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.32-base.ps1'
$FreshScript=Join-Path $Root 'NotebookLM-Fresh-Notebook-Source-CDP-V2.ps1'
$ResultMarker=Join-Path $Root 'AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT.json'
$DispatchMarker=Join-Path $Root 'AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT.dispatched'
$ExpectedBaseSha='a38da31ff6aad74c43839a7b010909fec041342d'
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
function ApiFile([string]$Path,[string]$Expected,[string]$Dest){
  $headers=@{'User-Agent'='HomeDesign-Local-Agent-1.1.77';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $r=Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
  if(([string]$r.sha).ToLowerInvariant() -ne $Expected.ToLowerInvariant()){throw "API_BLOB_MISMATCH path=$Path actual=$($r.sha) expected=$Expected"}
  $bytes=[Convert]::FromBase64String(([string]$r.content -replace '\s',''));$tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,$bytes)
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "LOCAL_BLOB_MISMATCH path=$Path actual=$actual expected=$Expected"}
  Move-Item $tmp $Dest -Force
}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function SetProp($Obj,[string]$Name,$Value){if($Obj.PSObject.Properties[$Name]){$Obj.$Name=$Value}else{$Obj|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not$r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  return ''
}
function WriteCentralNamed([string]$Name,$Object){
  $central=FindCentral;if(-not$central){return ''}
  try{$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}
}
function WriteState1177{
  $s=ReadJson $StateFile
  if(-not$s){$s=[pscustomobject]@{ok=$true;status='AGENT_APPLIED';agentVersion=$AgentVersion;agentMode='FRESH_NOTEBOOK_DIRECT_ONESHOT_1.1.77';updatedAt=(Get-Date).ToString('o')}}
  else{SetProp $s 'agentVersion' $AgentVersion;SetProp $s 'agentMode' 'FRESH_NOTEBOOK_DIRECT_ONESHOT_1.1.77';SetProp $s 'updatedAt' (Get-Date).ToString('o')}
  $tmp=$StateFile+'.1177.tmp';$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item $tmp $StateFile -Force
}

$mutex=New-Object System.Threading.Mutex($false,'HomeDesignFreshNotebook1177')
$haveMutex=$false
try{$haveMutex=$mutex.WaitOne(0,$false)}catch{$haveMutex=$false}
if(-not$haveMutex){
  $skip=[ordered]@{ok=$false;action='AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT';state='SKIP_CONCURRENT_INSTANCE';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $skip|ConvertTo-Json -Depth 20 -Compress;exit 0
}

$result=[ordered]@{ok=$false;action='AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT';state='STARTING';agentVersion=$AgentVersion;startedAt=(Get-Date).ToString('o');baseAgentExit=$null;freshExit=$null;freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;notebookUrl='';notebookId='';previousNotebookId=$OldNotebookId;marker='NLM_FRESH_ALL_20260829_1915';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
try{
  if(Test-Path -LiteralPath $ResultMarker){
    $prior=ReadJson $ResultMarker
    if($prior){$p=WriteCentralNamed 'AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT.json' $prior;if($p){SetProp $prior 'centralPath' $p};$prior|ConvertTo-Json -Depth 30 -Compress;exit $(if([bool]$prior.ok){0}else{2})}
  }
  if(Test-Path -LiteralPath $DispatchMarker){
    $pending=[ordered]@{ok=$false;action='AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT';state='PREVIOUS_DISPATCH_MARKER_PRESENT_NO_RESULT';agentVersion=$AgentVersion;freshNotebook=$false;sourceAdded=$false;sourceVerified=$false;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}
    [void](WriteCentralNamed 'AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT_PENDING.json' $pending)
    $pending|ConvertTo-Json -Depth 20 -Compress;exit 2
  }

  ApiFile 'local-agent/releases/1.1.32/HomeDesignLocalAgent.ps1' $ExpectedBaseSha $BaseAgent
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BaseAgent | Out-Null
  $result.baseAgentExit=$LASTEXITCODE
  if([int]$result.baseAgentExit -ne 0){throw "BASE_AGENT_1.1.32_EXIT_$($result.baseAgentExit)"}
  WriteState1177

  $dispatch=[ordered]@{ok=$true;action='AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_DISPATCH';state='DISPATCHED_ONCE';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');oldNotebookId=$OldNotebookId;marker='NLM_FRESH_ALL_20260829_1915';normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false}
  $dispatch|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $DispatchMarker -Encoding UTF8
  [void](WriteCentralNamed 'AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_DISPATCH.json' $dispatch)

  ApiFile 'local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1' $ExpectedFreshSha $FreshScript
  $combined=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FreshScript -Title $Title -SourceText $SourceText -ExpectedOldNotebookId $OldNotebookId -TimeoutSeconds 120 2>&1 | Out-String
  $result.freshExit=$LASTEXITCODE
  $lines=@($combined -split "`r?`n"|Where-Object{$_ -and $_.Trim()});$payload=$null
  for($i=$lines.Count-1;$i -ge 0;$i--){try{$payload=([string]$lines[$i])|ConvertFrom-Json;if($payload){break}}catch{}}
  if(-not$payload){throw ('FRESH_RESULT_JSON_NOT_FOUND: '+($combined.Trim()))}
  $result.freshNotebook=[bool]$payload.freshNotebook;$result.sourceAdded=[bool]$payload.sourceAdded;$result.sourceVerified=[bool]$payload.sourceVerified;$result.notebookUrl=[string]$payload.notebookUrl;$result.notebookId=[string]$payload.notebookId
  if($payload.error){$result.error=[string]$payload.error}
  $validId=([bool][string]$result.notebookId -and [string]$result.notebookId -ne $OldNotebookId);$validUrl=([string]$result.notebookUrl -match '^https://notebook\.google\.com/notebook/[0-9a-fA-F-]+')
  $result.ok=([int]$result.freshExit -eq 0 -and [bool]$payload.ok -and $result.freshNotebook -and $result.sourceAdded -and $result.sourceVerified -and $validId -and $validUrl)
  $result.state=if($result.ok){'PASS'}else{'FAIL'}
  if(-not$result.ok -and -not$result.error){$result.error='FRESH_NOTEBOOK_GATE_FAILED'}
}catch{$result.state='ERROR';$result.error=$_.Exception.Message}
finally{
  try{WriteState1177}catch{}
  $result.completedAt=(Get-Date).ToString('o')
  $result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ResultMarker -Encoding UTF8
  $result.centralPath=WriteCentralNamed 'AGENT_1.1.77_FRESH_NOTEBOOK_DIRECT_ONESHOT.json' $result
  $result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $ResultMarker -Encoding UTF8
  if($haveMutex){try{$mutex.ReleaseMutex()}catch{}}
  try{$mutex.Dispose()}catch{}
}
$result|ConvertTo-Json -Depth 30 -Compress
if($result.ok){exit 0}else{exit 2}
