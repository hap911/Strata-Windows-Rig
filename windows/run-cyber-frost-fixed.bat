@echo off
rem Starts the CYBER-FROST 3.8 Strata server (native Windows), FIXED variant:
rem tuned parameters frozen in the config (--spec-min-p 0.5 --host-core last),
rem independent of the tuning-preset system. Immune to "graphics card changed" resets.
rem First start loads ~111 GB into RAM: expect 1-3 minutes.
rem Close this window (or Ctrl+C) to stop the server.
set STRATA_HOME=%LOCALAPPDATA%\Strata\terminal\current
cd /d "%STRATA_HOME%"
"%STRATA_HOME%\python\python.exe" -m serve.server --engine strata --config "D:\strata\configs\strata-cyber-frost-windows-fixed.json" --port 8080
pause
