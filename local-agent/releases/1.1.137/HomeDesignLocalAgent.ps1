param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.137'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Ref='main'
$ChildPath='local-agent/governor/DiagnoseNotebookLMAutoPoll.ps1'
$ExpectedChildBlob='d035e37d8093a07737a7e7ada16e36e5959c4d9d'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$ReceiptName='AGENT_1.1.137_NOTEBOOKLM_RUNTIME_RESTART_RESULT.json'
$ReceiptPath=Join-Path $Root $ReceiptName
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlob([byte[]]$Bytes){
  $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0))
  $all=New-Object byte[] ($header.Length+$Bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($Bytes,0,$all,$header.Length,$Bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join'')}finally{$sha.Dispose()}
}
function FindCentral {
  $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $centralName),(Join-Path $d.Root ('My Drive\'+$centralName)),(Join-Path $d.Root ($myDriveKo+'\'+$centralName)),(Join-Path $d.Root ('Google Drive\'+$centralName)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
function SaveReceipt($o){
  $json=$o|ConvertTo-Json -Depth 40
  $json|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
  try{$central=FindCentral;if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dir $ReceiptName) -Encoding UTF8}}catch{}
}
function FindChrome {
  if(-not(Test-Path -LiteralPath $CftRoot -PathType Container)){return $null}
  return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
}
function OpenNotebookHome {
  $chrome=FindChrome
  if(-not$chrome){throw 'CHROME_FOR_TESTING_NOT_FOUND_AFTER_RECOVERY'}
  $args=@("--user-data-dir=$DedicatedUserData",'--profile-directory=Default','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9223','https://notebook.google.com/')
  Start-Process -FilePath $chrome.FullName -ArgumentList $args -WindowStyle Normal|Out-Null
}

$r=[ordered]@{ok=$false;action='NOTEBOOKLM_RUNTIME_RESTART_PROVEN_DIAGNOSTIC';version=$Version;startedAt=(Get-Date).ToString('o');stage='START';childBlob='';childExitCode=$null;childResult=$null;notebookHomeOpened=$false;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;extensionFilesChanged=$false;error=''}
try{
  $r.stage='FETCH_PINNED_DIAGNOSTIC'
  $uri='https://api.github.com/repos/'+$Repo+'/contents/'+$ChildPath+'?ref='+$Ref+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $meta=Invoke-RestMethod -Uri $uri -Headers @{'User-Agent'='HomeDesign-NotebookLM-Runtime-Recovery';'Accept'='application/vnd.github+json'} -TimeoutSec 30
  if(-not$meta.content){throw 'DIAGNOSTIC_CONTENT_MISSING'}
  $bytes=[Convert]::FromBase64String(([string]$meta.content-replace'\s',''))
  $blob=(GitBlob $bytes).ToLowerInvariant();$r.childBlob=$blob
  if($blob-ne$ExpectedChildBlob){throw ('DIAGNOSTIC_BLOB_MISMATCH:'+ $blob)}
  $tmp=Join-Path $Root 'DiagnoseNotebookLMAutoPoll.runtime-recovery.ps1'
  [IO.File]::WriteAllBytes($tmp,$bytes)

  $r.stage='RUN_PROVEN_NOTEBOOKLM_DIAGNOSTIC'
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tmp 2>&1
  $r.childExitCode=$LASTEXITCODE
  $last=(@($out)|Where-Object{$_-ne$null}|Select-Object -Last 1|Out-String).Trim()
  if($last){try{$r.childResult=$last|ConvertFrom-Json}catch{}}
  if($r.childExitCode-ne0){throw ('DIAGNOSTIC_EXIT_'+$r.childExitCode)}
  if(-not$r.childResult-or-not[bool]$r.childResult.ok){throw 'DIAGNOSTIC_RESULT_NOT_OK'}
  if(-not[bool]$r.childResult.serviceWorkerFound){throw 'NOTEBOOKLM_SERVICE_WORKER_NOT_FOUND'}
  if([int]$r.childResult.dedicatedAfter-lt1){throw 'DEDICATED_NOTEBOOKLM_CHROME_NOT_RUNNING'}

  $r.stage='OPEN_NOTEBOOKLM_HOME'
  OpenNotebookHome
  $r.notebookHomeOpened=$true
  Start-Sleep -Seconds 3
  try{$targets=@(Invoke-RestMethod -Uri 'http://127.0.0.1:9223/json/list' -TimeoutSec 3);if(-not(@($targets|Where-Object{$_.type-eq'page'-and($_.url-like'https://notebook.google.com/*'-or$_.url-like'https://notebooklm.google.com/*')}).Count-gt0)){throw 'NOTEBOOKLM_PAGE_TARGET_NOT_READY'}}catch{throw ('NOTEBOOKLM_PAGE_VERIFY_FAILED:'+ $_.Exception.Message)}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');SaveReceipt $r}
$r|ConvertTo-Json -Depth 40 -Compress
if($r.ok){exit 0}else{exit 2}
