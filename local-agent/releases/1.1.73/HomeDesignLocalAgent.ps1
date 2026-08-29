param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.73'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$RollbackRef='10b464ac4022a73e4728bf5012a7ce33c91025b2'
$RollbackVersion='0.2.75'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$StatePath=Join-Path $Root 'state.json'
$AttemptMarker=Join-Path $Root 'NOTEBOOKLM_ROLLBACK_0275_FRESH_CREATE_1.1.73.attempted'
$ResultPath=Join-Path $Root 'NOTEBOOKLM_ROLLBACK_0275_FRESH_CREATE_1.1.73.json'
New-Item -ItemType Directory -Force -Path $Root,$ExtensionRoot|Out-Null

function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0));$all=New-Object byte[]($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function ApiContent([string]$Path,[string]$Ref='main'){
  $headers=@{'User-Agent'='HomeDesign-NLM-Rollback-Fresh';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref='+$Ref+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
}
function DecodeText($R){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$R.content-replace'\s','')))}
function WriteApiFile($R,[string]$Path){$parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};[IO.File]::WriteAllBytes($Path,[Convert]::FromBase64String(([string]$R.content-replace'\s','')))}
function FindCentralRoot{
  $central=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not$r){continue}
    foreach($p in @((Join-Path $r $central),(Join-Path $r ($myDriveKo+'\'+$central)),(Join-Path $r ('My Drive\'+$central)),(Join-Path $r ('Google Drive\'+$central)))){if(Test-Path -LiteralPath $p -PathType Container){return $p}}
  }
  return ''
}
function SaveJson([string]$Path,$Obj){$parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$Obj|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}
function PublishReceipt($Obj){
  SaveJson $ResultPath $Obj
  $central=FindCentralRoot
  if($central){try{SaveJson (Join-Path $central 'Runtime_Readback\NotebookLM\NOTEBOOKLM_ROLLBACK_0275_FRESH_CREATE_1.1.73.json') $Obj}catch{}}
}
function SaveState([string]$Status,[string]$NotebookUrl=''){
  $s=[ordered]@{agentVersion=$AgentVersion;status=$Status;extensionVersion=$RollbackVersion;notebookUrl=$NotebookUrl;normalChromeTouched=$false;flowPrerequisite=$false;updatedAt=(Get-Date).ToString('o')}
  SaveJson $StatePath $s
}

if(Test-Path -LiteralPath $AttemptMarker){
  if(Test-Path -LiteralPath $ResultPath){
    try{$prior=Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8|ConvertFrom-Json;$prior|ConvertTo-Json -Depth 50 -Compress;if([bool]$prior.ok){exit 0}else{exit 2}}catch{}
  }
  $blocked=[ordered]@{ok=$false;action='NLM_ROLLBACK_0275_FRESH_CREATE';agentVersion=$AgentVersion;status='ONE_SHOT_ALREADY_ATTEMPTED_NO_RETRY';normalChromeTouched=$false;at=(Get-Date).ToString('o')}
  PublishReceipt $blocked;SaveState 'ONE_SHOT_ALREADY_ATTEMPTED_NO_RETRY';$blocked|ConvertTo-Json -Depth 20 -Compress;exit 2
}
Set-Content -LiteralPath $AttemptMarker -Value ((Get-Date).ToString('o')) -Encoding ASCII

$result=[ordered]@{ok=$false;action='NLM_ROLLBACK_0275_FRESH_CREATE';agentVersion=$AgentVersion;rollbackRef=$RollbackRef;rollbackVersion=$RollbackVersion;appliedFiles=@();freshNotebook=$null;helperExitCode=$null;helperStdout='';normalChromeTouched=$false;flowPrerequisite=$false;startedAt=(Get-Date).ToString('o');error=''}
try{
  $relResp=ApiContent 'runtime/stable/release.json' $RollbackRef
  $release=(DecodeText $relResp)|ConvertFrom-Json
  if([string]$release.version-ne$RollbackVersion){throw('ROLLBACK_RELEASE_VERSION_MISMATCH:'+ [string]$release.version)}
  foreach($f in @($release.files)){
    $relPath=[string]$f.path;$expected=([string]$f.gitBlobSha1).ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($relPath)-or$relPath.Contains('..')-or$relPath.StartsWith('/')-or$relPath.StartsWith('\')){throw('UNSAFE_RELEASE_PATH:'+ $relPath)}
    $src='notebooklm-webapp-bridge-source-v0.2.0/extension/'+$relPath.Replace('\','/')
    $r=ApiContent $src $RollbackRef
    if(([string]$r.sha).ToLowerInvariant()-ne$expected){throw('ROLLBACK_API_SHA_MISMATCH:'+ $relPath)}
    $dest=Join-Path $ExtensionRoot $relPath.Replace('/','\');$tmp=$dest+'.rollback0275.download';WriteApiFile $r $tmp
    $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual-ne$expected){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue;throw('ROLLBACK_LOCAL_SHA_MISMATCH:'+ $relPath)}
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    $result.appliedFiles+=([ordered]@{path=$relPath;sha=$actual})
  }
  $manifest=Get-Content -LiteralPath (Join-Path $ExtensionRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if([string]$manifest.version-ne$RollbackVersion){throw('ROLLBACK_MANIFEST_VERSION_MISMATCH:'+ [string]$manifest.version)}

  $helperResp=ApiContent 'local-agent/governor/CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1' 'main'
  $helper=Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1';$tmpHelper=$helper+'.download';WriteApiFile $helperResp $tmpHelper
  if((GitBlobSha1 $tmpHelper).ToLowerInvariant()-ne([string]$helperResp.sha).ToLowerInvariant()){Remove-Item -LiteralPath $tmpHelper -Force -ErrorAction SilentlyContinue;throw'FRESH_HELPER_SHA_MISMATCH'}
  Move-Item -LiteralPath $tmpHelper -Destination $helper -Force

  $title='NLM Fresh E2E 2026-08-29 1954'
  $source='NLM_FRESH_ALL_20260829_1954 fresh notebook container. Existing generation and download workflow is preserved.'
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Title $title -SourceText $source -RemoteDebuggingPort 9223 -TimeoutSeconds 90 2>&1|Out-String
  $rc=$LASTEXITCODE;$result.helperExitCode=$rc;$result.helperStdout=$out.Trim()
  $jsonLine=@(($out-split"`r?`n")|Where-Object{$_.Trim().StartsWith('{')-and$_.Trim().EndsWith('}')})|Select-Object -Last 1
  if(-not$jsonLine){throw('FRESH_HELPER_NO_JSON exit='+$rc)}
  $fresh=$jsonLine|ConvertFrom-Json;$result.freshNotebook=$fresh
  if($rc-ne0-or-not[bool]$fresh.ok-or[string]::IsNullOrWhiteSpace([string]$fresh.notebookUrl)){throw('FRESH_NOTEBOOK_CREATE_FAILED:'+ [string]$fresh.error)}
  if([string]$fresh.notebookId-eq'69e055e5-c8d0-4e9c-8686-58cc6da35a51'){throw'FRESH_NOTEBOOK_REUSED_HISTORICAL_ID'}
  $result.ok=$true;$result.status='FRESH_NOTEBOOK_CREATED';$result.completedAt=(Get-Date).ToString('o')
  PublishReceipt $result;SaveState 'FRESH_NOTEBOOK_CREATED' ([string]$fresh.notebookUrl)
}catch{
  $result.error=$_.Exception.Message;$result.status='FAILED_FAIL_CLOSED';$result.completedAt=(Get-Date).ToString('o')
  PublishReceipt $result;SaveState 'FAILED_FAIL_CLOSED'
}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}else{exit 2}
