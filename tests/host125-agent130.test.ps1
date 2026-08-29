$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agent30Path=Join-Path $root 'local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1'
$host125Path=Join-Path $root 'local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1'
$agent31Path=Join-Path $root 'local-agent/releases/1.1.31/HomeDesignLocalAgent.ps1'
$agent32Path=Join-Path $root 'local-agent/releases/1.1.32/HomeDesignLocalAgent.ps1'
$agent33Path=Join-Path $root 'local-agent/releases/1.1.33/HomeDesignLocalAgent.ps1'
$agent34Path=Join-Path $root 'local-agent/releases/1.1.34/HomeDesignLocalAgent.ps1'
$agent35Path=Join-Path $root 'local-agent/releases/1.1.35/HomeDesignLocalAgent.ps1'
$host126Path=Join-Path $root 'local-agent/releases/1.2.6/HomeDesignLocalCommandHost.ps1'
$host127Path=Join-Path $root 'local-agent/releases/1.2.7/HomeDesignLocalCommandHost.ps1'
$stablePath=Join-Path $root 'local-agent/stable/agent.json'

foreach($path in @($agent30Path,$host125Path,$agent31Path,$agent32Path,$agent33Path,$agent34Path,$agent35Path,$host126Path,$host127Path,$stablePath)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "MISSING:$path"}
}
foreach($path in @($agent30Path,$host125Path,$agent31Path,$agent32Path,$agent33Path,$agent34Path,$agent35Path,$host126Path,$host127Path)){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ("PARSE_FAIL:{0}:{1}" -f $path,($errors.Message -join '|'))}
}

$agent30=Get-Content -LiteralPath $agent30Path -Raw -Encoding UTF8
$host125=Get-Content -LiteralPath $host125Path -Raw -Encoding UTF8
$agent31=Get-Content -LiteralPath $agent31Path -Raw -Encoding UTF8
$agent32=Get-Content -LiteralPath $agent32Path -Raw -Encoding UTF8
$agent33=Get-Content -LiteralPath $agent33Path -Raw -Encoding UTF8
$agent34=Get-Content -LiteralPath $agent34Path -Raw -Encoding UTF8
$agent35=Get-Content -LiteralPath $agent35Path -Raw -Encoding UTF8
$host126=Get-Content -LiteralPath $host126Path -Raw -Encoding UTF8
$host127=Get-Content -LiteralPath $host127Path -Raw -Encoding UTF8
$stable=Get-Content -LiteralPath $stablePath -Raw -Encoding UTF8|ConvertFrom-Json

foreach($needle in @('MirrorNotebookLMArtifactToDrive.ps1','WatchNotebookLMDownloadsToCaptureBridge.ps1','1.2.5')){if(-not $host125.Contains($needle)){throw "HOST125_MISSING:$needle"}}
foreach($needle in @("`$AgentVersion='1.1.30'","`$HostVersion='1.2.5'",'EnsureHost125','AGENT_1.1.30_HOST125_FIRST_AUTORESUME','HOST125_FIRST_AUTORESUME_1.1.30')){if(-not $agent30.Contains($needle)){throw "AGENT130_MISSING:$needle"}}
if($agent30.Contains("local-agent/releases/1.2.4/HomeDesignLocalCommandHost.ps1")){throw 'AGENT130_STILL_POINTS_HOST124'}
$hostRecoveryIndex=$agent30.IndexOf('$result.hostRecovery=EnsureHost125');$autoResumeIndex=$agent30.IndexOf('$result.autoResume=EnsureAutoResume')
if($hostRecoveryIndex -lt 0 -or $autoResumeIndex -lt 0 -or $hostRecoveryIndex -ge $autoResumeIndex){throw 'AGENT130_NOT_HOST_FIRST'}
$host125Sha=(& git hash-object -- $host125Path).Trim();if($LASTEXITCODE -ne 0){throw 'HOST125_HASH_FAILED'}
if($host125Sha -ne 'e6a79fbb113a79e19650b2864072f6abde5bcffb'){throw "HOST125_SHA_MISMATCH:$host125Sha"}

foreach($needle in @('1.1.31','1.2.6','5d17bb233706897cd1706930cea9af3796f29488')){if(-not $agent31.Contains($needle)){throw "AGENT131_MISSING:$needle"}}
foreach($needle in @('1.2.6','local-agent/capture/ManageChromeExtensionArtifacts.ps1','local-agent/capture/Setup-ChromeExtensionCaptureBridge.ps1')){if(-not $host126.Contains($needle)){throw "HOST126_MISSING:$needle"}}
$host126Sha=(& git hash-object -- $host126Path).Trim();if($LASTEXITCODE -ne 0){throw 'HOST126_HASH_FAILED'}
if($host126Sha -ne '5d17bb233706897cd1706930cea9af3796f29488'){throw "HOST126_SHA_MISMATCH:$host126Sha"}

foreach($needle in @('1.1.32','1.2.6','5d17bb233706897cd1706930cea9af3796f29488','AGENT_1.1.32_CONTROL_CENTER_WAKE.attempted','normalChromeUntouched=$true','newOAuth=$false','newScope=$false')){if(-not $agent32.Contains($needle)){throw "AGENT132_MISSING:$needle"}}
if($agent32 -match 'Stop-Process.+chrome' -or $agent32 -match 'taskkill.+chrome'){throw 'AGENT132_CHROME_KILL_FORBIDDEN'}

foreach($needle in @('1.1.33','1.2.6','5d17bb233706897cd1706930cea9af3796f29488','AGENT_1.1.32_CONTROL_CENTER_WAKE.attempted','prior132MarkerPresent','prior132LocalEvidencePresent','PRIOR_1.1.32_WAKE_MARKER_PRESENT_NO_REPEAT','AGENT_1.1.33_EXTENSION_WAKE_DIAGNOSTIC.attempted','AGENT_1.1.33_EXTENSION_WAKE_DIAGNOSTIC.json','normalChromeUntouched=$true','tokenContentsRead=$false','newOAuth=$false','newScope=$false')){if(-not $agent33.Contains($needle)){throw "AGENT133_MISSING:$needle"}}
if($agent33 -match 'Stop-Process.+chrome' -or $agent33 -match 'taskkill.+chrome'){throw 'AGENT133_CHROME_KILL_FORBIDDEN'}

foreach($needle in @('1.2.7','tools/Switch-ContentOS-VercelGit.ps1','tools/Repair-ContentOS-DriveCacheAppsScript.ps1')){if(-not $host127.Contains($needle)){throw "HOST127_MISSING:$needle"}}
if($host127 -match "contents-os-git'.+scripts=@\([^\)]*\*" ){throw 'HOST127_CONTENTOS_WILDCARD_FORBIDDEN'}
$host127Sha=(& git hash-object -- $host127Path).Trim();if($LASTEXITCODE -ne 0){throw 'HOST127_HASH_FAILED'}
if($host127Sha -ne 'ac4aae953fae2219d393de2307ef655b0988c9f4'){throw "HOST127_SHA_MISMATCH:$host127Sha"}
foreach($needle in @('1.1.34','1.2.7','ac4aae953fae2219d393de2307ef655b0988c9f4','CONTENTOS_REPAIR_ALLOWLIST_READY','tools/Repair-ContentOS-DriveCacheAppsScript.ps1','newOAuth=$false','newScope=$false','publicPublish=$false','destructive=$false')){if(-not $agent34.Contains($needle)){throw "AGENT134_MISSING:$needle"}}

# D115 changed-route must use only the official Host async API with one fixed idempotent task.
foreach($needle in @('1.1.35','1.2.7','CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01','http://127.0.0.1:8765','/health','/run','/result?taskId=','taskType=''LOCAL_POWERSHELL''','tools/Repair-ContentOS-DriveCacheAppsScript.ps1','timeoutSeconds=600','idempotent=$true','newOAuth=$false','newScope=$false','newProject=$false','newDeployment=$false','newTrigger=$false','vercelAction=$false','AGENT_1.1.35_CONTENTOS_TASK203_DIRECT.json','AGENT_1.1.35_CONTENTOS_TASK203_SUBMITTED.json')){
  if(-not $agent35.Contains($needle)){throw "AGENT135_MISSING:$needle"}
}
if($agent35 -match 'LOCAL_POWERSHELL_ASYNC'){throw 'AGENT135_QUEUE_TASKTYPE_FORBIDDEN'}
if($agent35 -match 'Stop-Process.+chrome' -or $agent35 -match 'taskkill.+chrome'){throw 'AGENT135_CHROME_KILL_FORBIDDEN'}
if(([regex]::Matches($agent35,'CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01')).Count -ne 1){throw 'AGENT135_FIXED_TASK_ID_NOT_SINGLE_DECLARATION'}

# Current stable may advance beyond historical D115 agents. Preserve historical assertions above,
# then verify the active stable release generically by version path + exact repository blob SHA.
$stableVersion=[string]$stable.version
if($stableVersion -notmatch '^1\.1\.\d+$'){throw "BAD_STABLE_VERSION:$stableVersion"}
$stableAgentPath=Join-Path $root ('local-agent/releases/'+$stableVersion+'/HomeDesignLocalAgent.ps1')
if(-not(Test-Path -LiteralPath $stableAgentPath -PathType Leaf)){throw "STABLE_AGENT_RELEASE_MISSING:$stableVersion"}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($stableAgentPath,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ("STABLE_AGENT_PARSE_FAIL:{0}" -f ($errors.Message -join '|'))}
$stableSha=(& git hash-object -- $stableAgentPath).Trim();if($LASTEXITCODE -ne 0){throw 'STABLE_AGENT_HASH_FAILED'}
if($stableSha -ne [string]$stable.gitBlobSha1){throw ("AGENT_STABLE_SHA_MISMATCH:{0}:{1}" -f $stableSha,[string]$stable.gitBlobSha1)}
$stableText=Get-Content -LiteralPath $stableAgentPath -Raw -Encoding UTF8
if($stableVersion -eq '1.1.54'){
  foreach($needle in @('[string[]]$ArgList','AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P','PUSH_PULL_READBACK_PASS','DEPLOYMENT_INVARIANT_LOST','newProjectCreated=$false','oauthChanged=$false','newDeployment=$false','newTrigger=$false','browserLaunched=$false','queueTaskCreated=$false','creditSpend=$false')){
    if(-not $stableText.Contains($needle)){throw "STABLE_AGENT154_MISSING:$needle"}
  }
}elseif($stableVersion -eq '1.1.35'){
  if($stableSha -ne 'e27b760b67933be05a5d6f1ac0af1afd6158b32b'){throw 'STABLE_AGENT135_SHA_MISMATCH'}
  foreach($needle in @('CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01','taskType=''LOCAL_POWERSHELL''','/run','/result?taskId=')){if(-not $agent35.Contains($needle)){throw "STABLE_AGENT135_MISSING:$needle"}}
}elseif($stableVersion -eq '1.1.34' -and -not $agent34.Contains('ac4aae953fae2219d393de2307ef655b0988c9f4')){throw 'STABLE_AGENT134_HOST127_PIN_MISSING'}
Write-Host ('HOST_RECOVERY_LINEAGE_AND_CURRENT_STABLE_PASS stable='+$stableVersion)
