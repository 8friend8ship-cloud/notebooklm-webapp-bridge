param(
  [string]$CentralRootOverride = 'G:\내 드라이브\00_중앙에이전트',
  [string]$ExpectedExtensionId = 'gedfnhdibkfgacmkbjgpfjihacalnlpn',
  [string]$ExpectedVersion = '8.6.0'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$runtimeDir = Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
$manifestReceipt = Join-Path $runtimeDir 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json'
$contractReceipt = Join-Path $runtimeDir 'CHATGPT_IMAGE_ENTRYPOINT_CONTRACT_V1.json'
$outFile = Join-Path $runtimeDir 'CHATGPT_IMAGE_ADAPTER_BINDING_PLAN_V1.json'

function Write-Receipt([hashtable]$body) {
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $body.generatedAt = (Get-Date).ToString('o')
  $body | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outFile -Encoding UTF8
  Write-Output ($body | ConvertTo-Json -Depth 30 -Compress)
}

if (-not (Test-Path -LiteralPath $manifestReceipt -PathType Leaf)) {
  Write-Receipt @{ ok=$false; status='HOLD_MANIFEST_RECEIPT_MISSING'; manifestReceipt=$manifestReceipt; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 2
}

$manifest = Get-Content -LiteralPath $manifestReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
$id = [string]$manifest.extensionId
$version = [string]$manifest.extensionVersion
$sidePanel = [string]$manifest.sidePanelDefaultPath
$serviceWorker = [string]$manifest.serviceWorker
$contentScripts = @($manifest.contentScripts)
$permissions = @($manifest.permissions)
$hostPermissions = @($manifest.hostPermissions)
$referencedResources = @($manifest.referencedResources)

if (-not $manifest.ok) {
  Write-Receipt @{ ok=$false; status='HOLD_MANIFEST_INSPECT_NOT_OK'; manifestReceipt=$manifestReceipt; extensionId=$id; version=$version; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 3
}
if ($id -ne $ExpectedExtensionId) {
  Write-Receipt @{ ok=$false; status='HOLD_EXTENSION_ID_MISMATCH'; observedId=$id; expectedId=$ExpectedExtensionId; version=$version; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 4
}
if ($version -ne $ExpectedVersion) {
  Write-Receipt @{ ok=$false; status='HOLD_EXTENSION_VERSION_MISMATCH'; observedVersion=$version; expectedVersion=$ExpectedVersion; extensionId=$id; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 5
}
if (-not $sidePanel -and -not $serviceWorker -and $contentScripts.Count -eq 0) {
  Write-Receipt @{ ok=$false; status='HOLD_MANIFEST_ENTRYPOINTS_MISSING'; extensionId=$id; version=$version; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 6
}
$missingResources=@($referencedResources | Where-Object { -not $_.exists })
if($missingResources.Count -gt 0){
  Write-Receipt @{ ok=$false; status='HOLD_DECLARED_RESOURCE_MISSING'; extensionId=$id; version=$version; missingResources=$missingResources; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 7
}
if (-not (Test-Path -LiteralPath $contractReceipt -PathType Leaf)) {
  Write-Receipt @{ ok=$false; status='HOLD_ENTRYPOINT_CONTRACT_MISSING'; extensionId=$id; version=$version; contractReceipt=$contractReceipt; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 8
}
$contract = Get-Content -LiteralPath $contractReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $contract.ok -or [string]$contract.status -ne 'CONTRACT_CANDIDATES_FOUND') {
  Write-Receipt @{ ok=$false; status='HOLD_ENTRYPOINT_CONTRACT_NOT_READY'; extensionId=$id; version=$version; contractStatus=[string]$contract.status; normalChromeTouched=$false; extensionMutated=$false; generateClicked=$false; creditsSpent=$false }
  exit 9
}

$plan = @{
  ok = $true
  status = 'READY_FOR_EXACT_INTERFACE_BINDING'
  extensionId = $id
  version = $version
  sidePanel = $sidePanel
  serviceWorker = $serviceWorker
  contentScripts = $contentScripts
  permissions = $permissions
  hostPermissions = $hostPermissions
  referencedResources = $referencedResources
  manifestReceipt = $manifestReceipt
  contractReceipt = $contractReceipt
  contract = $contract
  executionPolicy = 'REUSE_EXISTING_EXTENSION_AND_CHATGPT_SESSION_ONLY'
  storagePolicy = 'CHROME_ORIGINAL_DOWNLOAD_DIRECT_TO_GOOGLE_DRIVE_DESKTOP_SYNCED_PROJECT_FOLDER'
  pythonPolicy = 'NOT_IN_DEFAULT_TRANSFER_PATH_EXCEPTION_VALIDATION_ONLY'
  pythonConditionalUses = @('ZERO_BYTE','MIME_EXTENSION','HASH','DUPLICATE','EXCEPTION_RECOVERY')
  nextRequiredEvidence = @(
    'EXACT_MESSAGE_OR_STORAGE_INTERFACE_CONFIRMATION',
    'AUTOMATIC_QUEUE_CLAIM',
    'AUTOMATIC_CHATGPT_SUBMIT',
    'GENERATION_COMPLETE_DETECTED',
    'ORIGINAL_IMAGE_DIRECT_DOWNLOAD_TO_DRIVE_SYNC_FOLDER',
    'DRIVE_FILE_ID_AND_NONZERO_READBACK',
    'QUEENS_ASSET_REGISTRATION',
    'RESULT_ACK_X2'
  )
  prohibitions = @(
    'NO_REINSTALL',
    'NO_NEW_OAUTH',
    'NO_PASSWORD_OR_COOKIE_READ',
    'NO_NORMAL_CHROME_RESTART',
    'NO_PARALLEL_DUPLICATE_GENERATION',
    'NO_PYTHON_COPY_UPLOAD_BY_DEFAULT',
    'NO_GENERATE_UNTIL_EXACT_INTERFACE_VERIFIED'
  )
  normalChromeTouched = $false
  extensionMutated = $false
  generateClicked = $false
  creditsSpent = $false
}
Write-Receipt $plan
exit 0
