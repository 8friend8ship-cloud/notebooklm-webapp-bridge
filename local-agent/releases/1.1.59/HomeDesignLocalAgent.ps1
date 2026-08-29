param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.59'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$State=Join-Path $Root 'state.json'
$Prev=Join-Path $Root 'HomeDesignLocalAgent-1.1.58.ps1'
$PrevBlob='ec1d1f28d7a83c5563028c253db9acc6d8a886b4'
$LocalReadback=Join-Path $Root 'CHATGPT_IMAGE_AUTO_LIVE_READBACK.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function FetchBlob([string]$Sha,[string]$Destination){$headers=@{'User-Agent'='HomeDesign-Local-Agent';'Accept'='application/vnd.github+json'};$r=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repo+'/git/blobs/'+$Sha+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -Method Get -TimeoutSec 20;$tmp=$Destination+'.download';[IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String(([string]$r.content -replace '\s','')));$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Sha.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('PINNED_BLOB_MISMATCH:'+ $actual+':'+$Sha)};Move-Item -LiteralPath $tmp -Destination $Destination -Force;return $actual}
function ReadJson([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function SaveJson([string]$Path,$Object){$par=Split-Path -Parent $Path;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};$Object|ConvertTo-Json -Depth 60|Set-Content -LiteralPath $Path -Encoding UTF8}
function FindCentralRoot{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){if(-not $d.Root){continue};foreach($c in @((Join-Path $d.Root $target),(Join-Path $d.Root ('My Drive\'+$target)),(Join-Path $d.Root ('내 드라이브\'+$target)),(Join-Path $d.Root ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function ResolveManifestName($m,[string]$verDir){$name=[string]$m.name;if($name -like '__MSG_*__' -and $m.default_locale){$key=$name.Trim('_');if($key.StartsWith('MSG_')){$key=$key.Substring(4)};$messages=ReadJson (Join-Path $verDir ('_locales\'+[string]$m.default_locale+'\messages.json'));if($messages -and ($messages.PSObject.Properties.Name -contains $key)){$name=[string]$messages.$key.message}};return $name}
function ScanChromeExtensions{$userData=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data';$out=@();if(-not(Test-Path -LiteralPath $userData)){return @()};foreach($profile in @(Get-ChildItem -LiteralPath $userData -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -eq 'Default' -or $_.Name -like 'Profile *'})){$pref=ReadJson (Join-Path $profile.FullName 'Preferences');$settings=$null;if($pref -and $pref.extensions -and $pref.extensions.settings){$settings=$pref.extensions.settings};$extRoot=Join-Path $profile.FullName 'Extensions';if(-not(Test-Path -LiteralPath $extRoot)){continue};foreach($idDir in @(Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue)){$verDir=Get-ChildItem -LiteralPath $idDir.FullName -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1;if(-not $verDir){continue};$m=ReadJson (Join-Path $verDir.FullName 'manifest.json');if(-not $m){continue};$name=ResolveManifestName $m $verDir.FullName;$enabled=$null;$stateValue=$null;if($settings -and ($settings.PSObject.Properties.Name -contains $idDir.Name)){$entry=$settings.($idDir.Name);if($entry.PSObject.Properties.Name -contains 'state'){$stateValue=$entry.state;try{$enabled=([int]$stateValue -eq 1)}catch{}}};$out += [pscustomobject]@{profile=$profile.Name;id=$idDir.Name;name=$name;version=[string]$m.version;enabled=$enabled;state=$stateValue;path=$verDir.FullName}}};return @($out|Sort-Object name,version,profile)}
$errors=@();$prevSha='';$prevExit=$null
try{$prevSha=FetchBlob $PrevBlob $Prev;$p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"`"$Prev`"") -WindowStyle Hidden -PassThru;$p.WaitForExit(150000)|Out-Null;if($p.HasExited){$prevExit=$p.ExitCode}else{$errors+='AGENT_1.1.58_TIMEOUT'}}catch{$errors+=('AGENT_1.1.58_RECOVERY:'+$_.Exception.Message)}
Start-Sleep -Seconds 3
$inventory=@(ScanChromeExtensions)
$matches=@($inventory|Where-Object{([string]$_.name) -like '*ChatGPT Image Auto*'})
$best=$matches|Sort-Object version -Descending|Select-Object -First 1
$status=if(-not $best){'CHATGPT_IMAGE_AUTO_ABSENT_CURRENT'}elseif($best.enabled -eq $false){'CHATGPT_IMAGE_AUTO_DISABLED'}elseif($null -eq $best.enabled){'CHATGPT_IMAGE_AUTO_ENABLE_STATE_UNKNOWN'}else{'CHATGPT_IMAGE_AUTO_INSTALLED_ENABLED'}
$ok=[bool]($prevExit -eq 0 -and $best -and $best.enabled -eq $true)
$central=FindCentralRoot
$receipt=[ordered]@{ok=$ok;action='HOST_1.3.0_THEN_CHATGPT_IMAGE_INVENTORY';agentVersion=$AgentVersion;previousAgent='1.1.58';previousAgentBlob=$prevSha;previousAgentExit=$prevExit;status=$status;extension=$(if($best){$best}else{$null});matchCount=@($matches).Count;allExtensionCount=@($inventory).Count;normalChromeTouched=$false;dedicatedChromeTouched=$false;flowGenerationTouched=$false;newOAuth=$false;newScope=$false;newProject=$false;newDeployment=$false;newTrigger=$false;generateClicked=$false;creditSpend=$false;errors=$errors;at=(Get-Date).ToString('o')}
SaveJson $LocalReadback $receipt
if($central){try{SaveJson (Join-Path $central 'Runtime_Readback\CHROME\CHATGPT_IMAGE_AUTO_LIVE_READBACK.json') $receipt}catch{$errors+=('CENTRAL_READBACK_WRITE:'+$_.Exception.Message)}}
try{$s=ReadJson $State;if(-not $s){$s=[pscustomobject]@{}};$s|Add-Member agentVersion $AgentVersion -Force;$s|Add-Member agentMode 'HOST_RECOVERY_THEN_CHATGPT_IMAGE_INVENTORY' -Force;$s|Add-Member status $status -Force;$s|Add-Member updatedAt ((Get-Date).ToString('o')) -Force;SaveJson $State $s}catch{}
$receipt|ConvertTo-Json -Depth 60 -Compress
if($ok){exit 0}else{exit 2}
