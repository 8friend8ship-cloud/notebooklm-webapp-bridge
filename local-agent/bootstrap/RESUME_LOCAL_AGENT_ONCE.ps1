param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Bootstrap=Join-Path $Root 'AgentBootstrap.ps1'
$AgentFile=Join-Path $Root 'HomeDesignLocalAgent.ps1'
$StateFile=Join-Path $Root 'state.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function ApiContent([string]$Path){$h=@{'User-Agent'='HomeDesign-Local-Agent-Resume';'Accept'='application/vnd.github+json'};$u='https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-RestMethod -Uri $u -Headers $h -Method Get -TimeoutSec 20}
function DecodeText($R){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$R.content-replace'\s','')))}
function WriteApiFile($R,[string]$Path){[IO.File]::WriteAllBytes($Path,[Convert]::FromBase64String(([string]$R.content-replace'\s','')))}
function RawUrl([string]$Path){'https://raw.githubusercontent.com/'+$Repo+'/main/'+$Path+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
function RawJson([string]$Path){$r=Invoke-WebRequest -UseBasicParsing -Uri (RawUrl $Path) -TimeoutSec 30;return ($r.Content|ConvertFrom-Json)}
function RawFileVerified([string]$Path,[string]$Dest,[string]$Expected){Invoke-WebRequest -UseBasicParsing -Uri (RawUrl $Path) -OutFile $Dest -TimeoutSec 30;$a=(GitBlobSha1 $Dest).ToLowerInvariant();if($Expected -and $a-ne$Expected.ToLowerInvariant()){Remove-Item $Dest -Force -ErrorAction SilentlyContinue;throw ('RAW_SHA_MISMATCH path='+$Path+' actual='+$a+' expected='+$Expected)};return $a}
function TestHostHealth(){try{$x=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return [bool]$x.ok}catch{return $false}}
function SafeKey([string]$v){return ([string]$v-replace'[^A-Za-z0-9_.-]','_')}
function FindCentralRoot{$central=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $central),(Join-Path $r ($my+'\'+$central)),(Join-Path $r ('My Drive\'+$central)),(Join-Path $r ('Google Drive\'+$central)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveCentral([string]$Name,$Object){try{$j=$Object|ConvertTo-Json -Depth 60;$j|Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8;$c=FindCentralRoot;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Name) -Encoding UTF8}}catch{}}
function BootstrapLoopPresent{try{return @((Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{$_.Name-match'powershell|pwsh'-and$_.CommandLine-and$_.CommandLine-like'*AgentBootstrap.ps1*'-and$_.CommandLine-match'(?i)(?:^|\s)-Loop(?:\s|$)'})).Count-gt0}catch{return $false}}
function EnsureBootstrapLoop{if(BootstrapLoopPresent){return $true};try{Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$Bootstrap+'"'),'-Loop') -WindowStyle Hidden|Out-Null;Start-Sleep -Seconds 2;return (BootstrapLoopPresent)}catch{return $false}}

$entry=[ordered]@{ok=$true;action='AUTO_RESUME_ENTRY_HEARTBEAT';version='RESUME_ONE_SHOT_FETCH_FALLBACK_V2_20260830';stage='ENTRY';pid=$PID;hostHealthy=(TestHostHealth);at=(Get-Date).ToString('o')};SaveCentral 'AUTO_RESUME_ENTRY_LATEST.json' $entry
$fetch=[ordered]@{ok=$false;action='AUTO_RESUME_FETCH_PATH';version='RESUME_ONE_SHOT_FETCH_FALLBACK_V2_20260830';stage='START';bootstrap='';meta='';bridge='';agent='';targetAgent='';targetBridge='';error='';startedAt=(Get-Date).ToString('o')}
try{
  $fetch.stage='BOOTSTRAP'
  try{$b=ApiContent 'local-agent/bootstrap/AgentBootstrap.ps1';$tmp=$Bootstrap+'.download';WriteApiFile $b $tmp;if((GitBlobSha1 $tmp).ToLowerInvariant()-ne([string]$b.sha).ToLowerInvariant()){throw 'BOOTSTRAP_SHA_MISMATCH'};Move-Item $tmp $Bootstrap -Force;$fetch.bootstrap='API_VERIFIED'}catch{if(Test-Path -LiteralPath $Bootstrap){$fetch.bootstrap='LOCAL_PRESERVED_API_FAILED'}else{throw}}
  $fetch.stage='META'
  try{$metaResp=ApiContent 'local-agent/stable/agent.json';$meta=(DecodeText $metaResp)|ConvertFrom-Json;$fetch.meta='API'}catch{$meta=RawJson 'local-agent/stable/agent.json';$fetch.meta='RAW'}
  $fetch.stage='BRIDGE'
  try{$bridgeResp=ApiContent 'runtime/stable/release.json';$bridge=(DecodeText $bridgeResp)|ConvertFrom-Json;$fetch.bridge='API'}catch{$bridge=RawJson 'runtime/stable/release.json';$fetch.bridge='RAW'}
  if(-not $meta.enabled){throw 'AGENT_STABLE_DISABLED'};if(-not $bridge.enabled){throw 'BRIDGE_STABLE_DISABLED'}
  $targetAgent=[string]$meta.version;$targetBridge=[string]$bridge.version;$mode=[string]$meta.executionMode;$resultReceipt=[string]$meta.resultReceipt;if(-not $mode){$mode='resident'};$fetch.targetAgent=$targetAgent;$fetch.targetBridge=$targetBridge
  $fetch.stage='AGENT'
  $expected=([string]$meta.gitBlobSha1).ToLowerInvariant();$agentPath='local-agent/releases/'+$targetAgent+'/HomeDesignLocalAgent.ps1';$agentTmp=$AgentFile+'.resume.download'
  try{$ar=ApiContent $agentPath;if(([string]$ar.sha).ToLowerInvariant()-ne$expected){throw 'AGENT_API_SHA_MISMATCH'};WriteApiFile $ar $agentTmp;if((GitBlobSha1 $agentTmp).ToLowerInvariant()-ne$expected){throw 'AGENT_FILE_SHA_MISMATCH'};$fetch.agent='API_VERIFIED'}catch{[void](RawFileVerified $agentPath $agentTmp $expected);$fetch.agent='RAW_VERIFIED'}
  Move-Item $agentTmp $AgentFile -Force;$fetch.ok=$true;$fetch.stage='READY';$fetch.completedAt=(Get-Date).ToString('o');SaveCentral 'AUTO_RESUME_FETCH_PATH_LATEST.json' $fetch
}catch{$fetch.error=$_.Exception.Message;$fetch.completedAt=(Get-Date).ToString('o');SaveCentral 'AUTO_RESUME_FETCH_PATH_LATEST.json' $fetch;exit 2}

$started=(Get-Date).ToString('o');$stdout=Join-Path $Root 'DIRECT_AGENT.stdout.log';$stderr=Join-Path $Root 'DIRECT_AGENT.stderr.log';Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
try{$p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$AgentFile+'"')) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden;if(-not $p.WaitForExit(330000)){try{$p.Kill()}catch{};$directExit=124}else{$directExit=[int]$p.ExitCode}}catch{$directExit=3;[string]$_.Exception.Message|Set-Content $stderr -Encoding UTF8}
$directOut='';if(Test-Path $stdout){$directOut+=Get-Content $stdout -Raw -Encoding UTF8};if(Test-Path $stderr){$e=Get-Content $stderr -Raw -Encoding UTF8;if($e){$directOut+="`n"+$e}}
$direct=[ordered]@{ok=[bool]($directExit-eq0);action='DIRECT_AGENT_APPLY_LATEST';resumeVersion='RESUME_ONE_SHOT_FETCH_FALLBACK_V2_20260830';targetAgent=$targetAgent;targetBridge=$targetBridge;executionMode=$mode;expectedResultReceipt=$resultReceipt;startedAt=$started;completedAt=(Get-Date).ToString('o');exitCode=[int]$directExit;stdout=[string]$directOut;hostHealthy=(TestHostHealth);bootstrapLoopPresent=(BootstrapLoopPresent);fetchAgent=[string]$fetch.agent};SaveCentral 'DIRECT_AGENT_APPLY_LATEST.json' $direct
$loopOk=EnsureBootstrapLoop
if($mode-eq'one_shot'){$final=[ordered]@{ok=[bool]($directExit-eq0);action='ONE_SHOT_RESUME_RESULT';targetAgent=$targetAgent;targetBridge=$targetBridge;executionMode=$mode;directExit=[int]$directExit;bootstrapLoopPresent=[bool]$loopOk;expectedResultReceipt=$resultReceipt;completedAt=(Get-Date).ToString('o')};SaveCentral 'ONE_SHOT_RESUME_RESULT.json' $final;if($directExit-eq0){exit 0}else{exit 2}}

$verifyKey='A'+(SafeKey $targetAgent)+'_B'+(SafeKey $targetBridge);$verifyMarker=Join-Path $Root ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.attempted')
if(-not(Test-Path -LiteralPath $verifyMarker)){$attempt=[ordered]@{ok=$false;action='NOTEBOOKLM_CDP_DOWNLOAD_VERSIONED_RETEST';changedCondition=$true;agentVersion=$targetAgent;bridgeVersion=$targetBridge;verifyKey=$verifyKey;startedAt=(Get-Date).ToString('o');stdout='';exitCode=$null;error=''};try{$helper=Join-Path $Root 'RunNotebookLMExistingDownloadViaCDP.ps1';$hr=ApiContent 'local-agent/governor/RunNotebookLMExistingDownloadViaCDP.ps1';WriteApiFile $hr $helper;if((GitBlobSha1 $helper).ToLowerInvariant()-ne([string]$hr.sha).ToLowerInvariant()){throw 'DOWNLOAD_HELPER_SHA_MISMATCH'};$o=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper 2>&1|Out-String;$attempt.stdout=$o.Trim();$attempt.exitCode=$LASTEXITCODE;$attempt.ok=($LASTEXITCODE-eq0)}catch{$attempt.error=$_.Exception.Message};$attempt.completedAt=(Get-Date).ToString('o');SaveCentral ('NOTEBOOKLM_CDP_DOWNLOAD_'+$verifyKey+'.json') $attempt;Set-Content -LiteralPath $verifyMarker -Value $attempt.completedAt -Encoding ASCII}
$deadline=(Get-Date).AddSeconds(180);while((Get-Date)-lt$deadline){Start-Sleep -Seconds 3;if(Test-Path -LiteralPath $StateFile){try{$s=Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;$av=[string]$s.agentVersion;$bv=[string]$s.extensionVersion;if(-not$bv){$bv=[string]$s.installedVersion};if($av-eq$targetAgent-and(TestHostHealth)-and$bv-eq$targetBridge){exit 0}}catch{}}};exit 2
