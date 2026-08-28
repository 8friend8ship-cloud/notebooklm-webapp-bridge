param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.30-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.34-patched.ps1'
$Base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$Expected='4b3503005503f9e3fb91e2eb17c4baa47152935a'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
Invoke-WebRequest -UseBasicParsing -Uri ($Base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Source -TimeoutSec 30
$Actual=(GitBlobSha1 $Source).ToLowerInvariant();if($Actual -ne $Expected){throw "Agent 1.1.30 source hash mismatch actual=$Actual expected=$Expected"}
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$replacements=[ordered]@{
  "`$AgentVersion='1.1.30'"="`$AgentVersion='1.1.34'"
  "`$HostVersion='1.2.5'"="`$HostVersion='1.2.7'"
  "AGENT_1.1.30_RECOVERY.json"="AGENT_1.1.34_RECOVERY.json"
  "/local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1"="/local-agent/releases/1.2.7/HomeDesignLocalCommandHost.ps1"
  "`$HostExpected='e6a79fbb113a79e19650b2864072f6abde5bcffb'"="`$HostExpected='ac4aae953fae2219d393de2307ef655b0988c9f4'"
  "StartHost125"="StartHost127"
  "EnsureHost125"="EnsureHost127"
  "HOST_1.2.5_START_FAILED"="HOST_1.2.7_START_FAILED"
  "HOST125_FIRST_AUTORESUME_1.1.30"="HOST127_FIRST_AUTORESUME_1.1.34"
  "AGENT_1.1.30_HOST125_FIRST_AUTORESUME"="AGENT_1.1.34_HOST127_FIRST_AUTORESUME"
}
foreach($old in $replacements.Keys){if(-not $Code.Contains($old)){throw ('AGENT_PATCH_TARGET_MISSING:'+ $old)};$Code=$Code.Replace($old,[string]$replacements[$old])}
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
$rc=$LASTEXITCODE
if($rc -eq 0){
  try{
    $central=''
    $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
      $r=[string]$d.Root;if(-not $r){continue}
      foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){$central=$c;break}}
      if($central){break}
    }
    $receipt=[ordered]@{ok=$true;action='CONTENTOS_REPAIR_ALLOWLIST_READY';agentVersion='1.1.34';hostVersion='1.2.7';repo='8friend8ship-cloud/contents-os-git';branch='main';allowedScripts=@('tools/Switch-ContentOS-VercelGit.ps1','tools/Repair-ContentOS-DriveCacheAppsScript.ps1');newOAuth=$false;newScope=$false;publicPublish=$false;destructive=$false;at=(Get-Date).ToString('o')}
    $json=$receipt|ConvertTo-Json -Depth 10
    if($central){$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest 'AGENT_1.1.34_CONTENTOS_REPAIR_ALLOWLIST.json') -Encoding UTF8}
    $json -replace "`r?`n",'' | Write-Output
  }catch{Write-Warning ('ALLOWLIST_RECEIPT_WRITE_FAILED:'+ $_.Exception.Message)}
}
exit $rc
