$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agent=Join-Path $root 'local-agent/releases/1.1.138/HomeDesignLocalAgent.ps1'
$manifest=Join-Path $root 'local-agent/stable/agent.json'
foreach($p in @($agent,$manifest)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw('MISSING:'+ $p)}}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($agent,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw('PARSE_FAIL:'+($errors.Message -join '|'))}
$a=Get-Content -LiteralPath $agent -Raw -Encoding UTF8
$m=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$m.version-ne'1.1.138'){throw'MANIFEST_VERSION_MISMATCH'}
if([string]$m.resultReceipt-ne'AGENT_1.1.138_NOTEBOOKLM_FRONT_CONSENT_LOOP_BYPASS_RESULT.json'){throw'MANIFEST_RECEIPT_MISMATCH'}
$repoPath='local-agent/releases/'+[string]$m.version+'/'+[string]$m.file
$blob=(& git rev-parse ('HEAD:'+$repoPath)).Trim()
if($LASTEXITCODE-ne0){throw'GIT_BLOB_LOOKUP_FAILED'}
if($blob.ToLowerInvariant()-ne([string]$m.gitBlobSha1).ToLowerInvariant()){throw('MANIFEST_BLOB_MISMATCH:'+ $blob)}
$must=@(
  "`$PinnedParentPath='local-agent/releases/1.1.137/HomeDesignLocalAgent.ps1'",
  "`$PinnedParentBlob='8a5ebfd07649d6d18f739fc46b0c67a114d9cdf2'",
  "`$FrontPrefix='https://notebooklm-webapp-bridge.vercel.app/'",
  "'/json/close/'",
  'CONTROL_CENTER_FRONT_STILL_OPEN',
  'NOTEBOOKLM_TARGET_LOST_AFTER_FRONT_CLOSE',
  'normalChromeTouched=$false',
  'oauthChanged=$false',
  'scopeChanged=$false',
  'extensionFilesChanged=$false',
  'vercelDeploymentChanged=$false'
)
foreach($needle in $must){if(-not$a.Contains($needle)){throw('CONTRACT_MISSING:'+ $needle)}}
$forbidden=@('Stop-Process -Name chrome','taskkill.exe /IM chrome.exe','clasp login','ScriptApp.newTrigger','FLOW_DIRECT_BOOTSTRAP','ImageGeneration')
foreach($needle in $forbidden){if($a.Contains($needle)){throw('FORBIDDEN:'+ $needle)}}
Write-Host 'NOTEBOOKLM_CONSENT_LOOP_BYPASS_1_1_138_STATIC_PASS'
