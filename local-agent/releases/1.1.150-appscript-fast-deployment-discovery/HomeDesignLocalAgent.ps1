param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.150-appscript-fast-deployment-discovery'
$TargetDeployment='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_FAST_DISCOVER_WEBAPP05_1.1.150.json'
$MaxParallel=6
$PerBatchTimeout=70
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 60;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;action='FAST_READONLY_SCRIPT_DISCOVERY_BY_EXACT_DEPLOYMENT';version=$Version;targetDeployment=$TargetDeployment;authorizedUserOk=$false;listScriptsRaw='';candidateCount=0;checkedCount=0;timedOutIds=@();matches=@();scriptId='';stage='START';error='';readOnly=$true;normalChromeTouched=$false;flowGenerateRan=$false;creditSpend=$false;newProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
$jobs=@()
try{
  $cp=(Get-Command clasp -ErrorAction Stop).Source
  $r.stage='AUTH';$auth=(& $cp show-authorized-user --json 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'};$r.authorizedUserOk=$true
  $r.stage='LIST_SCRIPTS';$list=(& $cp list-scripts 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'CLASP_LIST_SCRIPTS_FAILED'};$r.listScriptsRaw=$list.Substring(0,[Math]::Min(20000,$list.Length))
  $ids=@();foreach($line in ($list-split"`r?`n")){if($line -match '[–—-]\s*([A-Za-z0-9_-]{30,})\s*$'){$ids+=$Matches[1]}};$ids=@($ids|Sort-Object -Unique);if($ids.Count-eq0){$ids=@([regex]::Matches($list,'[A-Za-z0-9_-]{30,}')|ForEach-Object{$_.Value}|Sort-Object -Unique)};$r.candidateCount=$ids.Count
  $r.stage='PARALLEL_DEPLOYMENT_MATCH';$all=@()
  for($offset=0;$offset-lt$ids.Count;$offset+=$MaxParallel){
    $batch=@($ids[$offset..([Math]::Min($ids.Count-1,$offset+$MaxParallel-1))]);$jobs=@()
    foreach($sid in $batch){$jobs+=Start-Job -ScriptBlock {param($ClaspPath,$ScriptId) $txt=(& $ClaspPath list-deployments $ScriptId 2>&1|Out-String);[pscustomobject]@{scriptId=$ScriptId;exitCode=$LASTEXITCODE;text=$txt}} -ArgumentList $cp,$sid}
    $deadline=(Get-Date).AddSeconds($PerBatchTimeout)
    while((Get-Date)-lt$deadline -and @($jobs|Where-Object{$_.State -in @('Running','NotStarted')}).Count-gt0){Start-Sleep -Milliseconds 500}
    foreach($j in $jobs){if($j.State -in @('Running','NotStarted')){$sid='';try{$sid=[string]$j.ChildJobs[0].JobStateInfo.Reason}catch{};Stop-Job $j -ErrorAction SilentlyContinue;$r.timedOutIds+=([string]$j.Id);continue};$o=Receive-Job $j -ErrorAction SilentlyContinue;if($o){$all+=$o;$r.checkedCount++;if([int]$o.exitCode-eq0 -and [string]$o.text -match [regex]::Escape($TargetDeployment)){$r.matches+=[ordered]@{scriptId=[string]$o.scriptId;deploymentFound=$true;text=([string]$o.text).Substring(0,[Math]::Min(4000,([string]$o.text).Length))}}};Remove-Job $j -Force -ErrorAction SilentlyContinue}
    if($r.matches.Count-gt1){break}
  }
  $r.matches=@($r.matches|Group-Object scriptId|ForEach-Object{$_.Group[0]});if($r.matches.Count-ne1){throw('EXACT_DEPLOYMENT_MATCH_COUNT_'+$r.matches.Count)};$r.scriptId=[string]$r.matches[0].scriptId;$r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{foreach($j in @($jobs)){try{Stop-Job $j -ErrorAction SilentlyContinue;Remove-Job $j -Force -ErrorAction SilentlyContinue}catch{}};$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 60 -Compress
if($r.ok){exit 0}else{exit 2}
