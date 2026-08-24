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

function Find-CentralFolder {
  if(Test-Path -LiteralPath $CachePath){
    try{
      $c=Get-Content -LiteralPath $CachePath -Raw -Encoding UTF8|ConvertFrom-Json
      if($c.path -and (Test-Path -LiteralPath ([string]$c.path))){return [string]$c.path}
    }catch{}
  }

  $roots=@()
  try{$roots += @(Get-PSDrive -PSProvider FileSystem | ForEach-Object {$_.Root})}catch{}
  $roots += @(
    (Join-Path $env:USERPROFILE 'My Drive'),
    (Join-Path $env:USERPROFILE '내 드라이브'),
    (Join-Path $env:USERPROFILE 'Google Drive')
  )
  $roots=@($roots|Where-Object{$_ -and (Test-Path -LiteralPath $_)}|Select-Object -Unique)

  foreach($r in $roots){
    $direct=@(
      (Join-Path $r $TargetName),
      (Join-Path $r ('My Drive\'+$TargetName)),
      (Join-Path $r ('내 드라이브\'+$TargetName)),
      (Join-Path $r ('Google Drive\'+$TargetName))
    )
    foreach($p in $direct){if(Test-Path -LiteralPath $p){return $p}}
  }

  foreach($r in $roots){
    try{
      foreach($d1 in @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue)){
        if($d1.Name -eq $TargetName){return $d1.FullName}
        foreach($d2 in @(Get-ChildItem -LiteralPath $d1.FullName -Directory -ErrorAction SilentlyContinue)){
          if($d2.Name -eq $TargetName){return $d2.FullName}
        }
      }
    }catch{}
  }
  return $null
}

function Sync-Once {
  $target=Find-CentralFolder
  if(-not $target){
    @{ok=$false;status='DRIVE_SYNC_FOLDER_NOT_FOUND';at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $CachePath -Encoding UTF8
    return $false
  }

  $outDir=Join-Path $target 'Chrome_Extension_Governor'
  New-Item -ItemType Directory -Force -Path $outDir|Out-Null
  if(Test-Path -LiteralPath $ReportPath){Copy-Item -LiteralPath $ReportPath -Destination (Join-Path $outDir 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force}
  if(Test-Path -LiteralPath $InventoryPath){Copy-Item -LiteralPath $InventoryPath -Destination (Join-Path $outDir 'CHROME_EXTENSION_INVENTORY.json') -Force}
  @{ok=$true;status='SYNCED';path=$target;outDir=$outDir;at=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $CachePath -Encoding UTF8
  return $true
}

$mutex=New-Object Threading.Mutex($false,'HomeDesignChromeGovernorDriveSyncV1')
if(-not $mutex.WaitOne(0,$false)){exit 0}
try{
  do{
    [void](Sync-Once)
    if($Loop){Start-Sleep -Seconds $PollSeconds}
  }while($Loop)
}finally{
  try{$mutex.ReleaseMutex()}catch{}
  $mutex.Dispose()
}
