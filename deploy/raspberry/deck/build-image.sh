#!/bin/bash
# Costruisce l'immagine della SD del Deck (Raspberry Pi 2 a 32 bit, display da 7") partendo da
# Raspberry Pi OS Lite Trixie armhf e dal pacchetto linux-armv7 di PADD WS.
#
# Uso, su Debian/Ubuntu x86 come root, con qemu-user-static, rsync, parted, dosfstools e xz:
#   build-image.sh LITE.img PADDWS-linux-armv7.tar.gz USCITA.img [MESA.tar [KERNEL.tar]]
# MESA.tar (facoltativo, da mesa/build-mesa.sh) è Mesa senza LLVM: si mette sopra quello dei
# pacchetti e LLVM si toglie (avvio più veloce, immagine più piccola). KERNEL.tar (facoltativo,
# da kernel/build-kernel.sh) è il kernel del Deck: diventa quello di avvio (kernel= in
# config.txt), il kernel di Raspberry Pi OS resta come riserva. Al posto di MESA.tar, "-" per
# non metterlo. Oltre a USCITA.img si scrive USCITA.img.xz, da pubblicare.
#
# L'immagine ha tre partizioni:
#   1 boot  (FAT, 128 MB)  firmware, kernel, config.txt, cmdline.txt, secret/ (wifi.txt, ssh.txt)
#   2 root  (ext4)         il sistema: sempre in sola lettura, con l'overlay in RAM sopra
#   3 data  (ext4, 64 MB)  /data: configurazione e classifica del gioco, chiavi ssh del Deck
# Il resto della SD resta libero.
set -euo pipefail

[ $# -ge 3 ] && [ $# -le 5 ] || { echo "uso: $0 LITE.img PADDWS-linux-armv7.tar.gz USCITA.img [MESA.tar [KERNEL.tar]]" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "va eseguito come root" >&2; exit 1; }
LITE=$(readlink -f "$1"); GAME=$(readlink -f "$2"); OUT=$(readlink -f "$3")
MESA=; [ -n "${4:-}" ] && [ "$4" != - ] && MESA=$(readlink -f "$4")
KERNEL=${5:+$(readlink -f "$5")}
HERE=$(dirname "$(readlink -f "$0")")
DISKID=50414444          # "PADD": le partizioni sono PARTUUID=50414444-0N
BOOT_MB=128
DATA_MB=64

WORK=$(mktemp -d /var/tmp/deck-image.XXXXXX)
R=$WORK/src              # la Lite modificata
N=$WORK/new              # le partizioni dell'immagine finale
LOOP_SRC= LOOP_NEW=
cleanup() {
    set +e
    for m in $R/dev/pts $R/dev $R/proc $R/sys $R/boot/firmware $R $N/data $N/boot $N/root; do
        mountpoint -q "$m" && umount -l "$m"
    done
    [ -n "$LOOP_SRC" ] && losetup -d "$LOOP_SRC"
    [ -n "$LOOP_NEW" ] && losetup -d "$LOOP_NEW"
    rm -rf "$WORK"
}
trap cleanup EXIT
step() { echo; echo "== $*"; }

step "Copia della Lite, con 1 GB in più per i pacchetti"
cp --sparse=always "$LITE" $WORK/lite.img
truncate -s +1G $WORK/lite.img
LOOP_SRC=$(losetup -Pf --show $WORK/lite.img)
parted -s "$LOOP_SRC" resizepart 2 100%
e2fsck -fy "${LOOP_SRC}p2" >/dev/null || [ $? -le 1 ]
resize2fs "${LOOP_SRC}p2" >/dev/null
mkdir -p $R
mount "${LOOP_SRC}p2" $R
mount "${LOOP_SRC}p1" $R/boot/firmware
KVER=$(basename "$(ls -d $R/lib/modules/*-v7)")
echo "kernel $KVER"

step "File del Deck e gioco"
cp -a $R/etc/resolv.conf $WORK/resolv.conf.orig
cp -L /etc/resolv.conf $R/etc/resolv.conf
# permessi fissi (i file possono arrivare da Windows): cartelle 755, file 644; gli eseguibili
# li sistema setup-chroot.sh
(cd "$HERE/rootfs" && find . -type d -exec install -d -m 755 "$R/{}" \; &&
    find . -type f -exec install -m 644 "{}" "$R/{}" \;)
mkdir -p $R/opt/paddws
tar xzf "$GAME" -C $R/opt/paddws --strip-components=1 --no-same-owner
# configurazione del Deck: encoder ottici da 600 impulsi, filtro CRT spento (VideoCore IV)
python3 - "$R/opt/paddws/padd_config.json" "$R/opt/paddws/deck_config.json" <<'EOF'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["encoder"].update(enabled=True, pulses_per_revolution=600, debounce_us=0)
cfg["crt_effects"]["enabled"] = False
cfg["game"]["fullscreen"] = True
with open(sys.argv[2], "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
EOF
[ -n "$MESA" ] && install -m 644 "$MESA" $R/tmp/mesa.tar
install -m 755 "$HERE/setup-chroot.sh" $R/tmp/setup-chroot.sh
# identità dell'immagine: rende vecchio l'elenco della lettura anticipata di un'immagine precedente
date -u +%Y%m%d%H%M%S >$R/etc/paddws-build

step "Configurazione dentro l'immagine (ARM emulato: qualche minuto)"
mount --bind /dev $R/dev
mount --bind /dev/pts $R/dev/pts
mount -t proc proc $R/proc
mount -t sysfs sys $R/sys
chroot $R /tmp/setup-chroot.sh
rm -f $R/tmp/setup-chroot.sh
umount $R/sys $R/proc $R/dev/pts $R/dev
cp -a $WORK/resolv.conf.orig $R/etc/resolv.conf

step "Moduli del kernel decompressi (xz sul Pi 2 costa tempo a ogni avvio)"
find $R/lib/modules/$KVER -name '*.ko.xz' -exec xz -d {} +
depmod -b $R "$KVER"

B=$R/boot/firmware
if [ -n "$KERNEL" ]; then
    step "Kernel del Deck"
    mkdir -p $WORK/kernel
    tar -xf "$KERNEL" -C $WORK/kernel --no-same-owner
    KDECK=$(ls $WORK/kernel/lib/modules)
    cp -a $WORK/kernel/lib/modules/$KDECK $R/lib/modules/
    depmod -b $R "$KDECK"
    grep -q 'dwc2.ko' $R/lib/modules/$KDECK/modules.dep || { echo "modules.dep del kernel del Deck vuoto" >&2; exit 1; }
    cp $WORK/kernel/boot/config-* $R/boot/
    echo "kernel $KDECK"
fi

step "Partizione di boot"
rm -f $B/initramfs* $B/user-data $B/meta-data $B/network-config
rm -f $R/boot/initrd.img-*
# firmware e device tree dei Pi a 64 bit e del Pi 4/5 non servono al Pi 2
rm -f $B/kernel8.img $B/kernel_2712.img $B/start4*.elf $B/fixup4*.dat $B/bcm2711-* $B/bcm2712*
install -m 644 "$HERE/boot/config.txt" "$HERE/boot/cmdline.txt" $B/
if [ -n "$KERNEL" ]; then
    # kernel, device tree e overlay del Deck (gli overlay sono dello stesso ramo del kernel)
    cp $WORK/kernel/boot/kernel7-deck.img $WORK/kernel/boot/*.dtb $B/
    cp $WORK/kernel/boot/overlays/* $B/overlays/
    printf '\n# kernel del Deck (deploy/raspberry/deck/kernel); senza questa riga parte quello di\n# Raspberry Pi OS, kernel7.img\nkernel=kernel7-deck.img\n' >>$B/config.txt
fi
# rete e chiavi ssh, da compilare: in una cartella a parte
install -d $B/secret
install -m 644 "$HERE/boot/secret/wifi.txt" "$HERE/boot/secret/ssh.txt" $B/secret/
# si aprono con il Blocco note: fine riga di Windows
sed -i 's/$/\r/' $B/secret/wifi.txt $B/secret/ssh.txt

step "Immagine finale"
ROOT_KB=$(du -sxk $R | cut -f1)
# margine piccolo: il sistema non si scrive mai (in manutenzione c'è spazio per qualche pacchetto)
ROOT_MB=$(( (ROOT_KB * 105 / 100 / 1024 + 128 + 3) / 4 * 4 ))
TOTAL_MB=$((8 + BOOT_MB + ROOT_MB + DATA_MB))
echo "sistema $((ROOT_KB / 1024)) MB, partizione $ROOT_MB MB, immagine $TOTAL_MB MB"
rm -f "$OUT"
truncate -s ${TOTAL_MB}M "$OUT"
sfdisk -q "$OUT" <<EOF
label: dos
label-id: 0x$DISKID
unit: sectors
start=16384, size=${BOOT_MB}MiB, type=c
size=${ROOT_MB}MiB, type=83
size=${DATA_MB}MiB, type=83
EOF
LOOP_NEW=$(losetup -Pf --show "$OUT")
mkfs.vfat -F 32 -n BOOTFS "${LOOP_NEW}p1" >/dev/null
mkfs.ext4 -q -L rootfs "${LOOP_NEW}p2"
mkfs.ext4 -q -L paddws-data -m 0 "${LOOP_NEW}p3"
mkdir -p $N/boot $N/root $N/data
mount "${LOOP_NEW}p1" $N/boot
mount "${LOOP_NEW}p2" $N/root
mount "${LOOP_NEW}p3" $N/data
cp -r $B/. $N/boot/
rsync -aHAXx --numeric-ids $R/ $N/root/
PI=$(stat -c %u:%g $R/home/pi)
install -m 644 -o "${PI%:*}" -g "${PI#*:}" $R/opt/paddws/deck_config.json $N/data/padd_config.json
chown "$PI" $N/data
sync
umount $N/boot $N/root $N/data
losetup -d "$LOOP_NEW"; LOOP_NEW=
step "Compressione"
xz -T0 -6 -k -f "$OUT"
chown --reference="$(dirname "$OUT")" "$OUT" "$OUT.xz"
echo
echo "pronta: $OUT ($TOTAL_MB MB), $OUT.xz ($(( $(stat -c %s "$OUT.xz") / 1048576 )) MB)"
