param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='1.1.92'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$SourceHelper=Join-Path $Root 'RunNotebookLMExactOrderedResearchAudioV1.ps1'
$PatchedHelper=Join-Path $Root 'RunNotebookLMExactOrderedResearchAudioV3-keywordfix.ps1'
$ExpectedSourceSha='93599b4525369f8eaa0fedafb7a00a715e0085d0'
$Raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/diagnostics/RunNotebookLMExactOrderedResearchAudioV1.ps1'
$Stdout=Join-Path $Root 'AGENT_1.1.92.stdout.log'
$Stderr=Join-Path $Root 'AGENT_1.1.92.stderr.log'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveCentral([string]$Name,$Object){try{$central=FindCentral;if(-not $central){return ''};$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}}
$result=[ordered]@{ok=$false;action='AGENT_1.1.92_EXACT_ORDER_KEYWORDFIX';version=$Version;startedAt=(Get-Date).ToString('o');sourceHelperSha=$ExpectedSourceSha;sourceFetch='';patchApplied=$false;patchedHelperSha='';helperExit=$null;stage='START';notebookUrl='';titleVerified=$false;sourceVerified=$false;sourceCount=0;chatSubmitted=$false;studioSelected=$false;generateClicked=$false;artifactReady=$false;bridgeChanged=$false;normalChromeTouched=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
$m=New-Object Threading.Mutex($false,'HomeDesignNotebookLMExactOrderedResearchAudioV1')
$held=$false
try{
  $held=$m.WaitOne(0,$false)
  if(-not $held){throw 'EXACT_ORDERED_NOTEBOOKLM_ALREADY_RUNNING'}
  if((Test-Path -LiteralPath $SourceHelper) -and (GitBlobSha1 $SourceHelper).ToLowerInvariant() -eq $ExpectedSourceSha){$result.sourceFetch='LOCAL_VERIFIED'}else{Invoke-WebRequest -UseBasicParsing -Uri ($Raw+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $SourceHelper -TimeoutSec 30;$actual=(GitBlobSha1 $SourceHelper).ToLowerInvariant();if($actual -ne $ExpectedSourceSha){throw ('SOURCE_HELPER_SHA_MISMATCH actual='+$actual)};$result.sourceFetch='RAW_VERIFIED'}
  $txt=Get-Content -LiteralPath $SourceHelper -Raw -Encoding UTF8
  if(-not $txt.Contains('return$z.result')){throw 'RETURN_RUNTIME_PATCH_ANCHOR_NOT_FOUND'}
  if(-not $txt.Contains("throw'")){throw 'THROW_RUNTIME_PATCH_ANCHOR_NOT_FOUND'}
  $patched=$txt.Replace('return$z.result','return $z.result').Replace("throw'","throw '")
  if($patched.Contains('return$z.result') -or $patched.Contains("throw'")){throw 'KEYWORD_RUNTIME_PATCH_NOT_COMPLETE'}
  $patched|Set-Content -LiteralPath $PatchedHelper -Encoding UTF8
  $result.patchApplied=$true
  $result.patchedHelperSha=GitBlobSha1 $PatchedHelper
  $tokens=$null;$parseErrors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($PatchedHelper,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count -gt 0){throw ('PATCHED_HELPER_PARSE_FAIL '+(($parseErrors|ForEach-Object{$_.Message})-join' | '))}
  Remove-Item $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
  $p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$PatchedHelper+'"')) -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden
  if(-not $p.WaitForExit(1200000)){try{$p.Kill()}catch{};throw 'HELPER_TIMEOUT_20M'}
  $result.helperExit=[int]$p.ExitCode
  $out=''
  if(Test-Path $Stdout){$out+=Get-Content $Stdout -Raw -Encoding UTF8}
  if(Test-Path $Stderr){$e=Get-Content $Stderr -Raw -Encoding UTF8;if($e){$out+="`n"+$e}}
  $payload=$null
  foreach($line in @($out -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 50)){try{$j=$line|ConvertFrom-Json;if($j){$payload=$j}}catch{}}
  if(-not $payload){throw ('HELPER_RESULT_JSON_NOT_FOUND '+$out.Trim())}
  $result.stage=[string]$payload.stage
  $result.notebookUrl=[string]$payload.notebookUrl
  $result.titleVerified=[bool]$payload.titleVerified
  $result.sourceVerified=[bool]$payload.sourceVerified
  $result.sourceCount=[int]$payload.sourceCount
  $result.chatSubmitted=[bool]$payload.chatSubmitted
  $result.studioSelected=[bool]$payload.studioSelected
  $result.generateClicked=[bool]$payload.generateClicked
  $result.artifactReady=[bool]$payload.artifactReady
  if($payload.error){$result.error=[string]$payload.error}
  $result.ok=([bool]$payload.ok -and $result.titleVerified -and $result.sourceVerified -and $result.sourceCount -gt 0 -and $result.chatSubmitted -and $result.studioSelected -and $result.generateClicked -and $result.artifactReady)
  if(-not $result.ok -and -not $result.error){$result.error='EXACT_ORDER_KEYWORDFIX_GATE_FAILED'}
}catch{$result.error=$_.Exception.Message}
finally{if($held){try{$m.ReleaseMutex()}catch{}};$m.Dispose();$result.completedAt=(Get-Date).ToString('o');$result.centralPath=SaveCentral 'AGENT_1.1.92_EXACT_ORDER_KEYWORDFIX_RESULT.json' $result}
$result|ConvertTo-Json -Depth 60 -Compress
if($result.ok){exit 0}else{exit 2}
