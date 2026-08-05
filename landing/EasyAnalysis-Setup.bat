@echo off
REM ==========================================================================
REM  EasyAnalysis - double-click installer for Windows
REM --------------------------------------------------------------------------
REM  This exists so a first install needs no terminal at all. It does exactly
REM  what the documented one-liner does -- fetch and run install.ps1 -- but the
REM  user only has to double-click a file instead of opening PowerShell and
REM  pasting a command.
REM
REM  -ExecutionPolicy Bypass applies to THIS process only; it changes nothing
REM  on the machine. No administrator rights are required at any point.
REM
REM  After this finishes there will be an EasyAnalysis shortcut on the Desktop
REM  and in the Start Menu, so the terminal is never needed again.
REM ==========================================================================

title EasyAnalysis Setup
echo.
echo   Installing EasyAnalysis
echo   ----------------------
echo   R and the required packages are downloaded automatically if you do not
echo   already have them. The first run can take several minutes; after that
echo   the app starts in seconds.
echo.
echo   Nothing is installed for other users and no administrator rights are
echo   needed. You can close this window when the app has opened.
echo.

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { iwr -useb https://easyanalysis.dev/install.ps1 | iex } catch { Write-Host ''; Write-Host ('Setup failed: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"

if errorlevel 1 (
  echo.
  echo   Setup did not finish. Common causes:
  echo     - no internet connection
  echo     - a firewall or proxy blocking the download
  echo.
  echo   You can also install by opening PowerShell and running:
  echo     iwr -useb https://easyanalysis.dev/install.ps1 ^| iex
  echo.
  pause
  exit /b 1
)

echo.
echo   Done. Use the EasyAnalysis shortcut on your Desktop from now on.
echo.
pause
