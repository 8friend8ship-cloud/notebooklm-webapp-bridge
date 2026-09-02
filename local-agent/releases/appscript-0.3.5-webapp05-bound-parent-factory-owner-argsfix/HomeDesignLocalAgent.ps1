param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.5-webapp05-bound-parent-factory-owner-argsfix'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$SourcePath='local-agent/releases/appscript-0.3.4-webapp05-bound-parent-factory-owner-inspector/HomeDesignLocalAgent.ps1'
$SourceExpected='17e3d70b30ea5a88f8a15e1aefe63ad41fab8f1a'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='APPSCRIPT_WEBAPP05_BOUND_PARENT_FACTORY_OWNER_INSPECTOR_0.3.5.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 50;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function RawBytes([string]$Path){$u='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-AppScript-ArgsFix-0.3.5';return $wc.DownloadData($u)}finally{$wc.Dispose()}}
$r=[ordered]@{ok=$false;action='READONLY_BOUND_FACTORY_OWNER_ARGS_COLLISION_FIX_AND_RUN';version=$Version;sourcePath=$SourcePath;sourceExpected=$SourceExpected;sourceActual='';argsTokenCountBefore=0;argsTokenCountAfter=0;innerExit=$null;innerOutput='';patchedFile='';stage='START';error='';readOnly=$true;newProject=$false;newDeployment=$false;newTrigger=$false;pushPerformed=$false;oauthChanged=$false;scopeChanged=$false;normalChromeTouched=$false;startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $r.stage='FETCH_VERIFY_0.3.4'
  $b=RawBytes $SourcePath;if(-not$b-or$b.Length-eq0){throw 'SOURCE_RAW_EMPTY'}
  $r.sourceActual=(GitBlobSha1Bytes $b).ToLowerInvariant();if($r.sourceActual-ne$SourceExpected){throw ('SOURCE_BLOB_MISMATCH:'+ $r.sourceActual)}
  $text=[Text.Encoding]::UTF8.GetString($b)
  $r.argsTokenCountBefore=([regex]::Matches($text,'\$Args\b')).Count
  if($r.argsTokenCountBefore-lt1){throw 'ARGS_COLLISION_TOKEN_NOT_FOUND'}
  $text=[regex]::Replace($text,'\$Args\b','$ClaspArgs')
  $text=$text.Replace("appscript-0.3.4-webapp05-bound-parent-factory-owner-inspector","appscript-0.3.5-webapp05-bound-parent-factory-owner-argsfix")
  $text=$text.Replace("APPSCRIPT_WEBAPP05_BOUND_PARENT_FACTORY_OWNER_INSPECTOR_0.3.4.json","APPSCRIPT_WEBAPP05_BOUND_PARENT_FACTORY_OWNER_INSPECTOR_0.3.5.json")
  $r.argsTokenCountAfter=([regex]::Matches($text,'\$Args\b')).Count
  if($r.argsTokenCountAfter-ne0){throw 'ARGS_COLLISION_PATCH_INCOMPLETE'}
  $tmp=Join-Path $Root 'HomeDesignLocalAgent-appscript-0.3.5-patched.ps1';$text|Set-Content -LiteralPath $tmp -Encoding UTF8;$r.patchedFile=$tmp
  $r.stage='RUN_PATCHED_READONLY_INSPECTOR'
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$tmp+'"';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $p=[Diagnostics.Process]::Start($psi);if(-not$p.WaitForExit(300000)){try{$p.Kill()}catch{};throw 'PATCHED_INSPECTOR_TIMEOUT'}
  $r.innerExit=[int]$p.ExitCode;$r.innerOutput=($p.StandardOutput.ReadToEnd()+$p.StandardError.ReadToEnd()).Trim()
  if($r.innerExit-ne0){throw ('PATCHED_INSPECTOR_EXIT_'+$r.innerExit)}
  $r.ok=$true;$r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 50 -Compress
if($r.ok){exit 0}else{exit 2}
