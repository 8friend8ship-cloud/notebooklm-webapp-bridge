param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Base = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData = Join-Path $Base 'ChromeUserData'
$ExtensionRoot = Join-Path $Base 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot = Join-Path $Base 'ChromeForTesting'
$RemoteDebuggingPort = 9223
$NotebookHomeUrl = 'https://notebook.google.com/'
$HistoricalId = '69e055e5-c8d0-4e9c-8686-58cc6da35a51'
$Marker = Join-Path $Root 'NLM_FRESH_RESUME_CDP_20260829_2040.attempted'
$ResultPath = Join-Path $Root 'NLM_FRESH_RESUME_CDP_20260829_2040.json'
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
        $json | Set-Content -LiteralPath (Join-Path $dest 'NLM_FRESH_RESUME_CDP_20260829_2040.json') -Encoding UTF8
    }
}

function DebugReady {
    try {
        $v = Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/version") -TimeoutSec 2
        return [bool]$v.webSocketDebuggerUrl
    }
    catch { return $false }
}

function DedicatedProcesses {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and $_.CommandLine -like "*$UserData*"
        })
    }
    catch { return @() }
}

function FindChrome {
    if (Test-Path -LiteralPath $CftRoot) {
        $found = Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($found) { return [string]$found.FullName }
    }
    foreach ($candidate in @(
        (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return [string]$candidate }
    }
    throw 'CHROME_EXE_NOT_FOUND'
}

function StartDedicatedChrome {
    if (DebugReady) { return }
    foreach ($proc in @(DedicatedProcesses)) {
        try { Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 700
    $chrome = FindChrome
    $args = @(
        "--remote-debugging-port=$RemoteDebuggingPort",
        '--remote-allow-origins=*',
        "--user-data-dir=$UserData",
        '--profile-directory=Default',
        "--load-extension=$ExtensionRoot",
        '--new-window',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-session-crashed-bubble',
        $NotebookHomeUrl
    )
    Start-Process -FilePath $chrome -ArgumentList $args | Out-Null
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 400
        if (DebugReady) { return }
    } while ((Get-Date) -lt $deadline)
    throw 'CDP_PORT_NOT_READY'
}

function GetTabs {
    return @(Invoke-RestMethod -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3)
}

function GetNotebookTab {
    return @(GetTabs | Where-Object {
        [string]$_.type -eq 'page' -and [string]$_.url -like 'https://notebook.google.com/*'
    } | Select-Object -First 1)[0]
}

function ReceiveCdp([System.Net.WebSockets.ClientWebSocket]$Ws) {
    $buffer = New-Object byte[] 65536
    $stream = New-Object IO.MemoryStream
    try {
        do {
            $segment = New-Object ArraySegment[byte] -ArgumentList @(,$buffer)
            $received = $Ws.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            if ($received.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw 'CDP_WEBSOCKET_CLOSED' }
            $stream.Write($buffer, 0, $received.Count)
        } while (-not $received.EndOfMessage)
        return [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
    }
    finally { $stream.Dispose() }
}

function SendCdp([System.Net.WebSockets.ClientWebSocket]$Ws, [ref]$Sequence, [string]$Method, [hashtable]$Params = @{}) {
    $Sequence.Value++
    $id = $Sequence.Value
    $json = @{ id=$id; method=$Method; params=$Params } | ConvertTo-Json -Depth 30 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
    $Ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    while ($true) {
        $message = ReceiveCdp $Ws
        if ($message.id -eq $id) {
            if ($message.error) { throw ('CDP_' + $Method + ':' + ($message.error | ConvertTo-Json -Compress)) }
            return $message.result
        }
    }
}

function EvalCdp($Ws, [ref]$Sequence, [string]$Expression) {
    $response = SendCdp $Ws $Sequence 'Runtime.evaluate' @{
        expression = $Expression
        returnByValue = $true
        awaitPromise = $true
        userGesture = $true
    }
    return $response.result.value
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
    action = 'NLM_FRESH_RESUME_CDP_DIRECT'
    startedAt = (Get-Date).ToString('o')
    previousUrl = ''
    previousNotebookId = ''
    clickedLabel = ''
    notebookUrl = ''
    notebookId = ''
    normalChromeTouched = $false
    flowPrerequisite = $false
    error = ''
}
$ws = $null

try {
    StartDedicatedChrome
    $deadline = (Get-Date).AddSeconds(20)
    $tab = $null
    do {
        $tab = GetNotebookTab
        if ($tab) { break }
        Start-Sleep -Milliseconds 400
    } while ((Get-Date) -lt $deadline)
    if (-not $tab) { throw 'NOTEBOOKLM_TAB_NOT_FOUND' }

    $result.previousUrl = [string]$tab.url
    if ($result.previousUrl -match '/notebook/([0-9a-fA-F-]+)') { $result.previousNotebookId = $Matches[1] }

    $uri = [Uri]([string]$tab.webSocketDebuggerUrl)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync($uri, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $sequence = 0
    [void](SendCdp $ws ([ref]$sequence) 'Runtime.enable' @{})
    [void](SendCdp $ws ([ref]$sequence) 'Page.bringToFront' @{})
    Start-Sleep -Milliseconds 700

    $clickExpression = @"
(() => {
  const visible = e => {
    if (!(e instanceof HTMLElement)) return false;
    const r = e.getBoundingClientRect();
    const s = getComputedStyle(e);
    return r.width > 2 && r.height > 2 && s.display !== 'none' && s.visibility !== 'hidden';
  };
  const preferred = [
    '\uC0C8 \uB178\uD2B8 \uB9CC\uB4E4\uAE30',
    '\uC0C8 \uB178\uD2B8\uBD81 \uB9CC\uB4E4\uAE30',
    'create new notebook',
    'new notebook',
    '\uC0C8\uB85C \uB9CC\uB4E4\uAE30'
  ];
  const items = [...document.querySelectorAll('button,[role=button],a')].filter(visible);
  for (const wanted of preferred) {
    const hit = items.find(e => {
      const raw = String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).trim();
      const lower = raw.toLowerCase();
      return lower.includes(wanted.toLowerCase());
    });
    if (hit) {
      const label = String([hit.innerText,hit.textContent,hit.getAttribute('aria-label'),hit.getAttribute('title')].join(' ')).trim().slice(0,200);
      hit.click();
      return {ok:true,label};
    }
  }
  return {ok:false,error:'CREATE_CONTROL_NOT_FOUND'};
})()
"@
    $clicked = EvalCdp $ws ([ref]$sequence) $clickExpression
    if (-not $clicked.ok) { throw [string]$clicked.error }
    $result.clickedLabel = [string]$clicked.label

    $newUrl = ''
    $newId = ''
    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Milliseconds 500
        $newUrl = [string](EvalCdp $ws ([ref]$sequence) 'location.href')
        if ($newUrl -match '^https://notebook\.google\.com/notebook/([0-9a-fA-F-]+)') {
            $newId = $Matches[1]
            if ($newId -and $newId -ne $result.previousNotebookId -and $newId -ne $HistoricalId) { break }
        }
    } while ((Get-Date) -lt $deadline)

    if (-not $newId) { throw 'NEW_NOTEBOOK_ID_NOT_OBSERVED' }
    if ($newId -eq $result.previousNotebookId) { throw 'NOTEBOOK_ID_DID_NOT_CHANGE' }
    if ($newId -eq $HistoricalId) { throw 'HISTORICAL_NOTEBOOK_REUSED' }

    $result.notebookUrl = $newUrl
    $result.notebookId = $newId
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
finally {
    if ($ws) { try { $ws.Dispose() } catch {} }
}
