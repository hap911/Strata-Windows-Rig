@echo off
rem EXPERIMENT: as run-deepseek-abliterated-largepages-graphs.bat, plus whole-expert mode: during decode each GPU also
rem computes the layer's experts that the OTHER GPU holds, and some CPU-lane experts straight from the RAM store over PCIe.
rem Before CUDA graphs this was ~10% faster per token; with graphs it measured ~1-2% SLOWER than the graphs launcher
rem (~82 vs ~80.5 s on the 6-turn test), so the graphs launcher is the recommended one. Kept for comparison.
rem If the first request fails with "out of memory", set DS4_WHOLE_PULL_GB=48 (default 64) or remove DS4_WHOLE_PULL.
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
set DS4_WHOLE_EXPERT=1
set DS4_WHOLE_PULL=1
set DS4_ATTN_GRAPH=1
title DeepSeek-V4.1-Flash Strata server (abliterated, whole-expert experiment)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K abliterated" --set ablate="D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=900,100 --vision on --yes
pause
