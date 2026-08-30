param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Runtime=Join-Path $Root 'HomeDesignLocalAgent.1.1.119.runtime.ps1'
$Source=Join-Path $Root 'HomeDesignLocalAgent.1.1.118.source.ps1'
$Expected='304eca09b08719cd562b8ea3211e12000ea7b22c'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
try{
  $u='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.118/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $Source -TimeoutSec 30
  $sha=(GitBlobSha1 $Source).ToLowerInvariant();if($sha-ne$Expected){throw ('SOURCE_SHA_MISMATCH actual='+$sha+' expected='+$Expected)}
  $txt=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
  $txt=$txt.Replace('1.1.118','1.1.119')
  $txt=$txt.Replace('AGENT_1.1.118_TRUSTED_CHAT_SUBMIT_RESULT.json','AGENT_1.1.119_TRUSTED_CHAT_SUBMIT_RESULT.json')
  $txt=$txt.Replace('AGENT_1.1.118_TRUSTED_CHAT_SUBMIT','AGENT_1.1.119_TRUSTED_CHAT_SUBMIT')
  $txt=$txt.Replace('\\u','\u')
  [IO.File]::WriteAllText($Runtime,$txt,(New-Object Text.UTF8Encoding($true)))
  $tok=$null;$pe=$null;[void][Management.Automation.Language.Parser]::ParseFile($Runtime,[ref]$tok,[ref]$pe);if($pe.Count){throw ('RUNTIME_PARSE_FAIL '+(($pe|ForEach-Object{$_.Message})-join' | '))}
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Runtime
  exit $LASTEXITCODE
}catch{
  $r=[ordered]@{ok=$false;action='AGENT_1.1.119_TRUSTED_CHAT_SUBMIT';version='1.1.119';stage='WRAPPER';error=$_.Exception.Message;completedAt=(Get-Date).ToString('o')}
  $r|ConvertTo-Json -Depth 20 -Compress
  exit 2
}
