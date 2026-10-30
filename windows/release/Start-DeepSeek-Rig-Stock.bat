@echo off
rem DeepSeek-V4.1-Flash, stock (not abliterated), StrataRig patched engine (CUDA graphs).
title DeepSeek-V4.1-Flash - StrataRig (stock)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StrataRig.ps1" start -Stock
pause
