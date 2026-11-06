#!/bin/sh
# Release sulla macchina forge, dai sorgenti di un commit in ~/forge/src (li manda build.bat):
#   1. immagine paddws-build (tools/forge/Dockerfile), ricostruita solo quando cambia;
#   2. controlli e pacchetti nel container forge-build (tools/forge/build-all.sh);
#   3. core MiSTer: sintesi con Quartus (mister/synth.sh, container quartus-synth) e zip della SD.
# I pacchetti vanno in ~/forge/out, con BUILD.txt (versione, commit, esito) per lo stato della console.
#
#   sh build.sh [--no-check] [--check-only] [--no-mister] [--synth]
# --synth: con --check-only anche la sintesi del core MiSTer, senza pacchetti (forge-check.bat -Synth).
set -e
src=$(cd "$(dirname "$0")/../.." && pwd)
out=$HOME/forge/out
nocheck= checkonly= nomister= synth=
for a in "$@"; do
    case "$a" in
        --no-check) nocheck=1 ;;
        --check-only) checkonly=1 ;;
        --no-mister) nomister=1 ;;
        --synth) synth=1 ;;
        *) echo "opzione sconosciuta: $a" >&2; exit 2 ;;
    esac
done
version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$src/rust/Cargo.toml" | head -1 | tr -d '\r')
started=$(date +%s)
rm -rf "$out" && mkdir -p "$out"
result() { printf 'versione=%s\n%s\nesito=%s\ninizio=%s\nfine=%s\n' "$version" "$(cat "$src/.source" 2>/dev/null)" "$1" \
    "$started" "$(date +%s)" > "$out/BUILD.txt"; }
# i container lavorano come root: sorgenti e pacchetti tornano all'utente (non il volume di target)
fixown() {
    docker run --rm -v "$src:/src" -v "$out:/out" paddws-build \
        find /src /out -xdev -exec chown "$(id -u):$(id -g)" {} + 2>/dev/null || true
}
trap 'fixown; result fallita' EXIT

echo "== immagine paddws-build"
ctx=$(mktemp -d)
cp "$src/tools/forge/Dockerfile" "$src/python/requirements.txt" "$ctx/"
docker build -q -t paddws-build "$ctx" > /dev/null
rm -rf "$ctx"

# rustup e le crate stanno nell'immagine e nel volume forge-cargo; target nel volume forge-target,
# così la build dopo ricompila solo quello che è cambiato
docker run --rm --name forge-build -e NOCHECK=$nocheck -e CHECKONLY=$checkonly \
    -v "$src:/src" -v "$out:/out" -v forge-cargo:/usr/local/cargo/registry -v forge-target:/src/rust/target \
    paddws-build sh tools/forge/build-all.sh

if [ -z "$nomister" ] && { [ -z "$checkonly" ] || [ -n "$synth" ]; }; then
    echo
    echo "== core MiSTer: sintesi con Quartus (circa 16 minuti)"
    sh "$src/mister/synth.sh" > "$HOME/forge/synth.log" 2>&1 || { tail -30 "$HOME/forge/synth.log"; exit 1; }
    grep -E "Logic utilization" "$HOME/forge/synth.log" | sed 's/^/  /'
    LC_ALL=C awk -F: '/^Slack/ { v = $2 + 0; if (n == 0 || v < m) m = v; n++ } END { printf "  slack peggiore %.3f ns su %d controlli\n", m, n }' \
        "$src/mister/output_files/PaddWS.sta.summary"
fi
if [ -z "$checkonly" ] && [ -z "$nomister" ]; then
    # le cartelle della SD come nella CI: _Arcade con il .mra, il .rbf datato e le licenze
    day=$(date +%Y%m%d)
    sd=$(mktemp -d)
    lic=$sd/_Arcade/cores/PaddWS_licenses
    mkdir -p "$lic"
    cp "$src/mister/output_files/PaddWS.rbf" "$sd/_Arcade/cores/PaddWS_$day.rbf"
    cp "$src/mister/PaddWS.mra" "$sd/_Arcade/"
    cp "$src/mister/LICENSE" "$lic/LICENSE-GPL-2.0.txt"
    cp "$src/LICENSE" "$lic/LICENSE-GPL-3.0.txt"          # il firmware Rust dentro il core
    cp "$src/mister/rtl/sid/LICENSE-CERN-OHL-S-2.0.txt" "$src/THIRD_PARTY.md" "$src/assets/fonts/OFL-Munro.txt" "$lic/"
    cp "$src/mister/rtl/vexriscv/LICENSE" "$lic/LICENSE-VexRiscv-MIT.txt"
    docker run --rm -v "$sd:/sd" -v "$out:/out" -w /sd paddws-build zip -qr -X "/out/PaddWS_MiSTer_$day.zip" _Arcade
    rm -rf "$sd"
    echo "  $out/PaddWS_MiSTer_$day.zip"
fi
trap - EXIT
fixown
result riuscita
echo
echo "== fatto in $(( ($(date +%s) - started) / 60 )) minuti"
ls -l "$out" | tail -n +2 | awk '{ printf "  %-45s %10d\n", $NF, $5 }'
