@echo off
rem DeepSeek-V4.1-Flash STOCK (not abliterated) on the patched engine, with the CUDA-graph speed-up and large pages.
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
set DS4_ATTN_GRAPH=1
title DeepSeek-V4.1-Flash Strata server (stock model, CUDA graphs, large pages)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=900,100 --vision on --yes
pause
