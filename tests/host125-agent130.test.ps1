$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agentPath=Join-Path $root 'local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$hostPath=Join-Path $root 'local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1'
$stablePath=Join-Path $root 'local-agent/stable/agent.json'

foreach($path in @($agentPath,$hostPath,$stablePath)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "MISSING:$path"}
}
foreach($path in @($agentPath,$hostPath)){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ("PARSE_FAIL:{0}:{1}" -f $path,($errors.Message -join '|'))}
}

$agent=Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8
$hostCode=Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8
$stable=Get-Content -LiteralPath $stablePath -Raw -Encoding UTF8|ConvertFrom-Json

foreach($needle in @('MirrorNotebookLMArtifactToDrive.ps1','WatchNotebookLMDownloadsToCaptureBridge.ps1','1.2.5')){
  if(-not $hostCode.Contains($needle)){throw "HOST125_MISSING:$needle"}
}
foreach($needle in @("`$AgentVersion='1.1.30'","`$HostVersion='1.2.5'",'EnsureHost125','AGENT_1.1.30_HOST125_FIRST_AUTORESUME','HOST125_FIRST_AUTORESUME_1.1.30')){
  if(-not $agent.Contains($needle)){throw "AGENT130_MISSING:$needle"}
}
if($agent.Contains("local-agent/releases/1.2.4/HomeDesignLocalCommandHost.ps1")){throw 'AGENT130_STILL_POINTS_HOST124'}
$hostRecoveryIndex=$agent.IndexOf('$result.hostRecovery=EnsureHost125')
$autoResumeIndex=$agent.IndexOf('$result.autoResume=EnsureAutoResume')
if($hostRecoveryIndex -lt 0 -or $autoResumeIndex -lt 0 -or $hostRecoveryIndex -ge $autoResumeIndex){throw 'AGENT130_NOT_HOST_FIRST'}
if([string]$stable.version -ne '1.1.30'){throw "BAD_STABLE_VERSION:$($stable.version)"}
$agentSha=(& git hash-object -- $agentPath).Trim()
if($LASTEXITCODE -ne 0){throw 'AGENT_HASH_FAILED'}
if($agentSha -ne [string]$stable.gitBlobSha1){throw ("AGENT_STABLE_SHA_MISMATCH:{0}:{1}" -f $agentSha,[string]$stable.gitBlobSha1)}
$hostSha=(& git hash-object -- $hostPath).Trim()
if($LASTEXITCODE -ne 0){throw 'HOST_HASH_FAILED'}
if($hostSha -ne 'e6a79fbb113a79e19650b2864072f6abde5bcffb'){throw "HOST125_SHA_MISMATCH:$hostSha"}
Write-Host 'HOST125_AGENT130_REGRESSION_PASS'
