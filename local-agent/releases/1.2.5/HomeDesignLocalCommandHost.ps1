param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Source=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.0-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalCommandHost-1.2.5-patched.ps1'
$Base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.0/HomeDesignLocalCommandHost.ps1'
$Expected='3cee6a57aa2fd2ab9bcf04f275f4c95296bba247'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
$Url=$Base+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Source -TimeoutSec 30
$Actual=(GitBlobSha1 $Source).ToLowerInvariant();if($Actual -ne $Expected){throw "Host 1.2.0 source hash mismatch actual=$Actual expected=$Expected"}
$Code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$OldVersion="`$HostVersion='1.2.0'";$NewVersion="`$HostVersion='1.2.5'";if(-not $Code.Contains($OldVersion)){throw 'HOST_VERSION_PATCH_TARGET_MISSING'};$Code=$Code.Replace($OldVersion,$NewVersion)
$AllowOld="'tools/Run-VideoFrameQA.ps1')";$AllowNew="'tools/Run-VideoFrameQA.ps1','tools/Run-AgentDashboardPromoProductionE2E.ps1')";if($Code.Contains($AllowOld)){$Code=$Code.Replace($AllowOld,$AllowNew)}
$NotebookAllowOld="scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1')"
$NotebookAllowNew="scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1','local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1','local-agent/governor/InspectRecentNotebookLMDownloads.ps1','local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1','local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1')"
if(-not $Code.Contains($NotebookAllowOld)){throw 'HOST_NOTEBOOK_ALLOWLIST_PATCH_TARGET_MISSING'};$Code=$Code.Replace($NotebookAllowOld,$NotebookAllowNew)
$ContentOsAnchor="[pscustomobject]@{repo='8friend8ship-cloud/notebooklm-webapp-bridge';branch='main';scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1','local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1','local-agent/governor/InspectRecentNotebookLMDownloads.ps1','local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1','local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1')}"
$ContentOsRule=$ContentOsAnchor+",`r`n  [pscustomobject]@{repo='8friend8ship-cloud/contents-os-git';branch='main';scripts=@('tools/Switch-ContentOS-VercelGit.ps1')}"
if(-not $Code.Contains($ContentOsAnchor)){throw 'HOST_CONTENTOS_ALLOWLIST_ANCHOR_MISSING'};$Code=$Code.Replace($ContentOsAnchor,$ContentOsRule)
$DownloadOld='Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $localScript -TimeoutSec 60'
$DownloadNew='Invoke-WebRequest -UseBasicParsing -Uri ($rawUrl+''?hdcb=''+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $localScript -TimeoutSec 8'
if(-not $Code.Contains($DownloadOld)){throw 'HOST_RAW_DOWNLOAD_PATCH_TARGET_MISSING'};$Code=$Code.Replace($DownloadOld,$DownloadNew)
$StreamOld='$stdout='''';$stderr='''';try{$stdout=$outTask.Result}catch{};try{$stderr=$errTask.Result}catch{}'
$StreamNew='$stdout='''';$stderr='''';if($outTask.IsCompleted){try{$stdout=$outTask.Result}catch{}}else{$stdout=''[stdout stream did not close before timeout]''};if($errTask.IsCompleted){try{$stderr=$errTask.Result}catch{}}else{$stderr=''[stderr stream did not close before timeout]''}'
if(-not $Code.Contains($StreamOld)){throw 'HOST_TIMEOUT_STREAM_PATCH_TARGET_MISSING'};$Code=$Code.Replace($StreamOld,$StreamNew)
Set-Content -LiteralPath $Patched -Value $Code -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
exit $LASTEXITCODE
