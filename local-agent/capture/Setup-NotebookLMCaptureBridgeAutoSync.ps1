param([switch]$SmokeOnly)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Base='C:\HomeDesignAutomationV7'
$CaptureRoot=Join-Path $Base 'CaptureBridge'
$Inbox=Join-Path $CaptureRoot 'INBOX\NotebookLM'
$ScriptDir=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent\capture'
$Reconcile=Join-Path $ScriptDir 'Reconcile-NotebookLMCaptureBridge.ps1'
$HealthLocal=Join-Path $CaptureRoot 'capture-bridge-health.json'
$TaskName='HomeDesign-CaptureBridge-NotebookLM-Reconcile'

function Find-CentralRoot {
  $target='00_중앙에이전트'
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root
    if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){
      if(Test-Path -LiteralPath $c){return $c}
    }
  }
  return ''
}

New-Item -ItemType Directory -Force -Path $Inbox,$ScriptDir | Out-Null
$Central=Find-CentralRoot
if(-not $Central){ throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND' }
$DriveInbox=Join-Path $Central 'CaptureBridge\INBOX\NotebookLM'
New-Item -ItemType Directory -Force -Path $DriveInbox | Out-Null

$reconcileBody=@'
$ErrorActionPreference='Continue'
$Inbox='C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM'
function Find-CentralRoot {
  $target='00_중앙에이전트'
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}
  }
  return ''
}
$Central=Find-CentralRoot
if(-not $Central -or -not(Test-Path -LiteralPath $Inbox)){exit 0}
$Dest=Join-Path $Central 'CaptureBridge\INBOX\NotebookLM'
New-Item -ItemType Directory -Force -Path $Dest|Out-Null
$copied=@()
foreach($f in @(Get-ChildItem -LiteralPath $Inbox -File -ErrorAction SilentlyContinue)){
  if($f.Extension -eq '.crdownload' -or $f.Name.EndsWith('.tmp')){continue}
  if($f.Name -like '*.capture.json'){continue}
  $target=Join-Path $Dest $f.Name
  $needs=$true
  if(Test-Path -LiteralPath $target){$d=Get-Item -LiteralPath $target -ErrorAction SilentlyContinue;if($d -and $d.Length -eq $f.Length){$needs=$false}}
  if($needs){Copy-Item -LiteralPath $f.FullName -Destination $target -Force}
  if(Test-Path -LiteralPath $target){
    $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    $meta=[ordered]@{sourcePath=$f.FullName;drivePath=$target;name=$f.Name;size=(Get-Item -LiteralPath $target).Length;sha256=$hash;syncedAt=(Get-Date).ToString('o')}
    $meta|ConvertTo-Json -Depth 5|Set-Content -LiteralPath ($target+'.capture.json') -Encoding UTF8
    $copied+=$meta
  }
}
$health=[ordered]@{ok=$true;at=(Get-Date).ToString('o');localInbox=$Inbox;driveInbox=$Dest;copiedCount=$copied.Count;copied=$copied}
$healthRoot=Split-Path (Split-Path $Dest -Parent) -Parent
$health|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $healthRoot 'capture-bridge-health.json') -Encoding UTF8
'@
Set-Content -LiteralPath $Reconcile -Value $reconcileBody -Encoding UTF8

if(-not $SmokeOnly){
  $tr='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$Reconcile+'"'
  & schtasks.exe /Create /F /SC MINUTE /MO 5 /TN $TaskName /TR $tr | Out-Null
}

$stamp=(Get-Date).ToString('yyyyMMdd_HHmmss')
$smoke=Join-Path $Inbox ('_SMOKE_NOTEBOOKLM_CAPTURE_'+$stamp+'.txt')
$body='NOTEBOOKLM_CAPTUREBRIDGE_SMOKE_PASS '+(Get-Date).ToString('o')
Set-Content -LiteralPath $smoke -Value $body -Encoding UTF8
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Reconcile | Out-Null
$driveSmoke=Join-Path $DriveInbox (Split-Path $smoke -Leaf)
$exists=Test-Path -LiteralPath $driveSmoke
$size=if($exists){(Get-Item -LiteralPath $driveSmoke).Length}else{0}
$hash=if($exists){(Get-FileHash -Algorithm SHA256 -LiteralPath $driveSmoke).Hash.ToLowerInvariant()}else{''}
$health=[ordered]@{ok=[bool]$exists;at=(Get-Date).ToString('o');localInbox=$Inbox;driveInbox=$DriveInbox;scheduledTask=$TaskName;reconcileScript=$Reconcile;smokeLocal=$smoke;smokeDrive=$driveSmoke;driveExists=[bool]$exists;driveSize=[int64]$size;sha256=$hash;manualSyncRequired=$false}
$health|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $HealthLocal -Encoding UTF8
$health|ConvertTo-Json -Depth 8 -Compress
if(-not $exists){exit 2}
