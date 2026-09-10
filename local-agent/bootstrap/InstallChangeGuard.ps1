param()
$ErrorActionPreference='Continue'
$o=[ordered]@{active=$false;reason='';latestMsiId=0;latestMsiTime='';installerProcessCount=0}
try{
  $ev=Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='MsiInstaller';Id=1040,1042;StartTime=(Get-Date).AddHours(-3)} -ErrorAction SilentlyContinue | Sort-Object TimeCreated -Descending | Select-Object -First 1
  if($ev){
    $o.latestMsiId=[int]$ev.Id
    $o.latestMsiTime=$ev.TimeCreated.ToString('o')
    if([int]$ev.Id -eq 1040 -and ((Get-Date)-$ev.TimeCreated).TotalMinutes -lt 120){$o.active=$true;$o.reason='MSI_TRANSACTION_ACTIVE'}
  }
}catch{}
try{
  $p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {([string]$_.Name -match '^(winget|setup|installer)\.exe$') -and $_.CreationDate -and ((Get-Date)-([datetime]$_.CreationDate)).TotalMinutes -lt 30})
  $o.installerProcessCount=$p.Count
  if($p.Count -gt 0){$o.active=$true;if(-not $o.reason){$o.reason='RECENT_INSTALLER_PROCESS'}}
}catch{}
$o|ConvertTo-Json -Compress