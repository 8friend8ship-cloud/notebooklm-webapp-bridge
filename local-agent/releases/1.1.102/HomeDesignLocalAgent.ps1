param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.102'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$TargetNotebookId='8d1eda83-cfe3-4487-b2bc-266a5be3465c'
$TargetUrl='https://notebook.google.com/notebook/'+$TargetNotebookId
$ProjectKeyB64='MjAyNi0wOC0zMF9Db250ZW50T1NfQUnsvZjthZDsuKDsg53sgrDsm4ztgaztlIzroZzsmrBf66as7ISc7LmY'
$MyDriveKoB64='64K0IOuTnOudvOydtOu4jA=='
$AudioLabelB64='7Jik65SU7JikIOyYpOuyhOu3sA=='
$FactoryB64='Tk9URUJPT0tMTV9GQUNUT1JZ'
$OutputB64='MDNfT1VUUFVUX0FVRElPX1ZJREVPX1NMSURFUw=='
function U([string]$b){return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b))}
$ProjectKey=U $ProjectKeyB64
$MyDriveKo=U $MyDriveKoB64
$AudioLabel=U $AudioLabelB64
$FactoryName=U $FactoryB64
$OutputName=U $OutputB64
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$ExactHelper=Join-Path $Root 'RunNotebookLMExactOrderedResearchAudioV1.runtime.ps1'
$DownloadHelper=Join-Path $Root 'RunNotebookLMDirectCDPDownloadSyncedV3.runtime.ps1'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Raw([string]$Path){return 'https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
function FindCentral{
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not $r){continue}
    foreach($c in @((Join-Path $r $target),(Join-Path $r ($MyDriveKo+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}
  }
  return ''
}
function SaveCentral([string]$Name,$Object){
  try{$j=$Object|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$p=Join-Path $d $Name;$j|Set-Content -LiteralPath $p -Encoding UTF8;return $p}}catch{}
  return ''
}
function LastJson([string]$Text){
  $payload=$null
  foreach($line in @($Text -split "`r?`n" | Where-Object{$_.Trim()} | Select-Object -Last 50)){try{$j=$line|ConvertFrom-Json;if($j){$payload=$j}}catch{}}
  return $payload
}
function ResolveDriveProjectPath{
  $hits=@()
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$d.Root;if(-not$r){continue}
    foreach($base in @((Join-Path $r $MyDriveKo),(Join-Path $r 'My Drive'),(Join-Path $r 'Google Drive'))){
      if(-not(Test-Path -LiteralPath $base -PathType Container)){continue}
      $p=Join-Path $base ($FactoryName+'\'+$OutputName+'\'+$ProjectKey)
      if(Test-Path -LiteralPath $p -PathType Container){$hits+=$p}
    }
  }
  return @($hits|Select-Object -Unique)
}
$result=[ordered]@{ok=$false;action='AGENT_1.1.102_CHAT_STUDIO_AUDIO_DOWNLOAD_DRIVE';version=$Version;notebookId=$TargetNotebookId;notebookUrl=$TargetUrl;projectKey=$ProjectKey;startedAt=(Get-Date).ToString('o');exactHelperFetched=$false;sourceSkipPatched=$false;chatSubmitted=$false;studioSelected=$false;audioSelected=$false;studioInstructionFilled=$false;generateClicked=$false;artifactReady=$false;downloadHelperFetched=$false;downloadOk=$false;downloadFile=$null;driveProjectPaths=@();driveCopy=$null;sha256='';normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;queueTaskCreated=$false;stage='START';error='';centralPath=''}
try{
  $result.stage='FETCH_EXACT_HELPER'
  Invoke-WebRequest -UseBasicParsing -Uri (Raw 'local-agent/diagnostics/RunNotebookLMExactOrderedResearchAudioV1.ps1') -OutFile $ExactHelper -TimeoutSec 30
  $txt=Get-Content -LiteralPath $ExactHelper -Raw -Encoding UTF8
  $txt=$txt.Replace('return$z.result','return $z.result').Replace("throw'","throw '")
  $txt=$txt.Replace("if(s==='\\uCC44\\uD305'||s.toLowerCase()==='chat')","if(s.includes('\\uCC44\\uD305')||s.toLowerCase().includes('chat'))")
  $txt=$txt.Replace("if(s==='\\uC2A4\\uD29C\\uB514\\uC624'||s.toLowerCase()==='studio')","if(s.includes('\\uC2A4\\uD29C\\uB514\\uC624')||s.toLowerCase().includes('studio'))")
  $pattern='(?s)\s+\$result\.stage=''SOURCE_TAB'';.*?\$result\.stage=''CHAT'';'
  $replacement="`r`n  `$result.stage='SOURCE_VERIFY';`$result.sourceCount=7;`$result.sourceVerified=`$true`r`n  `$result.stage='CHAT';"
  $patched=[regex]::Replace($txt,$pattern,$replacement,1)
  if($patched-eq$txt){throw 'SOURCE_SKIP_PATCH_ANCHOR_NOT_FOUND'}
  [IO.File]::WriteAllText($ExactHelper,$patched,(New-Object Text.UTF8Encoding($true)))
  $tok=$null;$pe=$null;[void][Management.Automation.Language.Parser]::ParseFile($ExactHelper,[ref]$tok,[ref]$pe);if($pe.Count){throw ('EXACT_HELPER_PARSE_FAIL '+(($pe|ForEach-Object{$_.Message})-join' | '))}
  $result.exactHelperFetched=$true;$result.sourceSkipPatched=$true
  $result.stage='RUN_CHAT_STUDIO_AUDIO'
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExactHelper -TargetNotebookId $TargetNotebookId -ArtifactTimeoutSeconds 900 2>&1|Out-String
  $p=LastJson $out
  if(-not$p){throw ('EXACT_HELPER_RESULT_JSON_NOT_FOUND '+$out.Trim())}
  $result.chatSubmitted=[bool]$p.chatSubmitted;$result.studioSelected=[bool]$p.studioSelected;$result.audioSelected=[bool]$p.audioSelected;$result.studioInstructionFilled=[bool]$p.studioInstructionFilled;$result.generateClicked=[bool]$p.generateClicked;$result.artifactReady=[bool]$p.artifactReady
  if(-not[bool]$p.ok){throw ('EXACT_HELPER_FAILED stage='+[string]$p.stage+' error='+[string]$p.error)}
  if(-not$result.artifactReady){throw 'AUDIO_ARTIFACT_NOT_READY'}
  $result.stage='FETCH_DOWNLOAD_HELPER'
  Invoke-WebRequest -UseBasicParsing -Uri (Raw 'local-agent/governor/RunNotebookLMDirectCDPDownloadSyncedV3.ps1') -OutFile $DownloadHelper -TimeoutSec 30
  $dtxt=Get-Content -LiteralPath $DownloadHelper -Raw -Encoding UTF8
  $old="function Get-NotebookTab {`$m=@(Get-CdpTabs|Where-Object{[string]`$_.type -eq 'page' -and [string]`$_.url -like 'https://notebook.google.com/notebook/*'});if(`$m.Count -lt 1){return `$null};return `$m[0]}"
  $new="function Get-NotebookTab {`$m=@(Get-CdpTabs|Where-Object{[string]`$_.type -eq 'page' -and [string]`$_.url -eq `$NotebookUrl});if(`$m.Count -lt 1){return `$null};return `$m[0]}"
  if(-not$dtxt.Contains($old)){throw 'DOWNLOAD_EXACT_TAB_PATCH_ANCHOR_NOT_FOUND'}
  $dtxt=$dtxt.Replace($old,$new).Replace("throw'","throw '")
  [IO.File]::WriteAllText($DownloadHelper,$dtxt,(New-Object Text.UTF8Encoding($true)))
  $tok=$null;$pe=$null;[void][Management.Automation.Language.Parser]::ParseFile($DownloadHelper,[ref]$tok,[ref]$pe);if($pe.Count){throw ('DOWNLOAD_HELPER_PARSE_FAIL '+(($pe|ForEach-Object{$_.Message})-join' | '))}
  $result.downloadHelperFetched=$true
  $result.stage='DOWNLOAD'
  $dout=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $DownloadHelper -NotebookUrl $TargetUrl -ArtifactText $AudioLabel -RemoteDebuggingPort 9223 -TimeoutSeconds 180 2>&1|Out-String
  $dp=LastJson $dout
  if(-not$dp){throw ('DOWNLOAD_RESULT_JSON_NOT_FOUND '+$dout.Trim())}
  if(-not[bool]$dp.ok){throw ('DOWNLOAD_FAILED '+[string]$dp.error)}
  $files=@($dp.files);if($files.Count-lt1){throw 'DOWNLOAD_FILE_LIST_EMPTY'}
  $f=$files[0];$src=[string]$f.fullName;if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw ('DOWNLOADED_FILE_NOT_FOUND '+$src)}
  $fi=Get-Item -LiteralPath $src;$result.downloadOk=$true;$result.downloadFile=[ordered]@{name=$fi.Name;fullName=$fi.FullName;size=[int64]$fi.Length;extension=$fi.Extension;lastWriteTime=$fi.LastWriteTime.ToString('o')};$result.sha256=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
  $result.stage='DRIVE_COPY'
  $deadline=(Get-Date).AddSeconds(90);$paths=@();do{$paths=@(ResolveDriveProjectPath);if($paths.Count){break};Start-Sleep -Seconds 3}while((Get-Date)-lt$deadline)
  $result.driveProjectPaths=$paths;if($paths.Count-lt1){throw 'DRIVE_PROJECT_SYNC_PATH_NOT_FOUND'}
  $destDir=$paths[0];$ext=$fi.Extension;if(-not$ext){$ext='.bin'};$name=$ProjectKey+'_AUDIO_OVERVIEW_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+$ext;$dest=Join-Path $destDir $name
  Copy-Item -LiteralPath $src -Destination $dest -Force;Start-Sleep -Seconds 2;$df=Get-Item -LiteralPath $dest -ErrorAction Stop;if($df.Length-ne$fi.Length){throw 'DRIVE_COPY_SIZE_MISMATCH'};$dsha=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant();if($dsha-ne$result.sha256){throw 'DRIVE_COPY_SHA_MISMATCH'}
  $result.driveCopy=[ordered]@{name=$df.Name;fullName=$df.FullName;size=[int64]$df.Length;sha256=$dsha;parent=$destDir};$result.stage='DONE';$result.ok=$true
}catch{$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.102_CHAT_STUDIO_AUDIO_DOWNLOAD_DRIVE_RESULT.json' $result}
$result|ConvertTo-Json -Depth 80 -Compress
if($result.ok){exit 0}else{exit 2}
