$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runnerRoot=Join-Path $root 'notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner'
$recover=Join-Path $runnerRoot 'RecoverExistingBoundAppsScript.ps1'
$tasks=Join-Path $runnerRoot 'tasks.json'
$runner=Join-Path $runnerRoot 'CentralAppsScriptRunnerV2.ps1'
foreach($p in @($recover,$tasks,$runner)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}

$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($recover,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ('RECOVER_PARSE_FAIL:'+($errors.Message -join '|'))}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ('RUNNER_PARSE_FAIL:'+($errors.Message -join '|'))}

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
if($j.version -ne '20260831.7-readonly-startup-gate'){throw ('TASK_MANIFEST_VERSION_INVALID:'+ $j.version)}
$t=@($j.tasks | Where-Object {$_.taskId -eq 'TASK_20260831_NOTEBOOKLM_BOUND_READONLY_RECOVERY_001'})
if($t.Count -ne 1){throw ('TASK_COUNT_INVALID:'+ $t.Count)}
$t=$t[0]
if(-not$t.enabled){throw 'TASK_NOT_ENABLED'}
if($t.action -ne 'BOUND_APPS_SCRIPT_READONLY_RECOVERY'){throw 'TASK_ACTION_INVALID'}
if($t.targetTitle -ne 'WEBAPP_TEMPLATE_03'){throw 'TASK_TITLE_INVALID'}
if($t.expectedSpreadsheetId -ne '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'){throw 'TASK_SPREADSHEET_INVALID'}
if($t.expectedDeploymentId -ne 'AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'){throw 'TASK_DEPLOYMENT_INVALID'}
if([int]$t.maxAttempts -ne 1){throw 'TASK_MAX_ATTEMPTS_INVALID'}

$refresh=@($j.tasks | Where-Object {$_.taskId -eq 'TASK_20260831_CENTRAL_RUNNER_REFRESH_X5_READONLY_002'})
if($refresh.Count -ne 1 -or -not$refresh[0].enabled){throw 'READONLY_REFRESH_NOT_ENABLED'}
if($refresh[0].targetTitle -ne 'CENTRAL_RUNNER_REFRESH_X5_READONLY'){throw 'READONLY_REFRESH_TARGET_INVALID'}

$mutationCapable=@($j.tasks | Where-Object {
  $_.enabled -and (
    $_.taskId -eq 'TASK_20260822_CONTENTOS_BOUND_SYNC_001' -or
    $_.taskId -eq 'TASK_20260829_CHROME_FLOW_HEALTH_RECOVERY_002' -or
    $_.action -eq 'TRAVEL_APPS_SCRIPT_REPAIR'
  )
})
if($mutationCapable.Count -ne 0){throw ('BOOTSTRAP_MUTATION_TASK_ENABLED:'+ (($mutationCapable|ForEach-Object{$_.taskId}) -join '|'))}
$enabled=@($j.tasks | Where-Object {$_.enabled})
$enabledIds=@($enabled | ForEach-Object {[string]$_.taskId})
$allowedEnabled=@('TASK_20260831_CENTRAL_RUNNER_REFRESH_X5_READONLY_002','TASK_20260831_NOTEBOOKLM_BOUND_READONLY_RECOVERY_001')
foreach($id in $enabledIds){if($allowedEnabled -notcontains $id){throw ('UNEXPECTED_BOOTSTRAP_TASK_ENABLED:'+ $id)}}
if($enabledIds.Count -ne 2){throw ('BOOTSTRAP_ENABLED_TASK_COUNT_INVALID:'+ $enabledIds.Count)}

$rt=Get-Content -LiteralPath $runner -Raw -Encoding UTF8
if(-not$rt.Contains("'BOUND_APPS_SCRIPT_READONLY_RECOVERY'")){throw 'RUNNER_ACTION_MISSING'}
if(-not$rt.Contains("mode -ne 'READ_ONLY'")){throw 'RUNNER_READONLY_RECEIPT_GUARD_MISSING'}
if(-not$rt.Contains('mutationPerformed -ne $false')){throw 'RUNNER_MUTATION_GUARD_MISSING'}
Write-Host 'CENTRAL_RUNNER_NOTEBOOKLM_BOUND_READONLY_STATIC_PASS'
