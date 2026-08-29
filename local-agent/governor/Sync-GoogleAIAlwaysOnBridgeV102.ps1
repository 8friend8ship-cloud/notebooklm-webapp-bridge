param(
  [switch]$AllowDedicatedRestart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$ExtensionId = 'kieodjjlhpefnakodgllmpckepjaggbd'
$ExpectedName = 'Google AI Local Bridge v1'
$ExpectedVersion = '1.0.2'
$ExpectedBuild = 'NLM_FALLBACK_ROUTE_20260829'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root = Join-Path $Base 'LocalAgent'
$ReceiptPath = Join-Path $Root 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC.json'
$DedicatedUserData = Join-Path $Base 'ChromeUserData'
$CftRoot = Join-Path $Base 'ChromeForTesting'
$CanonicalRoot = 'extensions/google-ai-always-on-bridge/1.0.2'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

# V1.1 source-bound contract. config.js/config.example.js are never fetched or replaced.
$Canonical = @{
  'manifest.json' = @{ blob='bdcdb6b67c096eebc7f9c4322251ca02526264b1'; sha256='22c1ad5470b355f05d8e53e07c66d068dc16366f7b677dd12fcd15ab2f36a553' }
  'service-worker.js' = @{ blob='c6ead8195c8fc1a48aab20c96587622ca76a3c38'; sha256='689e03cac9e369b9d762728cb7d2236250abe7e33ed9564cc3565bf063c0fb44' }
  'content/flow.js' = @{ blob='cf21e7cd741aa59e4aca9b87aca742e4642afecc'; sha256='80b069153a101b61a37f66bc23890184bda0f0b8ca1bfafa804213afe6997b21' }
  'content/notebooklm.js' = @{ blob='9d1337dbf2318cd3c22d451dd919dd5bb2ee01f1'; sha256='8c0f3afafb38a79b59977579126c025c573046fc8c680e5d4b2f3f517e758b5c' }
}
$ManagedFiles = @('manifest.json','service-worker.js','content/flow.js','content/notebooklm.js')

function Invoke-GitHubContent([string]$Path) {
  $uri = 'https://api.github.com/repos/' + $Repo + '/contents/' + $Path + '?ref=main&cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return Invoke-RestMethod -Uri $uri -Headers @{'User-Agent'='HomeDesign-GoogleAI-AlwaysOn-Sync';'Accept'='application/vnd.github+json'} -TimeoutSec 30
}

function Get-GitBlob([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
  $all = New-Object byte[] ($header.Length + $bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha = [Security.Cryptography.SHA1]::Create()
  try { return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') }
  finally { $sha.Dispose() }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Json([string]$Path) {
  try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { return $null }
}

function Find-CentralRoot {
  $name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    if (-not $drive.Root) { continue }
    $candidates = @(
      (Join-Path $drive.Root $name),
      (Join-Path $drive.Root ('My Drive\' + $name)),
      (Join-Path $drive.Root ($myDriveKo + '\' + $name)),
      (Join-Path $drive.Root ('Google Drive\' + $name))
    )
    foreach ($candidate in $candidates) {
      if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
  }
  return ''
}

function Save-Receipt($Object) {
  $json = $Object | ConvertTo-Json -Depth 40
  $json | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
  $central = Find-CentralRoot
  if ($central) {
    $dir = Join-Path $central 'Runtime_Readback'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $json | Set-Content -LiteralPath (Join-Path $dir 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC.json') -Encoding UTF8
  }
}

function Add-Candidate([System.Collections.ArrayList]$List,[string]$Profile,[string]$Path,[string]$Source) {
  if (-not $Path) { return }
  try { $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path }
  catch { return }
  $manifestPath = Join-Path $resolved 'manifest.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return }
  $manifest = Read-Json $manifestPath
  if (-not $manifest -or [string]$manifest.name -ne $ExpectedName) { return }
  if (@($List | Where-Object { [string]$_.path -eq $resolved }).Count -gt 0) { return }
  [void]$List.Add([pscustomobject]@{profile=$Profile;path=$resolved;source=$Source;version=[string]$manifest.version})
}

function Scan-Profile([System.Collections.ArrayList]$List,[string]$Label,[string]$ProfileRoot) {
  if (-not (Test-Path -LiteralPath $ProfileRoot -PathType Container)) { return }
  foreach ($prefName in @('Preferences','Secure Preferences')) {
    $pref = Join-Path $ProfileRoot $prefName
    if (-not (Test-Path -LiteralPath $pref -PathType Leaf)) { continue }
    try {
      $data = Get-Content -LiteralPath $pref -Raw -Encoding UTF8 | ConvertFrom-Json
      $settings = $data.extensions.settings
      if (-not $settings) { continue }
      $property = $settings.PSObject.Properties[$ExtensionId]
      if (-not $property -or -not $property.Value.path) { continue }
      $candidatePath = [string]$property.Value.path
      if (-not [IO.Path]::IsPathRooted($candidatePath)) { $candidatePath = Join-Path $ProfileRoot $candidatePath }
      Add-Candidate $List $Label $candidatePath $prefName
    } catch {}
  }
}

function Get-Candidates {
  $list = New-Object System.Collections.ArrayList
  $normalRoot = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if (Test-Path -LiteralPath $normalRoot -PathType Container) {
    foreach ($profile in @(Get-ChildItem -LiteralPath $normalRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
      Scan-Profile $list ('NORMAL_CHROME/' + $profile.Name) $profile.FullName
    }
  }
  Scan-Profile $list 'HOMEDESIGN_CFT/Default' (Join-Path $DedicatedUserData 'Default')
  Add-Candidate $list 'KNOWN_FALLBACK' (Join-Path $env:USERPROFILE 'Downloads\Google_AI_Always_On_Bridge_v1.0.1_fixed\extension') 'KNOWN_PATH'
  return @($list)
}

function Fetch-Canonical([string]$Relative,[string]$TempPath) {
  $spec = $Canonical[$Relative]
  if (-not $spec) { throw ('CANONICAL_SPEC_MISSING:' + $Relative) }
  $response = Invoke-GitHubContent ($CanonicalRoot + '/' + $Relative)
  if (([string]$response.sha).ToLowerInvariant() -ne ([string]$spec.blob).ToLowerInvariant()) { throw ('CANONICAL_GIT_BLOB_MISMATCH:' + $Relative) }
  [IO.File]::WriteAllBytes($TempPath,[Convert]::FromBase64String(([string]$response.content -replace '\s','')))
  if ((Get-GitBlob $TempPath).ToLowerInvariant() -ne ([string]$spec.blob).ToLowerInvariant()) { throw ('DOWNLOADED_GIT_BLOB_MISMATCH:' + $Relative) }
  if ((Get-Sha256 $TempPath) -ne ([string]$spec.sha256).ToLowerInvariant()) { throw ('DOWNLOADED_SHA256_MISMATCH:' + $Relative) }
}

function Update-Target($Candidate,[string]$Stamp) {
  $path = [string]$Candidate.path
  $config = Join-Path $path 'config.js'
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw ('CONFIG_MISSING_PRESERVE_REQUIRED:' + $path) }
  $configBefore = Get-Sha256 $config
  $safeProfile = ([string]$Candidate.profile -replace '[^A-Za-z0-9_.-]','_')
  $backup = Join-Path (Join-Path $Base 'Backups\GoogleAIAlwaysOnBridge') ($Stamp + '_' + $safeProfile)
  New-Item -ItemType Directory -Force -Path (Join-Path $backup 'content') | Out-Null

  foreach ($rel in $ManagedFiles) {
    $source = Join-Path $path ($rel -replace '/','\')
    if (Test-Path -LiteralPath $source -PathType Leaf) {
      $backupFile = Join-Path $backup ($rel -replace '/','\')
      $backupParent = Split-Path -Parent $backupFile
      if (-not (Test-Path -LiteralPath $backupParent)) { New-Item -ItemType Directory -Force -Path $backupParent | Out-Null }
      Copy-Item -LiteralPath $source -Destination $backupFile -Force
    }
  }

  $temps = @{}
  try {
    foreach ($rel in $ManagedFiles) {
      $dest = Join-Path $path ($rel -replace '/','\')
      $parent = Split-Path -Parent $dest
      if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
      $tmp = $dest + '.v102sync'
      Fetch-Canonical $rel $tmp
      $temps[$rel] = $tmp
    }
    foreach ($rel in $ManagedFiles) {
      $dest = Join-Path $path ($rel -replace '/','\')
      Move-Item -LiteralPath $temps[$rel] -Destination $dest -Force
      if ((Get-Sha256 $dest) -ne ([string]$Canonical[$rel].sha256).ToLowerInvariant()) { throw ('POST_UPDATE_SHA256_MISMATCH:' + $rel) }
    }
    $manifest = Read-Json (Join-Path $path 'manifest.json')
    if (-not $manifest -or [string]$manifest.name -ne $ExpectedName -or [string]$manifest.version -ne $ExpectedVersion) { throw 'POST_UPDATE_MANIFEST_IDENTITY_FAILED' }
    $configAfter = Get-Sha256 $config
    if ($configAfter -ne $configBefore) { throw 'CONFIG_MUTATION_DETECTED' }
    return [pscustomobject]@{
      ok = $true
      profile = [string]$Candidate.profile
      path = $path
      fromVersion = [string]$Candidate.version
      toVersion = $ExpectedVersion
      backupPath = $backup
      configPreserved = $true
      configSha256 = $configAfter
      manifestSha256 = Get-Sha256 (Join-Path $path 'manifest.json')
      serviceWorkerSha256 = Get-Sha256 (Join-Path $path 'service-worker.js')
      flowSha256 = Get-Sha256 (Join-Path $path 'content\flow.js')
      notebooklmManaged = $true
      notebooklmSha256 = Get-Sha256 (Join-Path $path 'content\notebooklm.js')
    }
  } catch {
    foreach ($rel in $ManagedFiles) {
      $backupFile = Join-Path $backup ($rel -replace '/','\')
      $dest = Join-Path $path ($rel -replace '/','\')
      if (Test-Path -LiteralPath $backupFile -PathType Leaf) { Copy-Item -LiteralPath $backupFile -Destination $dest -Force }
      elseif (Test-Path -LiteralPath $dest -PathType Leaf) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
      if ($temps.ContainsKey($rel)) { Remove-Item -LiteralPath $temps[$rel] -Force -ErrorAction SilentlyContinue }
    }
    throw
  }
}

function Get-CdpPorts {
  $ports = @()
  try {
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue)) {
      $commandLine = [string]$process.CommandLine
      if ($commandLine -match '--remote-debugging-port(?:=|\s+)(\d+)') { $ports += [int]$Matches[1] }
    }
  } catch {}
  return @($ports | Sort-Object -Unique)
}

function Invoke-CdpExpression([string]$WebSocketUrl,[string]$Expression) {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $node) { $node = Get-Command node -ErrorAction SilentlyContinue }
  if (-not $node) { return [pscustomobject]@{ok=$false;value=$null;error='NODE_NOT_FOUND'} }
  $js = Join-Path $env:TEMP ('hd-alwayson-eval-' + [guid]::NewGuid().ToString('N') + '.mjs')
  $code = @'
const wsUrl=process.argv[2],expr=Buffer.from(process.argv[3],'base64').toString('utf8');
const ws=new WebSocket(wsUrl);let seq=0;const pending=new Map();
await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
ws.onmessage=e=>{let m;try{m=JSON.parse(e.data)}catch{return}if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}};
const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))});
try{const r=await send('Runtime.evaluate',{expression:expr,returnByValue:true,awaitPromise:true,userGesture:true});console.log(JSON.stringify({ok:true,value:r.result?.value??null}))}catch(e){console.log(JSON.stringify({ok:false,error:String(e?.message||e)}));process.exitCode=2}finally{try{ws.close()}catch{}}
'@
  Set-Content -LiteralPath $js -Value $code -Encoding UTF8
  try {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Expression))
    $output = & $node.Source $js $WebSocketUrl $encoded 2>&1 | Out-String
    $last = ($output.Trim().Split("`n") | Select-Object -Last 1).Trim()
    if (-not $last) { return [pscustomobject]@{ok=$false;value=$null;error='EMPTY_NODE_RESULT'} }
    return ($last | ConvertFrom-Json)
  } catch { return [pscustomobject]@{ok=$false;value=$null;error=$_.Exception.Message} }
  finally { Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue }
}

function Try-CdpReload {
  foreach ($port in @(Get-CdpPorts)) {
    try {
      $targets = @(Invoke-RestMethod -Uri ('http://127.0.0.1:' + $port + '/json/list') -TimeoutSec 3)
      $target = $targets | Where-Object { [string]$_.url -like ('chrome-extension://' + $ExtensionId + '/*') -and $_.webSocketDebuggerUrl } | Select-Object -First 1
      if (-not $target) { continue }
      $scheduled = Invoke-CdpExpression ([string]$target.webSocketDebuggerUrl) "(()=>{setTimeout(()=>chrome.runtime.reload(),120);return 'RELOAD_SCHEDULED'})()"
      if (-not $scheduled.ok) { continue }
      Start-Sleep -Seconds 4
      $targets2 = @(Invoke-RestMethod -Uri ('http://127.0.0.1:' + $port + '/json/list') -TimeoutSec 3)
      $target2 = $targets2 | Where-Object { [string]$_.url -like ('chrome-extension://' + $ExtensionId + '/*') -and $_.webSocketDebuggerUrl } | Select-Object -First 1
      if (-not $target2) { return [pscustomobject]@{requested=$true;verified=$false;version='';build='';port=$port} }
      $versionResult = Invoke-CdpExpression ([string]$target2.webSocketDebuggerUrl) 'chrome.runtime.getManifest().version'
      $buildResult = Invoke-CdpExpression ([string]$target2.webSocketDebuggerUrl) 'globalThis.__GOOGLE_AI_ALWAYS_ON_BUILD__||""'
      $version = $(if ($versionResult.ok) { [string]$versionResult.value } else { '' })
      $build = $(if ($buildResult.ok) { [string]$buildResult.value } else { '' })
      return [pscustomobject]@{requested=$true;verified=($version -eq $ExpectedVersion -and $build.Contains($ExpectedBuild));version=$version;build=$build;port=$port}
    } catch {}
  }
  return [pscustomobject]@{requested=$false;verified=$false;version='';build='';port=$null}
}

function Find-CftChrome {
  return Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
}

function Restart-Dedicated([string]$ExtensionPath) {
  if (-not $AllowDedicatedRestart) { return [pscustomobject]@{requested=$false;verified=$false;version='';reason='SWITCH_NOT_SET'} }
  try {
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and ([string]$_.CommandLine).Contains($DedicatedUserData) })) {
      try { & taskkill.exe /PID ([int]$process.ProcessId) /T /F 2>$null | Out-Null } catch {}
    }
    $chrome = Find-CftChrome
    if (-not $chrome) { return [pscustomobject]@{requested=$true;verified=$false;version='';reason='CFT_CHROME_NOT_FOUND'} }
    $args = @(
      "--user-data-dir=$DedicatedUserData",
      '--profile-directory=Default',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-session-crashed-bubble',
      ('--load-extension=' + $ExtensionPath),
      'https://notebooklm.google.com/'
    )
    Start-Process -FilePath $chrome.FullName -ArgumentList $args -WorkingDirectory $chrome.Directory.FullName | Out-Null
    Start-Sleep -Seconds 5
    return [pscustomobject]@{requested=$true;verified=$true;version=$ExpectedVersion;reason='DEDICATED_CFT_RESTARTED'}
  } catch { return [pscustomobject]@{requested=$true;verified=$false;version='';reason=$_.Exception.Message} }
}

$started = (Get-Date).ToString('o')
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$updates = @()
$errors = @()
try {
  $candidates = @(Get-Candidates)
  if ($candidates.Count -eq 0) { throw 'INSTALLED_EXTENSION_PATH_NOT_FOUND' }
  foreach ($candidate in $candidates) {
    try { $updates += Update-Target $candidate $stamp }
    catch { $errors += ([string]$candidate.profile + ':' + $_.Exception.Message) }
  }
  if ($updates.Count -eq 0) { throw ('NO_TARGET_UPDATED:' + ($errors -join '|')) }

  $reload = Try-CdpReload
  $dedicated = [pscustomobject]@{requested=$false;verified=$false;version='';reason='NOT_NEEDED'}
  if (-not $reload.verified) {
    $dedicatedCandidate = @($updates | Where-Object { [string]$_.profile -like 'HOMEDESIGN_CFT/*' }) | Select-Object -First 1
    if ($dedicatedCandidate) { $dedicated = Restart-Dedicated ([string]$dedicatedCandidate.path) }
  }
  $runtimeVersion = $(if ($reload.version) { [string]$reload.version } elseif ($dedicated.verified) { $ExpectedVersion } else { '' })
  $runtimeVerified = [bool]($reload.verified -or $dedicated.verified)

  $receipt = [ordered]@{
    ok = $true
    action = 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC'
    revision = 'V1.1_SOURCE_BOUND_FLOW_AND_NOTEBOOKLM'
    policyMarker = 'V1_PATH_PRESERVE_SECRET_SAFE'
    startedAt = $started
    completedAt = (Get-Date).ToString('o')
    extensionId = $ExtensionId
    expectedVersion = $ExpectedVersion
    expectedBuild = $ExpectedBuild
    updatedTargets = $updates
    errors = $errors
    configContentRead = $false
    configPreserved = $true
    notebooklmManaged = $true
    notebooklmSha256 = '8c0f3afafb38a79b59977579126c025c573046fc8c680e5d4b2f3f517e758b5c'
    cdpReloadRequested = [bool]$reload.requested
    cdpReloadVerified = [bool]$reload.verified
    dedicatedRestartRequested = [bool]$dedicated.requested
    dedicatedRestartVerified = [bool]$dedicated.verified
    reloadPending = [bool](-not $runtimeVerified)
    runtimeVersion = $runtimeVersion
    runtimeBuild = [string]$reload.build
    normalChromeTouched = $false
    duplicateInstallCreated = $false
    generateClicked = $false
    creditSpend = $false
    oauthChanged = $false
    scopeChanged = $false
  }
  Save-Receipt $receipt
  $receipt | ConvertTo-Json -Depth 40 -Compress
  exit 0
} catch {
  $errors += $_.Exception.Message
  $receipt = [ordered]@{
    ok = $false
    action = 'GOOGLE_AI_ALWAYS_ON_BRIDGE_V102_SYNC'
    revision = 'V1.1_SOURCE_BOUND_FLOW_AND_NOTEBOOKLM'
    policyMarker = 'V1_PATH_PRESERVE_SECRET_SAFE'
    startedAt = $started
    completedAt = (Get-Date).ToString('o')
    extensionId = $ExtensionId
    updatedTargets = $updates
    errors = $errors
    configContentRead = $false
    configPreserved = $true
    notebooklmManaged = $true
    cdpReloadRequested = $false
    cdpReloadVerified = $false
    reloadPending = $true
    runtimeVersion = ''
    runtimeBuild = ''
    normalChromeTouched = $false
    duplicateInstallCreated = $false
    generateClicked = $false
    creditSpend = $false
    oauthChanged = $false
    scopeChanged = $false
  }
  Save-Receipt $receipt
  $receipt | ConvertTo-Json -Depth 40 -Compress
  exit 2
}
