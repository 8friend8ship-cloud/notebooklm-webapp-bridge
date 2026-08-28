param(
  [switch]$SmokeOnly,
  [switch]$FlowBridgeConnectSmoke,
  [string]$FlowSmokeTaskId = '',
  [int]$FlowDebugPort = 9224,
  [string]$ManagerRef = 'main',
  [string]$LocalInboxRoot = 'C:\HomeDesignAutomationV7\CaptureBridge\INBOX',
  [string]$CentralRootOverride = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$ManagerExpected = '76a9718b30d1432829ea7c0f2e6af95ea6942ab8'
$FlowHelperExpected = '0941c69d525d37de3bf98796f0a77a73b0a49a1e'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent\capture'
$Manager = Join-Path $InstallRoot 'ManageChromeExtensionArtifacts.ps1'
$Wrapper = Join-Path $InstallRoot 'Reconcile-AllManagedChromeArtifacts.ps1'
$TaskName = 'HomeDesign-CaptureBridge-ManagedChrome-Reconcile'
$Services = @('NotebookLM','Flow','AIStudio','GoogleAI','FrontQA','SketchUp')

function GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
  $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create()
  try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

# Central-agent direct Flow bridge control reuses this already Host-allowlisted setup script.
# It downloads an integrity-pinned helper, runs only dedicated ChromeForTesting, never clicks Generate,
# writes result+ACK to central Drive, restores the NotebookLM dedicated Chrome, and exits with helper status.
if ($FlowBridgeConnectSmoke) {
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $helper = Join-Path $InstallRoot 'RunFlowBridgeConnectSmoke.ps1'
  $tmpHelper = $helper + '.download'
  $helperRaw = 'https://raw.githubusercontent.com/' + $Repo + '/refs/heads/main/local-agent/governor/RunFlowBridgeConnectSmoke.ps1?hdcb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $helperRaw -OutFile $tmpHelper -TimeoutSec 20
  $helperActual = (GitBlobSha1 $tmpHelper).ToLowerInvariant()
  if ($helperActual -ne $FlowHelperExpected) {
    Remove-Item -LiteralPath $tmpHelper -Force -ErrorAction SilentlyContinue
    throw ('FLOW_HELPER_SHA_MISMATCH:actual={0}:expected={1}' -f $helperActual,$FlowHelperExpected)
  }
  Move-Item -LiteralPath $tmpHelper -Destination $helper -Force
  $helperArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper,'-DebugPort',[string]$FlowDebugPort)
  if ($FlowSmokeTaskId) { $helperArgs += @('-TaskId',$FlowSmokeTaskId) }
  if ($CentralRootOverride) { $helperArgs += @('-CentralRootOverride',$CentralRootOverride) }
  $helperOut = & powershell.exe @helperArgs 2>&1
  $helperRc = $LASTEXITCODE
  $helperOut | ForEach-Object { Write-Output $_ }
  exit $helperRc
}

function Find-CentralRoot {
  if ($CentralRootOverride) {
    if (Test-Path -LiteralPath $CentralRootOverride -PathType Container) { return (Resolve-Path -LiteralPath $CentralRootOverride).Path }
    throw ('CENTRAL_ROOT_OVERRIDE_NOT_FOUND:{0}' -f $CentralRootOverride)
  }
  $target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    $root = [string]$drive.Root
    if (-not $root) { continue }
    foreach ($candidate in @(
      (Join-Path $root $target),
      (Join-Path $root ('My Drive\' + $target)),
      (Join-Path $root ($myDriveKo + '\' + $target)),
      (Join-Path $root ('Google Drive\' + $target))
    )) {
      if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
  }
  throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'
}

New-Item -ItemType Directory -Force -Path $InstallRoot,$LocalInboxRoot | Out-Null
$CentralRoot = Find-CentralRoot
foreach ($service in $Services) {
  New-Item -ItemType Directory -Force -Path (Join-Path $LocalInboxRoot $service) | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path $CentralRoot 'CaptureBridge\INBOX') $service) | Out-Null
}

$raw = 'https://raw.githubusercontent.com/' + $Repo + '/refs/heads/' + $ManagerRef + '/local-agent/capture/ManageChromeExtensionArtifacts.ps1?hdcb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$tmp = $Manager + '.download'
Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $tmp -TimeoutSec 20
$actual = (GitBlobSha1 $tmp).ToLowerInvariant()
if ($actual -ne $ManagerExpected) {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  throw ('CAPTURE_MANAGER_SHA_MISMATCH:actual={0}:expected={1}' -f $actual,$ManagerExpected)
}
Move-Item -LiteralPath $tmp -Destination $Manager -Force

$escapedManager = $Manager.Replace("'","''")
$escapedLocal = $LocalInboxRoot.Replace("'","''")
$wrapperBody = @"
`$ErrorActionPreference='Continue'
`$Manager='$escapedManager'
`$LocalInboxRoot='$escapedLocal'
`$known=@('NotebookLM','Flow','AIStudio','GoogleAI','FrontQA','SketchUp')
`$discovered=@(Get-ChildItem -LiteralPath `$LocalInboxRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { `$_.Name })
`$services=@(`$known + `$discovered | Where-Object { `$_ -match '^[A-Za-z0-9_.-]{1,64}$' } | Sort-Object -Unique)
foreach(`$service in `$services){
  try { & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `$Manager -ServiceKey `$service -ReconcileOnly -LocalInboxRoot `$LocalInboxRoot | Out-Null } catch {}
}
"@
Set-Content -LiteralPath $Wrapper -Value $wrapperBody -Encoding UTF8

$scheduled = $false
if (-not $SmokeOnly) {
  $tr = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Wrapper + '"'
  & schtasks.exe /Create /F /SC MINUTE /MO 5 /TN $TaskName /TR $tr | Out-Null
  if ($LASTEXITCODE -ne 0) { throw ('CAPTURE_SCHEDULED_TASK_CREATE_FAILED:{0}' -f $LASTEXITCODE) }
  $scheduled = $true
}

$smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ('CaptureBridgeManagedChromeSmoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
$smoke = @()
foreach ($service in $Services) {
  if ($service -eq 'Flow') {
    $src = Join-Path $smokeRoot 'flow-smoke.png'
    [IO.File]::WriteAllBytes($src,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZK1sAAAAASUVORK5CYII='))
  } else {
    $src = Join-Path $smokeRoot (($service.ToLowerInvariant()) + '-smoke.txt')
    Set-Content -LiteralPath $src -Value ('MANAGED_CHROME_CAPTURE_SMOKE ' + $service + ' ' + (Get-Date).ToString('o')) -Encoding UTF8
  }
  $args = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Manager,'-ServiceKey',$service,'-SourcePath',$src,'-TaskId',('SETUP_SMOKE_' + $service),'-LocalInboxRoot',$LocalInboxRoot)
  if ($CentralRootOverride) { $args += @('-CentralRootOverride',$CentralRoot) }
  $rawResult = & powershell.exe @args
  if ($LASTEXITCODE -ne 0) { throw ('CAPTURE_SMOKE_FAILED:{0}' -f $service) }
  $parsed = ($rawResult | Select-Object -Last 1) | ConvertFrom-Json
  if (-not [bool]$parsed.ok -or [int]$parsed.processedCount -lt 1 -or [bool]$parsed.genericDownloadsScan) {
    throw ('CAPTURE_SMOKE_CONTRACT_FAILED:{0}' -f $service)
  }
  $first = @($parsed.results)[0]
  if (-not [bool]$first.originalPreserved -or -not (Test-Path -LiteralPath ([string]$first.drivePath) -PathType Leaf)) {
    throw ('CAPTURE_SMOKE_COPY_VERIFY_FAILED:{0}' -f $service)
  }
  $smoke += [ordered]@{service=$service;ok=$true;drivePath=[string]$first.drivePath;bytes=[int64]$first.bytes;sha256=[string]$first.sha256}
}

# Smoke one future/unregistered adapter key to prove that new managed extensions do not require a manager-code edit.
$futureService = 'FutureManagedExtension'
$futureSrc = Join-Path $smokeRoot 'future-managed-smoke.txt'
Set-Content -LiteralPath $futureSrc -Value ('MANAGED_CHROME_CAPTURE_SMOKE ' + $futureService + ' ' + (Get-Date).ToString('o')) -Encoding UTF8
$futureArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Manager,'-ServiceKey',$futureService,'-SourcePath',$futureSrc,'-TaskId','SETUP_SMOKE_FUTURE_MANAGED','-LocalInboxRoot',$LocalInboxRoot)
if ($CentralRootOverride) { $futureArgs += @('-CentralRootOverride',$CentralRoot) }
$futureRaw = & powershell.exe @futureArgs
if ($LASTEXITCODE -ne 0) { throw 'CAPTURE_SMOKE_FAILED:FUTURE_MANAGED' }
$futureParsed = ($futureRaw | Select-Object -Last 1) | ConvertFrom-Json
if (-not [bool]$futureParsed.ok -or [int]$futureParsed.processedCount -lt 1 -or [bool]$futureParsed.knownProfile -or [bool]$futureParsed.genericDownloadsScan) {
  throw 'CAPTURE_SMOKE_CONTRACT_FAILED:FUTURE_MANAGED'
}
$futureFirst = @($futureParsed.results)[0]
$smoke += [ordered]@{service=$futureService;ok=$true;drivePath=[string]$futureFirst.drivePath;bytes=[int64]$futureFirst.bytes;sha256=[string]$futureFirst.sha256;knownProfile=$false}

$result = [ordered]@{
  ok = $true
  action = 'SETUP_MANAGED_CHROME_CAPTUREBRIDGE'
  services = $Services
  futureManagedAdapter = $futureService
  manager = $Manager
  managerRef = $ManagerRef
  managerSha = $actual
  localInboxRoot = $LocalInboxRoot
  centralRoot = $CentralRoot
  scheduledTask = $TaskName
  scheduled = $scheduled
  smokeOnly = [bool]$SmokeOnly
  dynamicInboxDiscovery = $true
  genericDownloadsSync = $false
  copyOnly = $true
  smoke = $smoke
  at = (Get-Date).ToString('o')
}
$result | ConvertTo-Json -Depth 10 -Compress
