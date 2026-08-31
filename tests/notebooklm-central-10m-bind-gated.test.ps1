$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bindPath=Join-Path $root 'notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/BindNotebookLMCentral10m.ps1'
$sourcePath=Join-Path $root 'apps-script/DriveAutoClassifySeedWriteback10m.gs'
if(-not(Test-Path -LiteralPath $bindPath -PathType Leaf)){throw 'BIND_SCRIPT_MISSING'}
if(-not(Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw '10M_SOURCE_MISSING'}

$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($bindPath,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ('BIND_PARSE_FAIL:'+($errors.Message -join '|'))}
$b=Get-Content -Raw -LiteralPath $bindPath
$s=Get-Content -Raw -LiteralPath $sourcePath

$must=@(
  "NOTEBOOKLM_CENTRAL_10M_BIND_V1_20260901",
  "CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json",
  "CENTRAL_APPS_SCRIPT_10M_BIND_WEBAPP_TEMPLATE_03_RESULT.json",
  "WEBAPP_TEMPLATE_03",
  "1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk",
  "AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P",
  "1dmbf19qgN6Q-CwLY",
  "54e13999aa9230475650da955b4bfcb53281af9e",
  "Assert-ReadOnlyReceipt",
  "BOUND_READONLY_RECEIPT_MUTATION_FLAG_INVALID",
  "RECEIPT_SCRIPT_ID_NOT_EQUAL_LIST_SCRIPTS",
  "EXPECTED_DEPLOYMENT_NOT_FOUND_BEFORE",
  "processTaskQueue",
  "runDriveAutoClassifySeedWriteback10mFromFactoryV1",
  "PREEXISTING_10M_MODULE_HASH_MISMATCH_ABORT",
  "CLASP_PUSH_FAILED",
  "CLASP_VERIFY_CLONE_FAILED",
  "READBACK_10M_MODULE_HASH_MISMATCH",
  "rollback-before",
  "ROLLBACK_CLASP_PUSH_FAILED",
  "newProjectCreated = `$false",
  "oauthChanged = `$false",
  "scopeChanged = `$false",
  "newDeployment = `$false",
  "newTrigger = `$false",
  "EXISTING_BOUND_SCRIPT_SOURCE_ONLY",
  "VERIFY_TWO_DISTINCT_10M_BUCKETS_AND_DRIVE_23_37_80_READBACK"
)
foreach($needle in $must){if(-not$b.Contains($needle)){throw ('BIND_CONTRACT_MISSING:'+ $needle)}}

$forbidden=@(
  '& $clasp.Source login',
  '& $clasp.Source create-script',
  '& $clasp.Source create-deployment',
  '& $clasp.Source deploy',
  '& $clasp.Source redeploy',
  'Register-ScheduledTask',
  'New-ScheduledTaskTrigger',
  'ScriptApp.newTrigger('
)
foreach($needle in $forbidden){if($b.Contains($needle)){throw ('BIND_FORBIDDEN_OPERATION:'+ $needle)}}

$gate=$b.IndexOf('$receipt = Assert-ReadOnlyReceipt')
$push=$b.IndexOf('& $clasp.Source push --force')
$readback=$b.IndexOf('CLASP_VERIFY_CLONE_FAILED')
$deploymentAfter=$b.IndexOf('EXPECTED_DEPLOYMENT_NOT_FOUND_AFTER')
if($gate -lt 0 -or $push -le $gate -or $readback -le $push -or $deploymentAfter -le $readback){throw 'BIND_GATE_ORDER_INVALID'}

if(([regex]::Matches($b,'&\s+\$clasp\.Source\s+push\s+--force')).Count -ne 2){throw 'BIND_PUSH_COUNT_EXPECT_PRIMARY_PLUS_ROLLBACK'}
if(([regex]::Matches($b,'Assert-ReadOnlyReceipt')).Count -lt 2){throw 'BIND_READONLY_GATE_NOT_DEFINED_AND_CALLED'}
if($b -notmatch "mutationPerformed\s*=\s*\$true"){throw 'BIND_MUTATION_SCOPE_NOT_EXPLICIT'}
if($b -notmatch "rollbackPerformed\s*=\s*\$rollbackPerformed"){throw 'BIND_ROLLBACK_RESULT_MISSING'}

$sourceMust=@(
  "DRIVE_AUTO_CLASSIFY_SEED_WRITEBACK_V1_20260831",
  "function runDriveAutoClassifySeedWriteback10m(",
  "function runDriveAutoClassifySeedWriteback10mFromFactoryV1(",
  "23_FILE_ASSET_INVENTORY",
  "37_QUEENS_RESEARCH_RESULTS",
  "80_DATA_RUNTIME_QA_LOG",
  "NO_AUTO_SEED_PROMOTION"
)
foreach($needle in $sourceMust){if(-not$s.Contains($needle)){throw ('10M_SOURCE_CONTRACT_MISSING:'+ $needle)}}
if($s -match 'ScriptApp\.newTrigger\s*\('){throw '10M_SOURCE_CREATES_PHYSICAL_TRIGGER'}

Write-Host 'NOTEBOOKLM_CENTRAL_10M_BIND_GATED_STATIC_PASS'
