param(
  [Parameter(Mandatory=$true)][string]$TargetTitle,
  [Parameter(Mandatory=$true)][string]$ExpectedSpreadsheetId,
  [Parameter(Mandatory=$true)][string]$ExpectedDeploymentId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-ClaspText([string[]]$Args, [string]$FailureCode) {
  $text = (& clasp @Args 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw $FailureCode }
  return $text
}

function Get-ClaspRoot([string]$ProjectDir) {
  $configPath = Join-Path $ProjectDir '.clasp.json'
  if (-not (Test-Path -LiteralPath $configPath)) { return [System.IO.Path]::GetFullPath($ProjectDir) }
  try { $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json } catch { throw 'CLASP_CONFIG_PARSE_FAILED' }
  if (-not $config.rootDir) { return [System.IO.Path]::GetFullPath($ProjectDir) }
  $root = [System.IO.Path]::GetFullPath((Join-Path $ProjectDir ([string]$config.rootDir)))
  if (-not (Test-Path -LiteralPath $root)) { throw 'CLASP_ROOT_DIR_MISSING' }
  return $root
}

if (-not (Get-Command clasp -ErrorAction SilentlyContinue)) { throw 'CLASP_COMMAND_NOT_FOUND_EXISTING_RUNNER_REQUIRED' }

# Existing authorization only. Never start login/create/deploy/push from this diagnostic.
$authText = (& clasp show-authorized-user --json 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
  $authText = (& clasp show-authorized-user 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE_DO_NOT_LOGIN_OR_CREATE_PROJECT' }
}

$listText = Invoke-ClaspText @('list-scripts') 'CLASP_LIST_SCRIPTS_FAILED'
$lines = @($listText -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($TargetTitle) })
if ($lines.Count -eq 0) { throw "SCRIPT_TITLE_NOT_FOUND:$TargetTitle" }
if ($lines.Count -gt 1) { throw "SCRIPT_TITLE_AMBIGUOUS:$TargetTitle" }
$match = [regex]::Match($lines[0], '[A-Za-z0-9_-]{30,}')
if (-not $match.Success) { throw 'SCRIPT_ID_PARSE_FAILED' }
$scriptId = $match.Value

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeTitle = ($TargetTitle -replace '[^A-Za-z0-9_-]','_')
$snapshotDir = Join-Path $env:TEMP "bound-appscript-readonly-$safeTitle-$stamp"
New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null
Push-Location $snapshotDir
try {
  & clasp clone-script $scriptId *> $null
  if ($LASTEXITCODE -ne 0) {
    & clasp clone $scriptId *> $null
    if ($LASTEXITCODE -ne 0) { throw 'CLASP_CLONE_EXISTING_SOURCE_FAILED' }
  }
} finally { Pop-Location }

$deploymentText = (& clasp list-deployments $scriptId 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'CLASP_LIST_DEPLOYMENTS_FAILED' }
if ($ExpectedDeploymentId -and $deploymentText -notmatch [regex]::Escape($ExpectedDeploymentId)) { throw 'EXPECTED_DEPLOYMENT_ID_NOT_FOUND_ABORT_READONLY_RECOVERY' }

$sourceRoot = Get-ClaspRoot $snapshotDir
$files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object { $_.Name -ne '.clasp.json' -and $_.Name -notmatch '^\.claspignore$' } | Sort-Object FullName)
$fileList = @($files | ForEach-Object {
  [pscustomobject]@{
    path = $_.FullName.Substring($sourceRoot.Length).TrimStart('\\','/')
    bytes = $_.Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
  }
})

$result = [ordered]@{
  ok = $true
  mode = 'READ_ONLY'
  mutationPerformed = $false
  projectTitle = $TargetTitle
  scriptId = $scriptId
  spreadsheetId = $ExpectedSpreadsheetId
  deploymentId = $ExpectedDeploymentId
  sourceRoot = $sourceRoot
  sourceFileCount = $fileList.Count
  sourceFiles = $fileList
  readOnlyTimestamp = (Get-Date).ToUniversalTime().ToString('o')
  next = 'Return JSON to central evidence. Compare source before any same-script minimum-diff repair. Do not create/login/deploy/push.'
}

$result | ConvertTo-Json -Depth 6
