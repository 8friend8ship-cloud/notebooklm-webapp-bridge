param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Marker = Join-Path $Root 'NLM_FRESH_RESUME_20260829_2035.attempted'
$ResultPath = Join-Path $Root 'NLM_FRESH_RESUME_20260829_2035.json'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function FindCentralRoot {
    $centralName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $rootPath = [string]$drive.Root
        if (-not $rootPath) { continue }
        foreach ($candidate in @(
            (Join-Path $rootPath $centralName),
            (Join-Path $rootPath ($myDriveKo + '\' + $centralName)),
            (Join-Path $rootPath ('My Drive\' + $centralName)),
            (Join-Path $rootPath ('Google Drive\' + $centralName))
        )) {
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        }
    }
    return ''
}

function SaveReceipt($Object) {
    $json = $Object | ConvertTo-Json -Depth 50
    $json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    $central = FindCentralRoot
    if ($central) {
        $dest = Join-Path $central 'Runtime_Readback\NotebookLM'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $json | Set-Content -LiteralPath (Join-Path $dest 'NLM_FRESH_RESUME_20260829_2035.json') -Encoding UTF8
    }
}

if (Test-Path -LiteralPath $Marker) {
    if (Test-Path -LiteralPath $ResultPath) {
        $prior = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([bool]$prior.ok) { exit 0 }
        exit 2
    }
    exit 2
}
Set-Content -LiteralPath $Marker -Value ((Get-Date).ToString('o')) -Encoding ASCII

$result = [ordered]@{
    ok = $false
    action = 'NLM_FRESH_RESUME_DIRECT'
    startedAt = (Get-Date).ToString('o')
    helperSha = ''
    helperExitCode = $null
    stdout = ''
    freshNotebook = $null
    normalChromeTouched = $false
    flowPrerequisite = $false
    error = ''
}

try {
    $headers = @{
        'User-Agent' = 'HomeDesign-NLM-Fresh-Resume'
        'Accept' = 'application/vnd.github+json'
    }
    $url = 'https://api.github.com/repos/' + $Repo + '/contents/local-agent/governor/CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1?ref=main&cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 30
    $raw = [Convert]::FromBase64String(([string]$response.content -replace '\s', ''))
    $helperText = [Text.Encoding]::UTF8.GetString($raw)
    $helperPath = Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1'
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($helperPath, $helperText, $utf8Bom)
    $result.helperSha = [string]$response.sha

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $helperPath + '" -Title "NLM Fresh E2E 2026-08-29 2035" -SourceText "NLM_FRESH_ALL_20260829_2035 fresh notebook container" -RemoteDebuggingPort 9223 -TimeoutSeconds 90'

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $result.helperExitCode = [int]$process.ExitCode
    $result.stdout = ($stdout + $(if ($stderr) { "`nSTDERR:`n" + $stderr } else { '' })).Trim()

    $jsonLine = @(($stdout -split "`r?`n") | Where-Object {
        $_.Trim().StartsWith('{') -and $_.Trim().EndsWith('}')
    }) | Select-Object -Last 1
    if (-not $jsonLine) {
        throw ('FRESH_HELPER_NO_JSON exit=' + $process.ExitCode + ' stderr=' + $stderr.Trim())
    }
    $fresh = $jsonLine | ConvertFrom-Json
    $result.freshNotebook = $fresh

    if ($process.ExitCode -ne 0) { throw ('HELPER_EXIT_' + $process.ExitCode + ':' + [string]$fresh.error) }
    if (-not [bool]$fresh.ok) { throw ('FRESH_CREATE_FAILED:' + [string]$fresh.error) }
    if ([string]::IsNullOrWhiteSpace([string]$fresh.notebookUrl)) { throw 'FRESH_NOTEBOOK_URL_EMPTY' }
    if ([string]$fresh.notebookId -eq '69e055e5-c8d0-4e9c-8686-58cc6da35a51') { throw 'HISTORICAL_NOTEBOOK_REUSED' }

    $result.ok = $true
    $result.status = 'FRESH_NOTEBOOK_CREATED'
    $result.completedAt = (Get-Date).ToString('o')
    SaveReceipt $result
    exit 0
}
catch {
    $result.error = $_.Exception.Message
    $result.status = 'FAILED_FAIL_CLOSED'
    $result.completedAt = (Get-Date).ToString('o')
    SaveReceipt $result
    exit 2
}
