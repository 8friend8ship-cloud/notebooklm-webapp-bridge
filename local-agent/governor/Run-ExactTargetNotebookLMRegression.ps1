param(
 [string]$NotebookUrl='https://notebook.google.com/notebook/69e055e5-c8d0-4e9c-8686-58cc6da35a51',
 [int]$DebugPort=9231
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7';$Managed=Join-Path $Base 'ManagedExtensions';$StatePath=Join-Path $Managed 'autopilot-state.json';New-Item -ItemType Directory -Force -Path $Managed|Out-Null
$launcher=Join-Path $env:TEMP ('ManagedExtensionExactTargetLauncher_'+[guid]::NewGuid().ToString('N')+'.ps1')
$repo='8friend8ship-cloud/notebooklm-webapp-bridge';$url='https://raw.githubusercontent.com/'+$repo+'/main/local-agent/governor/ManagedExtensionExactTargetLauncher.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $launcher -TimeoutSec 30
$expected='d352572c532aea3e2d76b580e2129bfa3fa4d68b'
function GitBlob([string]$p){$b=[IO.File]::ReadAllBytes($p);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|%{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
if((GitBlob $launcher) -ne $expected){throw 'EXACT_LAUNCHER_SHA_MISMATCH'}
$paths=@((Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'),(Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge-CANONICAL'),(Join-Path $Base 'Extension\NotebookLM'))|Where-Object{Test-Path -LiteralPath (Join-Path $_ 'manifest.json') -PathType Leaf
if(-not $paths){$paths=@(Get-ChildItem -LiteralPath (Join-Path $Base 'Extension') -Filter manifest.json -Recurse -File -ErrorAction SilentlyContinue|Where-Object{try{(Get-Content $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json).name -match 'NotebookLM'}catch{$false}}|Select-Object -First 1|ForEach-Object{$_.Directory.FullName})}
if(-not $paths){throw 'NOTEBOOKLM_EXTENSION_PATH_NOT_FOUND'};$extPath=[string]$paths[0]
$state=$null;if(Test-Path $StatePath){try{$state=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}};if(-not $state){$state=[pscustomobject]@{schema='MANAGED_EXTENSION_AUTOPILOT_STATE_V1';version='EXACT_TARGET_BOOTSTRAP';updatedAt='';extensions=@();history=@();policy=[pscustomobject]@{noNormalChromeRestart=$true;dedicatedChromeOnly=$true}}}
$found=@($state.extensions|Where-Object{$_.expectedExtensionId -eq 'llgjlejpknemhdmckoaifgjnjikceamp' -or $_.name -match 'NotebookLM'}|Select-Object -First 1)
if($found.Count){$e=$found[0];$e|Add-Member activePath $extPath -Force;$e|Add-Member active $true -Force;$e|Add-Member expectedExtensionId 'llgjlejpknemhdmckoaifgjnjikceamp' -Force}else{$state.extensions=@($state.extensions)+@([pscustomobject]@{name='NotebookLM WebApp Bridge CANONICAL';version='runtime';expectedExtensionId='llgjlejpknemhdmckoaifgjnjikceamp';activePath=$extPath;active=$true})}
$state.updatedAt=(Get-Date).ToString('o');$state|ConvertTo-Json -Depth 30|Set-Content $StatePath -Encoding UTF8
function RunOne([int]$n){$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $launcher -Service NOTEBOOKLM -TargetUrl $NotebookUrl -ExpectedUrlPattern 'notebook(lm)?\.google\.com/(notebook|notebook/)' -ExpectedExtensionId 'llgjlejpknemhdmckoaifgjnjikceamp' -RemoteDebuggingPort ($DebugPort+$n-1) -TimeoutSeconds 35 -RestartDedicatedChrome -ProbeInput -Sentinel ('CENTRAL_NLM_EXACT_WINDOW_X'+$n+'_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) 2>&1;$exit=$LASTEXITCODE;$text=($out|Out-String).Trim();$obj=$null;try{$obj=(($text -split "`r?`n")[-1]|ConvertFrom-Json)}catch{};return [pscustomobject]@{exit=$exit;text=$text;result=$obj}}
$r1=RunOne 1;$r2=$null;if($r1.exit -eq 0 -and $r1.result.ok){$r2=RunOne 2}
$ok=[bool]($r1.exit -eq 0 -and $r1.result.ok -and $r2 -and $r2.exit -eq 0 -and $r2.result.ok)
$central='';$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){foreach($c in @((Join-Path $d.Root $target),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('My Drive\'+$target)))){if(Test-Path $c -PathType Container){$central=$c;break}};if($central){break}}
$result=[ordered]@{ok=$ok;action='NOTEBOOKLM_EXACT_TARGET_X2_REGRESSION';extensionPath=$extPath;targetUrl=$NotebookUrl;run1=$r1;run2=$r2;normalChromeExpectedUntouched=$true;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}
if($central){$dir=Join-Path $central 'Runtime_Readback\Chrome_Exact_Target';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$result|ConvertTo-Json -Depth 60|Set-Content (Join-Path $dir 'NOTEBOOKLM_EXACT_TARGET_X2_REGRESSION.json') -Encoding UTF8}
Remove-Item $launcher -Force -ErrorAction SilentlyContinue;$result|ConvertTo-Json -Depth 60 -Compress;if($ok){exit 0}else{exit 2}
