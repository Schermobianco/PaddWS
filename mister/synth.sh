#!/bin/sh
# Sintesi del core in locale, con lo stesso container Docker della GitHub Action MiSTer
# (Quartus Prime Lite 17.0.2, immagine fissata per digest in quartus-image.txt): serve solo Docker,
# nessun account Altera/Intel. Il .rbf esce in mister/output_files/PaddWS.rbf.
# Uso:  sh mister/synth.sh            (da una macchina Linux x86_64 o una VM con Docker)
# Il container si chiama quartus-synth: vm/vm-status.sh ne legge la fase dal log mentre lavora.
set -e
cd "$(dirname "$0")"
image=$(tr -d '\r\n' < quartus-image.txt)
rc=0
docker run --rm --name quartus-synth -v "$PWD:/project" -w /project "$image" quartus_sh --flow compile PaddWS || rc=$?
# Quartus nel container gira come root: i file prodotti tornano a chi ha lanciato la sintesi
docker run --rm -v "$PWD:/project" "$image" chown -R "$(id -u):$(id -g)" /project
[ "$rc" -eq 0 ] || exit "$rc"
cd output_files
grep -E "Logic utilization|Total registers|Total block memory bits|Total DSP Blocks|Total pins" PaddWS.fit.summary || true
grep -E "^(Type|Slack|TNS)" PaddWS.sta.summary || true
if grep -qE "^Slack\s*:\s*-" PaddWS.sta.summary; then
    echo "Timing non rispettato (slack negativo): vedi output_files/PaddWS.sta.summary"
    exit 1
fi
echo "mister/output_files/PaddWS.rbf"
