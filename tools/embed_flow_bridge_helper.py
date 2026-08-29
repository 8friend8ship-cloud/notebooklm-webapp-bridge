from pathlib import Path
import base64, hashlib
setup=Path('local-agent/capture/Setup-ChromeExtensionCaptureBridge.ps1')
helper=Path('local-agent/governor/RunFlowBridgeConnectSmoke.ps1')
d=setup.read_text(encoding='utf-8')
h=helper.read_text(encoding='utf-8').encode('utf-8')
sha=hashlib.sha1(b'blob '+str(len(h)).encode()+b'\0'+h).hexdigest()
payload=base64.b64encode(h).decode('ascii')
start=d.index('if ($FlowBridgeConnectSmoke) {')
end=d.index('function Find-CentralRoot {',start)
block="""if ($FlowBridgeConnectSmoke) {
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $helper = Join-Path $InstallRoot 'RunFlowBridgeConnectSmoke.ps1'
  $tmpHelper = $helper + '.embedded'
  $payload='__PAYLOAD__'
  [IO.File]::WriteAllBytes($tmpHelper,[Convert]::FromBase64String($payload))
  $helperActual = (GitBlobSha1 $tmpHelper).ToLowerInvariant()
  $helperExpected='__SHA__'
  if ($helperActual -ne $helperExpected) {
    Remove-Item -LiteralPath $tmpHelper -Force -ErrorAction SilentlyContinue
    throw ('FLOW_HELPER_EMBEDDED_SHA_MISMATCH:actual={0}:expected={1}' -f $helperActual,$helperExpected)
  }
  Move-Item -LiteralPath $tmpHelper -Destination $helper -Force
  $helperArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper,'-DebugPort',[string]$FlowDebugPort)
  if ($FlowSmokeTaskId) { $helperArgs += @('-TaskId',$FlowSmokeTaskId) }
  if ($CentralRootOverride) { $helperArgs += @('-CentralRootOverride',$CentralRootOverride) }
  $oldEap=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try { $helperOut = & powershell.exe @helperArgs 2>&1; $helperRc = $LASTEXITCODE } finally { $ErrorActionPreference=$oldEap }
  $helperText = ($helperOut | Out-String).Trim()
  [ordered]@{
    ok = ($helperRc -eq 0)
    action = 'FLOW_BRIDGE_CONNECT_PROBE_WRAPPER_EMBEDDED'
    helperExit = $helperRc
    helperSha = $helperActual
    helperOutput = $helperText
    diagnosticOnly = $true
    secondaryNetworkFetch = $false
    generateClicked = $false
    creditSpend = $false
    at = (Get-Date).ToString('o')
  } | ConvertTo-Json -Depth 50 -Compress
  exit 0
}

""".replace('__PAYLOAD__',payload).replace('__SHA__',sha)
setup.write_text(d[:start]+block+d[end:],encoding='utf-8',newline='\n')
print(sha)
