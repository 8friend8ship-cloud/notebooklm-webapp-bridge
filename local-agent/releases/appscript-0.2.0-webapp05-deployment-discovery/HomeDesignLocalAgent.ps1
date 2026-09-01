param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.2.0-webapp05-deployment-discovery'
$TargetDeployment='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$ExpectedSheetId='1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_DISCOVER_WEBAPP_TEMPLATE_05_BY_DEPLOYMENT_0.2.0.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;action='DISCOVER_EXISTING_APPS_SCRIPT_BY_EXACT_DEPLOYMENT';version=$Version;targetDeployment=$TargetDeployment;expectedSheetId=$ExpectedSheetId;authorizedUserOk=$false;scriptListOk=$false;candidateCount=0;checkedCount=0;matches=@();scriptId='';sourceContainsExpectedSheetId=$false;stage='START';error='';readOnly=$true;newProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  if(-not(Get-Command clasp -ErrorAction SilentlyContinue)){throw 'CLASP_COMMAND_NOT_FOUND'}
  $r.stage='AUTH_READONLY';$auth=(& clasp show-authorized-user --json 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'};$r.authorizedUserOk=$true
  $r.stage='LIST_SCRIPTS';$list=(& clasp list-scripts 2>&1|Out-String);if($LASTEXITCODE-ne0){throw 'CLASP_LIST_SCRIPTS_FAILED'};$r.scriptListOk=$true
  $ids=@([regex]::Matches($list,'[A-Za-z0-9_-]{30,}')|ForEach-Object{$_.Value}|Sort-Object -Unique);$r.candidateCount=$ids.Count
  $matches=@();foreach($id in $ids){$r.checkedCount++;$dep=(& clasp list-deployments $id 2>&1|Out-String);if($LASTEXITCODE-ne0){continue};if($dep -match [regex]::Escape($TargetDeployment)){$matches+=[pscustomobject]@{scriptId=$id;deploymentFound=$true;deploymentText=$dep.Substring(0,[Math]::Min(4000,$dep.Length))}}}
  $r.matches=$matches;if($matches.Count-ne1){throw('EXACT_DEPLOYMENT_MATCH_COUNT_'+$matches.Count)};$sid=[string]$matches[0].scriptId;$r.scriptId=$sid
  $r.stage='READONLY_CLONE_VERIFY';$dir=Join-Path $env:TEMP ('webapp05-discovery-'+(Get-Date -Format 'yyyyMMdd_HHmmss'));New-Item -ItemType Directory -Force -Path $dir|Out-Null;Push-Location $dir;try{& clasp clone-script $sid 2>$null;if($LASTEXITCODE-ne0){& clasp clone $sid 2>$null;if($LASTEXITCODE-ne0){throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED'}}}finally{Pop-Location}
  $hits=@(Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in @('.gs','.js','.json')}|ForEach-Object{try{if((Get-Content $_.FullName -Raw -ErrorAction Stop)-match [regex]::Escape($ExpectedSheetId)){$_}}catch{}});$r.sourceContainsExpectedSheetId=($hits.Count-gt0)
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 40 -Compress
if($r.ok){exit 0}else{exit 2}
