#!/bin/sh
# deck-cache.sh - prepara su forge ~/forge/deck-cache, che serve a build.sh per l'immagine della SD del
# Deck (deploy/raspberry/deck):
#   lite.img    Raspberry Pi OS Lite Trixie armhf, decompressa (circa 600 MB da scaricare);
#   kernel.tar  il kernel del Deck, compilato incrociato (kernel/build-kernel.sh, una ventina di minuti);
#   mesa.tar    Mesa senza LLVM, compilato in un ARM emulato (mesa/build-mesa.sh, più di un'ora).
# Installa prima i pacchetti che servono a questi script e a build-image.sh. Quello che c'è già non si
# rifà: se si interrompe, si rilancia. Per rifare un pezzo basta cancellarne il file.
#
#   sh ~/forge/src/tools/forge/deck-cache.sh      (come l'utente di forge, con sudo senza password)
set -e
src=$(cd "$(dirname "$0")/../.." && pwd)
deck=$src/deploy/raspberry/deck
cache=$HOME/forge/deck-cache
# la Lite su cui è provata l'immagine del Deck: cambiarla qui e in deploy/raspberry/deck/README.md
lite=https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2026-10-06/2026-10-06-raspios-trixie-armhf-lite.img.xz
[ -f "$deck/build-image.sh" ] || { echo "errore: manca $deck (sorgenti in ~/forge/src?)" >&2; exit 1; }
mkdir -p "$cache"
step() { printf '\n== %s\n' "$*"; }

step "pacchetti"
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update -qq
sudo -E apt-get install -y -qq qemu-user-static rsync parted dosfstools xz-utils curl git make bc bison \
    flex libssl-dev libelf-dev kmod cpio dwarves crossbuild-essential-armhf >/dev/null
echo "ok"

if [ -f "$cache/lite.img" ]; then
    step "Raspberry Pi OS Lite: c'è già"
else
    step "Raspberry Pi OS Lite"
    curl -fL --progress-bar -o "$cache/lite.img.xz" "$lite"
    want=$(curl -fsL "$lite.sha256" | cut -d' ' -f1)
    have=$(sha256sum "$cache/lite.img.xz" | cut -d' ' -f1)
    [ -n "$want" ] && [ "$want" = "$have" ] || { rm -f "$cache/lite.img.xz"; echo "errore: SHA-256 diverso" >&2; exit 1; }
    # lite.img solo a file completo: build.sh guarda se c'è
    xz -dcT0 "$cache/lite.img.xz" >"$cache/lite.img.tmp"
    mv "$cache/lite.img.tmp" "$cache/lite.img"
    rm "$cache/lite.img.xz"
fi

if [ -f "$cache/kernel.tar" ]; then
    step "kernel del Deck: c'è già"
else
    step "kernel del Deck (una ventina di minuti)"
    bash "$deck/kernel/build-kernel.sh" "$cache/lite.img" "$cache/kernel.tar.tmp"
    mv "$cache/kernel.tar.tmp" "$cache/kernel.tar"
fi

if [ -f "$cache/mesa.tar" ]; then
    step "Mesa senza LLVM: c'è già"
else
    step "Mesa senza LLVM (più di un'ora)"
    sudo bash "$deck/mesa/build-mesa.sh" "$cache/lite.img" "$cache/mesa.tar.tmp"
    sudo chown "$(id -u):$(id -g)" "$cache/mesa.tar.tmp"
    mv "$cache/mesa.tar.tmp" "$cache/mesa.tar"
fi

step "pronta: $cache"
ls -l "$cache" | tail -n +2 | awk '{ printf "  %-12s %12d\n", $NF, $5 }'
echo "Dalla prossima build_onforge.bat la release comprende l'immagine della SD del Deck."
