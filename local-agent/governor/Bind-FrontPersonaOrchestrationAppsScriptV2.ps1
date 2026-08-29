param(
  [string]$ExpectedDeploymentId = 'AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo',
  [int]$MaxScripts = 200
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SourceRepo = '8friend8ship-cloud/Analyzer-12.09'
$SourceCommit = 'a11429ed7f39ebafefc2bee0589b800b4b1185ab'
$GateRel = 'apps-script/personaOrchestrationGate.gs'
$FactoryRel = 'apps-script/personaOrchestrator.gs'
$ExpectedGateBlob = '948c056e6d175b5b709b53955abdd3b83869b9c3'
$ExpectedFactoryBlob = 'a3e8ebb0400ffb19bb8cc83e88ab2950be4e7320'
$Contract = 'PERSONA_ORCHESTRATION_GATE_FACTORY_V1_1_20260829'
$TargetSpreadsheetId = '1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Work = Join-Path $Base ('PersonaOrchestrationBindV2\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$LocalReceipt = Join-Path $Base 'LocalAgent\WEBAPP_TEMPLATE_05_PERSONA_BIND_V2.json'
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
  if (-not $Path) { return }
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Object | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Safe([string]$File, [string[]]$Args, [int]$Timeout = 90, [string]$Cwd = '') {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $File
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  if ($Cwd) { $psi.WorkingDirectory = $Cwd }
  $psi.Arguments = ($Args | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' '
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $psi
  [void]$process.Start()
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($Timeout * 1000)) {
    try { & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null } catch {}
    $stdout = if ($outTask.IsCompleted) { try { $outTask.Result } catch { '' } } else { '[stdout stream did not close before timeout]' }
    $stderr = if ($errTask.IsCompleted) { try { $errTask.Result } catch { '' } } else { '[stderr stream did not close before timeout]' }
    return [ordered]@{ ok = $false; exit = -1; timedOut = $true; stdout = $stdout; stderr = $stderr }
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
    $_.Extension -in @('.gs','.js','.json','.html') -and $_.Name -ne '.clasp.json'
  })
}

function Get-SourceFingerprint([string]$RootDir) {
  $parts = @()
  foreach ($file in @(Get-SourceFiles $RootDir | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($RootDir.Length).TrimStart([char]92).Replace('\','/')
    $parts += ($relative + ':' + (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash)
  }
  if (-not $parts.Count) { return '' }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
  finally { $sha.Dispose() }
}

function Get-ListedScripts($Clasp) {
  $json = Invoke-Safe $Clasp @('list-scripts','--json') 90
  $ids = New-Object System.Collections.ArrayList
  $rows = @()
  if ($json.ok -and $json.stdout) {
    try {
      $parsed = $json.stdout | ConvertFrom-Json
      if ($parsed -is [System.Array]) { $rows = @($parsed) }
      elseif ($parsed.scripts) { $rows = @($parsed.scripts) }
      elseif ($parsed.results) { $rows = @($parsed.results) }
      else { $rows = @($parsed) }
      foreach ($row in $rows) {
        $id = ''
        if ($row.id) { $id = [string]$row.id }
        elseif ($row.scriptId) { $id = [string]$row.scriptId }
        if ($id -and $id -match '^[A-Za-z0-9_-]{40,}$' -and -not $ids.Contains($id)) { [void]$ids.Add($id) }
      }
    } catch {}
  }
  $plain = $null
  if (-not $ids.Count) {
    $plain = Invoke-Safe $Clasp @('list-scripts') 90
    $text = (($plain.stdout + "`n" + $plain.stderr).Trim())
    foreach ($m in [regex]::Matches($text, '(?<![A-Za-z0-9_-])([A-Za-z0-9_-]{50,})(?![A-Za-z0-9_-])')) {
      $id = [string]$m.Groups[1].Value
      if ($id -and -not $ids.Contains($id)) { [void]$ids.Add($id) }
    }
  }
  return [ordered]@{ ok = ($ids.Count -gt 0); ids = @($ids | Select-Object -First $MaxScripts); json = $json; plain = $plain }
}

function Get-DeploymentText($Clasp, [string]$ScriptId) {
  $result = Invoke-Safe $Clasp @('list-deployments', $ScriptId) 60
  if (-not $result.ok) { $result = Invoke-Safe $Clasp @('deployments', $ScriptId) 60 }
  return $result
}

function Fetch-PinnedSource([string]$Rel, [string]$ExpectedBlob, [string]$Destination) {
  $url = 'https://raw.githubusercontent.com/' + $SourceRepo + '/' + $SourceCommit + '/' + $Rel + '?cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Destination -TimeoutSec 30
  $sha = (Get-GitBlobSha1 $Destination).ToLowerInvariant()
  if ($sha -ne $ExpectedBlob.ToLowerInvariant()) { throw ('SOURCE_BLOB_MISMATCH:' + $Rel + ':' + $sha + ':' + $ExpectedBlob) }
  return $sha
}

function Test-LiveContract([string]$RootDir) {
  $files = Get-SourceFiles $RootDir
  $texts = @()
  $queueHits = @()
  foreach ($file in $files) {
    try {
      $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
      $texts += $text
      if ($text -match 'function\s+processTaskQueue\s*\(\s*\)') { $queueHits += $file }
    } catch {}
  }
  $joined = $texts -join "`n"
  $gateFiles = @($files | Where-Object { $_.BaseName -eq 'PersonaOrchestrationGate' })
  $factoryFiles = @($files | Where-Object { $_.BaseName -eq 'PersonaOrchestrator' })
  $factoryText = if ($factoryFiles.Count -eq 1) { Get-Content -LiteralPath $factoryFiles[0].FullName -Raw -Encoding UTF8 } else { '' }
  $functionNames = @()
  foreach ($match in [regex]::Matches($joined, 'function\s+([A-Za-z0-9_]+)\s*\(')) { $functionNames += $match.Groups[1].Value }
  $promotionCandidates = @($functionNames | Where-Object { $_ -match '(?i)(promot|publish|template|factory)' } | Sort-Object -Unique | Select-Object -First 50)
  return [ordered]@{
    gateFileCount = $gateFiles.Count
    factoryFileCount = $factoryFiles.Count
    queueDefinitionCount = $queueHits.Count
    adapterV2 = [bool]($joined -match 'PERSONA_FACTORY_DUE_ADAPTER_V2')
    reviewPass = [bool]($joined -match 'function\s+personaReviewPass_')
    promotionGate = [bool]($joined -match 'function\s+assertPersonaPackagePromotionAllowed_')
    crosscheck = [bool]($joined -match 'function\s+runGeminiProjectCrosscheckGate_')
    canonicalDaily = [bool]($joined -match 'function\s+runDailyPersonaMaintenanceFromFactory_')
    reuseMatch = [bool]($joined -match 'function\s+matchPersonaForContent_')
    botPackBuild = [bool]($joined -match 'function\s+buildBotPersonaKnowledgePack_')
    recurringErrors = [bool]($joined -match 'function\s+collectRecurringPersonaErrors_')
    factoryDaily = [bool]($joined -match 'function\s+runPersonaFactoryDailyIfDue_')
    duplicateClockForbidden = -not [bool]($factoryText -match 'ScriptApp\.newTrigger')
    targetSpreadsheetReferenced = [bool]($joined -match [regex]::Escape($TargetSpreadsheetId))
    promotionCandidates = $promotionCandidates
  }
}

function Assert-LiveContract($State, [string]$StageName) {
  if ($State.gateFileCount -ne 1 -or $State.factoryFileCount -ne 1 -or $State.queueDefinitionCount -ne 1 -or
      -not $State.adapterV2 -or -not $State.reviewPass -or -not $State.promotionGate -or -not $State.crosscheck -or
      -not $State.canonicalDaily -or -not $State.reuseMatch -or -not $State.botPackBuild -or -not $State.recurringErrors -or
      -not $State.factoryDaily -or -not $State.duplicateClockForbidden -or -not $State.targetSpreadsheetReferenced) {
    throw ($StageName + '_CONTRACT_FAILED:' + ($State | ConvertTo-Json -Compress))
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
  $push = Invoke-Safe $Clasp @('push','--force') 180 $ProjectDir
  if (-not $push.ok) { throw ('ROLLBACK_PUSH_FAILED:' + ($push.stderr + ' ' + $push.stdout).Trim()) }
  $pull = Invoke-Safe $Clasp @('pull') 120 $ProjectDir
  if (-not $pull.ok) { throw 'ROLLBACK_PULL_FAILED' }
  $actualRoot = Get-ProjectRoot $ProjectDir
  $fingerprint = Get-SourceFingerprint $actualRoot
  if ($ExpectedFingerprint -and $fingerprint -ne $ExpectedFingerprint) { throw ('ROLLBACK_FINGERPRINT_MISMATCH:' + $fingerprint + ':' + $ExpectedFingerprint) }
  return [ordered]@{ ok = $true; push = $push; pull = $pull; fingerprint = $fingerprint }
}

$central = Find-CentralRoot
$driveReceipt = ''
if ($central) { $driveReceipt = Join-Path $central 'Runtime_Readback\AppsScript_Persona\WEBAPP_TEMPLATE_05_PERSONA_BIND_V2.json' }
$stage = 'INIT'
$diag = @()
$targetScriptId = ''
$targetDir = ''
$targetRoot = ''
$backup = ''
$beforeFp = ''
$gateSha = ''
$factorySha = ''
$push = $null
$read1 = $null
$read2 = $null
$rollback = $null
$pushDone = $false
$list = $null

try {
  $stage = 'CLASP_DISCOVERY'
  $clasp = Get-Command clasp.cmd -ErrorAction SilentlyContinue
  if (-not $clasp) { $clasp = Get-Command clasp -ErrorAction SilentlyContinue }
  if (-not $clasp) { throw 'CLASP_NOT_FOUND_EXISTING_AUTH_REQUIRED' }

  $stage = 'LIST_SCRIPTS_READONLY'
  $list = Get-ListedScripts $clasp.Source
  if (-not $list.ok -or -not $list.ids.Count) { throw 'CLASP_LIST_SCRIPTS_RETURNED_NO_SCRIPT_IDS' }

  $stage = 'TARGET_BY_DEPLOYMENT_READONLY'
  $matches = @()
  foreach ($scriptId in @($list.ids)) {
    $deployment = Get-DeploymentText $clasp.Source $scriptId
    $hit = [bool]($deployment.ok -and (($deployment.stdout + ' ' + $deployment.stderr) -match [regex]::Escape($ExpectedDeploymentId)))
    $diag += [ordered]@{ scriptId = $scriptId; deploymentsOk = $deployment.ok; deploymentMatch = $hit }
    if ($hit) { $matches += $scriptId }
  }
  if ($matches.Count -ne 1) { throw ('TARGET_DEPLOYMENT_MATCH_COUNT_V2:' + $matches.Count + ':LISTED=' + $list.ids.Count) }
  $targetScriptId = [string]$matches[0]

  $stage = 'CLONE_BASELINE_READONLY'
  $targetDir = Join-Path $Work ('target-' + $targetScriptId.Substring(0,[Math]::Min(12,$targetScriptId.Length)))
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  $clone = Invoke-Safe $clasp.Source @('clone-script',$targetScriptId) 150 $targetDir
  if (-not $clone.ok) { throw ('TARGET_CLONE_FAILED:' + ($clone.stderr + ' ' + $clone.stdout).Trim()) }
  $targetRoot = Get-ProjectRoot $targetDir
  $beforeFp = Get-SourceFingerprint $targetRoot
  if (-not $beforeFp) { throw 'BASELINE_FINGERPRINT_EMPTY' }
  $baselineFiles = Get-SourceFiles $targetRoot
  $baselineText = ($baselineFiles | ForEach-Object { try { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 } catch { '' } }) -join "`n"
  if ($baselineText -notmatch 'function\s+processTaskQueue\s*\(\s*\)') { throw 'TARGET_PROCESS_TASK_QUEUE_NOT_FOUND' }
  if ($baselineText -notmatch [regex]::Escape($TargetSpreadsheetId)) { throw 'TARGET_SPREADSHEET_SIGNATURE_NOT_FOUND' }

  $stage = 'SOURCE_FETCH_PINNED'
  $gateSrc = Join-Path $Work 'PersonaOrchestrationGate.gs'
  $factorySrc = Join-Path $Work 'PersonaOrchestrator.gs'
  $gateSha = Fetch-PinnedSource $GateRel $ExpectedGateBlob $gateSrc
  $factorySha = Fetch-PinnedSource $FactoryRel $ExpectedFactoryBlob $factorySrc
  $gateText = Get-Content -LiteralPath $gateSrc -Raw -Encoding UTF8
  $factoryText = Get-Content -LiteralPath $factorySrc -Raw -Encoding UTF8
  foreach ($needle in @('function personaReviewPass_','function assertPersonaPackagePromotionAllowed_','function runGeminiProjectCrosscheckGate_','function runDailyPersonaMaintenanceFromFactory_')) {
    if ($gateText -notmatch [regex]::Escape($needle)) { throw ('GATE_SOURCE_CONTRACT_MISSING:' + $needle) }
  }
  foreach ($needle in @('function matchPersonaForContent_','function buildBotPersonaKnowledgePack_','function collectRecurringPersonaErrors_','function runPersonaFactoryDailyIfDue_')) {
    if ($factoryText -notmatch [regex]::Escape($needle)) { throw ('FACTORY_SOURCE_CONTRACT_MISSING:' + $needle) }
  }
  if ($factoryText -match 'ScriptApp\.newTrigger') { throw 'FACTORY_DUPLICATE_CLOCK_SOURCE_FORBIDDEN' }

  $stage = 'BACKUP'
  if ($central) { $backup = Join-Path $central ('Backups\AppsScript_Persona\WEBAPP_TEMPLATE_05\V2_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
  else { $backup = Join-Path $Work 'backup' }
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  foreach ($file in @(Get-ChildItem -LiteralPath $targetDir -File -Recurse -ErrorAction SilentlyContinue)) {
    $relative = $file.FullName.Substring($targetDir.Length).TrimStart([char]92)
    $destination = Join-Path $backup $relative
    $parent = Split-Path -Parent $destination
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
  }

  $stage = 'PATCH_LOCAL'
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
  if ($queueText -notmatch 'PERSONA_FACTORY_DUE_ADAPTER_V2') {
    $pattern = 'function\s+processTaskQueue\s*\(\s*\)\s*\{'
    $adapter = @'

  // PERSONA_FACTORY_DUE_ADAPTER_V2
  try {
    if (typeof runPersonaFactoryDailyIfDue_ === 'function') {
      runPersonaFactoryDailyIfDue_(SpreadsheetApp.openById('1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'), {source:'processTaskQueue'});
    }
  } catch (personaFactoryDueError) {
    console.warn('PERSONA_FACTORY_DUE_DEGRADED', String(personaFactoryDueError && personaFactoryDueError.message || personaFactoryDueError));
  }
'@
    $patched = [regex]::Replace($queueText, $pattern, '${0}' + $adapter, 1)
    if ($patched -eq $queueText) { throw 'PROCESS_TASK_QUEUE_ADAPTER_INSERT_FAILED' }
    Set-Content -LiteralPath $queueFiles[0].FullName -Value $patched -Encoding UTF8
  }
  Copy-Item -LiteralPath $gateSrc -Destination (Join-Path $targetRoot 'PersonaOrchestrationGate.gs') -Force
  Copy-Item -LiteralPath $factorySrc -Destination (Join-Path $targetRoot 'PersonaOrchestrator.gs') -Force
  $local = Test-LiveContract $targetRoot
  Assert-LiveContract $local 'LOCAL_PATCH_VERIFY'

  $stage = 'PUSH_EXISTING_PROJECT'
  $push = Invoke-Safe $clasp.Source @('push','--force') 180 $targetDir
  if (-not $push.ok) { throw ('CLASP_PUSH_FAILED:' + ($push.stderr + ' ' + $push.stdout).Trim()) }
  $pushDone = $true

  $stage = 'READBACK_X1'
  $pull1 = Invoke-Safe $clasp.Source @('pull') 120 $targetDir
  if (-not $pull1.ok) { throw ('READBACK_X1_PULL_FAILED:' + ($pull1.stderr + ' ' + $pull1.stdout).Trim()) }
  $targetRoot = Get-ProjectRoot $targetDir
  $read1 = Test-LiveContract $targetRoot
  Assert-LiveContract $read1 'READBACK_X1'

  $stage = 'READBACK_X2'
  Start-Sleep -Milliseconds 400
  $pull2 = Invoke-Safe $clasp.Source @('pull') 120 $targetDir
  if (-not $pull2.ok) { throw ('READBACK_X2_PULL_FAILED:' + ($pull2.stderr + ' ' + $pull2.stdout).Trim()) }
  $targetRoot = Get-ProjectRoot $targetDir
  $read2 = Test-LiveContract $targetRoot
  Assert-LiveContract $read2 'READBACK_X2'

  $stage = 'DEPLOYMENT_INVARIANT'
  $deploymentAfter = Get-DeploymentText $clasp.Source $targetScriptId
  if (-not $deploymentAfter.ok -or (($deploymentAfter.stdout + ' ' + $deploymentAfter.stderr) -notmatch [regex]::Escape($ExpectedDeploymentId))) { throw 'EXISTING_DEPLOYMENT_INVARIANT_FAILED' }

  $result = [ordered]@{
    ok = $true
    status = 'PUSH_PULL_READBACK_X2_PASS'
    contract = $Contract
    stage = 'DONE'
    scriptId = $targetScriptId
    deploymentId = $ExpectedDeploymentId
    spreadsheetId = $TargetSpreadsheetId
    backup = $backup
    beforeFingerprint = $beforeFp
    sourceCommit = $SourceCommit
    gateBlob = $gateSha
    factoryBlob = $factorySha
    listedScriptCount = $list.ids.Count
    readback1 = $read1
    readback2 = $read2
    promotionCandidates = $read2.promotionCandidates
    diagnostics = $diag
    newProjectCreated = $false
    oauthChanged = $false
    scopeChanged = $false
    newDeployment = $false
    newTrigger = $false
    duplicateClockCreated = $false
    paidGeminiApiCalled = $false
    at = (Get-Date).ToString('o')
  }
  Save-Json $LocalReceipt $result
  if ($driveReceipt) { Save-Json $driveReceipt $result }
  $result | ConvertTo-Json -Depth 80 -Compress
  exit 0
} catch {
  $errorText = $_.Exception.Message
  if ($pushDone -and $targetDir -and $backup) {
    try { $rollback = Restore-Snapshot $targetDir $targetRoot $backup $clasp.Source $beforeFp }
    catch { $rollback = [ordered]@{ ok = $false; error = $_.Exception.Message } }
  }
  $status = 'FAILED'
  if ($rollback -and $rollback.ok) { $status = 'FAILED_ROLLED_BACK' }
  $result = [ordered]@{
    ok = $false
    status = $status
    contract = $Contract
    stage = $stage
    error = $errorText
    scriptId = $targetScriptId
    deploymentId = $ExpectedDeploymentId
    spreadsheetId = $TargetSpreadsheetId
    backup = $backup
    beforeFingerprint = $beforeFp
    sourceCommit = $SourceCommit
    gateBlob = $gateSha
    factoryBlob = $factorySha
    listedScriptCount = if ($list -and $list.ids) { $list.ids.Count } else { 0 }
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
    duplicateClockCreated = $false
    paidGeminiApiCalled = $false
    at = (Get-Date).ToString('o')
  }
  try { Save-Json $LocalReceipt $result } catch {}
  if ($driveReceipt) { try { Save-Json $driveReceipt $result } catch {} }
  $result | ConvertTo-Json -Depth 80 -Compress
  exit 2
}
