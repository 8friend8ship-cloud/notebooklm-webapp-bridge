$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$path=Join-Path $root 'local-agent/releases/1.1.68/HomeDesignLocalAgent.ps1'
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'AGENT1168_MISSING'}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ('AGENT1168_PARSE_FAIL:'+($errors.Message -join '|'))}
$t=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$needles=@(
  "`$AgentVersion='1.1.68'",
  "`$PriorVersion='1.1.67'",
  "`$PriorSha='0044c3633912147ef15d6ecfe551152b73fa63a4'",
  "`$KnownScriptPrefix='1dmbf19qgN6Q-CwLY'",
  "`$ExpectedDeploymentId='AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P'",
  "`$TargetSpreadsheetId='1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk'",
  'Google\Chrome\User Data',
  'Microsoft\Edge\User Data',
  "'History'",
  "'Sessions'",
  '[IO.FileShare]::ReadWrite',
  '[IO.FileShare]::Delete',
  'home/projects/([A-Za-z0-9_-]{40,})',
  'list-deployments',
  'clone-script',
  'NotebookLM_Task_Queue',
  'setupNotebookLMBridge',
  'ONE_PUSH',
  "@('push','--force')",
  'PULL_READBACK',
  'DEPLOYMENT_INVARIANT',
  'NOTEBOOKLM_QUEUE_HISTORY_RECOVERY_V4.json',
  'normalChromeTouched=$false',
  'newProjectCreated=$false',
  'oauthChanged=$false',
  'scopeChanged=$false',
  'newDeployment=$false',
  'newTrigger=$false',
  'creditsSpent=$false'
)
foreach($needle in $needles){if(-not$t.Contains($needle)){throw ('AGENT1168_MISSING_CONTRACT:'+ $needle)}}
foreach($forbidden in @("@('create-script'","@('create-deployment'","@('deploy'","@('redeploy'",'Stop-Process -Name chrome','taskkill.exe /IM chrome.exe')){if($t.Contains($forbidden)){throw ('AGENT1168_FORBIDDEN:'+ $forbidden)}}
$history=$t.IndexOf("`$stage='HISTORY_SCAN'")
$verify=$t.IndexOf("`$stage='CLONE_VERIFY'")
$push=$t.IndexOf("`$stage='ONE_PUSH'")
$readback=$t.IndexOf("`$stage='PULL_READBACK'")
$invariant=$t.IndexOf("`$stage='DEPLOYMENT_INVARIANT'")
if($history -lt 0 -or $verify -le $history -or $push -le $verify -or $readback -le $push -or $invariant -le $readback){throw 'AGENT1168_GATE_ORDER_INVALID'}
$sample='xx https://script.google.com/u/0/home/projects/1dmbf19qgN6Q-CwLYOTx27L8Q6uUD85fZXNSy00AS_HpXBabcdefghi/edit yy'
$m=[regex]::Match($sample,'https?://script\.google\.com/(?:u/\d+/)?home/projects/([A-Za-z0-9_-]{40,})')
if(-not$m.Success -or -not$m.Groups[1].Value.StartsWith('1dmbf19qgN6Q-CwLY')){throw 'AGENT1168_URL_REGEX_FIXTURE_FAIL'}
Write-Host 'AGENT_1.1.68_BOUND_SCRIPT_HISTORY_RECOVERY_STATIC_PASS'