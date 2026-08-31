$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lane=Join-Path $root 'local-agent/releases/appscript-0.1.1/HomeDesignLocalAgent.ps1'
$manifest=Join-Path $root 'local-agent/stable/appscript.json'
$bootstrap=Join-Path $root 'local-agent/bootstrap/AgentBootstrap.ps1'
foreach($p in @($lane,$manifest,$bootstrap)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}

$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($lane,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ('LANE_PARSE_FAIL:'+($errors.Message -join '|'))}
$l=Get-Content -Raw -LiteralPath $lane
$m=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
$b=Get-Content -Raw -LiteralPath $bootstrap

if([string]$m.channel -ne 'appscript-readonly-bind'){throw 'MANIFEST_CHANNEL_MISMATCH'}
if([string]$m.version -ne 'appscript-0.1.1'){throw 'MANIFEST_VERSION_MISMATCH'}
if([string]$m.gitBlobSha1 -ne '939999e458d2abaa5f7ae4cb26125e33a4a45df2'){throw 'MANIFEST_LANE_BLOB_MISMATCH'}
if([int]$m.maxCycleSeconds -ne 900){throw 'MANIFEST_TIMEOUT_MISMATCH'}
if([string]$m.resultReceipt -ne 'AGENT_APPSCRIPT_BIND_V2_RESULT.json'){throw 'MANIFEST_RECEIPT_MISMATCH'}
if(-not$m.enabled){throw 'MANIFEST_DISABLED'}

$must=@(
  "`$Version='appscript-0.1.1'",
  "`$ReadOnlyRef='c8ee143d6db5ab89c3f7795e00b33691471b0c8e'",
  "`$ReadOnlyBlob='d8ed2414c89f04121c3b141e16ae9699ceb11fdf'",
  "`$BinderRef='598693dbbc16390b7fce57785b843bb0b71be2d3'",
  "`$BinderBlob='47e81c44c976c53acb182a50a7aa23737430d81b'",
  "`$ExpectedSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'",
  "`$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'",
  "`$ExpectedScriptPrefix='1dmbf19qgN6Q-CwLY'",
  "`$ExpectedSourceCommit='54e13999aa9230475650da955b4bfcb53281af9e'",
  "CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json",
  "CENTRAL_APPS_SCRIPT_10M_BIND_WEBAPP_TEMPLATE_03_RESULT.json",
  "AGENT_APPSCRIPT_BIND_V2_RESULT.json",
  "ALREADY_BOUND_VERIFIED",
  "RUN_READONLY_STAGE",
  "READONLY_RECEIPT_INVALID_AFTER_STAGE",
  "RUN_GATED_10M_BIND",
  "BINDER_FORBIDDEN_PATTERN",
  "BIND_RECEIPT_INVALID_AFTER_BIND",
  "DONE_BIND_RECEIPT_VERIFIED",
  "EXISTING_BOUND_SCRIPT_SOURCE_ONLY",
  "moduleHashReadback",
  "deploymentInvariant"
)
foreach($needle in $must){if(-not$l.Contains($needle)){throw ('LANE_CONTRACT_MISSING:'+ $needle)}}

$skip=$l.IndexOf('if(ValidBind $existingBind)')
$readOnly=$l.IndexOf("`$r.stage='RUN_READONLY_STAGE'")
$readOnlyVerify=$l.IndexOf("if(-not(ValidReadOnly `$ro)){throw 'READONLY_RECEIPT_INVALID_AFTER_STAGE'}")
$bind=$l.IndexOf("`$r.stage='RUN_GATED_10M_BIND'")
$bindVerify=$l.IndexOf("if(-not(ValidBind `$bind)){throw 'BIND_RECEIPT_INVALID_AFTER_BIND'}")
if($skip -lt 0 -or $readOnly -le $skip -or $readOnlyVerify -le $readOnly -or $bind -le $readOnlyVerify -or $bindVerify -le $bind){throw 'TWO_STAGE_GATE_ORDER_INVALID'}

$forbiddenPatterns=@(
  '&\s+\$clasp\.Source\s+login\b',
  '&\s+\$clasp\.Source\s+create-script\b',
  '&\s+\$clasp\.Source\s+create-deployment\b',
  '&\s+\$clasp\.Source\s+(?:deploy|redeploy)\b',
  'ScriptApp\.newTrigger\s*\(',
  'Register-ScheduledTask',
  'New-ScheduledTaskTrigger',
  'Stop-Process\s+-Name\s+chrome',
  'taskkill\.exe\s+/IM\s+chrome\.exe'
)
foreach($pattern in $forbiddenPatterns){if($l -match $pattern){throw ('LANE_FORBIDDEN_PATTERN:'+ $pattern)}}

if(([regex]::Matches($l,'FetchPinned\s+\$ReadOnlyRef\s+\$ReadOnlyPath\s+\$ReadOnlyBlob')).Count -ne 1){throw 'READONLY_PIN_CALL_COUNT_NOT_ONE'}
if(([regex]::Matches($l,'FetchPinned\s+\$BinderRef\s+\$BinderPath\s+\$BinderBlob')).Count -ne 1){throw 'BINDER_PIN_CALL_COUNT_NOT_ONE'}
if($l -notmatch "newTrigger\s+-eq\s+\`$false"){throw 'VALID_BIND_NEW_TRIGGER_FALSE_GATE_MISSING'}
if($l -notmatch "newDeployment\s+-eq\s+\`$false"){throw 'VALID_BIND_NEW_DEPLOYMENT_FALSE_GATE_MISSING'}
if($l -notmatch "oauthChanged\s+-eq\s+\`$false"){throw 'VALID_BIND_OAUTH_FALSE_GATE_MISSING'}
if($l -notmatch "scopeChanged\s+-eq\s+\`$false"){throw 'VALID_BIND_SCOPE_FALSE_GATE_MISSING'}
if($l -notmatch "sourceReadback\s+-eq\s+\`$true"){throw 'VALID_BIND_SOURCE_READBACK_GATE_MISSING'}
if($l -notmatch "moduleHashReadback\s+-eq\s+\`$true"){throw 'VALID_BIND_MODULE_HASH_GATE_MISSING'}

if($b -notmatch "ApplyIndependentLane 'local-agent/stable/appscript\.json' 'APPSCRIPT'"){throw 'BOOTSTRAP_APPSCRIPT_LANE_CALL_MISSING'}

Write-Host 'CENTRAL_APPSCRIPT_READONLY_TO_10M_BIND_LANE_STATIC_PASS'
