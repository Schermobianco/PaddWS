# Registra le scritture nei registri del SID del player Verilog (writes.cpp, Verilator, con un SID
# finto), frame per frame: riferimento del player in 6502 della versione C64 e del player Rust, in
# c64\test\sid_reference.txt (paddws-c64 sid, cargo test -p paddws-sid) e, per la musica dinamica
# (match point, bullet time e le due cose insieme), in rust\sid\tests\writes_fast.txt,
# writes_slow.txt e writes_both.txt (cargo test -p paddws-sid).
# Da rifare quando cambiano le musiche (tools/gen_sid_music.py) o il player.
# Uso:  .\mister\sim\sid\writes.ps1     Richiede la OSS CAD Suite e MinGW, come render.ps1.

$ErrorActionPreference = "Continue"
$PSNativeCommandArgumentPassing = "Legacy"
$dir = $PSScriptRoot
$root = Resolve-Path "$dir\..\..\.."
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$env:VERILATOR_ROOT = "$compilers\oss-cad-suite\share\verilator" -replace '\\', '/'
$env:PATH = "$compilers\oss-cad-suite\bin;$compilers\oss-cad-suite\lib;$compilers\mingw64\bin;" + $env:PATH
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { $env:PATH += ";" + (Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin") }

# Esegue writes.exe con l'argomento e salva le righe in `path`.
function Record([string]$arg, [string]$path) {
    $lines = @(if ($arg) { & .\obj_writes\writes.exe $arg } else { & .\obj_writes\writes.exe })
    if ($LASTEXITCODE -ne 0) { exit 1 }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [System.IO.File]::WriteAllText($path, ($lines -join "`n") + "`n")
    Write-Host "${path}: $($lines.Count) righe"
}

Push-Location $dir
try {
    $log = & verilator_bin --cc --exe -O3 -Wno-fatal -Wno-lint -Wno-style '-GROM_FILE=\"../../rtl/gen/sid_music.hex\"' '-GVOICE_FILE=\"../../rtl/gen/sid_voices.hex\"' `
        '-I../../rtl/gen' --top-module pong_sid --Mdir obj_writes -o writes.exe ../../rtl/pong_sid.v stub_sid.v writes.cpp 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $log; exit 1 }
    $log = & mingw32-make -s -C obj_writes -j8 -f Vpong_sid.mk OPT_FAST=-O2 OPT_SLOW=-O1 OPT_GLOBAL=-O2 2>&1 |
        ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $log | Where-Object { $_ -match "error" }; exit 1 }
    Record "" (Join-Path $root "c64\test\sid_reference.txt")
    foreach ($m in "fast", "slow", "both") {
        Record $m (Join-Path $root "rust\sid\tests\writes_$m.txt")
    }
} finally {
    Pop-Location
}
