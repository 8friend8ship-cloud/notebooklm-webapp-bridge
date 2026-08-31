param()
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.127/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$tmp=Join-Path $env:TEMP 'HomeDesignLocalAgent_1.1.128_probe.ps1'
Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $tmp -TimeoutSec 20
function LastJson([string]$Text){$p=$null;foreach($line in @($Text -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 40)){try{$j=$line|ConvertFrom-Json;if($j){$p=$j}}catch{}};$p}
$last=$null
for($i=1;$i-le20;$i++){
  $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1|Out-String
  $last=LastJson $out
  if($last-and[bool]$last.ok-and[bool]$last.ready){$last|ConvertTo-Json -Depth 80 -Compress;exit 0}
  if($i-lt20){Start-Sleep -Seconds 12}
}
if($last){$last|ConvertTo-Json -Depth 80 -Compress;exit 0}
throw 'READINESS_PROBE_NO_JSON'
