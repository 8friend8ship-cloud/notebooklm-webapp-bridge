param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.62'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ExpectedBridge='0.2.75'
$ExpectedHostSha='274aef614763cfe1d886fd16c5641e0b64ab6176'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Ext=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$HostPath=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$UserData=Join-Path $Base 'ChromeUserData'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$State=Join-Path $Root 'state.json'
$Receipt=Join-Path $Root 'FLOW_UNIFIED_RECOVERY_1.1.62.json'
New-Item -ItemType Directory -Force -Path $Root,$Ext|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Api([string]$p){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$p+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'} -TimeoutSec 20}
function Text($r){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$r.content-replace'\s','')))}
function ReadJ([string]$p){if(Test-Path $p){try{return Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}}
function SaveJ([string]$p,$o){$d=Split-Path $p -Parent;if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null};$o|ConvertTo-Json -Depth 60|Set-Content $p -Encoding UTF8}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ('내 드라이브\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)))){if(Test-Path $c){return $c}}};return ''}
function Procs([string]$needle){try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like ('*'+$needle+'*')})}catch{return @()}}
function Cft{if(Test-Path $CftRoot){return Get-ChildItem $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}}
$errors=@();$applied=@();$bridge='';$health=$null;$cftOk=$false;$central=Central
try{
  $rr=Api 'runtime/stable/release.json';$rel=(Text $rr)|ConvertFrom-Json;$bridge=[string]$rel.version
  if(-not $rel.enabled){throw 'BRIDGE_RELEASE_DISABLED'}
  if($bridge -ne $ExpectedBridge){throw ('BRIDGE_VERSION:'+ $bridge+':'+$ExpectedBridge)}
  foreach($f in @($rel.files)){
    $rp=[string]$f.path;$ex=([string]$f.gitBlobSha1).ToLowerInvariant();$src='notebooklm-webapp-bridge-source-v0.2.0/extension/'+($rp-replace'\','/');$r=Api $src
    if(([string]$r.sha).ToLowerInvariant()-ne$ex){throw('API_SHA:'+ $rp+':'+[string]$r.sha+':'+$ex)}
    $dst=Join-Path $Ext ($rp-replace'/','\');$par=Split-Path $dst -Parent;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null}
    $tmp=$dst+'.1162';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')))
    if((Blob $tmp).ToLowerInvariant()-ne$ex){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('LOCAL_SHA:'+ $rp)}
    Move-Item $tmp $dst -Force;$applied+=$rp
  }
  $m=ReadJ (Join-Path $Ext 'manifest.json');if([string]$m.version-ne$ExpectedBridge){throw('MANIFEST_VERSION:'+ [string]$m.version+':'+$ExpectedBridge)}
}catch{$errors+=('BRIDGE:'+ $_.Exception.Message)}
try{
  $r=Api 'local-agent/releases/1.3.0/HomeDesignLocalCommandHost.final.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$ExpectedHostSha){throw('HOST_API_SHA:'+[string]$r.sha)}
  $tmp=$HostPath+'.1162';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$ExpectedHostSha){throw'HOST_LOCAL_SHA'}
  Move-Item $tmp $HostPath -Force
  foreach($p in @(Procs 'HomeDesignLocalCommandHost.ps1')){if($p.ProcessId-ne$PID){Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}}
  Start-Sleep 1;Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$HostPath`"") -WindowStyle Hidden|Out-Null;Start-Sleep 2
  $health=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 5;if([string]$health.version-ne'1.3.0'){throw('HOST_HEALTH_VERSION:'+ [string]$health.version)}
}catch{$errors+=('HOST:'+ $_.Exception.Message)}
try{
  foreach($p in @(Procs $UserData)){if($p.Name-eq'chrome.exe'){Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}}
  Start-Sleep 2;$c=Cft;if(-not$c){throw'CFT_NOT_FOUND'}
  Start-Process $c.FullName -ArgumentList @("--user-data-dir=$UserData",'--profile-directory=Default',"--disable-extensions-except=$Ext","--load-extension=$Ext",'--remote-debugging-port=9224','https://labs.google/fx/tools/flow')|Out-Null
  Start-Sleep 3;$cftOk=@(Procs $UserData|Where-Object{$_.Name-eq'chrome.exe'}).Count-gt0;if(-not$cftOk){throw'CFT_RESTART_FAIL'}
}catch{$errors+=('CFT:'+ $_.Exception.Message)}
$ok=[bool]($errors.Count-eq0 -and $bridge-eq$ExpectedBridge -and $health -and [string]$health.version-eq'1.3.0' -and $cftOk)
$rec=[ordered]@{ok=$ok;action='FLOW_UNIFIED_RECOVERY';agentVersion=$AgentVersion;bridgeVersion=$bridge;hostVersion=$(if($health){[string]$health.version}else{''});hostSha=$ExpectedHostSha;appliedCount=$applied.Count;dedicatedCftRestarted=$cftOk;normalChromeTouched=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;errors=$errors;at=(Get-Date).ToString('o')}
SaveJ $Receipt $rec;if($central){SaveJ (Join-Path $central 'Runtime_Readback\FLOW_UNIFIED_RECOVERY_1.1.62.json') $rec}
try{$s=ReadJ $State;if(-not$s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member extensionVersion $bridge -Force;$s|Add-Member installedVersion $bridge -Force;$s|Add-Member commandHostVersion $(if($health){[string]$health.version}else{''}) -Force;$s|Add-Member hostHealthy [bool]$health -Force;$s|Add-Member status $(if($ok){'FLOW_UNIFIED_RECOVERY_PASS'}else{'FLOW_UNIFIED_RECOVERY_FAILED'}) -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJ $State $s}catch{}
$rec|ConvertTo-Json -Depth 60 -Compress
if($ok){exit 0}else{exit 2}
