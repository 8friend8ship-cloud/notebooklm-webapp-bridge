param(
  [Parameter(Mandatory=$true)][string]$TargetTitle,
  [Parameter(Mandatory=$true)][string]$ExpectedDeploymentId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RunnerActionVersion = 'CONTENTOS_BOUND_SYNC_V1_20260822'

if ($TargetTitle -ne 'WEBAPP_TEMPLATE_05') { throw 'TARGET_NOT_WHITELISTED' }
if ($ExpectedDeploymentId -ne 'AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo') { throw 'DEPLOYMENT_NOT_WHITELISTED' }

$clasp = Get-Command clasp.cmd -ErrorAction SilentlyContinue
if (!$clasp) { throw 'CLASP_CMD_NOT_FOUND' }
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (!$git) { $git = Get-Command git -ErrorAction SilentlyContinue }
if (!$git) { throw 'GIT_NOT_FOUND' }

& $clasp.Source show-authorized-user --json *> $null
if ($LASTEXITCODE -ne 0) {
  & $clasp.Source show-authorized-user *> $null
  if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE_NO_LOGIN_STARTED' }
}

$listText = (& $clasp.Source list-scripts 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_SCRIPTS_FAILED' }
$candidates = @(($listText -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($TargetTitle) })
if ($candidates.Count -eq 0) { throw 'SCRIPT_TITLE_NOT_FOUND' }
if ($candidates.Count -gt 1) { throw 'SCRIPT_TITLE_AMBIGUOUS' }
$match = [regex]::Match($candidates[0], '[A-Za-z0-9_-]{30,}')
if (!$match.Success) { throw 'SCRIPT_ID_PARSE_FAILED' }
$scriptId = $match.Value

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$workRoot = Join-Path $env:TEMP "central-contentos-sync-$stamp"
$sourceDir = Join-Path $workRoot 'canonical-source'
$liveDir = Join-Path $workRoot 'live-before'
$verifyDir = Join-Path $workRoot 'verify-after'
New-Item -ItemType Directory -Force -Path $workRoot,$liveDir,$verifyDir | Out-Null

# Reuse existing Windows Git credentials only. Never start a new login flow.
& $git.Source clone --depth 1 https://github.com/8friend8ship-cloud/contents-os-git.git $sourceDir
if ($LASTEXITCODE -ne 0) { throw 'EXISTING_GIT_AUTH_OR_CLONE_NOT_AVAILABLE_NO_LOGIN_STARTED' }

Push-Location $liveDir
try {
  & $clasp.Source clone-script $scriptId
  if ($LASTEXITCODE -ne 0) {
    & $clasp.Source clone $scriptId
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED' }
  }
} finally { Pop-Location }

$configPath = Join-Path $liveDir '.clasp.json'
$rootDir = $liveDir
$primaryExt = '.gs'
if (Test-Path $configPath) {
  $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  if ($cfg.rootDir) { $rootDir = [System.IO.Path]::GetFullPath((Join-Path $liveDir ([string]$cfg.rootDir))) }
  if ($cfg.scriptExtensions -and @($cfg.scriptExtensions).Count -gt 0) {
    $e = [string]@($cfg.scriptExtensions)[0]
    if (!$e.StartsWith('.')) { $e = '.' + $e }
    if ($e -in @('.js','.gs')) { $primaryExt = $e }
  }
}
if (!(Test-Path $rootDir)) { throw 'CLASP_ROOT_DIR_MISSING' }

$deployments = (& $clasp.Source list-deployments $scriptId 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_DEPLOYMENTS_FAILED' }
if ($deployments -notmatch [regex]::Escape($ExpectedDeploymentId)) { throw 'EXPECTED_DEPLOYMENT_ID_NOT_FOUND' }

$moduleNames = @(
  'ContentOS_Free_Backdata_Pipeline.gs',
  'ContentOS_Unified_Scheduler.gs',
  'ContentOS_Queens_YouTube_Bridge.gs',
  'ContentOS_Seed_Qualification_10m.gs',
  'ContentOS_Front_Lineage_Orchestrator.gs',
  'ContentOS_Front_Requirement_Seed_Rules.gs',
  'ContentOS_Runtime_Registry_V3.gs',
  'ContentOS_Drive_JSON_Cache_V3.gs'
)
$sourceRoot = Join-Path $sourceDir 'apps-script'
foreach ($name in $moduleNames) {
  $src = Join-Path $sourceRoot $name
  if (!(Test-Path $src)) { throw "CANONICAL_MODULE_MISSING:$name" }
  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
  $dst = Join-Path $rootDir ($base + $primaryExt)
  Copy-Item -Force -LiteralPath $src -Destination $dst
}

# Reuse the known-good physical processTaskQueue trigger. Inject one fail-open adapter call only.
$scriptFiles = @(Get-ChildItem -Path $rootDir -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in @('.gs','.js') })
$queueHits = @()
foreach ($f in $scriptFiles) {
  $t = Get-Content -Raw -LiteralPath $f.FullName
  if ($t -match 'function\s+processTaskQueue\s*\(\s*\)\s*\{') { $queueHits += $f }
}
if ($queueHits.Count -ne 1) { throw "PROCESS_TASK_QUEUE_DEFINITION_COUNT:$($queueHits.Count)" }
$queueFile = $queueHits[0].FullName
$queueText = Get-Content -Raw -LiteralPath $queueFile
if ($queueText -notmatch 'runContentOsScheduledStagesFromFactory\s*\(') {
  $pattern = '(function\s+processTaskQueue\s*\(\s*\)\s*\{)'
  $adapter = '${1}' + "`r`n  // Central Content OS adapter: reuse existing trigger; never block the factory queue.`r`n  try { if (typeof runContentOsScheduledStagesFromFactory === 'function') runContentOsScheduledStagesFromFactory(); } catch (contentOsErr) { console.error('CONTENTOS_SCHEDULER_ERROR', contentOsErr); }"
  $queueText = [regex]::Replace($queueText, $pattern, $adapter, 1)
  Set-Content -LiteralPath $queueFile -Value $queueText -Encoding UTF8
}

# Safety gates before push.
$allText = ($scriptFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($allText -notmatch 'function\s+runContentOsScheduledStagesFromFactory\s*\(') { throw 'UNIFIED_SCHEDULER_FUNCTION_MISSING' }
if (([regex]::Matches((Get-Content -Raw -LiteralPath $queueFile), 'runContentOsScheduledStagesFromFactory\s*\(')).Count -ne 1) { throw 'FACTORY_ADAPTER_COUNT_NOT_ONE' }

Push-Location $liveDir
try {
  & $clasp.Source show-file-status *> $null
  if ($LASTEXITCODE -ne 0) { throw 'CLASP_SHOW_FILE_STATUS_FAILED' }
  & $clasp.Source push --force
  if ($LASTEXITCODE -ne 0) { throw 'CLASP_PUSH_FAILED' }
} finally { Pop-Location }

Push-Location $verifyDir
try {
  & $clasp.Source clone-script $scriptId
  if ($LASTEXITCODE -ne 0) {
    & $clasp.Source clone $scriptId
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_VERIFY_CLONE_FAILED' }
  }
} finally { Pop-Location }

$verifyFiles = @(Get-ChildItem -Path $verifyDir -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in @('.gs','.js') })
$verifyText = ($verifyFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($verifyText -notmatch 'function\s+runContentOsScheduledStagesFromFactory\s*\(') { throw 'READBACK_UNIFIED_SCHEDULER_MISSING' }
if (([regex]::Matches($verifyText, 'runContentOsScheduledStagesFromFactory\s*\(')).Count -lt 2) { throw 'READBACK_FACTORY_ADAPTER_MISSING' }

[ordered]@{
  ok = $true
  action = 'CONTENTOS_APPS_SCRIPT_SYNC'
  version = $RunnerActionVersion
  scriptId = $scriptId
  expectedDeploymentId = $ExpectedDeploymentId
  canonicalRepo = '8friend8ship-cloud/contents-os-git'
  canonicalBranch = 'main'
  sourceReadback = $true
  physicalTriggerPolicy = 'REUSE_EXISTING_PROCESS_TASK_QUEUE'
  at = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 6
exit 0
