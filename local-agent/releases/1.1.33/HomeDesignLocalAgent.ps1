param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.30-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.33-patched.ps1'
$Base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$Expected='4b3503005503f9e3fb91e2eb17c4baa47152935a'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
Invoke-WebRequest -UseBasicParsing -Uri ($Base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Source -TimeoutSec 30
$Actual=(GitBlobSha1 $Source).ToLowerInvariant();if($Actual -ne $Expected){throw "Agent 1.1.30 source hash mismatch actual=$Actual expected=$Expected"}
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$replacements=[ordered]@{
  "`$AgentVersion='1.1.30'"="`$AgentVersion='1.1.33'"
  "`$HostVersion='1.2.5'"="`$HostVersion='1.2.6'"
  "AGENT_1.1.30_RECOVERY.json"="AGENT_1.1.33_RECOVERY.json"
  "/local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1"="/local-agent/releases/1.2.6/HomeDesignLocalCommandHost.ps1"
  "`$HostExpected='e6a79fbb113a79e19650b2864072f6abde5bcffb'"="`$HostExpected='5d17bb233706897cd1706930cea9af3796f29488'"
  "StartHost125"="StartHost126"
  "EnsureHost125"="EnsureHost126"
  "HOST_1.2.5_START_FAILED"="HOST_1.2.6_START_FAILED"
  "HOST125_FIRST_AUTORESUME_1.1.30"="HOST126_FIRST_AUTORESUME_1.1.33"
  "AGENT_1.1.30_HOST125_FIRST_AUTORESUME"="AGENT_1.1.33_HOST126_FIRST_AUTORESUME"
}
foreach($old in $replacements.Keys){if(-not $Code.Contains($old)){throw ('AGENT_PATCH_TARGET_MISSING:'+ $old)};$Code=$Code.Replace($old,[string]$replacements[$old])}
$exitNeedle="if(`$result.ok){exit 0}else{exit 2}"
if(-not $Code.Contains($exitNeedle)){throw 'INLINE_WAKE_EXIT_TARGET_MISSING'}
$inline=@'
# D103 changed-condition diagnostic: do not blindly repeat the 1.1.32 wake.
$priorMarker=Join-Path $Root 'AGENT_1.1.32_CONTROL_CENTER_WAKE.attempted'
$priorLocal=Join-Path $Root 'AGENT_1.1.32_CONTROL_CENTER_WAKE.json'
$marker=Join-Path $Root 'AGENT_1.1.33_EXTENSION_WAKE_DIAGNOSTIC.attempted'
$diagFile=Join-Path $Root 'AGENT_1.1.33_EXTENSION_WAKE_DIAGNOSTIC.json'
$front='https://notebooklm-webapp-bridge.vercel.app/'
$diag=[ordered]@{
  ok=$false; action='AGENT_1.1.33_EXTENSION_WAKE_DIAGNOSTIC'; version='1.1.33';
  prior132MarkerPresent=(Test-Path -LiteralPath $priorMarker); prior132LocalEvidencePresent=(Test-Path -LiteralPath $priorLocal);
  wakePerformed=$false; wakeSkippedReason=''; dedicatedBefore=(Dedicated).Count; dedicatedAfter=0;
  normalChromeUntouched=$true; tokenContentsRead=$false; newOAuth=$false; newScope=$false; publicPublish=$false; destructive=$false;
  error=''; at=(Get-Date).ToString('o')
}
try{
  if(Test-Path -LiteralPath $marker){
    $diag.wakeSkippedReason='VERSION_MARKER_EXISTS'
  }elseif($diag.prior132MarkerPresent){
    $diag.wakeSkippedReason='PRIOR_1.1.32_WAKE_MARKER_PRESENT_NO_REPEAT'
    Set-Content -LiteralPath $marker -Value (Get-Date).ToString('o') -Encoding ASCII
  }else{
    $c=FindChrome;if(-not $c){throw 'DEDICATED_CHROME_EXE_NOT_FOUND'}
    $args=@("--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-tab','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$front)
    Start-Process -FilePath $c.FullName -WorkingDirectory $c.Directory.FullName -ArgumentList $args|Out-Null
    Start-Sleep -Seconds 8
    $diag.wakePerformed=$true
    Set-Content -LiteralPath $marker -Value (Get-Date).ToString('o') -Encoding ASCII
  }
  $diag.dedicatedAfter=(Dedicated).Count
  $diag.ok=($diag.dedicatedAfter -gt 0)
}catch{$diag.error=$_.Exception.Message;$diag.dedicatedAfter=(Dedicated).Count}
$diag.at=(Get-Date).ToString('o')
$diagJson=$diag|ConvertTo-Json -Depth 12
$diagJson|Set-Content -LiteralPath $diagFile -Encoding UTF8
[void](WriteCentral 'AGENT_1.1.33_EXTENSION_WAKE_DIAGNOSTIC.json' $diagJson)
if($result.ok){exit 0}else{exit 2}
'@
$Code=$Code.Replace($exitNeedle,$inline)
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
exit $LASTEXITCODE
