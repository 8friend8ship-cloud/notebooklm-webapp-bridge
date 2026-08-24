param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$AgentVersion='1.1.16'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$StateFile=Join-Path $Root 'state.json'
$ReadbackFile=Join-Path $Root 'VIDEO_LOCAL_RUNTIME_READBACK.json'
$Source=Join-Path $Root 'HomeDesignLocalAgent-1.1.15-source.ps1'
$Patched=Join-Path $Root 'HomeDesignLocalAgent-1.1.16-patched.ps1'
$HostFile=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
$SourceUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.15/HomeDesignLocalAgent.ps1'
$SourceSha='8045fd786fc7c0b06ef97603de057af7a517bdd2'
$HostUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.2.1/HomeDesignLocalCommandHost.ps1'
$HostSha='019e22095799ae8eeef2bff7b5b1d6c1fc080bf4'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[] ($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function RefreshVerified([string]$Url,[string]$Path,[string]$Expected){$tmp=$Path+'.download';$u=$Url+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $tmp -TimeoutSec 60;$actual=(GitBlobSha1 $tmp).ToLowerInvariant();if($actual -ne $Expected.ToLowerInvariant()){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw "HASH_MISMATCH actual=$actual expected=$Expected"};Move-Item $tmp $Path -Force}
function Proc([string]$Needle){try{return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and $_.CommandLine -like "*$Needle*"})}catch{return @()}}
function KillTree([int]$ProcessId){try{& taskkill.exe /PID $ProcessId /T /F 2>$null|Out-Null}catch{try{Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue}catch{}}}
function TestHost121{try{$h=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3;return ([bool]$h.ok -and [string]$h.version -eq '1.2.1' -and [bool]$h.asyncJobs)}catch{return $false}}
function StartHost{Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$HostFile`"") -WindowStyle Hidden|Out-Null}
$mutex=New-Object System.Threading.Mutex($false,'HomeDesignLocalAgent116')
if(-not $mutex.WaitOne(0,$false)){exit 0}
try{
  RefreshVerified $HostUrl $HostFile $HostSha
  if(-not(TestHost121)){foreach($p in @(Proc 'HomeDesignLocalCommandHost.ps1')){KillTree ([int]$p.ProcessId)};Start-Sleep -Milliseconds 800;StartHost;$deadline=(Get-Date).AddSeconds(20);do{Start-Sleep -Milliseconds 500}while(-not(TestHost121)-and (Get-Date)-lt $deadline)}
  if(-not(TestHost121)){throw 'HOST_1.2.1_HEALTH_FAILED'}
  RefreshVerified $SourceUrl $Source $SourceSha
  $code=Get-Content -LiteralPath $Source -Raw -Encoding UTF8
  if(-not $code.Contains("`$AgentVersion='1.1.15'")){throw 'AGENT_115_VERSION_MARKER_MISSING'}
  if(-not $code.Contains('$Host=$null;try{$Host=Invoke-RestMethod')){throw 'AGENT_115_HOST_PATCH_TARGET_MISSING'}
  $code=$code.Replace("`$AgentVersion='1.1.15'","`$AgentVersion='1.1.16'")
  $code=$code.Replace('$Host=$null;try{$Host=Invoke-RestMethod','$HostInfo=$null;try{$HostInfo=Invoke-RestMethod')
  $code=$code.Replace('$(if($Host){[bool]$Host.ok}else{$false})','$(if($HostInfo){[bool]$HostInfo.ok}else{$false})')
  $code=$code.Replace('$(if($Host){[string]$Host.version}else{''''})','$(if($HostInfo){[string]$HostInfo.version}else{''''})')
  $code=$code.Replace('$(if($Host){[bool]$Host.asyncJobs}else{$false})','$(if($HostInfo){[bool]$HostInfo.asyncJobs}else{$false})')
  Set-Content -LiteralPath $Patched -Value $code -Encoding UTF8
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
  $rc=$LASTEXITCODE
  if($rc -ne 0){throw "PATCHED_AGENT_116_EXIT_$rc"}
  exit 0
}catch{
  try{$s=@{};if(Test-Path $StateFile){$o=Get-Content $StateFile -Raw -Encoding UTF8|ConvertFrom-Json;foreach($p in $o.PSObject.Properties){$s[$p.Name]=$p.Value}};$s.agentVersion=$AgentVersion;$s.status='COORDINATOR_FAILED';$s.lastError=$_.Exception.Message;$s.commandHostVersion=$(if(TestHost121){'1.2.1'}else{''});$s.updatedAt=(Get-Date).ToString('o');$s|ConvertTo-Json -Depth 30|Set-Content $StateFile -Encoding UTF8;$s|ConvertTo-Json -Depth 30|Set-Content $ReadbackFile -Encoding UTF8}catch{}
  exit 16
}finally{try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()}
