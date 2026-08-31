param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Version='IMAGE_CONTRACT_RECOVERY_V1_20260831'
$PinnedVersion='1.1.71'
$PinnedSha='49d4192a68e75c08598cc721c0d990bb573c97e0'
$TaskId='LOCAL_CHATGPT_IMAGE_MANIFEST_CAPTURE_20260829_1604_01'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Agent=Join-Path $Root 'HomeDesignLocalAgent-image-contract-1.1.71.ps1'
$ReceiptName='IMAGE_CONTRACT_RECOVERY_V1.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path)
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function FindCentral{
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
function Save($o){
  $json=$o|ConvertTo-Json -Depth 60
  $json|Set-Content -LiteralPath (Join-Path $Root $ReceiptName) -Encoding UTF8
  $central=FindCentral
  if($central){
    $d=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null
    $json|Set-Content -LiteralPath (Join-Path $d $ReceiptName) -Encoding UTF8
  }
}
function RunBounded([string]$Path,[int]$Seconds=330){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Path`""
  $p=[Diagnostics.Process]::Start($psi)
  if(-not$p.WaitForExit($Seconds*1000)){
    try{& taskkill.exe /PID ([int]$p.Id) /T /F 2>$null|Out-Null}catch{}
    return 124
  }
  try{return [int]$p.ExitCode}catch{return 1}
}
function ReadJsonIf([string]$Path){try{if(Test-Path -LiteralPath $Path -PathType Leaf){return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}}catch{};return $null}

$started=Get-Date
$result=[ordered]@{ok=$false;version=$Version;taskId=$TaskId;pinnedAgent=$PinnedVersion;pinnedSha=$PinnedSha;downloadSha='';agentExit=$null;entryFound=$false;directProbeFound=$false;inspectExitCode=$null;captureExitCode=$null;analyzeExitCode=$null;contractOk=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;extensionMutated=$false;startedAt=$started.ToString('o');finishedAt='';error=''}
try{
  $headers=@{'User-Agent'='HomeDesign-Image-Contract-Recovery';'Accept'='application/vnd.github+json'}
  $path='local-agent/releases/'+$PinnedVersion+'/HomeDesignLocalAgent.ps1'
  $url='https://api.github.com/repos/'+$Repo+'/contents/'+$path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $r=Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30
  if(([string]$r.sha).ToLowerInvariant() -ne $PinnedSha){throw('REMOTE_SHA_MISMATCH:'+([string]$r.sha))}
  $tmp=$Agent+'.download'
  [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')))
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();$result.downloadSha=$actual
  if($actual-ne$PinnedSha){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('LOCAL_SHA_MISMATCH:'+$actual)}
  Move-Item $tmp $Agent -Force

  $result.agentExit=RunBounded $Agent 330
  $central=FindCentral
  $entryLocal=Join-Path $Root 'CHATGPT_IMAGE_AGENT_ENTRY_1.1.71.json'
  $probeLocal=Join-Path $Root 'CHATGPT_IMAGE_DIRECT_PROBE_1.1.71.json'
  $entry=$null;$probe=$null
  if($central){
    $rr=Join-Path $central 'Runtime_Readback\ChatGPT_Image_Auto'
    $entry=ReadJsonIf (Join-Path $rr 'CHATGPT_IMAGE_AGENT_ENTRY_1.1.71.json')
    $probe=ReadJsonIf (Join-Path $rr 'CHATGPT_IMAGE_DIRECT_PROBE_1.1.71.json')
  }
  if(-not$entry){$entry=ReadJsonIf $entryLocal}
  if(-not$probe){$probe=ReadJsonIf $probeLocal}
  $result.entryFound=($null-ne$entry);$result.directProbeFound=($null-ne$probe)
  if($probe){
    if($null-ne$probe.inspectExitCode){$result.inspectExitCode=[int]$probe.inspectExitCode}
    if($null-ne$probe.captureExitCode){$result.captureExitCode=[int]$probe.captureExitCode}
    if($null-ne$probe.analyzeExitCode){$result.analyzeExitCode=[int]$probe.analyzeExitCode}
    $result.contractOk=[bool]$probe.contractOk
  }
  $result.ok=($result.agentExit-eq0 -and $result.entryFound -and $result.directProbeFound -and $result.inspectExitCode-eq0 -and $result.captureExitCode-eq0 -and $result.analyzeExitCode-eq0 -and $result.contractOk)
  if(-not$result.ok){$result.error='CONTRACT_PROBE_GATE_NOT_COMPLETE'}
}catch{$result.error=$_.Exception.Message}
$result.finishedAt=(Get-Date).ToString('o')
Save $result
$result|ConvertTo-Json -Depth 60 -Compress
if($result.ok){exit 0}else{exit 2}
