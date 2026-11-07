#!/bin/bash
# Compila Mesa senza LLVM, con il solo driver vc4 (Raspberry Pi 0-3), dentro una copia di
# Raspberry Pi OS Lite (chroot ARM con qemu) e dai sorgenti Raspberry della stessa versione
# installata nell'immagine. Il Mesa di Raspberry Pi OS si porta dietro LLVM (117 MB, solo per il
# rendering software): all'avvio del Deck se ne leggono decine di MB dalla SD, tre volte.
#
# Uso, come root su Linux x86 con qemu-user-static:
#   build-mesa.sh LITE.img USCITA.tar
# USCITA.tar contiene le librerie da mettere sopra quelle dei pacchetti (usr/lib/...).
set -euo pipefail
[ $# -eq 2 ] || { echo "uso: $0 LITE.img USCITA.tar" >&2; exit 2; }
LITE=$(readlink -f "$1"); OUT=$(readlink -f "$2")
WORK=/var/tmp/deck-mesa
R=$WORK/root
LOOP=

cleanup() {
    set +e
    for m in $R/dev/pts $R/dev $R/proc $R/sys $R; do mountpoint -q "$m" && umount -l "$m"; done
    [ -n "$LOOP" ] && losetup -d "$LOOP"
}
trap cleanup EXIT

mkdir -p $WORK
if [ ! -f $WORK/build.img ]; then
    cp --sparse=always "$LITE" $WORK/build.img
    truncate -s +6G $WORK/build.img
    LOOP=$(losetup -Pf --show $WORK/build.img)
    parted -s "$LOOP" resizepart 2 100%
    e2fsck -fy "${LOOP}p2" >/dev/null || [ $? -le 1 ]
    resize2fs "${LOOP}p2" >/dev/null
else
    LOOP=$(losetup -Pf --show $WORK/build.img)
fi
mkdir -p $R
mount "${LOOP}p2" $R
mount --bind /dev $R/dev; mount --bind /dev/pts $R/dev/pts
mount -t proc proc $R/proc; mount -t sysfs sys $R/sys
cp -L /etc/resolv.conf $R/etc/resolv.conf
install -m 755 "$(dirname "$(readlink -f "$0")")/inside.sh" $R/root/inside.sh
chroot $R /root/inside.sh
tar -C $R/root/mesa-out -cf "$OUT" .
echo "pronto: $OUT"
