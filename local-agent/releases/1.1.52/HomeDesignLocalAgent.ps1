param()

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.52'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$PreviousAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.51.ps1'
$PreviousAgentUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.51/HomeDesignLocalAgent.ps1'
$PreviousAgentSha='bb5ae000c04a679750dadaef00160a14a3cf76c0'
$ExpectedQueueVersion='0.2.10-queue-lock'
$ExpectedQueueSourceSha='e7c22534048062eca913e2d1b5d8b3c6e7ac8b28'
$TargetSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'
$KnownScriptPrefix='1dmbf19qgN6Q-CwLYOIx27L8Q6uUD85fZXNSy00AS_HpXB'
$State=Join-Path $Root 'state.json'

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path)
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[] ($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}
  finally{$s.Dispose()}
}
function FetchPinned([string]$Url,[string]$Destination,[string]$ExpectedSha){
  $tmp=$Destination+'.download'
  Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
  if($actual -ne $ExpectedSha.ToLowerInvariant()){
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw ('SHA_MISMATCH:'+$actual+':'+$ExpectedSha)
  }
  Move-Item -LiteralPath $tmp -Destination $Destination -Force
  return $actual
}
function FindCentralRoot{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not $drv.Root){continue}
    foreach($cand in @(
      (Join-Path $drv.Root $centralName),
      (Join-Path $drv.Root ($myDriveKo+'\'+$centralName)),
      (Join-Path $drv.Root ('My Drive\'+$centralName)),
      (Join-Path $drv.Root ('Google Drive\'+$centralName))
    )){
      if(Test-Path -LiteralPath $cand -PathType Container){return $cand}
    }
  }
  return ''
}
function SaveJson([string]$Path,$Object){
  if(-not $Path){return}
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  $Object|ConvertTo-Json -Depth 80|Set-Content -LiteralPath $Path -Encoding UTF8
}
function ReadJson([string]$Path){
  if(-not $Path -or -not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function SafeRun([string]$File,[string[]]$Args,[int]$Timeout=90,[string]$Cwd=''){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$File;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  if($Cwd){$psi.WorkingDirectory=$Cwd}
  $psi.Arguments=($Args|ForEach-Object{if($_ -match '[\s"]'){'"'+($_ -replace '"','\"')+'"'}else{$_}})-join ' '
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start()
  $ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit($Timeout*1000)){
    try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{}
    return [ordered]@{ok=$false;exit=-1;timedOut=$true;stdout=$ot.Result;stderr=$et.Result}
  }
  return [ordered]@{ok=($p.ExitCode -eq 0);exit=$p.ExitCode;timedOut=$false;stdout=$ot.Result.Trim();stderr=$et.Result.Trim()}
}
function InvokeChild([string]$Path){
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path 2>&1|Out-String
  return [ordered]@{exitCode=$LASTEXITCODE;stdout=$out.Trim()}
}
function LastJson([string]$Text){
  $parsed=$null
  foreach($line in @($Text -split "`r?`n")){
    if(-not $line -or -not $line.Trim()){continue}
    try{$candidate=$line.Trim()|ConvertFrom-Json;if($candidate -and $null -ne $candidate.ok){$parsed=$candidate}}catch{}
  }
  return $parsed
}
function DecodeJwtEmail([string]$Jwt){
  if(-not $Jwt -or $Jwt.Split('.').Count -lt 2){return ''}
  try{
    $p=$Jwt.Split('.')[1].Replace('-','+').Replace('_','/')
    switch($p.Length % 4){2{$p+='=='};3{$p+='='}}
    $j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))|ConvertFrom-Json
    if($j.email){return [string]$j.email}
  }catch{}
  return ''
}
function GetClaspIdentity{
  $result=[ordered]@{path='';email='';hasIdToken=$false;status='NOT_FOUND'}
  $cands=@(
    (Join-Path $env:USERPROFILE '.clasprc.json'),
    (Join-Path $env:USERPROFILE '.clasprc.json.backup')
  )
  foreach($p in $cands){
    if(-not(Test-Path -LiteralPath $p)){continue}
    try{
      $j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
      $id=''
      if($j.token -and $j.token.id_token){$id=[string]$j.token.id_token}
      elseif($j.tokens -and $j.tokens.default -and $j.tokens.default.id_token){$id=[string]$j.tokens.default.id_token}
      elseif($j.id_token){$id=[string]$j.id_token}
      $result.path=$p;$result.hasIdToken=[bool]$id;$result.email=DecodeJwtEmail $id
      $result.status=if($result.email){'EMAIL_DECODED_READONLY'}elseif($id){'ID_TOKEN_PRESENT_EMAIL_NOT_DECODED'}else{'TOKEN_FILE_PRESENT_NO_ID_TOKEN'}
      return $result
    }catch{$result.path=$p;$result.status='TOKEN_FILE_PARSE_FAILED';return $result}
  }
  return $result
}
function ReadSharedAscii([string]$Path,[long]$MaxBytes=134217728){
  $fs=$null
  try{
    $fs=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $len=[Math]::Min($fs.Length,$MaxBytes)
    if($len -le 0){return ''}
    $b=New-Object byte[] ([int]$len)
    $read=0
    while($read -lt $len){$n=$fs.Read($b,$read,[int]($len-$read));if($n -le 0){break};$read+=$n}
    if($read -lt $b.Length){$tmp=New-Object byte[] $read;[Buffer]::BlockCopy($b,0,$tmp,0,$read);$b=$tmp}
    return [Text.Encoding]::ASCII.GetString($b)
  }catch{return ''}
  finally{if($fs){$fs.Dispose()}}
}
function AddCandidateHits([string]$Path,[string]$Text,[hashtable]$Map,[System.Collections.ArrayList]$Evidence){
  if(-not $Text){return}
  $rx=[regex]::Escape($KnownScriptPrefix)+'[A-Za-z0-9_-]{11}'
  foreach($m in [regex]::Matches($Text,$rx)){
    $id=[string]$m.Value
    if(-not $Map.ContainsKey($id)){$Map[$id]=0}
    $Map[$id]=[int]$Map[$id]+1
    if($Evidence.Count -lt 100){[void]$Evidence.Add([ordered]@{scriptId=$id;source=$Path})}
  }
}
function GetBoundScriptCandidates([string]$CentralRoot){
  $map=@{};$evidence=New-Object System.Collections.ArrayList;$scanned=0;$errors=0
  $paths=New-Object System.Collections.ArrayList
  $chromeRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  foreach($profile in @('Default','Profile 1','Profile 2')){
    $p=Join-Path $chromeRoot $profile
    foreach($name in @('History','History-journal')){$f=Join-Path $p $name;if(Test-Path -LiteralPath $f -PathType Leaf){[void]$paths.Add($f)}}
    $sess=Join-Path $p 'Sessions'
    if(Test-Path -LiteralPath $sess -PathType Container){foreach($f in @(Get-ChildItem -LiteralPath $sess -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 30)){[void]$paths.Add($f.FullName)}}
  }
  foreach($root in @($Root,$Base,$CentralRoot,(Join-Path $env:USERPROFILE 'Documents'),(Join-Path $env:USERPROFILE 'Desktop'))){
    if(-not $root -or -not(Test-Path -LiteralPath $root -PathType Container)){continue}
    try{
      foreach($f in @(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Length -le 33554432 -and ($_.Extension -in '.json','.txt','.log','.ps1','.js','.gs','.html','.md' -or $_.Name -match 'History|Session|Tabs|Apps')}|Sort-Object LastWriteTime -Descending|Select-Object -First 400)){
        [void]$paths.Add($f.FullName)
      }
    }catch{}
  }
  foreach($p in @($paths|Select-Object -Unique)){
    try{$t=ReadSharedAscii $p;$scanned++;AddCandidateHits $p $t $map $evidence}catch{$errors++}
  }
  $cands=@($map.Keys|Sort-Object|ForEach-Object{[ordered]@{scriptId=$_;hits=$map[$_]}})
  return [ordered]@{candidates=$cands;evidence=@($evidence);scanned=$scanned;readErrors=$errors}
}
function VerifyCandidateReadOnly([string]$Clasp,[string]$ScriptId,[string]$WorkRoot){
  $dir=Join-Path $WorkRoot ('candidate-'+$ScriptId.Substring(0,[Math]::Min(12,$ScriptId.Length)))
  New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $clone=SafeRun $Clasp @('clone',$ScriptId) 90 $dir
  $score=0;$matches=@();$joined=''
  if($clone.ok){
    $files=@(Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in '.gs','.js','.json','.html'})
    $joined=($files|ForEach-Object{try{Get-Content $_.FullName -Raw -Encoding UTF8}catch{''}})-join "`n"
    if($joined -match 'NotebookLM_Task_Queue'){$score+=100;$matches+='NotebookLM_Task_Queue'}
    if($joined -match 'enqueueFromWriter_'){$score+=60;$matches+='enqueueFromWriter_'}
    if($joined -match 'NotebookLM WebApp Bridge'){$score+=60;$matches+='NotebookLM WebApp Bridge'}
    if($joined -match 'setupNotebookLMBridge'){$score+=40;$matches+='setupNotebookLMBridge'}
    if($joined -match [regex]::Escape($TargetSpreadsheetId)){$score+=80;$matches+='TargetSpreadsheetId'}
  }
  return [ordered]@{scriptId=$ScriptId;cloneOk=[bool]$clone.ok;cloneExit=$clone.exit;score=$score;matches=$matches;stderr=$clone.stderr;stdout=$clone.stdout;tempDir=$dir}
}

$central=FindCentralRoot
$runtimeRoot=if($central){Join-Path $central 'Runtime_Readback'}else{''}
$queueReceipt=if($runtimeRoot){Join-Path $runtimeRoot 'AppsScript_QueueIntegrity\NOTEBOOKLM_QUEUE_INTEGRITY_SYNC.json'}else{''}
$recoveryReceipt=if($runtimeRoot){Join-Path $runtimeRoot 'AppsScript_QueueIntegrity\NOTEBOOKLM_BOUND_SCRIPT_ID_RECOVERY_1.1.52.json'}else{Join-Path $Root 'NOTEBOOKLM_BOUND_SCRIPT_ID_RECOVERY_1.1.52.json'}
$queue=ReadJson $queueReceipt
$trigger=[bool]($queue -and -not [bool]$queue.ok -and [string]$queue.version -eq $ExpectedQueueVersion -and [string]$queue.stage -eq 'BINDING_VERIFY' -and [string]$queue.sourceSha -eq $ExpectedQueueSourceSha -and [string]$queue.error -match '^NOTEBOOKLM_EXISTING_PROJECT_NOT_FOUND')
$diag=[ordered]@{ok=$false;action='NOTEBOOKLM_BOUND_SCRIPT_ID_READONLY_RECOVERY';agentVersion=$AgentVersion;triggerMatched=$trigger;queue=$queue;claspIdentity=$null;claspList=$null;scan=$null;verification=$null;candidateScriptId='';readyForOnePush=$false;status='NOT_RUN';newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;browserLaunched=$false;queueTaskCreated=$false;remoteWriteStarted=$false;paidGeminiApiCalled=$false;creditSpend=$false;at=(Get-Date).ToString('o')}
$errors=@()
if($trigger){
  try{$diag.claspIdentity=GetClaspIdentity}catch{$errors+=('CLASP_IDENTITY:'+$_.Exception.Message)}
  $clasp=(Get-Command clasp.cmd -ErrorAction SilentlyContinue);if(-not $clasp){$clasp=Get-Command clasp -ErrorAction SilentlyContinue}
  if($clasp){
    try{$diag.claspList=SafeRun $clasp.Source @('list') 60}catch{$errors+=('CLASP_LIST:'+$_.Exception.Message)}
  }else{$errors+='CLASP_NOT_FOUND'}
  try{$diag.scan=GetBoundScriptCandidates $central}catch{$errors+=('LOCAL_SCAN:'+$_.Exception.Message)}
  $ids=@()
  if($diag.scan -and $diag.scan.candidates){$ids=@($diag.scan.candidates|ForEach-Object{[string]$_.scriptId}|Where-Object{$_}|Select-Object -Unique)}
  if($ids.Count -eq 1 -and $clasp){
    $work=Join-Path $Base ('BoundScriptRecovery\'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $work|Out-Null
    try{$diag.verification=VerifyCandidateReadOnly $clasp.Source $ids[0] $work}catch{$errors+=('CANDIDATE_VERIFY:'+$_.Exception.Message)}
    if($diag.verification -and [bool]$diag.verification.cloneOk -and [int]$diag.verification.score -ge 160){
      $diag.ok=$true;$diag.candidateScriptId=$ids[0];$diag.readyForOnePush=$true;$diag.status='UNIQUE_BOUND_SCRIPT_CANDIDATE_VERIFIED_READONLY'
    }else{$diag.status='UNIQUE_PREFIX_CANDIDATE_REMOTE_SIGNATURE_NOT_VERIFIED'}
  }elseif($ids.Count -gt 1){$diag.status='MULTIPLE_PREFIX_CANDIDATES_HOLD'}
  elseif(-not $clasp){$diag.status='CLASP_NOT_FOUND_HOLD'}
  else{$diag.status='NO_FULL_SCRIPT_ID_RECOVERED_HOLD'}
}else{$diag.status='QUEUE_FAILURE_NOT_MATCHING_RECOVERY_CONTRACT'}
$diag|Add-Member errors $errors -Force
SaveJson $recoveryReceipt $diag

$previousSha='';$previousRun=$null;$previousParsed=$null
try{
  $previousSha=FetchPinned $PreviousAgentUrl $PreviousAgent $PreviousAgentSha
  $previousRun=InvokeChild $PreviousAgent
  $previousParsed=LastJson ([string]$previousRun.stdout)
}catch{$errors+=('PREVIOUS_AGENT:'+$_.Exception.Message)}
$previousOk=[bool]($previousSha -eq $PreviousAgentSha -and $previousRun -and [int]$previousRun.exitCode -eq 0 -and $previousParsed -and [bool]$previousParsed.ok)
$receipt=[ordered]@{ok=$previousOk;governanceOk=$previousOk;action='AGENT_1.1.52_BOUND_SCRIPT_READONLY_RECOVERY';agentVersion=$AgentVersion;status=if($diag.readyForOnePush){'BOUND_SCRIPT_CANDIDATE_VERIFIED_WAIT_ONE_PUSH_PATCH'}elseif($previousOk){'PREVIOUS_AGENT_PASS_BOUND_SCRIPT_RECOVERY_HOLD'}else{'PREVIOUS_AGENT_HOLD_BOUND_SCRIPT_RECOVERY_HOLD'};recovery=$diag;previousAgentVersion='1.1.51';previousAgentSha=$previousSha;previousExitCode=if($previousRun){$previousRun.exitCode}else{$null};previousResult=$previousParsed;newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;browserLaunched=$false;queueTaskCreated=$false;remoteWriteStarted=$false;paidGeminiApiCalled=$false;creditSpend=$false;errors=$errors;at=(Get-Date).ToString('o')}
if($runtimeRoot){SaveJson (Join-Path $runtimeRoot 'AGENT_1.1.52_BOUND_SCRIPT_READONLY_RECOVERY.json') $receipt}
try{
  $s=ReadJson $State;if(-not $s){$s=[pscustomobject]@{}}
  $s|Add-Member agentVersion $AgentVersion -Force
  $s|Add-Member agentMode 'BOUND_SCRIPT_READONLY_RECOVERY_1.1.52' -Force
  $s|Add-Member ok $previousOk -Force
  $s|Add-Member governanceOk $previousOk -Force
  $s|Add-Member boundScriptCandidateVerified ([bool]$diag.readyForOnePush) -Force
  $s|Add-Member status ([string]$receipt.status) -Force
  $s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force
  SaveJson $State $s
}catch{}
$receipt|ConvertTo-Json -Depth 80 -Compress
if($previousOk){exit 0}else{exit 2}
