#!/bin/bash
# Kernel del Deck: quello di Raspberry Pi (ramo rpi-6.18.y) con la configurazione di Raspberry Pi
# OS a 32 bit (presa dalla Lite) più le modifiche di deck.config: niente tracing e i driver di
# display e audio nel kernel. Si compila su Linux x86 con il compilatore incrociato armhf.
#
# Uso (le dipendenze: crossbuild-essential-armhf bc bison flex libssl-dev kmod git):
#   build-kernel.sh LITE.img USCITA.tar
# USCITA.tar contiene boot/ (kernel7-deck.img, dtb, overlays) e lib/modules/<versione>.
set -euo pipefail
[ $# -eq 2 ] || { echo "uso: $0 LITE.img USCITA.tar" >&2; exit 2; }
LITE=$(readlink -f "$1"); OUT=$(readlink -f "$2")
HERE=$(dirname "$(readlink -f "$0")")
WORK=${WORK:-/var/tmp/deck-kernel}
BRANCH=rpi-6.18.y
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

mkdir -p "$WORK"
cd "$WORK"
[ -d linux ] || git clone -q --depth 1 --branch $BRANCH https://github.com/raspberrypi/linux.git
cd linux

# configurazione di partenza: quella del kernel v7 della Lite
if [ ! -f "$WORK/base.config" ]; then
    L=$(sudo losetup -Pf --show "$LITE")
    mkdir -p "$WORK/mnt"
    sudo mount -o ro "${L}p2" "$WORK/mnt"
    cp "$(ls "$WORK"/mnt/boot/config-*-rpi-v7 | head -1)" "$WORK/base.config"
    sudo umount "$WORK/mnt"; sudo losetup -d "$L"
fi
cp "$WORK/base.config" .config
scripts/kconfig/merge_config.sh -m .config "$HERE/deck.config" >/dev/null
make -s olddefconfig
for c in DRM_VC4 DRM_TOSHIBA_TC358762 DRM_PANEL_SIMPLE REGULATOR_FIXED_VOLTAGE \
         REGULATOR_RASPBERRYPI_TOUCHSCREEN_ATTINY I2C_BCM2835 I2C_MUX_PINCTRL SND_BCM2835 OVERLAY_FS; do
    grep -q "^CONFIG_$c=y" .config || { echo "CONFIG_$c non è nel kernel: $(grep "CONFIG_$c[= ]" .config)" >&2; exit 1; }
done
grep -q '^CONFIG_FTRACE=y' .config && { echo "il tracing è ancora attivo" >&2; exit 1; }
grep -q '^CONFIG_MODULE_COMPRESS=y' .config && { echo "i moduli sarebbero compressi" >&2; exit 1; }

make -s -j"$(nproc)" zImage modules dtbs
VER=$(make -s kernelrelease)
echo "kernel $VER"

rm -rf "$WORK/out" && mkdir -p "$WORK/out/boot/overlays"
make -s INSTALL_MOD_PATH="$WORK/out" INSTALL_MOD_STRIP=1 modules_install
rm -f "$WORK/out/lib/modules/$VER/build" "$WORK/out/lib/modules/$VER/source"
M="$WORK/out/lib/modules/$VER"
[ -z "$(find "$M" -name '*.ko.*')" ] || { echo "ci sono moduli compressi" >&2; exit 1; }
[ -s "$M/modules.dep" ] && grep -q 'dwc2.ko' "$M/modules.dep" || { echo "modules.dep vuoto o senza dwc2" >&2; exit 1; }
echo "moduli: $(wc -l <"$M/modules.dep")"
cp arch/arm/boot/zImage "$WORK/out/boot/kernel7-deck.img"
cp arch/arm/boot/dts/broadcom/bcm2709-rpi-2-b.dtb arch/arm/boot/dts/broadcom/bcm2710-rpi-2-b.dtb "$WORK/out/boot/"
cp arch/arm/boot/dts/overlays/*.dtbo "$WORK/out/boot/overlays/"
cp arch/arm/boot/dts/overlays/README "$WORK/out/boot/overlays/" 2>/dev/null || true
cp .config "$WORK/out/boot/config-$VER"
tar -C "$WORK/out" -cf "$OUT" .
ls -la "$WORK/out/boot/kernel7-deck.img"
echo "pronto: $OUT"
