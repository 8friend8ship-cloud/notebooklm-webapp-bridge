from pathlib import Path
import base64, hashlib

basep=Path('local-agent/releases/1.2.0/HomeDesignLocalCommandHost.ps1')
diagp=Path('local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1')
s=basep.read_text(encoding='utf-8')
s=s.replace("$HostVersion='1.2.0'","$HostVersion='1.2.9'",1)
s=s.replace("'tools/Run-VideoFrameQA.ps1')","'tools/Run-VideoFrameQA.ps1','tools/Run-AgentDashboardPromoProductionE2E.ps1')",1)
old="scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1')"
scripts="@('local-agent/governor/RunChromeGovernorReadback.ps1','local-agent/governor/RunChromeGovernorReadbackV2.ps1','local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1','local-agent/governor/InspectRecentNotebookLMDownloads.ps1','local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1','local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1','local-agent/capture/ManageChromeExtensionArtifacts.ps1','local-agent/capture/Setup-ChromeExtensionCaptureBridge.ps1','local-agent/governor/ManagedExtensionAutopilotV2.ps1','local-agent/governor/ManagedExtensionExactTargetLauncher.ps1','local-agent/governor/Run-ExactTargetNotebookLMRegression.ps1','local-agent/governor/Sync-CentralLearningQaAppsScript.ps1','local-agent/governor/Run-GeminiWebLearningQa.ps1','local-agent/governor/Inspect-FlowApprovedAccountCredits.ps1')"
if old not in s:
    raise SystemExit('HOST_NOTEBOOK_ALLOWLIST_PATCH_TARGET_MISSING')
s=s.replace(old,'scripts='+scripts,1)
anchor="[pscustomobject]@{repo='8friend8ship-cloud/notebooklm-webapp-bridge';branch='main';scripts="+scripts+'}'
if anchor not in s:
    raise SystemExit('HOST_CONTENTOS_ALLOWLIST_ANCHOR_MISSING')
rule=anchor+",\n  [pscustomobject]@{repo='8friend8ship-cloud/contents-os-git';branch='main';scripts=@('tools/Switch-ContentOS-VercelGit.ps1','tools/Repair-ContentOS-DriveCacheAppsScript.ps1')}"
s=s.replace(anchor,rule,1)
olddl='Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $localScript -TimeoutSec 60'
newdl="Invoke-WebRequest -UseBasicParsing -Uri ($rawUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $localScript -TimeoutSec 8"
if olddl not in s:
    raise SystemExit('HOST_RAW_DOWNLOAD_PATCH_TARGET_MISSING')
s=s.replace(olddl,newdl,1)
oldstream="$stdout='';$stderr='';try{$stdout=$outTask.Result}catch{};try{$stderr=$errTask.Result}catch{}"
newstream="$stdout='';$stderr='';if($outTask.IsCompleted){try{$stdout=$outTask.Result}catch{}}else{$stdout='[stdout stream did not close before timeout]'};if($errTask.IsCompleted){try{$stderr=$errTask.Result}catch{}}else{$stderr='[stderr stream did not close before timeout]'}"
if oldstream not in s:
    raise SystemExit('HOST_TIMEOUT_STREAM_PATCH_TARGET_MISSING')
s=s.replace(oldstream,newstream,1)
host_bytes=s.encode('utf-8')
gitsha=hashlib.sha1(b'blob '+str(len(host_bytes)).encode()+b'\0'+host_bytes).hexdigest()
payload=base64.b64encode(host_bytes).decode('ascii')
Path('local-agent/releases/1.2.9/HomeDesignLocalCommandHost.final.ps1').write_text(s,encoding='utf-8',newline='\n')
Path('local-agent/releases/1.2.9/embedded-host129.sha1').write_text(gitsha+'\n',encoding='utf-8')

d=diagp.read_text(encoding='utf-8')
start=d.index('if($KickAgent1155HostRepair){')
end=d.index('if($KickAgent1141HostRepair){',start)
block="""if($KickAgent1155HostRepair){
  try{
    New-Item -ItemType Directory -Force -Path $Root|Out-Null
    $canonical=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
    $tmp=$canonical+'.embedded129'
    $payload='__PAYLOAD__'
    [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String($payload))
    $expected='__SHA__'
    $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
    if($actual -ne $expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('EMBEDDED_HOST129_HASH_MISMATCH actual='+$actual+' expected='+$expected)}
    Move-Item -LiteralPath $tmp -Destination $canonical -Force
    $helper=Join-Path $Root 'Apply-EmbeddedHost129.ps1'
    $helperCode=@'
param([string]$HostPath,[string]$ReceiptPath)
$ErrorActionPreference='Continue'
Start-Sleep -Seconds 3
try{
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine) -match 'HomeDesignLocalCommandHost' -and ([string]$_.CommandLine) -notmatch 'Apply-EmbeddedHost129'})){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}
}catch{}
Start-Sleep -Milliseconds 800
$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$HostPath+'"';$proc=[Diagnostics.Process]::Start($psi)
$deadline=(Get-Date).AddSeconds(30);$health=$null
while((Get-Date)-lt $deadline){Start-Sleep -Milliseconds 500;try{$health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 2;if($health -and [bool]$health.ok -and [string]$health.version -eq '1.2.9' -and [bool]$health.asyncJobs){break}}catch{}}
$ok=[bool]($health -and [bool]$health.ok -and [string]$health.version -eq '1.2.9' -and [bool]$health.asyncJobs)
$o=[ordered]@{ok=$ok;action='EMBEDDED_HOST129_APPLY_READBACK';hostVersion=$(if($health){[string]$health.version}else{''});hostHealthy=$(if($health){[bool]$health.ok}else{$false});hostAsyncJobs=$(if($health){[bool]$health.asyncJobs}else{$false});pid=$(if($proc){[int]$proc.Id}else{$null});at=(Get-Date).ToString('o')}
if($ReceiptPath){try{$par=Split-Path -Parent $ReceiptPath;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};$o|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{}}
'@
    Set-Content -LiteralPath $helper -Value $helperCode -Encoding UTF8
    $central=Find-CentralRoot;$receipt=$(if($central){Join-Path $central 'Runtime_Readback\\EMBEDDED_HOST129_APPLY_READBACK.json'}else{''})
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -HostPath "'+$canonical+'" -ReceiptPath "'+$receipt+'"';$proc=[Diagnostics.Process]::Start($psi)
    [ordered]@{ok=$true;action='EMBEDDED_HOST129_RECOVERY_DISPATCHED';taskId=$TaskId;hostBlobSha1=$actual;pid=[int]$proc.Id;expectedHost='1.2.9';sourceFetchMode='INLINE_EMBEDDED_NO_SECONDARY_NETWORK';normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='EMBEDDED_HOST129_RECOVERY_DISPATCHED';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

""".replace('__PAYLOAD__',payload).replace('__SHA__',gitsha)
diagp.write_text(d[:start]+block+d[end:],encoding='utf-8',newline='\n')
print(gitsha)
