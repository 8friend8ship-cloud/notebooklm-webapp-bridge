param(
  [string]$CentralRootOverride = 'G:\내 드라이브\00_중앙에이전트'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
$captureReceipt=Join-Path $runtimeDir 'CHATGPT_IMAGE_DECLARED_ENTRYPOINTS_V1.json'
$out=Join-Path $runtimeDir 'CHATGPT_IMAGE_ENTRYPOINT_CONTRACT_V1.json'
function Write-Receipt([hashtable]$body){
  New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null
  $body.generatedAt=(Get-Date).ToString('o')
  $body|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $out -Encoding UTF8
  Write-Output ($body|ConvertTo-Json -Depth 30 -Compress)
}
if(-not(Test-Path -LiteralPath $captureReceipt -PathType Leaf)){
  Write-Receipt @{ok=$false;status='HOLD_ENTRYPOINT_CAPTURE_MISSING';normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false}
  exit 2
}
$r=Get-Content -LiteralPath $captureReceipt -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $r.ok -or $r.status -ne 'DECLARED_ENTRYPOINTS_CAPTURED'){
  Write-Receipt @{ok=$false;status='HOLD_ENTRYPOINT_CAPTURE_NOT_READY';normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false}
  exit 3
}
$files=@($r.captured|Where-Object{$_.copiedPath -and (Test-Path -LiteralPath $_.copiedPath -PathType Leaf)})
if($files.Count -eq 0){
  Write-Receipt @{ok=$false;status='HOLD_CAPTURED_FILES_MISSING';normalChromeTouched=$false;extensionMutated=$false;generateClicked=$false}
  exit 4
}
$findings=New-Object System.Collections.Generic.List[object]
foreach($f in $files){
  $ext=[IO.Path]::GetExtension([string]$f.copiedPath).ToLowerInvariant()
  if($ext -notin @('.js','.mjs','.html','.htm')){continue}
  $text=Get-Content -LiteralPath ([string]$f.copiedPath) -Raw -Encoding UTF8
  $patterns=[ordered]@{
    runtimeOnMessage='chrome\.runtime\.onMessage(?:External)?\.addListener'
    runtimeSendMessage='chrome\.runtime\.sendMessage'
    tabsSendMessage='chrome\.tabs\.sendMessage'
    storageLocal='chrome\.storage\.local'
    storageSync='chrome\.storage\.sync'
    storageSession='chrome\.storage\.session'
    downloads='chrome\.downloads\.'
    sidePanel='chrome\.sidePanel\.'
    alarms='chrome\.alarms\.'
    scripting='chrome\.scripting\.'
  }
  $hits=[ordered]@{}
  foreach($k in $patterns.Keys){$hits[$k]=[regex]::Matches($text,$patterns[$k],[System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count}
  $stringCandidates=@([regex]::Matches($text,'["'']([A-Za-z0-9_.:-]{3,80})["'']')|ForEach-Object{$_.Groups[1].Value}|Where-Object{$_ -match '(queue|prompt|image|download|task|status|storage|message|generate|ratio|model|count|file)' }|Select-Object -Unique -First 200)
  [void]$findings.Add([pscustomobject]@{relativePath=[string]$f.relativePath;sha256=[string]$f.sha256;bytes=[int64]$f.bytes;apiHits=$hits;stringCandidates=$stringCandidates})
}
$findingsArray=[object[]]$findings.ToArray()
$totalMessage=0;$totalStorage=0
foreach($f in $findingsArray){
  $totalMessage += [int]$f.apiHits.runtimeOnMessage+[int]$f.apiHits.runtimeSendMessage+[int]$f.apiHits.tabsSendMessage
  $totalStorage += [int]$f.apiHits.storageLocal+[int]$f.apiHits.storageSync+[int]$f.apiHits.storageSession
}
$status=if($totalMessage -gt 0 -or $totalStorage -gt 0){'CONTRACT_CANDIDATES_FOUND'}else{'HOLD_NO_RUNTIME_OR_STORAGE_CONTRACT_FOUND'}
Write-Receipt @{
  ok=($status -eq 'CONTRACT_CANDIDATES_FOUND')
  status=$status
  extensionId=[string]$r.extensionId
  version=[string]$r.version
  files=$findingsArray
  runtimeMessageHitCount=$totalMessage
  storageHitCount=$totalStorage
  analysisPolicy='STATIC_CAPTURED_ENTRYPOINTS_ONLY_NO_EXECUTION'
  next='MANUAL_MACHINE_READABLE_CONTRACT_CONFIRMATION_BEFORE_ADAPTER_EXECUTION'
  prohibitions=@('NO_CODE_EXECUTION_FROM_EXTENSION','NO_BROWSER_PROFILE_READ','NO_COOKIE_TOKEN_PASSWORD_READ','NO_GENERATE','NO_EXTENSION_MUTATION')
  normalChromeTouched=$false
  extensionMutated=$false
  generateClicked=$false
}
if($status -eq 'CONTRACT_CANDIDATES_FOUND'){exit 0}else{exit 5}
