param([switch]$KickStableAgent,[switch]$StatusOnly,[switch]$RunGovernor,[switch]$ApplyStableBridge,[switch]$BridgeStatusOnly,[switch]$BridgeLocalEvidence,[switch]$VideoFailureDiagnostic,[switch]$FlowDirectRecoveryDiagnostic,[switch]$CaptureBridgeSmoke,[switch]$InteriorAppsScriptSync,[switch]$InspectNotebookLMDownloads,[switch]$DownloadExistingNotebookArtifactViaCDP,[switch]$InstallPowerContinuity,[string]$CentralRelativePath='',[string]$SmokeFile='',[string]$ExpectedBridge='0.2.18')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Receipt=Join-Path $Root 'FRESH_NLM_SOURCE_CDP_V2_20260829_2132.json'
$OriginalBlob='32115379ac0ac2b48dddd592f2fad5fa834ec4a5'

function FindCentralRoot {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($candidate in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  }
  return ''
}
function WriteReceipt($Obj){
  try{$json=$Obj|ConvertTo-Json -Depth 40;$json|Set-Content -LiteralPath $Receipt -Encoding UTF8;$central=FindCentralRoot;if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir 'FRESH_NLM_SOURCE_CDP_V2_20260829_2132.json') -Encoding UTF8}}catch{}
}
function ApiFile([string]$Path){
  $h=@{'User-Agent'='HomeDesign-NLM-Fresh-OneShot';'Accept'='application/vnd.github+json'}
  $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return Invoke-RestMethod -Uri $u -Headers $h -Method Get -TimeoutSec 20
}
function DecodeTo($Resp,[string]$Path){[IO.File]::WriteAllBytes($Path,[Convert]::FromBase64String(([string]$Resp.content -replace '\s','')))}
function BuildOriginalArgs {
  $a=@()
  foreach($n in @('KickStableAgent','StatusOnly','RunGovernor','ApplyStableBridge','BridgeStatusOnly','BridgeLocalEvidence','VideoFailureDiagnostic','FlowDirectRecoveryDiagnostic','CaptureBridgeSmoke','InteriorAppsScriptSync','InspectNotebookLMDownloads','DownloadExistingNotebookArtifactViaCDP','InstallPowerContinuity')){if((Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue)){$a+=('-'+$n)}}
  if($CentralRelativePath){$a+=@('-CentralRelativePath',$CentralRelativePath)}
  if($SmokeFile){$a+=@('-SmokeFile',$SmokeFile)}
  if($ExpectedBridge){$a+=@('-ExpectedBridge',$ExpectedBridge)}
  return @($a)
}

if(-not $KickStableAgent){
  try{
    $h=@{'User-Agent'='HomeDesign-NLM-Fresh-OneShot';'Accept'='application/vnd.github+json'}
    $blob=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/git/blobs/'+$OriginalBlob+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $h -Method Get -TimeoutSec 20
    $orig=Join-Path $Root 'RunChromeGovernorReadback.original-32115379.ps1';[IO.File]::WriteAllBytes($orig,[Convert]::FromBase64String(([string]$blob.content -replace '\s','')))
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$orig)+(BuildOriginalArgs)
    & powershell.exe @args
    exit $LASTEXITCODE
  }catch{Write-Error ('ORIGINAL_GOVERNOR_FALLBACK_FAILED: '+$_.Exception.Message);exit 2}
}

if(Test-Path -LiteralPath $Receipt){
  try{$old=Get-Content -LiteralPath $Receipt -Raw -Encoding UTF8|ConvertFrom-Json;if($old -and $old.oneShotConsumed){$old|ConvertTo-Json -Depth 40 -Compress;exit 0}}catch{}
}

$outer=[ordered]@{ok=$true;action='NOTEBOOKLM_FRESH_NOTEBOOK_SOURCE_OUT_OF_BAND_ONESHOT';oneShotConsumed=$true;startedAt=(Get-Date).ToString('o');helperExitCode=$null;helperOk=$false;helper=$null;stdout='';error=''}
try{
  $resp=ApiFile 'local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1'
  $helper=Join-Path $Root 'FreshNotebookSourceCdpV2-OneShot.ps1';DecodeTo $resp $helper
  $title='2026-08-29 NotebookLM Fresh E2E 전체 산출물 검증'
  $source='2026-08-29 신규 NotebookLM E2E 검증 전용 원문. 이 노트북은 기존 프로젝트와 완전히 분리한다. 핵심 흐름은 FRESH_NOTEBOOK → SOURCE → AUDIO_OVERVIEW → SLIDES → VIDEO_OVERVIEW → REPORT → MIND_MAP → FLASHCARDS → QUIZ → INFOGRAPHIC → DATA_TABLE → NATIVE_DOWNLOAD → DRIVE_READBACK 이다. 고유 마커: NLM_FRESH_ALL_20260829_1915.'
  $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -Title $title -SourceText $source -ExpectedOldNotebookId '69e055e5-c8d0-4e9c-8686-58cc6da35a51' -TimeoutSeconds 120 2>&1|Out-String
  $ec=$LASTEXITCODE;$outer.helperExitCode=$ec;$outer.stdout=$out.Trim()
  try{$parsed=$out.Trim()|ConvertFrom-Json;$outer.helper=$parsed;$outer.helperOk=[bool]($parsed.ok -and $parsed.freshNotebook -and $parsed.sourceAdded -and $parsed.sourceVerified)}catch{$outer.error='HELPER_JSON_PARSE_FAILED: '+$_.Exception.Message}
  if(-not $outer.helperOk -and -not $outer.error){$outer.error='FRESH_HELPER_FAILED_OR_INCOMPLETE'}
}catch{$outer.error=$_.Exception.Message}
$outer.completedAt=(Get-Date).ToString('o');WriteReceipt $outer;$outer|ConvertTo-Json -Depth 40 -Compress
exit 0
