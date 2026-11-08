@echo off
rem Finds Strata's current DeepSeek engine folder: sets ENGDIR and ENGVER (the folder's version).
set "ENGDIR="
for /f "delims=" %%D in ('dir /b /ad /o-n "%LOCALAPPDATA%\Strata\install\engine-dsv41\*-windows-x86_64-cuda-*" 2^>nul') do if not defined ENGDIR set "ENGDIR=%LOCALAPPDATA%\Strata\install\engine-dsv41\%%D"
if not defined ENGDIR (
  echo StrataRig: no DeepSeek engine folder under %LOCALAPPDATA%\Strata\install\engine-dsv41 - launch the stock model once first.
  exit /b 1
)
for %%F in ("%ENGDIR%") do set "ENGFOLDER=%%~nxF"
for /f "tokens=1 delims=-" %%v in ("%ENGFOLDER%") do set "ENGVER=%%v"
exit /b 0