@echo off
rem RECOMMENDED daily driver: DeepSeek-V4.1-Flash ABLITERATED, rig engine, decode as CUDA graphs, large pages.
rem Measured on the reference rig (6-turn coding conversation, 400 tokens a turn, engine 0.1.58): decode
rem ~34.5 tok/s average with the desktop in use (30.8-37.4; ~38 quiet), ~85 s; prompts ~399 tok/s; without
rem graphs ~26-27. reserve-mib=1200,100 keeps the desktop card out of memory pressure (at 900: decode 24.5).
rem   DS4_ATTN_GRAPH=1   each decode layer's GPU work as CUDA graphs (byte-identical output; delete the line to turn off)
rem   DS4_SETTLE_MS=0    no pause after each prompt (~-9% on multi-turn work)
rem   DS4_STORE_LARGE=1  RAM store on 2 MB large pages (needs grant-lock-pages.bat once; no measured speed change -
rem                      it locks the store in RAM; delete the line to use normal pages)
rem   DS4_SPLIT=14,26    3080 Ti takes layers 0-13, the 5090 the other 26 (retune for your GPUs)
rem StrataRig: windows\rig\use-rig-engine.bat finds Strata's CURRENT engine folder and switches the rig build in
rem when the versions match; after a Strata engine update it starts the official engine and says what to do.
rem Needs windows\build-strata-engine.bat configure / build / install once (and again after each Strata engine update).
call "%~dp0rig\use-rig-engine.bat"
if not "%USE_RIG%"=="1" goto official
set DS4_STORE_LARGE=1
set DS4_SPLIT=14,26
set DS4_SETTLE_MS=0
set DS4_ATTN_GRAPH=1
title DeepSeek-V4.1-Flash Strata server (abliterated, CUDA graphs, rig engine %ENGVER%)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K abliterated" --set ablate="D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=1200,100 --vision on --yes
pause
exit /b 0
:official
title DeepSeek-V4.1-Flash Strata server (OFFICIAL engine - no rig build for this version)
"%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd" launch --preset "IST-DAS-2.00bpw 256K" --set ssd-cache=135 --set prefill-chunk=4096 --set cpu-threads=48 --set reserve-mib=1200,100 --vision on --yes
pause