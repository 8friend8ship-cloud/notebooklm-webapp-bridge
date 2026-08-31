param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.135'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Ref='main'
$ChildPath='local-agent/releases/1.1.129/RunNotebookLMFreshAllStudioE2EV1.ps1'
$Title='2026-08-31 ContentOS Workflow Studio E2E'
$Marker='NLM_WORKFLOW_STUDIO_ALL_20260831_1446'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='AGENT_1.1.135_NLM_FRESH_ALL_STUDIO_RECOVERY_RESULT.json'
$ReceiptPath=Join-Path $Root $Receipt
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function Save($o){$j=$o|ConvertTo-Json -Depth 100;$j|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;action='AGENT_1.1.135_NLM_FRESH_ALL_STUDIO_RECOVERY';version=$Version;childPath=$ChildPath;title=$Title;marker=$Marker;bridgeTarget='0.2.39';duplicateNotebookAllowed=$false;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;fetchMode='';stage='START';childExitCode=$null;childOutput='';error='';startedAt=(Get-Date).ToString('o')}
try{
  $headers=@{'User-Agent'='HomeDesignLocalAgent';'Accept'='application/vnd.github+json'}
  $text=$null
  try{
    $r.stage='FETCH_CHILD_CONTENTS_API'
    $uri='https://api.github.com/repos/'+$Repo+'/contents/'+$ChildPath+'?ref='+$Ref+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $meta=Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30
    if(-not $meta.content){throw 'CHILD_CONTENT_MISSING'}
    $bytes=[Convert]::FromBase64String(([string]$meta.content -replace '\s',''))
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    $r.fetchMode='CONTENTS_API'
  }catch{
    $r.stage='FETCH_CHILD_RAW_FALLBACK'
    $raw='https://raw.githubusercontent.com/'+$Repo+'/'+$Ref+'/'+$ChildPath+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $text=(Invoke-WebRequest -UseBasicParsing -Uri $raw -Headers @{'User-Agent'='HomeDesignLocalAgent'} -TimeoutSec 30).Content
    $r.fetchMode='RAW_FALLBACK'
  }
  if([string]::IsNullOrWhiteSpace([string]$text)){throw 'CHILD_TEXT_EMPTY'}
  if($text -notmatch 'NLM_WORKFLOW_STUDIO_ALL_20260831_1446'){throw 'CHILD_MARKER_CONTRACT_MISMATCH'}
  $tmp=Join-Path $Root 'RunNotebookLMFreshAllStudioE2EV1.ps1'
  [IO.File]::WriteAllText($tmp,$text,(New-Object Text.UTF8Encoding($false)))
  $r.stage='RUN_FRESH_ALL_STUDIO'
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp -Title $Title -Marker $Marker -RemoteDebuggingPort 9223 -TimeoutSeconds 1800 2>&1
  $r.childExitCode=$LASTEXITCODE
  $r.childOutput=(@($out)|Out-String).Trim()
  if($LASTEXITCODE -ne 0){throw ('CHILD_EXIT_'+$LASTEXITCODE)}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 100 -Compress
if($r.ok){exit 0}else{exit 2}
