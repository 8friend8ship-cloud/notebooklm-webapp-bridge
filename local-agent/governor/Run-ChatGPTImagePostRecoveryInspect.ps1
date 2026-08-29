param(
  [string]$CentralRootOverride='G:\내 드라이브\00_중앙에이전트'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Api='https://api.github.com/repos/'+$Repo+'/contents'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$headers=@{'User-Agent'='HomeDesign-ChatGPTImage-PostRecovery';'Accept'='application/vnd.github+json'}
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Get-ApiFile([string]$path){Invoke-RestMethod -Uri ($Api+'/'+$path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -TimeoutSec 30}
$stable=Get-ApiFile 'local-agent/stable/agent.json'
$stableJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$stable.content -replace '\s',''))) | ConvertFrom-Json
if(-not $stableJson.enabled){throw 'STABLE_AGENT_DISABLED'}
$version=[string]$stableJson.version
$expected=[string]$stableJson.gitBlobSha1
$meta=Get-ApiFile ('local-agent/releases/'+$version+'/HomeDesignLocalAgent.ps1')
if(([string]$meta.sha).ToLowerInvariant() -ne $expected.ToLowerInvariant()){throw 'STABLE_AGENT_SHA_MISMATCH'}
$agent=Join-Path $Root ('HomeDesignLocalAgent-'+$version+'-postinspect.ps1')
[IO.File]::WriteAllBytes($agent,[Convert]::FromBase64String(([string]$meta.content -replace '\s','')))
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $agent
$agentRc=$LASTEXITCODE
if($agentRc -ne 0){throw ('STABLE_AGENT_EXIT_'+$agentRc)}
$inspMeta=Get-ApiFile 'local-agent/governor/Inspect-ChatGPTImageAutoManifest.ps1'
$insp=Join-Path $Root 'Inspect-ChatGPTImageAutoManifest.ps1'
[IO.File]::WriteAllBytes($insp,[Convert]::FromBase64String(([string]$inspMeta.content -replace '\s','')))
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $insp -CentralRootOverride $CentralRootOverride
$inspectRc=$LASTEXITCODE
$manifestLocal=Join-Path $Root 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json'
$manifestCentral=$null
if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride -PathType Container)){
  $runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
  New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null
  $manifestCentral=Join-Path $runtimeDir 'CHATGPT_IMAGE_AUTO_MANIFEST_INSPECT.json'
}
$manifestOk=(Test-Path -LiteralPath $manifestLocal -PathType Leaf)
$receipt=[ordered]@{ok=($agentRc -eq 0 -and $inspectRc -eq 0 -and $manifestOk);stableAgent=$version;stableAgentSha=$expected;agentRc=$agentRc;inspectRc=$inspectRc;manifestLocal=$manifestLocal;manifestCentral=$manifestCentral;manifestReceiptExists=$manifestOk;normalChromeTouched=$false;oauthChanged=$false;generateClicked=$false;creditSpend=$false;at=(Get-Date).ToString('o')}
$out=Join-Path $Root 'CHATGPT_IMAGE_POST_RECOVERY_INSPECT.json'
$receipt|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $out -Encoding UTF8
if($CentralRootOverride -and (Test-Path -LiteralPath $CentralRootOverride -PathType Container)){
  $runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
  $receipt|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $runtimeDir 'CHATGPT_IMAGE_POST_RECOVERY_INSPECT.json') -Encoding UTF8
}
$receipt|ConvertTo-Json -Depth 20 -Compress
if($receipt.ok){exit 0}else{exit 2}
