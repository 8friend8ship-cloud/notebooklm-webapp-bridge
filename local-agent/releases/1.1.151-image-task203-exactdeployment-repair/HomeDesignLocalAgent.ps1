param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.151-image-task203-exactdeployment-repair'
$RepoUrl='https://github.com/8friend8ship-cloud/contents-os-git.git'
$RepairExpectedSha='a0b7bddb37f6c2623a2d56dc3750c02c244aa90a'
$LibrarianExpectedSha='4631330d911dc8b5ae8e92b07a150b7986d1bc7e'
$DeploymentId='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$WebAppUrl='https://script.google.com/macros/s/AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo/exec'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='IMAGE_TASK203_EXACTDEPLOY_REPAIR_LIBRARIAN_1.1.151.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function GitObjectSha([string]$Repo,[string]$Path){Push-Location $Repo;try{$s=(& git rev-parse ('HEAD:'+$Path) 2>&1|Out-String).Trim().ToLowerInvariant();if($LASTEXITCODE-ne0){throw('GIT_OBJECT_SHA_FAILED:'+ $Path)};return $s}finally{Pop-Location}}
function GetDeployments([string]$ScriptId){$t=(& clasp list-deployments $ScriptId 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'CLASP_LIST_DEPLOYMENTS_FAILED'};@([regex]::Matches($t,'AKfy[A-Za-z0-9_-]+')|ForEach-Object{$_.Value}|Sort-Object -Unique)}
function AssertDeployments([string[]]$Before,[string[]]$After){if((@($Before|Sort-Object)-join'|')-ne(@($After|Sort-Object)-join'|')){throw('DEPLOYMENT_SET_CHANGED before='+($Before-join'|')+' after='+($After-join'|'))}}
function ResolveScriptIdByDeployment([string]$ExpectedDeployment){
  $cp=(Get-Command clasp -ErrorAction Stop).Source
  $list=(& $cp list-scripts 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'CLASP_LIST_SCRIPTS_FAILED'}
  $ids=@();foreach($line in ($list-split"`r?`n")){if($line-match'[–—-]\s*([A-Za-z0-9_-]{30,})\s*$'){$ids+=$Matches[1]}}
  if($ids.Count-eq0){$ids=@([regex]::Matches($list,'[A-Za-z0-9_-]{30,}')|ForEach-Object{$_.Value}|Sort-Object -Unique)}else{$ids=@($ids|Sort-Object -Unique)}
  if($ids.Count-eq0){throw 'CLASP_SCRIPT_ID_INVENTORY_EMPTY'}
  $exact=@();$maxParallel=6
  for($offset=0;$offset-lt$ids.Count;$offset+=$maxParallel){
    $last=[Math]::Min($ids.Count-1,$offset+$maxParallel-1);$batch=@($ids[$offset..$last]);$jobs=@()
    foreach($sid in $batch){$jobs+=Start-Job -ScriptBlock {param($ClaspPath,$ScriptId) $txt=(& $ClaspPath list-deployments $ScriptId 2>&1|Out-String);[pscustomobject]@{scriptId=$ScriptId;exitCode=$LASTEXITCODE;text=$txt}} -ArgumentList $cp,$sid}
    $deadline=(Get-Date).AddSeconds(70)
    while((Get-Date)-lt$deadline -and @($jobs|Where-Object{$_.State-in@('Running','NotStarted')}).Count-gt0){Start-Sleep -Milliseconds 500}
    foreach($j in $jobs){
      if($j.State-in@('Running','NotStarted')){Stop-Job $j -ErrorAction SilentlyContinue;Remove-Job $j -Force -ErrorAction SilentlyContinue;continue}
      $o=Receive-Job $j -ErrorAction SilentlyContinue;Remove-Job $j -Force -ErrorAction SilentlyContinue
      if($o -and [int]$o.exitCode-eq0 -and [string]$o.text-match[regex]::Escape($ExpectedDeployment)){$exact+=[string]$o.scriptId}
    }
    $exact=@($exact|Sort-Object -Unique);if($exact.Count-gt1){break}
  }
  if($exact.Count-ne1){throw('SCRIPT_DEPLOYMENT_MATCH_COUNT_'+$exact.Count)}
  return [string]$exact[0]
}
function CloneScript([string]$ScriptId,[string]$Dir){New-Item -ItemType Directory -Force -Path $Dir|Out-Null;Push-Location $Dir;try{& clasp clone-script $ScriptId;if($LASTEXITCODE-ne0){& clasp clone $ScriptId;if($LASTEXITCODE-ne0){throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED'}}}finally{Pop-Location}}
function Layout([string]$Dir){$cfg=Join-Path $Dir '.clasp.json';$root=$Dir;$ext='.gs';if(Test-Path $cfg){$j=Get-Content -LiteralPath $cfg -Raw -Encoding UTF8|ConvertFrom-Json;if($j.rootDir){$root=[IO.Path]::GetFullPath((Join-Path $Dir ([string]$j.rootDir)))}};if(-not(Test-Path $root)){throw 'CLASP_ROOT_DIR_MISSING'};$gs=@(Get-ChildItem $root -Recurse -File -Filter '*.gs' -ErrorAction SilentlyContinue).Count;$js=@(Get-ChildItem $root -Recurse -File -Filter '*.js' -ErrorAction SilentlyContinue).Count;if($js-gt$gs){$ext='.js'};[pscustomobject]@{Root=$root;Ext=$ext}}
function ScriptFiles([string]$RootDir){@(Get-ChildItem $RootDir -Recurse -File -ErrorAction Stop|Where-Object{$_.Extension-in@('.gs','.js')})}
function CountPattern([System.IO.FileInfo[]]$Files,[string]$Pattern){$n=0;foreach($f in $Files){$n+=[regex]::Matches((Get-Content $f.FullName -Raw),$Pattern).Count};$n}
function AddDispatcher([System.IO.FileInfo[]]$Files,[string]$FunctionName,[string]$HandlerName){$pattern='function\s+'+[regex]::Escape($FunctionName)+'\s*\(\s*e\s*\)\s*\{';$hits=@();foreach($f in $Files){if((Get-Content $f.FullName -Raw)-match$pattern){$hits+=$f}};if($hits.Count-ne1){throw($FunctionName.ToUpperInvariant()+'_DEFINITION_COUNT:'+$hits.Count)};$file=$hits[0];$text=Get-Content $file.FullName -Raw;if($text-notmatch([regex]::Escape($HandlerName)+'\s*\(\s*e\s*\)')){$v='centralResponse_'+($HandlerName-replace'[^A-Za-z0-9_]','_');$rep='${0}'+"`r`n  var $v = $HandlerName(e);`r`n  if ($v) return $v;";$text=[regex]::Replace($text,$pattern,$rep,1);Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8}}
function AddLibrarianWake([System.IO.FileInfo[]]$Files){$pattern='function\s+processTaskQueue\s*\(\s*\)\s*\{';$hits=@();foreach($f in $Files){if((Get-Content $f.FullName -Raw)-match$pattern){$hits+=$f}};if($hits.Count-ne1){throw('PROCESSTASKQUEUE_DEFINITION_COUNT:'+$hits.Count)};$file=$hits[0];$text=Get-Content $file.FullName -Raw;if($text-notmatch'runCentralLibrarianKnowledgeIndex15mIfDue_\s*\('){$a="`r`n  try {`r`n    if (typeof runCentralLibrarianKnowledgeIndex15mIfDue_ === 'function') { runCentralLibrarianKnowledgeIndex15mIfDue_(); }`r`n  } catch (centralLibrarianError) {`r`n    console.warn('CENTRAL_LIBRARIAN_DEGRADED', String(centralLibrarianError && centralLibrarianError.message || centralLibrarianError));`r`n  }";$text=[regex]::Replace($text,$pattern,'${0}'+$a,1);Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8}}
function UpdateDeploymentStrict([string]$ProjectDir,[string]$Id,[string]$Description){Push-Location $ProjectDir;try{& clasp update-deployment $Id --description $Description;if($LASTEXITCODE-ne0){throw 'EXISTING_DEPLOYMENT_UPDATE_FAILED_NO_CREATE_FALLBACK'}}finally{Pop-Location}}
function InvokeCentral([string]$Action,$Payload){$pv=@{};if($null-ne$Payload){$pv=$Payload};$b=@{action=$Action;payload=$pv}|ConvertTo-Json -Depth 20;Invoke-RestMethod -Method Post -Uri $WebAppUrl -ContentType 'text/plain;charset=utf-8' -Body $b -TimeoutSec 90}

$r=[ordered]@{ok=$false;action='TASK203_EXACT_DEPLOYMENT_REPAIR_PLUS_LIBRARIAN';version=$Version;privateCloneOk=$false;repairPatched=$false;repairExit=$null;repairOutput='';scriptId='';deploymentBefore=@();deploymentAfter=@();librarianSourceReadback=$false;dispatcherReadback=$false;wakeReadback=$false;audit=$null;preflight1=$null;preflight2=$null;tick=$null;stage='START';error='';rollbackAttempted=$false;rollbackOk=$false;duplicateTaskCreated=$false;newAppsScriptProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
$libPushed=$false;$snapshot='';$scriptId='';$deployBefore=@();$verify=''
try{
  if(-not(Get-Command git -ErrorAction SilentlyContinue)){throw 'GIT_COMMAND_NOT_FOUND'};if(-not(Get-Command clasp -ErrorAction SilentlyContinue)){throw 'CLASP_COMMAND_NOT_FOUND_EXISTING_RUNNER_PATH_REQUIRED'}
  $auth=(& clasp show-authorized-user --json 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'}
  $work=Join-Path $env:TEMP ('task203-exactdeploy-'+(Get-Date -Format 'yyyyMMdd_HHmmss'));$repo=Join-Path $work 'repo';New-Item -ItemType Directory -Force -Path $work|Out-Null
  $r.stage='PRIVATE_GIT_CLONE_EXISTING_CREDENTIALS';$oldPrompt=$env:GIT_TERMINAL_PROMPT;$env:GIT_TERMINAL_PROMPT='0';try{& git clone --quiet --depth 1 --branch main $RepoUrl $repo;if($LASTEXITCODE-ne0){throw 'PRIVATE_GIT_CLONE_AUTH_OR_NETWORK_FAILED'}}finally{$env:GIT_TERMINAL_PROMPT=$oldPrompt};$r.privateCloneOk=$true
  $repair=Join-Path $repo 'tools\Repair-ContentOS-DriveCacheAppsScript.ps1';$lib=Join-Path $repo 'apps-script\Central_Librarian_Knowledge_Automation.gs';if(-not(Test-Path $repair)){throw 'REPAIR_SOURCE_MISSING'};if(-not(Test-Path $lib)){throw 'LIBRARIAN_SOURCE_MISSING'}
  if((GitObjectSha $repo 'tools/Repair-ContentOS-DriveCacheAppsScript.ps1')-ne$RepairExpectedSha){throw 'REPAIR_GIT_OBJECT_SHA_MISMATCH'};if((GitObjectSha $repo 'apps-script/Central_Librarian_Knowledge_Automation.gs')-ne$LibrarianExpectedSha){throw 'LIBRARIAN_GIT_OBJECT_SHA_MISMATCH'}
  $resolver=@'
function Resolve-ScriptIdByDeployment([string]$ExpectedDeploymentId) {
  $cp=(Get-Command clasp -ErrorAction Stop).Source
  $list=(& $cp list-scripts 2>&1 | Out-String); if($LASTEXITCODE -ne 0){throw 'CLASP_LIST_SCRIPTS_FAILED'}
  $ids=@(); foreach($line in ($list -split "`r?`n")){ if($line -match '[–—-]\s*([A-Za-z0-9_-]{30,})\s*$'){ $ids += $Matches[1] } }
  if($ids.Count -eq 0){$ids=@([regex]::Matches($list,'[A-Za-z0-9_-]{30,}')|ForEach-Object{$_.Value}|Sort-Object -Unique)} else {$ids=@($ids|Sort-Object -Unique)}
  $exact=@(); $maxParallel=6
  for($offset=0;$offset -lt $ids.Count;$offset+=$maxParallel){
    $last=[Math]::Min($ids.Count-1,$offset+$maxParallel-1); $batch=@($ids[$offset..$last]); $jobs=@()
    foreach($sid in $batch){$jobs+=Start-Job -ScriptBlock {param($ClaspPath,$ScriptId) $txt=(& $ClaspPath list-deployments $ScriptId 2>&1|Out-String);[pscustomobject]@{scriptId=$ScriptId;exitCode=$LASTEXITCODE;text=$txt}} -ArgumentList $cp,$sid}
    $deadline=(Get-Date).AddSeconds(70); while((Get-Date)-lt$deadline -and @($jobs|Where-Object{$_.State-in@('Running','NotStarted')}).Count-gt0){Start-Sleep -Milliseconds 500}
    foreach($j in $jobs){if($j.State-in@('Running','NotStarted')){Stop-Job $j -ErrorAction SilentlyContinue;Remove-Job $j -Force -ErrorAction SilentlyContinue;continue};$o=Receive-Job $j -ErrorAction SilentlyContinue;Remove-Job $j -Force -ErrorAction SilentlyContinue;if($o -and [int]$o.exitCode-eq0 -and [string]$o.text-match[regex]::Escape($ExpectedDeploymentId)){$exact+=[string]$o.scriptId}}
    $exact=@($exact|Sort-Object -Unique); if($exact.Count-gt1){break}
  }
  if($exact.Count-ne1){throw('SCRIPT_DEPLOYMENT_MATCH_COUNT_'+$exact.Count)}
  return [string]$exact[0]
}
'@
  $repairText=Get-Content -LiteralPath $repair -Raw -Encoding UTF8
  $insertPattern='(?m)^if\(-not\(Get-Command clasp'
  if([regex]::Matches($repairText,$insertPattern).Count-ne1){throw 'REPAIR_CLASP_MARKER_COUNT_INVALID'}
  $repairText=[regex]::Replace($repairText,$insertPattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$resolver+"`r`n"+$m.Value},1)
  $titlePattern='(?s)\$listText=\(& clasp list-scripts 2>&1 \| Out-String\).*?Write-Host "\[PASS\] Existing Script ID recovered: \$scriptId"'
  if([regex]::Matches($repairText,$titlePattern).Count-ne1){throw 'REPAIR_TITLE_BLOCK_COUNT_INVALID'}
  $titleReplacement='$scriptId=Resolve-ScriptIdByDeployment $ExpectedDeploymentId'+"`r`n"+'Write-Host "[PASS] Existing Script ID recovered by exact deployment: $scriptId"'
  $repairText=[regex]::Replace($repairText,$titlePattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$titleReplacement},1)
  $updatePattern='(?s)function Update-ExistingDeployment\(.*?(?=function Restore-Snapshot)'
  if([regex]::Matches($repairText,$updatePattern).Count-ne1){throw 'REPAIR_UPDATE_DEPLOYMENT_BLOCK_COUNT_INVALID'}
  $strictUpdate=@'
function Update-ExistingDeployment([string]$ProjectDir,[string]$DeploymentId,[string]$Description) {
  Push-Location $ProjectDir
  try {
    & clasp update-deployment $DeploymentId --description $Description
    if($LASTEXITCODE -ne 0){throw 'EXISTING_DEPLOYMENT_UPDATE_FAILED_NO_CREATE_FALLBACK'}
  } finally { Pop-Location }
}

'@
  $repairText=[regex]::Replace($repairText,$updatePattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$strictUpdate},1)
  $repairPatched=Join-Path $work 'Repair-ContentOS-DriveCacheAppsScript-ExactDeployment.ps1';Set-Content -LiteralPath $repairPatched -Value $repairText -Encoding UTF8;$r.repairPatched=$true
  $r.stage='RUN_PATCHED_EXISTING_TASK203_REPAIR';$out=(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $repairPatched 2>&1|Out-String);$r.repairExit=$LASTEXITCODE;$r.repairOutput=$out.Substring(0,[Math]::Min(16000,$out.Length));if($r.repairExit-ne0){throw('PATCHED_TASK203_REPAIR_EXIT_'+$r.repairExit)}
  $r.stage='LIBRARIAN_EXACT_DEPLOYMENT_PRECHECK';$scriptId=ResolveScriptIdByDeployment $DeploymentId;$r.scriptId=$scriptId;$deployBefore=GetDeployments $scriptId;$r.deploymentBefore=$deployBefore;if($deployBefore-notcontains$DeploymentId){throw 'EXPECTED_DEPLOYMENT_ID_NOT_FOUND'}
  $live=Join-Path $work 'live';$snapshot=Join-Path $work 'snapshot';$verify=Join-Path $work 'verify';CloneScript $scriptId $live;Copy-Item -LiteralPath $live -Destination $snapshot -Recurse -Force;$layout=Layout $live;$files=ScriptFiles $layout.Root
  $r.stage='PATCH_LIBRARIAN_SAME_SCRIPT';AddDispatcher $files 'doPost' 'centralLibrarianHandleWebPostV1';AddLibrarianWake $files;Copy-Item -Force $lib (Join-Path $layout.Root ('Central_Librarian_Knowledge_Automation'+$layout.Ext))
  Push-Location $live;try{& clasp push --force;if($LASTEXITCODE-ne0){throw 'LIBRARIAN_CLASP_PUSH_FAILED'}}finally{Pop-Location};$libPushed=$true
  CloneScript $scriptId $verify;$vl=Layout $verify;$vf=ScriptFiles $vl.Root;$r.librarianSourceReadback=@($vf|Where-Object{$_.BaseName-eq'Central_Librarian_Knowledge_Automation'}).Count-eq1;$r.dispatcherReadback=(CountPattern $vf 'centralLibrarianHandleWebPostV1\s*\(\s*e\s*\)')-ge2;$r.wakeReadback=(CountPattern $vf 'runCentralLibrarianKnowledgeIndex15mIfDue_\s*\(\s*\)')-ge2;if(-not$r.librarianSourceReadback-or-not$r.dispatcherReadback-or-not$r.wakeReadback){throw 'LIBRARIAN_SOURCE_OR_DISPATCH_READBACK_FAILED'}
  $r.stage='UPDATE_EXISTING_DEPLOYMENT_ONLY';UpdateDeploymentStrict $verify $DeploymentId ('Content OS central librarian '+(Get-Date -Format 'yyyyMMdd_HHmmss'));$r.deploymentAfter=GetDeployments $scriptId;AssertDeployments $deployBefore $r.deploymentAfter
  $r.stage='LIBRARIAN_RUNTIME_AUDIT';$r.audit=InvokeCentral 'central.librarian.audit.v1' @{};if(-not[bool]$r.audit.ok-or[int]$r.audit.librarianPhysicalTriggerCount-ne0){throw 'LIBRARIAN_AUDIT_FAILED'}
  $p=@{taskText='central librarian runtime verification: review history work instruction library workflow map success failure last good before task';appId='APP_AGENT_CORE'};$r.preflight1=InvokeCentral 'central.librarian.preflight.v1' $p;$r.preflight2=InvokeCentral 'central.librarian.preflight.v1' $p;if(-not[bool]$r.preflight1.ok-or-not[bool]$r.preflight2.ok){throw 'LIBRARIAN_PREFLIGHT_X2_FAILED'}
  try{$r.tick=InvokeCentral 'central.librarian.tick.v1' @{}}catch{$r.tick=[ordered]@{ok=$false;degraded=$true;error=$_.Exception.Message}}
  $r.ok=$true;$r.stage='DONE'
}catch{
  $r.error=$_.Exception.Message;$r.stage='ERROR'
  if($libPushed-and$scriptId-and(Test-Path $snapshot)){$r.rollbackAttempted=$true;try{Push-Location $snapshot;try{& clasp push --force;if($LASTEXITCODE-ne0){throw 'ROLLBACK_PUSH_FAILED'}}finally{Pop-Location};UpdateDeploymentStrict $snapshot $DeploymentId ('Central librarian rollback '+(Get-Date -Format 'yyyyMMdd_HHmmss'));AssertDeployments $deployBefore (GetDeployments $scriptId);$r.rollbackOk=$true}catch{$r.error+=';ROLLBACK='+$_.Exception.Message}}
}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}
