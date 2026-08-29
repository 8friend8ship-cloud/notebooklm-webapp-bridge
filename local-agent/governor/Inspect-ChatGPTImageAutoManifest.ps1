param(
  [string]$ExtensionId='gedfnhdibkfgacmkbjgpfjihacalnlpn',
  [string]$Profile='Default',
  [string]$CentralRootOverride=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='CHATGPT_IMAGE_MANIFEST_INSPECT_V1_20260829'
$chromeRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$profileRoot=Join-Path $chromeRoot $Profile
$extRoot=Join-Path $profileRoot ('Extensions\'+$ExtensionId)
if(-not(Test-Path -LiteralPath $extRoot -PathType Container)){throw 'EXTENSION_ROOT_NOT_FOUND'}
$verDir=Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction Stop|Sort-Object Name -Descending|Select-Object -First 1
if(-not $verDir){throw 'EXTENSION_VERSION_NOT_FOUND'}
$manifestPath=Join-Path $verDir.FullName 'manifest.json'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'MANIFEST_NOT_FOUND'}
$m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$sidePanel=$null
if($m.PSObject.Properties.Name -contains 'side_panel'){$sidePanel=$m.side_panel.default_path}
$serviceWorker=$null
if($m.PSObject.Properties.Name -contains 'background'){$serviceWorker=$m.background.service_worker}
$contentScripts=@()
if($m.PSObject.Properties.Name -contains 'content_scripts'){
  foreach($cs in @($m.content_scripts)){
    $contentScripts += [pscustomobject]@{matches=@($cs.matches);js=@($cs.js);css=@($cs.css);run_at=[string]$cs.run_at}
  }
}
$resourcePaths=@()
if($sidePanel){$resourcePaths += [string]$sidePanel}
if($serviceWorker){$resourcePaths += [string]$serviceWorker}
foreach($cs in $contentScripts){$resourcePaths += @($cs.js);$resourcePaths += @($cs.css)}
$resourcePaths=@($resourcePaths|Where-Object{$_}|Select-Object -Unique)
$resourceEvidence=@()
foreach($rel in $resourcePaths){
  $p=Join-Path $verDir.FullName ([string]$rel)
  $resourceEvidence += [pscustomobject]@{relativePath=[string]$rel;exists=(Test-Path -LiteralPath $p -PathType Leaf);fullPath=$p;bytes=$(if(Test-Path -LiteralPath $p -PathType Leaf){(Get-Item -LiteralPath $p).Length}else{0})}
}
$result=[ordered]@{
  ok=$true
  action='CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT'
  inspectorVersion=$Version
  profile=$Profile
  extensionId=$ExtensionId
  extensionVersion=[string]$m.version
  manifestVersion=$m.manifest_version
  extensionPath=$verDir.FullName
  name=[string]$m.name
  permissions=@($m.permissions)
  hostPermissions=@($m.host_permissions)
  sidePanelDefaultPath=[string]$sidePanel
  serviceWorker=[string]$serviceWorker
  contentScripts=$contentScripts
  referencedResources=$resourceEvidence
  privacyGuard='NO_PREFERENCES_NO_SECURE_PREFERENCES_NO_COOKIES_NO_TOKENS_NO_HISTORY'
  chromeMutation=$false
  reinstall=$false
  oauthChange=$false
  generateClicked=$false
  creditSpend=$false
  at=(Get-Date).ToString('o')
}
$outDir=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $outDir|Out-Null
$outPath=Join-Path $outDir 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json'
$result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $outPath -Encoding UTF8
if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride -PathType Container)){
  $destDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
  New-Item -ItemType Directory -Force -Path $destDir|Out-Null
  $result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $destDir 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json') -Encoding UTF8
}
$result['resultPath']=$outPath
$result|ConvertTo-Json -Depth 30 -Compress
exit 0
