@echo off
setlocal EnableExtensions
set "PS=%TEMP%\HomeDesignAutomation_RunHardenedRecovery.ps1"
>"%PS%" echo $ErrorActionPreference='Stop'
>>"%PS%" echo $repo='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap'
>>"%PS%" echo $root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
>>"%PS%" echo New-Item -ItemType Directory -Force -Path $root ^| Out-Null
>>"%PS%" echo $installer=Join-Path $root 'INSTALL_AUTO_RESUME_TASK.ps1'
>>"%PS%" echo $cb=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
>>"%PS%" echo Invoke-WebRequest -UseBasicParsing -Uri ($repo+'/INSTALL_AUTO_RESUME_TASK.ps1?hdcb='+$cb) -OutFile $installer -TimeoutSec 60
>>"%PS%" echo try { schtasks.exe /End /TN 'HomeDesignAutomation-AutoResume' ^| Out-Null } catch {}
>>"%PS%" echo ^& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer
>>"%PS%" echo $installRc=$LASTEXITCODE
>>"%PS%" echo $watchdog=Join-Path $root 'HomeDesignLocalWatchdog.ps1'
>>"%PS%" echo if(Test-Path $watchdog){ ^& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $watchdog; $watchdogRc=$LASTEXITCODE } else { $watchdogRc=98 }
>>"%PS%" echo $state=Join-Path $root 'state.json'
>>"%PS%" echo $receipt=Join-Path $root 'WATCHDOG_LAST.json'
>>"%PS%" echo Write-Host ('INSTALL_RC='+$installRc)
>>"%PS%" echo Write-Host ('WATCHDOG_RC='+$watchdogRc)
>>"%PS%" echo if(Test-Path $state){ Write-Host ('STATE='+((Get-Content $state -Raw -Encoding UTF8))) }
>>"%PS%" echo if(Test-Path $receipt){ Write-Host ('WATCHDOG_RECEIPT='+((Get-Content $receipt -Raw -Encoding UTF8))) }
>>"%PS%" echo if($installRc -eq 0 -and $watchdogRc -eq 0){ exit 0 } else { exit 2 }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS%"
set "RC=%ERRORLEVEL%"
del /q "%PS%" >nul 2>&1
exit /b %RC%
