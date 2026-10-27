@echo off
rem One-time setup: grants "Lock pages in memory" (SeLockMemoryPrivilege) to the current user so the Strata
rem DeepSeek engine can put its 120 GB expert RAM store on 2 MB large pages (DS4_STORE_LARGE=1, Zen 2 TLB lever).
rem Approves one UAC prompt. Takes effect after you SIGN OUT and back in (a reboot works too, but is not needed).
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File D:\strata\grant-lock-pages.ps1'"
echo UAC prompt raised. After it completes: sign out and back in, then use run-deepseek-abliterated-largepages.bat
pause
