param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.67'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$PinnedHost130='274aef614763cfe1d886fd16c5641e0b64ab6176'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$HostPath=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$UserData=Join-Path $Base 'ChromeUserData'
$Ext=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $Base 'ChromeForTesting'
$Receipt=Join-Path $Root 'NOTEBOOKLM_NATIVE_RUNTIME_RECOVERY_1.1.67.json'
$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51'
New-Item -ItemType Directory -Force -Path $Root,$UserData|Out-Null
function Blob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Api([string]$p){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$p+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'} -TimeoutSec 20}
function ReadJ([string]$p){if(Test-Path $p){try{return Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}}
function SaveJ([string]$p,$o){$d=Split-Path $p -Parent;if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null};$o|ConvertTo-Json -Depth 60|Set-Content $p -Encoding UTF8}
function Central{$n=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){foreach($c in @((Join-Path $d.Root $n),(Join-Path $d.Root ($m+'\'+$n)),(Join-Path $d.Root ('My Drive\'+$n)),(Join-Path $d.Root ('Google Drive\'+$n)))){if(Test-Path $c){return $c}}};''}
function Procs([string]$needle){try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like ('*'+$needle+'*')})}catch{return @()}}
function Cft{if(Test-Path $CftRoot){return Get-ChildItem $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1}}
$errors=@();$hostInstalled=$false;$allowlistOk=$false;$hostOk=$false;$prefsOk=$false;$cftOk=$false;$central=Central
try{
  $r=Api 'local-agent/releases/1.3.0/HomeDesignLocalCommandHost.final.ps1';if(([string]$r.sha).ToLowerInvariant()-ne$PinnedHost130){throw('HOST_130_API_SHA:'+[string]$r.sha)}
  $tmp=$HostPath+'.1167';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));if((Blob $tmp).ToLowerInvariant()-ne$PinnedHost130){throw'HOST_130_LOCAL_SHA'}
  $raw=Get-Content -LiteralPath $tmp -Raw -Encoding UTF8
  $anchor="'local-agent/governor/Inspect-FlowApprovedAccountCredits.ps1')"
  $replacement="'local-agent/governor/Inspect-FlowApprovedAccountCredits.ps1','local-agent/governor/MirrorNotebookLMArtifactQueensFirst.ps1','local-agent/governor/RunNotebookLMDirectCDPDownloadSyncedV3.ps1','local-agent/governor/RunNotebookLMExistingVideoQueensFirstV1.ps1','local-agent/governor/CaptureNotebookLMExistingArtifactViewToSeedV1.ps1')"
  if(-not $raw.Contains($anchor)){throw'HOST_ALLOWLIST_ANCHOR_NOT_FOUND'};$raw=$raw.Replace($anchor,$replacement);Set-Content -LiteralPath $tmp -Value $raw -Encoding UTF8
  foreach($x in @('MirrorNotebookLMArtifactQueensFirst.ps1','RunNotebookLMDirectCDPDownloadSyncedV3.ps1','RunNotebookLMExistingVideoQueensFirstV1.ps1','CaptureNotebookLMExistingArtifactViewToSeedV1.ps1')){if($raw -notlike ('*'+$x+'*')){throw('HOST_ALLOWLIST_PATCH_MISSING:'+ $x)}};$allowlistOk=$true
  foreach($p in @(Procs 'HomeDesignLocalCommandHost.ps1')){if($p.ProcessId-ne$PID){Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}};Start-Sleep 1;Move-Item -LiteralPath $tmp -Destination $HostPath -Force;$hostInstalled=$true
  Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$HostPath`"") -WindowStyle Hidden|Out-Null
  $deadline=(Get-Date).AddSeconds(15);do{Start-Sleep -Milliseconds 500;try{$h=Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 2;if([string]$h.version -eq '1.3.0'){$hostOk=$true;break}}catch{}}while((Get-Date)-lt$deadline);if(-not$hostOk){throw'HOST_130_HEALTH_NOT_READY'}
}catch{$errors+=('HOST:'+ $_.Exception.Message)}
try{
  foreach($p in @(Procs $UserData)){if($p.Name-eq'chrome.exe'){Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue}};Start-Sleep 2
  $pref=Join-Path $UserData 'Default\Preferences';$prefDir=Split-Path $pref -Parent;New-Item -ItemType Directory -Force -Path $prefDir|Out-Null;$j=ReadJ $pref;if(-not$j){$j=[pscustomobject]@{}};if(-not$j.PSObject.Properties['download']){$j|Add-Member download ([pscustomobject]@{}) -Force}
  $downloadPath=Join-Path $env:USERPROFILE 'Downloads';New-Item -ItemType Directory -Force -Path $downloadPath|Out-Null;$j.download|Add-Member prompt_for_download $false -Force;$j.download|Add-Member default_directory $downloadPath -Force;$j.download|Add-Member directory_upgrade $true -Force;SaveJ $pref $j
  $verify=ReadJ $pref;$prefsOk=($verify -and $verify.download.prompt_for_download -eq $false -and [string]$verify.download.default_directory -eq $downloadPath);if(-not$prefsOk){throw'DOWNLOAD_PREF_VERIFY_FAIL'}
  $c=Cft;if(-not$c){throw'CFT_NOT_FOUND'};Start-Process $c.FullName -ArgumentList @('--remote-debugging-port=9223','--remote-allow-origins=*',"--user-data-dir=$UserData",'--profile-directory=Default',"--disable-extensions-except=$Ext","--load-extension=$Ext",'--new-window','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$NotebookUrl)|Out-Null
  $deadline=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 500;try{$v=Invoke-RestMethod 'http://127.0.0.1:9223/json/version' -TimeoutSec 2;if($v.webSocketDebuggerUrl){$cftOk=$true;break}}catch{}}while((Get-Date)-lt$deadline);if(-not$cftOk){throw'NOTEBOOKLM_CFT_9223_NOT_READY'}
}catch{$errors+=('CFT:'+ $_.Exception.Message)}
$ok=($hostInstalled-and$allowlistOk-and$hostOk-and$prefsOk-and$cftOk-and$errors.Count-eq0)
try{$s=ReadJ $State;if(-not$s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member hostVersion $(if($hostOk){'1.3.0'}else{'UNKNOWN'}) -Force;$s|Add-Member status $(if($ok){'NOTEBOOKLM_NATIVE_RUNTIME_READY'}else{'NOTEBOOKLM_NATIVE_RUNTIME_RECOVERY_FAILED'}) -Force;$s|Add-Member notebookDebugPort 9223 -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJ $State $s}catch{$errors+=('STATE:'+ $_.Exception.Message);$ok=$false}
$rec=[ordered]@{ok=$ok;action='NOTEBOOKLM_NATIVE_RUNTIME_RECOVERY_SELF_CONTAINED';agentVersion=$AgentVersion;hostVersion=if($hostOk){'1.3.0'}else{'UNKNOWN'};hostInstalled=$hostInstalled;hostAllowlistPatched=$allowlistOk;downloadPromptDisabled=$prefsOk;downloadDirectory=(Join-Path $env:USERPROFILE 'Downloads');notebookCftPort=9223;notebookCftReady=$cftOk;normalChromeTouched=$false;flowGenerateClicked=$false;creditsSpent=$false;oauthChanged=$false;errors=$errors;at=(Get-Date).ToString('o')};SaveJ $Receipt $rec;if($central){SaveJ (Join-Path $central 'Runtime_Readback\NOTEBOOKLM_NATIVE_RUNTIME_RECOVERY_1.1.67.json') $rec};$rec|ConvertTo-Json -Depth 60 -Compress;if($ok){exit 0}else{exit 2}
