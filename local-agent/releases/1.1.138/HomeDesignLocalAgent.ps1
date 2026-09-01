param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.138'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$PinnedParentPath='local-agent/releases/1.1.137/HomeDesignLocalAgent.ps1'
$PinnedParentBlob='8a5ebfd07649d6d18f739fc46b0c67a114d9cdf2'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$ReceiptName='AGENT_1.1.138_NOTEBOOKLM_FRONT_CONSENT_LOOP_BYPASS_RESULT.json'
$ReceiptPath=Join-Path $Root $ReceiptName
$Cdp='http://127.0.0.1:9223'
$FrontPrefix='https://notebooklm-webapp-bridge.vercel.app/'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlob([byte[]]$Bytes){
  $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0))
  $all=New-Object byte[] ($header.Length+$Bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($Bytes,0,$all,$header.Length,$Bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join'')}finally{$sha.Dispose()}
}
function FindCentral{
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $centralName),(Join-Path $d.Root ('My Drive\'+$centralName)),(Join-Path $d.Root ($myDriveKo+'\'+$centralName)),(Join-Path $d.Root ('Google Drive\'+$centralName)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveReceipt($o){
  $json=$o|ConvertTo-Json -Depth 30
  $json|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
  try{
    $central=FindCentral
    if($central){
      $dir=Join-Path $central 'Runtime_Readback'
      New-Item -ItemType Directory -Force -Path $dir|Out-Null
      $json|Set-Content -LiteralPath (Join-Path $dir $ReceiptName) -Encoding UTF8
    }
  }catch{}
}
function Targets{ return @(Invoke-RestMethod -Uri ($Cdp+'/json/list') -TimeoutSec 5) }
function IsNotebookPage($t){ return ($t.type-eq'page' -and ($t.url-like'https://notebook.google.com/*' -or $t.url-like'https://notebooklm.google.com/*')) }
function IsFrontPage($t){ return ($t.type-eq'page' -and $t.url-like($FrontPrefix+'*')) }

$r=[ordered]@{
  ok=$false;action='NOTEBOOKLM_FRONT_CONSENT_LOOP_BYPASS';version=$Version;startedAt=(Get-Date).ToString('o');stage='START';
  parentBlob='';parentExitCode=$null;frontTabsBefore=0;frontTabsClosed=0;frontTabsRemaining=0;notebookTargetBefore=$false;notebookTargetAfter=$false;
  normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;extensionFilesChanged=$false;vercelDeploymentChanged=$false;error=''
}
try{
  $r.stage='RUN_PINNED_1_1_137_RECOVERY'
  $uri='https://api.github.com/repos/'+$Repo+'/contents/'+$PinnedParentPath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $meta=Invoke-RestMethod -Uri $uri -Headers @{'User-Agent'='HomeDesign-NotebookLM-Consent-Loop-Bypass';'Accept'='application/vnd.github+json'} -TimeoutSec 30
  if(-not$meta.content){throw 'PARENT_CONTENT_MISSING'}
  $bytes=[Convert]::FromBase64String(([string]$meta.content-replace'\s',''))
  $blob=(GitBlob $bytes).ToLowerInvariant();$r.parentBlob=$blob
  if($blob-ne$PinnedParentBlob){throw ('PARENT_BLOB_MISMATCH:'+ $blob)}
  $tmp=Join-Path $Root 'HomeDesignLocalAgent-1.1.137-consent-bypass-parent.ps1'
  [IO.File]::WriteAllBytes($tmp,$bytes)
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp | Out-Null
  $r.parentExitCode=$LASTEXITCODE
  if($r.parentExitCode-ne0){throw ('PARENT_1_1_137_EXIT_'+$r.parentExitCode)}

  $r.stage='CLOSE_CONTROL_CENTER_FRONT_ONLY'
  Start-Sleep -Seconds 2
  $targets=Targets
  $r.notebookTargetBefore=[bool](@($targets|Where-Object{IsNotebookPage $_}).Count-gt0)
  if(-not$r.notebookTargetBefore){throw 'NOTEBOOKLM_TARGET_MISSING_BEFORE_FRONT_CLOSE'}
  $front=@($targets|Where-Object{IsFrontPage $_})
  $r.frontTabsBefore=$front.Count
  foreach($t in $front){
    $id=[string]$t.id
    if(-not$id){continue}
    try{
      Invoke-RestMethod -Uri ($Cdp+'/json/close/'+[Uri]::EscapeDataString($id)) -TimeoutSec 5 | Out-Null
      $r.frontTabsClosed++
    }catch{}
  }

  Start-Sleep -Seconds 2
  $after=Targets
  $r.frontTabsRemaining=@($after|Where-Object{IsFrontPage $_}).Count
  $r.notebookTargetAfter=[bool](@($after|Where-Object{IsNotebookPage $_}).Count-gt0)
  if($r.frontTabsRemaining-ne0){throw ('CONTROL_CENTER_FRONT_STILL_OPEN:'+ $r.frontTabsRemaining)}
  if(-not$r.notebookTargetAfter){throw 'NOTEBOOKLM_TARGET_LOST_AFTER_FRONT_CLOSE'}
  $r.ok=$true;$r.stage='DONE'
}catch{
  $r.error=$_.Exception.Message;$r.stage='ERROR'
}finally{
  $r.completedAt=(Get-Date).ToString('o');SaveReceipt $r
}
$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 2}
