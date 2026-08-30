param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.88'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Helper=Join-Path $Root 'RunNotebookLMChatFirstAudioOverviewV1.ps1'
$ExpectedSha='3ef4152bfc4fecdb9192b07365750e6bcb09b03e'
$Raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/diagnostics/RunNotebookLMChatFirstAudioOverviewV1.ps1'
$Stdout=Join-Path $Root 'AGENT_1.1.88.stdout.log';$Stderr=Join-Path $Root 'AGENT_1.1.88.stderr.log'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($myDriveKo+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return$c}}};return''}
function SaveCentral([string]$Name,$Object){try{$central=FindCentral;if(-not$central){return''};$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $p -Encoding UTF8;return$p}catch{return''}}
$result=[ordered]@{ok=$false;action='AGENT_1.1.88_CHAT_FIRST_AUDIO_OVERVIEW';version=$Version;startedAt=(Get-Date).ToString('o');helperSha=$ExpectedSha;helperFetch='';notebookUrl='';modalClosed=$false;chatSelected=$false;promptFilled=$false;promptSubmitted=$false;autoSourceReady=$false;studioSelected=$false;audioClicked=$false;helperStage='';helperExit=$null;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
try{
 if(-not(Test-Path $Helper) -or (GitBlobSha1 $Helper).ToLowerInvariant() -ne $ExpectedSha){Invoke-WebRequest -UseBasicParsing -Uri ($Raw+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Helper -TimeoutSec 30;$result.helperFetch='RAW'}else{$result.helperFetch='LOCAL'}
 $actual=(GitBlobSha1 $Helper).ToLowerInvariant();if($actual-ne$ExpectedSha){throw('HELPER_SHA_MISMATCH actual='+$actual)};$result.helperFetch+='_VERIFIED'
 Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
 $arg='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Helper+'" -TargetNotebookId "8d1eda83-cfe3-4487-b2bc-266a5be3465c" -RemoteDebuggingPort 9223 -TimeoutSeconds 180 -CdpCommandTimeoutSeconds 8'
 $p=Start-Process powershell.exe -ArgumentList $arg -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden;$null=$p.WaitForExit(240000);$result.helperExit=[int]$p.ExitCode
 $out='';if(Test-Path $Stdout){$out+=Get-Content $Stdout -Raw -Encoding UTF8};if(Test-Path $Stderr){$e=Get-Content $Stderr -Raw -Encoding UTF8;if($e){$out+="`n"+$e}}
 $payload=$null;foreach($line in @($out -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 30)){try{$j=$line|ConvertFrom-Json;if($j){$payload=$j}}catch{}}
 if(-not$payload){throw('HELPER_RESULT_JSON_NOT_FOUND '+$out.Trim())}
 foreach($k in @('notebookUrl','modalClosed','chatSelected','promptFilled','promptSubmitted','autoSourceReady','studioSelected','audioClicked','stage','error')){if($payload.PSObject.Properties.Name -contains $k){if($k-eq'stage'){$result.helperStage=[string]$payload.$k}elseif($k-eq'error'){$result.error=[string]$payload.$k}else{$result[$k]=$payload.$k}}}
 $result.ok=([bool]$payload.ok -and [bool]$payload.promptFilled -and [bool]$payload.promptSubmitted -and [bool]$payload.studioSelected -and [bool]$payload.audioClicked -and [string]$payload.notebookUrl -eq 'https://notebook.google.com/notebook/8d1eda83-cfe3-4487-b2bc-266a5be3465c')
 if(-not$result.ok -and -not$result.error){$result.error='CHAT_FIRST_GATE_FAILED'}
}catch{$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.88_CHAT_FIRST_AUDIO_OVERVIEW_RESULT.json' $result}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}else{exit 2}
