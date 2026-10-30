@echo off
rem StrataRig first-time setup: installs official Strata if missing, then the patched DeepSeek engine.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StrataRig.ps1" setup
pause
