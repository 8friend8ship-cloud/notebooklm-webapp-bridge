param(
  [string]$CentralRootOverride='',
  [int]$MaxProjects=20
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$AuditPath='apps-script/CentralResultAudit.gs'
$QaPath='apps-script/CentralLearningQaAutomation.gs'
$AuditExpected='2db327858c4f8edcd99b3cae7803949077f3df83'
$QaExpected='b1e540e5ff6b0e809261c3711af2b4fcb635787b'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Work=Join-Path $Base ('AppsScriptQaSync\'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $Work|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{
  if($CentralRootOverride){if(Test-Path -LiteralPath $CentralRootOverride -PathType Container){return $CentralRootOverride};throw 'CENTRAL_ROOT_OVERRIDE_NOT_FOUND'}
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(!$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};throw 'CENTRAL_DRIVE_ROOT_NOT_FOUND'
}
function FetchPinned([string]$Rel,[string]$Dest,[string]$Expected){$url='https://raw.githubusercontent.com/'+$Repo+'/main/'+$Rel+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Dest -TimeoutSec 30;$actual=(GitBlobSha1 $Dest).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){throw ('SOURCE_SHA_MISMATCH:'+ $Rel+':actual='+$actual+':expected='+$Expected)};return $actual}
function SafeRun([string]$File,[string[]]$Args,[int]$TimeoutSec=60){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$File;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Arguments=($Args|ForEach-Object{if($_ -match '[\s"]'){'"'+($_ -replace '"','\"')+'"'}else{$_}})-join ' ';$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit($TimeoutSec*1000)){try{& taskkill.exe /PID $p.Id /T /F 2>$null|Out-Null}catch{};return [ordered]@{ok=$false;exit=-1;timedOut=$true;stdout=$ot.Result;stderr=$et.Result}};return [ordered]@{ok=($p.ExitCode -eq 0);exit=$p.ExitCode;timedOut=$false;stdout=$ot.Result.Trim();stderr=$et.Result.Trim()}}

$central=FindCentral
$readbackDir=Join-Path $central 'Runtime_Readback\AppsScript_QA';$backupRoot=Join-Path $central ('Backups\AppsScript_QA\'+(Get-Date -Format 'yyyyMMdd_HHmmss'));New-Item -ItemType Directory -Force -Path $readbackDir,$backupRoot|Out-Null
$clasp=(Get-Command clasp.cmd -ErrorAction SilentlyContinue);if(!$clasp){$clasp=Get-Command clasp -ErrorAction SilentlyContinue};if(!$clasp){throw 'CLASP_NOT_FOUND'}
$auditSrc=Join-Path $Work 'CentralResultAudit.gs';$qaSrc=Join-Path $Work 'CentralLearningQaAutomation.gs';$auditSha=FetchPinned $AuditPath $auditSrc $AuditExpected;$qaSha=FetchPinned $QaPath $qaSrc $QaExpected

# Static safety/contract test before touching any bound project.
$qaText=Get-Content -LiteralPath $qaSrc -Raw -Encoding UTF8
$auditText=Get-Content -LiteralPath $auditSrc -Raw -Encoding UTF8
$staticChecks=[ordered]@{
  hasInstallTrigger=($qaText -match 'function\s+installCentralLearningQaTriggersV1')
  hasFiveMinute=($qaText -match 'everyMinutes\(5\)')
  hasDriveCycle=($qaText -match 'function\s+runCentralDriveLearningQaCycleV1')
  imageBeforeFlow=($qaText.IndexOf('IMAGE_ASSET_T1') -ge 0 -and $qaText.IndexOf('IMAGE_ASSET_T1') -lt $qaText.IndexOf('FLOW_RESULT_GENERIC_V1'))
  apiCapDefaultZero=($qaText -match "CENTRAL_GEMINI_QA_DAILY_CAP'\)\|\|0" -and $qaText -match "CENTRAL_OPENAI_QA_DAILY_CAP'\)\|\|0")
  noAutoBudgetWrite=(-not($qaText -match 'setProperty\([^\r\n]*CENTRAL_(GEMINI|OPENAI)_QA_DAILY_CAP'))
  existingAuditIntegration=($auditText -match 'function\s+centralAuditResultV1' -and $qaText -match 'centralAuditResultV1\(')
}
if(@($staticChecks.Values|Where-Object{-not $_}).Count){throw ('STATIC_QA_FAILED:'+($staticChecks|ConvertTo-Json -Compress))}

$list=SafeRun $clasp.Source @('list') 45
if(!$list.ok){throw ('CLASP_LIST_FAILED:'+($list.stderr+' '+$list.stdout))}
$ids=[regex]::Matches(($list.stdout+' '+$list.stderr),'[A-Za-z0-9_-]{40,}')|ForEach-Object{$_.Value}|Select-Object -Unique|Select-Object -First $MaxProjects
if(!$ids){throw 'NO_EXISTING_APPS_SCRIPT_PROJECT_IDS_FOUND'}
$candidates=@();$target=$null
foreach($id in $ids){
  $dir=Join-Path $Work ('candidate_'+$id.Substring(0,[Math]::Min(8,$id.Length)));New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $clone=SafeRun $clasp.Source @('clone',$id,'--rootDir',$dir) 60
  if(!$clone.ok){$candidates += [ordered]@{scriptId=$id;cloneOk=$false;error=($clone.stderr+' '+$clone.stdout).Trim()};continue}
  $files=@(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)
  $joined=($files|Where-Object{$_.Extension -in '.gs','.js','.json'}|ForEach-Object{try{Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8}catch{''}})-join "`n"
  $score=0;if($joined -match 'centralAuditResultV1'){ $score+=100 };if($joined -match 'CENTRAL_MASTER_REGISTRY_ID'){ $score+=80 };if($joined -match 'NotebookLM_Task_Queue|APP_NOTEBOOKLM_BRIDGE'){ $score+=20 }
  $candidates += [ordered]@{scriptId=$id;cloneOk=$true;score=$score;dir=$dir}
  if(!$target -or $score -gt $target.score){$target=[ordered]@{scriptId=$id;score=$score;dir=$dir}}
}
if(!$target -or $target.score -lt 80){throw ('BOUND_CENTRAL_SCRIPT_NOT_FOUND:'+($candidates|ConvertTo-Json -Depth 5 -Compress))}

# Back up every current source file before any push.
$targetFiles=@(Get-ChildItem -LiteralPath $target.dir -Recurse -File -ErrorAction SilentlyContinue)
foreach($f in $targetFiles){$rel=$f.FullName.Substring($target.dir.Length).TrimStart('\');$dest=Join-Path $backupRoot $rel;$parent=Split-Path -Parent $dest;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};Copy-Item -LiteralPath $f.FullName -Destination $dest -Force}
$backupManifest=[ordered]@{scriptId=$target.scriptId;score=$target.score;files=@($targetFiles|ForEach-Object{[ordered]@{path=$_.FullName.Substring($target.dir.Length).TrimStart('\');bytes=$_.Length}});at=(Get-Date).ToString('o')};$backupManifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $backupRoot 'backup_manifest.json') -Encoding UTF8

Copy-Item -LiteralPath $auditSrc -Destination (Join-Path $target.dir 'CentralResultAudit.gs') -Force
Copy-Item -LiteralPath $qaSrc -Destination (Join-Path $target.dir 'CentralLearningQaAutomation.gs') -Force
$push=SafeRun $clasp.Source @('push','--force','--rootDir',$target.dir) 120
if(!$push.ok){$result=[ordered]@{ok=$false;stage='CLASP_PUSH';scriptId=$target.scriptId;backupRoot=$backupRoot;staticChecks=$staticChecks;auditSha=$auditSha;qaSha=$qaSha;push=$push;candidates=$candidates;at=(Get-Date).ToString('o')};$result|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $readbackDir 'CENTRAL_LEARNING_QA_SYNC.json') -Encoding UTF8;$result|ConvertTo-Json -Depth 20 -Compress;exit 2}

$test=SafeRun $clasp.Source @('run','testCentralLearningQaFunctionsV1','--rootDir',$target.dir) 90
$install=$null;$cycle=$null
if($test.ok){$install=SafeRun $clasp.Source @('run','installCentralLearningQaTriggersV1','--rootDir',$target.dir) 90;if($install.ok){$cycle=SafeRun $clasp.Source @('run','runCentralDriveLearningQaCycleV1','--rootDir',$target.dir) 120}}
$status=if($push.ok -and $test.ok -and $install.ok -and $cycle.ok){'RUNTIME_TRIGGER_PASS'}elseif($push.ok){'SYNC_PASS_RUNTIME_INSTALL_PENDING'}else{'FAILED'}
$result=[ordered]@{ok=($status -eq 'RUNTIME_TRIGGER_PASS');status=$status;scriptId=$target.scriptId;targetScore=$target.score;backupRoot=$backupRoot;staticChecks=$staticChecks;auditSha=$auditSha;qaSha=$qaSha;push=$push;test=$test;install=$install;cycle=$cycle;candidates=$candidates;apiBudgetMutated=$false;newOauthOrScope=$false;newProjectCreated=$false;at=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $readbackDir 'CENTRAL_LEARNING_QA_SYNC.json') -Encoding UTF8
$result|ConvertTo-Json -Depth 30 -Compress
if($status -eq 'RUNTIME_TRIGGER_PASS'){exit 0}else{exit 3}
