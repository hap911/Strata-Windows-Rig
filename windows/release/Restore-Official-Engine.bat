@echo off
rem Puts Strata's official DeepSeek engine back (the StrataRig launchers switch the patched one in again at their next start).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StrataRig.ps1" restore
pause
