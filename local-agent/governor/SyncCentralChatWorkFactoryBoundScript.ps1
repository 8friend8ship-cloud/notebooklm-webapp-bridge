param(
  [string]$ProjectTitle = 'WEBAPP_TEMPLATE_03',
  [string]$SpreadsheetId = '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk',
  [string]$ExpectedDeploymentId = 'AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P',
  [string]$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge',
  [string]$Branch = 'feat/central-daily-qa-asset-governor-20260828',
  [string]$SourcePath = 'apps-script/CentralChatWorkFactory.gs',
  [switch]$SkipFunctionRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root = Join-Path $Base 'Control\CentralChatFactorySync'
$RunId = 'CCWF_SYNC_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$Work = Join-Path $Root $RunId
$Clone = Join-Path $Work 'bound'
$ResultPath = Join-Path $Work 'result.json'
New-Item -ItemType Directory -Force -Path $Clone | Out-Null

function EmitResult([hashtable]$r, [int]$exitCode) {
  $r.runId = $RunId
  $r.projectTitle = $ProjectTitle
  $r.spreadsheetId = $SpreadsheetId
  $r.expectedDeploymentId = $ExpectedDeploymentId
  $r.at = (Get-Date).ToString('o')
  $json = $r | ConvertTo-Json -Depth 30
  $json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
  Write-Output ('CENTRAL_CHAT_FACTORY_SYNC_JSON=' + ($r | ConvertTo-Json -Depth 30 -Compress))
  exit $exitCode
}

function RunCapture([string]$exe, [string[]]$args) {
  $output = & $exe @args 2>&1 | Out-String
  return [ordered]@{ exitCode = $LASTEXITCODE; text = $output.Trim() }
}

function Get-ClaspProjects {
  $items = @()
  $jsonAttempt = RunCapture 'clasp' @('list','--json')
  if ($jsonAttempt.exitCode -eq 0 -and $jsonAttempt.text) {
    try {
      $obj = $jsonAttempt.text | ConvertFrom-Json
      $arr = if ($obj -is [System.Array]) { $obj } elseif ($obj.projects) { $obj.projects } else { @($obj) }
      foreach ($p in @($arr)) {
        $id = [string]($p.scriptId)
        $title = [string]($p.title)
        if (-not $title) { $title = [string]($p.name) }
        if ($id) { $items += [pscustomobject]@{ title=$title; scriptId=$id; source='clasp-list-json' } }
      }
    } catch {}
  }
  if ($items.Count -eq 0) {
    $plain = RunCapture 'clasp' @('list')
    if ($plain.exitCode -ne 0) { return @() }
    foreach ($line in ($plain.text -split "`r?`n")) {
      if (-not $line.Trim()) { continue }
      $m = [regex]::Match($line, '(?:/d/|projects/)?([A-Za-z0-9_-]{35,})')
      if ($m.Success) {
        $items += [pscustomobject]@{ title=$line.Trim(); scriptId=$m.Groups[1].Value; source='clasp-list-text' }
      }
    }
  }
  return @($items)
}

try {
  if (-not (Get-Command clasp -ErrorAction SilentlyContinue)) {
    EmitResult @{ ok=$false; status='BLOCKED_ACCESS'; stage='CLASP_CLI_MISSING'; approvalRequired=@('RECOVER_EXISTING_CLASP_INSTALL_ONLY') } 20
  }
  $authPath = Join-Path $env:USERPROFILE '.clasprc.json'
  if (-not (Test-Path -LiteralPath $authPath)) {
    EmitResult @{ ok=$false; status='BLOCKED_APPROVAL'; stage='CLASP_AUTH_RECEIPT_MISSING'; approvalRequired=@('GOOGLE_CLASP_LOGIN_IF_EXISTING_RECEIPT_CANNOT_BE_RECOVERED') } 21
  }

  $projects = @(Get-ClaspProjects)
  $matches = @($projects | Where-Object { $_.title -match [regex]::Escape($ProjectTitle) })
  if ($matches.Count -ne 1) {
    EmitResult @{
      ok=$false; status='DIAGNOSTIC_HOLD'; stage='UNIQUE_BOUND_PROJECT_NOT_RESOLVED';
      matchCount=$matches.Count; projectCount=$projects.Count;
      candidates=@($matches | ForEach-Object { [ordered]@{title=$_.title;scriptId=$_.scriptId;source=$_.source} });
      rule='NO_PUSH_UNTIL_EXACTLY_ONE_PROJECT_TITLE_MATCH'
    } 22
  }
  $scriptId = [string]$matches[0].scriptId

  Push-Location $Clone
  try {
    $cloneResult = RunCapture 'clasp' @('clone',$scriptId)
    if ($cloneResult.exitCode -ne 0) {
      EmitResult @{ok=$false;status='FAILED_TEST';stage='CLASP_CLONE_FAILED';scriptId=$scriptId;error=$cloneResult.text} 23
    }

    $deployResult = RunCapture 'clasp' @('deployments')
    $deploymentOk = $deployResult.exitCode -eq 0 -and $deployResult.text -match [regex]::Escape($ExpectedDeploymentId)
    if (-not $deploymentOk) {
      EmitResult @{
        ok=$false;status='DIAGNOSTIC_HOLD';stage='DEPLOYMENT_ID_MISMATCH';scriptId=$scriptId;
        deploymentReadback=$deployResult.text;rule='NO_PUSH_ON_DEPLOYMENT_MISMATCH'
      } 24
    }

    $beforeFiles = @(Get-ChildItem -LiteralPath $Clone -File -Recurse | Where-Object { $_.Name -ne '.clasp.json' } | ForEach-Object {
      [ordered]@{ path=$_.FullName.Substring($Clone.Length).TrimStart('\\'); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })

    $rawUrl = 'https://raw.githubusercontent.com/' + $Repo + '/' + $Branch + '/' + $SourcePath
    $target = Join-Path $Clone 'CentralChatWorkFactory.gs'
    Invoke-WebRequest -UseBasicParsing -Uri $rawUrl -OutFile $target -TimeoutSec 30
    if (-not (Test-Path -LiteralPath $target)) {
      EmitResult @{ok=$false;status='FAILED_TEST';stage='SOURCE_DOWNLOAD_MISSING';scriptId=$scriptId;rawUrl=$rawUrl} 25
    }
    $sourceHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    $sourceBytes = (Get-Item -LiteralPath $target).Length
    if ($sourceBytes -lt 5000) {
      EmitResult @{ok=$false;status='FAILED_TEST';stage='SOURCE_FILE_TOO_SMALL';scriptId=$scriptId;bytes=$sourceBytes;sha256=$sourceHash} 26
    }

    $statusBefore = RunCapture 'clasp' @('status')
    $push = RunCapture 'clasp' @('push','--force')
    if ($push.exitCode -ne 0) {
      EmitResult @{
        ok=$false;status='FAILED_TEST';stage='CLASP_PUSH_FAILED';scriptId=$scriptId;
        sourceHash=$sourceHash;statusBefore=$statusBefore.text;error=$push.text
      } 27
    }

    $pull = RunCapture 'clasp' @('pull')
    if ($pull.exitCode -ne 0 -or -not (Test-Path -LiteralPath $target)) {
      EmitResult @{ok=$false;status='FAILED_TEST';stage='POST_PUSH_PULL_FAILED';scriptId=$scriptId;push=$push.text;pull=$pull.text} 28
    }
    $readbackHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($readbackHash -ne $sourceHash) {
      EmitResult @{ok=$false;status='FAILED_TEST';stage='SOURCE_HASH_READBACK_MISMATCH';scriptId=$scriptId;sourceHash=$sourceHash;readbackHash=$readbackHash} 29
    }

    $functionRuns = @()
    $runtimeState = 'BOUND_SOURCE_SYNCED_FUNCTION_RUN_PENDING'
    if (-not $SkipFunctionRun) {
      $install = RunCapture 'clasp' @('run','installCentralChatWorkFactoryTriggersV1')
      $functionRuns += [ordered]@{ function='installCentralChatWorkFactoryTriggersV1'; exitCode=$install.exitCode; output=$install.text }
      if ($install.exitCode -eq 0) {
        $r1 = RunCapture 'clasp' @('run','runCentralChatWorkFactoryV1')
        $r2 = RunCapture 'clasp' @('run','runCentralChatWorkFactoryV1')
        $functionRuns += [ordered]@{ function='runCentralChatWorkFactoryV1#1'; exitCode=$r1.exitCode; output=$r1.text }
        $functionRuns += [ordered]@{ function='runCentralChatWorkFactoryV1#2'; exitCode=$r2.exitCode; output=$r2.text }
        if ($r1.exitCode -eq 0 -and $r2.exitCode -eq 0) { $runtimeState='FUNCTION_RUN_X2_COMPLETED_READBACK_REQUIRED' }
        else { $runtimeState='FUNCTION_RUN_PARTIAL_OR_FAILED' }
      } else {
        $runtimeState='CLASP_RUN_NOT_AVAILABLE_OR_EXEC_API_GATED'
      }
    }

    EmitResult @{
      ok=$true;status='SOURCE_SYNC_PASS';stage='BOUND_SOURCE_SYNCED';scriptId=$scriptId;
      deploymentVerified=$true;sourcePath=$SourcePath;sourceHash=$sourceHash;readbackHash=$readbackHash;
      beforeFileCount=$beforeFiles.Count;statusBefore=$statusBefore.text;push=$push.text;pull=$pull.text;
      runtimeState=$runtimeState;functionRuns=$functionRuns;
      approvalsUsed='EXISTING_CLASP_AUTH_ONLY';newDeploymentCreated=$false;newOAuthRequested=$false
    } 0
  } finally { Pop-Location }
} catch {
  EmitResult @{ok=$false;status='FAILED_TEST';stage='UNHANDLED';error=$_.Exception.Message;rule='STOP_NO_BLIND_RETRY'} 30
}
