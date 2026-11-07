#!/bin/bash
# Parte di build-mesa.sh che gira dentro il chroot ARM.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d

# sorgenti della stessa versione di Mesa dei pacchetti binari
sed -i 's/^#\s*deb-src/deb-src/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
for f in /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] && sed -i 's/^Types: deb$/Types: deb deb-src/' "$f"
done
apt-get update -q
VER=$(apt-cache policy libgl1-mesa-dri | awk '/Candidate/{print $2}')
echo "Mesa $VER"
apt-get install -y -q --no-install-recommends build-essential meson ninja-build pkg-config \
    python3-mako python3-yaml python3-packaging python3-ply bison flex dpkg-dev \
    libdrm-dev libexpat1-dev zlib1g-dev libzstd-dev libudev-dev libelf-dev \
    libwayland-dev wayland-protocols libwayland-egl-backend-dev \
    libx11-dev libxext-dev libxfixes-dev libx11-xcb-dev libxcb-glx0-dev libxcb-shm0-dev \
    libxcb-dri2-0-dev libxcb-dri3-dev libxcb-present-dev libxcb-sync-dev libxcb-randr0-dev \
    libxshmfence-dev libxxf86vm-dev libxrandr-dev libglvnd-dev

mkdir -p /root/src && cd /root/src
[ -d mesa-* ] 2>/dev/null || apt-get source -q "mesa=$VER"
cd "$(ls -d /root/src/mesa-*/ | head -1)"

rm -rf build
meson setup build --prefix=/usr --libdir=lib/arm-linux-gnueabihf --buildtype=release -Db_ndebug=true \
    -Dllvm=disabled -Dgallium-drivers=vc4 -Dvulkan-drivers= -Dplatforms=x11,wayland \
    -Dglvnd=enabled -Dglx=dri -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled \
    -Dgallium-va=disabled \
    -Dgallium-rusticl=false -Dvideo-codecs= -Dlmsensors=disabled -Dvalgrind=disabled \
    -Dlibunwind=disabled -Dtools= -Dbuild-tests=false \
    -Dc_args='-mcpu=cortex-a7 -mfpu=neon-vfpv4' -Dcpp_args='-mcpu=cortex-a7 -mfpu=neon-vfpv4'
ninja -C build -j"$(nproc)"
rm -rf /root/mesa-out
DESTDIR=/root/mesa-out ninja -C build install
find /root/mesa-out -name '*.so*' -type f -exec strip --strip-unneeded {} +
find /root/mesa-out -type f -o -type l | sort
du -sh /root/mesa-out
