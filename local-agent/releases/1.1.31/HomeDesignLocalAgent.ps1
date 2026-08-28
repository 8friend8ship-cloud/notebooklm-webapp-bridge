param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.30-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.31-patched.ps1'
$Base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$Expected='4b3503005503f9e3fb91e2eb17c4baa47152935a'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
Invoke-WebRequest -UseBasicParsing -Uri ($Base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Source -TimeoutSec 30
$Actual=(GitBlobSha1 $Source).ToLowerInvariant();if($Actual -ne $Expected){throw "Agent 1.1.30 source hash mismatch actual=$Actual expected=$Expected"}
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$replacements=[ordered]@{
  "`$AgentVersion='1.1.30'"="`$AgentVersion='1.1.31'"
  "`$HostVersion='1.2.5'"="`$HostVersion='1.2.6'"
  "AGENT_1.1.30_RECOVERY.json"="AGENT_1.1.31_RECOVERY.json"
  "/local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1"="/local-agent/releases/1.2.6/HomeDesignLocalCommandHost.ps1"
  "`$HostExpected='e6a79fbb113a79e19650b2864072f6abde5bcffb'"="`$HostExpected='5d17bb233706897cd1706930cea9af3796f29488'"
  "StartHost125"="StartHost126"
  "EnsureHost125"="EnsureHost126"
  "HOST_1.2.5_START_FAILED"="HOST_1.2.6_START_FAILED"
  "HOST125_FIRST_AUTORESUME_1.1.30"="HOST126_FIRST_AUTORESUME_1.1.31"
  "AGENT_1.1.30_HOST125_FIRST_AUTORESUME"="AGENT_1.1.31_HOST126_FIRST_AUTORESUME"
}
foreach($old in $replacements.Keys){if(-not $Code.Contains($old)){throw ('AGENT_PATCH_TARGET_MISSING:'+ $old)};$Code=$Code.Replace($old,[string]$replacements[$old])}
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
exit $LASTEXITCODE