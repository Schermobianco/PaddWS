# Verifica la logica del core MiSTer contro le tracce del core Rust: il firmware RISC-V di
# pong_logic_rv (immagine della BRAM in rtl/gen) su un emulatore, paddws-fw-sim.
# Uso:  .\mister\sim\run.ps1            (rigenera le tracce e le prova tutte)
# Richiede la toolchain Rust portable (tools\rust-env.ps1) e Python (.venv o python nel PATH).
# Lo stesso firmware sul VexRiscv vero, ciclo per ciclo con Verilator: sim\rv\rv.ps1.

$ErrorActionPreference = "Continue"   # gli avvisi su stderr non devono fermare lo script
$sim = $PSScriptRoot
$root = (Resolve-Path "$sim\..\..").Path
. "$root\tools\rust-env.ps1" | Out-Null

$traces = @(
    @{ name = "trace";     args = @("--seed", "1") },
    @{ name = "trace_s2";  args = @("--seed", "2") },
    @{ name = "trace_s3";  args = @("--seed", "3") },
    @{ name = "trace_1p";  args = @("--players", "1", "--classic") },
    @{ name = "trace_2pc"; args = @("--classic", "--seed", "7") },
    @{ name = "trace_d0";  args = @("--seed", "5", "--difficulty", "0") },
    @{ name = "trace_d3";  args = @("--seed", "6", "--difficulty", "3") },
    @{ name = "trace_1p3"; args = @("--players", "1", "--classic", "--seed", "4", "--difficulty", "3") },
    @{ name = "trace_next"; args = @("--next", "--seed", "9", "--ticks", "57600") },
    @{ name = "trace_next2"; args = @("--next", "--seed", "13", "--difficulty", "2", "--ticks", "57600") },
    @{ name = "trace_cpu"; args = @("--cpu-play", "--seed", "21", "--ticks", "28800") },
    @{ name = "trace_cpu_c"; args = @("--cpu-play", "--classic", "--seed", "22", "--difficulty", "3", "--ticks", "28800") },
    @{ name = "trace_enc"; args = @("--control", "spinner", "--seed", "31") },
    @{ name = "trace_next_enc"; args = @("--next", "--control", "spinner,joystick", "--seed", "33", "--ticks", "57600") },
    @{ name = "trace_kinds_bg"; args = @("--next", "--paddles", "blaster,guardian", "--seed", "41", "--ticks", "57600") },
    @{ name = "trace_kinds_tt"; args = @("--next", "--paddles", "titan,twist", "--seed", "42", "--ticks", "57600") },
    @{ name = "trace_kinds_hr"; args = @("--next", "--paddles", "hammer,rush", "--seed", "43", "--difficulty", "3", "--ticks", "57600") },
    @{ name = "trace_kinds_ab"; args = @("--next", "--paddles", "arcade,blaster", "--seed", "44", "--difficulty", "2", "--ticks", "57600") },
    @{ name = "trace_kinds_tg"; args = @("--next", "--paddles", "titan,guardian", "--control", "spinner,joystick", "--seed", "45", "--ticks", "57600") },
    @{ name = "trace_ladder"; args = @("--next", "--paddles", "rush,guardian", "--cpu-level", "10", "--difficulty", "2", "--seed", "46", "--ticks", "57600") },
    # mosse speciali (STRAIGHT SHOT e RISING STRIKE, anche delle CPU), con e senza tipi di racchetta
    @{ name = "trace_sup"; args = @("--next", "--supers", "--seed", "51", "--ticks", "57600") },
    @{ name = "trace_sup_d3"; args = @("--next", "--supers", "--seed", "52", "--difficulty", "3", "--ticks", "57600") },
    @{ name = "trace_sup_hr"; args = @("--next", "--supers", "--paddles", "hammer,rush", "--seed", "53", "--difficulty", "2", "--ticks", "57600") },
    @{ name = "trace_sup_rh"; args = @("--next", "--supers", "--paddles", "rush,hammer", "--seed", "54", "--difficulty", "3", "--ticks", "57600") },
    @{ name = "trace_sup_ladder"; args = @("--next", "--supers", "--paddles", "twist,guardian", "--cpu-level", "9", "--difficulty", "2", "--seed", "55", "--ticks", "57600") },
    @{ name = "trace_sup_bt"; args = @("--next", "--supers", "--paddles", "blaster,titan", "--control", "joystick,spinner", "--seed", "56", "--ticks", "57600") },
    # BULLET del giocatore destro contro lo spinner: colpi del BLASTER e manopola rallentati (anche HAMMER, tipo lento)
    @{ name = "trace_bul_bs"; args = @("--next", "--paddles", "blaster,rush", "--control", "spinner,joystick", "--seed", "73", "--ticks", "57600") },
    @{ name = "trace_bul_hb"; args = @("--next", "--paddles", "hammer,blaster", "--control", "spinner,joystick", "--seed", "67", "--ticks", "57600") },
    # BULLET armato che aspetta la palla nel proprio lato del campo, poi scatta e finisce alla ribattuta: a
    # 240 Hz la CPU lo usa solo con la palla gia' vicina (scatta subito), a 128 Hz la sua finestra dura
    # 0,5 s e lo arma con la palla ancora dall'altra parte. CPU con lo spinner; la traccia si ferma prima
    # del tick 4703, dove a 128 Hz la racchetta destra con l'encoder si separa dal core (con il BULLET
    # spento)
    @{ name = "trace_bul_wait"; args = @("--next", "--tick-hz", "128", "--control", "spinner,spinner", "--seed", "63", "--difficulty", "3", "--ticks", "4700") }
)

Push-Location "$root\rust"
foreach ($t in $traces) {
    cargo run -q --release -p paddws-trace -- --out "$sim\$($t.name)" @($t.args) | Out-Null
}
Pop-Location

# firmware RISC-V di pong_logic_rv: file generati allineati ai sorgenti, poi l'immagine della BRAM
# (quella che va nella sintesi) contro tutte le tracce, comandi delle CPU compresi
$py = if (Test-Path "$root\.venv\Scripts\python.exe") { "$root\.venv\Scripts\python.exe" } else { "python" }
& $py "$root\tools\gen_mister_fw.py" --check
if ($LASTEXITCODE -ne 0) { exit 1 }
Push-Location "$root\rust"
$dirs = @($traces | ForEach-Object { "$sim\$($_.name)" })
cargo run -q --release -p paddws-mister-fw --bin paddws-fw-sim -- --fw "$root\mister\rtl\gen" @dirs |
    Where-Object { $_ -match "^(PASS|FAIL|tick|Firmware|\d+ tracce)" }
$fw = $LASTEXITCODE
Pop-Location
if ($fw -ne 0) { Write-Host "Il firmware non coincide con il core Rust"; exit 1 }

Write-Host "Tutte le tracce coincidono con il core Rust"
