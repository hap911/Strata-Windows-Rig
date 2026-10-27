@echo off
rem DeepSeek-V4.1-Flash ABLITERATED + LARGE PAGES experiment (Zen 2 TLB lever, DS4_STORE_LARGE=1).
rem Same tuned settings as run-deepseek-abliterated.bat, but runs the build with the large-page patch
rem (strata-dsv41.exe.zen2lp) and sets DS4_STORE_LARGE=1: the 120 GB expert RAM store goes on 2 MB large pages.
rem Requires: grant-lock-pages.bat run once + sign out/in (otherwise it logs "no SeLockMemoryPrivilege" and
rem falls back to normal 4 KB pages - harmless, just no gain). Existing launchers are untouched; the proven
rem binary stays as strata-dsv41.exe.ablate.
set ENGDIR=%LOCALAPPDATA%\Strata\install\engine-dsv41\0.1.51-windows-x86_64-cuda-cuda13
copy /y "%ENGDIR%\strata-dsv41.exe.zen2lp" "%ENGDIR%\strata-dsv41.exe" >nul
set DS4_STORE_LARGE=1
rem DS4_SPLIT=14,26: measured optimum on this 3080 Ti + 5090 pair (2026-10-26): 29.9 tok/s decode vs 28.6 with the
rem engine's auto 18/22 (and 28.7-28.9 at 12/28 and 15/25). The 5090 is ~2.5x faster, so it takes 26 of 40 layers;
rem the engine's own auto split balances prompt streaming, not the decode pipeline's slowest stage.
set DS4_SPLIT=14,26
title DeepSeek-V4.1-Flash Strata server (abliterated, large pages)
rem NO --vision here (2026-10-27): the dsv41 family is text-only in Strata 0.1.51 - the API server has no
rem image path for this engine at all (docs/DEEPSEEK41.md; feature request Strata #3937). The flag is dropped.
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K abliterated" --set ablate="D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf" --set ssd-cache=120 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=1000,500 --yes
pause
