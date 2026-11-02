#!/usr/bin/env bash
# Verifica la logica del core MiSTer contro le tracce del core Rust (versione Linux di run.ps1,
# usata dalla CI e da forge): il firmware RISC-V di pong_logic_rv su un emulatore (paddws-fw-sim).
# Richiede cargo e python3 nel PATH.
set -euo pipefail

sim="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$sim/../.." && pwd)"

traces=(
    "trace:--seed 1"
    "trace_s2:--seed 2"
    "trace_s3:--seed 3"
    "trace_1p:--players 1 --classic"
    "trace_2pc:--classic --seed 7"
    "trace_d0:--seed 5 --difficulty 0"
    "trace_d3:--seed 6 --difficulty 3"
    "trace_1p3:--players 1 --classic --seed 4 --difficulty 3"
    "trace_next:--next --seed 9 --ticks 57600"
    "trace_next2:--next --seed 13 --difficulty 2 --ticks 57600"
    "trace_cpu:--cpu-play --seed 21 --ticks 28800"
    "trace_cpu_c:--cpu-play --classic --seed 22 --difficulty 3 --ticks 28800"
    "trace_enc:--control spinner --seed 31"
    "trace_next_enc:--next --control spinner,joystick --seed 33 --ticks 57600"
    "trace_kinds_bg:--next --paddles blaster,guardian --seed 41 --ticks 57600"
    "trace_kinds_tt:--next --paddles titan,twist --seed 42 --ticks 57600"
    "trace_kinds_hr:--next --paddles hammer,rush --seed 43 --difficulty 3 --ticks 57600"
    "trace_kinds_ab:--next --paddles arcade,blaster --seed 44 --difficulty 2 --ticks 57600"
    "trace_kinds_tg:--next --paddles titan,guardian --control spinner,joystick --seed 45 --ticks 57600"
    "trace_ladder:--next --paddles rush,guardian --cpu-level 10 --difficulty 2 --seed 46 --ticks 57600"
    # mosse speciali (STRAIGHT SHOT e RISING STRIKE, anche delle CPU), con e senza tipi di racchetta
    "trace_sup:--next --supers --seed 51 --ticks 57600"
    "trace_sup_d3:--next --supers --seed 52 --difficulty 3 --ticks 57600"
    "trace_sup_hr:--next --supers --paddles hammer,rush --seed 53 --difficulty 2 --ticks 57600"
    "trace_sup_rh:--next --supers --paddles rush,hammer --seed 54 --difficulty 3 --ticks 57600"
    "trace_sup_ladder:--next --supers --paddles twist,guardian --cpu-level 9 --difficulty 2 --seed 55 --ticks 57600"
    "trace_sup_bt:--next --supers --paddles blaster,titan --control joystick,spinner --seed 56 --ticks 57600"
    "trace_bul_bs:--next --paddles blaster,rush --control spinner,joystick --seed 73 --ticks 57600"
    "trace_bul_hb:--next --paddles hammer,blaster --control spinner,joystick --seed 67 --ticks 57600"
    # BULLET armato in attesa della palla, poi scatto e ribattuta (128 Hz: vedi run.ps1)
    "trace_bul_wait:--next --tick-hz 128 --control spinner,spinner --seed 63 --difficulty 3 --ticks 4700"
)

failed=0
for t in "${traces[@]}"; do
    name="${t%%:*}"
    args="${t#*:}"
    # shellcheck disable=SC2086
    (cd "$root/rust" && cargo run -q --release -p paddws-trace -- --out "$sim/$name" $args > /dev/null)
done

# firmware RISC-V di pong_logic_rv: file generati allineati ai sorgenti, poi l'immagine della BRAM
# (quella che va nella sintesi) contro tutte le tracce, comandi delle CPU compresi
python3 "$root/tools/gen_mister_fw.py" --check || failed=$((failed + 1))
dirs=()
for t in "${traces[@]}"; do dirs+=("$sim/${t%%:*}"); done
fwok=1
fwlog="$(cd "$root/rust" && cargo run -q --release -p paddws-mister-fw --bin paddws-fw-sim -- --fw "$root/mister/rtl/gen" "${dirs[@]}" 2>&1)" || fwok=0
grep -E '^(PASS|FAIL|tick|Firmware|[0-9]+ tracce)' <<< "$fwlog" || true
[ "$fwok" -eq 1 ] || failed=$((failed + 1))

if [ "$failed" -ne 0 ]; then
    echo "$failed tracce non coincidono"
    exit 1
fi
echo "Tutte le tracce coincidono con il core Rust"
