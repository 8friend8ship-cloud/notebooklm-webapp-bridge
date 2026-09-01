$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$watchdog=Join-Path $root 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'
if(-not(Test-Path -LiteralPath $watchdog -PathType Leaf)){throw 'WATCHDOG_MISSING'}
$tokens=$null;$parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($watchdog,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count -gt 0){throw ('WATCHDOG_PARSE_FAIL:'+($parseErrors|ForEach-Object{$_.Message}) -join '|')}
$w=Get-Content -LiteralPath $watchdog -Raw -Encoding UTF8
$must=@(
  "`$WatchdogVersion='WATCHDOG_V5_NOTEBOOKLM_RUNTIME_HEALTH_20260901'",
  "`$DedicatedUserData=Join-Path `$Base 'ChromeUserData'",
  "`$NotebookLMCdpUrl='http://127.0.0.1:9223/json/list'",
  'function NotebookLMRuntimeHealth',
  'DEDICATED_CHROME_PROCESS_MISSING',
  "chrome-extension://*/worker.js",
  'notebooklmRuntimeHealthy',
  '-and $notebooklmRuntimeOk',
  'AUTO_RESUME_COMPLETED_V5',
  'notebooklmRuntimeBefore',
  'notebooklmRuntimeAfter'
)
foreach($needle in $must){if(-not$w.Contains($needle)){throw ('WATCHDOG_CONTRACT_MISSING:'+ $needle)}}
$healthCall=$w.IndexOf('$nlm=NotebookLMRuntimeHealth')
$passGate=$w.IndexOf('if($hostOk -and $bootstrapOk -and $stateOk -and $versionOk -and $notebooklmRuntimeOk)')
$autoResumeStart=$w.IndexOf('$psi=New-Object Diagnostics.ProcessStartInfo')
if($healthCall-lt0 -or $passGate-le$healthCall -or $autoResumeStart-le$passGate){throw 'WATCHDOG_GATE_ORDER_INVALID'}
$forbidden=@(
  'Stop-Process -Name chrome',
  'taskkill.exe /IM chrome.exe',
  'ScriptApp.newTrigger',
  'clasp login',
  'Test-FlowCanonicalExtension',
  'FLOW_DIRECT_BOOTSTRAP'
)
foreach($needle in $forbidden){if($w.Contains($needle)){throw ('WATCHDOG_FORBIDDEN:'+ $needle)}}
if(([regex]::Matches($w,'NotebookLMRuntimeHealth')).Count-lt4){throw 'WATCHDOG_NLM_HEALTH_RECHECK_MISSING'}
if($w -notmatch 'Where-Object\{\$_.CommandLine -and \$_.CommandLine -like "\*\$DedicatedUserData\*"\}'){throw 'WATCHDOG_DEDICATED_PROCESS_FILTER_MISSING'}
Write-Host 'NOTEBOOKLM_WATCHDOG_RUNTIME_HEALTH_V5_STATIC_PASS'
