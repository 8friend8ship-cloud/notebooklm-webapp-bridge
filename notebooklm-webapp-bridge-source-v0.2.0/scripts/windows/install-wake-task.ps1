param(
  [int]$IntervalMinutes = 15,
  [string]$TaskName = 'NotebookLM Bridge Wake'
)

$ErrorActionPreference = 'Stop'

if ($IntervalMinutes -lt 5) { throw 'IntervalMinutes는 최소 5분 이상으로 설정하세요.' }

$launcher = Join-Path $PSScriptRoot 'bridge-wake.ps1'
if (!(Test-Path $launcher)) { throw "bridge-wake.ps1을 찾을 수 없습니다: $launcher" }

$action = New-ScheduledTaskAction `
  -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""

$start = (Get-Date).AddMinutes(1)
$trigger = New-ScheduledTaskTrigger `
  -Once `
  -At $start `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
  -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
  -WakeToRun `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

$principal = New-ScheduledTaskPrincipal `
  -UserId $env:USERNAME `
  -LogonType Interactive `
  -RunLevel Highest

$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null

Write-Host "설치 완료: $TaskName"
Write-Host "반복 주기: $IntervalMinutes 분"
Write-Host 'Windows 전원 옵션의 깨우기 타이머 허용도 활성화되어 있어야 합니다.'
Write-Host "테스트: Start-ScheduledTask -TaskName '$TaskName'"
