param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.3'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$LegacyFile=Join-Path $Root 'HomeDesignLocalAgentCore-1.0.0.ps1'
$StateFile=Join-Path $Root 'state.json'
$GovernorRoot=Join-Path (Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7') 'ChromeGovernor'
New-Item -ItemType Directory -Force -Path $Root,$GovernorRoot|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(("blob "+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function EnsureFile([string]$Url,[string]$Path,[string]$Expected){$need=(-not(Test-Path -LiteralPath $Path));if(-not $need){$need=(GitBlobSha1 $Path)-ne $Expected};if($need){$tmp=$Path+'.download';Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 60;if((GitBlobSha1 $tmp)-ne $Expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw 'Git blob SHA1 mismatch'};Move-Item $tmp $Path -Force;return $true};return $false}
function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function AgeSec($p){try{$d=$p.CreationDate;if(-not($d -is [datetime])){$d=[Management.ManagementDateTimeConverter]::ToDateTime([string]$d)};return [Math]::Max(0,((Get-Date)-$d).TotalSeconds)}catch{return 0}}
function KillTree([int]$Pid){try{& taskkill.exe /PID $Pid /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue}catch{}}}
function ClearStaleGovernorReadback(){
  $killed=@()
  foreach($p in (Proc 'RunChromeGovernorReadback.ps1')){
    if((AgeSec $p)-gt 150){KillTree $p.ProcessId;$killed+=('RunChromeGovernorReadback.ps1:'+$p.ProcessId)}
  }
  if($killed.Count -gt 0){Start-Sleep -Seconds 2}
  return $killed
}
function StartHidden([string]$File,[string[]]$Extra){$a=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$File`"")+$Extra;Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden;Start-Sleep -Milliseconds 500}
function RefreshGovernor(){
  $base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor'
  foreach($name in @('ChromeExtensionGovernor.ps1','SHOW_CHROME_EXTENSION_GOVERNOR_STATUS.ps1','GovernorDriveSync.ps1')){
    $dst=Join-Path $GovernorRoot $name;$tmp=$dst+'.download';Invoke-WebRequest -UseBasicParsing -Uri "$base/$name" -OutFile $tmp -TimeoutSec 60
    $changed=(-not(Test-Path $dst));if(-not $changed){$changed=(Get-FileHash $dst -Algorithm SHA256).Hash -ne (Get-FileHash $tmp -Algorithm SHA256).Hash}
    if($changed){Move-Item $tmp $dst -Force}else{Remove-Item $tmp -Force}
  }
  $gov=Join-Path $GovernorRoot 'ChromeExtensionGovernor.ps1';$sync=Join-Path $GovernorRoot 'GovernorDriveSync.ps1'
  if((Proc 'ChromeExtensionGovernor.ps1').Count -eq 0){StartHidden $gov @('-Loop')}
  if((Proc 'GovernorDriveSync.ps1').Count -eq 0){StartHidden $sync @('-Loop','-PollSeconds','900')}
}
function WriteState($Killed){
  $state=@{};if(Test-Path $StateFile){try{$o=Get-Content $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;foreach($p in $o.PSObject.Properties){$state[$p.Name]=$p.Value}}catch{}}
  $state.agentVersion=$AgentVersion;$state.commandHostVersion='1.1.2';$state.commandHostRunning=((Proc 'HomeDesignLocalCommandHost.ps1').Count -gt 0);$state.commandHostUrl='http://127.0.0.1:8765';$state.taskTimeoutEnforced=$true;$state.staleGovernorReadbackKilled=@($Killed);$state.updatedAt=(Get-Date).ToString('o');$state|ConvertTo-Json -Depth 20|Set-Content $StateFile -Encoding UTF8
}

$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.2/HomeDesignLocalCommandHost.ps1'
$LegacyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.0.0/HomeDesignLocalAgent.ps1'
$killed=ClearStaleGovernorReadback
$hostChanged=EnsureFile $HostUrl $HostFile 'c4b8747b840ce2ebd65f3c31612a62e151d3b143'
[void](EnsureFile $LegacyUrl $LegacyFile '6bf74c7b3a58e6f2bd118d11d906dda031796e57')
if($hostChanged -or $killed.Count -gt 0){foreach($p in (Proc 'HomeDesignLocalCommandHost.ps1')){KillTree $p.ProcessId};Start-Sleep -Milliseconds 750}
RefreshGovernor
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LegacyFile
if((Proc 'HomeDesignLocalCommandHost.ps1').Count -eq 0){StartHidden $HostFile @()}
WriteState $killed
