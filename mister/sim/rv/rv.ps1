# Verifica pong_logic_rv (VexRiscv + firmware rust/mister-fw) con Verilator contro le tracce di
# mister/sim (tb_rv_top.v, tb_rv.cpp), ciclo per ciclo come nel core, con i tempi di ogni tick.
# Uso:  .\mister\sim\rv\rv.ps1 [-Ticks N] [-Ratio 3|2] [-Traces traccia,...]
#   senza tracce le prova tutte (prima va eseguito mister\sim\run.ps1, che le genera);
#   -Ticks N  solo i primi N tick di ogni traccia;
#   -Ratio    clock del processore in multipli dei 20 MHz: 3 (60 MHz, il core) o 2 (40 MHz, il ripiego).
# Due modelli: obj240 (240 Hz) e obj128 per trace_bul_wait (128 Hz). Verilator riscrive solo i file che cambiano: la compilazione si rifà solo se cambia l'RTL.
# Le tracce girano 6 alla volta; i risultati sono in mister\sim\rv\out\<traccia>.txt.
# Richiede la OSS CAD Suite e MinGW in C:\DEV\@Compiler (oppure in $env:PADDWS_COMPILERS).
param([int]$Ticks = -1, [int]$Ratio = 3, [string[]]$Traces = @())

$ErrorActionPreference = "Continue"
$PSNativeCommandArgumentPassing = "Legacy"
$dir = $PSScriptRoot
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$env:VERILATOR_ROOT = "$compilers\oss-cad-suite\share\verilator" -replace '\\', '/'
$env:PATH = "$compilers\oss-cad-suite\bin;$compilers\oss-cad-suite\lib;$compilers\mingw64\bin;" + $env:PATH
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { $env:PATH += ";" + (Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin") }

function Build([int]$hz) {
    $out = & verilator_bin --cc --exe --public-ignore -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style `
        "-GTICK_HZ=$hz" "-I../../rtl/gen" --top-module tb_rv_top --Mdir "obj$hz" -o tb_rv.exe `
        tb_rv_top.v ../../rtl/pong_logic_rv.v ../../rtl/vexriscv/VexRiscv.v `
        tb_rv.cpp 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $out; return $false }
    $out = & mingw32-make -s -C "obj$hz" -j8 -f Vtb_rv_top.mk OPT_FAST=-O2 OPT_SLOW=-O1 OPT_GLOBAL=-O2 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $out | Where-Object { $_ -match "error" }; return $false }
    return $true
}

Push-Location $dir
try {
    if (-not (Build 240)) { exit 1 }
    if (-not (Build 128)) { exit 1 }
    $names = if ($Traces.Count) { $Traces } else { Get-ChildItem .. -Directory -Filter "trace*" | ForEach-Object { $_.Name } }
    New-Item -ItemType Directory -Force out | Out-Null
    # in esecuzione le DLL di MinGW (quelle con cui è compilato il modello) prima di quelle della OSS CAD Suite
    $env:PATH = "$compilers\mingw64\bin;" + $env:PATH
    $opts = @("--ratio", "$Ratio")
    if ($Ticks -ge 0) { $opts += @("--ticks", "$Ticks") }
    $jobs = @()
    foreach ($n in $names) {
        $exe = if ($n -eq "trace_bul_wait") { ".\obj128\tb_rv.exe" } else { ".\obj240\tb_rv.exe" }
        while (@($jobs | Where-Object { -not $_.HasExited }).Count -ge 6) { Start-Sleep -Milliseconds 500 }
        $jobs += Start-Process -FilePath $exe -ArgumentList (@($opts) + "..\$n") -NoNewWindow -PassThru `
            -RedirectStandardOutput "out\$n.txt" -RedirectStandardError "out\$n.err"
    }
    $jobs | Wait-Process
    $failed = 0
    foreach ($n in $names) {
        $lines = Get-Content "out\$n.txt"
        $lines | Where-Object { $_ -match "^(PASS|FAIL|  frame)" }
        if (-not ($lines | Where-Object { $_ -match "^PASS" })) { $failed++ }
    }
    if ($failed) { Write-Host "$failed tracce non coincidono"; exit 1 }
    Write-Host "pong_logic_rv identico al core Rust su tutte le tracce"
} finally {
    Pop-Location
}
