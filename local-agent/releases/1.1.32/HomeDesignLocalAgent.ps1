param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$BaseRoot=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $BaseRoot 'ChromeUserData'
$ExtensionRoot=Join-Path $BaseRoot 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $BaseRoot 'ChromeForTesting'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.30-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.32-patched.ps1'
$Base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$Expected='4b3503005503f9e3fb91e2eb17c4baa47152935a'
$WakeMarker=Join-Path $Root 'AGENT_1.1.32_CONTROL_CENTER_WAKE.attempted'
$WakeLocal=Join-Path $Root 'AGENT_1.1.32_CONTROL_CENTER_WAKE.json'
$Front='https://notebooklm-webapp-bridge.vercel.app/'

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindChrome{
  if(Test-Path -LiteralPath $CftRoot){$x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1;if($x){return $x.FullName}}
  throw 'DEDICATED_CHROME_EXE_NOT_FOUND'
}
function DedicatedProcs{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$UserData*"})}catch{return @()}}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  return ''
}
function WriteCentral([string]$Name,[string]$Json){$central=FindCentral;if(-not $central){return $false};try{$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$Json|Set-Content -LiteralPath (Join-Path $dest $Name) -Encoding UTF8;return $true}catch{return $false}}
function WakeDedicatedControlCenterOnce{
  if(Test-Path -LiteralPath $WakeMarker){return [ordered]@{ok=$true;action='DEDICATED_CONTROL_CENTER_WAKE';skipped='VERSION_MARKER_EXISTS';marker=$WakeMarker;at=(Get-Date).ToString('o')}}
  $before=@(DedicatedProcs).Count
  $chrome=FindChrome
  $args=@("--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-tab','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$Front)
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  Start-Sleep -Seconds 8
  $after=@(DedicatedProcs).Count
  $result=[ordered]@{
    ok=($after -gt 0)
    action='DEDICATED_CONTROL_CENTER_WAKE'
    version='1.1.32'
    reason='D82_READY_UNCLAIMED_AFTER_FRESH_SELF_HEAL; refresh existing control-center session handoff and wake extension surface once'
    dedicatedBefore=$before
    dedicatedAfter=$after
    frontUrl=$Front
    normalChromeUntouched=$true
    extensionRootPresent=(Test-Path -LiteralPath $ExtensionRoot)
    userDataPresent=(Test-Path -LiteralPath $UserData)
    newOAuth=$false
    newScope=$false
    publicPublish=$false
    destructive=$false
    at=(Get-Date).ToString('o')
  }
  $json=$result|ConvertTo-Json -Depth 12
  $json|Set-Content -LiteralPath $WakeLocal -Encoding UTF8
  [void](WriteCentral 'AGENT_1.1.32_CONTROL_CENTER_WAKE.json' $json)
  Set-Content -LiteralPath $WakeMarker -Value $result.at -Encoding ASCII
  return $result
}

Invoke-WebRequest -UseBasicParsing -Uri ($Base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Source -TimeoutSec 30
$Actual=(GitBlobSha1 $Source).ToLowerInvariant();if($Actual -ne $Expected){throw "Agent 1.1.30 source hash mismatch actual=$Actual expected=$Expected"}
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$replacements=[ordered]@{
  "`$AgentVersion='1.1.30'"="`$AgentVersion='1.1.32'"
  "`$HostVersion='1.2.5'"="`$HostVersion='1.2.6'"
  "AGENT_1.1.30_RECOVERY.json"="AGENT_1.1.32_RECOVERY.json"
  "/local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1"="/local-agent/releases/1.2.6/HomeDesignLocalCommandHost.ps1"
  "`$HostExpected='e6a79fbb113a79e19650b2864072f6abde5bcffb'"="`$HostExpected='5d17bb233706897cd1706930cea9af3796f29488'"
  "StartHost125"="StartHost126"
  "EnsureHost125"="EnsureHost126"
  "HOST_1.2.5_START_FAILED"="HOST_1.2.6_START_FAILED"
  "HOST125_FIRST_AUTORESUME_1.1.30"="HOST126_FIRST_AUTORESUME_1.1.32"
  "AGENT_1.1.30_HOST125_FIRST_AUTORESUME"="AGENT_1.1.32_HOST126_FIRST_AUTORESUME"
}
foreach($old in $replacements.Keys){if(-not $Code.Contains($old)){throw ('AGENT_PATCH_TARGET_MISSING:'+ $old)};$Code=$Code.Replace($old,[string]$replacements[$old])}
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
$rc=$LASTEXITCODE
if($rc -eq 0){
  try{(WakeDedicatedControlCenterOnce)|ConvertTo-Json -Depth 12 -Compress|Write-Output}catch{
    $err=[ordered]@{ok=$false;action='DEDICATED_CONTROL_CENTER_WAKE';version='1.1.32';error=$_.Exception.Message;normalChromeUntouched=$true;at=(Get-Date).ToString('o')}
    $json=$err|ConvertTo-Json -Depth 8
    $json|Set-Content -LiteralPath $WakeLocal -Encoding UTF8
    [void](WriteCentral 'AGENT_1.1.32_CONTROL_CENTER_WAKE.json' $json)
  }
}
exit $rc
