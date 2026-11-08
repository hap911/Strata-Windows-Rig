@echo off
rem DeepSeek-V4.1-Flash ABLITERATED on the rig engine WITHOUT the CUDA-graph speed-up (A/B comparisons only).
call "%~dp0rig\use-rig-engine.bat"
if not "%USE_RIG%"=="1" goto official
set DS4_STORE_LARGE=1
set DS4_SPLIT=14,26
set DS4_SETTLE_MS=0
title DeepSeek-V4.1-Flash Strata server (abliterated, no graphs, rig engine %ENGVER%)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K abliterated" --set ablate="D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=1200,100 --vision on --yes
pause
exit /b 0
:official
title DeepSeek-V4.1-Flash Strata server (OFFICIAL engine - no rig build for this version)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=1200,100 --vision on --yes
pause