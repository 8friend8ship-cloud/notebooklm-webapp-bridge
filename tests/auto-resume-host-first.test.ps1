$ErrorActionPreference='Stop'

$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hostSourcePath=Join-Path $repoRoot 'local-agent/releases/1.2.0/HomeDesignLocalCommandHost.ps1'
$hostWrapperPath=Join-Path $repoRoot 'local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1'
$agentPath=Join-Path $repoRoot 'local-agent/releases/1.1.29/HomeDesignLocalAgent.ps1'
$stablePath=Join-Path $repoRoot 'local-agent/stable/agent.json'

foreach($path in @($hostSourcePath,$hostWrapperPath,$agentPath,$stablePath)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "MISSING_FILE:$path"}
}

$parseTargets=@($hostWrapperPath,$agentPath)
foreach($path in $parseTargets){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ("POWERSHELL_PARSE_ERROR:{0}:{1}" -f $path,($errors.Message -join '|'))}
}

$hostWrapper=Get-Content -LiteralPath $hostWrapperPath -Raw -Encoding UTF8
foreach($needle in @(
  'local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1',
  'local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1',
  'HOST_VERSION_PATCH_TARGET_MISSING',
  'HOST_NOTEBOOK_ALLOWLIST_PATCH_TARGET_MISSING',
  'HOST_TIMEOUT_STREAM_PATCH_TARGET_MISSING'
)){
  if(-not $hostWrapper.Contains($needle)){throw "HOST_125_REGRESSION_MISSING:$needle"}
}

# Simulate the critical Host 1.2.5 transformation without starting the TCP listener.
$hostSource=Get-Content -LiteralPath $hostSourcePath -Raw -Encoding UTF8
$oldVersion="`$HostVersion='1.2.0'"
$newVersion="`$HostVersion='1.2.5'"
$oldAllow="scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1')"
$newAllow="scripts=@('local-agent/governor/RunChromeGovernorReadback.ps1','local-agent/diagnostics/Test-NotebookLMClaimStartBridge.ps1','local-agent/governor/InspectRecentNotebookLMDownloads.ps1','local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1','local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1')"
if(-not $hostSource.Contains($oldVersion)){throw 'HOST_SOURCE_VERSION_ANCHOR_MISSING'}
if(-not $hostSource.Contains($oldAllow)){throw 'HOST_SOURCE_ALLOWLIST_ANCHOR_MISSING'}
$simulated=$hostSource.Replace($oldVersion,$newVersion).Replace($oldAllow,$newAllow)
if(-not $simulated.Contains("`$HostVersion='1.2.5'")){throw 'HOST_125_VERSION_TRANSFORM_FAILED'}
if(-not $simulated.Contains('MirrorNotebookLMArtifactToDrive.ps1')){throw 'HOST_125_MIRROR_ALLOWLIST_TRANSFORM_FAILED'}
if(-not $simulated.Contains('WatchNotebookLMDownloadsToCaptureBridge.ps1')){throw 'HOST_125_WATCHER_ALLOWLIST_TRANSFORM_FAILED'}

$agent=Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8
foreach($needle in @(
  "`$AgentVersion='1.1.29'",
  "`$HostExpected='e6a79fbb113a79e19650b2864072f6abde5bcffb'",
  "`$BaseAgentExpected='60b072c8bb5fa1d268684c74108aedaeae37545a'",
  'HOST_1.2.5_NOT_HEALTHY',
  'HOST_1.2.5_LOST_AFTER_BASE_AGENT',
  'HOST_FIRST_125_THEN_AGENT128_AUTORESUME_1.1.29'
)){
  if(-not $agent.Contains($needle)){throw "AGENT_129_REGRESSION_MISSING:$needle"}
}

$hostGateIndex=$agent.IndexOf('$hostReady=')
$baseAgentIndex=$agent.IndexOf('RefreshVerified $BaseAgentUrl $BaseAgentFile $BaseAgentExpected')
if($hostGateIndex -lt 0 -or $baseAgentIndex -lt 0 -or $hostGateIndex -ge $baseAgentIndex){throw 'AGENT_129_HOST_GATE_NOT_BEFORE_BASE_AGENT'}

$stable=Get-Content -LiteralPath $stablePath -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$stable.version -ne '1.1.29'){throw "STABLE_AGENT_VERSION_MISMATCH:$($stable.version)"}
$agentBlob=(& git hash-object -- $agentPath).Trim()
if($LASTEXITCODE -ne 0){throw 'GIT_HASH_OBJECT_AGENT_FAILED'}
if($agentBlob -ne [string]$stable.gitBlobSha1){throw "STABLE_AGENT_SHA_MISMATCH actual=$agentBlob expected=$($stable.gitBlobSha1)"}
$hostBlob=(& git hash-object -- $hostWrapperPath).Trim()
if($LASTEXITCODE -ne 0){throw 'GIT_HASH_OBJECT_HOST_FAILED'}
if($hostBlob -ne 'e6a79fbb113a79e19650b2864072f6abde5bcffb'){throw "HOST_125_SHA_MISMATCH actual=$hostBlob"}

Write-Host 'AUTO_RESUME_HOST_FIRST_REGRESSION_PASS'
Write-Host 'Agent 1.1.29: Host 1.2.5 health gate precedes Agent 1.1.28 recovery.'
Write-Host 'Host 1.2.5: exact artifact mirror + watcher are allowlisted.'
