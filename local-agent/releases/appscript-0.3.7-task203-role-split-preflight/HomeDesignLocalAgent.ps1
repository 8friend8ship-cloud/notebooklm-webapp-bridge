param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.7-task203-role-split-preflight'
$WebAppScriptId='1XzludErvxZ3px6qf1aLNU4LZWVU9NqJXYzSrnOm0HoDjUR9XN8flhSir'
$FactoryScriptId='14OHCqUDMAgpqB6JvPw_XQfFH8NlIUlVUK163RrFH1Drz3HxIc53B4IL2'
$TargetDeployment='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$CanonicalEmail='homedesigntaedi@gmail.com'
$ExpectedWebAppHeadSha256='afe09428756cb3269fa21d4b6567e99cb322b3c39def243adadd3c68c8a0e7b9'
$ExpectedFactoryHeadSha256='a2e0b3014c8289b8e25687adb32da099710b72ec0a5e5161533f8f97ee6016a0'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_TASK203_ROLE_SPLIT_PREFLIGHT_0.3.7.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 100;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function ClaspPath{foreach($name in @('clasp.cmd','clasp.ps1','clasp')){$c=Get-Command $name -ErrorAction SilentlyContinue;if($c){return $c.Source}};foreach($p in @((Join-Path $env:APPDATA 'npm\clasp.cmd'),(Join-Path $env:APPDATA 'npm\clasp.ps1'))){if(Test-Path -LiteralPath $p){return $p}};''}
function RunProc([string]$File,[string[]]$Args,[int]$TimeoutSec=120,[string]$Cwd=''){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$File;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;if($Cwd){$psi.WorkingDirectory=$Cwd};$psi.Arguments=(($Args|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ');$p=[Diagnostics.Process]::Start($psi);if(-not$p.WaitForExit($TimeoutSec*1000)){try{$p.Kill()}catch{};return [ordered]@{ok=$false;exit=124;stdout='';stderr='TIMEOUT'}};[ordered]@{ok=($p.ExitCode-eq0);exit=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd();stderr=$p.StandardError.ReadToEnd()}}
function RunClasp([string]$Clasp,[string[]]$ClaspArgs,[int]$TimeoutSec=90,[string]$Cwd=''){$psi=New-Object Diagnostics.ProcessStartInfo;$ext=[IO.Path]::GetExtension($Clasp).ToLowerInvariant();if($ext-eq'.cmd'){$psi.FileName=$env:ComSpec;$psi.Arguments='/d /s /c ""'+$Clasp+'" '+(($ClaspArgs|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')+'"'}elseif($ext-eq'.ps1'){$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Clasp+'" '+(($ClaspArgs|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')}else{$psi.FileName=$Clasp;$psi.Arguments=(($ClaspArgs|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')};$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;if($Cwd){$psi.WorkingDirectory=$Cwd};$p=[Diagnostics.Process]::Start($psi);if(-not$p.WaitForExit($TimeoutSec*1000)){try{$p.Kill()}catch{};return [ordered]@{ok=$false;exit=124;stdout='';stderr='TIMEOUT'}};[ordered]@{ok=($p.ExitCode-eq0);exit=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd();stderr=$p.StandardError.ReadToEnd()}}
function Sha256Bytes([byte[]]$Bytes){$s=[Security.Cryptography.SHA256]::Create();try{return (($s.ComputeHash($Bytes)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function NamesFromText([string]$Text){
  $f=New-Object System.Collections.Generic.HashSet[string];$v=New-Object System.Collections.Generic.HashSet[string]
  foreach($m in [regex]::Matches($Text,'(?m)\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(')){[void]$f.Add([string]$m.Groups[1].Value)}
  foreach($m in [regex]::Matches($Text,'(?m)^\s*(?:var|let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*function\s*\(')){[void]$f.Add([string]$m.Groups[1].Value)}
  foreach($m in [regex]::Matches($Text,'(?m)^\s*(?:var|let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)\b')){[void]$v.Add([string]$m.Groups[1].Value)}
  [ordered]@{functions=@($f|Sort-Object);variables=@($v|Sort-Object)}
}
function InspectDir([string]$Dir){
  $files=@();$funcs=New-Object System.Collections.Generic.HashSet[string];$vars=New-Object System.Collections.Generic.HashSet[string];$aggregateParts=@()
  foreach($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue|Sort-Object FullName)){
    $rel=$f.FullName.Substring($Dir.Length).TrimStart('\');$bytes=[IO.File]::ReadAllBytes($f.FullName);$sha=Sha256Bytes $bytes;$aggregateParts+=($rel+'|'+$f.Length+'|'+$sha)
    if($f.Length-lt4194304){try{$txt=[Text.Encoding]::UTF8.GetString($bytes);$n=NamesFromText $txt;foreach($x in $n.functions){[void]$funcs.Add($x)};foreach($x in $n.variables){[void]$vars.Add($x)}}catch{}}
    $files+=,[ordered]@{path=$rel;bytes=[int64]$f.Length;sha256=$sha}
  }
  [ordered]@{fileCount=$files.Count;aggregateSha256=(Sha256Bytes ([Text.Encoding]::UTF8.GetBytes(($aggregateParts-join "`n"))));files=$files;functions=@($funcs|Sort-Object);variables=@($vars|Sort-Object)}
}
function CloneInspect([string]$Clasp,[string]$ScriptId,[string]$Label){$dir=Join-Path $env:TEMP ('task203-role-'+$Label+'-'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'));New-Item -ItemType Directory -Force -Path $dir|Out-Null;$c=RunClasp $Clasp @('clone-script',$ScriptId) 150 $dir;if(-not$c.ok){throw('CLONE_'+$Label+'_FAIL exit='+$c.exit+' err='+$c.stderr)};$i=InspectDir $dir;[ordered]@{scriptId=$ScriptId;directory=$dir;fileCount=$i.fileCount;aggregateSha256=$i.aggregateSha256;functions=$i.functions;variables=$i.variables;files=$i.files}}
function Intersect([object[]]$A,[object[]]$B){$h=@{};foreach($x in @($A)){$h[[string]$x]=1};@($B|Where-Object{$h.ContainsKey([string]$_)}|Sort-Object -Unique)}
function InspectSource([string]$Path,[string]$Name,[string]$Origin,[string]$ExpectedRole,[object[]]$WebFuncs,[object[]]$FactoryFuncs,[object[]]$WebVars,[object[]]$FactoryVars){
  if(-not(Test-Path -LiteralPath $Path)){return [ordered]@{name=$Name;origin=$Origin;expectedRole=$ExpectedRole;missing=$true}}
  $bytes=[IO.File]::ReadAllBytes($Path);$txt=[Text.Encoding]::UTF8.GetString($bytes);$n=NamesFromText $txt;$funcs=@($n.functions);$vars=@($n.variables)
  $webSignals=@($funcs|Where-Object{$_-match'(?i)(doGet|doPost|Web|HandleGet|HandlePost|JsonStore|DriveStore|Api)'});$factorySignals=@($funcs|Where-Object{$_-match'(?i)(Factory|Scheduler|Scheduled|Tick|Wake|Queue|Librarian|Crosscheck|Audit|Autofix|Governor|Repair|Worker|Pipeline)'});
  $webScore=$webSignals.Count;$factoryScore=$factorySignals.Count;$heuristic=if($webScore-gt0-and$factoryScore-eq0){'WEBAPP'}elseif($factoryScore-gt0-and$webScore-eq0){'FACTORY'}elseif($factoryScore-gt0-and$webScore-gt0){'MIXED_REVIEW'}else{'SHARED_REVIEW'}
  $definesDoPost=($funcs-contains'doPost');$definesDoGet=($funcs-contains'doGet');$triggerTokens=@();foreach($t in @('ScriptApp.newTrigger','ScriptApp.getProjectTriggers','ScriptApp.deleteTrigger','newTrigger(')){if($txt.Contains($t)){$triggerTokens+=$t}}
  [ordered]@{name=$Name;origin=$Origin;expectedRole=$ExpectedRole;missing=$false;bytes=[int64]$bytes.Length;sha256=(Sha256Bytes $bytes);functions=$funcs;variables=$vars;heuristicRole=$heuristic;webSignals=$webSignals;factorySignals=$factorySignals;definesDoGet=$definesDoGet;definesDoPost=$definesDoPost;triggerMutationTokens=@($triggerTokens|Sort-Object -Unique);webFunctionCollisions=(Intersect $WebFuncs $funcs);factoryFunctionCollisions=(Intersect $FactoryFuncs $funcs);webVariableCollisions=(Intersect $WebVars $vars);factoryVariableCollisions=(Intersect $FactoryVars $vars);entrypointCollisionRisk=($definesDoGet-or$definesDoPost)}
}

$r=[ordered]@{ok=$false;action='READONLY_TASK203_ROLE_SPLIT_PREFLIGHT';version=$Version;authorizedUserOk=$false;webAppScriptId=$WebAppScriptId;factoryScriptId=$FactoryScriptId;targetDeployment=$TargetDeployment;baselineWebAppExpected=$ExpectedWebAppHeadSha256;baselineFactoryExpected=$ExpectedFactoryHeadSha256;webAppHead=$null;factoryHead=$null;baselineUnchanged=$false;sourceCount=0;sources=@();duplicateSourceFunctions=@();duplicateSourceVariables=@();ambiguousSources=@();entrypointCollisionSources=@();triggerTokenSources=@();safeToPush=$false;nextGate='ROLE_PLAN_REVIEW_REQUIRED_BEFORE_ANY_WRITE';stage='START';error='';readOnly=$true;pushPerformed=$false;newProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;normalChromeTouched=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $clasp=ClaspPath;if(-not$clasp){throw'CLASP_NOT_FOUND'};$auth=RunClasp $clasp @('show-authorized-user','--json') 45;$r.authorizedUserOk=($auth.ok-and(($auth.stdout+$auth.stderr).ToLowerInvariant().Contains($CanonicalEmail)));if(-not$r.authorizedUserOk){throw'EXISTING_CLASP_AUTH_NOT_AVAILABLE'}
  $r.stage='CLONE_CURRENT_TARGETS';$r.webAppHead=CloneInspect $clasp $WebAppScriptId 'webapp';$r.factoryHead=CloneInspect $clasp $FactoryScriptId 'factory';$r.baselineUnchanged=(([string]$r.webAppHead.aggregateSha256-eq$ExpectedWebAppHeadSha256)-and([string]$r.factoryHead.aggregateSha256-eq$ExpectedFactoryHeadSha256));if(-not$r.baselineUnchanged){throw('BASELINE_DRIFT_ABORT web='+$r.webAppHead.aggregateSha256+' factory='+$r.factoryHead.aggregateSha256)}
  $git=(Get-Command git.exe -ErrorAction SilentlyContinue);if(-not$git){$git=(Get-Command git -ErrorAction SilentlyContinue)};if(-not$git){throw'GIT_NOT_FOUND'};$work=Join-Path $env:TEMP ('task203-role-sources-'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'));$an=Join-Path $work 'Analyzer';$su=Join-Path $work 'Support';New-Item -ItemType Directory -Force -Path $work|Out-Null
  $r.stage='CLONE_CANONICAL_SOURCES';$g1=RunProc $git.Source @('clone','--quiet','--depth','1','--branch','main','https://github.com/8friend8ship-cloud/Analyzer-12.09.git',$an) 180;if(-not$g1.ok){throw('ANALYZER_CLONE_FAIL '+$g1.stderr)};$g2=RunProc $git.Source @('clone','--quiet','--depth','1','--branch','main','https://github.com/8friend8ship-cloud/contents-os-git.git',$su) 180;if(-not$g2.ok){throw('SUPPORT_CLONE_FAIL '+$g2.stderr)}
  $specs=@(
    [ordered]@{name='ContentOS_Drive_JSON_Cache_V3';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ContentOS_Drive_JSON_Cache_V3.gs');expected='WEBAPP_CANDIDATE'},
    [ordered]@{name='ContentOS_Runtime_Registry_V3';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ContentOS_Runtime_Registry_V3.gs');expected='WEBAPP_CANDIDATE'},
    [ordered]@{name='ContentOS_Free_Backdata_Pipeline';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ContentOS_Free_Backdata_Pipeline.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='ContentOS_Unified_Scheduler';origin='contents-os-git';path=(Join-Path $su 'apps-script/ContentOS_Unified_Scheduler.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='ContentOS_Unified_Scheduler_V13_Overlay_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ContentOS_Unified_Scheduler_V13_Overlay_20260902.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='Central_Image_Queens_Seed_AutoLearn_V2';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/Central_Image_Queens_Seed_AutoLearn_V2.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='ContentOS_Image_Learning_Web_Adapter_V2';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ContentOS_Image_Learning_Web_Adapter_V2.gs');expected='WEBAPP_CANDIDATE'},
    [ordered]@{name='ImageSupply_Governor_V1';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ImageSupply_Governor_V1.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='ImageSupply_Governor_PrePost_V2';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ImageSupply_Governor_PrePost_V2.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='Central_Sheet_Runtime_Audit_Autofix_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/Central_Sheet_Runtime_Audit_Autofix_20260902.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='Central_Librarian_Knowledge_Automation';origin='contents-os-git';path=(Join-Path $su 'apps-script/Central_Librarian_Knowledge_Automation.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='ContentOS_DryWriter_Runtime_Config_Repair_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/ContentOS_DryWriter_Runtime_Config_Repair_20260902.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='Central_Workflow_Bridge_Crosscheck_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/Central_Workflow_Bridge_Crosscheck_20260902.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='OpenAI_5_Worker_Runtime_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/OpenAI_5_Worker_Runtime_20260902.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='CentralTabletRemoteDispatcher_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/CentralTabletRemoteDispatcher_20260902.gs');expected='FACTORY_CANDIDATE'},
    [ordered]@{name='Central_Runtime_Strict_X2_20260902';origin='Analyzer-12.09';path=(Join-Path $an 'apps-script/Central_Runtime_Strict_X2_20260902.gs');expected='FACTORY_CANDIDATE'}
  )
  $r.stage='ANALYZE_ROLE_COLLISIONS';$items=@();foreach($s in $specs){$items+=,(InspectSource $s.path $s.name $s.origin $s.expected $r.webAppHead.functions $r.factoryHead.functions $r.webAppHead.variables $r.factoryHead.variables)};$r.sources=$items;$r.sourceCount=$items.Count
  $fm=@{};$vm=@{};foreach($i in $items){if($i.missing){continue};foreach($f in @($i.functions)){if(-not$fm.ContainsKey($f)){$fm[$f]=@()};$fm[$f]+=$i.name};foreach($v in @($i.variables)){if(-not$vm.ContainsKey($v)){$vm[$v]=@()};$vm[$v]+=$i.name}}
  $r.duplicateSourceFunctions=@($fm.Keys|Where-Object{$fm[$_].Count-gt1}|Sort-Object|ForEach-Object{[ordered]@{name=$_;sources=@($fm[$_])}});$r.duplicateSourceVariables=@($vm.Keys|Where-Object{$vm[$_].Count-gt1}|Sort-Object|ForEach-Object{[ordered]@{name=$_;sources=@($vm[$_])}})
  $r.ambiguousSources=@($items|Where-Object{$_.missing-or$_.heuristicRole-in@('MIXED_REVIEW','SHARED_REVIEW')}|ForEach-Object{$_.name});$r.entrypointCollisionSources=@($items|Where-Object{$_.entrypointCollisionRisk}|ForEach-Object{$_.name});$r.triggerTokenSources=@($items|Where-Object{@($_.triggerMutationTokens).Count-gt0}|ForEach-Object{[ordered]@{name=$_.name;tokens=$_.triggerMutationTokens}})
  $r.ok=(@($items|Where-Object{$_.missing}).Count-eq0);$r.stage=if($r.ok){'DONE_READONLY_ROLE_REPORT'}else{'DONE_WITH_MISSING_SOURCE'}
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 100 -Compress
if($r.ok){exit 0}else{exit 2}
