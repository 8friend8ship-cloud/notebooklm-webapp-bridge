param(
  [string]$ProjectTitle = 'WEBAPP_TEMPLATE_03',
  [string]$SpreadsheetId = '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk',
  [string]$ExpectedDeploymentId = 'AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P',
  [string]$Repo = '8friend8ship-cloud/notebooklm-webapp-bridge',
  [string]$Branch = 'feat/central-daily-qa-asset-governor-20260828'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$AgentStatePath=Join-Path $Base 'LocalAgent\state.json'

function Emit([hashtable]$r,[int]$code){
  $r.at=(Get-Date).ToString('o')
  Write-Output ('CENTRAL_CHAT_FACTORY_D82_GATE_JSON='+($r|ConvertTo-Json -Depth 20 -Compress))
  exit $code
}

try {
  $host=$null
  try{$host=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 3}catch{}
  if($null -eq $host -or -not [bool]$host.ok){
    Emit @{ok=$false;status='HOLD_RECOVERY';stage='D82_HOST_NOT_FRESH_HEALTHY';rule='NO_LOCAL_CLASP_WORK_BEFORE_FRESH_DEVICE_RUNTIME'} 40
  }
  if(-not(Test-Path -LiteralPath $AgentStatePath)){
    Emit @{ok=$false;status='HOLD_RECOVERY';stage='D82_AGENT_STATE_MISSING';hostVersion=[string]$host.version;rule='NO_LOCAL_CLASP_WORK_BEFORE_FRESH_DEVICE_RUNTIME'} 41
  }
  $agentFile=Get-Item -LiteralPath $AgentStatePath
  $ageMin=((Get-Date)-$agentFile.LastWriteTime).TotalMinutes
  $agent=Get-Content -LiteralPath $AgentStatePath -Raw -Encoding UTF8|ConvertFrom-Json
  $agentStatus=[string]$agent.status
  $agentVersion=[string]$agent.agentVersion
  if($ageMin -gt 30 -or $agentStatus -notmatch 'RUN|READY|PASS|HEALTH'){
    Emit @{ok=$false;status='HOLD_RECOVERY';stage='D82_AGENT_STATE_STALE_OR_UNHEALTHY';hostVersion=[string]$host.version;agentVersion=$agentVersion;agentStatus=$agentStatus;agentStateAgeMinutes=[math]::Round($ageMin,1);rule='FRESH_DEVICE_READBACK_FIRST'} 42
  }

  $tmp=Join-Path $env:TEMP ('CentralChatFactorySync_'+[guid]::NewGuid().ToString('N')+'.ps1')
  $raw='https://raw.githubusercontent.com/'+$Repo+'/'+$Branch+'/local-agent/governor/SyncCentralChatWorkFactoryBoundScript.ps1'
  Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $tmp -TimeoutSec 30
  if(-not(Test-Path -LiteralPath $tmp)){Emit @{ok=$false;status='FAILED_TEST';stage='SYNC_HELPER_DOWNLOAD_MISSING'} 43}
  $args=@('-ProjectTitle',$ProjectTitle,'-SpreadsheetId',$SpreadsheetId,'-ExpectedDeploymentId',$ExpectedDeploymentId,'-Repo',$Repo,'-Branch',$Branch)
  $out=& $tmp @args 2>&1
  $exit=$LASTEXITCODE
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Write-Output $out
  exit $exit
}catch{
  Emit @{ok=$false;status='FAILED_TEST';stage='D82_GATE_UNHANDLED';error=$_.Exception.Message;rule='STOP_NO_BLIND_RETRY'} 49
}
