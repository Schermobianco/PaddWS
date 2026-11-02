# Attiva la toolchain Rust portable (e MinGW) nella sola sessione PowerShell corrente.
# Uso:  . .\tools\rust-env.ps1      (con il punto iniziale, così le variabili restano impostate)
# La cartella dei compilatori si può cambiare con la variabile PADDWS_COMPILERS.

$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$env:RUSTUP_HOME = Join-Path $compilers "rust\rustup"
$env:CARGO_HOME = Join-Path $compilers "rust\cargo"
$paths = @((Join-Path $env:CARGO_HOME "bin"), (Join-Path $compilers "mingw64\bin"))
$env:PATH = (($paths + ($env:PATH -split ";")) | Where-Object { $_ } | Select-Object -Unique) -join ";"
Write-Host "Rust: $(rustc --version)"
