@echo off
rem RECOMMENDED daily driver: DeepSeek-V4.1-Flash ABLITERATED, patched engine, decode as CUDA graphs, large pages.
rem Measured on the reference rig (6-turn coding conversation, 400 tokens a turn, engine 0.1.54 base):
rem   ~80 s total and ~38 tok/s decode (up to 42.4 on warmed-up turns), vs ~26-27 tok/s without graphs and
rem   ~119 s for the old launcher.
rem   DS4_ATTN_GRAPH=1   each decode layer's GPU work as CUDA graphs (byte-identical output; delete the line to turn off)
rem   DS4_SETTLE_MS=0    no pause after each prompt (~-9% on multi-turn work)
rem   DS4_STORE_LARGE=1  RAM store on 2 MB large pages (needs grant-lock-pages.bat once; no measured speed change -
rem                      it locks the store in RAM; delete the line to use normal pages)
rem   DS4_SPLIT=14,26    3080 Ti takes layers 0-13, the 5090 the other 26 (retune for your GPUs)
rem Needs build-strata-engine.bat configure / build / install once (and again after each Strata engine update).
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
title DeepSeek-V4.1-Flash Strata server (abliterated, CUDA graphs, large pages)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K abliterated" --set ablate="D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=900,100 --vision on --yes
pause
