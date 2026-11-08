@echo off
rem Puts the official DeepSeek engine back for the current folder version (saved by install-from-build.bat in
rem windows\rig\official\<version>\). Note: the official engine has no --ablate, so the abliterated preset will not start on it.
call "%~dp0rig\find-engine-dir.bat" || exit /b 1
if not exist "%~dp0rig\official\%ENGVER%\strata-dsv41.exe" (
  echo StrataRig: no official engine saved for %ENGVER% - nothing to restore.
  exit /b 1
)
copy /y "%~dp0rig\official\%ENGVER%\strata-dsv41.exe" "%ENGDIR%\strata-dsv41.exe" >nul
if exist "%~dp0rig\official\%ENGVER%\strata_kq.dll" copy /y "%~dp0rig\official\%ENGVER%\strata_kq.dll" "%ENGDIR%\strata_kq.dll" >nul
echo StrataRig: official engine %ENGVER% restored.
