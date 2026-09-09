param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.15-task203-ps51-envfix-wrapper'
$SourceVersion='appscript-0.3.13-task203-clone-auth-proof-force-retry'
$SourceBlob='94b93e25ec04d4299c14f13b7d29a76c27109626'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_TASK203_PS51_ENVFIX_0.3.15.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 50;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function GitBlob([byte[]]$b){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{(($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
$r=[ordered]@{ok=$false;action='TASK203_PS51_ENVFIX_WRAPPER';version=$Version;sourceVersion=$SourceVersion;sourceBlobExpected=$SourceBlob;sourceBlobActual='';depthReplacementCount=0;comSpecReplacementCount=0;parseErrors=0;childExitCode=$null;innerReceiptExists=$false;innerOk=$false;readOnly=$true;newOAuth=$false;newProject=$false;newDeployment=$false;newTrigger=$false;globalExecutionPolicyChanged=$false;stage='START';error='';startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/'+$SourceVersion+'/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-AppScript-PS51-Compat';$b=$wc.DownloadData($url)}finally{$wc.Dispose()}
  $r.sourceBlobActual=GitBlob $b;if($r.sourceBlobActual-ne$SourceBlob){throw 'SOURCE_GIT_BLOB_SHA_MISMATCH'}
  $text=[Text.Encoding]::UTF8.GetString($b)
  $r.depthReplacementCount=([regex]::Matches($text,[regex]::Escape('-Depth 120'))).Count;if($r.depthReplacementCount-ne2){throw 'DEPTH120_TARGET_COUNT_MISMATCH'}
  $old='$psi.FileName=$env:ComSpec;';$r.comSpecReplacementCount=([regex]::Matches($text,[regex]::Escape($old))).Count;if($r.comSpecReplacementCount-ne1){throw 'COMSPEC_TARGET_COUNT_MISMATCH'}
  $text=$text.Replace('-Depth 120','-Depth 100')
  $new='$cmdExe=[string]$env:ComSpec;if(-not$cmdExe){$cmdExe=(Get-Command ''cmd.exe'' -ErrorAction Stop).Source};$psi.FileName=$cmdExe;'
  $text=$text.Replace($old,$new)
  $tmp=Join-Path $env:TEMP ('appscript-0.3.15-inner-'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'.ps1');Set-Content -LiteralPath $tmp -Value $text -Encoding UTF8
  $e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile($tmp,[ref]$t,[ref]$e)|Out-Null;$r.parseErrors=@($e).Count;if($r.parseErrors-ne0){throw 'PATCHED_INNER_PARSE_FAILED'}
  $r.stage='RUN_INNER';$p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$tmp) -PassThru -WindowStyle Hidden
  if(-not$p.WaitForExit(600000)){try{$p.Kill()}catch{};throw 'PATCHED_INNER_TIMEOUT'};$r.childExitCode=[int]$p.ExitCode
  $inner=Join-Path $Root 'APPSCRIPT_TASK203_CLONE_AUTH_PROOF_FORCE_0.3.13.json';$r.innerReceiptExists=Test-Path -LiteralPath $inner
  if($r.innerReceiptExists){$j=Get-Content -LiteralPath $inner -Raw -Encoding UTF8|ConvertFrom-Json;$r.innerOk=[bool]$j.ok}
  $r.ok=($r.childExitCode-eq0-and$r.innerReceiptExists-and$r.innerOk);$r.stage=if($r.ok){'DONE_PASS'}else{'DONE_INNER_FAIL'}
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 50 -Compress
if($r.ok){exit 0}else{exit 2}
