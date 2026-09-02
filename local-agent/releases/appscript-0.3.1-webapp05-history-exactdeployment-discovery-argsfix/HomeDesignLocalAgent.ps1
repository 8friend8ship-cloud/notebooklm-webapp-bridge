param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.1-webapp05-history-exactdeployment-discovery-argsfix'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$BasePath='local-agent/releases/appscript-0.3.0-webapp05-history-exactdeployment-discovery/HomeDesignLocalAgent.ps1'
$BaseBlob='0d168954a5755b0556605dae121ab19adedeb3fe'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$WrapperReceipt='APPSCRIPT_DISCOVER_WEBAPP_TEMPLATE_05_ARGSFIX_0.3.1_WRAPPER.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''
}
function Save($o){try{$j=$o|ConvertTo-Json -Depth 20;$j|Set-Content -LiteralPath (Join-Path $Root $WrapperReceipt) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $WrapperReceipt) -Encoding UTF8}}catch{}}

$r=[ordered]@{ok=$false;action='DISCOVERY_ARGS_AUTOMATIC_VARIABLE_FIX';version=$Version;stage='START';baseBlob=$BaseBlob;patchedOccurrences=0;error='';startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $api='https://api.github.com/repos/'+$Repo+'/contents/'+$BasePath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $x=Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='HomeDesign-AppScript-Discovery-0.3.1';'Accept'='application/vnd.github+json'} -TimeoutSec 30
  if(([string]$x.sha).ToLowerInvariant()-ne$BaseBlob){throw('BASE_BLOB_MISMATCH actual='+[string]$x.sha)}
  $base=Join-Path $Root 'APPSCRIPT_DISCOVERY_0.3.0_BASE.ps1';[IO.File]::WriteAllBytes($base,[Convert]::FromBase64String(([string]$x.content-replace'\s','')))
  if((GitBlobSha1 $base).ToLowerInvariant()-ne$BaseBlob){throw 'BASE_LOCAL_BLOB_MISMATCH'}
  $text=Get-Content -LiteralPath $base -Raw -Encoding UTF8
  $count=([regex]::Matches($text,'\$Args')).Count
  if($count-lt2){throw('ARGS_COLLISION_PATTERN_NOT_FOUND count='+$count)}
  $patched=$text.Replace('$Args','$ClaspArgs')
  if($patched-match '\$Args'){throw 'ARGS_COLLISION_REMAINS'}
  if($patched-notmatch 'RunClasp\(\[string\]\$Clasp,\[string\[\]\]\$ClaspArgs'){throw 'PATCHED_RUNCLASP_SIGNATURE_MISSING'}
  $r.patchedOccurrences=$count
  $file=Join-Path $Root 'APPSCRIPT_DISCOVERY_0.3.1_PATCHED.ps1';Set-Content -LiteralPath $file -Value $patched -Encoding UTF8
  $r.stage='EXECUTE_PATCHED_DISCOVERY'
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file
  $rc=$LASTEXITCODE
  if($rc-ne0){throw('PATCHED_DISCOVERY_EXIT_'+$rc)}
  $receipt=Join-Path $Root 'APPSCRIPT_DISCOVER_WEBAPP_TEMPLATE_05_BY_HISTORY_EXACT_DEPLOYMENT_0.3.0.json'
  if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){throw 'DISCOVERY_RECEIPT_MISSING'}
  $obj=Get-Content -LiteralPath $receipt -Raw -Encoding UTF8|ConvertFrom-Json
  if(-not[bool]$obj.ok-or-not[string]$obj.scriptId){throw('DISCOVERY_RESULT_NOT_PASS error='+[string]$obj.error)}
  $r.ok=$true;$r.stage='DONE';$r.scriptId=[string]$obj.scriptId
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 20 -Compress
if($r.ok){exit 0}else{exit 2}
