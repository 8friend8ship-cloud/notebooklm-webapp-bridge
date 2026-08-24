param(
  [switch]$Loop,
  [int]$PollSeconds = 900,
  [string]$ReportPath = "$env:LOCALAPPDATA\HomeDesignAutomationV7\ChromeGovernor\state.json",
  [string]$InventoryPath = "$env:LOCALAPPDATA\HomeDesignAutomationV7\ChromeGovernor\inventory.json"
)

$ErrorActionPreference='Continue'
$CachePath=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\ChromeGovernor\drive-sync.json'
$TargetName='00_중앙에이전트'
$PollSeconds=[Math]::Max(300,$PollSeconds)

function Test-Central([string]$Path){return ($Path -and (Test-Path -LiteralPath $Path))}
function Find-CentralFolder {
  if(Test-Path -LiteralPath $CachePath){
    try{$c=Get-Content -LiteralPath $CachePath -Raw -Encoding UTF8|ConvertFrom-Json;if($c.path -and (Test-Central ([string]$c.path))){return [string]$c.path}}catch{}
  }

  # Google Drive for Desktop commonly exposes a virtual drive letter that is not always returned as a normal PSDrive.
  foreach($letter in 'D'..'Z'){
    foreach($candidate in @(
      "$letter`:\My Drive\$TargetName",
      "$letter`:\내 드라이브\$TargetName",
      "$letter`:\Google Drive\$TargetName",
      "$letter`:\$TargetName"
    )){if(Test-Central $candidate){return $candidate}}
  }

  foreach($candidate in @(
    (Join-Path $env:USERPROFILE ('My Drive\'+$TargetName)),
    (Join-Path $env:USERPROFILE ('내 드라이브\'+$TargetName)),
    (Join-Path $env:USERPROFILE ('Google Drive\'+$TargetName)),
    (Join-Path $env:USERPROFILE ('Google Drive\My Drive\'+$TargetName))
  )){if(Test-Central $candidate){return $candidate}}

  $roots=@()
  try{$roots += @(Get-PSDrive -PSProvider FileSystem | ForEach-Object {$_.Root})}catch{}
  $roots=@($roots|Where-Object{$_ -and (Test-Path -LiteralPath $_)}|Select-Object -Unique)
  foreach($r in $roots){
    foreach($candidate in @(
      (Join-Path $r $TargetName),
      (Join-Path $r ('My Drive\'+$TargetName)),
      (Join-Path $r ('내 드라이브\'+$TargetName)),
      (Join-Path $r ('Google Drive\'+$TargetName))
    )){if(Test-Central $candidate){return $candidate}}
  }
  return $null
}

function Sync-Once {
  $target=Find-CentralFolder
  if(-not $target){
    @{ok=$false;status='DRIVE_SYNC_FOLDER_NOT_FOUND';at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $CachePath -Encoding UTF8
    return $false
  }
  $outDir=Join-Path $target 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $outDir|Out-Null
  if(Test-Path -LiteralPath $ReportPath){Copy-Item -LiteralPath $ReportPath -Destination (Join-Path $outDir 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force}
  if(Test-Path -LiteralPath $InventoryPath){Copy-Item -LiteralPath $InventoryPath -Destination (Join-Path $outDir 'CHROME_EXTENSION_INVENTORY.json') -Force}
  @{ok=$true;status='SYNCED';path=$target;outDir=$outDir;at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $CachePath -Encoding UTF8
  return $true
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignChromeGovernorDriveSyncV1')
if(-not $mutex.WaitOne(0,$false)){exit 0}
try{do{[void](Sync-Once);if($Loop){Start-Sleep -Seconds $PollSeconds}}while($Loop)}finally{try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
