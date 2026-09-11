param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$PyLocal=Join-Path $Root 'DriveMirrorExactDiffFinalize.py'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1Bytes([byte[]]$Bytes){$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$Bytes.Length+[char]0));$a=New-Object byte[]($h.Length+$Bytes.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($Bytes,0,$a,$h.Length,$Bytes.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FetchRepoBytes([string]$Path){
  try{$u='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$wc=New-Object Net.WebClient;try{$wc.Headers['User-Agent']='HomeDesign-Drive-Mirror-Lane';return $wc.DownloadData($u)}finally{$wc.Dispose()}}catch{}
  $h=@{'User-Agent'='HomeDesign-Drive-Mirror-Lane';'Accept'='application/vnd.github+json'}
  $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main'
  $x=Invoke-RestMethod -Uri $u -Headers $h -Method Get -TimeoutSec 30
  $b=[Convert]::FromBase64String(([string]$x.content-replace'\s',''))
  if((GitBlobSha1Bytes $b).ToLowerInvariant()-ne([string]$x.sha).ToLowerInvariant()){throw 'PY_GIT_BLOB_SHA_MISMATCH'}
  return $b
}
$b=FetchRepoBytes 'local-agent/bootstrap/DriveMirrorExactDiffFinalize.py'
$tmp=$PyLocal+'.download';[IO.File]::WriteAllBytes($tmp,$b);Move-Item -LiteralPath $tmp -Destination $PyLocal -Force
$py=(Get-Command python.exe -ErrorAction SilentlyContinue).Source
if(-not$py){$py=(Get-Command python -ErrorAction SilentlyContinue).Source}
if(-not$py){throw 'PYTHON_NOT_FOUND'}
& $py $PyLocal
exit $LASTEXITCODE
