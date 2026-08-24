param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$AgentVersion='1.1.0'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$LegacyFile=Join-Path $Root 'HomeDesignLocalAgentCore-1.0.0.ps1'
$StateFile=Join-Path $Root 'state.json'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function GitBlobSha1([string]$Path){
  $bytes=[IO.File]::ReadAllBytes($Path)
  $header=[Text.Encoding]::ASCII.GetBytes(("blob "+$bytes.Length+[char]0))
  $all=New-Object byte[] ($header.Length+$bytes.Length)
  [Buffer]::BlockCopy($header,0,$all,0,$header.Length)
  [Buffer]::BlockCopy($bytes,0,$all,$header.Length,$bytes.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$sha.Dispose()}
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
function Host-Running(){
  try{
    return @(
      Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object{$_.CommandLine -and $_.CommandLine -like '*HomeDesignLocalCommandHost.ps1*'}
    ).Count -gt 0
  }catch{return $false}
}
function Patch-State(){
  $state=@{}
  if(Test-Path $StateFile){
    try{$old=Get-Content $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;foreach($p in $old.PSObject.Properties){$state[$p.Name]=$p.Value}}catch{}
  }
  $state.agentVersion=$AgentVersion
  $state.commandHostVersion='1.1.0'
  $state.commandHostRunning=(Host-Running)
  $state.commandHostUrl='http://127.0.0.1:8765'
  $state.updatedAt=(Get-Date).ToString('o')
  $state|ConvertTo-Json -Depth 20|Set-Content $StateFile -Encoding UTF8
}

$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.0/HomeDesignLocalCommandHost.ps1'
$LegacyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.0.0/HomeDesignLocalAgent.ps1'
$HostSha='476a76263fe082f60eb14c4f7db49ff05ba4ceb9'
$LegacySha='6bf74c7b3a58e6f2bd118d11d906dda031796e57'

Ensure-File $HostUrl $HostFile $HostSha
Ensure-File $LegacyUrl $LegacyFile $LegacySha

# Preserve the entire proven v1.0 updater/Chrome/rollback cycle.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LegacyFile

# Start the local command host separately so AgentBootstrap can keep its 5-minute update loop.
if(-not (Host-Running)){
  Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$HostFile`""
  ) -WindowStyle Hidden
  Start-Sleep -Seconds 2
}
Patch-State
