@echo off
setlocal EnableExtensions
set "PS=%TEMP%\HomeDesignAutomation_RunHardenedRecovery.ps1"
>"%PS%" echo $ErrorActionPreference='Stop'
>>"%PS%" echo $repo='8friend8ship-cloud/notebooklm-webapp-bridge'
>>"%PS%" echo $api='https://api.github.com/repos/'+$repo+'/contents'
>>"%PS%" echo $raw='https://raw.githubusercontent.com/'+$repo+'/main'
>>"%PS%" echo $root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
>>"%PS%" echo New-Item -ItemType Directory -Force -Path $root ^| Out-Null
>>"%PS%" echo $installer=Join-Path $root 'INSTALL_AUTO_RESUME_TASK.ps1'
>>"%PS%" echo $cb=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
>>"%PS%" echo Invoke-WebRequest -UseBasicParsing -Uri ($raw+'/local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1?hdcb='+$cb) -OutFile $installer -TimeoutSec 60
>>"%PS%" echo try { schtasks.exe /End /TN 'HomeDesignAutomation-AutoResume' ^| Out-Null } catch {}
>>"%PS%" echo ^& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
>>"%PS%" echo $installRc=$LASTEXITCODE
>>"%PS%" echo $watchdog=Join-Path $root 'HomeDesignLocalWatchdog.ps1'
>>"%PS%" echo if(Test-Path $watchdog){ ^& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $watchdog; $watchdogRc=$LASTEXITCODE } else { $watchdogRc=98 }
>>"%PS%" echo $headers=@{'User-Agent'='HomeDesign-Hardened-Recovery';'Accept'='application/vnd.github+json'}
>>"%PS%" echo $stable=Invoke-RestMethod -Uri ($api+'/local-agent/stable/agent.json?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -TimeoutSec 30
>>"%PS%" echo $stableJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$stable.content -replace '\s','')))^|ConvertFrom-Json
>>"%PS%" echo if(-not $stableJson.enabled){ throw 'STABLE_AGENT_DISABLED' }
>>"%PS%" echo $version=[string]$stableJson.version
>>"%PS%" echo $expected=[string]$stableJson.gitBlobSha1
>>"%PS%" echo $agentMeta=Invoke-RestMethod -Uri ($api+'/local-agent/releases/'+$version+'/HomeDesignLocalAgent.ps1?ref=main&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Headers $headers -TimeoutSec 30
>>"%PS%" echo if(([string]$agentMeta.sha).ToLowerInvariant() -ne $expected.ToLowerInvariant()){ throw ('STABLE_AGENT_SHA_MISMATCH api='+[string]$agentMeta.sha+' expected='+$expected) }
>>"%PS%" echo $agent=Join-Path $root ('HomeDesignLocalAgent-'+$version+'-stable.ps1')
>>"%PS%" echo [IO.File]::WriteAllBytes($agent,[Convert]::FromBase64String(([string]$agentMeta.content -replace '\s','')))
>>"%PS%" echo ^& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $agent
>>"%PS%" echo $agentRc=$LASTEXITCODE
>>"%PS%" echo $state=Join-Path $root 'state.json'
>>"%PS%" echo $receipt=Join-Path $root 'WATCHDOG_LAST.json'
>>"%PS%" echo Write-Host ('INSTALL_RC='+$installRc)
>>"%PS%" echo Write-Host ('WATCHDOG_RC='+$watchdogRc)
>>"%PS%" echo Write-Host ('STABLE_AGENT_VERSION='+$version)
>>"%PS%" echo Write-Host ('STABLE_AGENT_RC='+$agentRc)
>>"%PS%" echo if(Test-Path $state){ Write-Host ('STATE='+((Get-Content $state -Raw -Encoding UTF8))) }
>>"%PS%" echo if(Test-Path $receipt){ Write-Host ('WATCHDOG_RECEIPT='+((Get-Content $receipt -Raw -Encoding UTF8))) }
>>"%PS%" echo if($installRc -eq 0 -and $watchdogRc -eq 0 -and $agentRc -eq 0){ exit 0 } else { exit 2 }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS%"
set "RC=%ERRORLEVEL%"
del /q "%PS%" >nul 2>&1
exit /b %RC%
