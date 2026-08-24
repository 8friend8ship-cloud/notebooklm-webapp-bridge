param()
$Root = Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\ChromeGovernor'
$State = Join-Path $Root 'state.json'
Write-Host '=============================================================='
Write-Host ' HomeDesign Chrome Extension Governor STATUS'
Write-Host '=============================================================='
if(Test-Path -LiteralPath $State){
  try{
    $j=Get-Content -LiteralPath $State -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host ('OK                : ' + $j.ok)
    Write-Host ('VERSION           : ' + $j.version)
    Write-Host ('GENERATED AT      : ' + $j.generatedAt)
    Write-Host ('TOTAL EXTENSIONS  : ' + $j.summary.total)
    Write-Host ('CENTRAL MANAGED   : ' + $j.summary.centralManaged)
    Write-Host ('MANAGED PROBLEMS  : ' + $j.summary.managedProblems)
    Write-Host ('SECURITY HOLD     : ' + $j.summary.securityHold)
    Write-Host ('UNREGISTERED      : ' + $j.summary.unpackedUnregistered)
    Write-Host ('DUPLICATES        : ' + $j.summary.duplicates)
    Write-Host ('NLM TARGET        : ' + $j.notebookLocalAgent.targetVersion)
    Write-Host ('NLM INSTALLED     : ' + $j.notebookLocalAgent.installedVersion)
    Write-Host ('NLM AGENT LOOP    : ' + $j.notebookLocalAgent.bootstrapRunning)
    Write-Host ''
    foreach($e in @($j.extensions)){
      if($e.classification -ne 'UNREGISTERED_OBSERVE_ONLY'){
        Write-Host ('['+$e.classification+'] '+$e.name+' v'+$e.installedVersion+' / '+$e.profile+' / '+$e.action)
      }
    }
  }catch{
    Write-Host ('state.json read failed: ' + $_.Exception.Message)
  }
}else{
  Write-Host 'STATUS: FIRST GOVERNOR CYCLE NOT FINISHED'
}
Write-Host ''
Write-Host ('ROOT: ' + $Root)
Write-Host '=============================================================='
pause
