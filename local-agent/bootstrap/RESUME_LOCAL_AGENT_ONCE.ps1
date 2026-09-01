param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$CoreCommit='57939ad6809b2a8402880e8d760b1d09b13bbdba'
$CoreExpectedSha='30c5f438e942979b2013c1410a7ca0cdcd9ee27a'
$Core=Join-Path $Root 'RESUME_LOCAL_AGENT_CORE_PINNED_20260831.ps1'
$ImageRecovery=Join-Path $Root 'IMAGE_LANE_CURRENT.ps1'
$ImageHookState=Join-Path $Root 'AUTO_RESUME_IMAGE_HOOK_STATE.json'
$ImageHookReceipt='AUTO_RESUME_IMAGE_HOOK_LATEST.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function RawUrl([string]$Path){'https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
function RawText([string]$Path){(Invoke-WebRequest -UseBasicParsing -Uri (RawUrl $Path) -Headers @{'User-Agent'='HomeDesign-Resume-Image-Hook'} -TimeoutSec 30).Content}
function RawFileVerified([string]$Path,[string]$Dest,[string]$Expected){$tmp=$Dest+'.download';Invoke-WebRequest -UseBasicParsing -Uri (RawUrl $Path) -Headers @{'User-Agent'='HomeDesign-Resume-Image-Hook'} -OutFile $tmp -TimeoutSec 30;$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($Expected -and $actual-ne$Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('IMAGE_RAW_SHA_MISMATCH path='+$Path+' actual='+$actual+' expected='+$Expected)};Move-Item $tmp $Dest -Force;return $actual}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveHook($o){$j=$o|ConvertTo-Json -Depth 40;$j|Set-Content -LiteralPath (Join-Path $Root $ImageHookReceipt) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $ImageHookReceipt) -Encoding UTF8}}
function ExistingImagePass([string]$ReceiptName){if(-not$ReceiptName){$ReceiptName='IMAGE_AGENT_CONTENTOS_TASK203_DIRECT.json'};$c=FindCentral;if($c){$p=Join-Path (Join-Path $c 'Runtime_Readback') $ReceiptName;if(Test-Path -LiteralPath $p -PathType Leaf){try{$j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json;return [bool]$j.ok}catch{}}};$p=Join-Path $Root $ReceiptName;if(Test-Path -LiteralPath $p -PathType Leaf){try{$j=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json;return [bool]$j.ok}catch{}};return $false}
function RunBounded([string]$Path,[int]$Seconds){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Path`"";$p=[Diagnostics.Process]::Start($psi);if(-not$p.WaitForExit($Seconds*1000)){try{& taskkill.exe /PID ([int]$p.Id) /T /F 2>$null|Out-Null}catch{};return 124};try{return [int]$p.ExitCode}catch{return 1}}

# Preserve the previously verified normal Resume behavior exactly.
$coreUrl='https://raw.githubusercontent.com/'+$Repo+'/'+$CoreCommit+'/local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$coreTmp=$Core+'.download'
try{Invoke-WebRequest -UseBasicParsing -Uri $coreUrl -OutFile $coreTmp -TimeoutSec 30;$coreSha=(GitBlobSha1 $coreTmp).ToLowerInvariant();if($coreSha-ne$CoreExpectedSha){throw('CORE_SHA_MISMATCH:'+ $coreSha)};Move-Item $coreTmp $Core -Force;$coreExit=RunBounded $Core 420}catch{$coreExit=3;$coreError=$_.Exception.Message}

$hook=[ordered]@{ok=$false;action='AUTO_RESUME_IMAGE_TASK203_HOOK';version='V3_VERSION_AWARE_RETRY_20260901';coreCommit=$CoreCommit;coreExit=[int]$coreExit;imageEnabled=$false;imageVersion='';imageFetchMode='RAW_MAIN_SHA_VERIFIED';alreadyPassed=$false;attempt=0;maxAttempts=2;stateImageVersion='';attemptResetForNewVersion=$false;imageExit=$null;ranImage=$false;startedAt=(Get-Date).ToString('o');completedAt='';error=''}
try{
  $m=(RawText 'local-agent/stable/image.json')|ConvertFrom-Json
  $hook.imageEnabled=[bool]$m.enabled
  $hook.imageVersion=[string]$m.version
  $receiptName=[string]$m.resultReceipt;if(-not$receiptName){$receiptName='IMAGE_AGENT_CONTENTOS_TASK203_DIRECT.json'}
  if(-not$hook.imageEnabled){$hook.ok=$true;$hook.error='IMAGE_LANE_DISABLED'}
  elseif(ExistingImagePass $receiptName){$hook.ok=$true;$hook.alreadyPassed=$true}
  else{
    $attempt=0;$stateVersion=''
    if(Test-Path -LiteralPath $ImageHookState){try{$s=Get-Content -LiteralPath $ImageHookState -Raw -Encoding UTF8|ConvertFrom-Json;$attempt=[int]$s.attempt;$stateVersion=[string]$s.imageVersion}catch{}}
    $hook.stateImageVersion=$stateVersion
    if($stateVersion -ne [string]$m.version){$attempt=0;$hook.attemptResetForNewVersion=$true}
    $hook.attempt=$attempt
    if($attempt-ge2){$hook.error='MAX_2_REACHED_DIAGNOSTIC_HOLD'}
    else{
      $expected=([string]$m.gitBlobSha1).ToLowerInvariant()
      $releasePath='local-agent/releases/'+[string]$m.version+'/'+[string]$m.file
      [void](RawFileVerified $releasePath $ImageRecovery $expected)
      $attempt++;$hook.attempt=$attempt;[ordered]@{attempt=$attempt;imageVersion=[string]$m.version;at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $ImageHookState -Encoding UTF8
      $timeout=900;if($m.maxCycleSeconds){$timeout=[Math]::Max(180,[Math]::Min(1800,[int]$m.maxCycleSeconds))}
      $hook.ranImage=$true;$hook.imageExit=RunBounded $ImageRecovery $timeout;$hook.ok=ExistingImagePass $receiptName
      if(-not$hook.ok){$hook.error='IMAGE_TASK203_RESULT_NOT_PASS'}
    }
  }
}catch{$hook.error=$_.Exception.Message}
$hook.completedAt=(Get-Date).ToString('o');SaveHook $hook
# IMAGE hook is independent and must never destabilize the normal Resume lane.
exit $coreExit
