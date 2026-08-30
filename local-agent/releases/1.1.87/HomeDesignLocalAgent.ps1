param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.87'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$SourceHelper=Join-Path $Root 'BindSourceToExactFreshNotebookLMCDPV5.ps1'
$PatchedHelper=Join-Path $Root 'BindSourceToExactFreshNotebookLMCDPV5-connectfix.ps1'
$ExpectedSourceSha='2e39b41c239ceb3becd3be6ca10657445d192baf'
$Raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/diagnostics/BindSourceToExactFreshNotebookLMCDPV5.ps1'
$ResultMarker=Join-Path $Root 'AGENT_1.1.87_EXACT_FRESH_SOURCE_BIND_V5_CONNECTFIX_RESULT.json'
$Stdout=Join-Path $Root 'AGENT_1.1.87.stdout.log';$Stderr=Join-Path $Root 'AGENT_1.1.87.stderr.log'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$myDriveKo=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($myDriveKo+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveCentral([string]$Name,$Object){try{$central=FindCentral;if(-not $central){return ''};$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}}
$result=[ordered]@{ok=$false;action='AGENT_1.1.87_EXACT_FRESH_SOURCE_BIND_V5_CONNECTFIX';version=$Version;startedAt=(Get-Date).ToString('o');sourceHelperSha=$ExpectedSourceSha;patchedHelperSha='';patchApplied=$false;notebookUrl='';sourceAdded=$false;sourceVerified=$false;promptFilled=$false;promptSubmitted=$false;studioSelected=$false;createdNotebook=$false;helperStage='';helperExit=$null;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
try{
  if(-not(Test-Path $SourceHelper) -or (GitBlobSha1 $SourceHelper).ToLowerInvariant() -ne $ExpectedSourceSha){Invoke-WebRequest -UseBasicParsing -Uri ($Raw+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $SourceHelper -TimeoutSec 30}
  $actual=(GitBlobSha1 $SourceHelper).ToLowerInvariant();if($actual -ne $ExpectedSourceSha){throw "SOURCE_HELPER_SHA_MISMATCH actual=$actual"}
  $txt=Get-Content -LiteralPath $SourceHelper -Raw -Encoding UTF8
  $old="function Connect-Page(`$Tab){`$ws=New-Object System.Net.WebSockets.ClientWebSocket;`$cts=New-Object Threading.CancellationTokenSource;`$cts.CancelAfter([Math]::Max(1000,`$CdpCommandTimeoutSeconds*1000));try{`$ws.ConnectAsync([Uri]([string]`$Tab.webSocketDebuggerUrl),`$cts.Token).GetAwaiter().GetResult()}catch{`$ws.Dispose();throw 'CDP_CONNECT_TIMEOUT_OR_FAILED'}finally{`$cts.Dispose()};return `$ws}"
  $new="function Connect-Page(`$Tab){[System.Net.WebSockets.ClientWebSocket]`$socket=New-Object System.Net.WebSockets.ClientWebSocket;[Threading.CancellationTokenSource]`$cts=New-Object Threading.CancellationTokenSource;[void]`$cts.CancelAfter([Math]::Max(1000,`$CdpCommandTimeoutSeconds*1000));try{[void]`$socket.ConnectAsync([Uri]([string]`$Tab.webSocketDebuggerUrl),`$cts.Token).GetAwaiter().GetResult()}catch{`$socket.Dispose();throw 'CDP_CONNECT_TIMEOUT_OR_FAILED'}finally{[void]`$cts.Dispose()};Write-Output -NoEnumerate `$socket}"
  if(-not $txt.Contains($old)){throw 'CONNECT_PAGE_PATCH_ANCHOR_NOT_FOUND'}
  $patched=$txt.Replace($old,$new);$patched|Set-Content -LiteralPath $PatchedHelper -Encoding UTF8;$result.patchApplied=$true;$result.patchedHelperSha=GitBlobSha1 $PatchedHelper
  Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
  $argLine='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PatchedHelper+'" -TargetNotebookId "8d1eda83-cfe3-4487-b2bc-266a5be3465c" -RemoteDebuggingPort 9223 -TimeoutSeconds 120 -CdpCommandTimeoutSeconds 8'
  $p=Start-Process powershell.exe -ArgumentList $argLine -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden;$null=$p.WaitForExit(180000);$result.helperExit=[int]$p.ExitCode
  $out='';if(Test-Path $Stdout){$out+=Get-Content $Stdout -Raw -Encoding UTF8};if(Test-Path $Stderr){$e=Get-Content $Stderr -Raw -Encoding UTF8;if($e){$out+="`n"+$e}}
  $payload=$null;foreach($line in @($out -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 30)){try{$j=$line|ConvertFrom-Json;if($j){$payload=$j}}catch{}};if(-not $payload){throw ('PATCHED_HELPER_RESULT_JSON_NOT_FOUND: '+$out.Trim())}
  $result.notebookUrl=[string]$payload.notebookUrl;$result.sourceAdded=[bool]$payload.sourceAdded;$result.sourceVerified=[bool]$payload.sourceVerified;$result.promptFilled=[bool]$payload.promptFilled;$result.promptSubmitted=[bool]$payload.promptSubmitted;$result.studioSelected=[bool]$payload.studioSelected;$result.createdNotebook=[bool]$payload.createdNotebook;$result.helperStage=[string]$payload.stage;if($payload.error){$result.error=[string]$payload.error}
  $result.ok=([bool]$payload.ok -and $result.sourceVerified -and $result.notebookUrl -eq 'https://notebook.google.com/notebook/8d1eda83-cfe3-4487-b2bc-266a5be3465c' -and -not $result.createdNotebook);if(-not $result.ok -and -not $result.error){$result.error='CONNECTFIX_GATE_FAILED'}
}catch{$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.87_EXACT_FRESH_SOURCE_BIND_V5_CONNECTFIX_RESULT.json' $result;$result|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $ResultMarker -Encoding UTF8}
$result|ConvertTo-Json -Depth 50 -Compress
if($result.ok){exit 0}else{exit 2}
