@echo off
rem deepseek-abliterated: start/stop/status/stats for the abliterated DeepSeek server.
rem Usage: deepseek-abliterated        (starts the server in this window; close to stop)
rem        deepseek-abliterated status (is it up?)
rem        deepseek-abliterated stop   (stop the server)
rem        deepseek-abliterated stats  (speed and expert-lane statistics)
set STRATA_BIN=%LOCALAPPDATA%\Strata\terminal\current\bin\strata.cmd
if /i "%~1"=="status" (
    curl -s -m 5 http://127.0.0.1:8080/health
    echo.
    exit /b 0
)
if /i "%~1"=="stop" (
    call "%STRATA_BIN%" launch --stop
    exit /b 0
)
if /i "%~1"=="stats" (
    "%LOCALAPPDATA%\Strata\terminal\current\python\python.exe" "D:\strata\deepseek_stats.py"
    exit /b 0
)
call "%~dp0run-deepseek-abliterated-largepages-graphs.bat"
