param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.145-image-task203-privategit-gitobject'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$ParentPath='local-agent/releases/1.1.144-image-task203-privategit-librarian/HomeDesignLocalAgent.ps1'
$ParentSha='c9b9fe80349ef0bef9d2431b06cd54197f05ed2f'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function Blob([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
$parent=Join-Path $Root 'HomeDesignLocalAgent-1.1.144-source.ps1'
$patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.145-patched.ps1'
$url='https://raw.githubusercontent.com/'+$Repo+'/main/'+$ParentPath+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{'User-Agent'='HomeDesign-Task203-GitObject-Fix'} -OutFile $parent -TimeoutSec 30
$actual=(Blob $parent).ToLowerInvariant();if($actual -ne $ParentSha){throw('PARENT_1.1.144_SHA_MISMATCH:'+ $actual)}
$text=Get-Content -LiteralPath $parent -Raw -Encoding UTF8
$oldVersion='$Version=''1.1.144-image-task203-privategit-librarian'''
$oldReceipt='$Receipt=''IMAGE_TASK203_PRIVATEGIT_LIBRARIAN_1.1.144.json'''
$oldVerify='$repairSha=(Blob $repair).ToLowerInvariant();$libSha=(Blob $lib).ToLowerInvariant();if($repairSha -ne $RepairExpectedSha){throw(''REPAIR_SHA_MISMATCH:''+ $repairSha)};if($libSha -ne $LibrarianExpectedSha){throw(''LIBRARIAN_SHA_MISMATCH:''+ $libSha)}'
$newVerify='Push-Location $repo;try{$repairSha=(& git rev-parse ''HEAD:tools/Repair-ContentOS-DriveCacheAppsScript.ps1'' 2>&1|Out-String).Trim().ToLowerInvariant();if($LASTEXITCODE -ne 0){throw ''REPAIR_GIT_OBJECT_SHA_READ_FAILED''};$libSha=(& git rev-parse ''HEAD:apps-script/Central_Librarian_Knowledge_Automation.gs'' 2>&1|Out-String).Trim().ToLowerInvariant();if($LASTEXITCODE -ne 0){throw ''LIBRARIAN_GIT_OBJECT_SHA_READ_FAILED''}}finally{Pop-Location};if($repairSha -ne $RepairExpectedSha){throw(''REPAIR_GIT_OBJECT_SHA_MISMATCH:''+ $repairSha)};if($libSha -ne $LibrarianExpectedSha){throw(''LIBRARIAN_GIT_OBJECT_SHA_MISMATCH:''+ $libSha)}'
if(-not $text.Contains($oldVersion)){throw 'PARENT_VERSION_MARKER_MISSING'}
if(-not $text.Contains($oldReceipt)){throw 'PARENT_RECEIPT_MARKER_MISSING'}
if(-not $text.Contains($oldVerify)){throw 'PARENT_WORKTREE_SHA_BLOCK_MISSING'}
$text=$text.Replace($oldVersion,'$Version=''1.1.145-image-task203-privategit-gitobject''')
$text=$text.Replace($oldReceipt,'$Receipt=''IMAGE_TASK203_PRIVATEGIT_LIBRARIAN_1.1.145.json''')
$text=$text.Replace($oldVerify,$newVerify)
Set-Content -LiteralPath $patched -Value $text -Encoding UTF8
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $patched
$code=$LASTEXITCODE
exit $code
