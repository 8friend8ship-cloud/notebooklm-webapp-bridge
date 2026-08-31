param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$raw='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.124/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$tmp=Join-Path $env:TEMP 'HomeDesignLocalAgent_1.1.126_child.ps1'
$src=(Invoke-WebRequest -UseBasicParsing -Uri $raw -TimeoutSec 20).Content
$src=$src.Replace("$Version='1.1.124'","$Version='1.1.126'")
$src=$src.Replace("AGENT_1.1.124_GENERATION_ONLY_AUDIO_START_RESULT.json","AGENT_1.1.126_AUDIO_READINESS_READONLY_RESULT.json")
$src=$src.Replace("49828,53804,46356,50724","49828,53916,46356,50724")
$replacement=@'
$result.stage='READONLY_STATE'
$s=Eval $w ([ref]$q) "(() => {const A=String.fromCharCode(50724,46356,50724,32,50724,48260,48624), G=String.fromCharCode(49373,49457,32,51473), M=String.fromCharCode(47564,46300,45716,32,51473), P=String.fromCharCode(51116,49373);const body=String(document.body?.innerText||'');const low=body.toLowerCase();const els=[...document.querySelectorAll('button,[role=button],a,[role=option],[role=menuitem],div[tabindex],audio')].map(e=>String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).trim()).filter(Boolean);const generating=low.includes('generating')||low.includes('creating')||body.includes(G)||body.includes(M);const audioCount=document.querySelectorAll('audio').length;const hasAudio=body.includes(A)||low.includes('audio overview');const hasPlay=els.some(x=>x.includes(P)||/\bplay\b/i.test(x));const ready=!generating&&hasAudio&&(audioCount>0||hasPlay||els.some(x=>/more_vert|download|share/i.test(x)));return{generating,audioCount,hasAudio,hasPlay,ready,body:body.slice(0,12000),controls:els.slice(0,180)}})()"
$result.generationStarted=[bool]$s.generating
$result['ready']=[bool]$s.ready
$result['audioCount']=[int]$s.audioCount
$result['hasAudio']=[bool]$s.hasAudio
$result['hasPlay']=[bool]$s.hasPlay
$result['bodyText']=[string]$s.body
$result.controlDump=@($s.controls)
$result.ok=$true
$result.stage='DONE'
'@
$pat="(?s)\$result\.stage='AUDIO';.*?\$result\.stage='DONE'"
$patched=[regex]::Replace($src,$pat,$replacement,1)
if($patched-eq$src){throw 'READONLY_PATCH_ANCHOR_NOT_FOUND'}
Set-Content -LiteralPath $tmp -Value $patched -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
exit $LASTEXITCODE
