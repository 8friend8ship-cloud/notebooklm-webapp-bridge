param()
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'

$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomation\ChromeControl'
$Current=Join-Path $Root 'Current'
$History=Join-Path $Root 'History'
$Logs=Join-Path $Root 'Logs'
$Tmp=Join-Path $Root 'Temp'
New-Item -ItemType Directory -Force -Path $Current,$History,$Logs,$Tmp | Out-Null

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$historyRun=Join-Path $History $stamp
New-Item -ItemType Directory -Force -Path $historyRun | Out-Null

# Archive prior current evidence before replacing it.
Get-ChildItem -LiteralPath $Current -File -ErrorAction SilentlyContinue | ForEach-Object {
  Move-Item -LiteralPath $_.FullName -Destination (Join-Path $historyRun $_.Name) -Force -ErrorAction SilentlyContinue
}

# Clean up only audit artifacts created by this workflow from Desktop.
$desktop=[Environment]::GetFolderPath('Desktop')
$desktopArtifacts=@(
 'CHROME_ALL_EXTENSIONS_AUDIT.json','CHROME_ALL_EXTENSIONS_AUDIT.txt',
 'CHROME_ALL_EXTENSIONS_CLASSIFIED.json','CHROME_ALL_EXTENSIONS_CLASSIFIED.txt'
)
foreach($n in $desktopArtifacts){
  $p=Join-Path $desktop $n
  if(Test-Path -LiteralPath $p){Move-Item -LiteralPath $p -Destination (Join-Path $historyRun $n) -Force -ErrorAction SilentlyContinue}
}

$base='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main'
$auditUrl=$base+'/local-agent/bootstrap/AUDIT_ALL_CHROME_EXTENSIONS.ps1'
$classUrl=$base+'/scripts/windows/chrome-audit/CLASSIFY_CHROME_AUDIT_RESULT.ps1'
$resumeUrl=$base+'/local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1'
$autoResumeUrl=$base+'/local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1'

$auditLocal=Join-Path $Tmp 'AUDIT_ALL_CHROME_EXTENSIONS.ps1'
$classLocal=Join-Path $Tmp 'CLASSIFY_CHROME_AUDIT_RESULT.ps1'
$resumeLocal=Join-Path $Tmp 'RESUME_LOCAL_AGENT_ONCE.ps1'
$autoResumeLocal=Join-Path $Tmp 'INSTALL_AUTO_RESUME_TASK.ps1'

function Dl([string]$u,[string]$p){Invoke-WebRequest -UseBasicParsing -Uri ($u+'?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $p -TimeoutSec 60}
function Log([string]$m){Add-Content -LiteralPath (Join-Path $Logs 'chrome-control.log') -Value ('['+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'] '+$m) -Encoding UTF8}

try{Dl $auditUrl $auditLocal;Dl $classUrl $classLocal;Dl $resumeUrl $resumeLocal;Dl $autoResumeUrl $autoResumeLocal}catch{Log ('DOWNLOAD_FAIL '+$_.Exception.Message);throw}

# Patch audit output away from Desktop into the central Current folder.
$patchedAudit=Join-Path $Tmp 'AUDIT_ALL_CHROME_EXTENSIONS_CENTRAL.ps1'
$txt=Get-Content -LiteralPath $auditLocal -Raw
$escaped=$Current.Replace("'","''")
$txt=$txt -replace "\$desktop = \[Environment\]::GetFolderPath\('Desktop'\)", ("`$desktop = '"+$escaped+"'")
Set-Content -LiteralPath $patchedAudit -Value $txt -Encoding UTF8

$auditJson=Join-Path $Current 'CHROME_ALL_EXTENSIONS_AUDIT.json'
$auditTxt=Join-Path $Current 'CHROME_ALL_EXTENSIONS_AUDIT.txt'
$classJson=Join-Path $Current 'CHROME_ALL_EXTENSIONS_CLASSIFIED.json'
$classTxt=Join-Path $Current 'CHROME_ALL_EXTENSIONS_CLASSIFIED.txt'

# 1) Audit before repair.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patchedAudit | Out-Null
$preAudit=if(Test-Path $auditJson){Get-Content $auditJson -Raw}else{''}
Set-Content -LiteralPath (Join-Path $Current 'PRE_REPAIR_AUDIT.json') -Value $preAudit -Encoding UTF8

# 2) Safe automatic repairs only: scheduled auto-resume + Local Agent/Host/Bridge self-heal.
try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoResumeLocal | Out-Null;Log 'AUTO_RESUME_REPAIR_DONE'}catch{Log ('AUTO_RESUME_REPAIR_FAIL '+$_.Exception.Message)}
try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resumeLocal | Out-Null;Log ('LOCAL_RUNTIME_RESUME_EXIT='+$LASTEXITCODE)}catch{Log ('LOCAL_RUNTIME_RESUME_FAIL '+$_.Exception.Message)}
Start-Sleep -Seconds 5

# 3) Re-audit and classify after repair.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patchedAudit | Out-Null
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classLocal -AuditJson $auditJson -OutJson $classJson -OutTxt $classTxt | Out-Null
$rc=$LASTEXITCODE

# 4) Create one compact status file for humans/central-agent readback.
$overall='UNKNOWN'
$approval=@()
try{
  $c=Get-Content -LiteralPath $classJson -Raw|ConvertFrom-Json
  $overall=[string]$c.overall
  foreach($b in @($c.blockers)){
    if([string]$b.name -match 'Save to Google Drive|UniConverter|permission|OAuth|login'){$approval += $b}
  }
}catch{}
$status=@(
 'HomeDesign Chrome Control',
 ('Updated: '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
 ('Overall: '+$overall),
 ('Current: '+$Current),
 ('History: '+$History),
 ('Desktop audit artifacts: cleaned'),
 'Safe auto-repair: Agent/Host/Bridge runtime + logon/sleep auto-resume',
 'Not auto-modified: browser permissions, extension removal, login/OAuth, publishing, paid actions',
 ('Approval-required items: '+$approval.Count)
)
$status|Set-Content -LiteralPath (Join-Path $Current 'STATUS.txt') -Encoding UTF8

# Keep history bounded: 30 most recent runs.
Get-ChildItem -LiteralPath $History -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '============================================================'
Write-Host 'HOMEDESIGN CHROME CONTROL: AUDIT -> SAFE REPAIR -> RE-AUDIT DONE'
Write-Host ('OVERALL: '+$overall)
Write-Host ('CURRENT: '+$Current)
Write-Host 'Desktop audit files were consolidated automatically.'
Write-Host 'Only approval-sensitive browser changes remain manual.'
Write-Host '============================================================'
if($overall -eq 'PASS'){exit 0}
if($overall -eq 'LIVE_READBACK_REQUIRED'){exit 2}
exit 1
