@echo off
rem Puts Strata's official DeepSeek engine back (saved once by build-strata-engine.bat install as strata-dsv41.exe.official).
rem Note: the official engine has no --ablate, so the abliterated preset will not start on it.
call "%~dp0find-engine-dir.bat" || exit /b 1
if not exist "%ENGDIR%\strata-dsv41.exe.official" (
  echo No saved official engine in %ENGDIR% - nothing to restore.
  exit /b 1
)
copy /y "%ENGDIR%\strata-dsv41.exe.official" "%ENGDIR%\strata-dsv41.exe" >nul
echo Official engine restored in %ENGDIR%.
