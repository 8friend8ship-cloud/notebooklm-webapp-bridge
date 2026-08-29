param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.75'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ExpectedBridge='0.2.75'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ExtensionRoot=Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$StatePath=Join-Path $Root 'state.json'
$AttemptMarker=Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_HOMEFIX_1.1.75.attempted'
$ResultPath=Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_HOMEFIX_1.1.75.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return(($s.ComputeHash($a)|%{$_.ToString('x2')})-join'')}finally{$s.Dispose()}}
function ApiContent([string]$Path){Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/contents/'+$Path+'?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers @{'User-Agent'='HomeDesign-NLM-Fresh-HomeFix';'Accept'='application/vnd.github+json'} -TimeoutSec 30}
function FindCentralRoot{$c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$m=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($p in @((Join-Path $r $c),(Join-Path $r ($m+'\'+$c)),(Join-Path $r ('My Drive\'+$c)),(Join-Path $r ('Google Drive\'+$c)))){if(Test-Path -LiteralPath $p -PathType Container){return$p}}};return''}
function SaveJson([string]$Path,$Obj){$p=Split-Path -Parent $Path;if($p){New-Item -ItemType Directory -Force -Path $p|Out-Null};$Obj|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}
function Publish($Obj){SaveJson $ResultPath $Obj;$c=FindCentralRoot;if($c){try{SaveJson (Join-Path $c 'Runtime_Readback\NotebookLM\NOTEBOOKLM_FRESH_CREATE_HOMEFIX_1.1.75.json') $Obj}catch{}}}
function State([string]$Status,[string]$Url=''){SaveJson $StatePath ([ordered]@{agentVersion=$AgentVersion;status=$Status;extensionVersion=$ExpectedBridge;notebookUrl=$Url;normalChromeTouched=$false;flowPrerequisite=$false;updatedAt=(Get-Date).ToString('o')})}
if(Test-Path -LiteralPath $AttemptMarker){if(Test-Path -LiteralPath $ResultPath){try{$x=Get-Content $ResultPath -Raw -Encoding UTF8|ConvertFrom-Json;$x|ConvertTo-Json -Depth 50 -Compress;if([bool]$x.ok){exit 0}else{exit 2}}catch{}};exit 2}
Set-Content -LiteralPath $AttemptMarker -Value ((Get-Date).ToString('o')) -Encoding ASCII
$r=[ordered]@{ok=$false;action='NLM_FRESH_CREATE_HOMEFIX';agentVersion=$AgentVersion;verifiedBridge='';helperGitBlob='';helperExitCode=$null;helperStdout='';freshNotebook=$null;normalChromeTouched=$false;flowPrerequisite=$false;startedAt=(Get-Date).ToString('o');error=''}
try{
  $mp=Join-Path $ExtensionRoot 'manifest.json';if(-not(Test-Path $mp)){throw'MANIFEST_NOT_FOUND'};$m=Get-Content $mp -Raw -Encoding UTF8|ConvertFrom-Json;$r.verifiedBridge=[string]$m.version;if($r.verifiedBridge-ne$ExpectedBridge){throw('BRIDGE_NOT_0275:'+ $r.verifiedBridge)}
  $g=ApiContent 'local-agent/governor/CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1';$raw=[Convert]::FromBase64String(([string]$g.content-replace'\s',''));$tmp=Join-Path $Root 'fresh-helper.raw';[IO.File]::WriteAllBytes($tmp,$raw);$sha=(GitBlobSha1 $tmp).ToLowerInvariant();$r.helperGitBlob=$sha;if($sha-ne([string]$g.sha).ToLowerInvariant()){throw'FRESH_HELPER_SHA_MISMATCH'};$helper=Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1';([Text.Encoding]::UTF8.GetString($raw))|Set-Content -LiteralPath $helper -Encoding UTF8;Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -Title "NLM Fresh E2E 2026-08-29 2010" -SourceText "NLM_FRESH_ALL_20260829_2010 fresh notebook container" -RemoteDebuggingPort 9223 -TimeoutSeconds 90';$p=New-Object Diagnostics.Process;$p.StartInfo=$psi;[void]$p.Start();$o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit();$r.helperExitCode=$p.ExitCode;$r.helperStdout=($o+$(if($e){"`nSTDERR:`n"+$e}else{''})).Trim();$jl=@(($o-split"`r?`n")|?{$_.Trim().StartsWith('{')-and$_.Trim().EndsWith('}')})|Select-Object -Last 1;if(-not$jl){throw('FRESH_HELPER_NO_JSON exit='+$p.ExitCode+' stderr='+$e.Trim())};$f=$jl|ConvertFrom-Json;$r.freshNotebook=$f;if($p.ExitCode-ne0-or-not[bool]$f.ok-or[string]::IsNullOrWhiteSpace([string]$f.notebookUrl)){throw('FRESH_NOTEBOOK_CREATE_FAILED:'+ [string]$f.error)};if([string]$f.notebookId-eq'69e055e5-c8d0-4e9c-8686-58cc6da35a51'){throw'FRESH_NOTEBOOK_REUSED_HISTORICAL_ID'};$r.ok=$true;$r.status='FRESH_NOTEBOOK_CREATED';$r.completedAt=(Get-Date).ToString('o');Publish $r;State 'FRESH_NOTEBOOK_CREATED' ([string]$f.notebookUrl)
}catch{$r.error=$_.Exception.Message;$r.status='FAILED_FAIL_CLOSED';$r.completedAt=(Get-Date).ToString('o');Publish $r;State 'FAILED_FAIL_CLOSED'}
$r|ConvertTo-Json -Depth 50 -Compress;if($r.ok){exit 0}else{exit 2}
