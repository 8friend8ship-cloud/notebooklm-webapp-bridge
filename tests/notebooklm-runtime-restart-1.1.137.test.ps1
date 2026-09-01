$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agent=Join-Path $root 'local-agent/releases/1.1.137/HomeDesignLocalAgent.ps1'
$manifest=Join-Path $root 'local-agent/stable/agent.json'
$child=Join-Path $root 'local-agent/governor/DiagnoseNotebookLMAutoPoll.ps1'
foreach($p in @($agent,$manifest,$child)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}
$tokens=$null;$parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($agent,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count -gt 0){throw ('AGENT_PARSE_FAIL:'+($parseErrors|ForEach-Object{$_.Message}) -join '|')}
$m=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
$a=Get-Content -LiteralPath $agent -Raw -Encoding UTF8
if([string]$m.version -ne '1.1.137'){throw 'MANIFEST_VERSION_MISMATCH'}
if([string]$m.channel -ne 'stable'){throw 'MANIFEST_CHANNEL_MISMATCH'}
if($m.enabled -ne $true){throw 'MANIFEST_DISABLED'}
if([string]$m.resultReceipt -ne 'AGENT_1.1.137_NOTEBOOKLM_RUNTIME_RESTART_RESULT.json'){throw 'MANIFEST_RECEIPT_MISMATCH'}
$agentRepoPath='local-agent/releases/1.1.137/HomeDesignLocalAgent.ps1'
$agentBlob=(& git rev-parse ("HEAD:"+$agentRepoPath)).Trim()
if($LASTEXITCODE -ne 0){throw 'AGENT_BLOB_LOOKUP_FAILED'}
if($agentBlob.ToLowerInvariant() -ne ([string]$m.gitBlobSha1).ToLowerInvariant()){throw ('MANIFEST_AGENT_BLOB_MISMATCH actual='+$agentBlob+' expected='+[string]$m.gitBlobSha1)}
$childBlob=(& git rev-parse 'HEAD:local-agent/governor/DiagnoseNotebookLMAutoPoll.ps1').Trim()
if($LASTEXITCODE -ne 0){throw 'CHILD_BLOB_LOOKUP_FAILED'}
if($childBlob.ToLowerInvariant() -ne 'd035e37d8093a07737a7e7ada16e36e5959c4d9d'){throw ('CHILD_BLOB_MISMATCH:'+ $childBlob)}
$must=@(
  "`$ChildPath='local-agent/governor/DiagnoseNotebookLMAutoPoll.ps1'",
  "`$ExpectedChildBlob='d035e37d8093a07737a7e7ada16e36e5959c4d9d'",
  "AGENT_1.1.137_NOTEBOOKLM_RUNTIME_RESTART_RESULT.json",
  "DIAGNOSTIC_BLOB_MISMATCH",
  "NOTEBOOKLM_SERVICE_WORKER_NOT_FOUND",
  "DEDICATED_NOTEBOOKLM_CHROME_NOT_RUNNING",
  "https://notebook.google.com/",
  "http://127.0.0.1:9223/json/list",
  "normalChromeTouched=`$false",
  "oauthChanged=`$false",
  "scopeChanged=`$false",
  "extensionFilesChanged=`$false"
)
foreach($needle in $must){if(-not$a.Contains($needle)){throw ('CONTRACT_MISSING:'+ $needle)}}
$forbidden=@('FLOW_DIRECT_BOOTSTRAP','Test-FlowCanonicalExtension','ScriptApp.newTrigger','clasp login','taskkill.exe /IM chrome.exe','Stop-Process -Name chrome','chrome://extensions')
foreach($needle in $forbidden){if($a.Contains($needle)){throw ('FORBIDDEN:'+ $needle)}}
Write-Host 'NOTEBOOKLM_RUNTIME_RESTART_1_1_137_STATIC_PASS'
