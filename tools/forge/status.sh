#!/bin/sh
# status.sh - stato della macchina forge per la sua console: scritta, lavoro in corso (fase della build
# della release o di Quartus, tempo trascorso), ultima build (versione, esito, pacchetti), ultima sintesi
# (tempi e risorse dell'FPGA), immagini Docker, indirizzo, sistema, CPU, memoria e disco con le barre.
# Lo mostra a ogni accesso interattivo /etc/profile.d/forge-status.sh (scritto da setup.sh), che
# definisce anche forge-stato, forge-build e forge-sintesi.
#
#   sh status.sh                 lo stato, una volta
#   sh status.sh --watch [N]     vista dal vivo, ridisegnata ogni N secondi (2 se manca); Ctrl+C esce
#   sh status.sh --console [N]   la stessa sulla prima console dall'avvio (/usr/local/sbin/forge-console):
#                                nessun input, errori in ~/.cache/forge-console.log
#
# 80 x 25 caratteri (la console di VMware) e solo caratteri del font VGA del kernel, che la console usa
# perché setup.sh toglie il font di console-setup (Lat15 non ha i mezzi blocchi della scritta). POSIX
# sh; legge soltanto.
e=$(printf '\033')
# numeri col punto: awk di Debian (mawk) legge i decimali secondo la lingua, e in italiano "1.925" valeva 1
export LC_NUMERIC=C
root=$(cd "$(dirname "$0")/../.." && pwd)
mister=$root/mister
out=$HOME/forge/out
image=$(tr -d '\r\n' < "$mister/quartus-image.txt" 2>/dev/null)
B="${e}[94m" G="${e}[92m" Y="${e}[93m" R="${e}[91m" D="${e}[90m" W="${e}[1m" N="${e}[0m"

# una riga di n "─"
dash() { printf "%${1}s" '' | sed 's/ /─/g'; }

# "── Titolo ──────...── destra" su 76 colonne (titolo e testo a destra in ASCII: se ne conta la lunghezza)
rule() {
    right=${2:-}
    a=${#1} b=${#right}
    if [ -n "$right" ]; then n=$((76 - 4 - a - b - 1)); else n=$((76 - 4 - a)); fi
    printf '  %s%s %s %s%s%s%s\n' "$B" "$(dash 2)" "$W$1$N" "$B" "$(dash "$n")" "$N" "${2:+ $D$2$N}"
}

# bar PERCENTUALE: 20 celle, verde / giallo da 70 % / rosso da 90 %
bar() {
    p=$1; [ "$p" -gt 100 ] && p=100
    f=$((p / 5)) c=$G
    [ "$p" -ge 70 ] && c=$Y
    [ "$p" -ge 90 ] && c=$R
    printf '%s%s%s%s%s' "$c" "$(printf "%${f}s" '' | sed 's/ /█/g')" "$D" "$(printf "%$((20 - f))s" '' | sed 's/ /░/g')" "$N"
}

banner() {
    printf '%s\n' \
        "$B  ░█▀▀░█▀█░█▀▄░█▀▀░█▀▀" \
        '  ░█▀▀░█░█░█▀▄░█░█░█▀▀' \
        "  ░▀░░░▀▀▀░▀░▀░▀▀▀░▀▀▀$N" ""
    printf '  %s\n' "${G}Macchina di build${N}  ${D}pacchetti della release e sintesi FPGA, nei container Docker${N}"
}

# secondi -> "42 s", "12 min 5 s", "1 h 3 min"
dur() {
    s=$1
    if [ "$s" -ge 3600 ]; then echo "$((s / 3600)) h $((s % 3600 / 60)) min"
    elif [ "$s" -ge 60 ]; then echo "$((s / 60)) min $((s % 60)) s"
    else echo "$s s"; fi
}

# tempo di attività da /proc/uptime: "3 min", "2 h 5 min", "4 g 2 h"
up() {
    awk '{ s = int($1); d = int(s / 86400); h = int(s % 86400 / 3600); m = int(s % 3600 / 60)
           if (d) print d " g " h " h"; else if (h) print h " h " m " min"; else print m " min" }' /proc/uptime
}

# secondi da quando il container $1 è partito, vuoto se non sta lavorando
running_for() {
    st=$(docker inspect "$1" --format '{{.State.Running}} {{.State.StartedAt}}' 2>/dev/null)
    case "$st" in
        true\ *)
            t=$(printf '%s' "${st#true }" | cut -c1-19)
            echo $(( $(date -u +%s) - $(date -u -d "${t}Z" +%s 2>/dev/null || date -u +%s) )) ;;
    esac
}

# Il lavoro in corso: la build della release (container forge-build: la fase è l'ultima riga "== ..."
# di build-all.sh) o la sintesi (container quartus-synth: la fase dal log di Quartus).
work() {
    if s=$(running_for forge-build) && [ -n "$s" ]; then
        ph=$(docker logs forge-build 2>&1 | sed -n 's/^== //p' | tail -1)
        printf '   %-10s %s\n' "Stato" "${G}■ build: ${ph:-avvio}${N}  ${D}da $(dur "$s")${N}"
    elif s=$(running_for quartus-synth) && [ -n "$s" ]; then
        ph=$(docker logs quartus-synth 2>&1 | sed -n 's/.*Running Quartus Prime \(.*\)$/\1/p' | tail -1)
        case "$ph" in
            *Synthesis*) ph="1/4 analisi e sintesi" ;;
            *Fitter*) ph="2/4 piazzamento e collegamenti" ;;
            *Assembler*) ph="3/4 scrittura del .rbf" ;;
            *Timing*) ph="4/4 verifica dei tempi" ;;
            '') ph="avvio" ;;
        esac
        printf '   %-10s %s\n' "Stato" "${G}■ sintesi MiSTer: $ph${N}  ${D}da $(dur "$s")${N}"
    else
        printf '   %-10s %s\n' "Stato" "${D}fermo: build_onforge.bat dal PC, o forge-build e forge-sintesi${N}"
    fi
}

# L'ultima build (BUILD.txt di build.sh): quando, versione, esito, durata, pacchetti
last_build() {
    f=$out/BUILD.txt
    if [ ! -f "$f" ]; then
        printf '   %-10s %s\n' "Build" "${D}nessuna ancora${N}"
        return
    fi
    v=$(sed -n 's/^versione=//p' "$f") ok=$(sed -n 's/^esito=//p' "$f")
    t0=$(sed -n 's/^inizio=//p' "$f") t1=$(sed -n 's/^fine=//p' "$f")
    n=$(ls "$out" | grep -vc '^BUILD.txt$')
    when=$(date -d "@$t1" '+%d/%m %H:%M')
    if [ "$ok" = riuscita ]; then r="${G}riuscita${N} ${D}($n pacchetti)${N}"; else r="${R}fallita${N}"; fi
    printf '   %-10s %s %s %s\n' "Build" "$W$when$N ${D}in $(dur $((t1 - t0)))${N}" "$v" "$r"
}

# L'ultima sintesi in mister/output_files: data, durata, slack peggiore, risorse
last_synth() {
    o="$mister/output_files"
    if [ ! -f "$o/PaddWS.sta.summary" ]; then
        printf '   %-10s %s\n' "Sintesi" "${D}nessuna ancora${N}"
        return
    fi
    # lo slack peggiore fra tutti i controlli dei tempi (setup, hold, ... di ogni clock e modello)
    sl=$(awk -F: '/^Slack/ { gsub(/ /, "", $2); if (n == 0 || $2 + 0 < m) m = $2 + 0; n++ }
                  END { if (n) printf "%.3f", m }' "$o/PaddWS.sta.summary")
    when=$(date -d "@$(stat -c %Y "$o/PaddWS.sta.summary")" '+%d/%m %H:%M')
    if [ ! -f "$o/PaddWS.rbf" ]; then r="${R}fallita: nessun .rbf${N}"
    elif awk -v s="${sl:-0}" 'BEGIN { exit !(s < 0) }'; then r="${R}tempi NON rispettati, slack $sl ns${N}"
    else r="${G}tempi ok${N} ${D}(slack $sl ns)${N}"; fi
    # durata dalla riga "; Total ; 00:16:08 ;" della tabella Flow Elapsed Time
    tot=$(sed -n 's/^; Total *; \([0-9:]*\) .*/\1/p' "$o/PaddWS.flow.rpt" 2>/dev/null | head -1)
    [ -n "$tot" ] && tot=" ${D}in $(dur $(echo "$tot" | awk -F: '{ print $1 * 3600 + $2 * 60 + $3 }'))${N}"
    printf '   %-10s %s %s\n' "Sintesi" "$W$when$N$tot" "$r"
    # "Logic utilization (in ALMs) : 3,456 / 41,910 ( 8 % )" e i bit di memoria del fit.summary
    lu=$(sed -n 's/^Logic utilization[^:]*: *\(.*\)$/\1/p' "$o/PaddWS.fit.summary" 2>/dev/null | tr -s ' ')
    mb=$(sed -n 's/^Total block memory bits *: *\(.*\)$/\1/p' "$o/PaddWS.fit.summary" 2>/dev/null | tr -s ' ')
    printf '   %-10s %s\n' "FPGA" "ALM ${lu:-?}  ${D}memoria${N} ${mb:-?}"
}

# Un'immagine Docker: nome, dettaglio, dimensione, in uso dal container $3 o no
img_line() {
    sz=$(docker image inspect "$1" --format '{{.Size}}' 2>/dev/null)
    if [ -z "$sz" ]; then
        printf '   %-16s %s\n' "$2" "${Y}$4${N}"
        return
    fi
    if [ -n "$(running_for "$3")" ]; then state="${G}■ in uso${N}"; else state="${D}inattiva${N}"; fi
    printf '   %s%-16s%s %-28s %7s  %s\n' "$G$W" "$2" "$N" "$5" \
        "$(awk -v b="$sz" 'BEGIN { printf "%.1f GB", b / 1e9 }')" "$state"
}

images() {
    rule "Immagini"
    made=$(docker image inspect paddws-build --format '{{.Created}}' 2>/dev/null | cut -c1-10)
    img_line paddws-build "paddws-build" forge-build "si crea alla prima build" \
        "Ubuntu 22.04, del $(echo "$made" | awk -F- '{ print $3 "/" $2 }')"
    img_line "$image" "quartus-lite-c5" quartus-synth "si scarica alla prima sintesi (circa 3 GB)" \
        "Quartus 17.0.2 @$(printf '%s' "${image#*@sha256:}" | cut -c1-12)"
}

status() {
    ip=$(ip -4 addr show scope global 2>/dev/null |
         awk '/ inet / && $NF !~ /^(docker|br-|veth)/ { sub(/\/.*/, "", $2); printf "%s%s (%s)", sep, $2, $NF; sep = ", " }')
    sys=$(. /etc/os-release 2>/dev/null && echo "$NAME" | cut -d' ' -f1)
    printf '  %s\n' "${e}[96m$(date '+%d/%m/%Y %H:%M:%S')$N"         # ciano: un colore che nessun'altra riga usa
    rule "Macchina"
    printf '   %-10s %s%-30s%s %-7s %s\n' "Indirizzo" "$W" "${ip:-nessuno}" "$N" "Sistema" \
        "${sys:-Linux} $(cat /etc/debian_version 2>/dev/null), acceso da $(up)"
    # i sorgenti mandati dal PC: commit e versione (scritti in .source da build_onforge.bat)
    src=$(cat "$root/.source" 2>/dev/null || echo "${D}nessuno ancora${N}")
    if docker info >/dev/null 2>&1; then
        printf '   %-10s %s%-30s%s %-7s %s\n' "Docker" "$G" "attivo $(docker version --format '{{.Server.Version}}' 2>/dev/null)" "$N" \
            "Kernel" "$(uname -r)"
        printf '   %-10s %s\n' "Sorgenti" "$src"
        rule "Lavoro"
        work
        last_build
        last_synth
        images
    elif [ "$(id -u)" -ne 0 ] && ! id -nG | tr ' ' '\n' | grep -qx docker; then
        printf '   %-10s %s\n' "Docker" "${R}nessun accesso: $(id -un) non è nel gruppo docker${N}"
        printf '   %-10s %s\n' "Sorgenti" "$src"
    else
        printf '   %-10s %s\n' "Docker" "${R}NON ATTIVO${N}  (systemctl status docker)"
        printf '   %-10s %s\n' "Sorgenti" "$src"
    fi
    rule "Risorse"
    cpus=$(grep -c '^processor' /proc/cpuinfo)
    read -r l1 l5 l15 _ < /proc/loadavg
    lp=$(awk -v l="$l1" -v c="${cpus:-1}" 'BEGIN { printf "%d", l * 100 / c }')
    printf '   %-10s %s  %-22s %s\n' "CPU" "$(bar "$lp")" "carico $l1 $l5 $l15" "${D}$cpus core${N}"
    # totale e usata: MB della memoria, KB del disco
    read -r mt mu <<EOF
$(free -m | awk '/^Mem/ { print $2, $2 - $7 }')
EOF
    printf '   %-10s %s  %-22s %s\n' "Memoria" "$(bar $((mu * 100 / mt)))" "$mu di $mt MB" "${D}$((mu * 100 / mt)) %${N}"
    read -r dt du <<EOF
$(df -k / | awk 'NR == 2 { print $2, $3 }')
EOF
    printf '   %-10s %s  %-22s %s\n' "Disco" "$(bar $((du * 100 / dt)))" \
        "$(awk -v u="$du" -v t="$dt" 'BEGIN { printf "%.1f di %.1f GB", u / 1048576, t / 1048576 }')" "${D}$((du * 100 / dt)) %${N}"
}

case "${1:-}" in
    -w|--watch|--console)
        n=${2:-2}
        case "$n" in ''|*[!0-9]*|0) n=2 ;; esac
        if [ "$1" = --console ]; then
            # la prima console dall'avvio: nessun input, i tasti non compaiono, Ctrl+C non fa nulla; l'accesso
            # è sulla seconda console. Gli errori vanno in un file (riscritto a ogni avvio), mai sullo schermo:
            # sulla VM di Security Scan, con gli errori sulla console, la vista finiva subito e ripartiva di continuo
            mkdir -p "$HOME/.cache" 2>/dev/null
            exec 2>"$HOME/.cache/forge-console.log"
            echo "$(date '+%F %T') vista avviata come $(id -un) ($(id -Gn))" >&2
            trap '' INT QUIT TSTP
            trap 'printf "%s\n" "${e}[?25h"; exit 0' TERM HUP
            # il terminale arriva da systemd senza le impostazioni di agetty: senza onlcr le righe scendono a scalini
            stty sane -echo 2>/dev/null
            foot="Vista dal vivo, ogni $n s  -  per accedere: Alt+F2"
        else
            # il cursore torna all'uscita; lo schermo si prepara prima e si disegna in una volta (niente sfarfallio)
            trap 'printf "%s\n" "${e}[?25h"; exit 0' INT TERM HUP
            foot="Vista dal vivo, ogni $n s  -  Ctrl+C per uscire"
        fi
        printf '%s' "${e}[?25l"
        while :; do
            # 25 righe al massimo e nessun a capo dopo l'ultima: la console farebbe scorrere via la scritta
            o=$(banner; status; printf '  %s' "${D}$foot${N}")
            printf '%s%s' "${e}[H${e}[2J" "$o"
            sleep "$n"
        done ;;
    *)
        banner
        status
        echo ;;
esac
