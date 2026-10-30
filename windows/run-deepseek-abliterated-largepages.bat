@echo off
rem DeepSeek-V4.1-Flash ABLITERATED on the patched engine WITHOUT the CUDA-graph speed-up (the pre-2026-10-30 behaviour,
rem ~26-28 tok/s). Kept for A/B comparisons; use run-deepseek-abliterated-largepages-graphs.bat day to day.
call "%~dp0find-engine-dir.bat" || (pause & exit /b 1)
if not exist "%ENGDIR%\strata-dsv41.exe.rig" (
  echo Patched engine not installed in %ENGDIR% - run build-strata-engine.bat install first.
  pause
  exit /b 1
)
copy /y "%ENGDIR%\strata-dsv41.exe.rig" "%ENGDIR%\strata-dsv41.exe" >nul
copy /y "%ENGDIR%\strata_kq.dll.rig" "%ENGDIR%\strata_kq.dll" >nul
set DS4_STORE_LARGE=1
set DS4_SPLIT=14,26
set DS4_SETTLE_MS=0
title DeepSeek-V4.1-Flash Strata server (abliterated, large pages, no graphs)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K abliterated" --set ablate="D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=900,100 --vision on --yes
pause
