param()
$ErrorActionPreference='Continue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$Prod=Join-Path $Base 'VideoProduction'
function ReadText([string]$Path,[int]$Max=12000){
  if(-not(Test-Path -LiteralPath $Path)){return ''}
  try{$T=Get-Content -LiteralPath $Path -Raw -Encoding UTF8;if($T.Length -gt $Max){return $T.Substring([Math]::Max(0,$T.Length-$Max))};return $T}catch{return ('READ_ERROR: '+$_.Exception.Message)}
}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
$StatePath=Join-Path $Root 'video-job-state.json'
$ConsolePath=Join-Path $Root 'video-job-console.log'
$MetaPath=Join-Path $Root 'video-production-job.json'
$Recent=@()
if(Test-Path -LiteralPath $Prod){
  foreach($D in @(Get-ChildItem -LiteralPath $Prod -Directory -Filter 'AUTO_QA_V3_*' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 4)){
    $Log=Join-Path $D.FullName 'auto-qa.log'
    $QaLogs=@()
    foreach($Q in @('QA_PASS_1','QA_PASS_2')){
      $P=Join-Path $D.FullName ('out\'+$Q+'\qa-console.log')
      if(Test-Path -LiteralPath $P){$QaLogs += [ordered]@{pass=$Q;path=$P;text=(ReadText $P 8000)}}
    }
    $Recent += [ordered]@{path=$D.FullName;lastWrite=$D.LastWriteTime.ToString('o');autoQaLog=(ReadText $Log 8000);qaLogs=$QaLogs}
  }
}
[ordered]@{
  ok=$true
  action='READ_VIDEO_JOB_FAILURE_V1'
  at=(Get-Date).ToString('o')
  jobState=(ReadJson $StatePath)
  jobMeta=(ReadJson $MetaPath)
  workerConsole=(ReadText $ConsolePath 12000)
  recentRuns=$Recent
}|ConvertTo-Json -Depth 20 -Compress
exit 0
