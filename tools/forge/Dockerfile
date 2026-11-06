# Immagine paddws-build della macchina forge: tutti i tool delle GitHub Action in un container
# Ubuntu 22.04 (come i runner Linux della CI: eseguibili con glibc al massimo 2.36).
#   Rust (versione fissa) con i target Linux x86_64, Linux aarch64 e armv7 (compilazione incrociata),
#   Windows x86_64 (MinGW), web (wasm32) e RISC-V (riscv32im, firmware del core MiSTer); PowerShell per tools/build-web.ps1 come nella CI;
#   cc65 per il C64; Python con le dipendenze della versione
#   Python (requirements.txt, copiato nel contesto da build.sh) e pytest.
# La costruisce tools/forge/build.sh quando manca o quando cambia questo file.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# pacchetti arm64 e armhf dal mirror "ports" per collegare gli eseguibili aarch64 e armv7
# (armv7: Raspberry Pi OS a 32 bit, per i Raspberry Pi 2 v1.1)
RUN sed -i 's|^deb http|deb [arch=amd64] http|' /etc/apt/sources.list \
 && printf '%s\n' \
    'deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports jammy main universe' \
    'deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports jammy-updates main universe' \
    'deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports jammy-security main universe' \
    > /etc/apt/sources.list.d/arm64.list \
 && dpkg --add-architecture arm64 && dpkg --add-architecture armhf \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential pkg-config curl ca-certificates git zip unzip file \
    libx11-dev libxi-dev libgl1-mesa-dev libasound2-dev libudev-dev \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu libc6-dev-arm64-cross \
    libx11-dev:arm64 libxi-dev:arm64 libgl1-mesa-dev:arm64 libasound2-dev:arm64 libudev-dev:arm64 \
    gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf libc6-dev-armhf-cross \
    libx11-dev:armhf libxi-dev:armhf libgl1-mesa-dev:armhf libasound2-dev:armhf libudev-dev:armhf \
    gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 \
    cc65 \
    python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

# PowerShell, per lo stesso tools/build-web.ps1 della CI
RUN curl -sSLo /tmp/ms.deb https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb \
 && dpkg -i /tmp/ms.deb && rm /tmp/ms.deb \
 && apt-get update && apt-get install -y --no-install-recommends powershell \
 && rm -rf /var/lib/apt/lists/*

# Rust: la stessa versione della toolchain portable del PC (tools/rust-env.ps1)
ARG RUST=1.99.1
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal --default-toolchain $RUST -c clippy \
    -t aarch64-unknown-linux-gnu -t armv7-unknown-linux-gnueabihf -t wasm32-unknown-unknown -t x86_64-pc-windows-gnu \
    -t riscv32im-unknown-none-elf
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc

# Python: le versioni verificate della versione Python e pytest
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt pytest && rm /tmp/requirements.txt

WORKDIR /src
