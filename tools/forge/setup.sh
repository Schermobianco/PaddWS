#!/bin/sh
# setup.sh - prepara la macchina forge (Debian 13 con systemd), la VM che costruisce la release:
#   - nome host forge; Docker (get.docker.com), open-vm-tools (spegnimento pulito da VMware, anche da
#     build_onforge.bat) e ora sincronizzata, se mancano; l'utente nel gruppo docker;
#   - /etc/motd vuoto: la scritta e lo stato li stampa una volta /etc/profile.d/forge-status.sh a ogni
#     accesso interattivo, che definisce anche forge-stato (vista dal vivo), forge-build (release) e
#     forge-sintesi (solo il core MiSTer);
#   - /etc/issue (schermata di accesso) con la scritta, l'indirizzo IP e il comando ssh;
#   - sulla prima console, dall'avvio e senza accesso, la vista dal vivo (status.sh --console) come
#     l'utente; l'accesso passa alla seconda console (Alt+F2);
#   - la console con il font VGA del kernel (ha i mezzi blocchi della scritta), dal prossimo riavvio.
# Lo stato viene dai sorgenti mandati dal PC (~/forge/src/tools/forge/status.sh), quindi cambia a ogni
# build, senza root. Nulla gira in background oltre alla vista della prima console. Gli originali
# restano in /etc/motd.forge-orig, /etc/issue.forge-orig e /etc/default/console-setup.forge-orig.
#
#   sudo sh setup.sh [UTENTE]     (UTENTE: chi lancia sudo, se manca)
set -e
die() { echo "errore: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "va lanciato come root (sudo)"
user=${1:-${SUDO_USER:-}}
[ -n "$user" ] && [ "$user" != root ] || die "manca l'utente: sudo sh setup.sh UTENTE"
home=$(getent passwd "$user" | cut -d: -f6)
[ -n "$home" ] || die "l'utente $user non esiste"
src="$home/forge/src"
status="$src/tools/forge/status.sh"

old=$(hostname)
if [ "$old" != forge ]; then
    hostnamectl set-hostname forge
    sed -i "s/\b$old\b/forge/g" /etc/hosts
    echo "ok: nome host forge (era $old)"
fi
apt-get update -qq
for p in curl ca-certificates open-vm-tools systemd-timesyncd; do
    dpkg -s "$p" >/dev/null 2>&1 || { apt-get install -y -qq "$p" >/dev/null; echo "ok: installato $p"; }
done
timedatectl set-ntp true
command -v docker >/dev/null || { curl -fsSL https://get.docker.com | sh >/dev/null; echo "ok: installato Docker"; }
id -nG "$user" | tr ' ' '\n' | grep -qx docker || { usermod -aG docker "$user"; echo "ok: $user nel gruppo docker"; }
mkdir -p "$home/forge"
chown "$user:" "$home/forge"

# Il font della console: quello VGA del kernel, come sulla VM Alpine di Security Scan. Il Lat15 che
# console-setup carica su Debian non ha i mezzi blocchi della scritta; con FONTFACE vuoto setupcon non
# carica nessun font (anche nell'initramfs). Vale dal prossimo riavvio.
cs=/etc/default/console-setup
# i nomi delle versioni precedenti (quartus-*): via i file, gli originali restano col nome nuovo
for f in /etc/motd /etc/issue "$cs"; do
    for o in quartus; do
        [ -f "$f.$o-orig" ] && [ ! -f "$f.forge-orig" ] && mv "$f.$o-orig" "$f.forge-orig"
    done
done
for o in quartus; do
    rm -f "/etc/profile.d/$o-status.sh" "/usr/local/sbin/$o-console" "/etc/systemd/system/getty@tty1.service.d/$o.conf"
done
if grep -qx 'FONTFACE=""' "$cs" 2>/dev/null; then
    echo "ok: console con il font VGA del kernel"
else
    [ -f "$cs.forge-orig" ] || cp "$cs" "$cs.forge-orig"
    sed -i -e 's/^FONTFACE=.*/FONTFACE=""/' -e 's/^FONTSIZE=.*/FONTSIZE=""/' -e 's/^FONT=.*/FONT=""/' "$cs"
    grep -qx 'FONTFACE=""' "$cs" || echo 'FONTFACE=""' >>"$cs"
    # all'avvio udev esegue lo script salvato in /etc/console-setup (cached_setup_font.sh) prima che
    # console-setup lo rigeneri: va riscritto subito, o il primo riavvio carica ancora Lat15
    setupcon --save-only
    update-initramfs -u >/dev/null
    echo "ok: console con il font VGA del kernel dal prossimo riavvio (sudo reboot)"
fi

[ -f /etc/motd.forge-orig ] || { [ -f /etc/motd ] && cp /etc/motd /etc/motd.forge-orig; } || true
[ -f /etc/issue.forge-orig ] || { [ -f /etc/issue ] && cp /etc/issue /etc/issue.forge-orig; } || true
: >/etc/motd
echo "ok: /etc/motd vuoto (la scritta viene dallo script di accesso)"

cat >/etc/profile.d/forge-status.sh <<'STATUS'
# forge-status.sh - scritto da tools/forge/setup.sh (macchina di build forge, non modificare): scritta e
# stato della macchina a ogni accesso interattivo, e i comandi forge-stato (vista dal vivo, ridisegnata
# ogni 2 s finché resta aperta), forge-build (release dai sorgenti in ~/forge/src, pacchetti in
# ~/forge/out) e forge-sintesi (solo il core MiSTer). Sulla console lo schermo si pulisce prima, così
# la scritta della schermata di accesso non si ripete.
case $- in *i*) ;; *) return 0 ;; esac
case "$(tty 2>/dev/null)" in /dev/tty[0-9]*) printf '\033[H\033[2J' ;; esac
alias forge-stato='sh "$HOME/forge/src/tools/forge/status.sh" --watch'
alias forge-build='sh "$HOME/forge/src/tools/forge/build.sh"'
alias forge-sintesi='sh "$HOME/forge/src/mister/synth.sh"'
if [ -r "$HOME/forge/src/tools/forge/status.sh" ]; then
    sh "$HOME/forge/src/tools/forge/status.sh"
    printf '  %s\n\n' "Vista dal vivo: forge-stato (Ctrl+C per uscire)   Release: forge-build   MiSTer: forge-sintesi"
else
    printf '  %s\n\n' "forge: nessun sorgente in ~/forge/src (li manda build_onforge.bat dal PC)"
fi
STATUS
echo "ok: /etc/profile.d/forge-status.sh (stato a ogni accesso; forge-stato, forge-build, forge-sintesi)"

# agetty sostituisce da sé \4{scheda} con l'indirizzo IP e \e{colore} con i colori: niente script all'avvio.
# Quando la rete cambia (all'avvio l'indirizzo arriva dopo) agetty ristampa la schermata: comincia
# pulendo lo schermo (\e[H\e[2J), o la seconda copia finirebbe sotto la prima
nic=$(ip route show default 2>/dev/null | awk '{ print $5; exit }')
if [ -n "$nic" ]; then ip4="\\4{$nic}"; else ip4='\4'; fi
{
    printf '\\e[H\\e[2J\\e{lightblue}\n'
    printf '%s\n' \
        '  ░█▀▀░█▀█░█▀▄░█▀▀░█▀▀' \
        '  ░█▀▀░█░█░█▀▄░█░█░█▀▀' \
        '  ░▀░░░▀▀▀░▀░▀░▀▀▀░▀▀▀'
    printf '\\e{reset}\n  \\e{lightgreen}Macchina di build\\e{reset}  -  release e sintesi FPGA in Docker, gestita dal PC Windows\n\n'
    printf '    %-11s: %s\n' "Indirizzo" "\\e{bold}$ip4\\e{reset}" \
        "Nome host" '\n' \
        "Sistema" '\S{PRETTY_NAME}' \
        "SSH" "\\e{bold}$user@$ip4\\e{reset}"
    echo
} >/etc/issue
echo "ok: /etc/issue (schermata di accesso, indirizzo della scheda ${nic:-predefinita})"

cat >/usr/local/sbin/forge-console <<CONSOLE
#!/bin/sh
# forge-console - scritto da tools/forge/setup.sh (macchina di build forge, non modificare): la vista
# dal vivo sulla prima console (status.sh --console, come $user); accesso sulla seconda. Lo avvia
# getty@tty1 (override in /etc/systemd/system/getty@tty1.service.d/forge.conf), che lo riavvia quando
# finisce. Senza sorgenti (forge appena accesa, prima che build_onforge.bat li mandi) li aspetta.
f=$status
trap '' INT QUIT TSTP
stty sane -echo 2>/dev/null
while [ ! -r "\$f" ]; do
    printf '\033[H\033[2J\033[?25l\n  \033[94mFORGE\033[0m  in attesa dei sorgenti da build_onforge.bat (ssh forge)\n\n  Per accedere: Alt+F2\n'
    sleep 5
done
runuser -u $user -- /bin/sh "\$f" --console
sleep 3
CONSOLE
chown root:root /usr/local/sbin/forge-console
chmod 755 /usr/local/sbin/forge-console
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/forge.conf <<'UNIT'
# scritto da tools/forge/setup.sh: sulla prima console la vista dal vivo invece della richiesta di accesso
[Service]
ExecStart=
ExecStart=-/usr/local/sbin/forge-console
UNIT
systemctl daemon-reload
systemctl restart getty@tty1.service
echo "ok: prima console con la vista dal vivo, accesso sulla seconda (Alt+F2)"
echo "per tornare indietro: rm -r /etc/systemd/system/getty@tty1.service.d /etc/profile.d/forge-status.sh"
echo "  e rimetti /etc/motd.forge-orig, /etc/issue.forge-orig, /etc/default/console-setup.forge-orig"
