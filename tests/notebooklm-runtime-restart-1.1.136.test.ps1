$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agent=Join-Path $root 'local-agent/releases/1.1.136/HomeDesignLocalAgent.ps1'
$manifest=Join-Path $root 'local-agent/stable/agent.json'
foreach($p in @($agent,$manifest)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($agent,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ('PARSE_FAIL:'+($errors.Message -join '|'))}
$a=Get-Content -LiteralPath $agent -Raw -Encoding UTF8
$m=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$m.version-ne'1.1.136'){throw 'MANIFEST_VERSION_MISMATCH'}
if([string]$m.channel-ne'stable'){throw 'MANIFEST_CHANNEL_MISMATCH'}
if($m.enabled-ne$true){throw 'MANIFEST_DISABLED'}
if([string]$m.resultReceipt-ne'AGENT_1.1.136_NOTEBOOKLM_RUNTIME_RESTART_RESULT.json'){throw 'MANIFEST_RECEIPT_MISMATCH'}
$repoPath='local-agent/releases/'+[string]$m.version+'/'+[string]$m.file
$gitBlob=(& git rev-parse ("HEAD:"+$repoPath)).Trim()
if($LASTEXITCODE-ne0){throw 'GIT_BLOB_LOOKUP_FAILED'}
if($gitBlob.ToLowerInvariant()-ne([string]$m.gitBlobSha1).ToLowerInvariant()){throw ('MANIFEST_BLOB_MISMATCH actual='+$gitBlob+' expected='+[string]$m.gitBlobSha1)}
$must=@(
  "`$DedicatedUserData=Join-Path `$Base 'ChromeUserData'",
  "`$ExtensionRoot=Join-Path `$Base 'Extension\\NotebookLM-WebApp-Bridge'",
  "`$Port=9223",
  "`$NotebookHome='https://notebook.google.com/'",
  "NOTEBOOKLM_SERVICE_WORKER_NOT_FOUND",
  "NOTEBOOKLM_PAGE_TARGET_NOT_READY",
  "NOTEBOOKLM_AUTO_POLL_ALARM_NOT_READY",
  "pollReadyTasks('stable-runtime-restart-1.1.136')",
  "normalChromeTouched=`$false",
  "oauthChanged=`$false",
  "scopeChanged=`$false",
  "extensionFilesChanged=`$false",
  "AGENT_1.1.136_NOTEBOOKLM_RUNTIME_RESTART_RESULT.json"
)
foreach($needle in $must){if(-not$a.Contains($needle)){throw ('CONTRACT_MISSING:'+ $needle)}}
$forbidden=@(
  'FLOW_DIRECT_BOOTSTRAP',
  'Test-FlowCanonicalExtension',
  'Image',
  'clasp login',
  'ScriptApp.newTrigger',
  'Stop-Process -Name chrome',
  'taskkill.exe /IM chrome.exe',
  'chrome://extensions'
)
foreach($needle in $forbidden){if($a.Contains($needle)){throw ('FORBIDDEN:'+ $needle)}}
if(([regex]::Matches($a,'Stop-Process -Id')).Count-lt1){throw 'DEDICATED_PID_STOP_MISSING'}
if($a -notmatch '\-like\s+"\*\$DedicatedUserData\*"'){throw 'DEDICATED_PROCESS_FILTER_MISSING'}
Write-Host 'NOTEBOOKLM_RUNTIME_RESTART_1_1_136_STATIC_PASS'
