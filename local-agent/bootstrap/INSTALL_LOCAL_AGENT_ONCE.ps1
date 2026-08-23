param()

$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap = Join-Path $Root 'AgentBootstrap.ps1'
$StatusScript = Join-Path $Root 'SHOW_LOCAL_AGENT_STATUS.ps1'
$StateFile = Join-Path $Root 'state.json'
$Desktop = [Environment]::GetFolderPath('Desktop')
if([string]::IsNullOrWhiteSpace($Desktop)){ $Desktop=Join-Path $env:USERPROFILE 'Desktop' }
$Startup = [Environment]::GetFolderPath('Startup')
New-Item -ItemType Directory -Force -Path $Root | Out-Null

Write-Host 'HomeDesign Local Agent - ONE TIME INSTALL'
Write-Host 'Normal ChatGPT Chrome will NOT be closed.'
Write-Host 'Only the dedicated Chrome for Testing may restart.'

try {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match 'powershell|pwsh' -and $_.CommandLine -and
      $_.CommandLine -like '*HomeDesignAutomationV7*LocalAgent*AgentBootstrap.ps1*'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 1
}catch{}

$sourceBootstrap = Join-Path $PSScriptRoot 'AgentBootstrap.ps1'
$sourceStatus = Join-Path $PSScriptRoot 'SHOW_LOCAL_AGENT_STATUS.ps1'
if (-not (Test-Path -LiteralPath $sourceBootstrap)) { throw 'AgentBootstrap.ps1 missing.' }
if (-not (Test-Path -LiteralPath $sourceStatus)) { throw 'SHOW_LOCAL_AGENT_STATUS.ps1 missing.' }
Copy-Item -LiteralPath $sourceBootstrap -Destination $Bootstrap -Force
Copy-Item -LiteralPath $sourceStatus -Destination $StatusScript -Force

$ws = New-Object -ComObject WScript.Shell
$startupLink = Join-Path $Startup 'HomeDesign Local Agent.lnk'
$sc = $ws.CreateShortcut($startupLink)
$sc.TargetPath = 'powershell.exe'
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Bootstrap`" -Loop"
$sc.WorkingDirectory = $Root
$sc.Description = 'HomeDesign Local Agent - central update, backup, test and rollback runner'
$sc.Save()

$statusLink = Join-Path $Desktop 'HomeDesign Local Agent Status.lnk'
$ss = $ws.CreateShortcut($statusLink)
$ss.TargetPath = 'powershell.exe'
$ss.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$StatusScript`""
$ss.WorkingDirectory = $Root
$ss.Description = 'HomeDesign Local Agent current state'
$ss.Save()

Start-Process -FilePath 'powershell.exe' -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$Bootstrap`"",'-Loop'
) -WindowStyle Hidden

Write-Host 'Local Agent started. Waiting for first central update cycle...'
$deadline=(Get-Date).AddMinutes(3)
$lastStatus=''
while((Get-Date)-lt $deadline){
  Start-Sleep -Seconds 3
  if(Test-Path -LiteralPath $StateFile){
    try{
      $state=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $lastStatus=[string]$state.status
      Write-Host ('state = ' + $lastStatus)
      if($lastStatus -in @('UPDATED_HEALTH_PASS','HEALTHY','NEEDS_USER_APPROVAL','ROLLED_BACK','CENTRAL_ROLLBACK_DONE','ROLLBACK_FAILED','UPDATE_FAILED')){break}
    }catch{}
  }
}

if($lastStatus -in @('UPDATED_HEALTH_PASS','HEALTHY')){
  Write-Host 'INSTALL RESULT: LOCAL AGENT ACTIVE'
  Write-Host 'From now on, stable bridge updates are automatic.'
}elseif($lastStatus -eq 'NEEDS_USER_APPROVAL'){
  Write-Host 'INSTALL RESULT: ACTIVE - USER APPROVAL REQUIRED FOR CURRENT RELEASE'
}elseif($lastStatus){
  Write-Host ('INSTALL RESULT: CHECK REQUIRED - ' + $lastStatus)
}else{
  Write-Host 'INSTALL RESULT: AGENT STARTED, FIRST CYCLE STILL RUNNING'
}
Write-Host ('Startup: ' + $startupLink)
Write-Host ('Agent root: ' + $Root)
