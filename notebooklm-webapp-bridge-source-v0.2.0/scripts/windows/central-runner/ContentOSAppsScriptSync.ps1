param(
  [Parameter(Mandatory=$true)][string]$TargetTitle,
  [Parameter(Mandatory=$true)][string]$ExpectedDeploymentId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RunnerActionVersion = 'CONTENTOS_BOUND_SYNC_V1_20260822'

# Special mode: refresh only the already-installed Central Apps Script Runner file.
# This mode does not call clasp, Git, Apps Script, OAuth, project, deployment or trigger APIs.
if ($TargetTitle -eq 'CENTRAL_RUNNER_REFRESH_X5_READONLY') {
  if ($ExpectedDeploymentId -ne 'RUNNER_REFRESH_X5_READONLY_20260831') { throw 'RUNNER_REFRESH_TOKEN_MISMATCH' }
  $runnerUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/CentralAppsScriptRunnerV2.ps1'
  $installDir = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
  $runnerPath = Join-Path $installDir 'CentralAppsScriptRunner.ps1'
  $tempPath = Join-Path $installDir 'CentralAppsScriptRunner.x5.new.ps1'
  $receiptName = 'CENTRAL_APPS_SCRIPT_RUNNER_X5_READONLY_REFRESH_RESULT.json'
  $receiptLocal = Join-Path $installDir $receiptName
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Invoke-WebRequest -UseBasicParsing -Uri $runnerUrl -OutFile $tempPath -TimeoutSec 30
  if (!(Test-Path $tempPath) -or (Get-Item $tempPath).Length -lt 2500) { throw 'PATCHED_RUNNER_DOWNLOAD_FAILED' }
  $tokens=$null; $parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile($tempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) { throw 'PATCHED_RUNNER_PARSE_FAILED' }
  $text = Get-Content -Raw -LiteralPath $tempPath
  if ($text -notmatch 'CENTRAL_APPS_SCRIPT_RUNNER_V2_X5_READONLY_20260831') { throw 'PATCHED_RUNNER_VERSION_MISMATCH' }
  if ($text -notmatch 'BOUND_APPS_SCRIPT_READONLY_RECOVERY') { throw 'PATCHED_RUNNER_ACTION_MISSING' }
  $beforeSha = if (Test-Path $runnerPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $runnerPath).Hash.ToLowerInvariant() } else { '' }
  $newSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $tempPath).Hash.ToLowerInvariant()
  Copy-Item -Force -LiteralPath $tempPath -Destination $runnerPath
  $afterSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $runnerPath).Hash.ToLowerInvariant()
  if ($afterSha -ne $newSha) { throw 'PATCHED_RUNNER_ATOMIC_COPY_HASH_MISMATCH' }
  $centralPath=''
  try {
    $target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
    foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
      $r=[string]$d.Root; if(-not$r){continue}
      foreach($c in @((Join-Path $r $target),(Join-Path $r ($myDriveKo+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))) {
        if(Test-Path -LiteralPath $c -PathType Container) {
          $rd=Join-Path $c 'Runtime_Readback'; New-Item -ItemType Directory -Force -Path $rd|Out-Null
          $centralPath=Join-Path $rd $receiptName; break
        }
      }
      if($centralPath){break}
    }
  } catch {}
  $result=[ordered]@{
    ok=$true; action='CENTRAL_RUNNER_REFRESH_X5_READONLY'; mutationScope='LOCAL_RUNNER_FILE_ONLY';
    runnerVersion='CENTRAL_APPS_SCRIPT_RUNNER_V2_X5_READONLY_20260831'; beforeSha256=$beforeSha; afterSha256=$afterSha;
    x5TasksEnabled=$false; oauthChanged=$false; appsScriptChanged=$false; deploymentChanged=$false; triggerChanged=$false;
    at=(Get-Date).ToUniversalTime().ToString('o'); centralReceiptPath=$centralPath
  }
  $json=$result|ConvertTo-Json -Depth 6
  $json|Set-Content -LiteralPath $receiptLocal -Encoding UTF8
  if($centralPath){$json|Set-Content -LiteralPath $centralPath -Encoding UTF8}
  Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  $json
  exit 0
}

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
  'ContentOS_Free_Backdata_Pipeline.gs','ContentOS_Unified_Scheduler.gs','ContentOS_Queens_YouTube_Bridge.gs','ContentOS_Seed_Qualification_10m.gs',
  'ContentOS_Front_Lineage_Orchestrator.gs','ContentOS_Front_Requirement_Seed_Rules.gs','ContentOS_Runtime_Registry_V3.gs','ContentOS_Drive_JSON_Cache_V3.gs'
)
$sourceRoot = Join-Path $sourceDir 'apps-script'
foreach ($name in $moduleNames) {
  $src = Join-Path $sourceRoot $name
  if (!(Test-Path $src)) { throw "CANONICAL_MODULE_MISSING:$name" }
  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
  $dst = Join-Path $rootDir ($base + $primaryExt)
  Copy-Item -Force -LiteralPath $src -Destination $dst
}

$scriptFiles = @(Get-ChildItem -Path $rootDir -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in @('.gs','.js') })
$queueHits = @()
foreach ($f in $scriptFiles) { $t=Get-Content -Raw -LiteralPath $f.FullName; if($t -match 'function\s+processTaskQueue\s*\(\s*\)\s*\{'){$queueHits+=$f} }
if ($queueHits.Count -ne 1) { throw "PROCESS_TASK_QUEUE_DEFINITION_COUNT:$($queueHits.Count)" }
$queueFile=$queueHits[0].FullName; $queueText=Get-Content -Raw -LiteralPath $queueFile
if ($queueText -notmatch 'runContentOsScheduledStagesFromFactory\s*\(') {
  $pattern='(function\s+processTaskQueue\s*\(\s*\)\s*\{)'
  $adapter='${1}'+"`r`n  // Central Content OS adapter: reuse existing trigger; never block the factory queue.`r`n  try { if (typeof runContentOsScheduledStagesFromFactory === 'function') runContentOsScheduledStagesFromFactory(); } catch (contentOsErr) { console.error('CONTENTOS_SCHEDULER_ERROR', contentOsErr); }"
  $queueText=[regex]::Replace($queueText,$pattern,$adapter,1);Set-Content -LiteralPath $queueFile -Value $queueText -Encoding UTF8
}
$allText=($scriptFiles|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName})-join"`n"
if($allText -notmatch 'function\s+runContentOsScheduledStagesFromFactory\s*\('){throw 'UNIFIED_SCHEDULER_FUNCTION_MISSING'}
if(([regex]::Matches((Get-Content -Raw -LiteralPath $queueFile),'runContentOsScheduledStagesFromFactory\s*\(')).Count-ne1){throw 'FACTORY_ADAPTER_COUNT_NOT_ONE'}

Push-Location $liveDir
try { & $clasp.Source show-file-status *> $null; if($LASTEXITCODE-ne0){throw 'CLASP_SHOW_FILE_STATUS_FAILED'}; & $clasp.Source push --force; if($LASTEXITCODE-ne0){throw 'CLASP_PUSH_FAILED'} } finally { Pop-Location }
Push-Location $verifyDir
try { & $clasp.Source clone-script $scriptId; if($LASTEXITCODE-ne0){& $clasp.Source clone $scriptId; if($LASTEXITCODE-ne0){throw 'CLASP_VERIFY_CLONE_FAILED'}} } finally { Pop-Location }
$verifyFiles=@(Get-ChildItem -Path $verifyDir -Recurse -File|Where-Object{$_.Extension.ToLowerInvariant()-in@('.gs','.js')});$verifyText=($verifyFiles|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName})-join"`n"
if($verifyText -notmatch 'function\s+runContentOsScheduledStagesFromFactory\s*\('){throw 'READBACK_UNIFIED_SCHEDULER_MISSING'}
if(([regex]::Matches($verifyText,'runContentOsScheduledStagesFromFactory\s*\(')).Count-lt2){throw 'READBACK_FACTORY_ADAPTER_MISSING'}
[ordered]@{ok=$true;action='CONTENTOS_APPS_SCRIPT_SYNC';version=$RunnerActionVersion;scriptId=$scriptId;expectedDeploymentId=$ExpectedDeploymentId;canonicalRepo='8friend8ship-cloud/contents-os-git';canonicalBranch='main';sourceReadback=$true;physicalTriggerPolicy='REUSE_EXISTING_PROCESS_TASK_QUEUE';at=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Depth 6
exit 0
