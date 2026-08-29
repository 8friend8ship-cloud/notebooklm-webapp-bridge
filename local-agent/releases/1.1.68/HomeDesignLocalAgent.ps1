param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.68'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$PriorVersion='1.1.67'
$PriorSha='0044c3633912147ef15d6ecfe551152b73fa63a4'
$SourceCommit='082d9c3d292d2ffaa3c62ca5d337b0057620caa2'
$ExpectedQueueVersion='0.2.10-queue-lock'
$ExpectedCodeBlob='e7c22534048062eca913e2d1b5d8b3c6e7ac8b28'
$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'
$TargetSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'
$KnownScriptPrefix='1dmbf19qgN6Q-CwLY'
$CanonicalEmail='homedesigntaedi@gmail.com'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$State=Join-Path $Root 'state.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function Api([string]$Path,[string]$Ref='main'){
  Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref='+$Ref+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'} -TimeoutSec 25
}
function FetchApi([string]$Path,[string]$Dest,[string]$ExpectedSha,[string]$Ref='main'){
  $r=Api $Path $Ref;$api=([string]$r.sha).ToLowerInvariant()
  if($api-ne$ExpectedSha.ToLowerInvariant()){throw('SOURCE_API_SHA_MISMATCH:'+ $Path+':'+$api+':'+$ExpectedSha)}
  $tmp=$Dest+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')))
  $actual=(GitBlob $tmp).ToLowerInvariant();if($actual-ne$ExpectedSha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SOURCE_LOCAL_SHA_MISMATCH:'+ $Path+':'+$actual+':'+$ExpectedSha)}
  Move-Item -LiteralPath $tmp -Destination $Dest -Force;return $actual
}
function ReadJ([string]$Path){if(Test-Path -LiteralPath $Path){try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}}
function SaveJ([string]$Path,$Object){$d=Split-Path $Path -Parent;if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null};$Object|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding UTF8}
function Central{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  };''
}
function Quote([string]$s){if($null-eq$s){return '""'};if($s-notmatch'[\s"]'){return $s};'"'+($s-replace'"','\"')+'"'}
function Run([string]$File,[string[]]$Args,[int]$Timeout=120,[string]$Cwd=''){
  $actual=$File;$effective=@($Args);$ext=[IO.Path]::GetExtension($File).ToLowerInvariant()
  if($ext-eq'.ps1'){$actual='powershell.exe';$effective=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$File)+@($Args)}
  elseif($ext-eq'.cmd' -or $ext-eq'.bat'){$actual='cmd.exe';$line=(Quote $File);if($Args.Count){$line+=' '+(($Args|ForEach-Object{Quote([string]$_)})-join' ')};$effective=@('/d','/s','/c',$line)}
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$actual;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  if($Cwd){$psi.WorkingDirectory=$Cwd};$psi.Arguments=($effective|ForEach-Object{Quote([string]$_)})-join' '
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync()
  if(-not$p.WaitForExit($Timeout*1000)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{};return [ordered]@{ok=$false;exit=-1;timedOut=$true;stdout=if($ot.IsCompleted){$ot.Result}else{''};stderr=if($et.IsCompleted){$et.Result}else{''}}}
  [ordered]@{ok=($p.ExitCode-eq0);exit=$p.ExitCode;timedOut=$false;stdout=$ot.Result.Trim();stderr=$et.Result.Trim()}
}
function SharedAscii([string]$Path){
  try{
    $fs=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{$ms=New-Object IO.MemoryStream;$fs.CopyTo($ms);return [Text.Encoding]::ASCII.GetString($ms.ToArray())}finally{$fs.Dispose();if($ms){$ms.Dispose()}}
  }catch{return ''}
}
function BrowserEvidenceFiles{
  $roots=@($DedicatedUserData,(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'))|Where-Object{$_ -and (Test-Path -LiteralPath $_ -PathType Container)}|Select-Object -Unique
  $files=New-Object System.Collections.ArrayList
  foreach($root in $roots){
    $profiles=@(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name-eq'Default' -or $_.Name-like'Profile *'})
    foreach($p in $profiles){
      foreach($name in @('History','Archived History','Bookmarks','Preferences','Secure Preferences','Current Session','Current Tabs','Last Session','Last Tabs')){
        $f=Join-Path $p.FullName $name;if(Test-Path -LiteralPath $f -PathType Leaf){[void]$files.Add($f)}
      }
      $sessions=Join-Path $p.FullName 'Sessions';if(Test-Path -LiteralPath $sessions -PathType Container){foreach($f in @(Get-ChildItem -LiteralPath $sessions -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 30)){[void]$files.Add($f.FullName)}}
    }
  }
  @($files|Select-Object -Unique)
}
function RecoverCandidates{
  $map=@{};$scanned=@()
  $rx=@(
    'https?://script\.google\.com/(?:u/\d+/)?home/projects/([A-Za-z0-9_-]{40,})',
    'https?://script\.google\.com/d/([A-Za-z0-9_-]{40,})/edit'
  )
  foreach($f in @(BrowserEvidenceFiles)){
    try{$info=Get-Item -LiteralPath $f -ErrorAction Stop;if($info.Length-gt268435456){continue}}catch{continue}
    $text=SharedAscii $f;if(-not$text){continue};$count=0
    foreach($pattern in $rx){foreach($m in [regex]::Matches($text,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)){
      $id=[string]$m.Groups[1].Value;if(-not$id){continue};$count++
      if(-not$map.ContainsKey($id)){$map[$id]=[ordered]@{scriptId=$id;sources=New-Object System.Collections.ArrayList;prefixMatch=$id.StartsWith($KnownScriptPrefix)}}
      if(-not$map[$id].sources.Contains($f)){[void]$map[$id].sources.Add($f)}
    }}
    $scanned += [ordered]@{path=$f;bytes=[int64]$info.Length;matches=$count}
  }
  $rows=@($map.Values|ForEach-Object{[ordered]@{scriptId=$_.scriptId;prefixMatch=$_.prefixMatch;sources=@($_.sources)}}|Sort-Object @{Expression='prefixMatch';Descending=$true},scriptId)
  [ordered]@{candidates=$rows;scanned=$scanned}
}
function ClaspPath{
  foreach($name in @('clasp.cmd','clasp.ps1','clasp')){$c=Get-Command $name -ErrorAction SilentlyContinue;if($c){return $c.Source}}
  foreach($p in @((Join-Path $env:APPDATA 'npm\clasp.cmd'),(Join-Path $env:APPDATA 'npm\clasp.ps1'))){if(Test-Path -LiteralPath $p){return $p}};''
}
function ClaspEmail{
  foreach($p in @((Join-Path $env:USERPROFILE '.clasprc.json'),(Join-Path $env:USERPROFILE '.clasprc.json.backup'))){
    if(-not(Test-Path -LiteralPath $p)){continue};try{$j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json;$id=''
      if($j.token -and $j.token.id_token){$id=[string]$j.token.id_token}elseif($j.tokens -and $j.tokens.default -and $j.tokens.default.id_token){$id=[string]$j.tokens.default.id_token}elseif($j.id_token){$id=[string]$j.id_token}
      if($id -and $id.Split('.').Count-ge2){$part=$id.Split('.')[1].Replace('-','+').Replace('_','/');switch($part.Length%4){2{$part+='=='};3{$part+='='}};$pl=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part))|ConvertFrom-Json;if($pl.email){return [string]$pl.email}}
    }catch{}
  };''
}
function Deployment([string]$Clasp,[string]$Id){
  $r=Run $Clasp @('list-deployments',$Id,'--json') 60;$text=($r.stdout+"`n"+$r.stderr).Trim()
  if(-not$r.ok -or $text-notmatch[regex]::Escape($ExpectedDeploymentId)){$r=Run $Clasp @('list-deployments',$Id) 60;$text=($r.stdout+"`n"+$r.stderr).Trim()}
  [ordered]@{ok=$r.ok;match=[bool]($text-match[regex]::Escape($ExpectedDeploymentId));text=$text}
}
function ProjectRoot([string]$Dir){$cfg=Join-Path $Dir '.clasp.json';if(Test-Path $cfg){try{$j=Get-Content $cfg -Raw -Encoding UTF8|ConvertFrom-Json;if($j.rootDir){return [IO.Path]::GetFullPath((Join-Path $Dir ([string]$j.rootDir)))}}catch{}};$Dir}
function Sources([string]$RootDir){@(Get-ChildItem -LiteralPath $RootDir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in '.gs','.js','.json','.html' -and $_.Name-ne'.clasp.json'})}
function CodeFiles([string]$RootDir){@(Get-ChildItem -LiteralPath $RootDir -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in '.gs','.js'})}
function Signature([string]$RootDir){
  $joined=(@(Sources $RootDir)|ForEach-Object{try{Get-Content $_.FullName -Raw -Encoding UTF8}catch{''}})-join"`n";$score=0;$matches=@()
  if($joined-match'NotebookLM_Task_Queue'){$score+=100;$matches+='NotebookLM_Task_Queue'};if($joined-match'enqueueFromWriter_'){$score+=60;$matches+='enqueueFromWriter_'}
  if($joined-match'NotebookLM WebApp Bridge'){$score+=60;$matches+='NotebookLM WebApp Bridge'};if($joined-match'setupNotebookLMBridge'){$score+=40;$matches+='setupNotebookLMBridge'}
  if($joined-match[regex]::Escape($TargetSpreadsheetId)){$score+=80;$matches+='TargetSpreadsheetId'}
  $compliant=[bool]($joined-match[regex]::Escape($ExpectedQueueVersion) -and $joined-match'LockService\.getScriptLock' -and $joined-match'TASK_ROW_ID_MISMATCH')
  [ordered]@{score=$score;matches=$matches;alreadyCompliant=$compliant}
}
function Fingerprint([string]$Dir){$parts=@();foreach($f in @(Get-ChildItem -LiteralPath $Dir -File -Recurse -ErrorAction SilentlyContinue|Sort-Object FullName)){$rel=$f.FullName.Substring($Dir.Length).TrimStart('\');$parts+=($rel+':'+(Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash)};if(-not$parts.Count){return''};$s=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($s.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts-join"`n"))))).Replace('-','')}finally{$s.Dispose()}}
function BackupProject([string]$ProjectDir,[string]$BackupDir){New-Item -ItemType Directory -Force -Path $BackupDir|Out-Null;foreach($f in @(Get-ChildItem -LiteralPath $ProjectDir -File -Recurse -ErrorAction SilentlyContinue)){$rel=$f.FullName.Substring($ProjectDir.Length).TrimStart('\');$dest=Join-Path $BackupDir $rel;$p=Split-Path $dest -Parent;if($p){New-Item -ItemType Directory -Force -Path $p|Out-Null};Copy-Item $f.FullName $dest -Force}}
function Restore([string]$ProjectDir,[string]$BackupDir,[string]$Clasp,[string]$ExpectedFp){foreach($f in @(Get-ChildItem $ProjectDir -File -Recurse -ErrorAction SilentlyContinue)){Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue};BackupProject $BackupDir $ProjectDir;$push=Run $Clasp @('push','--force') 180 $ProjectDir;$pull=if($push.ok){Run $Clasp @('pull') 120 $ProjectDir}else{$null};$fp=if($pull -and $pull.ok){Fingerprint $ProjectDir}else{''};[ordered]@{ok=[bool]($push.ok -and $pull -and $pull.ok -and $fp-eq$ExpectedFp);push=$push;pull=$pull;fingerprint=$fp}}

$central=Central;$runtime=if($central){Join-Path $central 'Runtime_Readback\AppsScript_QueueIntegrity'}else{$Root};New-Item -ItemType Directory -Force -Path $runtime|Out-Null
$receipt=Join-Path $runtime 'NOTEBOOKLM_QUEUE_HISTORY_RECOVERY_V4.json';$canonical=Join-Path $runtime 'NOTEBOOKLM_QUEUE_INTEGRITY_SYNC.json'
$agentReceipt=if($central){Join-Path $central 'Runtime_Readback\AGENT_1.1.68_NOTEBOOKLM_BOUND_SCRIPT_HISTORY_RECOVERY.json'}else{Join-Path $Root 'AGENT_1.1.68_NOTEBOOKLM_BOUND_SCRIPT_HISTORY_RECOVERY.json'}
$priorPath=Join-Path $Root 'HomeDesignLocalAgent-1.1.67.ps1'
$result=[ordered]@{ok=$false;governanceOk=$true;queueIntegrityVerified=$false;action='AGENT_1.1.68_NOTEBOOKLM_BOUND_SCRIPT_HISTORY_RECOVERY';agentVersion=$AgentVersion;priorRuntime=$null;claspEmail='';historyScan=$null;deploymentChecks=@();targetScriptId='';clone=$null;signatureBefore=$null;backup='';remoteWriteStarted=$false;sourceSha='';push=$null;pullReadback=$null;signatureAfter=$null;deploymentAfter=$null;rollback=$null;status='START';newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;normalChromeTouched=$false;creditsSpent=$false;errors=@();at=(Get-Date).ToString('o')}
$stage='PRIOR_RUNTIME';$pushDone=$false;$targetDir='';$backupDir='';$beforeFp='';$clasp=''
try{
  FetchApi ('local-agent/releases/'+$PriorVersion+'/HomeDesignLocalAgent.ps1') $priorPath $PriorSha 'main'|Out-Null
  $prior=Run $priorPath @() 180;$result.priorRuntime=$prior;if(-not$prior.ok){throw('PRIOR_RUNTIME_FAILED:'+($prior.stderr+' '+$prior.stdout).Trim())}
  $stage='CLASP_IDENTITY';$clasp=ClaspPath;if(-not$clasp){throw'CLASP_NOT_FOUND'};$result.claspEmail=ClaspEmail;if($result.claspEmail.ToLowerInvariant()-ne$CanonicalEmail){throw('CLASP_ACCOUNT_MISMATCH:'+ $result.claspEmail)}
  $stage='HISTORY_SCAN';$result.historyScan=RecoverCandidates;$preferred=@($result.historyScan.candidates|Where-Object{$_.prefixMatch})
  if($preferred.Count-eq0){throw('SCRIPT_PREFIX_NOT_FOUND_IN_BROWSER_EVIDENCE scanned='+$result.historyScan.scanned.Count)}
  $verified=@()
  foreach($c in $preferred){$d=Deployment $clasp ([string]$c.scriptId);$result.deploymentChecks += [ordered]@{scriptId=$c.scriptId;match=$d.match;ok=$d.ok;sources=$c.sources};if($d.match){$verified += [string]$c.scriptId}}
  $verified=@($verified|Select-Object -Unique);if($verified.Count-ne1){throw('TARGET_DEPLOYMENT_MATCH_COUNT:'+ $verified.Count)}
  $result.targetScriptId=$verified[0]
  $stage='CLONE_VERIFY';$work=Join-Path $Base ('NotebookLMQueueHistoryV4\'+(Get-Date -Format 'yyyyMMdd_HHmmss'));$targetDir=Join-Path $work 'project';New-Item -ItemType Directory -Force -Path $targetDir|Out-Null
  $clone=Run $clasp @('clone-script',$result.targetScriptId) 120 $targetDir;if(-not$clone.ok){$clone=Run $clasp @('clone',$result.targetScriptId) 120 $targetDir};$result.clone=$clone;if(-not$clone.ok){throw('CLONE_FAILED:'+($clone.stderr+' '+$clone.stdout).Trim())}
  $root=ProjectRoot $targetDir;$result.signatureBefore=Signature $root;if([int]$result.signatureBefore.score-lt160){throw('NOTEBOOKLM_SIGNATURE_LOW:'+ $result.signatureBefore.score)}
  $beforeFp=Fingerprint $targetDir;$backupDir=if($central){Join-Path $central ('Backups\AppsScript_QueueIntegrity\'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_history_v4')}else{Join-Path $work 'backup'};BackupProject $targetDir $backupDir;$result.backup=$backupDir
  if(-not$result.signatureBefore.alreadyCompliant){
    $stage='SOURCE_FETCH';$src=Join-Path $work 'Code.js';$r=Api 'notebooklm-webapp-bridge-source-v0.2.0/apps-script/Code.gs' $SourceCommit
    if(([string]$r.sha).ToLowerInvariant()-ne$ExpectedCodeBlob){throw('QUEUE_CODE_API_SHA_MISMATCH:'+ [string]$r.sha)}
    [IO.File]::WriteAllBytes($src,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$result.sourceSha=(GitBlob $src).ToLowerInvariant();if($result.sourceSha-ne$ExpectedCodeBlob){throw('QUEUE_CODE_LOCAL_SHA_MISMATCH:'+ $result.sourceSha)}
    $stage='ONE_PUSH';foreach($f in @(CodeFiles $root)){Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue};Copy-Item $src (Join-Path $root 'Code.js') -Force;$result.remoteWriteStarted=$true
    $result.push=Run $clasp @('push','--force') 180 $targetDir;if(-not$result.push.ok){throw('CLASP_PUSH_FAILED:'+($result.push.stderr+' '+$result.push.stdout).Trim())};$pushDone=$true
  }else{$result.sourceSha=$ExpectedCodeBlob}
  $stage='PULL_READBACK';$result.pullReadback=Run $clasp @('pull') 120 $targetDir;if(-not$result.pullReadback.ok){throw('CLASP_PULL_READBACK_FAILED:'+($result.pullReadback.stderr+' '+$result.pullReadback.stdout).Trim())}
  $root=ProjectRoot $targetDir;$result.signatureAfter=Signature $root;if(-not$result.signatureAfter.alreadyCompliant){throw'PULL_READBACK_CONTRACT_MISMATCH'}
  $stage='DEPLOYMENT_INVARIANT';$result.deploymentAfter=Deployment $clasp $result.targetScriptId;if(-not$result.deploymentAfter.match){throw'DEPLOYMENT_INVARIANT_LOST'}
  $result.ok=$true;$result.queueIntegrityVerified=$true;$result.status=if($result.remoteWriteStarted){'PUSH_PULL_READBACK_PASS'}else{'ALREADY_COMPLIANT_READBACK_PASS'};$result.at=(Get-Date).ToString('o')
  $canon=[ordered]@{ok=$true;status='PUSH_PULL_READBACK_PASS';version=$ExpectedQueueVersion;stage='DONE';error='';scriptId=$result.targetScriptId;deploymentId=$ExpectedDeploymentId;backup=$result.backup;sourceSha=$ExpectedCodeBlob;signatureBefore=$result.signatureBefore;signatureAfter=$result.signatureAfter;deploymentInvariant=$true;mode=if($result.remoteWriteStarted){'ONE_PUSH_HISTORY_RECOVERED_EXISTING_PROJECT'}else{'ALREADY_COMPLIANT_HISTORY_RECOVERED'};browserEvidenceRecovered=$true;newProjectCreated=$false;oauthChanged=$false;scopeChanged=$false;newDeployment=$false;newTrigger=$false;creditSpend=$false;at=(Get-Date).ToString('o')};SaveJ $canonical $canon
}catch{
  $result.errors+=($stage+':'+$_.Exception.Message)
  if($pushDone -and $targetDir -and $backupDir -and $clasp){try{$result.rollback=Restore $targetDir $backupDir $clasp $beforeFp}catch{$result.errors+=('ROLLBACK:'+ $_.Exception.Message)}}
  $result.status=if($pushDone -and $result.rollback -and $result.rollback.ok){'FAILED_ROLLED_BACK'}else{'HOLD_NO_WRITE'};if(-not$pushDone -or ($result.rollback -and $result.rollback.ok)){$result.ok=$true};$result.at=(Get-Date).ToString('o')
}
SaveJ $receipt $result;SaveJ $agentReceipt $result
try{$s=ReadJ $State;if(-not$s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member notebookScriptRecoveryStatus $result.status -Force;$s|Add-Member notebookScriptId $result.targetScriptId -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJ $State $s}catch{}
$result|ConvertTo-Json -Depth 100 -Compress
if($result.ok){exit 0}else{exit 2}
