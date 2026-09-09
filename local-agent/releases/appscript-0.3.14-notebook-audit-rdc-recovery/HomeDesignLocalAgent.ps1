param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='appscript-0.3.14-notebook-audit-rdc-recovery'
$AuditExpected='915efb32287ed0b4a1ba4561381f796251c80daf'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$AuditLocal=Join-Path $Root 'NotebookAuditPack.ps1'
$Receipt=Join-Path $Root 'APPSCRIPT_NOTEBOOK_AUDIT_RDC_RECOVERY_0.3.14.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function FindCentral{
  $n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function Save($o){
  try{
    $j=$o|ConvertTo-Json -Depth 50
    $j|Set-Content -LiteralPath $Receipt -Encoding UTF8
    $c=FindCentral
    if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d 'APPSCRIPT_NOTEBOOK_AUDIT_RDC_RECOVERY_0.3.14.json') -Encoding UTF8}
  }catch{}
}
function GitBlob([byte[]]$b){
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function FetchAudit{
  $path='local-agent/bootstrap/NotebookAuditPack.ps1'
  $tmp=$AuditLocal+'.download'
  $mode='';$bytes=$null
  try{
    $url='https://api.github.com/repos/'+$Repo+'/contents/'+$path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $x=Invoke-RestMethod -Uri $url -Headers @{'User-Agent'='HomeDesign-Notebook-Audit-Recovery';'Accept'='application/vnd.github+json'} -TimeoutSec 30
    $bytes=[Convert]::FromBase64String(([string]$x.content-replace'\s',''))
    if(([string]$x.sha).ToLowerInvariant()-ne$AuditExpected){throw 'AUDIT_API_SHA_MISMATCH'}
    $mode='API'
  }catch{
    $raw='https://raw.githubusercontent.com/'+$Repo+'/main/'+$path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $wc=New-Object Net.WebClient
    try{$wc.Headers['User-Agent']='HomeDesign-Notebook-Audit-Recovery';$bytes=$wc.DownloadData($raw)}finally{$wc.Dispose()}
    $mode='RAW'
  }
  if(-not$bytes-or$bytes.Length-eq0){throw 'AUDIT_DOWNLOAD_EMPTY'}
  $actual=(GitBlob $bytes).ToLowerInvariant()
  if($actual-ne$AuditExpected){throw ('AUDIT_GIT_BLOB_SHA_MISMATCH actual='+$actual+' expected='+$AuditExpected)}
  [IO.File]::WriteAllBytes($tmp,$bytes)
  Move-Item -LiteralPath $tmp -Destination $AuditLocal -Force
  return $mode
}
function RunAudit([int]$TimeoutSeconds=300){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe'
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$AuditLocal+'"'
  $p=[Diagnostics.Process]::Start($psi)
  if(-not$p.WaitForExit($TimeoutSeconds*1000)){
    try{& taskkill.exe /PID ([int]$p.Id) /T /F 2>$null|Out-Null}catch{}
    return 124
  }
  try{return [int]$p.ExitCode}catch{return 1}
}

$r=[ordered]@{
  ok=$false
  action='P0_NOTEBOOK_AUDIT_REMOTE_DC_RECOVERY'
  version=$Version
  startedAt=(Get-Date).ToString('o')
  completedAt=''
  auditExpectedSha=$AuditExpected
  auditTransport=''
  auditExit=$null
  previousAppscriptVersion='appscript-0.3.13-task203-clone-auth-proof-force-retry'
  previousTask203Preserved=$true
  previousTask203DeferredForP0RemoteRecovery=$true
  remoteDcPriority='P0'
  newOAuth=$false
  newProject=$false
  newTrigger=$false
  globalNpmCacheClean=$false
  broadNodeKill=$false
  error=''
}
try{
  $r.auditTransport=FetchAudit
  $r.auditExit=RunAudit 300
  $r.ok=([int]$r.auditExit-eq0)
  if(-not$r.ok){$r.error='NOTEBOOK_AUDIT_EXIT_'+[string]$r.auditExit}
}catch{$r.error=$_.Exception.Message;$r.ok=$false}
$r.completedAt=(Get-Date).ToString('o')
Save $r
$r|ConvertTo-Json -Depth 50 -Compress
if($r.ok){exit 0}else{exit 2}
