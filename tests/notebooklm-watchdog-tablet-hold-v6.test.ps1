$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$watchdog=Join-Path $root 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'
$autoResume=Join-Path $root 'local-agent/bootstrap/HomeDesignAutoResume.ps1'
$resume=Join-Path $root 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1'
foreach($p in @($watchdog,$autoResume,$resume)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('MISSING:'+ $p)}}

foreach($p in @($watchdog,$autoResume,$resume)){
  $tokens=$null;$parseErrors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count -gt 0){throw ('PARSE_FAIL:'+ $p +':'+(($parseErrors|ForEach-Object{$_.Message}) -join '|'))}
}

$w=Get-Content -LiteralPath $watchdog -Raw -Encoding UTF8
$a=Get-Content -LiteralPath $autoResume -Raw -Encoding UTF8
$r=Get-Content -LiteralPath $resume -Raw -Encoding UTF8
$watchdogMust=@(
  "`$WatchdogVersion='WATCHDOG_V6_TABLET_PRIMARY_HOLD_AWARE_20260901'",
  'function StableTargetState',
  'TABLET_PRIMARY_HOLD',
  "action='WATCHDOG_TABLET_PRIMARY_HOLD_V6'",
  'notebooklmRuntimeChecked=$false',
  'autoResumeInvoked=$false',
  'stableMetaReachable=$true',
  'stableEnabled=$false'
)
foreach($needle in $watchdogMust){if(-not$w.Contains($needle)){throw ('WATCHDOG_V6_CONTRACT_MISSING:'+ $needle)}}
$stableCall=$w.IndexOf('$stable=StableTargetState')
$holdGate=$w.IndexOf('if($tabletPrimaryHold)')
$nlmCall=$w.IndexOf('$nlm=NotebookLMRuntimeHealth')
$autoResumeStart=$w.IndexOf('$psi=New-Object Diagnostics.ProcessStartInfo')
if($stableCall-lt0 -or $holdGate-le$stableCall -or $nlmCall-le$holdGate -or $autoResumeStart-le$nlmCall){throw 'WATCHDOG_V6_GATE_ORDER_INVALID'}

$autoMust=@(
  "`$WatchdogLocal=Join-Path `$Root 'HomeDesignLocalWatchdog.ps1'",
  "RefreshFile 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' `$WatchdogLocal 'WATCHDOG'",
  'AUTO_RESUME_START_V6_WATCHDOG_SELF_REFRESH'
)
foreach($needle in $autoMust){if(-not$a.Contains($needle)){throw ('AUTORESUME_WATCHDOG_REFRESH_MISSING:'+ $needle)}}
$watchdogRefresh=$a.IndexOf("RefreshFile 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'")
$bootstrapRefresh=$a.IndexOf("RefreshFile 'local-agent/bootstrap/AgentBootstrap.ps1'")
$resumeRefresh=$a.IndexOf("RefreshFile 'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1'")
if($watchdogRefresh-lt0 -or $bootstrapRefresh-le$watchdogRefresh -or $resumeRefresh-le$bootstrapRefresh){throw 'AUTORESUME_REFRESH_ORDER_INVALID'}

$resumeMust=@(
  "`$WatchdogLocal=Join-Path `$Root 'HomeDesignLocalWatchdog.ps1'",
  "`$AutoResumeLocal=Join-Path `$Root 'HomeDesignAutoResume.ps1'",
  'function RefreshCurrent',
  "RefreshCurrent 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1' `$WatchdogLocal 'WATCHDOG'",
  "RefreshCurrent 'local-agent/bootstrap/HomeDesignAutoResume.ps1' `$AutoResumeLocal 'AUTORESUME'",
  "version='V4_WATCHDOG_SELF_REFRESH_20260901'"
)
foreach($needle in $resumeMust){if(-not$r.Contains($needle)){throw ('RESUME_DELIVERY_CONTRACT_MISSING:'+ $needle)}}
$resumeWatchdogRefresh=$r.IndexOf("RefreshCurrent 'local-agent/bootstrap/HomeDesignLocalWatchdog.ps1'")
$resumeAutoRefresh=$r.IndexOf("RefreshCurrent 'local-agent/bootstrap/HomeDesignAutoResume.ps1'")
$coreStart=$r.IndexOf("$coreUrl='https://raw.githubusercontent.com/'")
if($resumeWatchdogRefresh-lt0 -or $resumeAutoRefresh-le$resumeWatchdogRefresh -or $coreStart-le$resumeAutoRefresh){throw 'RESUME_DELIVERY_ORDER_INVALID'}

$forbidden=@('ScriptApp.newTrigger','clasp login','Stop-Process -Name chrome','taskkill.exe /IM chrome.exe')
foreach($needle in $forbidden){if($w.Contains($needle)-or$a.Contains($needle)-or$r.Contains($needle)){throw ('FORBIDDEN:'+ $needle)}}
Write-Host 'NOTEBOOKLM_WATCHDOG_TABLET_HOLD_V6_STATIC_PASS'
