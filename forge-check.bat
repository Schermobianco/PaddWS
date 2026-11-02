@echo off
rem Controlli prima di un push sulla macchina forge, con i file come sono ora (modifiche e file nuovi,
rem senza commit): Rust, wasm, C64, tracce MiSTer, pytest. Con -Synth anche la sintesi del core MiSTer.
rem Vedi tools\build-release.ps1 (-WorkingTree).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-release.ps1" -WorkingTree %*
exit /b %ERRORLEVEL%
