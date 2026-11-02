#!/bin/sh
# Assembla la versione C64 (come build.ps1) in c64/build: la cartuccia EasyFlash paddws.crt (avvio
# crt.s, programma, caratteri della scelta dei bonus, voci di CHALLENGE) e i pezzi da cui nasce, che
# servono anche al banco di prova: paddws.prg (con paddws.lbl e paddws.map), il finale di CHALLENGE
# paddws.prg.end e i file voce voice0-6.prg. Richiede ca65 e ld65 nel PATH (pacchetto cc65) e python3.
set -e
c64=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$c64")
out="$c64/build"
mkdir -p "$out"

# part SORGENTE BASE ESTENSIONE CONFIGURAZIONE [opzioni di ca65...]
part() {
    src=$1 base=$2 ext=$3 cfg=$4
    shift 4
    ca65 --cpu 6502 -g "$@" -I "$c64/src" -I "$c64/gen" --bin-include-dir "$c64/gen" -o "$out/$base.o" -l "$out/$base.lst" "$c64/src/$src"
    ld65 -C "$c64/$cfg" -o "$out/$base$ext" -Ln "$out/$base.lbl" -m "$out/$base.map" "$out/$base.o"
}

part main.s paddws .prg paddws.cfg
voices=""
for k in 0 1 2 3 4 5 6; do
    part voice.s "voice$k" .prg voice.cfg -D "VOICE_KIND=$k"
    voices="$voices $out/voice$k.prg"
done
part crt.s paddws-crt .bin crt.cfg
# shellcheck disable=SC2086
python3 "$root/tools/make_crt.py" "$out/paddws.crt" "$out/paddws-crt.bin" "$out/paddws.prg" "$c64/gen/pick_bank.bin" "$out/paddws.prg.end" $voices > /dev/null
echo "c64/build/paddws.crt: cartuccia EasyFlash"
