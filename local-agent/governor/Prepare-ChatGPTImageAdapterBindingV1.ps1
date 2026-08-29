param(
  [string]$CentralRootOverride = 'G:\내 드라이브\00_중앙에이전트',
  [string]$ExpectedExtensionId = 'gedfnhdibkfgacmkbjgpfjihacalnlpn',
  [string]$ExpectedVersion = '8.6.0'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$runtimeDir = Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
$manifestReceipt = Join-Path $runtimeDir 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json'
$outFile = Join-Path $runtimeDir 'CHATGPT_IMAGE_ADAPTER_BINDING_PLAN_V1.json'

function Write-Receipt([hashtable]$body) {
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $body.generatedAt = (Get-Date).ToString('o')
  $body | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outFile -Encoding UTF8
  Write-Output ($body | ConvertTo-Json -Depth 20 -Compress)
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
  referencedResources = $referencedResources
  manifestReceipt = $manifestReceipt
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
