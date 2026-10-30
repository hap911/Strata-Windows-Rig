@echo off
rem Sets ENGDIR to Strata's newest installed DeepSeek engine folder (engine-dsv41\<version>-windows-x86_64-cuda-*).
rem Strata deletes the old folder when it updates the engine, so the launchers look it up instead of hard-coding it.
set "ENGDIR="
for /f "delims=" %%D in ('dir /b /ad /o-n "%LOCALAPPDATA%\Strata\install\engine-dsv41\*-windows-x86_64-cuda-*" 2^>nul') do (
  if not defined ENGDIR set "ENGDIR=%LOCALAPPDATA%\Strata\install\engine-dsv41\%%D"
)
if not defined ENGDIR (
  echo No DeepSeek engine found under %LOCALAPPDATA%\Strata\install\engine-dsv41 - launch the stock model once first.
  exit /b 1
)
exit /b 0
