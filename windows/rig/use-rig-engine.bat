@echo off
rem Finds Strata's current DeepSeek engine folder and switches a rig build in.
rem Sets: ENGDIR (the engine folder), ENGVER (its version), RIGVER (the rig build's version), USE_RIG (1 = rig active).
rem Rig builds live in %~dp0engine\<version>\ - OUTSIDE Strata's folders, so an engine update cannot delete them.
rem POLICY: when there is no rig build for the folder's version, the NEWEST rig build runs in that folder anyway.
rem The rig engine accepts the same command line as the Terminal's launches (0.1.58 built for the 0.1.46-era
rem Terminal; verified against a 0.1.59 folder), so an upstream engine update no longer stops it. A warning says
rem the build is older than the folder; re-porting onto the new upstream release is optional, not required.
set "ENGDIR="
for /f "delims=" %%D in ('dir /b /ad /o-n "%LOCALAPPDATA%\Strata\install\engine-dsv41\*-windows-x86_64-cuda-*" 2^>nul') do if not defined ENGDIR set "ENGDIR=%LOCALAPPDATA%\Strata\install\engine-dsv41\%%D"
if not defined ENGDIR (
  echo StrataRig: no DeepSeek engine folder under %LOCALAPPDATA%\Strata\install\engine-dsv41 - launch the stock model once first.
  exit /b 1
)
for %%F in ("%ENGDIR%") do set "ENGFOLDER=%%~nxF"
for /f "tokens=1 delims=-" %%v in ("%ENGFOLDER%") do set "ENGVER=%%v"
set "RIGDIR=%~dp0engine\%ENGVER%"
if exist "%RIGDIR%\strata-dsv41.exe" goto rigok
set "NEWEST="
for /f "delims=" %%D in ('dir /b /ad /o-n %~dp0engine\* 2^>nul') do if not defined NEWEST set "NEWEST=%~dp0engine\%%D"
if defined NEWEST set "RIGDIR=%NEWEST%"
:rigok
if not exist "%RIGDIR%\strata-dsv41.exe" (
  echo StrataRig: no rig build at all in %~dp0engine - starting the OFFICIAL engine ^(no --ablate, no CUDA graphs^).
  echo StrataRig: build one first ^(rig\install-from-build.bat^).
  set "USE_RIG=0"
  exit /b 0
)
for %%F in ("%RIGDIR%") do set "RIGVER=%%~nxF"
if not "%RIGVER%"=="%ENGVER%" echo StrataRig: rig build %RIGVER% runs in Strata's %ENGVER% folder ^(same command line; re-port onto %ENGVER% is optional^).
copy /y "%RIGDIR%\strata-dsv41.exe" "%ENGDIR%\strata-dsv41.exe" >nul
copy /y "%RIGDIR%\strata_kq.dll" "%ENGDIR%\strata_kq.dll" >nul
echo StrataRig: patched engine %RIGVER% active.
set "USE_RIG=1"
exit /b 0