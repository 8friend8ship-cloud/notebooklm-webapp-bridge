param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.57'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StatePath=Join-Path $Root 'state.json'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
New-Item -ItemType Directory -Force -Path $ExtensionRoot|Out-Null

function GitBlob([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function ApiContent([string]$Path){
  $headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
  $u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $u -Headers $headers -Method Get -TimeoutSec 20
}
function DecodeText($R){$raw=([string]$R.content -replace '\s','');[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))}
function SaveJson([string]$Path,$Obj){$p=Split-Path -Parent $Path;if($p){New-Item -ItemType Directory -Force -Path $p|Out-Null};$Obj|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{$null}}
function FindCentralRoot{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $target),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('My Drive\'+$target)),(Join-Path $d.Root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''
}
function FindCftChrome{if(-not(Test-Path -LiteralPath $CftRoot)){return $null};Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}
function DedicatedProcesses{
  try{@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -eq 'chrome.exe' -and $_.CommandLine -and $_.CommandLine -like ('*'+$UserData+'*')})}catch{@()}
}

$errors=@();$applied=@();$releaseVersion='';$releaseSha='';$restartOk=$false;$cftPath=''
try{
  $relResp=ApiContent 'runtime/stable/release.json'
  $releaseSha=([string]$relResp.sha).ToLowerInvariant()
  $rel=(DecodeText $relResp)|ConvertFrom-Json
  if(-not $rel.enabled -or [string]$rel.action -ne 'apply'){throw 'STABLE_EXTENSION_RELEASE_NOT_APPLY_ENABLED'}
  $releaseVersion=[string]$rel.version
  foreach($f in @($rel.files)){
    $relPath=[string]$f.path;$expected=([string]$f.gitBlobSha1).ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($relPath) -or $relPath.Contains('..') -or $relPath.StartsWith('/') -or $relPath.StartsWith('\')){throw ('UNSAFE_RELEASE_PATH:'+ $relPath)}
    $srcPath='notebooklm-webapp-bridge-source-v0.2.0/extension/'+($relPath -replace '\','/')
    $r=ApiContent $srcPath
    if(([string]$r.sha).ToLowerInvariant() -ne $expected){throw ('API_SHA_MISMATCH:'+ $relPath+':'+[string]$r.sha+':'+$expected)}
    $dest=Join-Path $ExtensionRoot ($relPath -replace '/','\');$par=Split-Path -Parent $dest;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null}
    $tmp=$dest+'.agent1157.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')))
    $actual=(GitBlob $tmp).ToLowerInvariant();if($actual -ne $expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('FILE_SHA_MISMATCH:'+ $relPath+':'+$actual+':'+$expected)}
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    $applied += [pscustomobject]@{path=$relPath;sha=$actual}
  }

  $manifest=ReadJson (Join-Path $ExtensionRoot 'manifest.json')
  if(-not $manifest -or [string]$manifest.version -ne $releaseVersion){throw ('MANIFEST_VERSION_MISMATCH:'+ [string]$manifest.version+':'+$releaseVersion)}

  $procs=@(DedicatedProcesses)
  foreach($p in $procs){try{Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}catch{}}
  if($procs.Count -gt 0){Start-Sleep -Seconds 2}
  $cft=FindCftChrome
  if(-not $cft){throw 'CHROME_FOR_TESTING_NOT_FOUND'}
  $cftPath=$cft.FullName
  $args=@("--user-data-dir=$UserData",'--profile-directory=Default',"--disable-extensions-except=$ExtensionRoot","--load-extension=$ExtensionRoot",'--remote-debugging-port=9224','https://labs.google/fx/tools/flow')
  Start-Process -FilePath $cft.FullName -ArgumentList $args|Out-Null
  Start-Sleep -Seconds 3
  $restartOk=@(DedicatedProcesses).Count -gt 0
  if(-not $restartOk){throw 'DEDICATED_CFT_RESTART_NOT_OBSERVED'}
}catch{$errors+=$_.Exception.Message}

$ok=($errors.Count -eq 0 -and $applied.Count -gt 0 -and $restartOk)
$central=FindCentralRoot
$receipt=[ordered]@{
  ok=$ok;action='STABLE_EXTENSION_RELEASE_APPLY';agentVersion=$AgentVersion;releaseVersion=$releaseVersion;releaseApiSha=$releaseSha;appliedFiles=$applied;appliedCount=$applied.Count;extensionRoot=$ExtensionRoot;dedicatedChromeRestarted=$restartOk;dedicatedChromePath=$cftPath;normalChromeRestarted=$false;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;newProject=$false;newDeployment=$false;errors=$errors;at=(Get-Date).ToString('o')
}
SaveJson (Join-Path $Root 'STABLE_EXTENSION_RELEASE_APPLY_1.1.57.json') $receipt
if($central){try{SaveJson (Join-Path $central 'Runtime_Readback\CHROME\STABLE_EXTENSION_RELEASE_APPLY_1.1.57.json') $receipt}catch{}}
try{$s=ReadJson $StatePath;if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member agentMode 'STABLE_EXTENSION_RELEASE_APPLY' -Force;$s|Add-Member extensionStableVersion $releaseVersion -Force;$s|Add-Member status $(if($ok){'EXTENSION_RELEASE_APPLIED'}else{'EXTENSION_RELEASE_APPLY_FAILED'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $StatePath $s}catch{}
$receipt|ConvertTo-Json -Depth 50 -Compress
if($ok){exit 0}else{exit 2}
