param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.154-image-task203-central-factory-v14-immediate-tablet-discoveryfix'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$BasePath='local-agent/releases/1.1.152-image-task203-central-factory-v14/HomeDesignLocalAgent.ps1'
$BaseBlob='d1ee150032ea984032111eb6752c0aa46b3f7e43'
$OldAnalyzer='a31f97cd41c2256dbacd3ad426037743090a11cc'
$NewAnalyzer='3f0265aeb5242bdf245ae93039a4474eb30a186b'
$OldDiscoveryPath='local-agent/releases/appscript-0.3.0-webapp05-history-exactdeployment-discovery/HomeDesignLocalAgent.ps1'
$NewDiscoveryPath='local-agent/releases/appscript-0.3.1-webapp05-history-exactdeployment-discovery-argsfix/HomeDesignLocalAgent.ps1'
$OldDiscoveryBlob='0d168954a5755b0556605dae121ab19adedeb3fe'
$NewDiscoveryBlob='9793675f4679e0edbf55a6a2d8d225a6b7a92129'
$OldVersion='1.1.152-image-task203-central-factory-v14'
$OldReceipt='IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.152.json'
$NewReceipt='IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.154.json'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){try{$j=$o|ConvertTo-Json -Depth 30;$p=Join-Path $Root 'IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.154_WRAPPER.json';$j|Set-Content -LiteralPath $p -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'IMAGE_TASK203_CENTRAL_FACTORY_V14_1.1.154_WRAPPER.json') -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;action='TASK203_1.1.154_DISCOVERY_ARGS_FIX_WRAPPER';version=$Version;stage='START';baseBlob=$BaseBlob;analyzerCommit=$NewAnalyzer;discoveryBlob=$NewDiscoveryBlob;error='';startedAt=(Get-Date).ToString('o');completedAt=''}
try{
  $api='https://api.github.com/repos/'+$Repo+'/contents/'+$BasePath+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $x=Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='HomeDesign-Task203-1.1.154';'Accept'='application/vnd.github+json'} -TimeoutSec 30
  if(([string]$x.sha).ToLowerInvariant()-ne$BaseBlob){throw('BASE_BLOB_MISMATCH actual='+[string]$x.sha)}
  $base=Join-Path $Root 'TASK203_1.1.152_BASE_FOR_154.ps1';[IO.File]::WriteAllBytes($base,[Convert]::FromBase64String(([string]$x.content-replace'\s','')))
  if((GitBlobSha1 $base).ToLowerInvariant()-ne$BaseBlob){throw 'BASE_LOCAL_BLOB_MISMATCH'}
  $text=Get-Content -LiteralPath $base -Raw -Encoding UTF8
  foreach($need in @($OldAnalyzer,$OldDiscoveryPath,$OldDiscoveryBlob,$OldVersion,$OldReceipt)){if($text-notlike ('*'+$need+'*')){throw('PATCH_TOKEN_MISSING:'+ $need)}}
  $text=$text.Replace($OldAnalyzer,$NewAnalyzer).Replace($OldDiscoveryPath,$NewDiscoveryPath).Replace($OldDiscoveryBlob,$NewDiscoveryBlob).Replace($OldVersion,$Version).Replace($OldReceipt,$NewReceipt)
  $patched=Join-Path $Root 'TASK203_1.1.154_PATCHED_RUNNER.ps1';Set-Content -LiteralPath $patched -Value $text -Encoding UTF8
  $verify=Get-Content -LiteralPath $patched -Raw -Encoding UTF8
  if($verify-notlike ('*'+$NewAnalyzer+'*')-or$verify-notlike('*'+$NewDiscoveryBlob+'*')-or$verify-notlike('*'+$NewDiscoveryPath+'*')){throw 'PATCH_VERIFY_FAILED'}
  $r.stage='EXECUTE_PATCHED_1.1.154'
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $patched
  $rc=$LASTEXITCODE;if($rc-ne0){throw('PATCHED_RUNNER_EXIT_'+$rc)}
  $result=Join-Path $Root $NewReceipt;if(-not(Test-Path -LiteralPath $result -PathType Leaf)){throw '1.1.154_RESULT_RECEIPT_MISSING'}
  $obj=Get-Content -LiteralPath $result -Raw -Encoding UTF8|ConvertFrom-Json
  if((-not[bool]$obj.ok)-or([string]$obj.analyzerCommit).ToLowerInvariant()-ne$NewAnalyzer-or-not[bool]$obj.sourceReadback){throw('1.1.154_RESULT_NOT_VERIFIED stage='+[string]$obj.stage+' error='+[string]$obj.error)}
  $r.ok=$true;$r.stage='DONE_BOUND_SOURCE_SYNC_VERIFIED_WAIT_FACTORY_WAKE';$r.scriptId=[string]$obj.scriptId
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 30 -Compress
if($r.ok){exit 0}else{exit 2}
