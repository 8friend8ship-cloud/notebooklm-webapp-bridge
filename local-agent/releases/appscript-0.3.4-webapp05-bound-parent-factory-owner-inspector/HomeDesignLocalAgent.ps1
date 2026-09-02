param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.4-webapp05-bound-parent-factory-owner-inspector'
$ExpectedSheetId='1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'
$KnownWebAppDeploymentScriptId='1XzludErvxZ3px6qf1aLNU4LZWVU9NqJXYzSrnOm0HoDjUR9XN8flhSir'
$CanonicalEmail='homedesigntaedi@gmail.com'
$DefaultClaspClientId='1072944905499-vm2v2i5dvn0a0d2o4ca36i1vge8cvbn0.apps.googleusercontent.com'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$Receipt='APPSCRIPT_WEBAPP05_BOUND_PARENT_FACTORY_OWNER_INSPECTOR_0.3.4.json'
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
  $j=$o|ConvertTo-Json -Depth 80
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
function AddCredential([System.Collections.ArrayList]$List,[object]$Value,[string]$Source,[string]$FallbackClientId=''){
  if(-not$Value){return}
  $clientId=[string]$Value.client_id;if(-not$clientId){$clientId=$FallbackClientId}
  $clientSecret=[string]$Value.client_secret
  $access=[string]$Value.access_token
  $refresh=[string]$Value.refresh_token
  $expiry=0
  try{if($Value.expiry_date){$expiry=[int64]$Value.expiry_date}elseif($Value.exprity_date){$expiry=[int64]$Value.exprity_date}}catch{$expiry=0}
  if($access -or $refresh){[void]$List.Add([ordered]@{source=$Source;clientId=$clientId;clientSecret=$clientSecret;accessToken=$access;refreshToken=$refresh;expiryDate=$expiry})}
}
function GetCredentialCandidates{
  $list=New-Object System.Collections.ArrayList
  $paths=@((Join-Path $env:USERPROFILE '.clasprc.json'),(Join-Path $HOME '.clasprc.json'),(Join-Path (Get-Location).Path '.clasprc.json'))|Where-Object{$_}|Select-Object -Unique
  foreach($path in $paths){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
    try{
      $j=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
      if($j.token){
        $v=[ordered]@{access_token=[string]$j.token.access_token;refresh_token=[string]$j.token.refresh_token;expiry_date=$j.token.expiry_date;client_id='';client_secret=''}
        if($j.oauth2ClientSettings){$v.client_id=[string]$j.oauth2ClientSettings.clientId;$v.client_secret=[string]$j.oauth2ClientSettings.clientSecret}
        AddCredential $list ([pscustomobject]$v) ($path+':legacy-local') $DefaultClaspClientId
      }
      if($j.access_token -or $j.refresh_token){AddCredential $list $j ($path+':legacy-global') $DefaultClaspClientId}
      if($j.tokens){foreach($p in $j.tokens.PSObject.Properties){AddCredential $list $p.Value ($path+':v3:'+$p.Name) $DefaultClaspClientId}}
    }catch{}
  }
  @($list)
}
function GetAccessToken([string]$ExpectedClientId){
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $creds=@(GetCredentialCandidates)
  if($creds.Count-eq0){throw 'CLASP_CREDENTIAL_FILE_NOT_FOUND_OR_UNREADABLE'}
  $ordered=@($creds|Sort-Object @{Expression={if($_.clientId -eq $ExpectedClientId){0}else{1}}},@{Expression={$_.expiryDate};Descending=$true})
  foreach($c in $ordered){
    if($ExpectedClientId -and $c.clientId -and $c.clientId -ne $ExpectedClientId){continue}
    if($c.accessToken -and (($c.expiryDate-eq0)-or($c.expiryDate-gt($now+120000)))){return [ordered]@{token=$c.accessToken;source=$c.source;ephemeralRefresh=$false;clientId=$c.clientId}}
    if($c.refreshToken -and $c.clientId){
      try{
        $body=@{client_id=$c.clientId;refresh_token=$c.refreshToken;grant_type='refresh_token'}
        if($c.clientSecret){$body.client_secret=$c.clientSecret}
        $t=Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body $body -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30
        if($t.access_token){return [ordered]@{token=[string]$t.access_token;source=$c.source;ephemeralRefresh=$true;clientId=$c.clientId}}
      }catch{}
    }
  }
  throw 'NO_USABLE_EXISTING_CLASP_ACCESS_TOKEN'
}
function ApiGet([string]$Url,[string]$Token){
  try{
    $v=Invoke-RestMethod -Method Get -Uri $Url -Headers @{Authorization=('Bearer '+$Token)} -TimeoutSec 30
    return [ordered]@{ok=$true;value=$v;status=200;error=''}
  }catch{
    $status=0
    try{$status=[int]$_.Exception.Response.StatusCode}catch{}
    return [ordered]@{ok=$false;value=$null;status=$status;error=$_.Exception.Message}
  }
}
function InspectContent([object]$Content){
  $text='';$files=New-Object System.Collections.ArrayList
  foreach($f in @($Content.files)){
    $src=[string]$f.source
    [void]$files.Add([ordered]@{name=[string]$f.name;type=[string]$f.type;bytes=[Text.Encoding]::UTF8.GetByteCount($src)})
    $text+="`n"+$src
  }
  $sig=[ordered]@{
    processTaskQueue=($text -match '\bprocessTaskQueue\b')
    centralFactoryV2=($text -match 'CENTRAL_FACTORY_V2_20260812')
    factoryCycle=($text -match 'FACTORY_CYCLE')
    health=($text -match '\bHEALTH\b')
    appAnalyzer=($text -match 'APP_ANALYZER')
    expectedSheetId=($text -match [regex]::Escape($ExpectedSheetId))
    contentOsUnifiedSchedulerTick=($text -match '\bcontentOsUnifiedSchedulerTick\b')
    runCentralTabletRemoteDispatcherFromFactory=($text -match '\brunCentralTabletRemoteDispatcherFromFactory\b')
  }
  [ordered]@{files=@($files);signatures=$sig}
}

$r=[ordered]@{
  ok=$false
  action='READONLY_DISCOVER_BOUND_FACTORY_TRIGGER_OWNER_BY_PARENT_AND_HEAD_SIGNATURE'
  version=$Version
  expectedSheetId=$ExpectedSheetId
  knownWebAppDeploymentScriptId=$KnownWebAppDeploymentScriptId
  canonicalEmail=$CanonicalEmail
  authorizedUserOk=$false
  authorizedClientId=''
  credentialSource=''
  tokenRefreshedEphemeral=$false
  candidateCount=0
  metadataCheckedCount=0
  parentMatchCount=0
  parentMatches=@()
  factoryOwnerMatchCount=0
  factoryOwnerMatches=@()
  factoryTriggerScriptId=''
  webAppAndFactoryAreDifferent=$null
  historyScan=$null
  stage='START'
  error=''
  readOnly=$true
  newProject=$false
  newDeployment=$false
  newTrigger=$false
  pushPerformed=$false
  oauthChanged=$false
  scopeChanged=$false
  normalChromeTouched=$false
  startedAt=(Get-Date).ToString('o')
  completedAt=''
}
try{
  $clasp=ClaspPath;if(-not$clasp){throw 'CLASP_COMMAND_NOT_FOUND'}
  $r.stage='AUTH_READONLY'
  $auth=RunClasp $clasp @('show-authorized-user','--json') 45
  if(-not$auth.ok){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'}
  $authText=($auth.stdout+' '+$auth.stderr).Trim()
  try{$authJson=$authText|ConvertFrom-Json}catch{$authJson=$null}
  if($authJson){
    $r.authorizedUserOk=([string]$authJson.email).ToLowerInvariant()-eq$CanonicalEmail.ToLowerInvariant()
    $r.authorizedClientId=[string]$authJson.clientId
  }else{
    $r.authorizedUserOk=$authText.ToLowerInvariant().Contains($CanonicalEmail.ToLowerInvariant())
    if($authText -match '1072944905499-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com'){$r.authorizedClientId=$Matches[0]}
  }
  if(-not$r.authorizedUserOk){throw 'CLASP_ACCOUNT_MISMATCH'}
  if(-not$r.authorizedClientId){$r.authorizedClientId=$DefaultClaspClientId}

  $tok=GetAccessToken $r.authorizedClientId
  $accessToken=[string]$tok.token
  $r.credentialSource=[string]$tok.source
  $r.tokenRefreshedEphemeral=[bool]$tok.ephemeralRefresh

  $r.stage='RECOVER_CANDIDATES'
  $r.historyScan=RecoverCandidates
  $candidates=@($r.historyScan.candidates)
  $r.candidateCount=$candidates.Count
  if($candidates.Count-eq0){throw 'NO_SCRIPT_ID_CANDIDATES_IN_LOCAL_OR_BROWSER_EVIDENCE'}

  $r.stage='PROJECT_METADATA_PARENT_MATCH'
  $parents=New-Object System.Collections.ArrayList
  foreach($c in $candidates){
    $id=[string]$c.scriptId
    $meta=ApiGet ('https://script.googleapis.com/v1/projects/'+$id) $accessToken
    $r.metadataCheckedCount++
    if(-not$meta.ok){continue}
    $p=[string]$meta.value.parentId
    if($p -eq $ExpectedSheetId){
      [void]$parents.Add([ordered]@{scriptId=$id;title=[string]$meta.value.title;parentId=$p;updateTime=[string]$meta.value.updateTime;creatorEmail=[string]$meta.value.creator.email;lastModifyEmail=[string]$meta.value.lastModifyUser.email;sources=$c.sources})
    }
  }
  $r.parentMatches=@($parents);$r.parentMatchCount=$parents.Count
  if($parents.Count-eq0){throw 'NO_SCRIPT_PROJECT_BOUND_TO_EXPECTED_SHEET_AMONG_RECOVERED_CANDIDATES'}

  $r.stage='HEAD_FACTORY_SIGNATURE_MATCH'
  $owners=New-Object System.Collections.ArrayList
  foreach($p in @($parents)){
    $id=[string]$p.scriptId
    $content=ApiGet ('https://script.googleapis.com/v1/projects/'+$id+'/content') $accessToken
    if(-not$content.ok){continue}
    $ins=InspectContent $content.value
    if($ins.signatures.processTaskQueue){
      [void]$owners.Add([ordered]@{scriptId=$id;title=$p.title;parentId=$p.parentId;updateTime=$p.updateTime;isKnownWebAppDeploymentScript=($id-eq$KnownWebAppDeploymentScriptId);files=$ins.files;signatures=$ins.signatures})
    }
  }
  $r.factoryOwnerMatches=@($owners);$r.factoryOwnerMatchCount=$owners.Count
  if($owners.Count-ne1){throw ('BOUND_FACTORY_OWNER_MATCH_COUNT_'+$owners.Count)}

  $r.factoryTriggerScriptId=[string]$owners[0].scriptId
  $r.webAppAndFactoryAreDifferent=($r.factoryTriggerScriptId-ne$KnownWebAppDeploymentScriptId)
  if(-not$r.webAppAndFactoryAreDifferent){throw 'SAFETY_STOP_WEBAPP_DEPLOYMENT_SCRIPT_EQUALS_FACTORY_TRIGGER_OWNER_REVERIFY_REQUIRED'}

  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{
  $r.completedAt=(Get-Date).ToString('o')
  Save $r
}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}
