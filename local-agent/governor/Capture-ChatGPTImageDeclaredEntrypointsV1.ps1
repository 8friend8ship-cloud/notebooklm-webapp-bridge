param(
  [string]$CentralRootOverride = 'G:\내 드라이브\00_중앙에이전트'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
$manifestReceipt=Join-Path $runtimeDir 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json'
$outDir=Join-Path $runtimeDir 'CHATGPT_IMAGE_DECLARED_ENTRYPOINTS_V1'
$receiptPath=Join-Path $runtimeDir 'CHATGPT_IMAGE_DECLARED_ENTRYPOINTS_V1.json'

function Write-Receipt([hashtable]$body){
  New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null
  $body.generatedAt=(Get-Date).ToString('o')
  $body|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $receiptPath -Encoding UTF8
  Write-Output ($body|ConvertTo-Json -Depth 30 -Compress)
}

if(-not(Test-Path -LiteralPath $manifestReceipt -PathType Leaf)){
  Write-Receipt @{ok=$false;status='HOLD_MANIFEST_RECEIPT_MISSING';normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false;creditsSpent=$false}
  exit 2
}
$m=Get-Content -LiteralPath $manifestReceipt -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $m.ok){
  Write-Receipt @{ok=$false;status='HOLD_MANIFEST_INSPECT_NOT_OK';normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false;creditsSpent=$false}
  exit 3
}
$root=[string]$m.extensionPath
if(-not $root -or -not(Test-Path -LiteralPath $root -PathType Container)){
  Write-Receipt @{ok=$false;status='HOLD_EXTENSION_PATH_MISSING';extensionPath=$root;normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false;creditsSpent=$false}
  exit 4
}

$targets=New-Object System.Collections.Generic.List[string]
if($m.serviceWorker){[void]$targets.Add([string]$m.serviceWorker)}
foreach($cs in @($m.contentScripts)){foreach($js in @($cs.js)){if($js){[void]$targets.Add([string]$js)}}}
$side=[string]$m.sidePanelDefaultPath
if($side){[void]$targets.Add($side)}
$targets=@($targets|Select-Object -Unique)
if($targets.Count -eq 0){
  Write-Receipt @{ok=$false;status='HOLD_NO_DECLARED_ENTRYPOINTS';normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false;creditsSpent=$false}
  exit 5
}

New-Item -ItemType Directory -Force -Path $outDir|Out-Null
$captured=New-Object System.Collections.Generic.List[object]
$sideLocalScripts=New-Object System.Collections.Generic.List[string]
foreach($rel in $targets){
  $src=Join-Path $root $rel
  if(-not(Test-Path -LiteralPath $src -PathType Leaf)){
    Write-Receipt @{ok=$false;status='HOLD_DECLARED_ENTRYPOINT_MISSING';missing=$rel;normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false;creditsSpent=$false}
    exit 6
  }
  $safeName=($rel -replace '[\\/:*?"<>|]','__')
  $dst=Join-Path $outDir $safeName
  Copy-Item -LiteralPath $src -Destination $dst -Force
  $item=Get-Item -LiteralPath $dst
  $sha=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLowerInvariant()
  [void]$captured.Add([pscustomobject]@{relativePath=$rel;copiedPath=$dst;bytes=$item.Length;sha256=$sha})
  if($side -and $rel -eq $side -and ([IO.Path]::GetExtension($rel) -match '^\.html?$')){
    $html=Get-Content -LiteralPath $src -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($html,'<script[^>]+src=["'"']([^"'"']+)["'"']','IgnoreCase')){
      $v=[string]$match.Groups[1].Value
      if($v -and $v -notmatch '^(https?:|//|data:|chrome-extension:)') {[void]$sideLocalScripts.Add($v)}
    }
  }
}
foreach($rel in @($sideLocalScripts|Select-Object -Unique)){
  $base=Split-Path -Parent $side
  $resolvedRel=if($base){Join-Path $base $rel}else{$rel}
  $src=Join-Path $root $resolvedRel
  if(Test-Path -LiteralPath $src -PathType Leaf){
    $safeName=($resolvedRel -replace '[\\/:*?"<>|]','__')
    $dst=Join-Path $outDir $safeName
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $item=Get-Item -LiteralPath $dst
    $sha=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$captured.Add([pscustomobject]@{relativePath=$resolvedRel;copiedPath=$dst;bytes=$item.Length;sha256=$sha;discoveredFrom='sidePanelScriptSrc'})
  }
}
Write-Receipt @{
  ok=$true
  status='DECLARED_ENTRYPOINTS_CAPTURED'
  extensionId=[string]$m.extensionId
  version=[string]$m.extensionVersion
  captured=@($captured)
  policy='READ_ONLY_DECLARED_EXTENSION_FILES_ONLY'
  prohibitions=@('NO_PREFERENCES','NO_SECURE_PREFERENCES','NO_COOKIES','NO_TOKENS','NO_HISTORY','NO_REINSTALL','NO_GENERATE')
  normalChromeTouched=$false
  extensionMutated=$false
  generateClicked=$false
  creditsSpent=$false
}
exit 0
