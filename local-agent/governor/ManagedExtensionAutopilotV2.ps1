param(
  [ValidateSet('Inventory','SyncRegistry','Stage','Rollback','LaunchExact','ProbeExact')]
  [string]$Mode='Inventory',
  [ValidateSet('NOTEBOOKLM','FLOW','AI_STUDIO','FRONT_QA','CENTRAL_CAPTURE','GENERIC')]
  [string]$Service='GENERIC',
  [string]$TargetUrl='',
  [string]$ExpectedUrlPattern='',
  [string]$ExpectedExtensionId='',
  [string]$RegistryUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/config/managed-extension-autopilot-v1.json',
  [string]$SourceZip='',
  [string]$SourceDir='',
  [string]$SourceUrl='',
  [string]$ManifestSubPath='',
  [int]$RemoteDebuggingPort=9230,
  [int]$TimeoutSeconds=35,
  [switch]$Apply,
  [switch]$RestartDedicatedChrome,
  [switch]$ProbeInput
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Version='MANAGED_EXTENSION_AUTOPILOT_V2_20260828'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$ToolRoot=Join-Path $Base 'ManagedExtensions\Tools';New-Item -ItemType Directory -Force -Path $ToolRoot|Out-Null
$Legacy=Join-Path $ToolRoot 'ManagedExtensionAutopilot-v1.ps1'
$Exact=Join-Path $ToolRoot 'ManagedExtensionExactTargetLauncher-v1.ps1'
$LegacySha='6f4acb1f1c0d6f37fd675b55cd2f8a3a349f7ec4'
$ExactSha='d352572c532aea3e2d76b580e2129bfa3fa4d68b'
function GitBlob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Fetch([string]$rel,[string]$dest,[string]$sha){$tmp=$dest+'.download';$url='https://raw.githubusercontent.com/'+$Repo+'/main/'+$rel+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 30;$actual=(GitBlob $tmp).ToLowerInvariant();if($actual -ne $sha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('SOURCE_SHA_MISMATCH:'+ $rel+':'+$actual+':'+$sha)};Move-Item $tmp $dest -Force}
Fetch 'local-agent/governor/ManagedExtensionAutopilot.ps1' $Legacy $LegacySha
Fetch 'local-agent/governor/ManagedExtensionExactTargetLauncher.ps1' $Exact $ExactSha
function DefaultRoute([string]$svc){switch($svc){'NOTEBOOKLM'{return [pscustomobject]@{url='https://notebook.google.com/';pattern='notebook(lm)?\.google\.com';id='llgjlejpknemhdmckoaifgjnjikceamp'}}'FLOW'{return [pscustomobject]@{url='https://labs.google/fx/tools/flow';pattern='labs\.google/.*/flow|labs\.google/fx/tools/flow';id='lgedgmpcikglaajhfclcihicgafimlna'}}'AI_STUDIO'{return [pscustomobject]@{url='https://aistudio.google.com/';pattern='aistudio\.google\.com';id='okppbdphadmdfbfpllpjjnmmemokbccp'}}default{return [pscustomobject]@{url='';pattern='';id=$ExpectedExtensionId}}}}
if($Mode -in @('Inventory','SyncRegistry','Stage','Rollback')){
  $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Legacy,'-Mode',$Mode,'-RegistryUrl',$RegistryUrl)
  if($SourceZip){$args+=@('-SourceZip',$SourceZip)};if($SourceDir){$args+=@('-SourceDir',$SourceDir)};if($SourceUrl){$args+=@('-SourceUrl',$SourceUrl)};if($ManifestSubPath){$args+=@('-ManifestSubPath',$ManifestSubPath)};if($ExpectedExtensionId){$args+=@('-ExpectedExtensionId',$ExpectedExtensionId)};if($Apply){$args+='-Apply'}
  # Deliberately do not pass RestartDedicatedChrome here. V2 forbids generic chrome://extensions launch as an execution success path.
  $out=& powershell.exe @args 2>&1;$exit=$LASTEXITCODE
  [pscustomobject]@{ok=($exit -eq 0);version=$Version;mode=$Mode;legacyStageOnly=$true;genericLaunchSuppressed=$true;output=($out|Out-String).Trim()}|ConvertTo-Json -Depth 30
  exit $exit
}
$route=DefaultRoute $Service
if(-not $TargetUrl){$TargetUrl=$route.url};if(-not $ExpectedUrlPattern){$ExpectedUrlPattern=$route.pattern};if(-not $ExpectedExtensionId){$ExpectedExtensionId=$route.id}
if(-not $TargetUrl){throw 'EXACT_TARGET_URL_REQUIRED'}
$args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Exact,'-Service',$Service,'-TargetUrl',$TargetUrl,'-ExpectedUrlPattern',$ExpectedUrlPattern,'-ExpectedExtensionId',$ExpectedExtensionId,'-RemoteDebuggingPort',[string]$RemoteDebuggingPort,'-TimeoutSeconds',[string]$TimeoutSeconds)
if($RestartDedicatedChrome -or $Mode -eq 'LaunchExact'){$args+='-RestartDedicatedChrome'}
if($ProbeInput -or $Mode -eq 'ProbeExact'){$args+='-ProbeInput'}
$out=& powershell.exe @args 2>&1;$exit=$LASTEXITCODE;$text=($out|Out-String).Trim();$inner=$null;try{$inner=(($text -split "`r?`n")[-1]|ConvertFrom-Json)}catch{}
$pass=[bool]($exit -eq 0 -and $inner -and $inner.ok -and $inner.targetContextVerified -and $inner.normalChromeUntouched)
if(($ProbeInput -or $Mode -eq 'ProbeExact') -and $pass){$pass=[bool]($inner.inputFound -and $inner.inputVerified -and $inner.inputRestored)}
[pscustomobject]@{ok=$pass;version=$Version;mode=$Mode;service=$Service;targetUrl=$TargetUrl;exactTargetRequired=$true;pageOpenAloneNeverPass=$true;loadExtensionAloneNeverPass=$true;inner=$inner;raw=$text}|ConvertTo-Json -Depth 60 -Compress
if($pass){exit 0}else{exit 2}
