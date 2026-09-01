param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.148-image-task203-deploymentid-script-discovery'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ParentPath='local-agent/releases/1.1.145-image-task203-privategit-gitobject/HomeDesignLocalAgent.ps1'
$ParentSha='a8ac8605163aac48ac05271414112dbaf2a5e0fe'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
$parent=Join-Path $Root 'HomeDesignLocalAgent-1.1.145-source.ps1'
$patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.148-patched.ps1'
$url='https://raw.githubusercontent.com/'+$Repo+'/main/'+$ParentPath+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{'User-Agent'='HomeDesign-Task203-DeploymentId-Discovery'} -OutFile $parent -TimeoutSec 30
$actual=(Blob $parent).ToLowerInvariant();if($actual-ne$ParentSha){throw('PARENT_1.1.145_SHA_MISMATCH:'+ $actual)}
$text=Get-Content -LiteralPath $parent -Raw -Encoding UTF8
$text=$text.Replace("$Version='1.1.145-image-task203-privategit-gitobject'","$Version='1.1.148-image-task203-deploymentid-script-discovery'")
$text=$text.Replace("$Receipt='IMAGE_TASK203_PRIVATEGIT_LIBRARIAN_1.1.145.json'","$Receipt='IMAGE_TASK203_DEPLOYMENTID_LIBRARIAN_1.1.148.json'")
$pattern="(?s)\$r\.stage='LIBRARIAN_SAME_SCRIPT_PRECHECK';.*?\$deployBefore=GetDeployments \$scriptId;"
if([regex]::Matches($text,$pattern).Count-ne1){throw('PRECHECK_BLOCK_MATCH_COUNT_'+[regex]::Matches($text,$pattern).Count)}
$new=@'
$r.stage='LIBRARIAN_SAME_SCRIPT_PRECHECK';$auth=(& clasp show-authorized-user --json 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw 'EXISTING_CLASP_AUTH_NOT_AVAILABLE'};$list=(& clasp list-scripts 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw 'CLASP_LIST_SCRIPTS_FAILED'};$ids=@([regex]::Matches($list,'[A-Za-z0-9_-]{30,}')|ForEach-Object{$_.Value}|Sort-Object -Unique);$exact=@();foreach($sid in $ids){$dt=(& clasp list-deployments $sid 2>&1|Out-String);if($LASTEXITCODE-ne0){continue};if($dt -match [regex]::Escape($DeploymentId)){$exact+=$sid}};$exact=@($exact|Sort-Object -Unique);if($exact.Count-ne1){throw('SCRIPT_DEPLOYMENT_MATCH_COUNT_'+$exact.Count)};$scriptId=[string]$exact[0];$r.scriptId=$scriptId;$deployBefore=GetDeployments $scriptId;
'@
$text=[regex]::Replace($text,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$new},1)
Set-Content -LiteralPath $patched -Value $text -Encoding UTF8
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $patched
exit $LASTEXITCODE
