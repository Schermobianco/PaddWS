#!/bin/sh
# Assembla la versione C64 (come build.ps1) in c64/build: la cartuccia EasyFlash paddws.crt (avvio
# crt.s, programma, caratteri della scelta dei bonus, voci di CHALLENGE) e i pezzi da cui nasce, che
# servono anche al banco di prova: paddws.prg (con paddws.lbl e paddws.map), il finale di CHALLENGE
# paddws.prg.end, il banco di OMEGA paddws.prg.omega e i file voce voice0-7.prg (il 7 è OMEGA).
# Con --ntsc la versione NTSC (60 frame e tick al secondo) in c64/build/ntsc: i parametri da
# c64/gen/ntsc/params.inc e il simbolo NTSC per il resto. Con --rotated la versione con il campo
# girato, una cartuccia a sé, in c64/build/rotated (con anche --ntsc in c64/build/rotated/ntsc): i
# file di c64/gen/rotated prima degli altri e il simbolo ROTATED. Il nome dentro il .crt dice quale
# delle quattro è: PADD WS HORIZONTAL PAL, HORIZONTAL NTSC, VERTICAL PAL (il campo girato), VERTICAL
# NTSC.
# Richiede ca65 e ld65 nel PATH (pacchetto cc65) e python3.
set -e
c64=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$c64")
sub=""
tv=""
pads=""
field="HORIZONTAL"
system="PAL"
for arg in "$@"; do
    case "$arg" in
        --rotated) rotated=1 ;;
        --ntsc) ntsc=1 ;;
    esac
done
if [ -n "$rotated" ]; then
    sub="/rotated"
    field="VERTICAL"
    [ -n "$ntsc" ] && tv="-I $c64/gen/rotated/ntsc"
    tv="$tv -D ROTATED -I $c64/gen/rotated --bin-include-dir $c64/gen/rotated"
    pads="--pads $c64/gen/rotated/paddles.bin"
fi
if [ -n "$ntsc" ]; then
    sub="$sub/ntsc"
    system="NTSC"
    tv="$tv -D NTSC -I $c64/gen/ntsc"
fi
out="$c64/build$sub"
where="c64/build$sub"
mkdir -p "$out"

# part SORGENTE BASE ESTENSIONE CONFIGURAZIONE [opzioni di ca65...]
part() {
    src=$1 base=$2 ext=$3 cfg=$4
    shift 4
    # shellcheck disable=SC2086
    ca65 --cpu 6502 -g "$@" $tv -I "$c64/src" -I "$c64/gen" --bin-include-dir "$c64/gen" -o "$out/$base.o" -l "$out/$base.lst" "$c64/src/$src"
    ld65 -C "$c64/$cfg" -o "$out/$base$ext" -Ln "$out/$base.lbl" -m "$out/$base.map" "$out/$base.o"
}

part main.s paddws .prg paddws.cfg
voices=""
for k in 0 1 2 3 4 5 6 7; do
    part voice.s "voice$k" .prg voice.cfg -D "VOICE_KIND=$k"
    voices="$voices $out/voice$k.prg"
done
part crt.s paddws-crt .bin crt.cfg
# shellcheck disable=SC2086
python3 "$root/tools/make_crt.py" $pads --name "PADD WS $field $system" "$out/paddws.crt" "$out/paddws-crt.bin" "$out/paddws.prg" "$c64/gen/pick_bank.bin" "$out/paddws.prg.end" "$out/paddws.prg.omega" $voices > /dev/null
echo "$where/paddws.crt: cartuccia EasyFlash"
