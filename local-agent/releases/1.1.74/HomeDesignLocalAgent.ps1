param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.74'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ExpectedBridge='0.2.75'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$StatePath=Join-Path $Root 'state.json'
$AttemptMarker=Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_BOM_1.1.74.attempted'
$ResultPath=Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_BOM_1.1.74.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0));$all=New-Object byte[]($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function ApiContent([string]$Path){
  $headers=@{'User-Agent'='HomeDesign-NLM-Fresh-BOM';'Accept'='application/vnd.github+json'}
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
}
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
  if($central){try{SaveJson (Join-Path $central 'Runtime_Readback\NotebookLM\NOTEBOOKLM_FRESH_CREATE_BOM_1.1.74.json') $Obj}catch{}}
}
function SaveState([string]$Status,[string]$NotebookUrl=''){
  $s=[ordered]@{agentVersion=$AgentVersion;status=$Status;extensionVersion=$ExpectedBridge;notebookUrl=$NotebookUrl;normalChromeTouched=$false;flowPrerequisite=$false;updatedAt=(Get-Date).ToString('o')}
  SaveJson $StatePath $s
}

if(Test-Path -LiteralPath $AttemptMarker){
  if(Test-Path -LiteralPath $ResultPath){try{$prior=Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8|ConvertFrom-Json;$prior|ConvertTo-Json -Depth 50 -Compress;if([bool]$prior.ok){exit 0}else{exit 2}}catch{}}
  $blocked=[ordered]@{ok=$false;action='NLM_FRESH_CREATE_BOM';agentVersion=$AgentVersion;status='ONE_SHOT_ALREADY_ATTEMPTED_NO_RETRY';normalChromeTouched=$false;at=(Get-Date).ToString('o')}
  PublishReceipt $blocked;SaveState 'ONE_SHOT_ALREADY_ATTEMPTED_NO_RETRY';$blocked|ConvertTo-Json -Depth 20 -Compress;exit 2
}
Set-Content -LiteralPath $AttemptMarker -Value ((Get-Date).ToString('o')) -Encoding ASCII

$result=[ordered]@{ok=$false;action='NLM_FRESH_CREATE_BOM';agentVersion=$AgentVersion;verifiedBridge='';helperGitBlob='';helperExitCode=$null;helperStdout='';freshNotebook=$null;normalChromeTouched=$false;flowPrerequisite=$false;startedAt=(Get-Date).ToString('o');error=''}
try{
  $manifestPath=Join-Path $ExtensionRoot 'manifest.json'
  if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw'MANIFEST_NOT_FOUND_AFTER_0275_ROLLBACK'}
  $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
  $result.verifiedBridge=[string]$manifest.version
  if($result.verifiedBridge-ne$ExpectedBridge){throw('BRIDGE_NOT_0275:'+ $result.verifiedBridge)}

  $r=ApiContent 'local-agent/governor/CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1'
  $raw=[Convert]::FromBase64String(([string]$r.content-replace'\s',''))
  $rawTmp=Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.raw.tmp'
  [IO.File]::WriteAllBytes($rawTmp,$raw)
  $actual=(GitBlobSha1 $rawTmp).ToLowerInvariant();$expected=([string]$r.sha).ToLowerInvariant();$result.helperGitBlob=$actual
  if($actual-ne$expected){Remove-Item -LiteralPath $rawTmp -Force -ErrorAction SilentlyContinue;throw'FRESH_HELPER_RAW_SHA_MISMATCH'}
  $helperText=[Text.Encoding]::UTF8.GetString($raw)
  $helper=Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1'
  $helperText|Set-Content -LiteralPath $helper -Encoding UTF8
  Remove-Item -LiteralPath $rawTmp -Force -ErrorAction SilentlyContinue

  $title='NLM Fresh E2E 2026-08-29 2008'
  $source='NLM_FRESH_ALL_20260829_2008 fresh notebook container. Existing generation and download workflow is preserved.'
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
  $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -Title "'+$title+'" -SourceText "'+$source+'" -RemoteDebuggingPort 9223 -TimeoutSeconds 90'
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$stdout=$p.StandardOutput.ReadToEnd();$stderr=$p.StandardError.ReadToEnd();$p.WaitForExit();$rc=$p.ExitCode
  $result.helperExitCode=$rc;$result.helperStdout=($stdout+$(if($stderr){"`nSTDERR:`n"+$stderr}else{''})).Trim()
  $jsonLine=@(($stdout-split"`r?`n")|Where-Object{$_.Trim().StartsWith('{')-and$_.Trim().EndsWith('}')})|Select-Object -Last 1
  if(-not$jsonLine){throw('FRESH_HELPER_NO_JSON exit='+$rc+' stderr='+$stderr.Trim())}
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
