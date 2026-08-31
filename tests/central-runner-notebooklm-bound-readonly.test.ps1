$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runnerRoot=Join-Path $root 'notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner'
$recover=Join-Path $runnerRoot 'RecoverExistingBoundAppsScript.ps1'
$tasks=Join-Path $runnerRoot 'tasks.json'
$runner=Join-Path $runnerRoot 'CentralAppsScriptRunnerV2.ps1'
$installer=Join-Path $runnerRoot 'Install-CentralAppsScriptRunner.ps1'
$cmd=Join-Path $runnerRoot 'INSTALL_CENTRAL_RUNNER.cmd'
foreach($p in @($recover,$tasks,$runner,$installer,$cmd)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}

foreach($p in @($recover,$runner,$installer)){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ((Split-Path $p -Leaf)+':PARSE_FAIL:'+($errors.Message -join '|'))}
}

$r=Get-Content -LiteralPath $recover -Raw -Encoding UTF8
foreach($needle in @(
  "'WEBAPP_TEMPLATE_03'",
  "spreadsheet='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'",
  "deployment='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'",
  "mode='READ_ONLY'",
  'mutationPerformed=$false',
  'clone-script',
  'list-deployments',
  'CENTRAL_APPS_SCRIPT_BOUND_READONLY_',
  'Runtime_Readback'
)){if(-not$r.Contains($needle)){throw ('RECOVER_CONTRACT_MISSING:'+ $needle)}}
foreach($forbidden in @('create-script','create-deployment','delete-deployment','ScriptApp.newTrigger','clasp login')){if($r.Contains($forbidden)){throw ('RECOVER_FORBIDDEN:'+ $forbidden)}}
if($r -match '&\s*\$claspCmd\.Source\s+push\b'){throw 'RECOVER_FORBIDDEN_CLASP_PUSH'}
if($r -match '&\s*\$claspCmd\.Source\s+deploy\b'){throw 'RECOVER_FORBIDDEN_CLASP_DEPLOY'}

$j=Get-Content -LiteralPath $tasks -Raw -Encoding UTF8 | ConvertFrom-Json
if($j.channel -ne 'CENTRAL_APPS_SCRIPT_RUNNER_V2'){throw ('TASK_CHANNEL_INVALID:'+ $j.channel)}
if($j.mode -ne 'READ_ONLY_BOOTSTRAP'){throw ('TASK_MODE_INVALID:'+ $j.mode)}
if($j.releaseRef -ne 'central-runner-readonly-bootstrap-v7'){throw ('TASK_RELEASE_REF_INVALID:'+ $j.releaseRef)}
if($j.version -ne '20260831.8-immutable-readonly-release'){throw ('TASK_MANIFEST_VERSION_INVALID:'+ $j.version)}
$t=@($j.tasks | Where-Object {$_.taskId -eq 'TASK_20260831_NOTEBOOKLM_BOUND_READONLY_RECOVERY_001'})
if($t.Count -ne 1){throw ('TASK_COUNT_INVALID:'+ $t.Count)}
$t=$t[0]
if(-not$t.enabled){throw 'TASK_NOT_ENABLED'}
if($t.action -ne 'BOUND_APPS_SCRIPT_READONLY_RECOVERY'){throw 'TASK_ACTION_INVALID'}
if($t.targetTitle -ne 'WEBAPP_TEMPLATE_03'){throw 'TASK_TITLE_INVALID'}
if($t.expectedSpreadsheetId -ne '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'){throw 'TASK_SPREADSHEET_INVALID'}
if($t.expectedDeploymentId -ne 'AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'){throw 'TASK_DEPLOYMENT_INVALID'}
if([int]$t.maxAttempts -ne 1){throw 'TASK_MAX_ATTEMPTS_INVALID'}
$enabled=@($j.tasks | Where-Object {$_.enabled})
if($enabled.Count -ne 1){throw ('BOOTSTRAP_ENABLED_TASK_COUNT_INVALID:'+ $enabled.Count)}
if($enabled[0].taskId -ne 'TASK_20260831_NOTEBOOKLM_BOUND_READONLY_RECOVERY_001'){throw ('UNEXPECTED_BOOTSTRAP_TASK_ENABLED:'+ $enabled[0].taskId)}

$release='central-runner-readonly-bootstrap-v7'
$rt=Get-Content -LiteralPath $runner -Raw -Encoding UTF8
foreach($needle in @(
  'CENTRAL_APPS_SCRIPT_RUNNER_V2_READONLY_BOOTSTRAP_V7_20260831',
  $release,
  "'BOUND_APPS_SCRIPT_READONLY_RECOVERY'",
  "mode -ne 'READ_ONLY'",
  'mutationPerformed -ne $false',
  'MUTATION_ACTION_DISABLED_IN_READONLY_BOOTSTRAP_RELEASE',
  'UNRELATED_BROWSER_ACTION_DISABLED_IN_READONLY_BOOTSTRAP_RELEASE',
  'ENABLED_NON_READONLY_TASK_BLOCKED'
)){if(-not$rt.Contains($needle)){throw ('RUNNER_GATE_MISSING:'+ $needle)}}
if($rt.Contains('fix/central-appscript-runner-20260821')){throw 'RUNNER_BRANCH_DRIFT_URL_PRESENT'}

$it=Get-Content -LiteralPath $installer -Raw -Encoding UTF8
foreach($needle in @($release,'CENTRAL_APPS_SCRIPT_RUNNER_V2_READONLY_BOOTSTRAP_V7_20260831','RUNNER_MUTATION_GATE_MISSING','RUNNER_RELEASE_REF_MISMATCH')){if(-not$it.Contains($needle)){throw ('INSTALLER_PIN_MISSING:'+ $needle)}}
if($it.Contains('fix/central-appscript-runner-20260821')){throw 'INSTALLER_BRANCH_DRIFT_URL_PRESENT'}

$ct=Get-Content -LiteralPath $cmd -Raw -Encoding UTF8
if(-not$ct.Contains($release)){throw 'CMD_RELEASE_REF_MISSING'}
if($ct.Contains('fix/central-appscript-runner-20260821')){throw 'CMD_BRANCH_DRIFT_URL_PRESENT'}

Write-Host 'CENTRAL_RUNNER_NOTEBOOKLM_BOUND_READONLY_STATIC_PASS'
