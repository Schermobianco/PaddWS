@echo off
rem Controlli prima di un push con le GitHub Action, per chi non ha la macchina forge: i file come
rem sono ora (modifiche e file nuovi, senza commit) su un ramo temporaneo, poi Rust, Python, C64 e
rem MiSTer con la sintesi. Uso: check_ongithub.bat [-NoSynth] [-NoWait] [-Keep]
rem (vedi tools\check-github.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\check-github.ps1" %*
exit /b %ERRORLEVEL%
