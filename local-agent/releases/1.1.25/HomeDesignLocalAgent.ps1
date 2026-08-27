param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.25'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$Agent122File=Join-Path $Root 'HomeDesignLocalAgent-1.1.22.ps1'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$RecoveryFile=Join-Path $Root 'AGENT_1.1.25_RECOVERY.json'
$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.4/HomeDesignLocalCommandHost.ps1'
$HostExpected='01cee0022b14748f638ee245d8632c1ff3ecde6e'
$Agent122Url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.22/HomeDesignLocalAgent.ps1'
$Agent122Expected='8eb558717939ea6ecb95725dfbaa2656692d8e58'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){
  $b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length)
  [Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length)
  $s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}
}
function Refresh([string]$Url,[string]$Path,[string]$Expected){
  $tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30
  $actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "SHA_MISMATCH path=$Path actual=$actual expected=$Expected"}
  Move-Item $tmp $Path -Force
}
function HostHealth{try{return Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{return $null}}
function StopHost{
  try{foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -match 'HomeDesignLocalCommandHost'})){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}}catch{}
}
function StartHost124{
  $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$HostFile+'"'))
  Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden|Out-Null
  $deadline=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 500;$h=HostHealth;if($h -and [bool]$h.ok -and [string]$h.version -eq '1.2.4' -and [bool]$h.asyncJobs){return $h}}while((Get-Date)-lt $deadline)
  throw 'HOST_1.2.4_START_FAILED'
}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}};return ''
}
function PromoteState{
  if(-not(Test-Path -LiteralPath $StateFile)){return $false}
  try{$s=Get-Content $StateFile -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $false}
  if($s.PSObject.Properties.Name -contains 'agentVersion'){$s.agentVersion=$AgentVersion}else{$s|Add-Member -NotePropertyName agentVersion -NotePropertyValue $AgentVersion}
  if($s.PSObject.Properties.Name -contains 'agentMode'){$s.agentMode='HOST_124_NLM_DOWNLOAD_INSPECT_ALLOWLIST_1.1.25'}else{$s|Add-Member -NotePropertyName agentMode -NotePropertyValue 'HOST_124_NLM_DOWNLOAD_INSPECT_ALLOWLIST_1.1.25'}
  if($s.PSObject.Properties.Name -contains 'commandHostVersion'){$s.commandHostVersion='1.2.4'}else{$s|Add-Member -NotePropertyName commandHostVersion -NotePropertyValue '1.2.4'}
  if($s.PSObject.Properties.Name -contains 'hostHealthy'){$s.hostHealthy=$true}else{$s|Add-Member -NotePropertyName hostHealthy -NotePropertyValue $true}
  if($s.PSObject.Properties.Name -contains 'hostAsyncJobs'){$s.hostAsyncJobs=$true}else{$s|Add-Member -NotePropertyName hostAsyncJobs -NotePropertyValue $true}
  if($s.PSObject.Properties.Name -contains 'updatedAt'){$s.updatedAt=(Get-Date).ToString('o')}else{$s|Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date).ToString('o')}
  $json=$s|ConvertTo-Json -Depth 30;$json|Set-Content -LiteralPath $StateFile -Encoding UTF8;$json|Set-Content -LiteralPath $ReadbackFile -Encoding UTF8
  $central=FindCentral;if($central){try{$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}catch{}}
  return $true
}

$r=[ordered]@{action='AGENT_1.1.25_HOST_124_NLM_DOWNLOAD_INSPECT_ALLOWLIST';startedAt=(Get-Date).ToString('o');recovery122Exit=$null;hostBlobExpected=$HostExpected;hostRefreshed=$false;hostHealthy=$false;statePromoted=$false;ok=$false;error=''}
try{
  Refresh $Agent122Url $Agent122File $Agent122Expected
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Agent122File
  $r.recovery122Exit=$LASTEXITCODE
  Refresh $HostUrl $HostFile $HostExpected;$r.hostRefreshed=$true
  StopHost;Start-Sleep -Milliseconds 700;$h=StartHost124;$r.hostHealthy=[bool]$h.ok
  $h2=HostHealth;if(-not($h2 -and [bool]$h2.ok -and [string]$h2.version -eq '1.2.4' -and [bool]$h2.asyncJobs)){throw 'HOST_1.2.4_NOT_HEALTHY'}
  $r.statePromoted=PromoteState
  $r.ok=$true
}catch{$r.error=$_.Exception.Message;$r.ok=$false}
$r.completedAt=(Get-Date).ToString('o')
$r|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $RecoveryFile -Encoding UTF8
if($r.ok){exit 0}else{exit 2}