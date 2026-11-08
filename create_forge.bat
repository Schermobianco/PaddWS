@echo off
rem Crea da zero la macchina forge in VMware Workstation (tools\forge\create_vm.py): immagine
rem cloud di Debian 13, cloud-init, Docker e console di forge, voce in ~/.ssh/config e
rem forge.local.psd1. Poi basta build_onforge.bat. Opzioni: create_forge.bat --help
setlocal
set PY=%~dp0.venv\Scripts\python.exe
if not exist "%PY%" set PY=python
"%PY%" "%~dp0tools\forge\create_vm.py" %*
exit /b %ERRORLEVEL%
