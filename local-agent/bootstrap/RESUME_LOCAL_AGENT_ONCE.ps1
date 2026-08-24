param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$StateFile=Join-Path $Root 'state.json'
$BootstrapUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/AgentBootstrap.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function Proc([string]$Needle){
  try{return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}
}
# NOTE: $PID is a read-only automatic variable in Windows PowerShell.
# Never use $Pid/$PID as a parameter or assignment target here.
function KillTree([int]$ProcessId){
  try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}
  catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}
}
function StopTarget([string]$Needle){foreach($procItem in @(Proc $Needle)){KillTree -ProcessId ([int]$procItem.ProcessId)}}

Write-Host 'HomeDesign Local Agent - SAFE RESUME'
Write-Host 'Normal Chrome / OAuth / Apps Script / extension data will not be changed.'

StopTarget 'RunChromeGovernorReadback.ps1'
StopTarget 'HomeDesignLocalCommandHost.ps1'
StopTarget 'AgentBootstrap.ps1'
Start-Sleep -Seconds 1

$tmp=$Bootstrap+'.download'
Invoke-WebRequest -UseBasicParsing -Uri $BootstrapUrl -OutFile $tmp -TimeoutSec 60
Move-Item -LiteralPath $tmp -Destination $Bootstrap -Force

Start-Process -FilePath 'powershell.exe' -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop'
) -WindowStyle Hidden

Write-Host 'Bootstrap restarted. Waiting for stable v1.1.4 / TcpListener host v1.1.4...'
$deadline=(Get-Date).AddSeconds(150)
$last=$null
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 3
  if(Test-Path -LiteralPath $StateFile){
    try{
      $last=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json
      $av=[string]$last.agentVersion;$hv=[string]$last.commandHostVersion;$hr=[bool]$last.commandHostRunning
      Write-Host ("agent="+$av+" host="+$hv+" hostRunning="+$hr+" bridge="+[string]$last.installedVersion+" status="+[string]$last.status)
      if($av -eq '1.1.4' -and $hv -eq '1.1.4' -and $hr){
        Write-Host 'RESUME RESULT: ACTIVE'
        Write-Host 'The queued Chrome Governor readback will continue automatically through the localhost TcpListener host.'
        exit 0
      }
    }catch{}
  }
}
Write-Host 'RESUME RESULT: STARTED, READBACK STILL PENDING'
Write-Host 'Do not reinstall. Keep this window result and let the central queue continue.'
exit 2
