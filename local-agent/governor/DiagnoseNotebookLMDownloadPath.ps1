$ErrorActionPreference='Stop'
$base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$userData=Join-Path $base 'ChromeUserData'
$pref=Join-Path $userData 'Default\Preferences'
$result=[ordered]@{ok=$true;at=(Get-Date).ToString('o');preferencesPath=$pref;preferencesExists=(Test-Path -LiteralPath $pref);downloadDefaultDirectory='';promptForDownload=$null;driveMounts=@();googleDriveProcesses=@();userDownloads=(Join-Path $env:USERPROFILE 'Downloads')}
if(Test-Path -LiteralPath $pref){
  try{
    $j=Get-Content -LiteralPath $pref -Raw -Encoding UTF8 | ConvertFrom-Json
    if($j.download){
      $result.downloadDefaultDirectory=[string]$j.download.default_directory
      if($null -ne $j.download.prompt_for_download){$result.promptForDownload=[bool]$j.download.prompt_for_download}
    }
  }catch{$result.preferencesError=$_.Exception.Message}
}
foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
  $root=[string]$d.Root
  if(-not $root){continue}
  $matches=@()
  foreach($candidate in @((Join-Path $root 'My Drive'),(Join-Path $root '내 드라이브'),(Join-Path $root 'Google Drive'),$root)){
    try{
      if((Test-Path -LiteralPath $candidate) -and ($candidate -match '(?i)google drive|my drive|내 드라이브' -or $d.Name -match '^[G-Z]$')){$matches+=$candidate}
    }catch{}
  }
  if($matches.Count -gt 0){$result.driveMounts += [ordered]@{name=$d.Name;root=$root;candidates=@($matches|Select-Object -Unique)}}
}
try{
  $result.googleDriveProcesses=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object{$_.Name -match '(?i)GoogleDriveFS|GoogleDrive'} | ForEach-Object{[ordered]@{name=$_.Name;pid=[int]$_.ProcessId;commandLine=[string]$_.CommandLine}})
}catch{}
$result | ConvertTo-Json -Depth 8 -Compress
