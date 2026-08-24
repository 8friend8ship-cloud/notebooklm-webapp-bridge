param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='CHROME_EXTENSION_GOVERNOR_ONESHOT_V2_NODE_20260824'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$ReportPath=Join-Path $GovRoot 'state.json'
$InventoryPath=Join-Path $GovRoot 'inventory.json'
$RawInventoryPath=Join-Path $GovRoot 'inventory-node.json'
$ScannerPath=Join-Path $GovRoot 'scanChromeInventory.js'
$ScannerUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/scanChromeInventory.js'
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
$AgentStatePath=Join-Path $Base 'LocalAgent\state.json'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$DedicatedExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
New-Item -ItemType Directory -Force -Path $GovRoot|Out-Null

function Read-Json([string]$FilePath){if(-not(Test-Path -LiteralPath $FilePath)){return $null};try{return Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Refresh-File([string]$Url,[string]$Path){try{$tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 30;Move-Item -LiteralPath $tmp -Destination $Path -Force;return $true}catch{return $false}}
function Read-Manifest([string]$RootPath){if([string]::IsNullOrWhiteSpace($RootPath)){return $null};return Read-Json (Join-Path $RootPath 'manifest.json')}
function Make-Item([string]$ProfileLabel,[string]$ExtensionId,[string]$RootPath,[bool]$IsUnpacked,[string]$SourceLabel){
  $manifest=Read-Manifest $RootPath;if(-not $manifest){return $null};$errors=@()
  if($manifest.background -and $manifest.background.service_worker){$worker=Join-Path $RootPath ([string]$manifest.background.service_worker);if(-not(Test-Path -LiteralPath $worker)){$errors+=('missing service_worker: '+[string]$manifest.background.service_worker)}}
  foreach($contentSpec in @($manifest.content_scripts)){if(-not $contentSpec){continue};foreach($jsFile in @($contentSpec.js)){if($jsFile -and -not(Test-Path -LiteralPath (Join-Path $RootPath ([string]$jsFile)))){$errors+=('missing content_script: '+[string]$jsFile)}}}
  return [pscustomobject]@{profile=$ProfileLabel;id=$ExtensionId;name=[string]$manifest.name;version=[string]$manifest.version;path=$RootPath;unpacked=$IsUnpacked;source=$SourceLabel;fileIntegrityOk=($errors.Count -eq 0);fileErrors=$errors}
}
function Fallback-Inventory{
  $items=@()
  if(Test-Path -LiteralPath $NormalRoot){foreach($profile in @(Get-ChildItem -LiteralPath $NormalRoot -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -eq 'Default' -or $_.Name -like 'Profile *'})){ $extRoot=Join-Path $profile.FullName 'Extensions';if(Test-Path $extRoot){foreach($idDir in @(Get-ChildItem $extRoot -Directory -ErrorAction SilentlyContinue)){ $latest=Get-ChildItem $idDir.FullName -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1;if($latest){$i=Make-Item ('NORMAL_CHROME/'+$profile.Name) $idDir.Name $latest.FullName $false 'PROFILE_EXTENSIONS_DIR_FALLBACK';if($i){$items+=$i}}}}}}
  $cftExt=Join-Path (Join-Path $DedicatedUserData 'Default') 'Extensions';if(Test-Path $cftExt){foreach($idDir in @(Get-ChildItem $cftExt -Directory -ErrorAction SilentlyContinue)){ $latest=Get-ChildItem $idDir.FullName -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1;if($latest){$i=Make-Item 'HOMEDESIGN_CFT/Default' $idDir.Name $latest.FullName $false 'PROFILE_EXTENSIONS_DIR_FALLBACK';if($i){$items+=$i}}}}
  if(Test-Path -LiteralPath (Join-Path $DedicatedExtensionRoot 'manifest.json')){$i=Make-Item 'HOMEDESIGN_CFT/LoadedExtension' 'RESOLVE_FROM_PROFILE' $DedicatedExtensionRoot $true 'LOCAL_AGENT_EXTENSION_ROOT';if($i){$items+=$i}}
  return $items
}
function Get-InventoryFast{
  $engine='NODE';$error='';$count=0
  [void](Refresh-File $ScannerUrl $ScannerPath)
  $node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $node){$node=Get-Command node -ErrorAction SilentlyContinue}
  if($node -and (Test-Path -LiteralPath $ScannerPath)){
    try{
      & $node.Source $ScannerPath --normalRoot $NormalRoot --dedicatedUserData $DedicatedUserData --dedicatedExtensionRoot $DedicatedExtensionRoot --output $RawInventoryPath *> (Join-Path $GovRoot 'node-scan.log')
      if($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $RawInventoryPath)){$items=@(Read-Json $RawInventoryPath);$count=$items.Count;return [pscustomobject]@{engine=$engine;ok=$true;error='';items=$items;count=$count}}
      $error='NODE_SCAN_NONZERO_OR_NO_OUTPUT'
    }catch{$error=$_.Exception.Message}
  }else{$error='NODE_NOT_FOUND'}
  $engine='POWERSHELL_PACKED_ONLY_FALLBACK';$items=@(Fallback-Inventory);return [pscustomobject]@{engine=$engine;ok=($items.Count -gt 0);error=$error;items=$items;count=$items.Count}
}
function Get-Policy{try{return Invoke-RestMethod -Uri $PolicyUrl -TimeoutSec 20}catch{return [pscustomobject]@{updatedAt='';managedExtensions=@();securityHoldNames=@();observeOnlyNames=@()}}}
function Classify($Inventory,$Policy){
  $out=@();$managed=@($Policy.managedExtensions);$security=@($Policy.securityHoldNames);$observe=@($Policy.observeOnlyNames)
  foreach($item in @($Inventory)){
    $rule=$managed|Where-Object{[string]$_.name -eq [string]$item.name}|Select-Object -First 1
    $classification='UNREGISTERED_OBSERVE_ONLY';$mode='OBSERVE_ONLY';$expected='';$action='OBSERVE_ONLY'
    if($rule){$classification='CENTRAL_MANAGED';$mode=[string]$rule.mode;$expected=[string]$rule.canonicalVersion;if(-not [bool]$item.fileIntegrityOk){$action='REPAIR_FILES_REQUIRED'}elseif($mode -eq 'LOCAL_AGENT_STABLE'){$action='OWNED_BY_LOCAL_AGENT'}elseif($expected -and [string]$item.version -ne $expected){$action='VERSION_DIFF_HOLD_OR_CANONICAL_UPDATE'}else{$action='CHECK_OK'}}
    elseif($security -contains [string]$item.name){$classification='SECURITY_HOLD';$mode='HOLD_NO_DELETE';$action='USER_REVIEW_REQUIRED_NO_AUTO_DELETE'}
    elseif($observe -contains [string]$item.name){$classification='THIRD_PARTY_OBSERVE_ONLY';$mode='OBSERVE_ONLY';$action='NO_AUTO_CHANGE'}
    elseif([bool]$item.unpacked){$classification='UNPACKED_UNREGISTERED_HOLD';$mode='HOLD_NO_DELETE';$action='REGISTER_SOURCE_BEFORE_UPDATE'}
    $out+=[pscustomobject]@{profile=$item.profile;id=$item.id;name=$item.name;installedVersion=$item.version;expectedVersion=$expected;classification=$classification;mode=$mode;action=$action;fileIntegrityOk=[bool]$item.fileIntegrityOk;path=$item.path;unpacked=[bool]$item.unpacked;source=$item.source;fileErrors=@($item.fileErrors)}
  };return $out
}

$scan=Get-InventoryFast
$inventory=@($scan.items)
$policy=Get-Policy
$classified=@(Classify $inventory $policy)
$duplicates=@();foreach($group in @($classified|Group-Object name)){if($group.Name -and $group.Count -gt 1){$duplicates+=[pscustomobject]@{name=$group.Name;count=$group.Count;items=@($group.Group|Select-Object profile,id,installedVersion,path)}}}
$agent=Read-Json $AgentStatePath
$release=$null;try{$release=Invoke-RestMethod -Uri $ReleaseUrl -TimeoutSec 20}catch{}
$managedProblems=@($classified|Where-Object{$_.classification -eq 'CENTRAL_MANAGED' -and $_.action -notin @('CHECK_OK','OWNED_BY_LOCAL_AGENT')})
$report=[ordered]@{
  ok=[bool]$scan.ok;version=$Version;mode='AGENT_5MIN_ONESHOT_NODE_FAST';generatedAt=(Get-Date).ToUniversalTime().ToString('o');scanEngine=$scan.engine;scanError=$scan.error;policyUpdatedAt=[string]$policy.updatedAt;
  notebookLocalAgent=[ordered]@{agentVersion=$(if($agent){$agent.agentVersion}else{$null});installedVersion=$(if($agent){$agent.extensionVersion}else{$null});hostVersion=$(if($agent){$agent.commandHostVersion}else{$null});hostHealthy=$(if($agent){$agent.hostHealthy}else{$null});targetBridgeVersion=$(if($release){$release.version}else{$null})};
  summary=[ordered]@{total=$classified.Count;centralManaged=@($classified|Where-Object{$_.classification -eq 'CENTRAL_MANAGED'}).Count;securityHold=@($classified|Where-Object{$_.classification -eq 'SECURITY_HOLD'}).Count;unpackedUnregistered=@($classified|Where-Object{$_.classification -eq 'UNPACKED_UNREGISTERED_HOLD'}).Count;duplicates=$duplicates.Count;managedProblems=$managedProblems.Count};
  extensions=$classified;duplicates=$duplicates;policy=[ordered]@{noDelete=$true;noCredentialRead=$true;noNewOAuth=$true;noNormalChromeRestart=$true}
}
$report|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReportPath -Encoding UTF8
$inventory|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $InventoryPath -Encoding UTF8
[ordered]@{ok=$report.ok;version=$Version;mode=$report.mode;scanEngine=$scan.engine;scanError=$scan.error;reportPath=$ReportPath;inventoryPath=$InventoryPath;summary=$report.summary}|ConvertTo-Json -Depth 8 -Compress
if($report.ok){exit 0}else{exit 2}
