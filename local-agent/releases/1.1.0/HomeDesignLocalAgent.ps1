param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$AgentVersion='1.1.0'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$LegacyFile=Join-Path $Root 'HomeDesignLocalAgentCore-1.0.0.ps1'
$StateFile=Join-Path $Root 'state.json'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$GovernorRoot=Join-Path $Base 'ChromeGovernor'
$GovernorFile=Join-Path $GovernorRoot 'ChromeExtensionGovernor.ps1'
$GovernorStatus=Join-Path $GovernorRoot 'SHOW_CHROME_EXTENSION_GOVERNOR_STATUS.ps1'
$GovernorBaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor'
New-Item -ItemType Directory -Force -Path $Root,$GovernorRoot | Out-Null

function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  $header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0))
  $all=New-Object byte[] ($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
}
function Sha256([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return ''}
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Ensure-File([string]$Url,[string]$Path,[string]$Expected){
  $need=(-not(Test-Path -LiteralPath $Path))
  if(-not $need){$need=(GitBlobSha1 $Path)-ne $Expected}
  if($need){
    $tmp=$Path+'.download'
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 60
    if((GitBlobSha1 $tmp)-ne $Expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw 'Git blob SHA1 mismatch'}
    Move-Item $tmp $Path -Force
  }
}
function Refresh-RemoteFile([string]$Url,[string]$Path){
  $before=Sha256 $Path
  $tmp=$Path+'.download'
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 60
  $after=Sha256 $tmp
  if($before -ne $after){Move-Item $tmp $Path -Force;return $true}
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $false
}
function Host-Running(){
  try{
    return @(
      Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object{$_.CommandLine -and $_.CommandLine -like '*HomeDesignLocalCommandHost.ps1*'}
    ).Count -gt 0
  }catch{return $false}
}
function Governor-Processes(){
  try{
    return @(
      Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object{$_.CommandLine -and $_.CommandLine -like '*HomeDesignAutomationV7*ChromeGovernor*ChromeExtensionGovernor.ps1*'}
    )
  }catch{return @()}
}
function Ensure-Governor(){
  $runnerChanged=Refresh-RemoteFile "$GovernorBaseUrl/ChromeExtensionGovernor.ps1" $GovernorFile
  [void](Refresh-RemoteFile "$GovernorBaseUrl/SHOW_CHROME_EXTENSION_GOVERNOR_STATUS.ps1" $GovernorStatus)

  $ws=New-Object -ComObject WScript.Shell
  $startup=[Environment]::GetFolderPath('Startup')
  $desktop=[Environment]::GetFolderPath('Desktop')
  if([string]::IsNullOrWhiteSpace($desktop)){$desktop=Join-Path $env:USERPROFILE 'Desktop'}
  $startupLink=Join-Path $startup 'HomeDesign Chrome Extension Governor.lnk'
  if(-not(Test-Path -LiteralPath $startupLink)){
    $sc=$ws.CreateShortcut($startupLink)
    $sc.TargetPath='powershell.exe'
    $sc.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$GovernorFile`" -Loop"
    $sc.WorkingDirectory=$GovernorRoot
    $sc.Description='HomeDesign Chrome Extension Governor'
    $sc.Save()
  }
  $statusLink=Join-Path $desktop 'HomeDesign Chrome Extension Governor Status.lnk'
  if(-not(Test-Path -LiteralPath $statusLink)){
    $ss=$ws.CreateShortcut($statusLink)
    $ss.TargetPath='powershell.exe'
    $ss.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$GovernorStatus`""
    $ss.WorkingDirectory=$GovernorRoot
    $ss.Description='HomeDesign Chrome Extension Governor current status'
    $ss.Save()
  }

  $procs=Governor-Processes
  if($runnerChanged -and $procs.Count -gt 0){
    foreach($p in $procs){Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue}
    Start-Sleep -Milliseconds 500
    $procs=@()
  }
  if($procs.Count -eq 0){
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$GovernorFile`"",'-Loop'
    ) -WindowStyle Hidden
    Start-Sleep -Milliseconds 500
  }
  return @{root=$GovernorRoot;running=((Governor-Processes).Count -gt 0);runnerChanged=$runnerChanged}
}
function Patch-State($GovernorState){
  $state=@{}
  if(Test-Path $StateFile){
    try{$old=Get-Content $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;foreach($p in $old.PSObject.Properties){$state[$p.Name]=$p.Value}}catch{}
  }
  $state.agentVersion=$AgentVersion
  $state.commandHostVersion='1.1.0'
  $state.commandHostRunning=(Host-Running)
  $state.commandHostUrl='http://127.0.0.1:8765'
  $state.chromeGovernorManaged=$true
  $state.chromeGovernorRunning=[bool]$GovernorState.running
  $state.chromeGovernorRoot=[string]$GovernorState.root
  $state.chromeGovernorUpdatedThisCycle=[bool]$GovernorState.runnerChanged
  $state.updatedAt=(Get-Date).ToString('o')
  $state|ConvertTo-Json -Depth 20|Set-Content $StateFile -Encoding UTF8
}

$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.0/HomeDesignLocalCommandHost.ps1'
$LegacyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.0.0/HomeDesignLocalAgent.ps1'
$HostSha='476a76263fe082f60eb14c4f7db49ff05ba4ceb9'
$LegacySha='6bf74c7b3a58e6f2bd118d11d906dda031796e57'

Ensure-File $HostUrl $HostFile $HostSha
Ensure-File $LegacyUrl $LegacyFile $LegacySha
$governorState=Ensure-Governor

# Preserve the entire proven v1.0 updater/Chrome/rollback cycle.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LegacyFile

# Start the local command host separately so AgentBootstrap can keep its 5-minute update loop.
if(-not (Host-Running)){
  Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$HostFile`""
  ) -WindowStyle Hidden
  Start-Sleep -Seconds 2
}
Patch-State $governorState
