param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.17'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$GovRoot=Join-Path $Base 'ChromeGovernor'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$BaseAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.16-base.ps1'
$NodeGov=Join-Path $GovRoot 'chromeGovernorFast.js'
$Policy=Join-Path $GovRoot 'policy.json'
$Release=Join-Path $GovRoot 'release.json'
$Report=Join-Path $GovRoot 'state.json'
$Inventory=Join-Path $GovRoot 'inventory.json'
$NormalRoot=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$DedicatedUserData=Join-Path $Base 'ChromeUserData'
$DedicatedExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$BaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.16/HomeDesignLocalAgent.ps1'
$BaseSha='3f544a02bdf28b6c891430377b9ba519352cde8f'
$NodeUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/2e5870f823fb3895bc01219562bdcac6c35dd9bb/local-agent/governor/chromeGovernorFast.js'
$NodeSha='6b2cc50985e72bfc1d271bcfde675bfb4a77427c'
$PolicyUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/policy.json'
$ReleaseUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/runtime/stable/release.json'
New-Item -ItemType Directory -Force -Path $Root,$GovRoot|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function RefreshVerified([string]$Url,[string]$Path,[string]$Expected){$tmp=$Path+'.download';$u=$Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $tmp -TimeoutSec 60;$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "HASH_MISMATCH actual=$actual expected=$Expected"};Move-Item $tmp $Path -Force}
function Refresh([string]$Url,[string]$Path){$tmp=$Path+'.download';$u=$Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $tmp -TimeoutSec 60;Move-Item $tmp $Path -Force}
function QuoteArgs([object[]]$Items){return (($Items|ForEach-Object{$s=[string]$_;if($s -match '[\s"]'){'"'+($s -replace '"','\"')+'"'}else{$s}})-join ' ')}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function RunProc([string]$File,[string[]]$Args,[int]$TimeoutSec){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$File;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.Arguments=QuoteArgs $Args;$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$ot=$p.StandardOutput.ReadToEndAsync();$et=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit($TimeoutSec*1000)){KillTree ([int]$p.Id);return [ordered]@{ok=$false;exitCode=124;timedOut=$true;stdout='';stderr='TIMEOUT'}};$p.WaitForExit();return [ordered]@{ok=($p.ExitCode -eq 0);exitCode=$p.ExitCode;timedOut=$false;stdout=$ot.Result.Trim();stderr=$et.Result.Trim()}}
function ReadJson([string]$Path){if(-not(Test-Path $Path)){return $null};try{return Get-Content $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path $c){return $c}}};foreach($c in @((Join-Path $env:USERPROFILE ('My Drive\'+$target)),(Join-Path $env:USERPROFILE ('내 드라이브\'+$target)),(Join-Path $env:USERPROFILE ('Google Drive\'+$target)))){if(Test-Path $c){return $c}};return ''}
$mutex=New-Object System.Threading.Mutex($false,'HomeDesignLocalAgent117');if(-not $mutex.WaitOne(0,$false)){exit 0}
try{
  $baseRun=[ordered]@{ok=$false;exitCode=1;stderr='NOT_RUN'}
  try{RefreshVerified $BaseUrl $BaseAgent $BaseSha;$baseRun=RunProc 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$BaseAgent) 90}catch{$baseRun=[ordered]@{ok=$false;exitCode=1;stderr=$_.Exception.Message}}
  $nodeRun=[ordered]@{ok=$false;exitCode=1;stderr='NOT_RUN'}
  try{RefreshVerified $NodeUrl $NodeGov $NodeSha;Refresh $PolicyUrl $Policy;Refresh $ReleaseUrl $Release;$node=Get-Command node.exe -ErrorAction SilentlyContinue;if(-not $node){$node=Get-Command node -ErrorAction SilentlyContinue};if(-not $node){throw 'NODE_NOT_FOUND'};$args=@($NodeGov,'--normalRoot',$NormalRoot,'--dedicatedUserData',$DedicatedUserData,'--dedicatedExtensionRoot',$DedicatedExtensionRoot,'--policy',$Policy,'--release',$Release,'--agentState',$StateFile,'--report',$Report,'--inventory',$Inventory);$nodeRun=RunProc $node.Source $args 60}catch{$nodeRun=[ordered]@{ok=$false;exitCode=1;stderr=$_.Exception.Message}}
  $central=FindCentral;$driveOk=$false
  if($central -and $nodeRun.ok -and (Test-Path $Report) -and (Test-Path $Inventory)){try{$out=Join-Path $central 'Chrome_Extension_Governor';New-Item -ItemType Directory -Force -Path $out|Out-Null;Copy-Item $Report (Join-Path $out 'CHROME_EXTENSION_GOVERNOR_RESULT.json') -Force;Copy-Item $Inventory (Join-Path $out 'CHROME_EXTENSION_INVENTORY.json') -Force;$driveOk=$true}catch{}}
  $existing=ReadJson $StateFile;$s=@{};if($existing){foreach($p in $existing.PSObject.Properties){$s[$p.Name]=$p.Value}}
  $gov=ReadJson $Report;$s.agentVersion=$AgentVersion;$s.agentMode='THIN_COORDINATOR_PLUS_NODE_GOVERNOR_V4';$s.baseAgentVersion='1.1.16';$s.baseAgentOk=[bool]$baseRun.ok;$s.governorMode='AGENT_5MIN_NODE_DIRECT';$s.governorCycleOk=[bool]$nodeRun.ok;$s.governorExitCode=$nodeRun.exitCode;$s.governorError=[string]$nodeRun.stderr;$s.governorDriveSyncOk=$driveOk;$s.governorCentralPath=$central;$s.governorSummary=$(if($gov){$gov.summary}else{$null});$s.updatedAt=(Get-Date).ToString('o')
  $s|ConvertTo-Json -Depth 30|Set-Content $StateFile -Encoding UTF8;$s|ConvertTo-Json -Depth 30|Set-Content $ReadbackFile -Encoding UTF8
  if($central){try{$rd=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $rd|Out-Null;$s|ConvertTo-Json -Depth 30|Set-Content (Join-Path $rd 'VIDEO_LOCAL_RUNTIME_READBACK.json') -Encoding UTF8}catch{}}
  if(-not $nodeRun.ok){exit 17};exit 0
}finally{try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
