param(
  [string]$CentralRootOverride = 'G:\내 드라이브\00_중앙에이전트'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
$out=Join-Path $runtimeDir 'CHATGPT_IMAGE_AUTOMATION_PROBE_V1.json'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestScript=Join-Path $repoRoot 'local-agent\governor\Inspect-ChatGPTImageAutoManifestV1.ps1'
$captureScript=Join-Path $repoRoot 'local-agent\governor\Capture-ChatGPTImageDeclaredEntrypointsV1.ps1'
$analyzeScript=Join-Path $repoRoot 'local-agent\governor\Analyze-ChatGPTImageEntrypointContractV1.ps1'
function Save([hashtable]$b){New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null;$b.at=(Get-Date).ToString('o');$b|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $out -Encoding UTF8;Write-Output ($b|ConvertTo-Json -Depth 30 -Compress)}
$missing=@($manifestScript,$captureScript,$analyzeScript|Where-Object{-not(Test-Path -LiteralPath $_ -PathType Leaf)})
if($missing.Count){Save @{ok=$false;status='HOLD_REQUIRED_SCRIPT_MISSING';missing=$missing;generateClicked=$false;creditsSpent=$false};exit 2}
$steps=@()
foreach($s in @($manifestScript,$captureScript,$analyzeScript)){
  $text=& pwsh -NoProfile -ExecutionPolicy Bypass -File $s -CentralRootOverride $CentralRootOverride 2>&1 | Out-String
  $rc=$LASTEXITCODE
  $steps += [pscustomobject]@{script=[IO.Path]::GetFileName($s);exitCode=$rc;output=$text.Trim()}
  if($rc -ne 0){Save @{ok=$false;status='HOLD_PROBE_STEP_FAILED';steps=$steps;failedScript=[IO.Path]::GetFileName($s);generateClicked=$false;creditsSpent=$false};exit $rc}
}
$contract=Join-Path $runtimeDir 'CHATGPT_IMAGE_ENTRYPOINT_CONTRACT_V1.json'
$c=$null
if(Test-Path -LiteralPath $contract -PathType Leaf){$c=Get-Content -LiteralPath $contract -Raw -Encoding UTF8|ConvertFrom-Json}
Save @{ok=($null -ne $c -and $c.ok);status=$(if($c -and $c.ok){'AUTOMATION_CONTRACT_PROBE_PASS'}else{'HOLD_CONTRACT_NOT_READY'});steps=$steps;contract=$c;next='BIND_EXACT_MESSAGE_STORAGE_DOWNLOAD_INTERFACE_THEN_GENERATE_FIXTURE';generateClicked=$false;creditsSpent=$false;extensionMutated=$false;normalChromeTouched=$false}
if($c -and $c.ok){exit 0}else{exit 5}
