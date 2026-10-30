@echo off
rem DeepSeek-V4.1-Flash, abliterated, StrataRig patched engine (CUDA graphs). Settings: %LOCALAPPDATA%\StrataRig\StrataRig.config.json
title DeepSeek-V4.1-Flash - StrataRig
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StrataRig.ps1" start
pause
