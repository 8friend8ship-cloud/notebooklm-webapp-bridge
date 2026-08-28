param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$BaseAgent=Join-Path $Root 'HomeDesignLocalAgent-1.1.35-base.ps1'
$Recovery=Join-Path $Root 'Recover-StaleFlowProbe-1.1.36.ps1'
$StatePath=Join-Path $Root 'state.json'
$BaseUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.35/HomeDesignLocalAgent.ps1'
$BaseExpected='e27b760b67933be05a5d6f1ac0af1afd6158b32b'
$RecoveryUrl='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/Recover-StaleFlowProbe.ps1'
$RecoveryExpected='9737147483386f4e6c78766d18acd9492ccd4b4f'
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FetchVerified([string]$Url,[string]$Dest,[string]$Expected){$tmp=$Dest+'.download';Invoke-WebRequest -UseBasicParsing -Uri ($Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $tmp -TimeoutSec 30;$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('SHA_MISMATCH actual='+$actual+' expected='+$Expected)};Move-Item $tmp $Dest -Force;return $actual}
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not $r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c){return $c}}};return ''}
function WriteCentral([string]$Name,$Object){$central=FindCentral;if(-not $central){return $false};$dest=Join-Path $central 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $dest $Name) -Encoding UTF8;return $true}
$started=(Get-Date).ToString('o');$baseExit=$null;$recoveryExit=$null;$recoveryOutput='';$errorText=''
try{
  [void](FetchVerified $BaseUrl $BaseAgent $BaseExpected)
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BaseAgent
  $baseExit=$LASTEXITCODE
}catch{$baseExit=-1;$errorText='BASE:'+($_.Exception.Message)}
try{
  [void](FetchVerified $RecoveryUrl $Recovery $RecoveryExpected)
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Recovery 2>&1
  $recoveryExit=$LASTEXITCODE;$recoveryOutput=($out|Out-String).Trim()
}catch{$recoveryExit=-1;$errorText+=(';RECOVERY:'+($_.Exception.Message))}
$recoveryOk=($recoveryExit -eq 0 -and $recoveryOutput -match '"normalChromeUntouched"\s*:\s*true' -and $recoveryOutput -match '"notebookDedicatedRestored"\s*:\s*true')
$receipt=[ordered]@{ok=[bool]$recoveryOk;action='AGENT_1.1.36_FLOW_STALE_PROBE_SELF_HEAL';agentVersion='1.1.36';startedAt=$started;baseAgent='1.1.35';baseExit=$baseExit;recoveryExit=$recoveryExit;recoveryOutput=$recoveryOutput;normalChromeRequiredUntouched=$true;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;chromeSettingsChanged=$false;publicAction=$false;destructiveAction=$false;error=$errorText;completedAt=(Get-Date).ToString('o')}
[void](WriteCentral 'AGENT_1.1.36_FLOW_STALE_PROBE_SELF_HEAL.json' $receipt)
try{$state=$null;if(Test-Path -LiteralPath $StatePath){$state=Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8|ConvertFrom-Json};if(-not $state){$state=[pscustomobject]@{}};$state|Add-Member -NotePropertyName agentVersion -NotePropertyValue '1.1.36' -Force;$state|Add-Member -NotePropertyName agentMode -NotePropertyValue 'FLOW_STALE_PROBE_SELF_HEAL_1.1.36' -Force;$state|Add-Member -NotePropertyName ok -NotePropertyValue ([bool]$recoveryOk) -Force;$state|Add-Member -NotePropertyName status -NotePropertyValue $(if($recoveryOk){'SELF_HEAL_PASS'}else{'FLOW_RECOVERY_FAILED'}) -Force;$state|Add-Member -NotePropertyName updatedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force;if($errorText){$state|Add-Member -NotePropertyName errors -NotePropertyValue @($errorText) -Force};$state|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $StatePath -Encoding UTF8}catch{}
if($recoveryOk){exit 0}else{exit 2}
