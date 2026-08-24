param([switch]$Loop)

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CHROME_EXTENSION_GOVERNOR_V2_20260824'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$LogRoot=Join-Path $GovRoot 'Logs'
$ReportPath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$DesktopReport=Join-Path ([Environment]::GetFolderPath('Desktop')) 'CHROME_EXTENSION_GOVERNOR_RESULT.json'
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
$AgentStatePath=Join-Path $Base 'LocalAgent\state.json'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$DedicatedExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
New-Item -ItemType Directory -Force -Path $GovRoot,$LogRoot|Out-Null

function Write-Log([string]$Message){
  $logFile=Join-Path $LogRoot ('governor_'+(Get-Date -Format 'yyyyMMdd')+'.log')
  Add-Content -LiteralPath $logFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8
}
function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Resolve-Manifest([string]$RootPath){
  if([string]::IsNullOrWhiteSpace($RootPath)){return $null}
  $manifestFile=Join-Path $RootPath 'manifest.json'
  if(-not(Test-Path -LiteralPath $manifestFile)){return $null}
  return Read-Json $manifestFile
}
function New-InventoryItem([string]$ProfileLabel,[string]$ExtensionId,[string]$RootPath,[bool]$IsUnpacked,[string]$SourceLabel){
  $manifest=Resolve-Manifest $RootPath
  if(-not $manifest){return $null}
  $fileErrors=@()
  if($manifest.background -and $manifest.background.service_worker){
    $workerPath=Join-Path $RootPath ([string]$manifest.background.service_worker)
    if(-not(Test-Path -LiteralPath $workerPath)){$fileErrors+=('missing service_worker: '+[string]$manifest.background.service_worker)}
  }
  foreach($contentSpec in @($manifest.content_scripts)){
    if(-not $contentSpec){continue}
    foreach($jsFile in @($contentSpec.js)){
      if(-not $jsFile){continue}
      $scriptPath=Join-Path $RootPath ([string]$jsFile)
      if(-not(Test-Path -LiteralPath $scriptPath)){$fileErrors+=('missing content_script: '+[string]$jsFile)}
    }
  }
  return [pscustomobject]@{
    profile=$ProfileLabel
    id=$ExtensionId
    name=[string]$manifest.name
    version=[string]$manifest.version
    path=$RootPath
    unpacked=$IsUnpacked
    source=$SourceLabel
    manifestVersion=[string]$manifest.manifest_version
    fileIntegrityOk=($fileErrors.Count -eq 0)
    fileErrors=$fileErrors
  }
}
function Scan-ChromeProfile([string]$ProfileLabel,[string]$ProfileRoot){
  $items=@()
  if(-not(Test-Path -LiteralPath $ProfileRoot)){return $items}
  $seen=@{}
  $extensionsRoot=Join-Path $ProfileRoot 'Extensions'
  if(Test-Path -LiteralPath $extensionsRoot){
    foreach($idDir in @(Get-ChildItem -LiteralPath $extensionsRoot -Directory -ErrorAction SilentlyContinue)){
      $latest=Get-ChildItem -LiteralPath $idDir.FullName -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1
      if(-not $latest){continue}
      $item=New-InventoryItem $ProfileLabel ([string]$idDir.Name) ([string]$latest.FullName) $false 'PROFILE_EXTENSIONS_DIR'
      if($item){$items+=$item;$seen[[string]$idDir.Name]=$true}
    }
  }
  foreach($prefName in @('Preferences','Secure Preferences')){
    $prefFile=Join-Path $ProfileRoot $prefName
    if(-not(Test-Path -LiteralPath $prefFile)){continue}
    try{
      $prefData=Get-Content -LiteralPath $prefFile -Raw -Encoding UTF8|ConvertFrom-Json
      $settings=$prefData.extensions.settings
      if(-not $settings){continue}
      foreach($settingProp in $settings.PSObject.Properties){
        $extId=[string]$settingProp.Name
        if($seen.ContainsKey($extId)){continue}
        $setting=$settingProp.Value
        if(-not $setting.path){continue}
        $candidate=[string]$setting.path
        if(-not [IO.Path]::IsPathRooted($candidate)){$candidate=Join-Path $ProfileRoot $candidate}
        if(-not(Test-Path -LiteralPath (Join-Path $candidate 'manifest.json'))){continue}
        $item=New-InventoryItem $ProfileLabel $extId $candidate $true $prefName
        if($item){$items+=$item;$seen[$extId]=$true}
      }
    }catch{Write-Log "PREFERENCES_PARSE_FAILED label=$ProfileLabel file=$prefName error=$($_.Exception.Message)"}
  }
  return $items
}
function Get-AllInventory{
  $items=@()
  $normalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if(Test-Path -LiteralPath $normalRoot){
    foreach($profileDir in @(Get-ChildItem -LiteralPath $normalRoot -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -eq 'Default' -or $_.Name -like 'Profile *'})){
      $items+=@(Scan-ChromeProfile ('NORMAL_CHROME/'+[string]$profileDir.Name) ([string]$profileDir.FullName))
    }
  }
  $items+=@(Scan-ChromeProfile 'HOMEDESIGN_CFT/Default' (Join-Path $DedicatedUserData 'Default'))
  if(Test-Path -LiteralPath (Join-Path $DedicatedExtensionRoot 'manifest.json')){
    $norm=(Resolve-Path -LiteralPath $DedicatedExtensionRoot -ErrorAction SilentlyContinue).Path
    $exists=@($items|Where-Object{$_.path -and ((Resolve-Path -LiteralPath $_.path -ErrorAction SilentlyContinue).Path -eq $norm)}).Count -gt 0
    if(-not $exists){
      $item=New-InventoryItem 'HOMEDESIGN_CFT/LoadedExtension' 'RESOLVE_FROM_PROFILE' $DedicatedExtensionRoot $true 'LOCAL_AGENT_EXTENSION_ROOT'
      if($item){$items+=$item}
    }
  }
  return $items
}
function Get-Policy{
  try{return Invoke-RestMethod -Uri $PolicyUrl -Method Get -TimeoutSec 20}catch{
    Write-Log ('POLICY_FETCH_FAILED '+$_.Exception.Message)
    return [pscustomobject]@{updatedAt='';pollSeconds=900;rules=[pscustomobject]@{unregisteredMode='OBSERVE_ONLY'};managedExtensions=@();securityHoldNames=@();observeOnlyNames=@()}
  }
}
function Classify-Inventory($Inventory,$Policy){
  $classified=@()
  $managed=@($Policy.managedExtensions)
  $securityNames=@($Policy.securityHoldNames)
  $observeNames=@($Policy.observeOnlyNames)
  foreach($item in @($Inventory)){
    $rule=$managed|Where-Object{[string]$_.name -eq [string]$item.name}|Select-Object -First 1
    $classification='UNREGISTERED_OBSERVE_ONLY'
    $mode=[string]$Policy.rules.unregisteredMode
    $expected=''
    $action='OBSERVE_ONLY'
    if($rule){
      $classification='CENTRAL_MANAGED';$mode=[string]$rule.mode;$expected=[string]$rule.canonicalVersion
      if(-not [bool]$item.fileIntegrityOk){$action='REPAIR_FILES_REQUIRED'}
      elseif($expected -and [string]$item.version -ne $expected){$action='VERSION_DIFF_HOLD_OR_CANONICAL_UPDATE'}
      else{$action='CHECK_OK'}
      if($mode -eq 'LOCAL_AGENT_STABLE'){$action='OWNED_BY_LOCAL_AGENT'}
    }elseif($securityNames -contains [string]$item.name){$classification='SECURITY_HOLD';$mode='HOLD_NO_DELETE';$action='USER_REVIEW_REQUIRED_NO_AUTO_DELETE'}
    elseif($observeNames -contains [string]$item.name){$classification='THIRD_PARTY_OBSERVE_ONLY';$mode='OBSERVE_ONLY';$action='NO_AUTO_CHANGE'}
    elseif([bool]$item.unpacked){$classification='UNPACKED_UNREGISTERED_HOLD';$mode='HOLD_NO_DELETE';$action='REGISTER_SOURCE_BEFORE_UPDATE'}
    $classified+=[pscustomobject]@{
      profile=$item.profile;id=$item.id;name=$item.name;installedVersion=$item.version;expectedVersion=$expected;
      classification=$classification;mode=$mode;action=$action;fileIntegrityOk=[bool]$item.fileIntegrityOk;
      path=$item.path;unpacked=[bool]$item.unpacked;source=$item.source;fileErrors=@($item.fileErrors)
    }
  }
  return $classified
}
function Get-NotebookState{
  $agentState=Read-Json $AgentStatePath
  $release=$null
  try{$release=Invoke-RestMethod -Uri $ReleaseUrl -Method Get -TimeoutSec 20}catch{}
  return [ordered]@{
    agentVersion=$(if($agentState){$agentState.agentVersion}else{$null})
    installedVersion=$(if($agentState){$agentState.extensionVersion}else{$null})
    hostVersion=$(if($agentState){$agentState.commandHostVersion}else{$null})
    hostHealthy=$(if($agentState){$agentState.hostHealthy}else{$null})
    targetBridgeVersion=$(if($release){$release.version}else{$null})
    releaseActionId=$(if($release){$release.actionId}else{$null})
  }
}
function Run-Cycle{
  Write-Log "CYCLE_START version=$Version"
  $policy=Get-Policy
  $inventory=@(Get-AllInventory)
  $classified=@(Classify-Inventory $inventory $policy)
  $duplicates=@()
  foreach($group in @($classified|Group-Object name)){
    if($group.Name -and $group.Count -gt 1){$duplicates+=[pscustomobject]@{name=$group.Name;count=$group.Count;items=@($group.Group|Select-Object profile,id,installedVersion,path)}}
  }
  $managedProblems=@($classified|Where-Object{$_.classification -eq 'CENTRAL_MANAGED' -and $_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT')})
  $securityProblems=@($classified|Where-Object{$_.classification -eq 'SECURITY_HOLD'})
  $unpackedProblems=@($classified|Where-Object{$_.classification -eq 'UNPACKED_UNREGISTERED_HOLD'})
  $report=[ordered]@{
    ok=($managedProblems.Count -eq 0 -and $securityProblems.Count -eq 0)
    version=$Version
    generatedAt=(Get-Date).ToUniversalTime().ToString('o')
    policyUpdatedAt=[string]$policy.updatedAt
    notebookLocalAgent=Get-NotebookState
    summary=[ordered]@{
      total=$classified.Count
      centralManaged=@($classified|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}).Count
      thirdPartyObserve=@($classified|Where-Object{$_.classification -eq 'THIRD_PARTY_OBSERVE_ONLY'}).Count
      securityHold=$securityProblems.Count
      unpackedUnregistered=$unpackedProblems.Count
      duplicates=$duplicates.Count
      managedProblems=$managedProblems.Count
    }
    extensions=$classified
    duplicates=$duplicates
    policy=[ordered]@{noDelete=$true;noCredentialRead=$true;noNewOAuth=$true;noNormalChromeRestart=$true;safeAutomaticScope='inventory;file-integrity;version-diff;source-binding;Local-Agent stable only'}
  }
  $report|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReportPath -Encoding UTF8
  $inventory|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $InventoryPath -Encoding UTF8
  try{Copy-Item -LiteralPath $ReportPath -Destination $DesktopReport -Force}catch{}
  Write-Log "CYCLE_END total=$($classified.Count) managedProblems=$($managedProblems.Count) securityHold=$($securityProblems.Count) duplicates=$($duplicates.Count)"
  $seconds=900
  try{$seconds=[Math]::Max(300,[int]$policy.pollSeconds)}catch{}
  return $seconds
}

$mutex=New-Object System.Threading.Mutex($false,'HomeDesignChromeExtensionGovernorV2')
if(-not $mutex.WaitOne(0,$false)){exit 0}
try{
  do{
    $sleepSeconds=Run-Cycle
    if($Loop){Start-Sleep -Seconds $sleepSeconds}
  }while($Loop)
}finally{
  try{$mutex.ReleaseMutex()}catch{}
  $mutex.Dispose()
}
