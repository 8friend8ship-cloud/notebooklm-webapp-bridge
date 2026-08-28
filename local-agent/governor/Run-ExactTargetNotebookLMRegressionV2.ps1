param(
  [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$DebugPort=9231
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Launcher=Join-Path $env:TEMP ('ManagedExtensionExactTargetLauncherV2_'+[guid]::NewGuid().ToString('N')+'.ps1')
$Url='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/ManagedExtensionExactTargetLauncherV2.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$Expected='6ea89f678d4716e7ed39163e6bb0634e78eb750c'
function GitBlob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function Find-Central {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Launcher -TimeoutSec 30
$Actual=(GitBlob $Launcher).ToLowerInvariant()
if($Actual -ne $Expected){Remove-Item $Launcher -Force -ErrorAction SilentlyContinue;throw ('EXACT_LAUNCHER_V2_SHA_MISMATCH actual='+$Actual+' expected='+$Expected)}
function Run-One([int]$N){
  $sentinel='CENTRAL_NLM_EXACT_V2_X'+$N+'_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Launcher -Service NOTEBOOKLM -TargetUrl $NotebookUrl -RemoteDebuggingPort ($DebugPort+$N-1) -TimeoutSeconds 45 -RestartDedicatedChrome -ProbeInput -Sentinel $sentinel 2>&1
  $exit=$LASTEXITCODE;$text=($out|Out-String).Trim();$obj=$null
  try{$obj=(($text -split "`r?`n")[-1]|ConvertFrom-Json)}catch{}
  $gate=[bool]($exit -eq 0 -and $obj -and $obj.ok -and $obj.targetContextVerified -and $obj.extensionContextActive -and $obj.inputFound -and $obj.inputVerified -and $obj.inputRestored -and $obj.normalChromeUntouched -and -not $obj.generateClicked -and -not $obj.creditSpend)
  return [pscustomobject]@{run=$N;exit=$exit;gate=$gate;sentinel=$sentinel;text=$text;result=$obj}
}
$r1=Run-One 1
$r2=$null
if($r1.gate){$r2=Run-One 2}
$ok=[bool]($r1.gate -and $r2 -and $r2.gate)
$result=[ordered]@{
  ok=$ok;action='NOTEBOOKLM_EXACT_TARGET_X2_REGRESSION_V2';launcherSha=$Expected;targetUrl=$NotebookUrl;run1=$r1;run2=$r2;
  exactTargetRequired=$true;contentScriptMarkerRequired=$true;inputReadbackRestoreRequired=$true;normalChromeRequiredUntouched=$true;
  generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')
}
$central=Find-Central
if($central){$dir=Join-Path $central 'Runtime_Readback\Chrome_Exact_Target';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$result|ConvertTo-Json -Depth 80|Set-Content -LiteralPath (Join-Path $dir 'NOTEBOOKLM_EXACT_TARGET_X2_REGRESSION_V2.json') -Encoding UTF8}
Remove-Item $Launcher -Force -ErrorAction SilentlyContinue
$result|ConvertTo-Json -Depth 80 -Compress
if($ok){exit 0}else{exit 2}
