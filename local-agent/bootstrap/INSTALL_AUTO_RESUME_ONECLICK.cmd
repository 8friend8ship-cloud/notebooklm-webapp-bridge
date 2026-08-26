@echo off
setlocal EnableExtensions
chcp 65001 >nul
title HomeDesign Auto Resume Installer

set "URL=https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/bootstrap/INSTALL_AUTO_RESUME_TASK.ps1"
set "PS1=%TEMP%\INSTALL_AUTO_RESUME_TASK.ps1"

echo ============================================================
echo HomeDesign AUTO RESUME INSTALLER
echo - Windows logon auto recovery
echo - Sleep/wake auto recovery
echo - Existing ChromeUserData login/session preserved
echo - Normal Chrome is not reset or reauthorized
echo ============================================================
echo.

echo [1/2] Downloading current installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri ('%URL%?hdcb=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile '%PS1%' -TimeoutSec 60"
if errorlevel 1 goto :fail

echo [2/2] Installing automatic resume task and running first self-heal...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo ============================================================
  echo AUTO RESUME: INSTALLED
  echo Next reboot/logon and sleep-resume will self-heal automatically.
  echo Chrome automation will reuse the existing persistent login profile.
  echo ============================================================
) else (
  echo ============================================================
  echo AUTO RESUME INSTALL FAILED ^(exit=%RC%^)
  echo Send this screen to ChatGPT. Do not delete ChromeUserData.
  echo ============================================================
)
echo.
pause
exit /b %RC%

:fail
echo.
echo DOWNLOAD FAILED - NOTHING WAS CHANGED
pause
exit /b 1
