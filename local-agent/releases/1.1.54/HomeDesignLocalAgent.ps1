param([int]$MaxScripts=200)

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.54'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$SourceCommit='082d9c3d292d2ffaa3c62ca5d337b0057620caa2'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

$PreviousAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.53.ps1'
$PreviousAgentUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.53/HomeDesignLocalAgent.ps1'
$PreviousAgentSha='f469f17e5d7d0101d5d0f21a521ee449abd747a9'
$ExpectedQueueVersion='0.2.10-queue-lock'
$ExpectedCodeBlob='e7c22534048062eca913e2d1b5d8b3c6e7ac8b28'
$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'
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
  $Object|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding UTF8
}
function ReadJson([string]$Path){
  if(-not $Path -or -not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function QuoteArg([string]$Value){
  if($null -eq $Value){return '""'}
  if($Value -notmatch '[\s"]'){return $Value}
  return '"'+($Value -replace '"','\"')+'"'
}
function InvokeSafe([string]$File,[string[]]$ArgList,[int]$Timeout=90,[string]$Cwd=''){
  $actualFile=$File
  $effective=@($ArgList)
  $ext=[IO.Path]::GetExtension($File).ToLowerInvariant()
  if($ext -eq '.ps1'){
    $actualFile='powershell.exe'
    $effective=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$File)+@($ArgList)
  }elseif($ext -eq '.cmd' -or $ext -eq '.bat'){
    $actualFile='cmd.exe'
    $cmdLine=(QuoteArg $File)
    if($ArgList.Count){$cmdLine+=' '+(($ArgList|ForEach-Object{QuoteArg ([string]$_)})-join ' ')}
    $effective=@('/d','/s','/c',$cmdLine)
  }
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$actualFile
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  if($Cwd){$psi.WorkingDirectory=$Cwd}
  $psi.Arguments=($effective|ForEach-Object{QuoteArg ([string]$_)})-join ' '
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start()
  $ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit($Timeout*1000)){
    try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{}
    return [ordered]@{ok=$false;exit=-1;timedOut=$true;stdout=if($ot.IsCompleted){$ot.Result}else{''};stderr=if($et.IsCompleted){$et.Result}else{''};file=$actualFile;arguments=$psi.Arguments}
  }
  return [ordered]@{ok=($p.ExitCode -eq 0);exit=$p.ExitCode;timedOut=$false;stdout=$ot.Result.Trim();stderr=$et.Result.Trim();file=$actualFile;arguments=$psi.Arguments}
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
function GetClaspIdentity{
  $result=[ordered]@{path='';email='';hasIdToken=$false;status='NOT_FOUND'}
  foreach($p in @((Join-Path $env:USERPROFILE '.clasprc.json'),(Join-Path $env:USERPROFILE '.clasprc.json.backup'))){
    if(-not(Test-Path -LiteralPath $p)){continue}
    try{
      $j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
      $id=''
      if($j.token -and $j.token.id_token){$id=[string]$j.token.id_token}
      elseif($j.tokens -and $j.tokens.default -and $j.tokens.default.id_token){$id=[string]$j.tokens.default.id_token}
      elseif($j.id_token){$id=[string]$j.id_token}
      $result.path=$p;$result.hasIdToken=[bool]$id
      if($id -and $id.Split('.').Count -ge 2){
        try{$part=$id.Split('.')[1].Replace('-','+').Replace('_','/');switch($part.Length%4){2{$part+='=='};3{$part+='='}};$payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part))|ConvertFrom-Json;if($payload.email){$result.email=[string]$payload.email}}catch{}
      }
      $result.status=if($result.email){'EMAIL_DECODED_READONLY'}elseif($id){'ID_TOKEN_PRESENT_EMAIL_NOT_DECODED'}else{'TOKEN_FILE_PRESENT_NO_ID_TOKEN'}
      return $result
    }catch{$result.path=$p;$result.status='TOKEN_FILE_PARSE_FAILED';return $result}
  }
  return $result
}
function GetListedScripts([string]$Clasp){
  $ids=New-Object System.Collections.ArrayList
  $json=InvokeSafe $Clasp @('list-scripts','--json') 90
  if($json.ok -and $json.stdout){
    try{
      $parsed=$json.stdout|ConvertFrom-Json
      $rows=@()
      if($parsed -is [System.Array]){$rows=@($parsed)}elseif($parsed.scripts){$rows=@($parsed.scripts)}elseif($parsed.results){$rows=@($parsed.results)}else{$rows=@($parsed)}
      foreach($row in $rows){
        $id='';if($row.id){$id=[string]$row.id}elseif($row.scriptId){$id=[string]$row.scriptId}
        if($id -and $id -match '^[A-Za-z0-9_-]{40,}$' -and -not $ids.Contains($id)){[void]$ids.Add($id)}
      }
    }catch{}
  }
  $plain=$null
  if(-not $ids.Count){
    $plain=InvokeSafe $Clasp @('list-scripts') 90
    $text=(($plain.stdout+"`n"+$plain.stderr).Trim())
    foreach($m in [regex]::Matches($text,'(?<![A-Za-z0-9_-])([A-Za-z0-9_-]{50,})(?![A-Za-z0-9_-])')){
      $id=[string]$m.Groups[1].Value;if($id -and -not $ids.Contains($id)){[void]$ids.Add($id)}
    }
  }
  return [ordered]@{ok=($ids.Count -gt 0);ids=@($ids|Select-Object -First $MaxScripts);json=$json;plain=$plain}
}
function GetDeployment([string]$Clasp,[string]$ScriptId){
  $r=InvokeSafe $Clasp @('list-deployments',$ScriptId,'--json') 60
  if(-not $r.ok -or -not(($r.stdout+"`n"+$r.stderr) -match [regex]::Escape($ExpectedDeploymentId))){$r=InvokeSafe $Clasp @('list-deployments',$ScriptId) 60}
  if(-not $r.ok -or -not(($r.stdout+"`n"+$r.stderr) -match [regex]::Escape($ExpectedDeploymentId))){$r=InvokeSafe $Clasp @('deployments',$ScriptId) 60}
  $text=(($r.stdout+"`n"+$r.stderr).Trim())
  return [ordered]@{scriptId=$ScriptId;ok=$r.ok;match=[bool]($text -match [regex]::Escape($ExpectedDeploymentId));result=$r;text=$text}
}
function GetProjectRoot([string]$ProjectDir){
  $cfg=Join-Path $ProjectDir '.clasp.json'
  if(Test-Path -LiteralPath $cfg){try{$j=Get-Content -LiteralPath $cfg -Raw -Encoding UTF8|ConvertFrom-Json;if($j.rootDir){return [IO.Path]::GetFullPath((Join-Path $ProjectDir ([string]$j.rootDir)))}}catch{}}
  return $ProjectDir
}
function GetSourceFiles([string]$RootDir){return @(Get-ChildItem -LiteralPath $RootDir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in '.gs','.js','.json','.html' -and $_.Name -ne '.clasp.json'})}
function GetCodeFiles([string]$RootDir){return @(Get-ChildItem -LiteralPath $RootDir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in '.gs','.js'})}
function GetFingerprint([string]$ProjectDir){
  $parts=@();foreach($f in @(Get-ChildItem -LiteralPath $ProjectDir -File -Recurse -ErrorAction SilentlyContinue|Sort-Object FullName)){$rel=$f.FullName.Substring($ProjectDir.Length).TrimStart('\');$parts+=($rel+':'+(Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash)}
  if(-not $parts.Count){return ''};$bytes=[Text.Encoding]::UTF8.GetBytes(($parts-join "`n"));$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
}
function TestNotebookSignature([string]$RootDir){
  $joined=(@(GetSourceFiles $RootDir)|ForEach-Object{try{Get-Content $_.FullName -Raw -Encoding UTF8}catch{''}})-join "`n"
  $score=0;$matches=@()
  if($joined -match 'NotebookLM_Task_Queue'){$score+=100;$matches+='NotebookLM_Task_Queue'}
  if($joined -match 'enqueueFromWriter_'){$score+=60;$matches+='enqueueFromWriter_'}
  if($joined -match 'NotebookLM WebApp Bridge'){$score+=60;$matches+='NotebookLM WebApp Bridge'}
  if($joined -match 'setupNotebookLMBridge'){$score+=40;$matches+='setupNotebookLMBridge'}
  if($joined -match [regex]::Escape($TargetSpreadsheetId)){$score+=80;$matches+='TargetSpreadsheetId'}
  if($joined -match [regex]::Escape($ExpectedQueueVersion)){$matches+='ExpectedQueueVersion'}
  return [ordered]@{score=$score;matches=$matches;alreadyCompliant=[bool]($joined -match [regex]::Escape($ExpectedQueueVersion) -and $joined -match 'LockService\.getScriptLock' -and $joined -match 'TASK_ROW_ID_MISMATCH')}
}
function RestoreBackup([string]$ProjectDir,[string]$BackupDir,[string]$Clasp,[string]$ExpectedFingerprint){
  foreach($f in @(Get-ChildItem -LiteralPath $ProjectDir -File -Recurse -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue}
  foreach($f in @(Get-ChildItem -LiteralPath $BackupDir -File -Recurse -ErrorAction SilentlyContinue)){
    $rel=$f.FullName.Substring($BackupDir.Length).TrimStart('\');$dest=Join-Path $ProjectDir $rel;$par=Split-Path -Parent $dest;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
  }
  $push=InvokeSafe $Clasp @('push','--force') 180 $ProjectDir
  $pull=if($push.ok){InvokeSafe $Clasp @('pull') 120 $ProjectDir}else{$null}
  $fp=if($pull -and $pull.ok){GetFingerprint $ProjectDir}else{''}
  return [ordered]@{ok=[bool]($push.ok -and $pull -and $pull.ok -and $fp -eq $ExpectedFingerprint);push=$push;pull=$pull;fingerprint=$fp}
}

$central=FindCentralRoot
$runtimeRoot=if($central){Join-Path $central 'Runtime_Readback'}else{''}
$queueFolder=if($runtimeRoot){Join-Path $runtimeRoot 'AppsScript_QueueIntegrity'}else{$Root}
$canonicalPath=Join-Path $queueFolder 'NOTEBOOKLM_QUEUE_INTEGRITY_SYNC.json'
$v3Path=Join-Path $queueFolder 'NOTEBOOKLM_QUEUE_INTEGRITY_SYNC_V3.json'
$agentPath=if($runtimeRoot){Join-Path $runtimeRoot 'AGENT_1.1.54_NOTEBOOKLM_EXACT_SCRIPT_QUEUE_FIX.json'}else{Join-Path $Root 'AGENT_1.1.54_NOTEBOOKLM_EXACT_SCRIPT_QUEUE_FIX.json'}
$queue=ReadJson $canonicalPath
$existingV3=ReadJson $v3Path
$eligible=[bool]($queue -and -not [bool]$queue.ok -and [string]$queue.version -eq $ExpectedQueueVersion -and [string]$queue.stage -eq 'BINDING_VERIFY' -and [string]$queue.sourceSha -eq $ExpectedCodeBlob -and [string]$queue.error -match '^NOTEBOOKLM_EXISTING_PROJECT_NOT_FOUND')
$terminalV3=[bool]($existingV3 -and [string]$existingV3.status -in @('PUSH_PULL_READBACK_PASS','FAILED','FAILED_ROLLED_BACK'))

$errors=@();$previousSha='';$previousRun=$null;$previousParsed=$null
try{$previousSha=FetchPinned $PreviousAgentUrl $PreviousAgent $PreviousAgentSha;$previousRun=InvokeChild $PreviousAgent;$previousParsed=LastJson ([string]$previousRun.stdout)}catch{$errors+=('PREVIOUS_AGENT:'+$_.Exception.Message)}
$previousOk=[bool]($previousSha -eq $PreviousAgentSha -and $previousRun -and [int]$previousRun.exitCode -eq 0 -and $previousParsed -and [bool]$previousParsed.ok)

$diag=[ordered]@{ok=$false;action='NOTEBOOKLM_EXACT_EXISTING_SCRIPT_QUEUE_FIX_V3';agentVersion=$AgentVersion;eligible=$eligible;terminalV3=$terminalV3;claspIdentity=$null;list=$null;deploymentChecks=@();targetScriptId='';targetPrefixMatch=$false;clone=$null;signatureBefore=$null;backup='';sourceSha='';remoteWriteStarted=$false;push=$null;pullReadback=$null;signatureAfter=$null;deploymentAfter=$null;rollback=$null;status='NOT_RUN';newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;browserLaunched=$false;queueTaskCreated=$false;paidGeminiApiCalled=$false;creditSpend=$false;at=(Get-Date).ToString('o')}

if(-not $previousOk){$diag.status='PREVIOUS_AGENT_HOLD'}
elseif($terminalV3){$diag=$existingV3}
elseif(-not $eligible){$diag.status='QUEUE_NOT_ELIGIBLE_FOR_V3'}
else{
  $stage='CLASP_DISCOVERY';$targetDir='';$backupDir='';$beforeFp='';$pushDone=$false
  try{
    $diag.claspIdentity=GetClaspIdentity
    if($diag.claspIdentity.email -and [string]$diag.claspIdentity.email -ne 'homedesigntaedi@gmail.com'){throw ('CLASP_ACCOUNT_MISMATCH:'+[string]$diag.claspIdentity.email)}
    $clasp=Get-Command clasp.cmd -ErrorAction SilentlyContinue;if(-not $clasp){$clasp=Get-Command clasp -ErrorAction SilentlyContinue};if(-not $clasp){throw 'CLASP_NOT_FOUND'}
    $stage='LIST_SCRIPTS_READONLY';$diag.list=GetListedScripts $clasp.Source;if(-not $diag.list.ok -or -not $diag.list.ids.Count){throw 'CLASP_LIST_SCRIPTS_NO_IDS'}
    $stage='TARGET_BY_DEPLOYMENT_READONLY';$matches=@()
    foreach($id in @($diag.list.ids|Select-Object -First $MaxScripts)){
      $check=GetDeployment $clasp.Source ([string]$id);$diag.deploymentChecks+=([ordered]@{scriptId=$check.scriptId;ok=$check.ok;match=$check.match})
      if($check.match){$matches+=[string]$id}
    }
    $matches=@($matches|Select-Object -Unique);if($matches.Count -ne 1){throw ('TARGET_DEPLOYMENT_MATCH_COUNT:'+$matches.Count)}
    $diag.targetScriptId=$matches[0];$diag.targetPrefixMatch=[bool]($diag.targetScriptId.StartsWith($KnownScriptPrefix))
    $stage='CLONE_EXISTING_READONLY';$work=Join-Path $Base ('NotebookLMQueueFixV3\'+(Get-Date -Format 'yyyyMMdd_HHmmss'));$targetDir=Join-Path $work 'project';New-Item -ItemType Directory -Force -Path $targetDir|Out-Null
    $clone=InvokeSafe $clasp.Source @('clone-script',$diag.targetScriptId) 120 $targetDir;if(-not $clone.ok){$clone=InvokeSafe $clasp.Source @('clone',$diag.targetScriptId) 120 $targetDir};$diag.clone=$clone;if(-not $clone.ok){throw ('CLONE_FAILED:'+($clone.stderr+' '+$clone.stdout).Trim())}
    $root=GetProjectRoot $targetDir;$diag.signatureBefore=TestNotebookSignature $root;if([int]$diag.signatureBefore.score -lt 160){throw ('NOTEBOOKLM_REMOTE_SIGNATURE_SCORE_LOW:'+$diag.signatureBefore.score)}
    $beforeFp=GetFingerprint $targetDir;$backupDir=if($central){Join-Path $central ('Backups\AppsScript_QueueIntegrity\'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}else{Join-Path $work 'backup'};New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
    foreach($f in @(Get-ChildItem -LiteralPath $targetDir -File -Recurse -ErrorAction SilentlyContinue)){$rel=$f.FullName.Substring($targetDir.Length).TrimStart('\');$dest=Join-Path $backupDir $rel;$par=Split-Path -Parent $dest;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};Copy-Item -LiteralPath $f.FullName -Destination $dest -Force};$diag.backup=$backupDir
    if(-not [bool]$diag.signatureBefore.alreadyCompliant){
      $stage='SOURCE_FETCH';$src=Join-Path $work 'Code.gs';$url='https://raw.githubusercontent.com/'+$Repo+'/'+$SourceCommit+'/notebooklm-webapp-bridge-source-v0.2.0/apps-script/Code.gs?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $src -TimeoutSec 30;$diag.sourceSha=(GitBlobSha1 $src).ToLowerInvariant();if($diag.sourceSha -ne $ExpectedCodeBlob){throw ('QUEUE_CODE_SHA_MISMATCH:'+$diag.sourceSha)}
      $stage='ONE_PUSH';$diag.remoteWriteStarted=$true
      foreach($f in @(GetCodeFiles $root)){Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue}
      Copy-Item -LiteralPath $src -Destination (Join-Path $root 'Code.js') -Force
      $diag.push=InvokeSafe $clasp.Source @('push','--force') 180 $targetDir;if(-not $diag.push.ok){throw ('CLASP_PUSH_FAILED:'+($diag.push.stderr+' '+$diag.push.stdout).Trim())};$pushDone=$true
    }else{$diag.sourceSha=$ExpectedCodeBlob}
    $stage='PULL_READBACK';$diag.pullReadback=InvokeSafe $clasp.Source @('pull') 120 $targetDir;if(-not $diag.pullReadback.ok){throw ('CLASP_PULL_READBACK_FAILED:'+($diag.pullReadback.stderr+' '+$diag.pullReadback.stdout).Trim())}
    $root=GetProjectRoot $targetDir;$diag.signatureAfter=TestNotebookSignature $root;if(-not [bool]$diag.signatureAfter.alreadyCompliant){throw ('PULL_READBACK_CONTRACT_MISMATCH:'+($diag.signatureAfter|ConvertTo-Json -Compress))}
    $stage='DEPLOYMENT_INVARIANT';$diag.deploymentAfter=GetDeployment $clasp.Source $diag.targetScriptId;if(-not $diag.deploymentAfter.match){throw 'DEPLOYMENT_INVARIANT_LOST'}
    $diag.ok=$true;$diag.status='PUSH_PULL_READBACK_PASS';$diag.at=(Get-Date).ToString('o')
    SaveJson $v3Path $diag
    $canonical=[ordered]@{ok=$true;status='PUSH_PULL_READBACK_PASS';version=$ExpectedQueueVersion;stage='DONE';error='';scriptId=$diag.targetScriptId;deploymentId=$ExpectedDeploymentId;backup=$diag.backup;sourceSha=$ExpectedCodeBlob;push=$diag.push;pullReadback=$diag.pullReadback;signatureBefore=$diag.signatureBefore;signatureAfter=$diag.signatureAfter;deploymentInvariant=$true;mode=if($diag.remoteWriteStarted){'ONE_PUSH_EXACT_EXISTING_PROJECT'}else{'ALREADY_COMPLIANT_READBACK'};newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;generateClicked=$false;creditSpend=$false;at=(Get-Date).ToString('o')};SaveJson $canonicalPath $canonical
  }catch{
    $errors+=($stage+':'+$_.Exception.Message)
    if($pushDone -and $targetDir -and $backupDir -and $clasp){try{$diag.rollback=RestoreBackup $targetDir $backupDir $clasp.Source $beforeFp}catch{$errors+=('ROLLBACK:'+$_.Exception.Message)}}
    $diag.ok=$false;$diag.status=if($pushDone -and $diag.rollback -and [bool]$diag.rollback.ok){'FAILED_ROLLED_BACK'}else{'FAILED'};$diag.at=(Get-Date).ToString('o');$diag|Add-Member errors $errors -Force;SaveJson $v3Path $diag
  }
}
if(-not $diag.PSObject.Properties['errors']){$diag|Add-Member errors $errors -Force}
$receipt=[ordered]@{ok=$previousOk;governanceOk=$previousOk;queueIntegrityVerified=[bool]($diag -and [bool]$diag.ok -and [string]$diag.status -eq 'PUSH_PULL_READBACK_PASS');action='AGENT_1.1.54_NOTEBOOKLM_EXACT_SCRIPT_QUEUE_FIX';agentVersion=$AgentVersion;status=if($diag -and [bool]$diag.ok){'NOTEBOOKLM_QUEUE_INTEGRITY_V3_PASS'}elseif($previousOk){'PREVIOUS_AGENT_PASS_NOTEBOOKLM_QUEUE_V3_HOLD'}else{'PREVIOUS_AGENT_HOLD_NOTEBOOKLM_QUEUE_V3_HOLD'};previousAgentVersion='1.1.53';previousAgentSha=$previousSha;previousExitCode=if($previousRun){$previousRun.exitCode}else{$null};previousResult=$previousParsed;queueFix=$diag;newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;browserLaunched=$false;queueTaskCreated=$false;paidGeminiApiCalled=$false;creditSpend=$false;errors=$errors;at=(Get-Date).ToString('o')}
try{SaveJson $agentPath $receipt}catch{}
try{$s=ReadJson $State;if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member agentMode 'NOTEBOOKLM_EXACT_SCRIPT_QUEUE_FIX_1.1.54' -Force;$s|Add-Member ok $previousOk -Force;$s|Add-Member governanceOk $previousOk -Force;$s|Add-Member queueIntegrityVerified ([bool]$receipt.queueIntegrityVerified) -Force;$s|Add-Member status ([string]$receipt.status) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $State $s}catch{}
$receipt|ConvertTo-Json -Depth 100 -Compress
if($previousOk){exit 0}else{exit 2}
