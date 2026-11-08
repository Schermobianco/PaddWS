@echo off
rem Release in locale sulla macchina forge (tools\forge): gli stessi controlli e pacchetti delle
rem GitHub Action, core MiSTer compreso, in dist\. Accende e spegne forge da solo.
rem Opzioni: -Publish -NoCheck -CheckOnly -SkipMister -KeepVm (vedi tools\build-release.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-release.ps1" %*
exit /b %ERRORLEVEL%
