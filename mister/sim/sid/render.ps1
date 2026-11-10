# Registra in WAV le canzoni e gli effetti del SID dal player Verilog (Verilator).
# Uso:  .\mister\sim\sid\render.ps1 CARTELLA [8580|6581] [-Voice]
# Filtro 8580 se non si dice altro. Sono i riferimenti per il SID Rust del gioco (rust/sid), che
# suona musica, effetti e voci in tempo reale: paddws-sid compare CANZONE CARTELLA\canzone.wav,
# fx:EFFETTO CARTELLA\effetto.wav, voice:NOME CARTELLA\intro_voice_nome.wav.
# Richiede la OSS CAD Suite e MinGW in C:\DEV\@Compiler (oppure in $env:PADDWS_COMPILERS), come
# frames.ps1.
# Con -Voice registra solo le prove della voce della CHALLENGE e degli effetti del bullet time (vedi
# render.cpp).

param([Parameter(Mandatory)][string]$Out, [string]$Model = "8580", [switch]$Voice)
$ErrorActionPreference = "Continue"
$PSNativeCommandArgumentPassing = "Legacy"
$dir = $PSScriptRoot
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path      # render.exe parte dalla cartella dello script
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$env:VERILATOR_ROOT = "$compilers\oss-cad-suite\share\verilator" -replace '\\', '/'
$env:PATH = "$compilers\oss-cad-suite\bin;$compilers\oss-cad-suite\lib;$compilers\mingw64\bin;" + $env:PATH
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { $env:PATH += ";" + (Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin") }

Push-Location $dir
try {
    $rtl = @("../../rtl/pong_sid.v") + (Get-ChildItem ..\..\rtl\sid\*.sv | ForEach-Object { "../../rtl/sid/$($_.Name)" })
    $log = & verilator_bin --cc --exe -O3 --x-assign fast --x-initial fast `
        -Wno-fatal -Wno-lint -Wno-style -Wno-SELRANGE '-GROM_FILE=\"../../rtl/gen/sid_music.hex\"' `
        '-GVOICE_FILE=\"../../rtl/gen/sid_voices.hex\"' `
        '-I../../rtl/gen' --top-module pong_sid --Mdir obj -o render.exe $rtl render.cpp 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $log; exit 1 }
    $log = & mingw32-make -s -C obj -j8 -f Vpong_sid.mk OPT_FAST=-O2 OPT_SLOW=-O1 OPT_GLOBAL=-O2 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $log | Where-Object { $_ -match "error" }; exit 1 }
    & .\obj\render.exe $Out $Model @(if ($Voice) { "voice" })
    if ($LASTEXITCODE -ne 0) { exit 1 }
    exit 0
} finally {
    Pop-Location
}
