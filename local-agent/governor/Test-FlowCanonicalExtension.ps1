param(
  [string]$CentralRootOverride=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$ExpectedVersion='0.1.0'
$ExpectedName='Flow Agent Bridge'
$ExpectedExtensionId='lgedgmpcikglaajhfclcihicgafimlna'
$Expected=[ordered]@{
  'manifest.json'=[ordered]@{bytes=868;sha256='41d7d4acd844329ae328373d8d56798f508848a17f5892841c7930d2451c8169'}
  'content.js'=[ordered]@{bytes=8334;sha256='fa4d98f8962c6c8b799908a3e876d19e57babfecbe62781312a28a34549f3050'}
  'popup.js'=[ordered]@{bytes=8747;sha256='297e40dfe1609f840b58d76d0ec531f6e594f15ba793710e6806892501419040'}
  'popup.html'=[ordered]@{bytes=2307;sha256='ba79b1decc5e135433123bd9764d796035c2e8b39315553870873a4465dec0f2'}
}
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'

function FindCentral {
  if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride -PathType Container)){return $CentralRootOverride}
  $name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    if(-not$d.Root){continue}
    foreach($c in @((Join-Path $d.Root $name),(Join-Path $d.Root ('My Drive\'+$name)),(Join-Path $d.Root ($myDriveKo+'\'+$name)),(Join-Path $d.Root ('Google Drive\'+$name)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function CandidatePaths {
  @(
    (Join-Path $Base 'ManagedExtensions\Flow_Agent_Bridge\0.1.0'),
    (Join-Path $Base 'Extension\Flow-Agent-Bridge'),
    (Join-Path $Base 'Extension\Google-AI-Local-Bridge-Flow'),
    (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0\flow-agent-bridge-v0.1.0'),
    (Join-Path $env:USERPROFILE 'Downloads\flow-agent-bridge-v0.1.0')
  ) | Select-Object -Unique
}
function Inspect([string]$Path){
  $errors=@();$files=[ordered]@{};$manifest=$null
  if(-not(Test-Path -LiteralPath (Join-Path $Path 'manifest.json') -PathType Leaf)){return [ordered]@{path=$Path;exists=$false;ok=$false;errors=@('MANIFEST_NOT_FOUND')}}
  try{$manifest=Get-Content -LiteralPath (Join-Path $Path 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{$errors+='MANIFEST_PARSE_FAILED'}
  if($manifest){
    if([string]$manifest.name-ne$ExpectedName){$errors+=('NAME_MISMATCH:'+ [string]$manifest.name)}
    if([string]$manifest.version-ne$ExpectedVersion){$errors+=('VERSION_MISMATCH:'+ [string]$manifest.version)}
    if([int]$manifest.manifest_version-ne3){$errors+=('MANIFEST_VERSION_MISMATCH:'+ [string]$manifest.manifest_version)}
    $bg='';try{$bg=[string]$manifest.background.service_worker}catch{}
    if($bg){$errors+=('UNEXPECTED_BACKGROUND_SERVICE_WORKER:'+ $bg)}
    $contentOk=$false;try{$contentOk=@($manifest.content_scripts|Where-Object{@($_.matches)-contains'https://labs.google/*'-and@($_.js)-contains'content.js'}).Count-gt0}catch{}
    if(-not$contentOk){$errors+='CONTENT_SCRIPT_CONTRACT_MISMATCH'}
    $popup='';try{$popup=[string]$manifest.action.default_popup}catch{}
    if($popup-ne'popup.html'){$errors+=('POPUP_CONTRACT_MISMATCH:'+ $popup)}
  }
  foreach($name in $Expected.Keys){
    $p=Join-Path $Path $name
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){$files[$name]=[ordered]@{exists=$false;ok=$false};$errors+=('MISSING_FILE:'+ $name);continue}
    $f=Get-Item -LiteralPath $p; $sha=Hash $p; $exp=$Expected[$name]
    $match=([int64]$f.Length-eq[int64]$exp.bytes -and $sha-eq[string]$exp.sha256)
    $files[$name]=[ordered]@{exists=$true;bytes=[int64]$f.Length;sha256=$sha;expectedBytes=[int64]$exp.bytes;expectedSha256=[string]$exp.sha256;ok=$match}
    if(-not$match){$errors+=('FINGERPRINT_MISMATCH:'+ $name)}
  }
  return [ordered]@{path=$Path;exists=$true;ok=($errors.Count-eq0);manifestName=$(if($manifest){[string]$manifest.name}else{''});manifestVersion=$(if($manifest){[string]$manifest.version}else{''});architecture='content_script_plus_popup';files=$files;errors=$errors}
}

$checked=@();$pass=$null
foreach($path in @(CandidatePaths)){
  $r=Inspect $path;$checked+=$r
  if(-not$pass -and $r.ok){$pass=$r}
}
$ok=[bool]$pass
$result=[ordered]@{
  ok=$ok
  action='FLOW_CANONICAL_EXTENSION_FINGERPRINT_V1'
  expectedName=$ExpectedName
  expectedVersion=$ExpectedVersion
  expectedExtensionId=$ExpectedExtensionId
  canonicalDriveFolderId='14BcD6HVwI082uTY5ecy_L1ZOGHuVgYvb'
  selectedPath=$(if($pass){[string]$pass.path}else{''})
  checked=$checked
  policy=[ordered]@{sameVersionDifferentCoreFiles='HOLD';permissionExpansion='USER_GATE';duplicateInstall=$false;flowV8IsExecutionSequence=$true}
  generateClicked=$false
  creditSpend=$false
  oauthChanged=$false
  checkedAt=(Get-Date).ToString('o')
}
$central=FindCentral
if($central){
  $dir=Join-Path $central 'Runtime_Readback\Flow_Bridge_Direct';New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $dir 'FLOW_CANONICAL_EXTENSION_FINGERPRINT_V1.json') -Encoding UTF8
}
$result|ConvertTo-Json -Depth 30 -Compress
if($ok){exit 0}else{exit 2}
