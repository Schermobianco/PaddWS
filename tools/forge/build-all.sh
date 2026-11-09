#!/bin/sh
# Dentro l'immagine paddws-build (tools/forge/Dockerfile), con i sorgenti di un commit in /src e i
# pacchetti in /out: gli stessi controlli e gli stessi pacchetti delle GitHub Action, tranne il
# core MiSTer (Quartus ha il suo container: tools/forge/build.sh).
#   NOCHECK=1     senza i controlli
#   CHECKONLY=1   solo i controlli
# Le righe "== ..." sono le fasi: tools/forge/status.sh le mostra mentre il container lavora.
set -e
cd /src
version=$(sed -n 's/^version = "\(.*\)"/\1/p' rust/Cargo.toml | head -1 | tr -d '\r')
step() { echo; echo "== $*"; }
licenses="LICENSE THIRD_PARTY.md assets/fonts/OFL-Munro.txt"

# cartella paddws-$version-$1 in /tmp/pkg con i file indicati dopo
stage() {
    dir=/tmp/pkg/paddws-$version-$1
    rm -rf "$dir" && mkdir -p "$dir"
    shift
    cp -r "$@" "$dir/"
}
zipdir() { (cd /tmp/pkg && zip -qr -X "/out/$1.zip" "$1"); echo "  /out/$1.zip"; }
tardir() { (cd /tmp/pkg && tar czf "/out/$1.tar.gz" "$1"); echo "  /out/$1.tar.gz"; }

# la glibc più recente chiesta dall'eseguibile: al massimo quella di Raspberry Pi OS Bookworm
glibc() {
    need=$($1 -T "$2" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)
    echo "  glibc richiesta: $need"
    [ "$(printf '%s\n' "$need" GLIBC_2.36 | sort -V | tail -1)" = GLIBC_2.36 ]
}

if [ -z "$CHECKONLY" ]; then
    # per primo, prima che i test lascino __pycache__ nei sorgenti: gli stessi file della CI
    step "pacchetto Python"
    # la cartella python/ intera, come nel repository: il pacchetto trova asset e configurazione due
    # cartelle sopra di sé
    stage python python assets deploy padd_config.json README.md README.en.md \
        CHANGELOG.md LICENSE THIRD_PARTY.md
    zipdir "paddws-$version-python"
fi

if [ -z "$NOCHECK" ]; then
    step "controlli Rust: clippy e test"
    cd rust
    cargo clippy --all-targets --release -q -- -D warnings
    cargo clippy --release -q -p paddws --target wasm32-unknown-unknown -- -D warnings
    # Raspberry Pi a 32 bit (Pi 2 v1.1): usize e puntatori a 32 bit
    PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig \
        cargo clippy --release -q -p paddws --target armv7-unknown-linux-gnueabihf -- -D warnings
    cargo test --release -q > /tmp/test.log 2>&1 || { cat /tmp/test.log; exit 1; }
    grep -E "test result" /tmp/test.log | awk '{ p += $4; f += $6 } END { print "  test: " p " passati, " f " falliti" }'
    cd ..

    step "controlli C64: banco di prova contro il core Rust"
    before=$(md5sum c64/gen/params.inc)
    (cd rust && cargo run --release -q -p paddws-c64 -- params --check > /dev/null)
    [ "$(md5sum c64/gen/params.inc)" = "$before" ] || { echo "c64/gen/params.inc non aggiornato"; exit 1; }
    sh c64/build.sh
    for c in math game sid ui frames; do
        (cd rust && cargo run --release -q -p paddws-c64 -- $c) > /tmp/c64.log 2>&1 || { cat /tmp/c64.log; exit 1; }
        echo "  $c: $(tail -1 /tmp/c64.log)"
    done

    step "controlli MiSTer: tracce contro il core Rust"
    bash mister/sim/run.sh > /tmp/traces.log 2>&1 || { tail -30 /tmp/traces.log; exit 1; }
    echo "  $(grep -c '^PASS' /tmp/traces.log) prove del firmware identiche al core Rust"
    # firmware RISC-V ricompilato qui: se i byte non sono quelli in mister/rtl/gen lo si dice e basta
    # (l'impronta dei sorgenti l'ha già controllata run.sh, le tracce l'immagine nel repository)
    cp -r mister/rtl/gen /tmp/fwgen
    python3 tools/gen_mister_fw.py > /dev/null
    if diff -q /tmp/fwgen mister/rtl/gen > /dev/null; then echo "  firmware ricompilato: identico"
    else echo "  attenzione: il firmware ricompilato su Linux ha byte diversi da mister/rtl/gen"; cp /tmp/fwgen/* mister/rtl/gen/; fi

    step "controlli Python: pytest"
    (cd python && python3 -m pytest -q -p no:cacheprovider tests 2>&1 | tail -1)
fi
[ -n "$CHECKONLY" ] && exit 0

step "Windows x86_64 (MinGW)"
(cd rust && cargo build --release -q -p paddws --target x86_64-pc-windows-gnu)
stage windows-x86_64 rust/target/x86_64-pc-windows-gnu/release/paddws.exe padd_config.json $licenses
zipdir "paddws-$version-windows-x86_64"

step "Linux x86_64"
(cd rust && cargo build --release -q -p paddws)
glibc objdump rust/target/release/paddws
stage linux-x86_64 rust/target/release/paddws padd_config.json $licenses
tardir "paddws-$version-linux-x86_64"

step "Linux aarch64 (compilazione incrociata)"
(cd rust && PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig \
    cargo build --release -q -p paddws --target aarch64-unknown-linux-gnu)
glibc aarch64-linux-gnu-objdump rust/target/aarch64-unknown-linux-gnu/release/paddws
stage linux-aarch64 rust/target/aarch64-unknown-linux-gnu/release/paddws padd_config.json $licenses
tardir "paddws-$version-linux-aarch64"

step "Linux armv7 (compilazione incrociata, Raspberry Pi OS a 32 bit)"
(cd rust && PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig \
    cargo build --release -q -p paddws --target armv7-unknown-linux-gnueabihf)
glibc arm-linux-gnueabihf-objdump rust/target/armv7-unknown-linux-gnueabihf/release/paddws
stage linux-armv7 rust/target/armv7-unknown-linux-gnueabihf/release/paddws padd_config.json $licenses
tardir "paddws-$version-linux-armv7"

step "web"
CI=1 pwsh -NoProfile -File tools/build-web.ps1 > /tmp/web.log 2>&1 || { tail -20 /tmp/web.log; exit 1; }
stage web rust/target/web/. $licenses
zipdir "paddws-$version-web"

step "C64"
sh c64/build.sh
stage c64 c64/build/paddws.crt $licenses
zipdir "paddws-$version-c64"
