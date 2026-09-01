param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.139-image-resume-transport'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ResumePath='local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1'
$ResumeSha='8f712fd41dcc22476a904fc145742c352275d6f8'
$GlobalPath='local-agent/releases/1.1.135/HomeDesignLocalAgent.ps1'
$GlobalSha='bcf146e26164c41a426ed301928627e9cf4d0ba9'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='IMAGE_RESUME_TRANSPORT_1.1.139.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $Receipt) -Encoding UTF8;try{$c=Central;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function RawVerified([string]$Path,[string]$Dest,[string]$Expected){$u='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$tmp=$Dest+'.download';Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{'User-Agent'='HomeDesign-Image-Resume-Transport'} -OutFile $tmp -TimeoutSec 30;$a=(Blob $tmp).ToLowerInvariant();if($a-ne$Expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('RAW_SHA_MISMATCH:'+ $Path+':'+$a+':'+$Expected)};Move-Item $tmp $Dest -Force}
$r=[ordered]@{ok=$false;action='IMAGE_RESUME_TRANSPORT';version=$Version;resumeSha=$ResumeSha;globalSha=$GlobalSha;resumeApplied=$false;globalChildExit=$null;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;duplicateTaskCreated=$false;startedAt=(Get-Date).ToString('o');error=''}
try{
  $resumeDest=Join-Path $Root 'RESUME_LOCAL_AGENT_ONCE.ps1'
  RawVerified $ResumePath $resumeDest $ResumeSha
  $r.resumeApplied=$true
  $globalDest=Join-Path $Root 'HomeDesignLocalAgent-global-1.1.135.ps1'
  RawVerified $GlobalPath $globalDest $GlobalSha
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $globalDest
  $r.globalChildExit=$LASTEXITCODE
  if($LASTEXITCODE-ne0){throw('GLOBAL_1.1.135_EXIT_'+$LASTEXITCODE)}
  $r.ok=$true
}catch{$r.error=$_.Exception.Message}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 80 -Compress
if($r.ok){exit 0}else{exit 2}
