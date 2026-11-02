@echo off
rem Release online come prima: tools\release.py, push del tag, avvio delle GitHub Action che
rem costruiscono tutti i pacchetti (core MiSTer compreso). Uso: build_ongithub.bat [VERSIONE] [-NoCheck] [-NoWait]
rem (vedi tools\build-github.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-github.ps1" %*
exit /b %ERRORLEVEL%
