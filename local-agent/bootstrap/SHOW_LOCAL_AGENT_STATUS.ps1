param()
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$State = Join-Path $Root 'state.json'
Write-Host '=============================================================='
Write-Host ' HomeDesign Local Agent STATUS'
Write-Host '=============================================================='
if(Test-Path -LiteralPath $State){
  try{
    $j=Get-Content -LiteralPath $State -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host ('STATUS            : ' + $j.status)
    Write-Host ('AGENT VERSION     : ' + $j.agentVersion)
    Write-Host ('INSTALLED VERSION : ' + $j.installedVersion)
    Write-Host ('CANDIDATE VERSION : ' + $j.candidateVersion)
    Write-Host ('AWAITING E2E      : ' + $j.awaitingE2E)
    Write-Host ('LAST SUCCESS      : ' + $j.lastSuccessAt)
    Write-Host ('LAST ERROR        : ' + $j.lastError)
    Write-Host ('UPDATED AT        : ' + $j.updatedAt)
  }catch{
    Write-Host ('state.json read failed: ' + $_.Exception.Message)
  }
}else{
  Write-Host 'STATUS: NOT INSTALLED / FIRST CYCLE NOT FINISHED'
}
Write-Host ('ROOT: ' + $Root)
Write-Host '=============================================================='
pause
