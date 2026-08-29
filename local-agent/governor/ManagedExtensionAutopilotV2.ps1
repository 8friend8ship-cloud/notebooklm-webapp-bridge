param(
  [ValidateSet('Inventory','SyncRegistry','Stage','Rollback','LaunchExact','ProbeExact')][string]$Mode='Inventory',
  [ValidateSet('NOTEBOOKLM','FLOW','AI_STUDIO','FRONT_QA','CENTRAL_CAPTURE','GENERIC')][string]$Service='GENERIC',
  [string]$TargetUrl='',
  [string]$ExpectedUrlPattern='',
  [string]$ExpectedExtensionId='',
  [string]$RegistryUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/config/managed-extension-autopilot-v1.json',
  [string]$SourceZip='',[string]$SourceDir='',[string]$SourceUrl='',[string]$ManifestSubPath='',
  [int]$RemoteDebuggingPort=9230,[int]$TimeoutSeconds=35,[switch]$Apply,[switch]$RestartDedicatedChrome,[switch]$ProbeInput
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Version='MANAGED_EXTENSION_AUTOPILOT_V2_2_20260829'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$ToolRoot=Join-Path $Base 'ManagedExtensions\Tools';New-Item -ItemType Directory -Force -Path $ToolRoot|Out-Null
$Legacy=Join-Path $ToolRoot 'ManagedExtensionAutopilot-v1.ps1'
$ExactLegacy=Join-Path $ToolRoot 'ManagedExtensionExactTargetLauncher-v1.ps1'
$ExactV2=Join-Path $ToolRoot 'ManagedExtensionExactTargetLauncher-v2.ps1'
$LegacySha='6f4acb1f1c0d6f37fd675b55cd2f8a3a349f7ec4'
$ExactLegacySha='e272246c0d1553c703095bdeae68f77ab259db57'
$ExactV2Sha='6ea89f678d4716e7ed39163e6bb0634e78eb750c'
function GitBlob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Api([string]$rel){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$rel+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-Managed-Extension';'Accept'='application/vnd.github+json'} -TimeoutSec 20}
function FetchApi([string]$rel,[string]$dest,[string]$sha){$r=Api $rel;$api=([string]$r.sha).ToLowerInvariant();if($api-ne$sha.ToLowerInvariant()){throw('SOURCE_API_SHA_MISMATCH:'+ $rel+':'+$api+':'+$sha)};$tmp=$dest+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content-replace'\s','')));$actual=(GitBlob $tmp).ToLowerInvariant();if($actual-ne$sha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw('SOURCE_LOCAL_SHA_MISMATCH:'+ $rel+':'+$actual+':'+$sha)};Move-Item $tmp $dest -Force}
FetchApi 'local-agent/governor/ManagedExtensionAutopilot.ps1' $Legacy $LegacySha
if($Service -eq 'NOTEBOOKLM' -and $Mode -in @('LaunchExact','ProbeExact')){FetchApi 'local-agent/governor/ManagedExtensionExactTargetLauncherV2.ps1' $ExactV2 $ExactV2Sha}else{FetchApi 'local-agent/governor/ManagedExtensionExactTargetLauncher.ps1' $ExactLegacy $ExactLegacySha}
function DefaultRoute([string]$svc){switch($svc){'NOTEBOOKLM'{return [pscustomobject]@{url='https://notebook.google.com/';pattern='notebook(lm)?\.google\.com';id='llgjlejpknemhdmckoaifgjnjikceamp'}}'FLOW'{return [pscustomobject]@{url='https://labs.google/fx/tools/flow';pattern='labs\.google/.*/flow|labs\.google/fx/tools/flow';id='lgedgmpcikglaajhfclcihicgafimlna'}}'AI_STUDIO'{return [pscustomobject]@{url='https://aistudio.google.com/';pattern='aistudio\.google\.com';id='okppbdphadmdfbfpllpjjnmmemokbccp'}}default{return [pscustomobject]@{url='';pattern='';id=$ExpectedExtensionId}}}}
if($Mode -in @('Inventory','SyncRegistry','Stage','Rollback')){
  $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Legacy,'-Mode',$Mode,'-RegistryUrl',$RegistryUrl)
  if($SourceZip){$args+=@('-SourceZip',$SourceZip)};if($SourceDir){$args+=@('-SourceDir',$SourceDir)};if($SourceUrl){$args+=@('-SourceUrl',$SourceUrl)};if($ManifestSubPath){$args+=@('-ManifestSubPath',$ManifestSubPath)};if($ExpectedExtensionId){$args+=@('-ExpectedExtensionId',$ExpectedExtensionId)};if($Apply){$args+='-Apply'}
  $out=& powershell.exe @args 2>&1;$exit=$LASTEXITCODE
  [pscustomobject]@{ok=($exit-eq0);version=$Version;mode=$Mode;legacyStageOnly=$true;genericLaunchSuppressed=$true;output=($out|Out-String).Trim()}|ConvertTo-Json -Depth 30
  exit $exit
}
$route=DefaultRoute $Service
if(-not$TargetUrl){$TargetUrl=$route.url};if(-not$ExpectedUrlPattern){$ExpectedUrlPattern=$route.pattern};if(-not$ExpectedExtensionId){$ExpectedExtensionId=$route.id}
if(-not$TargetUrl){throw'EXACT_TARGET_URL_REQUIRED'}
if($Service -eq 'NOTEBOOKLM'){
  $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$ExactV2,'-Service','NOTEBOOKLM','-TargetUrl',$TargetUrl,'-RemoteDebuggingPort',[string]$RemoteDebuggingPort,'-TimeoutSeconds',[string]$TimeoutSeconds)
  if($RestartDedicatedChrome -or $Mode -eq 'LaunchExact'){$args+='-RestartDedicatedChrome'}
  if($ProbeInput -or $Mode -eq 'ProbeExact'){$args+='-ProbeInput'}
  $out=& powershell.exe @args 2>&1;$exit=$LASTEXITCODE;$text=($out|Out-String).Trim();$inner=$null;try{$inner=(($text -split "`r?`n")[-1]|ConvertFrom-Json)}catch{}
  $pass=[bool]($exit-eq0 -and $inner -and $inner.ok -and $inner.targetContextVerified -and $inner.extensionContextActive -and $inner.normalChromeUntouched)
  if(($ProbeInput -or $Mode-eq'ProbeExact') -and $pass){$pass=[bool]($inner.inputFound -and $inner.inputVerified -and $inner.inputRestored)}
  [pscustomobject]@{ok=$pass;version=$Version;mode=$Mode;service=$Service;targetUrl=$TargetUrl;launcher='EXACT_TARGET_V2';sourceTransport='GITHUB_CONTENTS_API_SHA_PINNED';exactTargetRequired=$true;contentScriptMarkerRequired=$true;pageOpenAloneNeverPass=$true;loadExtensionAloneNeverPass=$true;inner=$inner;raw=$text}|ConvertTo-Json -Depth 60 -Compress
  if($pass){exit 0}else{exit 2}
}
$args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$ExactLegacy,'-Service',$Service,'-TargetUrl',$TargetUrl,'-ExpectedUrlPattern',$ExpectedUrlPattern,'-ExpectedExtensionId',$ExpectedExtensionId,'-RemoteDebuggingPort',[string]$RemoteDebuggingPort,'-TimeoutSeconds',[string]$TimeoutSeconds)
if($RestartDedicatedChrome -or $Mode-eq'LaunchExact'){$args+='-RestartDedicatedChrome'};if($ProbeInput -or $Mode-eq'ProbeExact'){$args+='-ProbeInput'}
$out=& powershell.exe @args 2>&1;$exit=$LASTEXITCODE;$text=($out|Out-String).Trim();$inner=$null;try{$inner=(($text -split "`r?`n")[-1]|ConvertFrom-Json)}catch{}
$pass=[bool]($exit-eq0 -and $inner -and $inner.ok -and $inner.targetContextVerified -and $inner.normalChromeUntouched);if(($ProbeInput -or $Mode-eq'ProbeExact') -and $pass){$pass=[bool]($inner.inputFound -and $inner.inputVerified -and $inner.inputRestored)}
[pscustomobject]@{ok=$pass;version=$Version;mode=$Mode;service=$Service;targetUrl=$TargetUrl;launcher='LEGACY_NON_NOTEBOOKLM';sourceTransport='GITHUB_CONTENTS_API_SHA_PINNED';exactTargetRequired=$true;pageOpenAloneNeverPass=$true;loadExtensionAloneNeverPass=$true;inner=$inner;raw=$text}|ConvertTo-Json -Depth 60 -Compress
if($pass){exit 0}else{exit 2}
