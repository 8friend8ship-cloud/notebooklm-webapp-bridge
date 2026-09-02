param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.0-webapp05-history-exactdeployment-discovery'
$TargetDeployment='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo'
$ExpectedSheetId='1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'
$CanonicalEmail='homedesigntaedi@gmail.com'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$Receipt='APPSCRIPT_DISCOVER_WEBAPP_TEMPLATE_05_BY_HISTORY_EXACT_DEPLOYMENT_0.3.0.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  ''
}
function Save($o){
  $j=$o|ConvertTo-Json -Depth 60
  $j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8
  try{
    $c=FindCentral
    if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}
  }catch{}
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
      $sessions=Join-Path $p.FullName 'Sessions'
      if(Test-Path -LiteralPath $sessions -PathType Container){foreach($f in @(Get-ChildItem -LiteralPath $sessions -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 40)){[void]$files.Add($f.FullName)}}
    }
  }
  @($files|Select-Object -Unique)
}
function AddCandidate([hashtable]$Map,[string]$Id,[string]$Source,[datetime]$When){
  if(-not$Id -or $Id.Length-lt40){return}
  if(-not$Map.ContainsKey($Id)){$Map[$Id]=[ordered]@{scriptId=$Id;sources=New-Object System.Collections.ArrayList;latest=[datetime]'2000-01-01'}}
  if($Source -and -not$Map[$Id].sources.Contains($Source)){[void]$Map[$Id].sources.Add($Source)}
  if($When -gt [datetime]$Map[$Id].latest){$Map[$Id].latest=$When}
}
function RecoverCandidates{
  $map=@{};$scanned=New-Object System.Collections.ArrayList
  foreach($root in @($Base,(Join-Path $env:USERPROFILE 'Documents'),(Join-Path $env:USERPROFILE 'Desktop'),(Join-Path $env:USERPROFILE 'Downloads'))|Where-Object{$_ -and (Test-Path -LiteralPath $_ -PathType Container)}|Select-Object -Unique){
    foreach($f in @(Get-ChildItem -LiteralPath $root -Filter '.clasp.json' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 300)){
      try{$j=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json;AddCandidate $map ([string]$j.scriptId) $f.FullName $f.LastWriteTime}catch{}
    }
  }
  $rx=@(
    'https?://script\.google\.com/(?:u/\d+/)?home/projects/([A-Za-z0-9_-]{40,})',
    'https?://script\.google\.com/d/([A-Za-z0-9_-]{40,})/edit'
  )
  foreach($f in @(BrowserEvidenceFiles)){
    try{$info=Get-Item -LiteralPath $f -ErrorAction Stop;if($info.Length-gt268435456){continue}}catch{continue}
    $text=SharedAscii $f;if(-not$text){continue};$count=0
    foreach($pattern in $rx){foreach($m in [regex]::Matches($text,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)){
      $id=[string]$m.Groups[1].Value;if(-not$id){continue};$count++;AddCandidate $map $id $f $info.LastWriteTime
    }}
    [void]$scanned.Add([ordered]@{path=$f;bytes=[int64]$info.Length;matches=$count;lastWrite=$info.LastWriteTime.ToString('o')})
  }
  $rows=@($map.Values|ForEach-Object{[ordered]@{scriptId=$_.scriptId;latest=([datetime]$_.latest).ToString('o');sources=@($_.sources)}}|Sort-Object @{Expression={[datetime]$_.latest};Descending=$true})
  [ordered]@{candidates=$rows;scanned=@($scanned)}
}
function ClaspPath{
  foreach($name in @('clasp.cmd','clasp.ps1','clasp')){$c=Get-Command $name -ErrorAction SilentlyContinue;if($c){return $c.Source}}
  foreach($p in @((Join-Path $env:APPDATA 'npm\clasp.cmd'),(Join-Path $env:APPDATA 'npm\clasp.ps1'))){if(Test-Path -LiteralPath $p){return $p}}
  ''
}
function RunClasp([string]$Clasp,[string[]]$Args,[int]$TimeoutSec=60,[string]$Cwd=''){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $ext=[IO.Path]::GetExtension($Clasp).ToLowerInvariant()
  if($ext -eq '.cmd'){$psi.FileName=$env:ComSpec;$psi.Arguments='/d /s /c ""'+$Clasp+'" '+(($Args|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')+'"'}
  elseif($ext -eq '.ps1'){$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Clasp+'" '+(($Args|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')}
  else{$psi.FileName=$Clasp;$psi.Arguments=(($Args|ForEach-Object{'"'+($_-replace'"','\"')+'"'})-join' ')}
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  if($Cwd){$psi.WorkingDirectory=$Cwd}
  $p=[Diagnostics.Process]::Start($psi)
  if(-not$p.WaitForExit($TimeoutSec*1000)){try{$p.Kill()}catch{};return [ordered]@{ok=$false;exit=124;stdout='';stderr='TIMEOUT'}}
  [ordered]@{ok=($p.ExitCode-eq0);exit=$p.ExitCode;stdout=$p.StandardOutput.ReadToEnd();stderr=$p.StandardError.ReadToEnd()}
}

$r=[ordered]@{ok=$false;action='DISCOVER_EXISTING_APPS_SCRIPT_BY_HISTORY_AND_EXACT_DEPLOYMENT';version=$Version;targetDeployment=$TargetDeployment;expectedSheetId=$ExpectedSheetId;authorizedUser='';authorizedUserOk=$false;deprecatedListScriptsUsed=$false;candidateCount=0;checkedCount=0;matches=@();scriptId='';sourceContainsExpectedSheetId=$false;sourceContainsProcessTaskQueue=$false;historyScan=$null;stage='START';error='';readOnly=$true;newProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $clasp=ClaspPath;if(-not$clasp){throw 'CLASP_COMMAND_NOT_FOUND'}
  $r.stage='AUTH_READONLY';$auth=RunClasp $clasp @('show-authorized-user','--json') 45
  if(-not$auth.ok){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'}
  $r.authorizedUser=($auth.stdout+' '+$auth.stderr).Trim()
  $r.authorizedUserOk=($r.authorizedUser.ToLowerInvariant().Contains($CanonicalEmail.ToLowerInvariant()))
  if(-not$r.authorizedUserOk){throw 'CLASP_ACCOUNT_MISMATCH'}

  $r.stage='RECOVER_LOCAL_AND_BROWSER_CANDIDATES';$r.historyScan=RecoverCandidates;$candidates=@($r.historyScan.candidates);$r.candidateCount=$candidates.Count
  if($candidates.Count-eq0){throw 'NO_SCRIPT_ID_CANDIDATES_IN_LOCAL_OR_BROWSER_EVIDENCE'}

  $r.stage='EXACT_DEPLOYMENT_MATCH';$found=$null
  foreach($c in $candidates){
    $r.checkedCount++
    $dep=RunClasp $clasp @('list-deployments',[string]$c.scriptId) 45
    if(-not$dep.ok){continue}
    $txt=($dep.stdout+' '+$dep.stderr)
    if($txt -match [regex]::Escape($TargetDeployment)){$found=[string]$c.scriptId;$r.matches=@([ordered]@{scriptId=$found;sources=$c.sources;deploymentFound=$true});break}
  }
  if(-not$found){throw ('EXACT_DEPLOYMENT_NOT_FOUND_AMONG_'+$candidates.Count+'_CANDIDATES')}
  $r.scriptId=$found

  $r.stage='READONLY_CLONE_VERIFY';$dir=Join-Path $env:TEMP ('webapp05-history-discovery-'+(Get-Date -Format 'yyyyMMdd_HHmmss'));New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $clone=RunClasp $clasp @('clone-script',$found) 120 $dir;if(-not$clone.ok){$clone=RunClasp $clasp @('clone',$found) 120 $dir}
  if(-not$clone.ok){throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED'}
  $files=@(Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in @('.gs','.js','.json','.html')})
  foreach($f in $files){try{$text=Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop;if($text -match [regex]::Escape($ExpectedSheetId)){$r.sourceContainsExpectedSheetId=$true};if($text -match 'processTaskQueue'){$r.sourceContainsProcessTaskQueue=$true}}catch{}}
  if(-not$r.sourceContainsProcessTaskQueue){throw 'BOUND_SOURCE_SIGNATURE_PROCESS_TASK_QUEUE_MISSING'}

  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 60 -Compress
if($r.ok){exit 0}else{exit 2}
