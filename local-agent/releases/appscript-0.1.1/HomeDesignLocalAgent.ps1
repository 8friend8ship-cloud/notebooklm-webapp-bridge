param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.1.1'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ReadOnlyRef='c8ee143d6db5ab89c3f7795e00b33691471b0c8e'
$ReadOnlyPath='local-agent/releases/appscript-0.1.0/HomeDesignLocalAgent.ps1'
$ReadOnlyBlob='d8ed2414c89f04121c3b141e16ae9699ceb11fdf'
$BinderRef='598693dbbc16390b7fce57785b843bb0b71be2d3'
$BinderPath='notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/BindNotebookLMCentral10m.ps1'
$BinderBlob='47e81c44c976c53acb182a50a7aa23737430d81b'
$ExpectedSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'
$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'
$ExpectedScriptPrefix='1dmbf19qgN6Q-CwLY'
$ExpectedSourceCommit='54e13999aa9230475650da955b4bfcb53281af9e'
$ReadOnlyReceiptName='CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json'
$BindReceiptName='CENTRAL_APPS_SCRIPT_10M_BIND_WEBAPP_TEMPLATE_03_RESULT.json'
$LaneReceiptName='AGENT_APPSCRIPT_BIND_V2_RESULT.json'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Work=Join-Path $Root 'central-appscript-bind-lane'
$LaneReceipt=Join-Path $Root $LaneReceiptName
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
function RuntimeReadbackDir {
  $c=FindCentral
  if(-not$c){return ''}
  $rd=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $rd|Out-Null
  return $rd
}
function SaveResult($o){
  $j=$o|ConvertTo-Json -Depth 30
  $j|Set-Content -LiteralPath $LaneReceipt -Encoding UTF8
  try{$rd=RuntimeReadbackDir;if($rd){$j|Set-Content -LiteralPath (Join-Path $rd $LaneReceiptName) -Encoding UTF8}}catch{}
}
function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0));$all=New-Object byte[]($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function FetchPinned([string]$Ref,[string]$Path,[string]$ExpectedBlob,[string]$Dest){
  $headers=@{'User-Agent'='HomeDesign-AppScript-Bind-Lane';'Accept'='application/vnd.github+json'}
  $uri='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref='+$Ref+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $meta=Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
  if(([string]$meta.sha).ToLowerInvariant() -ne $ExpectedBlob){throw ('PINNED_BLOB_API_MISMATCH:'+ $Path)}
  [IO.File]::WriteAllBytes($Dest,[Convert]::FromBase64String(([string]$meta.content-replace'\s','')))
  if((GitBlobSha1 $Dest).ToLowerInvariant() -ne $ExpectedBlob){throw ('PINNED_BLOB_LOCAL_MISMATCH:'+ $Path)}
  $tokens=$null;$parseErrors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Dest,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count -gt 0){throw ('PINNED_SCRIPT_PARSE_FAIL:'+ $Path+':'+($parseErrors.Message -join '|'))}
}
function ReadOnlyReceiptPath {
  $rd=RuntimeReadbackDir;if(-not$rd){return ''}
  $p=Join-Path $rd $ReadOnlyReceiptName
  if(Test-Path -LiteralPath $p -PathType Leaf){return $p}
  return ''
}
function BindReceiptPath {
  $rd=RuntimeReadbackDir;if(-not$rd){return ''}
  $p=Join-Path $rd $BindReceiptName
  if(Test-Path -LiteralPath $p -PathType Leaf){return $p}
  return ''
}
function ValidReadOnly([string]$Path){
  if(-not$Path){return $false}
  try{
    $x=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
    $sid=[string]$x.scriptId
    return ($x.ok -eq $true -and [string]$x.mode -eq 'READ_ONLY' -and $x.mutationPerformed -eq $false -and [string]$x.projectTitle -eq 'WEBAPP_TEMPLATE_03' -and [string]$x.spreadsheetId -eq $ExpectedSpreadsheetId -and [string]$x.deploymentId -eq $ExpectedDeploymentId -and $sid.Length -ge 40 -and $sid.StartsWith($ExpectedScriptPrefix,[StringComparison]::Ordinal))
  }catch{return $false}
}
function ValidBind([string]$Path){
  if(-not$Path){return $false}
  try{
    $x=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
    $sid=[string]$x.scriptId
    return ($x.ok -eq $true -and [string]$x.action -eq 'NOTEBOOKLM_CENTRAL_10M_BIND' -and [string]$x.spreadsheetId -eq $ExpectedSpreadsheetId -and [string]$x.deploymentId -eq $ExpectedDeploymentId -and $sid.Length -ge 40 -and $sid.StartsWith($ExpectedScriptPrefix,[StringComparison]::Ordinal) -and [string]$x.sourceCommit -eq $ExpectedSourceCommit -and $x.deploymentInvariant -eq $true -and $x.sourceReadback -eq $true -and $x.moduleHashReadback -eq $true -and $x.newProjectCreated -eq $false -and $x.oauthChanged -eq $false -and $x.scopeChanged -eq $false -and $x.newDeployment -eq $false -and $x.newTrigger -eq $false -and [string]$x.mutationScope -eq 'EXISTING_BOUND_SCRIPT_SOURCE_ONLY')
  }catch{return $false}
}
function RunBounded([string]$Path,[string[]]$Args,[int]$TimeoutSeconds){
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $quoted=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$Path+'"'))+@($Args)
  $psi.Arguments=($quoted -join ' ')
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start()
  $stdoutTask=$p.StandardOutput.ReadToEndAsync();$stderrTask=$p.StandardError.ReadToEndAsync()
  if(-not$p.WaitForExit($TimeoutSeconds*1000)){try{& taskkill.exe /PID ([int]$p.Id) /T /F 2>$null|Out-Null}catch{};return [ordered]@{exitCode=124;stdout='';stderr='TIMEOUT'}}
  return [ordered]@{exitCode=[int]$p.ExitCode;stdout=$stdoutTask.Result;stderr=$stderrTask.Result}
}

$r=[ordered]@{ok=$false;action='AGENT_APPSCRIPT_BIND_V2';version=$Version;readOnlyRef=$ReadOnlyRef;readOnlyBlob=$ReadOnlyBlob;binderRef=$BinderRef;binderBlob=$BinderBlob;existingClaspOnly=$true;newLoginAllowed=$false;newProjectAllowed=$false;newDeploymentAllowed=$false;newTriggerAllowed=$false;oauthChangeAllowed=$false;stage='START';readOnlyReceipt='';bindReceipt='';readOnlyExitCode=$null;binderExitCode=$null;error='';startedAt=(Get-Date).ToString('o')}
try{
  $existingBind=BindReceiptPath
  if(ValidBind $existingBind){
    $r.ok=$true;$r.stage='ALREADY_BOUND_VERIFIED';$r.bindReceipt=$existingBind
  }else{
    $ro=ReadOnlyReceiptPath
    if(-not(ValidReadOnly $ro)){
      $r.stage='RUN_READONLY_STAGE'
      $roScript=Join-Path $Work 'HomeDesignLocalAgent-appscript-0.1.0.ps1'
      FetchPinned $ReadOnlyRef $ReadOnlyPath $ReadOnlyBlob $roScript
      $roRun=RunBounded $roScript @() 420
      $r.readOnlyExitCode=$roRun.exitCode;$r.readOnlyOutput=([string]$roRun.stdout).Trim();$r.readOnlyError=([string]$roRun.stderr).Trim()
      if($roRun.exitCode -ne 0){throw ('READONLY_STAGE_EXIT_'+$roRun.exitCode)}
      $ro=ReadOnlyReceiptPath
    }
    if(-not(ValidReadOnly $ro)){throw 'READONLY_RECEIPT_INVALID_AFTER_STAGE'}
    $r.readOnlyReceipt=$ro

    $r.stage='RUN_GATED_10M_BIND'
    $binder=Join-Path $Work 'BindNotebookLMCentral10m.ps1'
    FetchPinned $BinderRef $BinderPath $BinderBlob $binder
    $binderText=Get-Content -Raw -LiteralPath $binder
    foreach($pattern in @('&\s+\$clasp\.Source\s+login\b','&\s+\$clasp\.Source\s+create-script\b','&\s+\$clasp\.Source\s+create-deployment\b','&\s+\$clasp\.Source\s+(?:deploy|redeploy)\b','ScriptApp\.newTrigger\s*\(')){if($binderText -match $pattern){throw ('BINDER_FORBIDDEN_PATTERN:'+ $pattern)}}
    $bindRun=RunBounded $binder @('-ReceiptPath',('"'+$ro+'"')) 420
    $r.binderExitCode=$bindRun.exitCode;$r.binderOutput=([string]$bindRun.stdout).Trim();$r.binderError=([string]$bindRun.stderr).Trim()
    if($bindRun.exitCode -ne 0){throw ('BINDER_EXIT_'+$bindRun.exitCode)}
    $bind=BindReceiptPath
    if(-not(ValidBind $bind)){throw 'BIND_RECEIPT_INVALID_AFTER_BIND'}
    $r.bindReceipt=$bind
    $r.ok=$true;$r.stage='DONE_BIND_RECEIPT_VERIFIED'
  }
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');SaveResult $r}
$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 2}
