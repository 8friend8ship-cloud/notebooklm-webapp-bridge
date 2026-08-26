param(
  [string]$AuditJson = "$env:USERPROFILE\Desktop\CHROME_ALL_EXTENSIONS_AUDIT.json",
  [string]$OutJson   = "$env:USERPROFILE\Desktop\CHROME_ALL_EXTENSIONS_CLASSIFIED.json",
  [string]$OutTxt    = "$env:USERPROFILE\Desktop\CHROME_ALL_EXTENSIONS_CLASSIFIED.txt"
)

$ErrorActionPreference = 'Stop'

function Get-PropValue($obj, [string[]]$names) {
  foreach ($n in $names) {
    if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains $n) { return $obj.$n }
  }
  return $null
}

if (-not (Test-Path -LiteralPath $AuditJson)) {
  $result = [ordered]@{
    overall = 'LIVE_READBACK_REQUIRED'
    reason = 'Audit JSON not found on this PC. Run RUN_AUDIT_ALL_CHROME_EXTENSIONS.cmd first.'
    audit_json = $AuditJson
    generated_at = (Get-Date).ToString('o')
  }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutJson -Encoding UTF8
  @("OVERALL: LIVE_READBACK_REQUIRED", "REASON: $($result.reason)", "AUDIT_JSON: $AuditJson") | Set-Content -LiteralPath $OutTxt -Encoding UTF8
  exit 2
}

$audit = Get-Content -LiteralPath $AuditJson -Raw | ConvertFrom-Json

$extensions = @()
$rawExt = Get-PropValue $audit @('extensions','chrome_extensions','extension_inventory')
if ($rawExt) { $extensions = @($rawExt) }

$known = [ordered]@{
  'NotebookLM WebApp Bridge' = @('NotebookLM WebApp Bridge','notebooklm')
  'Google AI Local Bridge' = @('Google AI Local Bridge','Google AI Local Bridge v1')
  'Flow Agent Bridge' = @('Flow Agent Bridge','Flow Bridge')
  'AI Studio Bridge' = @('AI Studio Bridge')
  'Front App Test Bridge' = @('Front App Test Bridge')
  'SketchUp Plan Template Bridge' = @('SketchUp Plan Template Bridge')
  'ChatGPT Image Auto' = @('ChatGPT Image Auto')
  'UniConverter' = @('UniConverter')
  'Save to Google Drive' = @('Save to Google Drive')
}

$items = @()
foreach ($kv in $known.GetEnumerator()) {
  $match = $null
  foreach ($e in $extensions) {
    $name = [string](Get-PropValue $e @('name','extension_name','title'))
    if (-not $name) { continue }
    foreach ($needle in $kv.Value) {
      if ($name -like "*$needle*") { $match = $e; break }
    }
    if ($match) { break }
  }

  if (-not $match) {
    $status = if ($kv.Key -in @('UniConverter','Save to Google Drive')) { 'OPTIONAL_OR_REMOVE' } else { 'LIVE_READBACK_REQUIRED' }
    $items += [ordered]@{ name=$kv.Key; status=$status; evidence='not detected in audit inventory' }
    continue
  }

  $enabled = Get-PropValue $match @('enabled','is_enabled','state')
  $version = [string](Get-PropValue $match @('version','manifest_version_string'))
  $status = 'PASS'
  if ($enabled -eq $false -or "$enabled" -match 'disabled|error') { $status = 'FAIL' }
  if ($kv.Key -eq 'Save to Google Drive') { $status = 'REMOVE_REQUIRED' }
  if ($kv.Key -eq 'UniConverter') { $status = 'OPTIONAL_OR_REMOVE' }

  $items += [ordered]@{ name=$kv.Key; status=$status; version=$version; enabled=$enabled }
}

$agent = Get-PropValue $audit @('local_agent','agent','agent_health')
$host  = Get-PropValue $audit @('command_host','host','host_health')
$chrome = Get-PropValue $audit @('dedicated_chrome','chrome_for_testing','chrome_health')
$tasks = Get-PropValue $audit @('scheduled_tasks','resume_tasks','automation_tasks')

$runtime = @(
  [ordered]@{name='Local Agent'; value=$agent},
  [ordered]@{name='Command Host'; value=$host},
  [ordered]@{name='Dedicated Chrome'; value=$chrome},
  [ordered]@{name='Logon/Sleep Resume Tasks'; value=$tasks}
) | ForEach-Object {
  $v = $_.value
  $s = 'LIVE_READBACK_REQUIRED'
  if ($null -ne $v) {
    $txt = ($v | ConvertTo-Json -Depth 8 -Compress)
    if ($txt -match 'false|stopped|missing|error|fail') { $s = 'FAIL' }
    elseif ($txt -match 'true|running|active|ready|pass|healthy') { $s = 'PASS' }
  }
  [ordered]@{name=$_.name; status=$s; evidence=$v}
}

$blocking = @($items + $runtime | Where-Object { $_.status -in @('FAIL','REMOVE_REQUIRED') })
$live = @($items + $runtime | Where-Object { $_.status -eq 'LIVE_READBACK_REQUIRED' })
$overall = if ($blocking.Count -gt 0) { 'FAIL' } elseif ($live.Count -gt 0) { 'LIVE_READBACK_REQUIRED' } else { 'PASS' }

$result = [ordered]@{
  overall = $overall
  generated_at = (Get-Date).ToString('o')
  source_audit = $AuditJson
  extensions = $items
  runtime = $runtime
  blockers = $blocking
  live_readback_required = $live
  completion_rule = 'Queue->extension action->real result->Drive save->ACK->central readback->sleep/logon auto-reconnect'
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutJson -Encoding UTF8

$lines = @()
$lines += "OVERALL: $overall"
$lines += "GENERATED_AT: $($result.generated_at)"
$lines += ''
$lines += '[EXTENSIONS]'
foreach ($x in $items) { $lines += ("{0,-34} {1,-24} v={2}" -f $x.name,$x.status,$x.version) }
$lines += ''
$lines += '[RUNTIME]'
foreach ($x in $runtime) { $lines += ("{0,-34} {1}" -f $x.name,$x.status) }
$lines += ''
$lines += 'COMPLETE only when the full E2E rule passes.'
$lines | Set-Content -LiteralPath $OutTxt -Encoding UTF8

if ($overall -eq 'PASS') { exit 0 }
if ($overall -eq 'LIVE_READBACK_REQUIRED') { exit 2 }
exit 1
