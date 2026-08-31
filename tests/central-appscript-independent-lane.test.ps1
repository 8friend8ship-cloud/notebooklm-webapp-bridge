$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bootstrap=Join-Path $root 'local-agent/bootstrap/AgentBootstrap.ps1'
$manifest=Join-Path $root 'local-agent/stable/appscript.json'
if(-not(Test-Path -LiteralPath $bootstrap -PathType Leaf)){throw 'BOOTSTRAP_MISSING'}
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'MANIFEST_MISSING'}

$m=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
$version=[string]$m.version
if([string]::IsNullOrWhiteSpace($version) -or -not$version.StartsWith('appscript-')){throw 'MANIFEST_VERSION_INVALID'}
if(-not([string]$m.channel).StartsWith('appscript-')){throw 'MANIFEST_CHANNEL_INVALID'}
if($m.enabled -ne $true){throw 'MANIFEST_NOT_ENABLED'}
if([string]::IsNullOrWhiteSpace([string]$m.gitBlobSha1)){throw 'MANIFEST_BLOB_MISSING'}
if([string]::IsNullOrWhiteSpace([string]$m.resultReceipt)){throw 'MANIFEST_RECEIPT_MISSING'}
if([int]$m.maxCycleSeconds -lt 180 -or [int]$m.maxCycleSeconds -gt 1800){throw 'MANIFEST_TIMEOUT_OUT_OF_RANGE'}

$repoLanePath=('local-agent/releases/'+$version+'/HomeDesignLocalAgent.ps1')
$lane=Join-Path $root $repoLanePath
if(-not(Test-Path -LiteralPath $lane -PathType Leaf)){throw ('LANE_RELEASE_MISSING:'+ $version)}

# Windows checkout may CRLF-normalize the working-tree file, so hashing local bytes is not
# a valid comparison to the GitHub Contents API blob. Read the canonical blob id from Git's
# object database for HEAD:path instead; this is exactly the value the runtime API exposes.
$repoBlob=(& git rev-parse ('HEAD:'+$repoLanePath) 2>&1|Out-String).Trim().ToLowerInvariant()
if($LASTEXITCODE -ne 0 -or $repoBlob -notmatch '^[0-9a-f]{40}$'){throw ('GIT_OBJECT_BLOB_LOOKUP_FAILED:'+ $repoBlob)}
if($repoBlob -ne ([string]$m.gitBlobSha1).ToLowerInvariant()){throw ('MANIFEST_RELEASE_BLOB_MISMATCH repo='+$repoBlob+' expected='+[string]$m.gitBlobSha1)}

foreach($p in @($bootstrap,$lane)){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){throw ('PARSE_FAIL:'+ $p+':'+($errors.Message -join '|'))}
}

$b=Get-Content -Raw -LiteralPath $bootstrap
$l=Get-Content -Raw -LiteralPath $lane
$mustBootstrap=@(
  "`$AppScriptAgentFile = Join-Path `$Root 'HomeDesignLocalAgent-appscript.ps1'",
  "`$AppScriptLaneStateFile = Join-Path `$Root 'state-appscript.json'",
  "ApplyIndependentLane 'local-agent/stable/appscript.json' 'APPSCRIPT' `$AppScriptAgentFile `$AppScriptLaneStateFile",
  "ApplyIndependentLane 'local-agent/stable/flow.json' 'FLOW'",
  "ApplyIndependentLane 'local-agent/stable/image.json' 'IMAGE'"
)
foreach($needle in $mustBootstrap){if(-not$b.Contains($needle)){throw ('BOOTSTRAP_CONTRACT_MISSING:'+ $needle)}}
if(([regex]::Matches($b,"ApplyIndependentLane 'local-agent/stable/appscript\.json' 'APPSCRIPT'")).Count -ne 1){throw 'APPSCRIPT_LANE_CALL_COUNT_NOT_ONE'}

$commonLane=@(
  '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk',
  'AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P',
  'CENTRAL_APPS_SCRIPT_BOUND_READONLY_WEBAPP_TEMPLATE_03_RESULT.json'
)
foreach($needle in $commonLane){if(-not$l.Contains($needle)){throw ('COMMON_LANE_CONTRACT_MISSING:'+ $needle)}}

# Reject executable mutation patterns. Literal strings used by self-audit scanners are allowed.
$forbiddenPatterns=@(
  '&\s+\$clasp\.Source\s+login\b',
  '&\s+\$clasp\.Source\s+create-script\b',
  '&\s+\$clasp\.Source\s+create-deployment\b',
  '&\s+\$clasp\.Source\s+(?:deploy|redeploy)\b',
  'ScriptApp\.newTrigger\s*\(',
  'Stop-Process\s+-Name\s+chrome',
  'taskkill\.exe\s+/IM\s+chrome\.exe'
)
foreach($pattern in $forbiddenPatterns){if($l -match $pattern){throw ('LANE_FORBIDDEN_PATTERN:'+ $pattern)}}

# Version-specific behavior belongs to its dedicated contract test; this regression only
# guarantees that the manifest-selected release remains isolated, parseable, blob-pinned,
# exact-targeted, and free of direct project/deployment/OAuth/Chrome mutations.
Write-Host ('CENTRAL_APPSCRIPT_INDEPENDENT_LANE_STATIC_PASS version='+$version+' blob='+$repoBlob)
