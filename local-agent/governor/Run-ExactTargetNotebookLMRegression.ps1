param(
  [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$DebugPort=9231,
  [switch]$RepairStableAgentApi
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function ApiContent([string]$Path){
  $headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
  $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main'
  Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 15
}
function DecodeText($R){
  $raw=([string]$R.content -replace '\s','')
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))
}
function WriteBytesFromApi($R,[string]$Path){
  $bytes=[Convert]::FromBase64String(([string]$R.content -replace '\s',''))
  [IO.File]::WriteAllBytes($Path,$bytes)
}
function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not $d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('내 드라이브\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c -PathType Container){return $c}}
  }
  return ''
}

if($RepairStableAgentApi){
  try{
    $metaResp=ApiContent 'local-agent/stable/agent.json'
    $meta=(DecodeText $metaResp)|ConvertFrom-Json
    if(-not $meta.enabled){throw 'LOCAL_AGENT_STABLE_DISABLED'}
    $target=[string]$meta.version
    $expected=([string]$meta.gitBlobSha1).ToLowerInvariant()
    $releaseResp=ApiContent ('local-agent/releases/'+$target+'/HomeDesignLocalAgent.ps1')
    if(([string]$releaseResp.sha).ToLowerInvariant() -ne $expected){throw ('AGENT_API_SHA_MISMATCH api='+[string]$releaseResp.sha+' expected='+$expected)}
    $agent=Join-Path $Root 'HomeDesignLocalAgent.ps1'
    $tmp=$agent+'.api-repair.download'
    WriteBytesFromApi $releaseResp $tmp
    $actual=(GitBlob $tmp).ToLowerInvariant()
    if($actual -ne $expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('AGENT_FILE_SHA_MISMATCH actual='+$actual+' expected='+$expected)}
    Move-Item $tmp $agent -Force

    $helper=Join-Path $Root 'Stable-Agent-Api-Delayed-Handoff.ps1'
    $central=FindCentral
    $receipt=$(if($central){Join-Path $central 'Runtime_Readback\AGENT_STABLE_API_DELAYED_HANDOFF.json'}else{Join-Path $Root 'AGENT_STABLE_API_DELAYED_HANDOFF.json'})
    $helperCode=@'
param([string]$AgentPath,[string]$ReceiptPath,[string]$Target,[string]$ExpectedSha)
$ErrorActionPreference='Continue'
Start-Sleep -Seconds 4
$p=$null;$err=''
try{$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$AgentPath+'"';$p=[Diagnostics.Process]::Start($psi)}catch{$err=$_.Exception.Message}
try{$par=Split-Path -Parent $ReceiptPath;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};[ordered]@{ok=[bool]$p;action='STABLE_AGENT_API_DELAYED_HANDOFF';targetAgent=$Target;expectedSha=$ExpectedSha;pid=$(if($p){[int]$p.Id}else{$null});error=$err;startedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{}
'@
    Set-Content -LiteralPath $helper -Value $helperCode -Encoding UTF8
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -AgentPath "'+$agent+'" -ReceiptPath "'+$receipt+'" -Target "'+$target+'" -ExpectedSha "'+$expected+'"'
    $p=[Diagnostics.Process]::Start($psi)
    [ordered]@{ok=$true;action='STABLE_AGENT_API_REPAIR_DISPATCHED';targetAgent=$target;expectedSha=$expected;localAgentSha=$actual;handoffPid=[int]$p.Id;delaySeconds=4;receipt=$receipt;normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 12 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='STABLE_AGENT_API_REPAIR_DISPATCHED';error=$_.Exception.Message;normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

# Compatibility path: the old V1 implementation had a syntax defect. Forward all normal regression calls to the verified V2 wrapper.
try{
  $expected='1b7f543850c42b6d4f36641c73b5c9021ccd3384'
  $resp=ApiContent 'local-agent/governor/Run-ExactTargetNotebookLMRegressionV2.ps1'
  if(([string]$resp.sha).ToLowerInvariant() -ne $expected){throw ('REGRESSION_V2_API_SHA_MISMATCH api='+[string]$resp.sha+' expected='+$expected)}
  $child=Join-Path $Root 'Run-ExactTargetNotebookLMRegressionV2.compat.ps1'
  WriteBytesFromApi $resp $child
  $actual=(GitBlob $child).ToLowerInvariant();if($actual -ne $expected){throw ('REGRESSION_V2_FILE_SHA_MISMATCH actual='+$actual+' expected='+$expected)}
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -NotebookUrl $NotebookUrl -DebugPort $DebugPort
  exit $LASTEXITCODE
}catch{
  [ordered]@{ok=$false;action='NOTEBOOKLM_EXACT_TARGET_V1_COMPAT_TO_V2';error=$_.Exception.Message;generateClicked=$false;creditSpend=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
  exit 2
}
