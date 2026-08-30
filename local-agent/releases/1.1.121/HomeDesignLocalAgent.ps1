param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Source=Join-Path $Root 'HomeDesignLocalAgent.1.1.117.source.ps1'
$Runtime=Join-Path $Root 'HomeDesignLocalAgent.1.1.121.runtime.ps1'
$Expected='1d9ff2e49edc6a55d667bea73491419ac977e363'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
try{
  $u='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.117/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $Source -TimeoutSec 30
  $sha=(GitBlobSha1 $Source).ToLowerInvariant();if($sha-ne$Expected){throw ('SOURCE_SHA_MISMATCH actual='+$sha+' expected='+$Expected)}
  $txt=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
  $txt=$txt.Replace('1.1.117','1.1.121')
  $txt=$txt.Replace('AGENT_1.1.117_AUDIO_READY_DOWNLOAD_DRIVE_VERIFY_RESULT.json','AGENT_1.1.121_AUDIO_READY_DOWNLOAD_DRIVE_VERIFY_RESULT.json')
  $txt=$txt.Replace('AGENT_1.1.117_AUDIO_READY_DOWNLOAD_DRIVE_VERIFY','AGENT_1.1.121_AUDIO_READY_DOWNLOAD_DRIVE_VERIFY')
  $anchor="[void](Send `$w ([ref]`$q) 'Runtime.enable' @{});[void](Send `$w ([ref]`$q) 'Page.bringToFront' @{})"
  $insert=@'
;[void](Eval $w ([ref]$q) "(() => {for(const e of [...document.querySelectorAll('[role=tab]')]){const s=String(e.innerText||e.textContent||'').trim().toLowerCase();if(s==='studio'||s.includes('\uC2A4\uD29C\uB514\uC624')){e.click();return true}}return false})()")
  Start-Sleep -Milliseconds 1000
'@
  if(-not$txt.Contains($anchor)){throw 'STUDIO_PRECHECK_PATCH_ANCHOR_NOT_FOUND'}
  $txt=$txt.Replace($anchor,$anchor+$insert)
  [IO.File]::WriteAllText($Runtime,$txt,(New-Object Text.UTF8Encoding($true)))
  $tok=$null;$pe=$null;[void][Management.Automation.Language.Parser]::ParseFile($Runtime,[ref]$tok,[ref]$pe);if($pe.Count){throw ('RUNTIME_PARSE_FAIL '+(($pe|ForEach-Object{$_.Message})-join' | '))}
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Runtime
  exit $LASTEXITCODE
}catch{
  $r=[ordered]@{ok=$false;action='AGENT_1.1.121_AUDIO_READY_DOWNLOAD_DRIVE_VERIFY';version='1.1.121';stage='WRAPPER';error=$_.Exception.Message;completedAt=(Get-Date).ToString('o')}
  $r|ConvertTo-Json -Depth 20 -Compress
  exit 2
}
