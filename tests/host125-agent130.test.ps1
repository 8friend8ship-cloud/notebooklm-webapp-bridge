$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agent30Path=Join-Path $root 'local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$host125Path=Join-Path $root 'local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1'
$agent31Path=Join-Path $root 'local-agent/releases/1.1.31/HomeDesignLocalAgent.ps1'
$host126Path=Join-Path $root 'local-agent/releases/1.2.6/HomeDesignLocalCommandHost.ps1'
$stablePath=Join-Path $root 'local-agent/stable/agent.json'

foreach($path in @($agent30Path,$host125Path,$agent31Path,$host126Path,$stablePath)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "MISSING:$path"}
}
foreach($path in @($agent30Path,$host125Path,$agent31Path,$host126Path)){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ("PARSE_FAIL:{0}:{1}" -f $path,($errors.Message -join '|'))}
}

$agent30=Get-Content -LiteralPath $agent30Path -Raw -Encoding UTF8
$host125=Get-Content -LiteralPath $host125Path -Raw -Encoding UTF8
$agent31=Get-Content -LiteralPath $agent31Path -Raw -Encoding UTF8
$host126=Get-Content -LiteralPath $host126Path -Raw -Encoding UTF8
$stable=Get-Content -LiteralPath $stablePath -Raw -Encoding UTF8|ConvertFrom-Json

# Preserve the known-good Host 1.2.5 / Agent 1.1.30 recovery contract as historical regression evidence.
foreach($needle in @('MirrorNotebookLMArtifactToDrive.ps1','WatchNotebookLMDownloadsToCaptureBridge.ps1','1.2.5')){
  if(-not $host125.Contains($needle)){throw "HOST125_MISSING:$needle"}
}
foreach($needle in @("`$AgentVersion='1.1.30'","`$HostVersion='1.2.5'",'EnsureHost125','AGENT_1.1.30_HOST125_FIRST_AUTORESUME','HOST125_FIRST_AUTORESUME_1.1.30')){
  if(-not $agent30.Contains($needle)){throw "AGENT130_MISSING:$needle"}
}
if($agent30.Contains("local-agent/releases/1.2.4/HomeDesignLocalCommandHost.ps1")){throw 'AGENT130_STILL_POINTS_HOST124'}
$hostRecoveryIndex=$agent30.IndexOf('$result.hostRecovery=EnsureHost125')
$autoResumeIndex=$agent30.IndexOf('$result.autoResume=EnsureAutoResume')
if($hostRecoveryIndex -lt 0 -or $autoResumeIndex -lt 0 -or $hostRecoveryIndex -ge $autoResumeIndex){throw 'AGENT130_NOT_HOST_FIRST'}
$host125Sha=(& git hash-object -- $host125Path).Trim()
if($LASTEXITCODE -ne 0){throw 'HOST125_HASH_FAILED'}
if($host125Sha -ne 'e6a79fbb113a79e19650b2864072f6abde5bcffb'){throw "HOST125_SHA_MISMATCH:$host125Sha"}

# Current stable must use the managed CaptureBridge-capable Agent 1.1.31 / Host 1.2.6 lineage.
foreach($needle in @('1.1.31','1.2.6','5d17bb233706897cd1706930cea9af3796f29488')){
  if(-not $agent31.Contains($needle)){throw "AGENT131_MISSING:$needle"}
}
foreach($needle in @('1.2.6','local-agent/capture/ManageChromeExtensionArtifacts.ps1','local-agent/capture/Setup-ChromeExtensionCaptureBridge.ps1')){
  if(-not $host126.Contains($needle)){throw "HOST126_MISSING:$needle"}
}
if([string]$stable.version -ne '1.1.31'){throw "BAD_STABLE_VERSION:$($stable.version)"}
$agent31Sha=(& git hash-object -- $agent31Path).Trim()
if($LASTEXITCODE -ne 0){throw 'AGENT131_HASH_FAILED'}
if($agent31Sha -ne [string]$stable.gitBlobSha1){throw ("AGENT_STABLE_SHA_MISMATCH:{0}:{1}" -f $agent31Sha,[string]$stable.gitBlobSha1)}
$host126Sha=(& git hash-object -- $host126Path).Trim()
if($LASTEXITCODE -ne 0){throw 'HOST126_HASH_FAILED'}
if($host126Sha -ne '5d17bb233706897cd1706930cea9af3796f29488'){throw "HOST126_SHA_MISMATCH:$host126Sha"}
Write-Host 'HOST125_AGENT130_HISTORY_AND_AGENT131_HOST126_STABLE_PASS'
