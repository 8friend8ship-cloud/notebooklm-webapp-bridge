param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.131'
$ExpectedSha='1f14e203d0d8a7a2939803fb5a04e92386d95b35cc313e3c7f4a74083ef0e74c'
$ExpectedBytes=35482290
$SourceNameB64='7ZqM7IKs66W8X+2GteynuOuhnF/snpDrj5ntmZTtlZjripRfQUlf7JuM7YGs7ZSM66GcLm00YQ=='
$DestNameB64='MjAyNi0wOC0zMF9Db250ZW50T1NfQUnsvZjthZDsuKDsg53sgrDsm4ztgaztlIzroZzsmrBf66as7ISc7LmYX19BVURJT19PVkVSVklFV19f7ZqM7IKs66W8X+2GteynuOuhnF/snpDrj5ntmZTtlZjripRfQUlf7JuM7YGs7ZSM66GcLm00YQ=='
$InboxB64='QzpcSG9tZURlc2lnbkF1dG9tYXRpb25WN1xDYXB0dXJlQnJpZGdlXElOQk9YXE5vdGVib29rTE0='
function U([string]$b){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b))}
$SourceName=U $SourceNameB64;$DestName=U $DestNameB64;$Inbox=U $InboxB64
$Source=Join-Path (Join-Path $env:USERPROFILE 'Downloads') $SourceName
$Dest=Join-Path $Inbox $DestName
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='AGENT_1.1.131_CAPTUREBRIDGE_AUDIO_HANDOFF_RESULT.json'
$Marker=Join-Path $Root $Receipt
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Sha([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$root=[string]$d.Root;if(-not $root){continue};foreach($c in @((Join-Path $root $target),(Join-Path $root ($my+'\'+$target)),(Join-Path $root ('My Drive\'+$target)),(Join-Path $root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function Save($o){$j=$o|ConvertTo-Json -Depth 60;$j|Set-Content -LiteralPath $Marker -Encoding UTF8;try{$c=FindCentral;if($c){$dir=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$j|Set-Content -LiteralPath (Join-Path $dir $Receipt) -Encoding UTF8}}catch{}}
$r=[ordered]@{ok=$false;action='AGENT_1.1.131_CAPTUREBRIDGE_AUDIO_HANDOFF';version=$Version;startedAt=(Get-Date).ToString('o');source=$Source;expectedBytes=$ExpectedBytes;expectedSha256=$ExpectedSha;sourceVerified=$false;captureInbox=$Inbox;destination=$Dest;copied=$false;destinationBytes=0;destinationSha256='';sourceImmutableVerified=$false;scheduledTask='HomeDesign-CaptureBridge-ManagedChrome-Reconcile';scheduledTaskExists=$false;scheduledTaskRunning=$false;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;stage='START';error=''}
try{
  $r.stage='SOURCE_VERIFY'
  if(-not (Test-Path -LiteralPath $Source -PathType Leaf)){throw 'VERIFIED_AUDIO_SOURCE_NOT_FOUND'}
  $s=Get-Item -LiteralPath $Source
  $ssh=Sha $Source
  if([int64]$s.Length -ne [int64]$ExpectedBytes){throw ('SOURCE_SIZE_MISMATCH actual='+$s.Length)}
  if($ssh -ne $ExpectedSha){throw ('SOURCE_SHA_MISMATCH actual='+$ssh)}
  $r.sourceVerified=$true
  $r.stage='CAPTURE_INBOX_COPY'
  New-Item -ItemType Directory -Force -Path $Inbox|Out-Null
  if(Test-Path -LiteralPath $Dest -PathType Leaf){$old=Get-Item -LiteralPath $Dest;$oldSha=Sha $Dest;if($old.Length -eq $s.Length -and $oldSha -eq $ExpectedSha){$r.copied=$true}else{Remove-Item -LiteralPath $Dest -Force}}
  if(-not $r.copied){Copy-Item -LiteralPath $Source -Destination $Dest -Force;$r.copied=$true}
  $d=Get-Item -LiteralPath $Dest
  $dsha=Sha $Dest
  $r.destinationBytes=[int64]$d.Length
  $r.destinationSha256=$dsha
  $sourceAfter=Sha $Source
  $r.sourceImmutableVerified=($sourceAfter -eq $ExpectedSha)
  if($d.Length -ne $s.Length -or $dsha -ne $ExpectedSha -or -not $r.sourceImmutableVerified){throw 'CAPTURE_INBOX_COPY_INTEGRITY_FAILED'}
  try{$q=& schtasks.exe /Query /TN $r.scheduledTask /FO LIST /V 2>$null|Out-String;if($LASTEXITCODE -eq 0){$r.scheduledTaskExists=$true;$r.scheduledTaskRunning=($q -match '(?i)Running')}}catch{}
  $r.ok=$true
  $r.stage='DONE'
}catch{$r.error=$_.Exception.Message;$r.stage='ERROR'}finally{$r.completedAt=(Get-Date).ToString('o');Save $r}
$r|ConvertTo-Json -Depth 60 -Compress
if($r.ok){exit 0}else{exit 2}
