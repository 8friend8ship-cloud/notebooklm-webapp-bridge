param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$AgentFile=Join-Path $Root 'HomeDesignLocalAgent.ps1'
$StateFile=Join-Path $Root 'state.json'
$BootstrapUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/AgentBootstrap.ps1'
$AgentMetaUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/stable/agent.json'
$AgentBaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases'
$BridgeReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function StopTarget([string]$Needle){foreach($procItem in @(Proc $Needle)){KillTree -ProcessId ([int]$procItem.ProcessId)}}
function GitBlobSha1([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0));$all=New-Object byte[] ($header.Length+$bytes.Length);[Buffer]::BlockCopy($header,0,$all,0,$header.Length);[Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length);$sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}}
function TestHostHealth(){try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$h.ok}catch{return $false}}
function Bust([string]$Url,[string]$Tag){$sep=if($Url.Contains('?')){'&'}else{'?'};return $Url+$sep+'hdcb='+[Uri]::EscapeDataString($Tag)}

Write-Host 'HomeDesign Local Agent - SAFE DIRECT RESUME'
Write-Host 'No reinstall / no new OAuth / no Apps Script redeploy / normal Chrome untouched.'

# Only stale governor/readback processes are cleaned. Healthy Host/Bootstrap stay alive.
StopTarget 'RunChromeGovernorReadback.ps1'
StopTarget 'ChromeExtensionGovernor.ps1'
StopTarget 'GovernorDriveSync.ps1'
Start-Sleep -Milliseconds 500

$nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
Write-Host '[1/5] Refreshing bootstrap without stopping the current loop...'
$tmp=$Bootstrap+'.download'
Invoke-WebRequest -UseBasicParsing -Uri (Bust $BootstrapUrl $nonce) -OutFile $tmp -TimeoutSec 60
Move-Item -LiteralPath $tmp -Destination $Bootstrap -Force

Write-Host '[2/5] Resolving current stable Agent + Bridge...'
$meta=Invoke-RestMethod -Uri (Bust $AgentMetaUrl ($nonce+'-agent')) -Method Get -TimeoutSec 30
$bridge=Invoke-RestMethod -Uri (Bust $BridgeReleaseUrl ($nonce+'-bridge')) -Method Get -TimeoutSec 30
if(-not $meta.enabled){throw 'Local Agent stable channel disabled.'}
if(-not $bridge.enabled){throw 'NotebookLM bridge stable channel disabled.'}
$targetAgent=[string]$meta.version
$targetBridge=[string]$bridge.version
Write-Host ("targetAgent="+$targetAgent+" targetBridge="+$targetBridge)

Write-Host '[3/5] Downloading and SHA-verifying stable Agent...'
$agentTmp=$AgentFile+'.resume.download'
$expectedSha=([string]$meta.gitBlobSha1).ToLowerInvariant()
$agentUrl=Bust ("$AgentBaseUrl/$targetAgent/HomeDesignLocalAgent.ps1") ($expectedSha+'-'+$nonce)
Invoke-WebRequest -UseBasicParsing -Uri $agentUrl -OutFile $agentTmp -TimeoutSec 60
$actualSha=GitBlobSha1 $agentTmp
if($actualSha -ne $expectedSha){Remove-Item $agentTmp -Force -ErrorAction SilentlyContinue;throw "Agent SHA mismatch: actual=$actualSha expected=$expectedSha"}
Move-Item -LiteralPath $agentTmp -Destination $AgentFile -Force

Write-Host '[4/5] Applying stable Agent directly...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AgentFile
$directExit=$LASTEXITCODE
Write-Host ("directAgentExit="+$directExit)

Write-Host '[5/5] Ensuring future bootstrap loop...'
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop') -WindowStyle Hidden

$deadline=(Get-Date).AddSeconds(180)
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 3
  if(Test-Path -LiteralPath $StateFile){
    try{
      $last=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json
      $av=[string]$last.agentVersion;$hv=[string]$last.commandHostVersion;$hr=TestHostHealth;$bv=[string]$last.extensionVersion
      if(-not $bv){$bv=[string]$last.installedVersion}
      $gov=[bool]$last.governorCycleOk;$sync=[bool]$last.governorDriveSyncOk
      Write-Host ("agent="+$av+" host="+$hv+" hostHealth="+$hr+" bridge="+$bv+" status="+[string]$last.status+" governor="+$gov+" driveSync="+$sync)
      if($av -eq $targetAgent -and $hr -and $bv -eq $targetBridge -and $gov -and $sync){
        Write-Host 'RESUME RESULT: ACTIVE + GOVERNOR VERIFIED'
        exit 0
      }
      if($av -eq $targetAgent -and $hr -and $bv -eq $targetBridge -and $directExit -eq 0){
        Write-Host 'RESUME RESULT: ACTIVE; GOVERNOR READBACK STILL SYNCING'
        exit 0
      }
    }catch{}
  }
}
Write-Host 'RESUME RESULT: STARTED, RUNTIME READBACK STILL PENDING'
Write-Host 'Do not reinstall or reauthorize. Bootstrap remains enabled.'
exit 2
