param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.11-task203-role-split-force-receipt'
$SourceVersion='appscript-0.3.9-task203-role-split-transport-resilient'
$SourceBlob='9899e5eb5f4b67b3aa78d219d0bcab02a146f08b'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_TASK203_ROLE_SPLIT_FORCE_RECEIPT_0.3.11.json'
$ChildReceipt='APPSCRIPT_TASK203_ROLE_SPLIT_RESILIENT_0.3.9.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 120;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{(($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
$r=[ordered]@{ok=$false;action='READONLY_TASK203_ROLE_SPLIT_FORCE_RECEIPT_NUDGE';version=$Version;sourceVersion=$SourceVersion;sourceBlobExpected=$SourceBlob;sourceBlobActual='';replacementCount=0;childExitCode=$null;child=$null;stage='START';error='';readOnly=$true;pushPerformed=$false;newProject=$false;newDeployment=$false;newTrigger=$false;oauthChanged=$false;scopeChanged=$false;normalChromeTouched=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/'+$SourceVersion+'/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $wc=New-Object Net.WebClient
  try{$wc.Headers['User-Agent']='HomeDesign-Task203-ForceReceipt';$b=$wc.DownloadData($url)}finally{$wc.Dispose()}
  $r.sourceBlobActual=GitBlob $b
  if($r.sourceBlobActual-ne$SourceBlob){throw 'SOURCE_GIT_BLOB_SHA_MISMATCH'}
  $text=[Text.Encoding]::UTF8.GetString($b)
  $r.replacementCount=([regex]::Matches($text,"throw'")).Count
  if($r.replacementCount-lt1){throw 'EXPECTED_THROW_SYNTAX_PATTERN_NOT_FOUND'}
  $patched=$text.Replace("throw'","throw '")
  $tmp=Join-Path $env:TEMP ('task203-0.3.11-patched-'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'.ps1')
  Set-Content -LiteralPath $tmp -Value $patched -Encoding UTF8
  $r.stage='RUN_PATCHED_READONLY_CHILD'
  $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$tmp) -PassThru -WindowStyle Hidden
  if(-not$p.WaitForExit(900000)){try{$p.Kill()}catch{};throw 'PATCHED_CHILD_TIMEOUT'}
  $r.childExitCode=[int]$p.ExitCode
  $childPath=Join-Path $Root $ChildReceipt
  if(-not(Test-Path -LiteralPath $childPath)){throw 'PATCHED_CHILD_RECEIPT_MISSING'}
  $r.child=Get-Content -LiteralPath $childPath -Raw -Encoding UTF8|ConvertFrom-Json
  $r.ok=[bool]$r.child.ok
  $r.stage=if($r.ok){'DONE_CHILD_PASS'}else{'DONE_CHILD_FAIL'}
  if(-not$r.ok){$r.error='CHILD_ERROR: '+[string]$r.child.error}
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 120 -Compress
if($r.ok){exit 0}else{exit 2}
