@echo off
rem Copies a freshly built rig engine into windows\rig\engine\<version>\ (outside Strata's folders) so the launchers
rem can switch it in, and saves the official exe+dll of that engine folder into windows\rig\official\<version>\.
rem Usage: windows\rig\install-from-build.bat [build-dir] [version]
rem The version is read from the built engine's own --version line, so this never mislabels a build.
setlocal
set "BUILDDIR=%~1"
if "%BUILDDIR%"=="" set "BUILDDIR=%~dp0..\..\build\Release"
if not exist "%BUILDDIR%\strata-dsv41.exe" (
  echo No strata-dsv41.exe in %BUILDDIR% - build it first ^(windows\build-strata-engine.bat configure, build^).
  exit /b 1
)
set "VER=%~2"
if not defined VER for /f "tokens=2" %%v in ('"%BUILDDIR%\strata-dsv41.exe" --version 2^>nul') do set "VER=%%v"
if not defined VER (
  echo Could not read the engine's version ^(the --version line^) - pass it: install-from-build.bat ^<build-dir^> ^<version^>
  exit /b 1
)
set "DST=%~dp0engine\%VER%"
if not exist "%DST%" mkdir "%DST%"
copy /y "%BUILDDIR%\strata-dsv41.exe" "%DST%\" >nul
copy /y "%BUILDDIR%\strata_kq.dll" "%DST%\" >nul
echo StrataRig: engine %VER% installed to %DST% - the launchers switch it in at their next start.
call "%~dp0find-engine-dir.bat"
if defined ENGDIR if "%ENGVER%"=="%VER%" if not exist "%~dp0official\%VER%\strata-dsv41.exe" (
  if not exist "%~dp0official\%VER%" mkdir "%~dp0official\%VER%"
  copy /y "%ENGDIR%\strata-dsv41.exe" "%~dp0official\%VER%\strata-dsv41.exe" >nul
  copy /y "%ENGDIR%\strata_kq.dll" "%~dp0official\%VER%\strata_kq.dll" >nul
  echo StrataRig: official engine %VER% saved in %~dp0official\%VER% ^(windows\restore-official-engine.bat^).
)
endlocal