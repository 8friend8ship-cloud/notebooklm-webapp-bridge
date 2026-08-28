param(
  [ValidateSet('Inventory','Stage','Rollback','LaunchDedicated')]
  [string]$Mode='Inventory',
  [string]$SourceZip='',
  [string]$SourceDir='',
  [string]$ManifestSubPath='',
  [string]$ExpectedExtensionId='',
  [switch]$Apply,
  [switch]$RestartDedicatedChrome
)

$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='MANAGED_CHROME_EXTENSION_PACKAGE_V1_20260828'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'ManagedExtensions'
$StatePath=Join-Path $Root 'manager-state.json'
$LogRoot=Join-Path $Root 'Logs'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$GovernorScript=Join-Path $Base 'Governor\ChromeExtensionGovernor.ps1'
if(-not(Test-Path -LiteralPath $GovernorScript)){
  $repoGovernor=Join-Path $PSScriptRoot 'ChromeExtensionGovernor.ps1'
  if(Test-Path -LiteralPath $repoGovernor){$GovernorScript=$repoGovernor}
}
New-Item -ItemType Directory -Force -Path $Root,$LogRoot,$DedicatedUserData|Out-Null

function Write-Log([string]$Message){
  $p=Join-Path $LogRoot ('managed_extension_'+(Get-Date -Format 'yyyyMMdd')+'.log')
  Add-Content -LiteralPath $p -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8
}
function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Save-State($State){
  $State.updatedAt=(Get-Date).ToUniversalTime().ToString('o')
  $State|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $StatePath -Encoding UTF8
}
function New-State{
  [pscustomobject]@{
    schema='MANAGED_CHROME_EXTENSION_STATE_V1'
    version=$Version
    updatedAt=''
    extensions=@()
    history=@()
    policy=[pscustomobject]@{
      noDelete=$true
      noCredentialRead=$true
      noNewOAuth=$true
      noNormalChromeRestart=$true
      dedicatedChromeOnly=$true
      preserveLastGood=$true
    }
  }
}
function Get-State{
  $s=Read-Json $StatePath
  if(-not $s){$s=New-State}
  if(-not $s.extensions){$s.extensions=@()}
  if(-not $s.history){$s.history=@()}
  return $s
}
function Safe-Name([string]$Text){
  $x=($Text -replace '[^A-Za-z0-9._-]+','_').Trim('_')
  if([string]::IsNullOrWhiteSpace($x)){$x='extension'}
  return $x
}
function Find-Chrome{
  $candidates=@(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
  )|Where-Object{$_ -and (Test-Path -LiteralPath $_)}
  return $candidates|Select-Object -First 1
}
function Resolve-ManifestRoot([string]$InputRoot,[string]$SubPath){
  if($SubPath){
    $p=Join-Path $InputRoot $SubPath
    if(Test-Path -LiteralPath (Join-Path $p 'manifest.json')){return (Resolve-Path -LiteralPath $p).Path}
    throw "MANIFEST_SUBPATH_NOT_FOUND: $SubPath"
  }
  if(Test-Path -LiteralPath (Join-Path $InputRoot 'manifest.json')){return (Resolve-Path -LiteralPath $InputRoot).Path}
  $manifests=@(Get-ChildItem -LiteralPath $InputRoot -Filter manifest.json -File -Recurse -ErrorAction SilentlyContinue)
  if($manifests.Count -eq 0){throw 'MANIFEST_NOT_FOUND'}
  $roots=@($manifests|ForEach-Object{$_.Directory.FullName}|Sort-Object {($_ -split '[\\/]').Count})
  return $roots[0]
}
function Test-ManifestFiles([string]$RootPath,$Manifest){
  $errors=@()
  if([int]$Manifest.manifest_version -ne 3){$errors+='MANIFEST_V3_REQUIRED'}
  if($Manifest.background -and $Manifest.background.service_worker){
    $p=Join-Path $RootPath ([string]$Manifest.background.service_worker)
    if(-not(Test-Path -LiteralPath $p)){$errors+=('MISSING_SERVICE_WORKER:'+([string]$Manifest.background.service_worker))}
  }
  foreach($spec in @($Manifest.content_scripts)){
    if(-not $spec){continue}
    foreach($js in @($spec.js)){
      if($js -and -not(Test-Path -LiteralPath (Join-Path $RootPath ([string]$js)))){$errors+=('MISSING_CONTENT_SCRIPT:'+([string]$js))}
    }
  }
  return $errors
}
function Get-TreeHash([string]$RootPath){
  $files=@(Get-ChildItem -LiteralPath $RootPath -File -Recurse|Sort-Object FullName)
  $lines=@()
  foreach($f in $files){
    $h=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $rel=$f.FullName.Substring($RootPath.Length).TrimStart('\\','/')
    $lines+=("$h  $rel")
  }
  $tmp=Join-Path $env:TEMP ('ccem_hash_'+[guid]::NewGuid().ToString('N')+'.txt')
  $lines|Set-Content -LiteralPath $tmp -Encoding UTF8
  try{return (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}
function Upsert-ExtensionState($State,$Entry){
  $list=@($State.extensions)
  $existing=$list|Where-Object{([string]$_.name -eq [string]$Entry.name) -or ($Entry.expectedExtensionId -and [string]$_.expectedExtensionId -eq [string]$Entry.expectedExtensionId)}|Select-Object -First 1
  if($existing){
    foreach($p in $Entry.PSObject.Properties){$existing|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force}
  }else{$State.extensions=@($list)+@($Entry)}
}
function Add-History($State,[string]$Action,[string]$Name,[string]$Status,[string]$Detail){
  $State.history=@($State.history)+@([pscustomobject]@{at=(Get-Date).ToUniversalTime().ToString('o');action=$Action;name=$Name;status=$Status;detail=$Detail})
  if(@($State.history).Count -gt 200){$State.history=@($State.history|Select-Object -Last 200)}
}
function Get-ActivePaths($State){
  @($State.extensions|Where-Object{$_.active -eq $true -and $_.activePath -and (Test-Path -LiteralPath $_.activePath)}|ForEach-Object{[string]$_.activePath}|Select-Object -Unique)
}
function Launch-DedicatedChrome($State,[bool]$Restart){
  $chrome=Find-Chrome
  if(-not $chrome){throw 'CHROME_EXE_NOT_FOUND'}
  $paths=Get-ActivePaths $State
  if($paths.Count -eq 0){throw 'NO_ACTIVE_MANAGED_EXTENSION_PATHS'}
  if($Restart){
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$DedicatedUserData*"}|ForEach-Object{
      try{Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop}catch{}
    }
    Start-Sleep -Seconds 2
  }
  $args=@(
    "--user-data-dir=$DedicatedUserData",
    '--no-first-run',
    '--disable-default-apps',
    ('--load-extension='+($paths -join ',')),
    'chrome://version/'
  )
  Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
  return [pscustomobject]@{ok=$true;chrome=$chrome;userDataDir=$DedicatedUserData;loadedPaths=$paths;restart=$Restart}
}
function Run-GovernorInventory{
  if(Test-Path -LiteralPath $GovernorScript){
    try{
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GovernorScript |Out-Null
      $govState=Join-Path $Base 'ChromeGovernor\state.json'
      if(Test-Path -LiteralPath $govState){return (Read-Json $govState)}
    }catch{Write-Log ('GOVERNOR_INVENTORY_FAILED '+$_.Exception.Message)}
  }
  return $null
}

$mutex=New-Object System.Threading.Mutex($false,'HomeDesignManagedChromeExtensionPackageV1')
if(-not $mutex.WaitOne(0,$false)){throw 'MANAGER_ALREADY_RUNNING'}
try{
  $state=Get-State
  if($Mode -eq 'Inventory'){
    $gov=Run-GovernorInventory
    $result=[pscustomobject]@{
      ok=$true
      version=$Version
      mode=$Mode
      generatedAt=(Get-Date).ToUniversalTime().ToString('o')
      managerState=$state
      governorInventory=$gov
      policy=$state.policy
    }
    $result|ConvertTo-Json -Depth 30
    return
  }

  if($Mode -eq 'Stage'){
    if([string]::IsNullOrWhiteSpace($SourceZip) -and [string]::IsNullOrWhiteSpace($SourceDir)){throw 'SOURCE_ZIP_OR_DIR_REQUIRED'}
    $temp=''
    try{
      if($SourceZip){
        if(-not(Test-Path -LiteralPath $SourceZip)){throw "SOURCE_ZIP_NOT_FOUND: $SourceZip"}
        $temp=Join-Path $env:TEMP ('ccem_unpack_'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $temp|Out-Null
        Expand-Archive -LiteralPath $SourceZip -DestinationPath $temp -Force
        $inputRoot=$temp
      }else{
        if(-not(Test-Path -LiteralPath $SourceDir)){throw "SOURCE_DIR_NOT_FOUND: $SourceDir"}
        $inputRoot=(Resolve-Path -LiteralPath $SourceDir).Path
      }
      $manifestRoot=Resolve-ManifestRoot $inputRoot $ManifestSubPath
      $manifest=Read-Json (Join-Path $manifestRoot 'manifest.json')
      if(-not $manifest){throw 'MANIFEST_JSON_PARSE_FAILED'}
      $errors=@(Test-ManifestFiles $manifestRoot $manifest)
      if($errors.Count -gt 0){throw ('MANIFEST_INTEGRITY_FAILED:'+($errors -join '|'))}
      $name=[string]$manifest.name
      $ver=[string]$manifest.version
      if([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($ver)){throw 'MANIFEST_NAME_VERSION_REQUIRED'}
      $safe=Safe-Name $name
      $target=Join-Path (Join-Path $Root $safe) $ver
      New-Item -ItemType Directory -Force -Path $target|Out-Null
      Copy-Item -LiteralPath (Join-Path $manifestRoot '*') -Destination $target -Recurse -Force
      $treeHash=Get-TreeHash $target
      $existing=@($state.extensions)|Where-Object{[string]$_.name -eq $name}|Select-Object -First 1
      $previousPath=$(if($existing){[string]$existing.activePath}else{''})
      $entry=[pscustomobject]@{
        name=$name
        version=$ver
        expectedExtensionId=$ExpectedExtensionId
        activePath=$target
        previousPath=$previousPath
        active=$true
        manifestVersion=[int]$manifest.manifest_version
        treeSha256=$treeHash
        stagedAt=(Get-Date).ToUniversalTime().ToString('o')
        sourceZip=$SourceZip
        sourceDir=$SourceDir
        approval='EXISTING_SCOPE_ONLY; NEW_PERMISSION_PROMPT_IS_USER_GATE'
      }
      Upsert-ExtensionState $state $entry
      Add-History $state 'STAGE' $name 'PASS' ("version=$ver;path=$target;hash=$treeHash;previous=$previousPath")
      Save-State $state
      $launch=$null
      if($Apply){$launch=Launch-DedicatedChrome $state ([bool]$RestartDedicatedChrome)}
      [pscustomobject]@{ok=$true;version=$Version;mode=$Mode;name=$name;extensionVersion=$ver;path=$target;treeSha256=$treeHash;previousPath=$previousPath;apply=[bool]$Apply;launch=$launch;statePath=$StatePath}|ConvertTo-Json -Depth 20
    }finally{
      if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
    }
    return
  }

  if($Mode -eq 'Rollback'){
    $candidates=@($state.extensions|Where-Object{$_.previousPath -and (Test-Path -LiteralPath $_.previousPath)})
    if($ExpectedExtensionId){$candidates=@($candidates|Where-Object{[string]$_.expectedExtensionId -eq $ExpectedExtensionId})}
    if($candidates.Count -eq 0){throw 'NO_ROLLBACK_CANDIDATE'}
    foreach($e in $candidates){
      $current=[string]$e.activePath
      $e.activePath=[string]$e.previousPath
      $e.previousPath=$current
      $e.active=$true
      Add-History $state 'ROLLBACK' ([string]$e.name) 'PASS' ("active=$($e.activePath);previous=$($e.previousPath)")
    }
    Save-State $state
    $launch=$null
    if($Apply){$launch=Launch-DedicatedChrome $state ([bool]$RestartDedicatedChrome)}
    [pscustomobject]@{ok=$true;version=$Version;mode=$Mode;rolledBack=$candidates.Count;apply=[bool]$Apply;launch=$launch;statePath=$StatePath}|ConvertTo-Json -Depth 20
    return
  }

  if($Mode -eq 'LaunchDedicated'){
    $launch=Launch-DedicatedChrome $state ([bool]$RestartDedicatedChrome)
    Add-History $state 'LAUNCH_DEDICATED' 'ALL_ACTIVE' 'PASS' (($launch.loadedPaths) -join '|')
    Save-State $state
    $launch|ConvertTo-Json -Depth 10
    return
  }
}finally{
  try{$mutex.ReleaseMutex()}catch{}
  $mutex.Dispose()
}
