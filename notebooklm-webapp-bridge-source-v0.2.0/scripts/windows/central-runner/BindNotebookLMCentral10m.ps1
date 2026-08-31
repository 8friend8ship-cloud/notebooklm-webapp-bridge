param(
  [string]$TargetTitle = 'WEBAPP_TEMPLATE_03',
  [string]$ExpectedSpreadsheetId = '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk',
  [string]$ExpectedDeploymentId = 'AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P',
  [string]$ExpectedScriptPrefix = '1dmbf19qgN6Q-CwLY',
  [string]$SourceCommit = '54e13999aa9230475650da955b4bfcb53281af9e',
  [string]$ReceiptPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$BindVersion = 'NOTEBOOKLM_CENTRAL_10M_BIND_V1_20260901'
$ReadOnlyReceiptName = 'CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json'
$BindReceiptName = 'CENTRAL_APPS_SCRIPT_10M_BIND_WEBAPP_TEMPLATE_03_RESULT.json'
$SourceUrl = "https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/$SourceCommit/apps-script/DriveAutoClassifySeedWriteback10m.gs"

function Find-CentralRuntimeReadback {
  $target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    $r = [string]$d.Root
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    foreach ($c in @(
      (Join-Path $r $target),
      (Join-Path $r ($myDriveKo + '\\' + $target)),
      (Join-Path $r ('My Drive\\' + $target)),
      (Join-Path $r ('Google Drive\\' + $target))
    )) {
      if (Test-Path -LiteralPath $c -PathType Container) {
        $rd = Join-Path $c 'Runtime_Readback'
        if (Test-Path -LiteralPath $rd -PathType Container) { return $rd }
      }
    }
  }
  return ''
}

function Assert-ReadOnlyReceipt([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'BOUND_READONLY_RECEIPT_NOT_FOUND' }
  $raw = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  if ($raw.ok -ne $true) { throw 'BOUND_READONLY_RECEIPT_OK_FALSE' }
  if ([string]$raw.mode -ne 'READ_ONLY') { throw 'BOUND_READONLY_RECEIPT_MODE_MISMATCH' }
  if ($raw.mutationPerformed -ne $false) { throw 'BOUND_READONLY_RECEIPT_MUTATION_FLAG_INVALID' }
  if ([string]$raw.projectTitle -ne $TargetTitle) { throw 'BOUND_READONLY_RECEIPT_TITLE_MISMATCH' }
  if ([string]$raw.spreadsheetId -ne $ExpectedSpreadsheetId) { throw 'BOUND_READONLY_RECEIPT_SPREADSHEET_MISMATCH' }
  if ([string]$raw.deploymentId -ne $ExpectedDeploymentId) { throw 'BOUND_READONLY_RECEIPT_DEPLOYMENT_MISMATCH' }
  $sid = [string]$raw.scriptId
  if ([string]::IsNullOrWhiteSpace($sid) -or $sid.Length -lt 40) { throw 'BOUND_READONLY_RECEIPT_SCRIPT_ID_INVALID' }
  if (!$sid.StartsWith($ExpectedScriptPrefix, [StringComparison]::Ordinal)) { throw 'BOUND_READONLY_RECEIPT_SCRIPT_PREFIX_MISMATCH' }
  return $raw
}

function Get-ScriptFiles([string]$Root) {
  return @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in @('.gs','.js') })
}

$runtimeReadback = Find-CentralRuntimeReadback
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
  if ([string]::IsNullOrWhiteSpace($runtimeReadback)) { throw 'CENTRAL_RUNTIME_READBACK_FOLDER_NOT_FOUND' }
  $ReceiptPath = Join-Path $runtimeReadback $ReadOnlyReceiptName
}
$receipt = Assert-ReadOnlyReceipt $ReceiptPath
$scriptId = [string]$receipt.scriptId

$clasp = Get-Command clasp.cmd -ErrorAction SilentlyContinue
if (!$clasp) { $clasp = Get-Command clasp -ErrorAction SilentlyContinue }
if (!$clasp) { throw 'EXISTING_CLASP_REQUIRED_NO_INSTALL' }
& $clasp.Source show-authorized-user --json *> $null
if ($LASTEXITCODE -ne 0) {
  & $clasp.Source show-authorized-user *> $null
  if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_REQUIRED_NO_LOGIN' }
}

$listText = (& $clasp.Source list-scripts 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_SCRIPTS_FAILED' }
$titleLines = @(($listText -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($TargetTitle) })
if ($titleLines.Count -ne 1) { throw "SCRIPT_TITLE_RESOLUTION_COUNT:$($titleLines.Count)" }
if ($titleLines[0] -notmatch [regex]::Escape($scriptId)) { throw 'RECEIPT_SCRIPT_ID_NOT_EQUAL_LIST_SCRIPTS' }

$deploymentBefore = (& $clasp.Source list-deployments $scriptId 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_DEPLOYMENTS_BEFORE_FAILED' }
if ($deploymentBefore -notmatch [regex]::Escape($ExpectedDeploymentId)) { throw 'EXPECTED_DEPLOYMENT_NOT_FOUND_BEFORE' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $env:TEMP "notebooklm-central-10m-bind-$stamp"
$liveDir = Join-Path $workRoot 'live-before'
$verifyDir = Join-Path $workRoot 'verify-after'
$downloadDir = Join-Path $workRoot 'source'
New-Item -ItemType Directory -Force -Path $workRoot,$liveDir,$verifyDir,$downloadDir | Out-Null

Push-Location $liveDir
try {
  & $clasp.Source clone-script $scriptId *> $null
  if ($LASTEXITCODE -ne 0) {
    & $clasp.Source clone $scriptId *> $null
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED' }
  }
} finally { Pop-Location }

$configPath = Join-Path $liveDir '.clasp.json'
$rootDir = $liveDir
$primaryExt = '.gs'
if (Test-Path -LiteralPath $configPath) {
  $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  if ($cfg.rootDir) { $rootDir = [IO.Path]::GetFullPath((Join-Path $liveDir ([string]$cfg.rootDir))) }
  if ($cfg.scriptExtensions -and @($cfg.scriptExtensions).Count -gt 0) {
    $e = [string]@($cfg.scriptExtensions)[0]
    if (!$e.StartsWith('.')) { $e = '.' + $e }
    if ($e -in @('.gs','.js')) { $primaryExt = $e }
  }
}
if (!(Test-Path -LiteralPath $rootDir -PathType Container)) { throw 'CLASP_ROOT_DIR_MISSING' }

$beforeFiles = Get-ScriptFiles $rootDir
$queueHits = @()
foreach ($f in $beforeFiles) {
  $t = Get-Content -Raw -LiteralPath $f.FullName
  if ($t -match 'function\s+processTaskQueue\s*\(\s*\)\s*\{') { $queueHits += $f }
}
if ($queueHits.Count -ne 1) { throw "PROCESS_TASK_QUEUE_DEFINITION_COUNT:$($queueHits.Count)" }
$queueFile = $queueHits[0].FullName
$queueBeforeText = Get-Content -Raw -LiteralPath $queueFile

$sourcePath = Join-Path $downloadDir 'DriveAutoClassifySeedWriteback10m.gs'
Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl -OutFile $sourcePath -TimeoutSec 30
if (!(Test-Path -LiteralPath $sourcePath) -or (Get-Item -LiteralPath $sourcePath).Length -lt 5000) { throw 'PINNED_10M_SOURCE_DOWNLOAD_FAILED' }
$sourceText = Get-Content -Raw -LiteralPath $sourcePath
if ($sourceText -notmatch 'DRIVE_AUTO_CLASSIFY_SEED_WRITEBACK_V1_20260831') { throw 'PINNED_10M_SOURCE_VERSION_MISMATCH' }
if ($sourceText -notmatch 'function\s+runDriveAutoClassifySeedWriteback10m\s*\(') { throw 'PINNED_10M_HANDLER_MISSING' }
if ($sourceText -notmatch 'function\s+runDriveAutoClassifySeedWriteback10mFromFactoryV1\s*\(') { throw 'PINNED_10M_FACTORY_HANDLER_MISSING' }
if ($sourceText -match 'ScriptApp\.newTrigger\s*\(') { throw 'PINNED_10M_SOURCE_FORBIDDEN_NEW_TRIGGER' }

$targetModule = Join-Path $rootDir ('DriveAutoClassifySeedWriteback10m' + $primaryExt)
Copy-Item -Force -LiteralPath $sourcePath -Destination $targetModule

$hookNeedle = 'runDriveAutoClassifySeedWriteback10mFromFactoryV1'
$queueText = Get-Content -Raw -LiteralPath $queueFile
$hookCountBefore = ([regex]::Matches($queueText, [regex]::Escape($hookNeedle) + '\s*\(')).Count
if ($hookCountBefore -eq 0) {
  $pattern = '(function\s+processTaskQueue\s*\(\s*\)\s*\{)'
  $insert = '${1}' + "`r`n  // Central 10m Drive classify adapter: logical gate only, never blocks queue.`r`n  try { if (typeof $hookNeedle === 'function') $hookNeedle(); } catch (drive10mErr) { console.error('DRIVE_AUTO_CLASSIFY_10M_ERROR', drive10mErr); }"
  $queueText = [regex]::Replace($queueText, $pattern, $insert, 1)
  Set-Content -LiteralPath $queueFile -Value $queueText -Encoding UTF8
} elseif ($hookCountBefore -gt 1) {
  throw "FACTORY_HOOK_PREEXISTING_DUPLICATE_COUNT:$hookCountBefore"
}

$allAfterLocal = (Get-ScriptFiles $rootDir | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if (([regex]::Matches($allAfterLocal, 'function\s+runDriveAutoClassifySeedWriteback10m\s*\(')).Count -ne 1) { throw 'LOCAL_HANDLER_DEFINITION_COUNT_NOT_ONE' }
$queueAfterText = Get-Content -Raw -LiteralPath $queueFile
if (([regex]::Matches($queueAfterText, [regex]::Escape($hookNeedle) + '\s*\(')).Count -ne 1) { throw 'LOCAL_FACTORY_HOOK_COUNT_NOT_ONE' }
if ($queueAfterText -match 'ScriptApp\.newTrigger\s*\(') { throw 'LOCAL_QUEUE_FORBIDDEN_NEW_TRIGGER' }

$beforeManifest = @($beforeFiles | ForEach-Object {
  [ordered]@{path=$_.FullName.Substring($rootDir.Length).TrimStart('\\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
})
$sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()

Push-Location $liveDir
try {
  & $clasp.Source show-file-status *> $null
  if ($LASTEXITCODE -ne 0) { throw 'CLASP_SHOW_FILE_STATUS_FAILED' }
  & $clasp.Source push --force
  if ($LASTEXITCODE -ne 0) { throw 'CLASP_PUSH_FAILED' }
} finally { Pop-Location }

Push-Location $verifyDir
try {
  & $clasp.Source clone-script $scriptId *> $null
  if ($LASTEXITCODE -ne 0) {
    & $clasp.Source clone $scriptId *> $null
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_VERIFY_CLONE_FAILED' }
  }
} finally { Pop-Location }

$verifyConfig = Join-Path $verifyDir '.clasp.json'
$verifyRoot = $verifyDir
if (Test-Path -LiteralPath $verifyConfig) {
  $vcfg = Get-Content -Raw -LiteralPath $verifyConfig | ConvertFrom-Json
  if ($vcfg.rootDir) { $verifyRoot = [IO.Path]::GetFullPath((Join-Path $verifyDir ([string]$vcfg.rootDir))) }
}
$verifyFiles = Get-ScriptFiles $verifyRoot
$verifyAll = ($verifyFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if (([regex]::Matches($verifyAll, 'function\s+runDriveAutoClassifySeedWriteback10m\s*\(')).Count -ne 1) { throw 'READBACK_HANDLER_DEFINITION_COUNT_NOT_ONE' }
if (([regex]::Matches($verifyAll, [regex]::Escape($hookNeedle) + '\s*\(')).Count -ne 1) { throw 'READBACK_FACTORY_HOOK_COUNT_NOT_ONE' }
if ($verifyAll -match 'ScriptApp\.newTrigger\s*\(') { throw 'READBACK_FORBIDDEN_NEW_TRIGGER' }

$deploymentAfter = (& $clasp.Source list-deployments $scriptId 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_DEPLOYMENTS_AFTER_FAILED' }
if ($deploymentAfter -notmatch [regex]::Escape($ExpectedDeploymentId)) { throw 'EXPECTED_DEPLOYMENT_NOT_FOUND_AFTER' }

$verifyModule = @($verifyFiles | Where-Object { $_.BaseName -eq 'DriveAutoClassifySeedWriteback10m' })
if ($verifyModule.Count -ne 1) { throw "READBACK_10M_MODULE_COUNT:$($verifyModule.Count)" }
$verifyModuleSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $verifyModule[0].FullName).Hash.ToLowerInvariant()
if ($verifyModuleSha256 -ne $sourceSha256) { throw 'READBACK_10M_MODULE_HASH_MISMATCH' }

$result = [ordered]@{
  ok = $true
  action = 'NOTEBOOKLM_CENTRAL_10M_BIND'
  version = $BindVersion
  targetTitle = $TargetTitle
  spreadsheetId = $ExpectedSpreadsheetId
  scriptId = $scriptId
  scriptPrefixVerified = $true
  deploymentId = $ExpectedDeploymentId
  deploymentInvariant = $true
  sourceCommit = $SourceCommit
  sourceSha256 = $sourceSha256
  readOnlyGateReceipt = $ReceiptPath
  readOnlyGateMode = [string]$receipt.mode
  readOnlyGateMutationPerformed = $receipt.mutationPerformed
  processTaskQueueDefinitionCount = 1
  factoryHookCount = 1
  handlerDefinitionCount = 1
  sourceReadback = $true
  moduleHashReadback = $true
  newProjectCreated = $false
  oauthChanged = $false
  scopeChanged = $false
  newDeployment = $false
  newTrigger = $false
  mutationPerformed = $true
  mutationScope = 'EXISTING_BOUND_SCRIPT_SOURCE_ONLY'
  beforeScriptFileCount = $beforeManifest.Count
  afterScriptFileCount = $verifyFiles.Count
  at = (Get-Date).ToUniversalTime().ToString('o')
  next = 'WAIT_EXISTING_5M_PROCESS_TASK_QUEUE;VERIFY_TWO_DISTINCT_10M_BUCKETS_AND_DRIVE_23_37_80_READBACK'
}
$json = $result | ConvertTo-Json -Depth 8

$localReceiptDir = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
New-Item -ItemType Directory -Force -Path $localReceiptDir | Out-Null
$json | Set-Content -LiteralPath (Join-Path $localReceiptDir $BindReceiptName) -Encoding UTF8
if ($runtimeReadback) { $json | Set-Content -LiteralPath (Join-Path $runtimeReadback $BindReceiptName) -Encoding UTF8 }
$json
exit 0
