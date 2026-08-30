param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.100'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Helper=Join-Path $Root 'DiagnoseNotebookLMAutoPoll.ps1'
$Sentinel=Join-Path $Root 'AGENT_1.1.100_WAKE_ONCE.done'
$Stdout=Join-Path $Root 'AGENT_1.1.100.stdout.log'
$Stderr=Join-Path $Root 'AGENT_1.1.100.stderr.log'
$ExpectedSha='d035e37d8093a07737a7e7ada16e36e5959c4d9d'
$Raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/DiagnoseNotebookLMAutoPoll.ps1'
New-Item -ItemType Directory -Force -Path $Root | Out-Null
function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path)
  $h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
  $a=New-Object byte[]($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length)
  [Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create()
  try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function FindCentral {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  $my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root
    if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c -PathType Container){return $c}
    }
  }
  return ''
}
function SaveCentral([string]$Name,$Object){
  try{
    $j=$Object | ConvertTo-Json -Depth 60
    $j | Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8
    $c=FindCentral
    if($c){
      $d=Join-Path $c 'Runtime_Readback'
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      $p=Join-Path $d $Name
      $j | Set-Content -LiteralPath $p -Encoding UTF8
      return $p
    }
  }catch{}
  return ''
}
$result=[ordered]@{
  ok=$false
  action='AGENT_1.1.100_RUN_EXISTING_AUTO_POLL_DIAGNOSTIC_ONCE'
  version=$Version
  startedAt=(Get-Date).ToString('o')
  helperSha=$ExpectedSha
  helperFetch=''
  alreadyExecuted=$false
  helperExit=$null
  helperResult=$null
  serviceWorkerFound=$false
  bridgeVersion=''
  normalChromeTouched=$false
  bridgeChanged=$false
  oauthChanged=$false
  scopeChanged=$false
  queueTaskCreated=$false
  error=''
  centralPath=''
}
try{
  if(Test-Path -LiteralPath $Sentinel){
    $result.alreadyExecuted=$true
    $result.ok=$true
  } else {
    if((Test-Path -LiteralPath $Helper) -and ((GitBlobSha1 $Helper).ToLowerInvariant() -eq $ExpectedSha)){
      $result.helperFetch='LOCAL_VERIFIED'
    } else {
      Invoke-WebRequest -UseBasicParsing -Uri ($Raw+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Helper -TimeoutSec 30
      $actual=(GitBlobSha1 $Helper).ToLowerInvariant()
      if($actual -ne $ExpectedSha){throw ('HELPER_SHA_MISMATCH actual='+$actual)}
      $result.helperFetch='RAW_VERIFIED'
    }
    $tok=$null;$pe=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Helper,[ref]$tok,[ref]$pe)
    if($pe.Count){throw ('HELPER_PARSE_FAIL '+(($pe|ForEach-Object{$_.Message})-join' | '))}
    Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
    $p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$Helper+'"')) -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden
    if(-not $p.WaitForExit(90000)){try{$p.Kill()}catch{};throw 'DIAGNOSTIC_TIMEOUT_90S'}
    $result.helperExit=[int]$p.ExitCode
    $out=''
    if(Test-Path -LiteralPath $Stdout){$out=Get-Content -LiteralPath $Stdout -Raw -Encoding UTF8}
    if(Test-Path -LiteralPath $Stderr){$e=Get-Content -LiteralPath $Stderr -Raw -Encoding UTF8;if($e){$out+="`n"+$e}}
    $payload=$null
    foreach($line in @($out -split "`r?`n" | Where-Object {$_.Trim()} | Select-Object -Last 30)){
      try{$j=$line|ConvertFrom-Json;if($j){$payload=$j}}catch{}
    }
    if(-not $payload){throw ('DIAGNOSTIC_RESULT_JSON_NOT_FOUND '+$out.Trim())}
    $result.helperResult=$payload
    $result.serviceWorkerFound=[bool]$payload.serviceWorkerFound
    $result.bridgeVersion=[string]$payload.bridgeVersion
    if(-not [bool]$payload.ok){throw ('DIAGNOSTIC_FAILED '+[string]$payload.error)}
    if(-not $result.serviceWorkerFound){throw 'SERVICE_WORKER_NOT_FOUND_AFTER_EXISTING_DIAGNOSTIC'}
    if($result.bridgeVersion -ne '0.2.39'){throw ('BRIDGE_VERSION_MISMATCH actual='+$result.bridgeVersion)}
    Set-Content -LiteralPath $Sentinel -Value ((Get-Date).ToString('o')) -Encoding ASCII
    $result.ok=$true
  }
}catch{
  $result.error=$_.Exception.Message
}
finally{
  $result.completedAt=(Get-Date).ToString('o')
  $result.centralPath=SaveCentral 'AGENT_1.1.100_RUN_EXISTING_AUTO_POLL_DIAGNOSTIC_ONCE_RESULT.json' $result
}
$result | ConvertTo-Json -Depth 60 -Compress
if($result.ok){exit 0}else{exit 2}
