param(
  [string]$TaskId = 'NLM_VIDEO_EXISTING_QUEENS_FIRST',
  [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=180
)
$ErrorActionPreference='Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$downloadScript = Join-Path $here 'RunNotebookLMDirectCDPDownloadSyncedV3.ps1'
$queensScript = Join-Path $here 'MirrorNotebookLMArtifactQueensFirst.ps1'
if (-not (Test-Path -LiteralPath $downloadScript -PathType Leaf)) { throw 'DIRECT_CDP_DOWNLOAD_SCRIPT_NOT_FOUND' }
if (-not (Test-Path -LiteralPath $queensScript -PathType Leaf)) { throw 'QUEENS_FIRST_SCRIPT_NOT_FOUND' }

function Invoke-DownloadAttempt([string]$label) {
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
  $escapedUrl=$NotebookUrl.Replace('"','\"');$escapedLabel=$label.Replace('"','\"')
  $psi.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$downloadScript`" -NotebookUrl `"$escapedUrl`" -ArtifactText `"$escapedLabel`" -RemoteDebuggingPort $RemoteDebuggingPort -TimeoutSeconds $TimeoutSeconds"
  $p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$stdout=$p.StandardOutput.ReadToEnd();$stderr=$p.StandardError.ReadToEnd();$p.WaitForExit();$exitCode=$p.ExitCode
  $lines=@(([string]$stdout -split "`r?`n")|Where-Object{$_ -ne ''});if($stderr){$lines+=([string]$stderr -split "`r?`n")}
  $jsonLine=@($lines|Where-Object{$_ -match '^\s*\{'}|Select-Object -Last 1);$obj=$null;if($jsonLine.Count){try{$obj=$jsonLine[0]|ConvertFrom-Json}catch{}}
  [pscustomobject]@{label=$label;exitCode=$exitCode;raw=$lines;result=$obj}
}

$attempts=New-Object System.Collections.Generic.List[object];$download=$null
foreach($label in @('동영상 개요','Video Overview','video overview')){
  $a=Invoke-DownloadAttempt $label;$attempts.Add($a)
  if($a.exitCode -eq 0 -and $a.result -and $a.result.ok -and @($a.result.files).Count -gt 0){$download=$a.result;break}
  $err=if($a.result){[string]$a.result.error}else{''};if($err -and $err -notmatch 'ARTIFACT_MENU_NOT_FOUND|NOTEBOOK_TAB_NOT_FOUND'){break}
}
if(-not$download){$summary=@($attempts|ForEach-Object{[pscustomobject]@{label=$_.label;exitCode=$_.exitCode;error=if($_.result){[string]$_.result.error}else{'NO_JSON_RESULT'}}});throw('VIDEO_EXISTING_DOWNLOAD_FAILED:'+($summary|ConvertTo-Json -Compress))}
$file=@($download.files|Where-Object{[int64]$_.size -gt 0 -and ([string]$_.extension).ToLowerInvariant() -in @('.mp4','.webm','.mov')}|Select-Object -First 1)
if($file.Count -lt 1){throw('VIDEO_NATIVE_FILE_NOT_FOUND:'+(($download.files|ConvertTo-Json -Compress -Depth 10)))}
$sourcePath=[string]$file[0].fullName;if(-not(Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw('VIDEO_SOURCE_PATH_MISSING:'+$sourcePath)}

try{$rawQueens=@(& $queensScript -TaskId $TaskId -ArtifactType 'VIDEO_OVERVIEW' -SourcePath $sourcePath -TimeoutSeconds $TimeoutSeconds 2>&1)}catch{throw('VIDEO_QUEENS_FIRST_EXCEPTION:'+$_.Exception.Message)}
$qLines=@($rawQueens|ForEach-Object{[string]$_});$qJsonLine=@($qLines|Where-Object{$_ -match '^\s*\{'}|Select-Object -Last 1)
if($qJsonLine.Count -lt 1){throw('VIDEO_QUEENS_FIRST_NO_JSON:output='+($qLines -join ' | '))}
$q=$qJsonLine[0]|ConvertFrom-Json
if(-not$q.ok -or -not$q.nativeOriginalVerified -or -not$q.sourceImmutable -or [int64]$q.nativeOriginalBytes -le 0){throw'VIDEO_QUEENS_FIRST_NOT_VERIFIED'}
if($q.seedEligible -ne $false -or $q.seedVerified -ne $false){throw'SEED_MUST_REMAIN_GATED_UNTIL_QUEENS_URL_VERIFIED'}
if($q.johnsonEligible){throw'JOHNSON_MUST_REMAIN_GATED'}

[pscustomobject]@{ok=$true;action='NOTEBOOKLM_EXISTING_VIDEO_QUEENS_FIRST_V1';taskId=$TaskId;artifactType='VIDEO_OVERVIEW';generationUsed=$false;download=$download;nativeOriginalVerified=[bool]$q.nativeOriginalVerified;sourceImmutable=[bool]$q.sourceImmutable;nativeOriginalPath=[string]$q.nativeOriginalPath;nativeOriginalName=[string]$q.nativeOriginalName;nativeOriginalBytes=[int64]$q.nativeOriginalBytes;sha256=[string]$q.sha256;assetId=[string]$q.assetId;queensStatus=[string]$q.queensStatus;queensUrlVerified=[bool]$q.queensUrlVerified;queensSidecarPath=[string]$q.queensSidecarPath;seedEligible=[bool]$q.seedEligible;seedVerified=[bool]$q.seedVerified;johnsonEligible=[bool]$q.johnsonEligible;nextGate=[string]$q.nextGate;completedAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 30 -Compress
