param(
  [string]$CentralRootOverride = 'G:\\내 드라이브\\00_중앙에이전트',
  [string]$ExpectedExtensionId = 'gedfnhdibkfgacmkbjgpfjihacalnlpn',
  [string]$ExpectedVersion = '8.6.0'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$runtimeDir = Join-Path $CentralRootOverride 'Runtime_Readback\\CHROME'
$manifestReceipt = Join-Path $runtimeDir 'CHATGPT_IMAGE_POST_RECOVERY_INSPECT.json'
$outFile = Join-Path $runtimeDir 'CHATGPT_IMAGE_ADAPTER_BINDING_PLAN_V1.json'

function Write-Receipt([hashtable]$body) {
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $body.generatedAt = (Get-Date).ToString('o')
  $body | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outFile -Encoding UTF8
  Write-Output ($body | ConvertTo-Json -Depth 12 -Compress)
}

if (-not (Test-Path -LiteralPath $manifestReceipt)) {
  Write-Receipt @{ ok=$false; status='HOLD_MANIFEST_RECEIPT_MISSING'; manifestReceipt=$manifestReceipt; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 2
}

$receipt = Get-Content -LiteralPath $manifestReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = $receipt.manifest
if (-not $manifest) { $manifest = $receipt }

$id = [string]($manifest.extensionId)
if (-not $id) { $id = [string]($manifest.id) }
$version = [string]($manifest.version)
$sidePanel = [string]($manifest.sidePanel)
$serviceWorker = [string]($manifest.serviceWorker)
$contentScripts = @($manifest.contentScripts)
$permissions = @($manifest.permissions)
$hostPermissions = @($manifest.hostPermissions)

if ($id -ne $ExpectedExtensionId) {
  Write-Receipt @{ ok=$false; status='HOLD_EXTENSION_ID_MISMATCH'; observedId=$id; expectedId=$ExpectedExtensionId; version=$version; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 3
}
if ($version -ne $ExpectedVersion) {
  Write-Receipt @{ ok=$false; status='HOLD_EXTENSION_VERSION_MISMATCH'; observedVersion=$version; expectedVersion=$ExpectedVersion; extensionId=$id; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 4
}
if (-not $sidePanel -and -not $serviceWorker -and $contentScripts.Count -eq 0) {
  Write-Receipt @{ ok=$false; status='HOLD_MANIFEST_ENTRYPOINTS_MISSING'; extensionId=$id; version=$version; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 5
}

$plan = @{
  ok = $true
  status = 'READY_FOR_ADAPTER_BINDING'
  extensionId = $id
  version = $version
  sidePanel = $sidePanel
  serviceWorker = $serviceWorker
  contentScripts = $contentScripts
  permissions = $permissions
  hostPermissions = $hostPermissions
  executionPolicy = 'REUSE_EXISTING_EXTENSION_AND_SESSION_ONLY'
  nextRequiredEvidence = @(
    'DECLARED_ENTRYPOINT_SOURCE_READBACK',
    'MESSAGE_INTERFACE_READBACK',
    'SAFE_FIXTURE_CLAIMED_STARTED_DONE',
    'NONZERO_IMAGE',
    'EXACT_DOWNLOAD_PATH',
    'DRIVE_ASSET_READBACK',
    'RESULT_ACK_X2'
  )
  prohibitions = @(
    'NO_REINSTALL',
    'NO_NEW_OAUTH',
    'NO_PASSWORD_OR_COOKIE_READ',
    'NO_NORMAL_CHROME_RESTART',
    'NO_FLOW_SUBSTITUTION',
    'NO_GENERATE_UNTIL_INTERFACE_VERIFIED'
  )
  normalChromeTouched = $false
  extensionMutated = $false
  generateClicked = $false
  creditsSpent = $false
}
Write-Receipt $plan
exit 0
