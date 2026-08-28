param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$ExpectedAgent='1.1.46'
$ExpectedAgentBlob='b72e57af70f77578fddb3de49f6581a37e2de792'
$ExpectedV2Blob='a4b7967da7bc26f3cb49c88d3b3cb122ddf86c7c'
$ExpectedPowerBlob='3edde1fe1276052a084380a84fe27a2b2574e9ef'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$V2=Join-Path $Root 'RunChromeGovernorReadbackV2.ps1'
$PowerHelper=Join-Path $Root 'Setup-PowerContinuity.ps1'
$LocalReceipt=Join-Path $Root 'PERSONA_BIND_DEVICE_RECOVERY_ONCE.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path)
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[] ($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}
  finally{$s.Dispose()}
}
function GitHubContent([string]$Path){
  $headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'}
  return Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -Method Get -TimeoutSec 20
}
function FetchPinned([string]$Path,[string]$Destination,[string]$ExpectedBlob){
  $resp=GitHubContent $Path
  $tmp=$Destination+'.recovery.download'
  [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$resp.content -replace '\s','')))
  $sha=(GitBlobSha1 $tmp).ToLowerInvariant()
  if($sha -ne $ExpectedBlob.ToLowerInvariant()){
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw ('PINNED_BLOB_MISMATCH:'+ $Path + ':' + $sha)
  }
  Move-Item -LiteralPath $tmp -Destination $Destination -Force
}
function WriteReceipt($obj){
  $json=$obj|ConvertTo-Json -Depth 30
  $json|Set-Content -LiteralPath $LocalReceipt -Encoding UTF8
  try{
    $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    $myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
    foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
      if(-not $drv.Root){continue}
      foreach($cand in @((Join-Path $drv.Root $centralName),(Join-Path $drv.Root ($myDriveKo+'\'+$centralName)),(Join-Path $drv.Root ('My Drive\'+$centralName)),(Join-Path $drv.Root ('Google Drive\'+$centralName)))){
        if(Test-Path -LiteralPath $cand -PathType Container){
          $dest=Join-Path $cand 'Runtime_Readback'
          New-Item -ItemType Directory -Force -Path $dest|Out-Null
          $json|Set-Content -LiteralPath (Join-Path $dest 'PERSONA_BIND_DEVICE_RECOVERY_ONCE.json') -Encoding UTF8
          return
        }
      }
    }
  }catch{}
}

$receipt=[ordered]@{
  ok=$false
  action='PINNED_PERSONA_BIND_DEVICE_RECOVERY_ONCE'
  expectedAgent=$ExpectedAgent
  expectedAgentBlob=$ExpectedAgentBlob
  expectedV2Blob=$ExpectedV2Blob
  expectedPowerBlob=$ExpectedPowerBlob
  nightStart='02:00'
  nightEnd='05:00'
  powerContinuity=$null
  newProjectCreated=$false
  oauthChanged=$false
  scopeChanged=$false
  newDeployment=$false
  newTrigger=$false
  paidGeminiApiCalled=$false
  startedAt=(Get-Date).ToString('o')
  stage='INIT'
  output=''
  error=''
}
try{
  $receipt.stage='VERIFY_STABLE_MANIFEST'
  $meta=GitHubContent 'local-agent/stable/agent.json'
  $metaJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$meta.content -replace '\s','')))|ConvertFrom-Json
  if([string]$metaJson.version -ne $ExpectedAgent){throw ('STABLE_AGENT_CHANGED:'+[string]$metaJson.version)}
  if(([string]$metaJson.gitBlobSha1).ToLowerInvariant() -ne $ExpectedAgentBlob){throw 'STABLE_AGENT_BLOB_CHANGED'}

  $receipt.stage='FETCH_V2_API_HELPER'
  FetchPinned 'local-agent/governor/RunChromeGovernorReadbackV2.ps1' $V2 $ExpectedV2Blob

  $receipt.stage='KICK_EXACT_STABLE_AGENT'
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try{$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $V2 -KickStableAgent 2>&1|Out-String;$rc=$LASTEXITCODE}
  finally{$ErrorActionPreference=$old}
  $receipt.output=$out.Trim()
  if($rc -ne 0){throw ('KICK_EXIT_'+$rc)}
  $parsed=$null
  foreach($line in @($out -split "`r?`n")){
    if(-not $line -or -not $line.Trim()){continue}
    try{$candidate=$line.Trim()|ConvertFrom-Json;if($candidate -and $null -ne $candidate.ok){$parsed=$candidate}}catch{}
  }
  if(-not $parsed -or -not [bool]$parsed.ok){throw 'KICK_NO_PASS_JSON'}
  if([string]$parsed.targetAgent -and [string]$parsed.targetAgent -ne $ExpectedAgent){throw ('KICK_TARGET_MISMATCH:'+[string]$parsed.targetAgent)}

  $receipt.stage='INSTALL_POWER_CONTINUITY_0200_0500'
  FetchPinned 'local-agent/capture/Setup-PowerContinuity.ps1' $PowerHelper $ExpectedPowerBlob
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try{$powerOut=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PowerHelper -Install -NightStart '02:00' -NightEnd '05:00' 2>&1|Out-String;$powerRc=$LASTEXITCODE}
  finally{$ErrorActionPreference=$old}
  if($powerRc -ne 0){throw ('POWER_CONTINUITY_EXIT_'+$powerRc+':'+$powerOut.Trim())}
  $powerParsed=$null
  foreach($line in @($powerOut -split "`r?`n")){
    if(-not $line -or -not $line.Trim()){continue}
    try{$candidate=$line.Trim()|ConvertFrom-Json;if($candidate -and $null -ne $candidate.ok){$powerParsed=$candidate}}catch{}
  }
  if(-not $powerParsed -or -not [bool]$powerParsed.ok){throw ('POWER_CONTINUITY_NO_PASS_JSON:'+ $powerOut.Trim())}
  if([string]$powerParsed.nightStart -ne '02:00' -or [string]$powerParsed.nightEnd -ne '05:00'){throw 'POWER_CONTINUITY_WINDOW_MISMATCH'}
  $receipt.powerContinuity=$powerParsed

  $receipt.stage='AGENT_KICK_AND_POWER_CONTINUITY_PASS'
  $receipt.ok=$true
  $receipt.completedAt=(Get-Date).ToString('o')
  WriteReceipt $receipt
  Write-Host ($receipt|ConvertTo-Json -Depth 30 -Compress)
  exit 0
}catch{
  $receipt.error=$_.Exception.Message
  $receipt.completedAt=(Get-Date).ToString('o')
  WriteReceipt $receipt
  Write-Host ($receipt|ConvertTo-Json -Depth 30 -Compress)
  exit 2
}
