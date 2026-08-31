param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.1.0'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ReleaseRef='central-runner-readonly-bootstrap-v7'
$InstallerPath='notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/Install-CentralAppsScriptRunner.ps1'
$ExpectedInstallerBlob='896c06532a0ec0db0af445ce90a78c197a4a77c9'
$ExpectedSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'
$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'
$ReceiptName='AGENT_APPSCRIPT_BOOTSTRAP_V1_RESULT.json'
$BoundReceiptName='CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Work=Join-Path $Root 'central-appscript-lane'
$ReceiptPath=Join-Path $Root $ReceiptName
New-Item -ItemType Directory -Force -Path $Root,$Work|Out-Null

function FindCentral {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not$r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveResult($o){
  $j=$o|ConvertTo-Json -Depth 20
  $j|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
  try{$c=FindCentral;if($c){$rd=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $rd|Out-Null;$j|Set-Content -LiteralPath (Join-Path $rd $ReceiptName) -Encoding UTF8}}catch{}
}
function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
  $all=New-Object byte[]($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function GetBoundReceiptPath {
  $c=FindCentral;if(-not$c){return ''}
  $p=Join-Path (Join-Path $c 'Runtime_Readback') $BoundReceiptName
  if(Test-Path -LiteralPath $p -PathType Leaf){return $p}
  return ''
}
function BoundReceiptValid([string]$Path){
  if(-not$Path){return $false}
  try{
    $x=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
    return ($x.ok -eq $true -and [string]$x.mode -eq 'READ_ONLY' -and $x.mutationPerformed -eq $false -and [string]$x.projectTitle -eq 'WEBAPP_TEMPLATE_03' -and [string]$x.spreadsheetId -eq $ExpectedSpreadsheetId -and [string]$x.deploymentId -eq $ExpectedDeploymentId -and -not[string]::IsNullOrWhiteSpace([string]$x.scriptId))
  }catch{return $false}
}

$r=[ordered]@{ok=$false;action='AGENT_APPSCRIPT_BOOTSTRAP_V1';version=$Version;releaseRef=$ReleaseRef;installerBlob=$ExpectedInstallerBlob;existingClaspOnly=$true;newLoginAllowed=$false;newProjectAllowed=$false;newDeploymentAllowed=$false;newOAuthAllowed=$false;duplicateTaskAllowed=$false;stage='START';installerExitCode=$null;boundReceipt='';error='';startedAt=(Get-Date).ToString('o')}
try{
  $existingReceipt=GetBoundReceiptPath
  if(BoundReceiptValid $existingReceipt){
    $r.ok=$true;$r.stage='ALREADY_VERIFIED_READONLY';$r.boundReceipt=$existingReceipt
  }else{
    $clasp=Get-Command clasp.cmd -ErrorAction SilentlyContinue
    if(-not$clasp){$clasp=Get-Command clasp -ErrorAction SilentlyContinue}
    if(-not$clasp){throw 'EXISTING_CLASP_REQUIRED_NO_INSTALL_NO_LOGIN'}
    & $clasp.Source show-authorized-user --json *> $null
    if($LASTEXITCODE -ne 0){& $clasp.Source show-authorized-user *> $null;if($LASTEXITCODE -ne 0){throw 'EXISTING_CLASP_AUTH_REQUIRED_NO_LOGIN'}}

    $r.stage='FETCH_IMMUTABLE_INSTALLER'
    $headers=@{'User-Agent'='HomeDesign-AppScript-Lane';'Accept'='application/vnd.github+json'}
    $uri='https://api.github.com/repos/'+$Repo+'/contents/'+$InstallerPath+'?ref='+$ReleaseRef+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $meta=Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
    if(([string]$meta.sha).ToLowerInvariant() -ne $ExpectedInstallerBlob){throw 'IMMUTABLE_INSTALLER_BLOB_MISMATCH'}
    $installer=Join-Path $Work 'Install-CentralAppsScriptRunner.ps1'
    [IO.File]::WriteAllBytes($installer,[Convert]::FromBase64String(([string]$meta.content-replace'\s','')))
    if((GitBlobSha1 $installer).ToLowerInvariant() -ne $ExpectedInstallerBlob){throw 'LOCAL_INSTALLER_BLOB_MISMATCH'}

    $tokens=$null;$parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count -gt 0){throw ('INSTALLER_PARSE_FAIL:'+($parseErrors.Message -join '|'))}
    $installerText=Get-Content -Raw -LiteralPath $installer
    foreach($forbidden in @('clasp login','create-script','create-deployment','ScriptApp.newTrigger')){if($installerText -match [regex]::Escape($forbidden)){throw ('INSTALLER_FORBIDDEN_TOKEN:'+ $forbidden)}}

    $r.stage='RUN_IMMUTABLE_READONLY_INSTALLER'
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer -IntervalMinutes 5 -TaskName 'Central Apps Script Runner' 2>&1
    $r.installerExitCode=$LASTEXITCODE
    $r.installerOutput=(@($out)|Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw ('INSTALLER_EXIT_'+$LASTEXITCODE)}

    $r.stage='VERIFY_READONLY_RECEIPT'
    $bound=GetBoundReceiptPath
    if(-not(BoundReceiptValid $bound)){throw 'BOUND_READONLY_RECEIPT_MISSING_OR_INVALID_AFTER_INSTALL'}
    $r.boundReceipt=$bound
    $r.ok=$true;$r.stage='DONE'
  }
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');SaveResult $r}
$r|ConvertTo-Json -Depth 20 -Compress
if($r.ok){exit 0}else{exit 2}
