param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CHROME_EXTENSION_GOVERNOR_ONESHOT_V1_20260824'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ReportPath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
$AgentStatePath=Join-Path $Base 'LocalAgent\state.json'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$DedicatedExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
New-Item -ItemType Directory -Force -Path $GovRoot|Out-Null

function Read-Json([string]$FilePath){
  if(-not(Test-Path -LiteralPath $FilePath)){return $null}
  try{return Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Read-Manifest([string]$RootPath){
  if([string]::IsNullOrWhiteSpace($RootPath)){return $null}
  return Read-Json (Join-Path $RootPath 'manifest.json')
}
function Make-Item([string]$ProfileLabel,[string]$ExtensionId,[string]$RootPath,[bool]$IsUnpacked,[string]$SourceLabel){
  $manifest=Read-Manifest $RootPath
  if(-not $manifest){return $null}
  $errors=@()
  if($manifest.background -and $manifest.background.service_worker){
    $worker=Join-Path $RootPath ([string]$manifest.background.service_worker)
    if(-not(Test-Path -LiteralPath $worker)){$errors+=('missing service_worker: '+[string]$manifest.background.service_worker)}
  }
  foreach($contentSpec in @($manifest.content_scripts)){
    if(-not $contentSpec){continue}
    foreach($jsFile in @($contentSpec.js)){
      if($jsFile -and -not(Test-Path -LiteralPath (Join-Path $RootPath ([string]$jsFile)))){$errors+=('missing content_script: '+[string]$jsFile)}
    }
  }
  return [pscustomobject]@{
    profile=$ProfileLabel;id=$ExtensionId;name=[string]$manifest.name;version=[string]$manifest.version;
    path=$RootPath;unpacked=$IsUnpacked;source=$SourceLabel;fileIntegrityOk=($errors.Count -eq 0);fileErrors=$errors
  }
}
function Scan-Profile([string]$ProfileLabel,[string]$ProfileRoot){
  $items=@();$seen=@{}
  if(-not(Test-Path -LiteralPath $ProfileRoot)){return $items}
  $extRoot=Join-Path $ProfileRoot 'Extensions'
  if(Test-Path -LiteralPath $extRoot){
    foreach($idDir in @(Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue)){
      $latest=Get-ChildItem -LiteralPath $idDir.FullName -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1
      if(-not $latest){continue}
      $item=Make-Item $ProfileLabel ([string]$idDir.Name) ([string]$latest.FullName) $false 'PROFILE_EXTENSIONS_DIR'
      if($item){$items+=$item;$seen[[string]$idDir.Name]=$true}
    }
  }
  foreach($prefName in @('Preferences','Secure Preferences')){
    $prefPath=Join-Path $ProfileRoot $prefName
    if(-not(Test-Path -LiteralPath $prefPath)){continue}
    try{
      $pref=Get-Content -LiteralPath $prefPath -Raw -Encoding UTF8|ConvertFrom-Json
      $settings=$pref.extensions.settings
      if(-not $settings){continue}
      foreach($prop in $settings.PSObject.Properties){
        $extId=[string]$prop.Name
        if($seen.ContainsKey($extId)){continue}
        $setting=$prop.Value
        if(-not $setting.path){continue}
        $candidate=[string]$setting.path
        if(-not [IO.Path]::IsPathRooted($candidate)){$candidate=Join-Path $ProfileRoot $candidate}
        if(-not(Test-Path -LiteralPath (Join-Path $candidate 'manifest.json'))){continue}
        $item=Make-Item $ProfileLabel $extId $candidate $true $prefName
        if($item){$items+=$item;$seen[$extId]=$true}
      }
    }catch{}
  }
  return $items
}
function Get-Inventory{
  $items=@()
  $normalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if(Test-Path -LiteralPath $normalRoot){
    foreach($dir in @(Get-ChildItem -LiteralPath $normalRoot -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -eq 'Default' -or $_.Name -like 'Profile *'})){
      $items+=@(Scan-Profile ('NORMAL_CHROME/'+[string]$dir.Name) ([string]$dir.FullName))
    }
  }
  $items+=@(Scan-Profile 'HOMEDESIGN_CFT/Default' (Join-Path $DedicatedUserData 'Default'))
  if(Test-Path -LiteralPath (Join-Path $DedicatedExtensionRoot 'manifest.json')){
    $already=@($items|Where-Object{[string]$_.path -eq [string]$DedicatedExtensionRoot}).Count -gt 0
    if(-not $already){$item=Make-Item 'HOMEDESIGN_CFT/LoadedExtension' 'RESOLVE_FROM_PROFILE' $DedicatedExtensionRoot $true 'LOCAL_AGENT_EXTENSION_ROOT';if($item){$items+=$item}}
  }
  return $items
}
function Get-Policy{
  try{return Invoke-RestMethod -Uri $PolicyUrl -TimeoutSec 20}catch{return [pscustomobject]@{updatedAt='';managedExtensions=@();securityHoldNames=@();observeOnlyNames=@()}}
}
function Classify($Inventory,$Policy){
  $out=@();$managed=@($Policy.managedExtensions);$security=@($Policy.securityHoldNames);$observe=@($Policy.observeOnlyNames)
  foreach($item in @($Inventory)){
    $rule=$managed|Where-Object{[string]$_.name -eq [string]$item.name}|Select-Object -First 1
    $classification='UNREGISTERED_OBSERVE_ONLY';$mode='OBSERVE_ONLY';$expected='';$action='OBSERVE_ONLY'
    if($rule){
      $classification='CENTRAL_MANAGED';$mode=[string]$rule.mode;$expected=[string]$rule.canonicalVersion
      if(-not [bool]$item.fileIntegrityOk){$action='REPAIR_FILES_REQUIRED'}
      elseif($mode -eq 'LOCAL_AGENT_STABLE'){$action='OWNED_BY_LOCAL_AGENT'}
      elseif($expected -and [string]$item.version -ne $expected){$action='VERSION_DIFF_HOLD_OR_CANONICAL_UPDATE'}
      else{$action='CHECK_OK'}
    }elseif($security -contains [string]$item.name){$classification='SECURITY_HOLD';$mode='HOLD_NO_DELETE';$action='USER_REVIEW_REQUIRED_NO_AUTO_DELETE'}
    elseif($observe -contains [string]$item.name){$classification='THIRD_PARTY_OBSERVE_ONLY';$mode='OBSERVE_ONLY';$action='NO_AUTO_CHANGE'}
    elseif([bool]$item.unpacked){$classification='UNPACKED_UNREGISTERED_HOLD';$mode='HOLD_NO_DELETE';$action='REGISTER_SOURCE_BEFORE_UPDATE'}
    $out+=[pscustomobject]@{profile=$item.profile;id=$item.id;name=$item.name;installedVersion=$item.version;expectedVersion=$expected;classification=$classification;mode=$mode;action=$action;fileIntegrityOk=[bool]$item.fileIntegrityOk;path=$item.path;unpacked=[bool]$item.unpacked;source=$item.source;fileErrors=@($item.fileErrors)}
  }
  return $out
}

$policy=Get-Policy
$inventory=@(Get-Inventory)
$classified=@(Classify $inventory $policy)
$duplicates=@()
foreach($group in @($classified|Group-Object name)){if($group.Name -and $group.Count -gt 1){$duplicates+=[pscustomobject]@{name=$group.Name;count=$group.Count;items=@($group.Group|Select-Object profile,id,installedVersion,path)}}}
$agent=Read-Json $AgentStatePath
$release=$null;try{$release=Invoke-RestMethod -Uri $ReleaseUrl -TimeoutSec 20}catch{}
$managedProblems=@($classified|Where-Object{$_.classification -eq 'CENTRAL_MANAGED' -and $_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT')})
$report=[ordered]@{
  ok=$true;version=$Version;mode='AGENT_5MIN_ONESHOT';generatedAt=(Get-Date).ToUniversalTime().ToString('o');policyUpdatedAt=[string]$policy.updatedAt;
  notebookLocalAgent=[ordered]@{agentVersion=$(if($agent){$agent.agentVersion}else{$null});installedVersion=$(if($agent){$agent.extensionVersion}else{$null});hostVersion=$(if($agent){$agent.commandHostVersion}else{$null});hostHealthy=$(if($agent){$agent.hostHealthy}else{$null});targetBridgeVersion=$(if($release){$release.version}else{$null})};
  summary=[ordered]@{total=$classified.Count;centralManaged=@($classified|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}).Count;securityHold=@($classified|Where-Object{$_.classification -eq 'SECURITY_HOLD'}).Count;unpackedUnregistered=@($classified|Where-Object{$_.classification -eq 'UNPACKED_UNREGISTERED_HOLD'}).Count;duplicates=$duplicates.Count;managedProblems=$managedProblems.Count};
  extensions=$classified;duplicates=$duplicates;policy=[ordered]@{noDelete=$true;noCredentialRead=$true;noNewOAuth=$true;noNormalChromeRestart=$true}
}
$report|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReportPath -Encoding UTF8
$inventory|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $InventoryPath -Encoding UTF8
[ordered]@{ok=$true;version=$Version;mode='AGENT_5MIN_ONESHOT';reportPath=$ReportPath;inventoryPath=$InventoryPath;summary=$report.summary}|ConvertTo-Json -Depth 8 -Compress
exit 0
