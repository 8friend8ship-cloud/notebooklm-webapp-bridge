param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$AgentVersion = '1.1.76'
$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge'
$ExpectedBridge = '0.2.75'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root = Join-Path $Base 'LocalAgent'
$ExtensionRoot = Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$StatePath = Join-Path $Root 'state.json'
$AttemptMarker = Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_1.1.76.attempted'
$ResultPath = Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_1.1.76.json'
$EntryPath = Join-Path $Root 'NOTEBOOKLM_FRESH_CREATE_ENTRY_1.1.76.json'

New-Item -ItemType Directory -Force -Path $Root | Out-Null

function GitBlobSha1([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $header = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
    $all = New-Object byte[] ($header.Length + $bytes.Length)
    [Buffer]::BlockCopy($header, 0, $all, 0, $header.Length)
    [Buffer]::BlockCopy($bytes, 0, $all, $header.Length, $bytes.Length)
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        return (($sha.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

function FindCentralRoot {
    $central = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    $myDriveKo = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='))
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $rootPath = [string]$drive.Root
        if (-not $rootPath) { continue }
        $candidates = @(
            (Join-Path $rootPath $central),
            (Join-Path $rootPath ($myDriveKo + '\' + $central)),
            (Join-Path $rootPath ('My Drive\' + $central)),
            (Join-Path $rootPath ('Google Drive\' + $central))
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        }
    }
    return ''
}

function SaveJson([string]$Path, $Object) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Object | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function PublishCentral([string]$Name, $Object) {
    $central = FindCentralRoot
    if ($central) {
        $dest = Join-Path $central 'Runtime_Readback\NotebookLM'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        SaveJson (Join-Path $dest $Name) $Object
    }
}

function SaveState([string]$Status, [string]$NotebookUrl = '') {
    $state = [ordered]@{
        agentVersion = $AgentVersion
        status = $Status
        extensionVersion = $ExpectedBridge
        notebookUrl = $NotebookUrl
        normalChromeTouched = $false
        flowPrerequisite = $false
        updatedAt = (Get-Date).ToString('o')
    }
    SaveJson $StatePath $state
}

$entry = [ordered]@{
    ok = $true
    action = 'NLM_FRESH_CREATE_ENTRY'
    agentVersion = $AgentVersion
    at = (Get-Date).ToString('o')
    normalChromeTouched = $false
    flowPrerequisite = $false
}
SaveJson $EntryPath $entry
PublishCentral 'NOTEBOOKLM_FRESH_CREATE_ENTRY_1.1.76.json' $entry

if (Test-Path -LiteralPath $AttemptMarker) {
    if (Test-Path -LiteralPath $ResultPath) {
        $prior = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $prior | ConvertTo-Json -Depth 50 -Compress
        if ([bool]$prior.ok) { exit 0 }
        exit 2
    }
    exit 2
}
Set-Content -LiteralPath $AttemptMarker -Value ((Get-Date).ToString('o')) -Encoding ASCII

$result = [ordered]@{
    ok = $false
    action = 'NLM_FRESH_CREATE'
    agentVersion = $AgentVersion
    verifiedBridge = ''
    helperGitBlob = ''
    helperExitCode = $null
    helperStdout = ''
    freshNotebook = $null
    normalChromeTouched = $false
    flowPrerequisite = $false
    startedAt = (Get-Date).ToString('o')
    error = ''
}

try {
    $manifestPath = Join-Path $ExtensionRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'MANIFEST_NOT_FOUND'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result.verifiedBridge = [string]$manifest.version
    if ($result.verifiedBridge -ne $ExpectedBridge) {
        throw ('BRIDGE_NOT_0275:' + $result.verifiedBridge)
    }

    $headers = @{
        'User-Agent' = 'HomeDesign-NLM-Fresh-1.1.76'
        'Accept' = 'application/vnd.github+json'
    }
    $helperUrl = 'https://api.github.com/repos/' + $Repo + '/contents/local-agent/governor/CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1?ref=main&cb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $helperResponse = Invoke-RestMethod -Uri $helperUrl -Headers $headers -Method Get -TimeoutSec 30
    $raw = [Convert]::FromBase64String(([string]$helperResponse.content -replace '\s', ''))
    $rawTemp = Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.raw.tmp'
    [IO.File]::WriteAllBytes($rawTemp, $raw)
    $actualSha = (GitBlobSha1 $rawTemp).ToLowerInvariant()
    $expectedSha = ([string]$helperResponse.sha).ToLowerInvariant()
    $result.helperGitBlob = $actualSha
    if ($actualSha -ne $expectedSha) {
        throw 'FRESH_HELPER_SHA_MISMATCH'
    }

    $helperText = [Text.Encoding]::UTF8.GetString($raw)
    $helperPath = Join-Path $Root 'CreateFreshNotebookLMNotebookViaExistingCDPV1.ps1'
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($helperPath, $helperText, $utf8Bom)
    Remove-Item -LiteralPath $rawTemp -Force -ErrorAction SilentlyContinue

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $helperPath + '" -Title "NLM Fresh E2E 2026-08-29 2024" -SourceText "NLM_FRESH_ALL_20260829_2024 fresh notebook container" -RemoteDebuggingPort 9223 -TimeoutSeconds 90'

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $result.helperExitCode = [int]$process.ExitCode
    $combined = $stdout
    if ($stderr) { $combined += "`nSTDERR:`n" + $stderr }
    $result.helperStdout = $combined.Trim()

    $jsonLine = @(($stdout -split "`r?`n") | Where-Object {
        $_.Trim().StartsWith('{') -and $_.Trim().EndsWith('}')
    }) | Select-Object -Last 1
    if (-not $jsonLine) {
        throw ('FRESH_HELPER_NO_JSON exit=' + $process.ExitCode + ' stderr=' + $stderr.Trim())
    }

    $fresh = $jsonLine | ConvertFrom-Json
    $result.freshNotebook = $fresh
    if ($process.ExitCode -ne 0) {
        throw ('FRESH_NOTEBOOK_HELPER_EXIT_' + $process.ExitCode + ':' + [string]$fresh.error)
    }
    if (-not [bool]$fresh.ok) {
        throw ('FRESH_NOTEBOOK_CREATE_FAILED:' + [string]$fresh.error)
    }
    if ([string]::IsNullOrWhiteSpace([string]$fresh.notebookUrl)) {
        throw 'FRESH_NOTEBOOK_URL_EMPTY'
    }
    if ([string]$fresh.notebookId -eq '69e055e5-c8d0-4e9c-8686-58cc6da35a51') {
        throw 'FRESH_NOTEBOOK_REUSED_HISTORICAL_ID'
    }

    $result.ok = $true
    $result.status = 'FRESH_NOTEBOOK_CREATED'
    $result.completedAt = (Get-Date).ToString('o')
    SaveJson $ResultPath $result
    PublishCentral 'NOTEBOOKLM_FRESH_CREATE_1.1.76.json' $result
    SaveState 'FRESH_NOTEBOOK_CREATED' ([string]$fresh.notebookUrl)
}
catch {
    $result.error = $_.Exception.Message
    $result.status = 'FAILED_FAIL_CLOSED'
    $result.completedAt = (Get-Date).ToString('o')
    SaveJson $ResultPath $result
    PublishCentral 'NOTEBOOKLM_FRESH_CREATE_1.1.76.json' $result
    SaveState 'FAILED_FAIL_CLOSED'
}

$result | ConvertTo-Json -Depth 50 -Compress
if ($result.ok) { exit 0 }
exit 2
