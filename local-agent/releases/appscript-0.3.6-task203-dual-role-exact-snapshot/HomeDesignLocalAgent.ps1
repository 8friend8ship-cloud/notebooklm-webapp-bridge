param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.6-task203-dual-role-exact-snapshot'
$WebAppScriptId='1XzludErvxZ3px6qf1aLNU4LZWVU9NqJXYzSrnOm0HoDjUR9XN8flhSir'
$FactoryScriptId='14OHCqUDMAgpqB6JvPw_XQfFH8NlIUlVUK163RrFH1Drz3HxIc53B4IL2'
$TargetDeployment='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$ExpectedParentId='1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'
$CanonicalEmail='homedesigntaedi@gmail.com'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_TASK203_DUAL_ROLE_EXACT_SNAPSHOT_0.3.6.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function ClaspPath{foreach($name in @('clasp.cmd','clasp.ps1','clasp')){$c=Get-Command $name -ErrorAction SilentlyContinue;if($c){return $c.Source}};foreach($p in @((Join-Path $env:APPDATA 'npm\clasp.cmd'),(Join-Path $env:APPDATA 'npm\clasp.ps1'))){if(Test-Path -LiteralPath $p){return $p}};''}
function RunClasp([string]$Clasp,[string[]]$ClaspArgs,[int]$TimeoutSec=90,[string]$Cwd=''){$psi=New-Object Diagnostics.ProcessStartInfo;$ext=[IO.Path]::GetExtension($Clasp).ToLowerInvariant();if($ext-eq'.cmd'){$psi.FileName=$env:ComSpec;$psi.Arguments='/d /s /c ""'+$Clasp+'" '+(($ClaspArgs|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')+'"'}elseif($ext-eq'.ps1'){$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Clasp+'" '+(($ClaspArgs|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')}else{$psi.FileName=$Clasp;$psi.Arguments=(($ClaspArgs|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')};$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;if($Cwd){$psi.WorkingDirectory=$Cwd};$p=[Diagnostics.Process]::Start($psi);if(-not$p.WaitForExit($TimeoutSec*1000)){try{$p.Kill()}catch{};return [ordered]@{ok=$false;exit=124;stdout='';stderr='TIMEOUT'}};[ordered]@{ok=($p.ExitCode-eq0);exit=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd();stderr=$p.StandardError.ReadToEnd()}}
function Sha256Bytes([byte[]]$Bytes){$s=[Security.Cryptography.SHA256]::Create();try{return (($s.ComputeHash($Bytes)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function InspectDir([string]$Dir){
  $files=@();$funcs=New-Object System.Collections.Generic.HashSet[string]
  $sig=[ordered]@{processTaskQueue=$false;contentOsUnifiedSchedulerTick=$false;contentOsPipelineTick=$false;runCentralTabletRemoteDispatcherFromFactory=$false;Central_Librarian_Knowledge_Automation=$false;doPost=$false;doGet=$false;spreadsheetApp=$false}
  $parentId='';$title='';$aggregateParts=@()
  foreach($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue|Sort-Object FullName)){
    $rel=$f.FullName.Substring($Dir.Length).TrimStart('\');$bytes=[IO.File]::ReadAllBytes($f.FullName);$sha=Sha256Bytes $bytes
    $e=[ordered]@{path=$rel;extension=$f.Extension;bytes=[int64]$f.Length;sha256=$sha;textRead=$false};$aggregateParts+=($rel+'|'+$f.Length+'|'+$sha)
    if($rel-eq'.clasp.json'){try{$cj=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json;if($cj.parentId){$parentId=[string]$cj.parentId};if($cj.projectId-and-not$parentId){$parentId=[string]$cj.projectId}}catch{}}
    if($f.Length-lt4194304){try{$txt=[Text.Encoding]::UTF8.GetString($bytes);$e.textRead=$true;if($txt-match'processTaskQueue'){$sig.processTaskQueue=$true};if($txt-match'contentOsUnifiedSchedulerTick'){$sig.contentOsUnifiedSchedulerTick=$true};if($txt-match'contentOsPipelineTick'){$sig.contentOsPipelineTick=$true};if($txt-match'runCentralTabletRemoteDispatcherFromFactory'){$sig.runCentralTabletRemoteDispatcherFromFactory=$true};if($txt-match'Central_Librarian_Knowledge_Automation'){$sig.Central_Librarian_Knowledge_Automation=$true};if($txt-match'function\s+doPost\s*\('){$sig.doPost=$true};if($txt-match'function\s+doGet\s*\('){$sig.doGet=$true};if($txt-match'SpreadsheetApp'){$sig.spreadsheetApp=$true};foreach($m in [regex]::Matches($txt,'(?m)\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(')){[void]$funcs.Add([string]$m.Groups[1].Value)}}catch{}}
    $files+=,$e
  }
  $agg=Sha256Bytes ([Text.Encoding]::UTF8.GetBytes(($aggregateParts-join "`n")))
  [ordered]@{fileCount=$files.Count;aggregateSha256=$agg;parentId=$parentId;files=$files;functions=@($funcs|Sort-Object);signatures=$sig}
}
function CloneInspect([string]$Clasp,[string]$ScriptId,[string]$Label,[string]$VersionNumber=''){
  $dir=Join-Path $env:TEMP ('task203-snap-'+$Label+'-'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'));New-Item -ItemType Directory -Force -Path $dir|Out-Null
  if($VersionNumber){$c=RunClasp $Clasp @('clone-script',$ScriptId,$VersionNumber) 150 $dir;$mode='VERSION_'+$VersionNumber}else{$c=RunClasp $Clasp @('clone-script',$ScriptId) 150 $dir;$mode='HEAD'}
  if(-not$c.ok){throw('CLONE_'+$Label+'_FAIL exit='+$c.exit+' err='+$c.stderr)}
  $ins=InspectDir $dir
  [ordered]@{scriptId=$ScriptId;cloneMode=$mode;directory=$dir;fileCount=$ins.fileCount;aggregateSha256=$ins.aggregateSha256;parentId=$ins.parentId;files=$ins.files;functions=$ins.functions;signatures=$ins.signatures}
}

$r=[ordered]@{ok=$false;action='READONLY_TASK203_DUAL_ROLE_EXACT_SNAPSHOT';version=$Version;authorizedUserOk=$false;webAppScriptId=$WebAppScriptId;factoryScriptId=$FactoryScriptId;targetDeployment=$TargetDeployment;expectedParentId=$ExpectedParentId;deploymentList='';deploymentVersion='';webAppDeployed=$null;webAppHead=$null;factoryHead=$null;webAppHeadDriftFromDeployment=$null;factoryParentMatchesExpected=$null;roleGatePass=$false;stage='START';error='';readOnly=$true;pushPerformed=$false;newProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;normalChromeTouched=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $clasp=ClaspPath;if(-not$clasp){throw'CLASP_NOT_FOUND'}
  $auth=RunClasp $clasp @('show-authorized-user','--json') 45;$r.authorizedUserOk=($auth.ok-and(($auth.stdout+$auth.stderr).ToLowerInvariant().Contains($CanonicalEmail)));if(-not$r.authorizedUserOk){throw'EXISTING_CLASP_AUTH_NOT_AVAILABLE'}
  $r.stage='WEBAPP_DEPLOYMENT_RESOLVE';$dep=RunClasp $clasp @('list-deployments',$WebAppScriptId) 60;if(-not$dep.ok){throw('WEBAPP_LIST_DEPLOYMENTS_FAIL '+$dep.stderr)};$r.deploymentList=($dep.stdout+$dep.stderr).Trim();$line=@(($r.deploymentList-split"`r?`n")|Where-Object{$_-match[regex]::Escape($TargetDeployment)}|Select-Object -First 1);if($line.Count-eq0){throw'TARGET_DEPLOYMENT_NOT_FOUND'};$ver='';if([string]$line[0]-match'@(\d+)'){$ver=$Matches[1]};if(-not$ver){throw'DEPLOYMENT_VERSION_UNPARSED'};$r.deploymentVersion=$ver
  $r.stage='SNAPSHOT_WEBAPP_DEPLOYED';$r.webAppDeployed=CloneInspect $clasp $WebAppScriptId 'webapp-deployed' $ver
  $r.stage='SNAPSHOT_WEBAPP_HEAD';$r.webAppHead=CloneInspect $clasp $WebAppScriptId 'webapp-head'
  $r.stage='SNAPSHOT_FACTORY_HEAD';$r.factoryHead=CloneInspect $clasp $FactoryScriptId 'factory-head'
  $r.webAppHeadDriftFromDeployment=([string]$r.webAppHead.aggregateSha256-ne[string]$r.webAppDeployed.aggregateSha256)
  $r.factoryParentMatchesExpected=([string]$r.factoryHead.parentId-eq$ExpectedParentId)
  $r.roleGatePass=([bool]$r.factoryHead.signatures.processTaskQueue-and-not[bool]$r.webAppDeployed.signatures.processTaskQueue-and($WebAppScriptId-ne$FactoryScriptId))
  if(-not$r.roleGatePass){throw'ROLE_GATE_FAILED'}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}
