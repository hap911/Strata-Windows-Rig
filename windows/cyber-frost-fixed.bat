@echo off
rem cyber-frost-fixed: start/status/stats for the CYBER-FROST server with frozen tuned parameters.
rem Usage: cyber-frost-fixed        (starts the server in this window; close to stop)
rem        cyber-frost-fixed status (is it up?)
rem        cyber-frost-fixed stats  (MTP/speculative decoding and cache statistics)
set STRATA_HOME=%LOCALAPPDATA%\Strata\terminal\current
if /i "%~1"=="status" (
    curl -s -m 5 http://127.0.0.1:8080/health
    echo.
    exit /b 0
)
if /i "%~1"=="stats" (
    "%STRATA_HOME%\python\python.exe" "D:\strata\cyber_frost_stats.py"
    exit /b 0
)
pushd "%STRATA_HOME%"
"%STRATA_HOME%\python\python.exe" -m serve.server --engine strata --config "D:\strata\configs\strata-cyber-frost-windows-fixed.json" --port 8080
popd
