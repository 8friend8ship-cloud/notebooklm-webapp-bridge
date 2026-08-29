param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.81'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$BaseRoot=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$UserData=Join-Path $BaseRoot 'ChromeUserData'
$ExtensionRoot=Join-Path $BaseRoot 'Extension\NotebookLM-WebApp-Bridge'
$CftRoot=Join-Path $BaseRoot 'ChromeForTesting'
$Delegate=Join-Path $Root 'HomeDesignLocalAgent-1.1.32-delegate.ps1'
$DelegateUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.32/HomeDesignLocalAgent.ps1'
$DelegateExpected='a38da31ff6aad74c43839a7b010909fec041342d'
$WakeMarker=Join-Path $Root 'AGENT_1.1.81_ROW450_WAKE.attempted'
$WakeReceipt=Join-Path $Root 'AGENT_1.1.81_ROW450_WAKE.json'
$Front='https://notebooklm-webapp-bridge.vercel.app/'
New-Item -ItemType Directory -Force -Path $Root|Out-Null

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}};return ''}
function WriteCentral([string]$Name,$Object){$central=FindCentral;if(-not $central){return ''};try{$dir=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dir|Out-Null;$p=Join-Path $dir $Name;$Object|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $p -Encoding UTF8;return $p}catch{return ''}}
function FindChrome{if(Test-Path -LiteralPath $CftRoot){$x=Get-ChildItem -LiteralPath $CftRoot -Recurse -Filter chrome.exe -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1;if($x){return [string]$x.FullName}};throw 'DEDICATED_CHROME_EXE_NOT_FOUND'}
function DedicatedCount{try{return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$UserData*"}).Count}catch{return 0}}

$result=[ordered]@{ok=$false;action='AGENT_1.1.81_ROW450_WAKE';version=$Version;delegateVersion='1.1.32';taskId='LOCAL_NLM_FRESH_NOTEBOOK_SOURCE_CDP_V2_20260829_2132_01';startedAt=(Get-Date).ToString('o');delegateExit=$null;dedicatedBefore=0;dedicatedAfter=0;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;error='';centralPath=''}
try{
  Invoke-WebRequest -UseBasicParsing -Uri ($DelegateUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $Delegate -TimeoutSec 30
  $actual=(GitBlobSha1 $Delegate).ToLowerInvariant();if($actual -ne $DelegateExpected){throw "DELEGATE_1.1.32_SHA_MISMATCH actual=$actual expected=$DelegateExpected"}
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Delegate
  $result.delegateExit=$LASTEXITCODE
  if($LASTEXITCODE -ne 0){throw ('DELEGATE_1.1.32_FAILED exit='+$LASTEXITCODE)}
  $result.dedicatedBefore=DedicatedCount
  if(-not(Test-Path -LiteralPath $WakeMarker)){
    $chrome=FindChrome
    $args=@("--user-data-dir=$UserData",'--profile-directory=Default',"--load-extension=$ExtensionRoot",'--new-tab','--no-first-run','--no-default-browser-check','--disable-session-crashed-bubble',$Front)
    Start-Process -FilePath $chrome -ArgumentList $args|Out-Null
    Start-Sleep -Seconds 8
    Set-Content -LiteralPath $WakeMarker -Value ((Get-Date).ToString('o')) -Encoding ASCII
  }
  $result.dedicatedAfter=DedicatedCount
  $result.ok=($result.delegateExit -eq 0 -and $result.dedicatedAfter -gt 0)
  if(-not $result.ok){throw 'DEDICATED_CONTROL_CENTER_WAKE_NOT_VERIFIED'}
}catch{$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');$result.centralPath=WriteCentral 'AGENT_1.1.81_ROW450_WAKE.json' $result;$result|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $WakeReceipt -Encoding UTF8}
$result|ConvertTo-Json -Depth 20 -Compress
if($result.ok){exit 0}else{exit 2}
