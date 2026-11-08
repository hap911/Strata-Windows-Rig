@echo off
rem Finds Strata's current DeepSeek engine folder and switches the rig build in when a build for that version exists.
rem Sets: ENGDIR (the engine folder), ENGVER (its version), USE_RIG (1 = rig build active, 0 = official engine).
rem The rig builds live in windows\rig\engine\<version>\ - OUTSIDE Strata's folders, so a Strata update cannot delete them.
rem After a Strata engine update the folder version changes: the launcher then runs the official engine and says so
rem (never a version-mismatched rig build - that is what broke a setup before). Rebuild for the new version, or ask
rem Claude to re-port the patches onto it.
set "ENGDIR="
for /f "delims=" %%D in ('dir /b /ad /o-n "%LOCALAPPDATA%\Strata\install\engine-dsv41\*-windows-x86_64-cuda-*" 2^>nul') do if not defined ENGDIR set "ENGDIR=%LOCALAPPDATA%\Strata\install\engine-dsv41\%%D"
if not defined ENGDIR (
  echo StrataRig: no DeepSeek engine folder under %LOCALAPPDATA%\Strata\install\engine-dsv41 - launch the stock model once first.
  exit /b 1
)
for %%F in ("%ENGDIR%") do set "ENGFOLDER=%%~nxF"
for /f "tokens=1 delims=-" %%v in ("%ENGFOLDER%") do set "ENGVER=%%v"
set "RIGDIR=%~dp0engine\%ENGVER%"
if not exist "%RIGDIR%\strata-dsv41.exe" (
  echo StrataRig: no rig build for engine %ENGVER% ^(looked in %RIGDIR%^) - starting the OFFICIAL engine.
  echo StrataRig: the official engine has no --ablate and no CUDA graphs. If Strata updated its engine, rebuild the
  echo StrataRig: rig for %ENGVER% first ^(windows\rig\install-from-build.bat^) or ask Claude to re-port the patches onto it.
  set "USE_RIG=0"
  exit /b 0
)
copy /y "%RIGDIR%\strata-dsv41.exe" "%ENGDIR%\strata-dsv41.exe" >nul
copy /y "%RIGDIR%\strata_kq.dll" "%ENGDIR%\strata_kq.dll" >nul
echo StrataRig: patched engine %ENGVER% active.
set "USE_RIG=1"
exit /b 0