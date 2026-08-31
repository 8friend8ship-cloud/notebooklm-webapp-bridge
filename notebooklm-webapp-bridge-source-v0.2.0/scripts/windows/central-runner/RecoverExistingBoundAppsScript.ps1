param(
  [Parameter(Mandatory=$true)][string]$TargetTitle,
  [Parameter(Mandatory=$true)][string]$ExpectedSpreadsheetId,
  [Parameter(Mandatory=$true)][string]$ExpectedDeploymentId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$allowed = @{
  'WEBAPP_TEMPLATE_05' = @{ spreadsheet='1gBuyuDyRZkRDYwl2DGj6oUWQUS-KnD1alapyTBWZXN8'; deployment='AKfycbzz247_Mwl9c6N1WxmpHAttwHQJB6RCFtaY08XlHgxysz1iEzg7HWDXa3i5oXhDS1jo' }
  'WEBAPP_TEMPLATE_06' = @{ spreadsheet='1vW1tXBLL7B5iwPS41C4tExPvHH5eALER6yctoW7crdQ'; deployment='AKfycbx5Sm8FtA7D6iQVNmdoYFON-Y5xHNdNT5a-zZWoxeORL6_nFfqOBoPwA1IYEFKHcKKjoQ' }
  'WEBAPP_TEMPLATE_07' = @{ spreadsheet='1De5GneJRng_RjYSpCyyWudZMA6fqJdgHStQAMBeh3lM'; deployment='AKfycbyzSZZqDwMAgqltkfCYQb4-aIZ4zSFlRHkh9dyN5F_Qd7hfUev6oVNqjUSsEtYE3b4VBA' }
  'WEBAPP_TEMPLATE_08' = @{ spreadsheet='1TGCmhXTz-XWIydv_tU0rPQ_CxrecRMdEflKRK4OApe4'; deployment='AKfycbxk7qhwbfJK5qL7xVQZyvHUC9CcGQSjO3WmdUa8ugzGMR0bCZNO6XynVLPHfff4kPg9' }
  'WEBAPP_TEMPLATE_09' = @{ spreadsheet='1K4Bj0PnnLD-Wka8AlNmDprvfXFnsh9mCV3QXjgdbT2s'; deployment='AKfycby5rynajzdtrWcVuwd1W8kT37DHfFYgwg6Bg7C5dlm222FxIYrl3J5l1UQSYNp1FZ8IQg' }
}

if (-not $allowed.ContainsKey($TargetTitle)) { throw 'TARGET_TITLE_NOT_ALLOWLISTED' }
$expect = $allowed[$TargetTitle]
if ($ExpectedSpreadsheetId -ne $expect.spreadsheet) { throw 'SPREADSHEET_ID_ALLOWLIST_MISMATCH' }
if ($ExpectedDeploymentId -ne $expect.deployment) { throw 'DEPLOYMENT_ID_ALLOWLIST_MISMATCH' }

$claspCmd = Get-Command clasp.cmd -ErrorAction SilentlyContinue
if (-not $claspCmd) { $claspCmd = Get-Command clasp -ErrorAction SilentlyContinue }
if (-not $claspCmd) { throw 'CLASP_COMMAND_NOT_FOUND_EXISTING_RUNNER_REQUIRED' }

# Existing authorization only. Never start login/create/deploy/push from this diagnostic.
& $claspCmd.Source show-authorized-user --json *> $null
if ($LASTEXITCODE -ne 0) {
  & $claspCmd.Source show-authorized-user *> $null
  if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE_DO_NOT_LOGIN' }
}

$listText = (& $claspCmd.Source list-scripts 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_SCRIPTS_FAILED' }
$lines = @($listText -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($TargetTitle) })
if ($lines.Count -eq 0) { throw "SCRIPT_TITLE_NOT_FOUND:$TargetTitle" }
if ($lines.Count -gt 1) { throw "SCRIPT_TITLE_AMBIGUOUS:$TargetTitle" }
$match = [regex]::Match($lines[0], '[A-Za-z0-9_-]{30,}')
if (-not $match.Success) { throw 'SCRIPT_ID_PARSE_FAILED' }
$scriptId = $match.Value

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$snapshotDir = Join-Path $env:TEMP "central-bound-readonly-$TargetTitle-$stamp"
New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null
Push-Location $snapshotDir
try {
  & $claspCmd.Source clone-script $scriptId *> $null
  if ($LASTEXITCODE -ne 0) {
    & $claspCmd.Source clone $scriptId *> $null
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED' }
  }
} finally { Pop-Location }

$deploymentText = (& $claspCmd.Source list-deployments $scriptId 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_DEPLOYMENTS_FAILED' }
if ($deploymentText -notmatch [regex]::Escape($ExpectedDeploymentId)) { throw 'EXPECTED_DEPLOYMENT_ID_NOT_FOUND_ABORT' }

$claspPath = Join-Path $snapshotDir '.clasp.json'
$sourceRoot = $snapshotDir
if (Test-Path $claspPath) {
  $cfg = Get-Content -Raw -LiteralPath $claspPath | ConvertFrom-Json
  if ($cfg.rootDir) { $sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $snapshotDir ([string]$cfg.rootDir))) }
}
if (-not (Test-Path $sourceRoot)) { throw 'SOURCE_ROOT_NOT_FOUND' }
$files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object { $_.Name -notin @('.clasp.json','.claspignore') } | Sort-Object FullName)
$fileList = @($files | ForEach-Object {
  [pscustomobject]@{
    path = $_.FullName.Substring($sourceRoot.Length).TrimStart('\\','/')
    bytes = $_.Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
  }
})

[ordered]@{
  ok = $true
  mode = 'READ_ONLY'
  mutationPerformed = $false
  projectTitle = $TargetTitle
  spreadsheetId = $ExpectedSpreadsheetId
  deploymentId = $ExpectedDeploymentId
  scriptId = $scriptId
  sourceFileCount = $fileList.Count
  sourceFiles = $fileList
  timestamp = (Get-Date).ToUniversalTime().ToString('o')
  next = 'Return receipt to central evidence. No push/deploy until source diff is reviewed.'
} | ConvertTo-Json -Depth 8
