param(
  [string]$ExpectedDeploymentId = 'AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo',
  [int]$MaxBindings = 50
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SourceRepo = '8friend8ship-cloud/Analyzer-12.09'
$SourceCommit = '0ad86472116e73728d99c0c49d940e0a884d4739'
$SourceRel = 'apps-script/personaOrchestrationGate.gs'
$ExpectedSourceBlob = '948c056e6d175b5b709b53955abdd3b83869b9c3'
$Contract = 'PERSONA_ORCHESTRATION_GATE_V1_20260828'
$TargetSpreadsheetId = '1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Work = Join-Path $Base ('PersonaOrchestrationBindV1\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$LocalReceipt = Join-Path $Base 'LocalAgent\WEBAPP_TEMPLATE_05_PERSONA_BIND_V1.json'
New-Item -ItemType Directory -Force -Path $Work | Out-Null

function Get-GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
  $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header, 0, $all, 0, $header.Length)
  [Buffer]::BlockCopy($bytes, 0, $all, $header.Length, $bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create()
  try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') }
  finally { $sha.Dispose() }
}

function Find-CentralRoot {
  $name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    if (-not $drive.Root) { continue }
    foreach ($candidate in @(
      (Join-Path $drive.Root $name),
      (Join-Path $drive.Root ($myDriveKo + '\' + $name)),
      (Join-Path $drive.Root ('My Drive\' + $name)),
      (Join-Path $drive.Root ('Google Drive\' + $name))
    )) {
      if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
  }
  return ''
}

function Save-Json([string]$Path, $Object) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Object | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Safe([string]$File, [string[]]$Args, [int]$Timeout = 90, [string]$Cwd = '') {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $File
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  if ($Cwd) { $psi.WorkingDirectory = $Cwd }
  $psi.Arguments = ($Args -join ' ')
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $psi
  [void]$process.Start()
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($Timeout * 1000)) {
    try { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null } catch {}
    return [ordered]@{ ok = $false; exit = -1; timedOut = $true; stdout = $outTask.Result; stderr = $errTask.Result }
  }
  return [ordered]@{
    ok = ($process.ExitCode -eq 0)
    exit = $process.ExitCode
    timedOut = $false
    stdout = $outTask.Result.Trim()
    stderr = $errTask.Result.Trim()
  }
}

function Get-ProjectRoot([string]$ProjectDir) {
  $configPath = Join-Path $ProjectDir '.clasp.json'
  if (-not (Test-Path -LiteralPath $configPath)) { return $ProjectDir }
  try {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.rootDir) { return [IO.Path]::GetFullPath((Join-Path $ProjectDir ([string]$config.rootDir))) }
  } catch {}
  return $ProjectDir
}

function Get-SourceFiles([string]$RootDir) {
  return @(Get-ChildItem -LiteralPath $RootDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -in @('.gs', '.js', '.json') -and $_.Name -ne '.clasp.json'
  })
}

function Get-SourceFingerprint([string]$RootDir) {
  $parts = @()
  foreach ($file in @(Get-SourceFiles $RootDir | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($RootDir.Length).TrimStart([char]92).Replace('\', '/')
    $parts += ($relative + ':' + (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash)
  }
  if (-not $parts.Count) { return '' }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
  finally { $sha.Dispose() }
}

function Get-DeploymentText($Clasp, [string]$ProjectDir) {
  $result = Invoke-Safe $Clasp @('deployments') 45 $ProjectDir
  if (-not $result.ok) { $result = Invoke-Safe $Clasp @('list-deployments') 45 $ProjectDir }
  return $result
}

function Test-LiveContract([string]$RootDir) {
  $files = Get-SourceFiles $RootDir
  $texts = @()
  foreach ($file in $files) {
    try { $texts += (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) } catch {}
  }
  $joined = $texts -join "`n"
  $queueHits = @()
  foreach ($file in $files) {
    try {
      $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
      if ($text -match 'function\s+processTaskQueue\s*\(\s*\)') { $queueHits += $file }
    } catch {}
  }
  $functionNames = @()
  foreach ($match in [regex]::Matches($joined, 'function\s+([A-Za-z0-9_]+)\s*\(')) {
    $functionNames += $match.Groups[1].Value
  }
  $promotionCandidates = @($functionNames | Where-Object {
    $_ -match '(?i)(promot|publish|template|factory)'
  } | Sort-Object -Unique | Select-Object -First 40)
  return [ordered]@{
    personaFileCount = @($files | Where-Object { $_.BaseName -eq 'PersonaOrchestrationGate' }).Count
    queueDefinitionCount = $queueHits.Count
    adapter = [bool]($joined -match 'PERSONA_ORCH_FACTORY_ADAPTER_V1')
    reviewPass = [bool]($joined -match 'function\s+personaReviewPass_')
    packReady = [bool]($joined -match 'function\s+personaPackReady_')
    crosscheck = [bool]($joined -match 'function\s+runGeminiProjectCrosscheckGate_')
    daily = [bool]($joined -match 'function\s+runDailyPersonaMaintenanceFromFactory_')
    promotionCandidates = $promotionCandidates
  }
}

function Restore-Snapshot([string]$ProjectDir, [string]$RootDir, [string]$BackupDir, $Clasp, [string]$ExpectedFingerprint) {
  foreach ($file in @(Get-SourceFiles $RootDir)) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
  foreach ($file in @(Get-ChildItem -LiteralPath $BackupDir -File -Recurse -ErrorAction SilentlyContinue)) {
    $relative = $file.FullName.Substring($BackupDir.Length).TrimStart([char]92)
    $destination = Join-Path $ProjectDir $relative
    $parent = Split-Path -Parent $destination
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
  }
  $push = Invoke-Safe $Clasp @('push', '--force') 150 $ProjectDir
  if (-not $push.ok) { throw ('ROLLBACK_PUSH_FAILED:' + ($push.stderr + ' ' + $push.stdout).Trim()) }
  $pull = Invoke-Safe $Clasp @('pull') 90 $ProjectDir
  if (-not $pull.ok) { throw 'ROLLBACK_PULL_FAILED' }
  $actualRoot = Get-ProjectRoot $ProjectDir
  $fingerprint = Get-SourceFingerprint $actualRoot
  if ($ExpectedFingerprint -and $fingerprint -ne $ExpectedFingerprint) {
    throw ('ROLLBACK_FINGERPRINT_MISMATCH:' + $fingerprint + ':' + $ExpectedFingerprint)
  }
  return [ordered]@{ ok = $true; push = $push; pull = $pull; fingerprint = $fingerprint }
}

$central = Find-CentralRoot
$driveReceipt = ''
if ($central) { $driveReceipt = Join-Path $central 'Runtime_Readback\AppsScript_Persona\WEBAPP_TEMPLATE_05_PERSONA_BIND_V1.json' }
$stage = 'INIT'
$diag = @()
$target = $null
$targetRoot = ''
$backup = ''
$sourceSha = ''
$beforeFp = ''
$push = $null
$read1 = $null
$read2 = $null
$rollback = $null
$pushDone = $false

try {
  $stage = 'CLASP_DISCOVERY'
  $clasp = Get-Command clasp.cmd -ErrorAction SilentlyContinue
  if (-not $clasp) { $clasp = Get-Command clasp -ErrorAction SilentlyContinue }
  if (-not $clasp) { throw 'CLASP_NOT_FOUND_EXISTING_BINDING_REQUIRED' }

  $stage = 'SOURCE_FETCH'
  $src = Join-Path $Work 'PersonaOrchestrationGate.gs'
  $url = 'https://raw.githubusercontent.com/' + $SourceRepo + '/' + $SourceCommit + '/' + $SourceRel + '?cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $src -TimeoutSec 30
  $sourceSha = (Get-GitBlobSha1 $src).ToLowerInvariant()
  if ($sourceSha -ne $ExpectedSourceBlob) { throw ('PERSONA_SOURCE_SHA_MISMATCH:' + $sourceSha + ':' + $ExpectedSourceBlob) }
  $sourceText = Get-Content -LiteralPath $src -Raw -Encoding UTF8
  foreach ($needle in @(
    'function personaReviewPass_',
    'function personaPackReady_',
    'function runGeminiProjectCrosscheckGate_',
    'function runDailyPersonaMaintenanceFromFactory_'
  )) {
    if ($sourceText -notmatch [regex]::Escape($needle)) { throw ('PERSONA_SOURCE_CONTRACT_MISSING:' + $needle) }
  }

  $stage = 'BINDING_SCAN'
  $roots = @($Base, (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Desktop')) | Where-Object { Test-Path $_ -PathType Container }
  $seen = @{}
  $bindings = @()
  foreach ($root in $roots) {
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '.clasp.json' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First $MaxBindings)) {
      try {
        $config = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.scriptId -and -not $seen[[string]$config.scriptId]) {
          $seen[[string]$config.scriptId] = $true
          $bindings += [ordered]@{ scriptId = [string]$config.scriptId; dir = $file.Directory.FullName }
        }
      } catch {}
    }
  }
  if (-not $bindings.Count) { throw 'NO_EXISTING_CLASP_BINDING_FOUND' }

  $stage = 'TARGET_BY_DEPLOYMENT'
  $matches = @()
  foreach ($binding in $bindings) {
    $deployment = Get-DeploymentText $clasp.Source $binding.dir
    $hit = [bool]($deployment.ok -and (($deployment.stdout + ' ' + $deployment.stderr) -match [regex]::Escape($ExpectedDeploymentId)))
    $diag += [ordered]@{
      scriptId = $binding.scriptId
      dir = $binding.dir
      deploymentsOk = $deployment.ok
      deploymentMatch = $hit
    }
    if ($hit) { $matches += $binding }
  }
  if ($matches.Count -ne 1) { throw ('TARGET_DEPLOYMENT_MATCH_COUNT:' + $matches.Count) }
  $target = $matches[0]

  $stage = 'PULL_BASELINE'
  $pull0 = Invoke-Safe $clasp.Source @('pull') 90 $target.dir
  if (-not $pull0.ok) { throw ('BASELINE_PULL_FAILED:' + ($pull0.stderr + ' ' + $pull0.stdout).Trim()) }
  $targetRoot = Get-ProjectRoot $target.dir
  $beforeFp = Get-SourceFingerprint $targetRoot

  $stage = 'BACKUP'
  if ($central) { $backup = Join-Path $central ('Backups\AppsScript_Persona\WEBAPP_TEMPLATE_05\' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
  else { $backup = Join-Path $Work 'backup' }
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  foreach ($file in @(Get-ChildItem -LiteralPath $target.dir -File -Recurse -ErrorAction SilentlyContinue)) {
    $relative = $file.FullName.Substring($target.dir.Length).TrimStart([char]92)
    $destination = Join-Path $backup $relative
    $parent = Split-Path -Parent $destination
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
  }

  $stage = 'PATCH'
  $files = Get-SourceFiles $targetRoot
  $queueFiles = @()
  foreach ($file in $files) {
    try {
      $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
      if ($text -match 'function\s+processTaskQueue\s*\(\s*\)') { $queueFiles += $file }
    } catch {}
  }
  if ($queueFiles.Count -ne 1) { throw ('PROCESSTASKQUEUE_DEFINITION_COUNT:' + $queueFiles.Count) }
  $queueText = Get-Content -LiteralPath $queueFiles[0].FullName -Raw -Encoding UTF8
  if ($queueText -notmatch 'PERSONA_ORCH_FACTORY_ADAPTER_V1') {
    $pattern = 'function\s+processTaskQueue\s*\(\s*\)\s*\{'
    $adapter = @'

  // PERSONA_ORCH_FACTORY_ADAPTER_V1
  try {
    if (typeof runDailyPersonaMaintenanceFromFactory_ === 'function') {
      runDailyPersonaMaintenanceFromFactory_(SpreadsheetApp.openById('1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'), {source:'processTaskQueue'});
    }
  } catch (personaOrchMaintenanceError) {
    console.warn('PERSONA_ORCH_MAINTENANCE_DEGRADED', String(personaOrchMaintenanceError && personaOrchMaintenanceError.message || personaOrchMaintenanceError));
  }
'@
    $queueText = [regex]::Replace($queueText, $pattern, '${0}' + $adapter, 1)
    Set-Content -LiteralPath $queueFiles[0].FullName -Value $queueText -Encoding UTF8
  }
  Copy-Item -LiteralPath $src -Destination (Join-Path $targetRoot 'PersonaOrchestrationGate.gs') -Force
  $local = Test-LiveContract $targetRoot
  if ($local.personaFileCount -ne 1 -or $local.queueDefinitionCount -ne 1 -or -not $local.adapter -or -not $local.reviewPass -or -not $local.packReady -or -not $local.crosscheck -or -not $local.daily) {
    throw ('LOCAL_PATCH_VERIFY_FAILED:' + ($local | ConvertTo-Json -Compress))
  }

  $stage = 'PUSH'
  $push = Invoke-Safe $clasp.Source @('push', '--force') 150 $target.dir
  if (-not $push.ok) { throw ('CLASP_PUSH_FAILED:' + ($push.stderr + ' ' + $push.stdout).Trim()) }
  $pushDone = $true

  $stage = 'READBACK_X1'
  $pull1 = Invoke-Safe $clasp.Source @('pull') 90 $target.dir
  if (-not $pull1.ok) { throw 'READBACK_X1_PULL_FAILED' }
  $targetRoot = Get-ProjectRoot $target.dir
  $read1 = Test-LiveContract $targetRoot
  if ($read1.personaFileCount -ne 1 -or $read1.queueDefinitionCount -ne 1 -or -not $read1.adapter -or -not $read1.reviewPass -or -not $read1.packReady -or -not $read1.crosscheck -or -not $read1.daily) {
    throw ('READBACK_X1_CONTRACT_FAILED:' + ($read1 | ConvertTo-Json -Compress))
  }

  $stage = 'READBACK_X2'
  $pull2 = Invoke-Safe $clasp.Source @('pull') 90 $target.dir
  if (-not $pull2.ok) { throw 'READBACK_X2_PULL_FAILED' }
  $targetRoot = Get-ProjectRoot $target.dir
  $read2 = Test-LiveContract $targetRoot
  if ($read2.personaFileCount -ne 1 -or $read2.queueDefinitionCount -ne 1 -or -not $read2.adapter -or -not $read2.reviewPass -or -not $read2.packReady -or -not $read2.crosscheck -or -not $read2.daily) {
    throw ('READBACK_X2_CONTRACT_FAILED:' + ($read2 | ConvertTo-Json -Compress))
  }

  $stage = 'DEPLOYMENT_INVARIANT'
  $deploymentAfter = Get-DeploymentText $clasp.Source $target.dir
  if (-not $deploymentAfter.ok -or (($deploymentAfter.stdout + ' ' + $deploymentAfter.stderr) -notmatch [regex]::Escape($ExpectedDeploymentId))) {
    throw 'EXISTING_DEPLOYMENT_INVARIANT_FAILED'
  }

  $result = [ordered]@{
    ok = $true
    status = 'PUSH_PULL_READBACK_X2_PASS'
    contract = $Contract
    stage = 'DONE'
    scriptId = $target.scriptId
    deploymentId = $ExpectedDeploymentId
    spreadsheetId = $TargetSpreadsheetId
    backup = $backup
    beforeFingerprint = $beforeFp
    sourceCommit = $SourceCommit
    sourceBlob = $sourceSha
    readback1 = $read1
    readback2 = $read2
    promotionCandidates = $read2.promotionCandidates
    diagnostics = $diag
    newProjectCreated = $false
    oauthChanged = $false
    scopeChanged = $false
    newDeployment = $false
    newTrigger = $false
    paidGeminiApiCalled = $false
    at = (Get-Date).ToString('o')
  }
  Save-Json $LocalReceipt $result
  if ($driveReceipt) { Save-Json $driveReceipt $result }
  $result | ConvertTo-Json -Depth 50 -Compress
  exit 0
} catch {
  $errorText = $_.Exception.Message
  if ($pushDone -and $target -and $backup) {
    try { $rollback = Restore-Snapshot $target.dir $targetRoot $backup $clasp.Source $beforeFp }
    catch { $rollback = [ordered]@{ ok = $false; error = $_.Exception.Message } }
  }
  $status = 'FAILED'
  if ($rollback -and $rollback.ok) { $status = 'FAILED_ROLLED_BACK' }
  $scriptIdValue = ''
  if ($target) { $scriptIdValue = $target.scriptId }
  $result = [ordered]@{
    ok = $false
    status = $status
    contract = $Contract
    stage = $stage
    error = $errorText
    scriptId = $scriptIdValue
    deploymentId = $ExpectedDeploymentId
    spreadsheetId = $TargetSpreadsheetId
    backup = $backup
    beforeFingerprint = $beforeFp
    sourceCommit = $SourceCommit
    sourceBlob = $sourceSha
    push = $push
    readback1 = $read1
    readback2 = $read2
    rollback = $rollback
    diagnostics = $diag
    newProjectCreated = $false
    oauthChanged = $false
    scopeChanged = $false
    newDeployment = $false
    newTrigger = $false
    paidGeminiApiCalled = $false
    at = (Get-Date).ToString('o')
  }
  try { Save-Json $LocalReceipt $result } catch {}
  if ($driveReceipt) { try { Save-Json $driveReceipt $result } catch {} }
  $result | ConvertTo-Json -Depth 50 -Compress
  exit 2
}
