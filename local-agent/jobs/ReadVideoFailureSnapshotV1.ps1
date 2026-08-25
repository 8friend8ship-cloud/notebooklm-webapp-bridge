param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Prod=Join-Path $Base 'VideoProduction'
$Console=Join-Path $Root 'video-job-console.log'
function Tail([string]$Path,[int]$Lines=100){if(-not(Test-Path -LiteralPath $Path)){return ''};try{return ((Get-Content -LiteralPath $Path -Tail $Lines -Encoding UTF8 -ErrorAction Stop)-join "`n")}catch{return 'READ_ERROR: '+$_.Exception.Message}}
function ReadSmallJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{$F=Get-Item -LiteralPath $Path;if($F.Length -gt 524288){return [ordered]@{path=$Path;tooLarge=$true;bytes=$F.Length}};return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return [ordered]@{path=$Path;error=$_.Exception.Message}}}
function FindCentral{
  $Target='00_중앙에이전트'
  foreach($D in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$R=[string]$D.Root;if(-not $R){continue};foreach($C in @((Join-Path $R $Target),(Join-Path $R ('My Drive\'+$Target)),(Join-Path $R ('내 드라이브\'+$Target)),(Join-Path $R ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}}
  foreach($C in @((Join-Path $env:USERPROFILE ('My Drive\'+$Target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$Target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$Target)))){if(Test-Path -LiteralPath $C){return $C}}
  return ''
}
$Runs=@()
if(Test-Path -LiteralPath $Prod){
  $Dirs=@(Get-ChildItem -LiteralPath $Prod -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -like 'AUTO_QA_V3_*'}|Sort-Object LastWriteTime -Descending|Select-Object -First 3)
  foreach($D in $Dirs){
    $Qa=@()
    foreach($N in @('QA_PASS_1','QA_PASS_2')){
      $Dir=Join-Path $D.FullName ('out\'+$N)
      $Qa += [ordered]@{name=$N;console=(Tail (Join-Path $Dir 'qa-console.log') 80);summary=(ReadSmallJson (Join-Path $Dir '00_FRAME_QA_SUMMARY.json'))}
    }
    $Runs += [ordered]@{path=$D.FullName;lastWrite=$D.LastWriteTime.ToString('o');autoQaLog=(Tail (Join-Path $D.FullName 'auto-qa.log') 100);qa=$Qa}
  }
}
$Snap=[ordered]@{ok=$true;action='VIDEO_FAILURE_SNAPSHOT_V1';at=(Get-Date).ToString('o');previousWorkerConsole=(Tail $Console 120);recentRuns=$Runs}
$Central=FindCentral
if($Central){try{$Dir=Join-Path $Central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $Dir|Out-Null;$Path=Join-Path $Dir 'VIDEO_FAILURE_SNAPSHOT_V1.json';$Snap|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding UTF8;$Snap.centralPath=$Path}catch{$Snap.centralWriteError=$_.Exception.Message}}
$Snap|ConvertTo-Json -Compress -Depth 30
exit 0
