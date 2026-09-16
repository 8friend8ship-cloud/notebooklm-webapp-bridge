param(
  [string]$TaskManifestUrl = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner/tasks.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RunnerVersion = 'CENTRAL_APPS_SCRIPT_RUNNER_V1_20260821'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CentralAppsScriptRunner'
$StatePath = Join-Path $StateRoot 'state.json'
$LogPath = Join-Path $StateRoot 'runner.log'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-RunnerLog([string]$Message) {
  $line = "$(Get-Date -Format o) $Message"
  Add-Content -LiteralPath $LogPath -Value $line
}

function Load-State() {
  if (!(Test-Path $StatePath)) {
    return [ordered]@{ runnerVersion = $RunnerVersion; tasks = @{} }
  }
  try {
    $raw = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    $tasks = @{}
    if ($raw.tasks) {
      foreach ($p in $raw.tasks.PSObject.Properties) { $tasks[$p.Name] = $p.Value }
    }
    return [ordered]@{ runnerVersion = $RunnerVersion; tasks = $tasks }
  } catch {
    Write-RunnerLog "STATE_PARSE_FAILED $($_.Exception.Message)"
    return [ordered]@{ runnerVersion = $RunnerVersion; tasks = @{} }
  }
}

function Save-State($State) {
  $obj = [ordered]@{ runnerVersion = $RunnerVersion; updatedAt = (Get-Date).ToUniversalTime().ToString('o'); tasks = $State.tasks }
  $obj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Get-ClaspProjectLayout([string]$ProjectDir) {
  $configPath = Join-Path $ProjectDir '.clasp.json'
  $rootDir = $ProjectDir
  $extensions = @()
  if (Test-Path $configPath) {
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    if ($config.rootDir) { $rootDir = [System.IO.Path]::GetFullPath((Join-Path $ProjectDir ([string]$config.rootDir))) }
    if ($config.scriptExtensions) {
      $extensions = @($config.scriptExtensions | ForEach-Object {
        $e = [string]$_
        if ($e -and -not $e.StartsWith('.')) { '.' + $e } else { $e }
      } | Where-Object { $_ -in @('.js', '.gs') })
    } elseif ($config.fileExtension) {
      $e = [string]$config.fileExtension
      if ($e -and -not $e.StartsWith('.')) { $e = '.' + $e }
      if ($e -in @('.js', '.gs')) { $extensions = @($e) }
    }
  }
  if (!(Test-Path $rootDir)) { throw "CLASP_ROOT_DIR_MISSING:$rootDir" }
  if ($extensions.Count -eq 0) {
    $jsCount = @(Get-ChildItem -Path $rootDir -Recurse -File -Filter '*.js' -ErrorAction SilentlyContinue).Count
    $gsCount = @(Get-ChildItem -Path $rootDir -Recurse -File -Filter '*.gs' -ErrorAction SilentlyContinue).Count
    if ($gsCount -gt $jsCount) { $extensions = @('.gs', '.js') } else { $extensions = @('.js', '.gs') }
  } elseif ($extensions.Count -eq 1) {
    $extensions += @(@('.js', '.gs') | Where-Object { $_ -ne $extensions[0] })
  }
  return [pscustomobject]@{ RootDir = $rootDir; PrimaryExtension = $extensions[0]; AcceptedExtensions = $extensions }
}

function Get-ScriptFiles([string]$RootDir, [string[]]$Extensions) {
  return @(Get-ChildItem -Path $RootDir -Recurse -File -ErrorAction Stop | Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() })
}

function Count-ScriptPattern([System.IO.FileInfo[]]$Files, [string]$Pattern) {
  $count = 0
  foreach ($file in $Files) { $count += [regex]::Matches((Get-Content -Raw -LiteralPath $file.FullName), $Pattern).Count }
  return $count
}

function Assert-ExistingClaspAuth() {
  if (!(Get-Command clasp -ErrorAction SilentlyContinue)) { throw 'CLASP_COMMAND_NOT_FOUND' }
  & clasp show-authorized-user --json *> $null
  if ($LASTEXITCODE -ne 0) {
    & clasp show-authorized-user *> $null
    if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE' }
  }
}

function Download-RunnerAsset([string]$Name, [string]$Destination) {
  $base = 'https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/fix/central-appscript-runner-20260821/notebooklm-webapp-bridge-source-v0.2.0/scripts/windows/central-runner'
  Invoke-WebRequest -UseBasicParsing -Uri "$base/$Name" -OutFile $Destination
  if (!(Test-Path $Destination) -or (Get-Item $Destination).Length -lt 100) { throw "RUNNER_ASSET_DOWNLOAD_FAILED:$Name" }
}

function Invoke-TravelAppsScriptRepair($Task) {
  if ([string]$Task.targetTitle -ne 'WEBAPP_TEMPLATE_07') { throw 'TARGET_NOT_WHITELISTED' }
  $expectedDeploymentId = [string]$Task.expectedDeploymentId
  if ($expectedDeploymentId -ne 'AKfycbyzSZZqDwMAgqltkfCYQb4-aIZ4zSFlRHkh9dyN5F_Qd7hfUev6oVNqjUSsEtYE3b4VBA') { throw 'DEPLOYMENT_NOT_WHITELISTED' }

  Assert-ExistingClaspAuth
  $listText = (& clasp list-scripts 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_SCRIPTS_FAILED' }
  $candidates = @(($listText -split "`r?`n") | Where-Object { $_ -match [regex]::Escape([string]$Task.targetTitle) })
  if ($candidates.Count -eq 0) { throw 'SCRIPT_TITLE_NOT_FOUND' }
  if ($candidates.Count -gt 1) { throw 'SCRIPT_TITLE_AMBIGUOUS' }
  $match = [regex]::Match($candidates[0], '[A-Za-z0-9_-]{30,}')
  if (!$match.Success) { throw 'SCRIPT_ID_PARSE_FAILED' }
  $scriptId = $match.Value

  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $workRoot = Join-Path $env:TEMP "central-appscript-runner-$stamp"
  $liveDir = Join-Path $workRoot 'live-before'
  $verifyDir = Join-Path $workRoot 'verify-after'
  New-Item -ItemType Directory -Force -Path $liveDir,$verifyDir | Out-Null

  Push-Location $liveDir
  try {
    & clasp clone-script $scriptId
    if ($LASTEXITCODE -ne 0) {
      & clasp clone $scriptId
      if ($LASTEXITCODE -ne 0) { throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED' }
    }
  } finally { Pop-Location }

  $layout = Get-ClaspProjectLayout $liveDir
  $deployments = (& clasp list-deployments $scriptId 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_DEPLOYMENTS_FAILED' }
  if ($deployments -notmatch [regex]::Escape($expectedDeploymentId)) { throw 'EXPECTED_DEPLOYMENT_ID_NOT_FOUND' }

  $files = Get-ScriptFiles $layout.RootDir $layout.AcceptedExtensions
  $hits = @()
  foreach ($file in $files) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if ($text -match 'function\s+processTaskQueue\s*\(\s*\)\s*\{') { $hits += $file }
  }
  if ($hits.Count -ne 1) { throw "PROCESS_TASK_QUEUE_DEFINITION_COUNT:$($hits.Count)" }

  $targetFile = $hits[0].FullName
  $text = Get-Content -Raw -LiteralPath $targetFile
  if ($text -notmatch 'travelFactoryEnsureRuntimeConfig_\s*\(\s*\)') {
    $pattern = '(function\s+processTaskQueue\s*\(\s*\)\s*\{)'
    $replacement = '${1}' + "`r`n  // APP_TRAVEL central runner runtime guard.`r`n  travelFactoryEnsureRuntimeConfig_();"
    $text = [regex]::Replace($text, $pattern, $replacement, 1)
    Set-Content -LiteralPath $targetFile -Value $text -Encoding UTF8
  }

  $ext = $layout.PrimaryExtension
  $guardDest = Join-Path $layout.RootDir ("TravelFactoryRuntimeGuard" + $ext)
  $repairDest = Join-Path $layout.RootDir ("TravelFactoryRuntimeRepair" + $ext)
  Download-RunnerAsset 'TravelFactoryRuntimeGuard.gs' $guardDest
  Download-RunnerAsset 'TravelFactoryRuntimeRepair.gs' $repairDest

  $patched = Get-ScriptFiles $layout.RootDir $layout.AcceptedExtensions
  if ((Count-ScriptPattern $patched 'travelFactoryEnsureRuntimeConfig_\s*\(\s*\)') -lt 2) { throw 'LOCAL_GUARD_REFERENCE_VERIFY_FAILED' }

  Push-Location $liveDir
  try {
    & clasp show-file-status *> $null
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_SHOW_FILE_STATUS_FAILED' }
    & clasp push --force
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_PUSH_FAILED' }
  } finally { Pop-Location }

  Push-Location $verifyDir
  try {
    & clasp clone-script $scriptId
    if ($LASTEXITCODE -ne 0) {
      & clasp clone $scriptId
      if ($LASTEXITCODE -ne 0) { throw 'CLASP_VERIFY_CLONE_FAILED' }
    }
  } finally { Pop-Location }

  $verifyLayout = Get-ClaspProjectLayout $verifyDir
  $verifyFiles = Get-ScriptFiles $verifyLayout.RootDir $verifyLayout.AcceptedExtensions
  $guardFiles = @($verifyFiles | Where-Object { $_.BaseName -eq 'TravelFactoryRuntimeGuard' })
  $repairFiles = @($verifyFiles | Where-Object { $_.BaseName -eq 'TravelFactoryRuntimeRepair' })
  $refCount = Count-ScriptPattern $verifyFiles 'travelFactoryEnsureRuntimeConfig_\s*\(\s*\)'
  if ($guardFiles.Count -ne 1 -or $repairFiles.Count -ne 1 -or $refCount -lt 2) { throw 'CLEAN_RECLONE_READBACK_FAILED' }

  return [ordered]@{
    ok = $true
    action = 'TRAVEL_APPS_SCRIPT_REPAIR'
    scriptId = $scriptId
    expectedDeploymentId = $expectedDeploymentId
    sourceReadback = $true
    runnerVersion = $RunnerVersion
    at = (Get-Date).ToUniversalTime().ToString('o')
  }
}

try {
  Write-RunnerLog "RUN_START version=$RunnerVersion"
  $manifest = Invoke-RestMethod -Uri $TaskManifestUrl -Method Get
  if ([string]$manifest.channel -ne 'CENTRAL_APPS_SCRIPT_RUNNER_V1') { throw 'TASK_CHANNEL_MISMATCH' }
  $state = Load-State
  $runHadFailure = $false

  foreach ($task in @($manifest.tasks)) {
    if (!$task.enabled) { continue }
    $taskId = [string]$task.taskId
    if ([string]::IsNullOrWhiteSpace($taskId)) { continue }

    $existing = $state.tasks[$taskId]
    if ($existing -and [string]$existing.status -eq 'COMPLETED') { continue }
    $attempts = if ($existing -and $existing.attempts) { [int]$existing.attempts } else { 0 }
    $maxAttempts = if ($task.maxAttempts) { [int]$task.maxAttempts } else { 1 }
    if ($attempts -ge $maxAttempts) { continue }

    $attempts++
    $state.tasks[$taskId] = [ordered]@{ status = 'RUNNING'; attempts = $attempts; action = [string]$task.action; startedAt = (Get-Date).ToUniversalTime().ToString('o') }
    Save-State $state
    Write-RunnerLog "TASK_START id=$taskId action=$($task.action) attempt=$attempts"

    try {
      switch ([string]$task.action) {
        'TRAVEL_APPS_SCRIPT_REPAIR' { $result = Invoke-TravelAppsScriptRepair $task }
        default { throw 'ACTION_NOT_WHITELISTED' }
      }
      $state.tasks[$taskId] = [ordered]@{ status = 'COMPLETED'; attempts = $attempts; action = [string]$task.action; completedAt = (Get-Date).ToUniversalTime().ToString('o'); result = $result }
      Save-State $state
      Write-RunnerLog "TASK_COMPLETED id=$taskId"
    } catch {
      $runHadFailure = $true
      $state.tasks[$taskId] = [ordered]@{ status = 'FAILED'; attempts = $attempts; action = [string]$task.action; failedAt = (Get-Date).ToUniversalTime().ToString('o'); error = $_.Exception.Message }
      Save-State $state
      Write-RunnerLog "TASK_FAILED id=$taskId error=$($_.Exception.Message)"
    }
  }
  if ($runHadFailure) {
    Write-RunnerLog 'RUN_END_WITH_TASK_FAILURE'
    exit 2
  }
  Write-RunnerLog 'RUN_END_SUCCESS'
  exit 0
} catch {
  Write-RunnerLog "RUN_FATAL error=$($_.Exception.Message)"
  exit 1
}
