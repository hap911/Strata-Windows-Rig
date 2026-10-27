@echo off
rem Start DeepSeek-V4.1-Flash STOCK (IST-DAS 2.00bpw, 256K) with the 2026-10-26/27 gains:
rem - runs the patched engine build (strata-dsv41.exe.zen2lp: --ablate support dormant without the flag,
rem   per-GPU --reserve-mib, DS4_STORE_LARGE large pages) instead of the stock binary
rem - DS4_STORE_LARGE=1: the 120 GB expert RAM store on 2 MB large pages (needs the one-time
rem   grant-lock-pages.bat + sign-in; without the privilege it logs a line and runs 4 KB pages - harmless)
rem - DS4_SPLIT=14,26: measured optimum on this 3080 Ti + 5090 pair (29.9 vs 28.6 tok/s auto): the 5090
rem   takes 26 of 40 layers because it is ~2.5x faster; the engine's own auto split balances prompt
rem   streaming, not the decode pipeline's slowest stage
rem Tuned settings identical to run-deepseek.bat (which stays as the plain-stock fallback):
rem --ssd-cache 120 keeps ~all CPU-side experts in RAM; --prefill-chunk 4096 is the faster prompt path
rem on this box; --cpu-threads 48 measured faster than 24; --reserve-mib 1000,500 is per-GPU with this engine.
set ENGDIR=%LOCALAPPDATA%\Strata\install\engine-dsv41\0.1.51-windows-x86_64-cuda-cuda13
copy /y "%ENGDIR%\strata-dsv41.exe.zen2lp" "%ENGDIR%\strata-dsv41.exe" >nul
set DS4_STORE_LARGE=1
set DS4_SPLIT=14,26
title DeepSeek-V4.1-Flash Strata server (large pages)
rem NO --vision here (2026-10-27): the dsv41 family is text-only in Strata 0.1.51 - the API server has no
rem image path for this engine at all (docs/DEEPSEEK41.md; feature request Strata #3937). The flag is dropped.
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K" --set ssd-cache=120 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=1000,500 --yes
pause
