# Compila, se serve, ed esegue il simulatore dei frame del core completo (Verilator).
# Uso:  .\mister\sim\frames\frames.ps1 [scenario] [frame o intervalli ...] [-f]
#   .\mister\sim\frames\frames.ps1 next 1300 1400-1420
# Gli argomenti passano a frames.exe (vedi frames.cpp); le immagini PPM e i checkpoint restano
# in mister\sim\frames. Verilator riscrive solo i file C++ che cambiano, quindi make ricompila
# il modello solo quando cambia l'RTL (circa 15 s).
# Richiede la OSS CAD Suite e MinGW in C:\DEV\@Compiler (oppure in $env:PADDWS_COMPILERS).

$ErrorActionPreference = "Continue"   # gli avvisi su stderr non devono fermare lo script
$PSNativeCommandArgumentPassing = "Legacy"   # PowerShell 7: stesse virgolette di Windows PowerShell
$dir = $PSScriptRoot
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
# con le barre normali: make passa i percorsi a sh, che toglierebbe le barre rovesciate
$env:VERILATOR_ROOT = "$compilers\oss-cad-suite\share\verilator" -replace '\\', '/'
$env:PATH = "$compilers\oss-cad-suite\bin;$compilers\oss-cad-suite\lib;$compilers\mingw64\bin;" + $env:PATH
# verilated.mk usa sh, uname e xargs: si prendono quelli di Git per Windows
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { $env:PATH += ";" + (Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin") }

Push-Location $dir
try {
    $rtl = Get-ChildItem ..\..\rtl\*.v | ForEach-Object { "../../rtl/$($_.Name)" }
    $rtl += Get-ChildItem ..\..\rtl\sid\*.sv | ForEach-Object { "../../rtl/sid/$($_.Name)" }
    $rtl += "../../rtl/vexriscv/VexRiscv.v"
    $out = & verilator_bin --cc --exe --savable --public-ignore -O3 --x-assign fast --x-initial fast `
        -Wno-fatal -Wno-lint -Wno-style -Wno-SELRANGE '-GSID_ROM=\"../../rtl/gen/sid_music.hex\"' `
        '-GVOICE_ROM=\"../../rtl/gen/sid_voices.hex\"' `
        '-GHOWTO_TEXT_ROM=\"../../rtl/gen/howto_text.hex\"' '-GHOWTO_ROWS_ROM=\"../../rtl/gen/howto_rows.hex\"' `
        '-GHOWTO_SPRITE_ROM=\"../../rtl/gen/howto_sprites.hex\"' `
        '-GENDING_TEXT_ROM=\"../../rtl/gen/ending_text.hex\"' '-GENDING_MAP_ROM=\"../../rtl/gen/ending_map.hex\"' `
        '-GENDING_FW_ROM=\"../../rtl/gen/ending_fw.hex\"' `
        '-GFW_ROM0=\"../../rtl/gen/pong_fw_b0.hex\"' '-GFW_ROM1=\"../../rtl/gen/pong_fw_b1.hex\"' `
        '-GFW_ROM2=\"../../rtl/gen/pong_fw_b2.hex\"' '-GFW_ROM3=\"../../rtl/gen/pong_fw_b3.hex\"' `
        '-I../../rtl/gen' --top-module pong_top --Mdir obj -o frames.exe public.vlt $rtl frames.cpp 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $out; exit 1 }
    $out = & mingw32-make -s -C obj -j8 -f Vpong_top.mk OPT_FAST=-O2 OPT_SLOW=-O1 OPT_GLOBAL=-O2 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $out | Where-Object { $_ -match "error" }; exit 1 }
    & .\obj\frames.exe @args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
