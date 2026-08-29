param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.80'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$OutLocal=Join-Path $Root 'AGENT_1.1.80_INSPECT_1.1.79.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function ReadRaw([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return ''};try{return [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)}catch{return ''}}
function ReadJson([string]$Path){$r=ReadRaw $Path;if(-not $r){return $null};try{return $r|ConvertFrom-Json}catch{return $null}}
function SetProp($Obj,[string]$Name,$Value){if($Obj.PSObject.Properties[$Name]){$Obj.$Name=$Value}else{$Obj|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}}
function GitBlobSha1([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return ''};$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentralRoot{$centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$rr=[string]$drv.Root;if(-not $rr){continue};foreach($cand in @((Join-Path $rr $centralName),(Join-Path $rr ($myDriveKo+'\'+$centralName)),(Join-Path $rr ('My Drive\'+$centralName)),(Join-Path $rr ('Google Drive\'+$centralName))){if(Test-Path -LiteralPath $cand -PathType Container){return $cand}}};return ''}
function Clip([string]$s,[int]$n=24000){if(-not $s){return ''};if($s.Length -le $n){return $s};return $s.Substring(0,$n)+'...[TRUNCATED]'}
$targets=[ordered]@{
  result1179=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3_RESULT.json'
  dispatch1179=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3.dispatched'
  stdout1179=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3.stdout.log'
  stderr1179=Join-Path $Root 'AGENT_1.1.79_FRESH_NOTEBOOK_V3.stderr.log'
  helperV3=Join-Path $Root 'NotebookLM-Fresh-Notebook-Source-CDP-V3.ps1'
  result1178=Join-Path $Root 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT_RESULT.json'
  dispatch1178=Join-Path $Root 'AGENT_1.1.78_FRESH_NOTEBOOK_DIRECT.dispatched'
}
$diag=[ordered]@{ok=$true;action='AGENT_1.1.80_INSPECT_1.1.79';agentVersion=$AgentVersion;at=(Get-Date).ToString('o');normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;stateBefore='';files=[ordered]@{};helperV3Sha='';helperV3ExpectedSha='5e80c0ee3e809f573ee3f9b5af28dedbdb700b82';helperProcesses=@();notebookTabs=@();freshNotebookCandidates=@();centralPath='';error=''}
try{
  $diag.stateBefore=Clip (ReadRaw $StateFile) 12000
  foreach($k in $targets.Keys){$p=[string]$targets[$k];$exists=Test-Path -LiteralPath $p;$raw=if($exists){Clip (ReadRaw $p)}else{''};$diag.files[$k]=[ordered]@{path=$p;exists=$exists;size=if($exists){(Get-Item -LiteralPath $p).Length}else{0};modified=if($exists){(Get-Item -LiteralPath $p).LastWriteTime.ToString('o')}else{''};raw=$raw}}
  if(Test-Path -LiteralPath $targets.helperV3){$diag.helperV3Sha=GitBlobSha1 ([string]$targets.helperV3)}
  try{$diag.helperProcesses=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name -match 'powershell|pwsh' -and $_.CommandLine -and ($_.CommandLine -like '*NotebookLM*Fresh*' -or $_.CommandLine -like '*Test-NotebookLMClaimStartBridge*')}|ForEach-Object{[ordered]@{pid=[int]$_.ProcessId;name=[string]$_.Name;commandLine=[string]$_.CommandLine}})}catch{}
  try{$tabs=@(Invoke-RestMethod -Uri 'http://127.0.0.1:9223/json/list' -TimeoutSec 4);$diag.notebookTabs=@($tabs|Where-Object{[string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/*'}|ForEach-Object{[ordered]@{id=[string]$_.id;title=[string]$_.title;url=[string]$_.url}});$diag.freshNotebookCandidates=@($diag.notebookTabs|Where-Object{$_.url -match '/notebook/([0-9a-fA-F-]+)' -and $Matches[1] -ne '69e055e5-c8d0-4e9c-8686-58cc6da35a51'})}catch{$diag.error='CDP_LIST_READ_FAILED: '+$_.Exception.Message}
  $s=ReadJson $StateFile;if(-not $s){$s=[pscustomobject]@{ok=$true;status='AGENT_APPLIED'}};SetProp $s 'agentVersion' $AgentVersion;SetProp $s 'agentMode' 'READ_ONLY_FRESH_1179_DIAGNOSTIC';SetProp $s 'updatedAt' (Get-Date).ToString('o');$tmp=$StateFile+'.1180.tmp';$s|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}catch{$diag.ok=$false;$diag.error=$_.Exception.Message}
$json=$diag|ConvertTo-Json -Depth 50
$json|Set-Content -LiteralPath $OutLocal -Encoding UTF8
try{$central=FindCentralRoot;if($central){$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$dest=Join-Path $dir 'AGENT_1.1.80_INSPECT_1.1.79.json';$json|Set-Content -LiteralPath $dest -Encoding UTF8;$diag.centralPath=$dest;$json=$diag|ConvertTo-Json -Depth 50;$json|Set-Content -LiteralPath $OutLocal -Encoding UTF8;$json|Set-Content -LiteralPath $dest -Encoding UTF8}}
catch{$diag.ok=$false;$diag.error=if($diag.error){$diag.error+'; CENTRAL_WRITE_FAILED: '+$_.Exception.Message}else{'CENTRAL_WRITE_FAILED: '+$_.Exception.Message};$json=$diag|ConvertTo-Json -Depth 50;$json|Set-Content -LiteralPath $OutLocal -Encoding UTF8}
$diag|ConvertTo-Json -Depth 50 -Compress
if($diag.ok){exit 0}else{exit 2}
