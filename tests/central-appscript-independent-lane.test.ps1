$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bootstrap=Join-Path $root 'local-agent/bootstrap/AgentBootstrap.ps1'
$manifest=Join-Path $root 'local-agent/stable/appscript.json'
$lane=Join-Path $root 'local-agent/releases/appscript-0.1.0/HomeDesignLocalAgent.ps1'
foreach($p in @($bootstrap,$manifest,$lane)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}

foreach($p in @($bootstrap,$lane)){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ('PARSE_FAIL:'+ $p+':'+($errors.Message -join '|'))}
}

$b=Get-Content -Raw -LiteralPath $bootstrap
$l=Get-Content -Raw -LiteralPath $lane
$m=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
if([string]$m.version -ne 'appscript-0.1.0'){throw 'MANIFEST_VERSION_MISMATCH'}
if([string]$m.channel -ne 'appscript-readonly'){throw 'MANIFEST_CHANNEL_MISMATCH'}
if($m.enabled -ne $true){throw 'MANIFEST_NOT_ENABLED'}
if([string]$m.gitBlobSha1 -ne 'd8ed2414c89f04121c3b141e16ae9699ceb11fdf'){throw 'MANIFEST_BLOB_MISMATCH'}
if([string]$m.resultReceipt -ne 'AGENT_APPSCRIPT_BOOTSTRAP_V1_RESULT.json'){throw 'MANIFEST_RECEIPT_MISMATCH'}

$mustBootstrap=@(
  "`$AppScriptAgentFile = Join-Path `$Root 'HomeDesignLocalAgent-appscript.ps1'",
  "`$AppScriptLaneStateFile = Join-Path `$Root 'state-appscript.json'",
  "ApplyIndependentLane 'local-agent/stable/appscript.json' 'APPSCRIPT' `$AppScriptAgentFile `$AppScriptLaneStateFile",
  "ApplyIndependentLane 'local-agent/stable/flow.json' 'FLOW'",
  "ApplyIndependentLane 'local-agent/stable/image.json' 'IMAGE'"
)
foreach($needle in $mustBootstrap){if(-not$b.Contains($needle)){throw ('BOOTSTRAP_CONTRACT_MISSING:'+ $needle)}}
if(([regex]::Matches($b,"ApplyIndependentLane 'local-agent/stable/appscript\.json' 'APPSCRIPT'")).Count -ne 1){throw 'APPSCRIPT_LANE_CALL_COUNT_NOT_ONE'}

$mustLane=@(
  "`$ReleaseRef='central-runner-readonly-bootstrap-v7'",
  "`$ExpectedInstallerBlob='896c06532a0ec0db0af445ce90a78c197a4a77c9'",
  "`$ExpectedSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'",
  "`$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'",
  "CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json",
  "ALREADY_VERIFIED_READONLY",
  "EXISTING_CLASP_REQUIRED_NO_INSTALL_NO_LOGIN",
  "EXISTING_CLASP_AUTH_REQUIRED_NO_LOGIN",
  "IMMUTABLE_INSTALLER_BLOB_MISMATCH",
  "BOUND_READONLY_RECEIPT_MISSING_OR_INVALID_AFTER_INSTALL",
  "-TaskName 'Central Apps Script Runner'"
)
foreach($needle in $mustLane){if(-not$l.Contains($needle)){throw ('LANE_CONTRACT_MISSING:'+ $needle)}}

$forbidden=@('clasp login','create-script','create-deployment','clasp deploy','ScriptApp.newTrigger','Stop-Process -Name chrome','taskkill.exe /IM chrome.exe')
foreach($needle in $forbidden){if($l -match [regex]::Escape($needle)){throw ('LANE_FORBIDDEN:'+ $needle)}}

$receiptCheck=$l.IndexOf('if(BoundReceiptValid $existingReceipt)')
$installerFetch=$l.IndexOf("`$r.stage='FETCH_IMMUTABLE_INSTALLER'")
$installerRun=$l.IndexOf("`$r.stage='RUN_IMMUTABLE_READONLY_INSTALLER'")
$receiptVerify=$l.IndexOf("`$r.stage='VERIFY_READONLY_RECEIPT'")
if($receiptCheck -lt 0 -or $installerFetch -le $receiptCheck -or $installerRun -le $installerFetch -or $receiptVerify -le $installerRun){throw 'LANE_GATE_ORDER_INVALID'}

Write-Host 'CENTRAL_APPSCRIPT_INDEPENDENT_LANE_STATIC_PASS'
