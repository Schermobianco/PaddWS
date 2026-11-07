#!/bin/bash
# Gira dentro l'immagine (chroot ARM con qemu), lanciato da build-image.sh: toglie ciò che
# rallenta l'avvio, installa cage e Xwayland e prepara utente, servizi e rete. I file di rootfs/ sono già al
# loro posto.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

# nel chroot nessun servizio deve partire davvero
printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
# l'initramfs non serve (ext4 e SD sono nel kernel): non si rigenera a ogni pacchetto
sed -i 's/^update_initramfs=.*/update_initramfs=no/' /etc/initramfs-tools/update-initramfs.conf

# pacchetti da togliere: primo avvio, cloud-init, Bluetooth (il Pi 2 non ce l'ha), swap,
# aggiornamenti automatici e i kernel degli altri modelli
# (il firmware WiFi resta solo per le chiavette Realtek, come la TL-WN725N)
purge=(cloud-init rpi-cloud-init-mods rpi-connect-lite userconf-pi rpi-swap bluez bluez-firmware
       rpi-eeprom rpi-update rpi-usb-gadget cron
       firmware-atheros firmware-libertas firmware-mediatek firmware-brcm80211)
mapfile -t -O ${#purge[@]} purge < <(dpkg-query -W -f='${binary:Package}\n' \
    'linux-headers-*' 'linux-image-*-v6' 'linux-image-*-v8' 'linux-image-rpi-v6' 'linux-image-rpi-v8' \
    'linux-image-*-v8:arm64' 'linux-image-rpi-v8:arm64' 2>/dev/null | sort -u)
mapfile -t purge < <(dpkg-query -W -f='${binary:Package}\n' "${purge[@]}" 2>/dev/null)
apt-get purge -y -q "${purge[@]}"

# cage (compositor Wayland per una sola applicazione) con il gioco nativo Wayland (PADDWS_WAYLAND)
# e Xwayland di riserva, e il resto che gli serve (GL di Mesa per vc4, ALSA). Niente server X
# classico: con il driver "modesetting" di X il display DSI del Pi 2 resta nero (kernel 6.18),
# con cage si vede.
apt-get update -q
apt-get install -y -q --no-install-recommends \
    cage xwayland libwayland-egl1 libwayland-cursor0 \
    libgl1 libglx-mesa0 libegl1 libegl-mesa0 libgl1-mesa-dri libxi6 libxkbcommon0 alsa-utils
apt-get autoremove -y -q --purge
apt-get clean
rm -rf /var/lib/apt/lists/*

# Mesa senza LLVM (mesa/build-mesa.sh), se c'è: le sue librerie al posto di quelle dei pacchetti,
# poi via LLVM (117 MB, serviva solo al rendering software). Dopo le operazioni con apt, perché
# dpkg ora vede una dipendenza mancante.
if [ -f /tmp/mesa.tar ]; then
    LIB=/usr/lib/arm-linux-gnueabihf
    old=$(ls $LIB/libgallium-*.so)
    tar -xf /tmp/mesa.tar -C / --no-same-owner --wildcards './usr/lib/*' './usr/share/glvnd/*' './usr/share/drirc.d/*'
    rm -f $LIB/pkgconfig/dri.pc $LIB/pkgconfig/egl.pc $LIB/pkgconfig/gbm.pc $LIB/pkgconfig/gl.pc
    for f in $old; do tar -tf /tmp/mesa.tar "./${f#/}" >/dev/null 2>&1 || rm -f "$f"; done
    llvm=$(dpkg-query -W -f='${binary:Package}\n' 'libllvm*' 2>/dev/null || true)
    [ -z "$llvm" ] || dpkg --purge --force-depends $llvm
    rm -f /tmp/mesa.tar
    ldconfig
    echo "Mesa senza LLVM: $(ls $LIB/libgallium-*.so)"
fi
# manuali e documentazione non servono (restano le licenze); delle traduzioni restano it ed en
rm -rf /usr/share/man/* /usr/share/info/* /usr/share/groff/*
find /usr/share/doc -mindepth 1 ! -type d ! -name copyright -delete
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'it*' ! -name 'en*' -exec rm -rf {} +

# utente pi: niente password (si entra solo con le chiavi di secret/ssh.txt, sulla partizione di
# boot), sudo senza password per SHUTDOWN
usermod -s /bin/bash pi
for g in audio video input render gpio plugdev netdev sudo; do
    getent group "$g" >/dev/null && usermod -aG "$g" pi
done
echo 'pi ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/010_pi-nopasswd
chmod 440 /etc/sudoers.d/010_pi-nopasswd

# nome, ora e identità della macchina fissati qui (paddws-init la ricava poi dal numero di serie
# del Pi): altrimenti, con la radice in RAM, ogni accensione sarebbe un "primo avvio". Le chiavi
# ssh del Deck non sono nell'immagine: le crea il Deck in /data al primo avvio.
# radio WiFi accesa per NetworkManager (Raspberry Pi OS la spegne finché non si sceglie il paese)
mkdir -p /var/lib/NetworkManager
printf '[main]\nNetworkingEnabled=true\nWirelessEnabled=true\nWWANEnabled=true\n' \
    >/var/lib/NetworkManager/NetworkManager.state

echo deck >/etc/hostname
sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tdeck/' /etc/hosts
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
echo Europe/Rome >/etc/timezone
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
systemd-hwdb update
touch /etc/.updated /var/.updated

# servizi: si avvia solo il necessario; rete, avahi e ssh li accende paddws-net.timer
mask=(rpi-resize.service sshswitch.service regenerate_ssh_host_keys.service
      keyboard-setup.service console-setup.service apparmor.service e2scrub_reap.service
      e2scrub_all.timer apt-daily.timer apt-daily-upgrade.timer dpkg-db-backup.timer
      fstrim.timer logrotate.timer man-db.timer udisks2.service systemd-pstore.service
      getty@tty1.service serial-getty@ttyAMA0.service serial-getty@ttyS0.service
      NetworkManager-wait-online.service systemd-networkd-wait-online.service
      ldconfig.service systemd-hwdb-update.service systemd-update-done.service
      systemd-journal-catalog-update.service systemd-journal-flush.service
      systemd-random-seed.service systemd-rfkill.service systemd-rfkill.socket
      systemd-binfmt.service rpi-display-backlight.service systemd-firstboot.service
      ModemManager.service bluetooth.service hciuart.service triggerhappy.service
      triggerhappy.socket rpi-eeprom-update.service dphys-swapfile.service
      proc-sys-fs-binfmt_misc.automount sys-kernel-debug.mount sys-kernel-tracing.mount
      sys-kernel-config.mount sys-fs-fuse-connections.mount dev-hugepages.mount
      systemd-machine-id-commit.service systemd-hibernate-clear.service systemd-sysusers.service
      getty.target systemd-ask-password-wall.path systemd-ask-password-console.path
      sshd-keygen.service)
for u in "${mask[@]}"; do systemctl mask "$u" >/dev/null 2>&1 || true; done
for u in NetworkManager.service avahi-daemon.service avahi-daemon.socket ssh.service ssh.socket \
         wpa_supplicant.service systemd-timesyncd.service remote-fs.target; do
    systemctl disable "$u" >/dev/null 2>&1 || true
done
systemctl enable paddws.service paddws-net.timer paddws-log.timer paddws-readahead.timer
systemctl set-default multi-user.target

# generatori di systemd che il Deck non usa: ognuno è un programma letto dalla SD e avviato a
# ogni accensione (restano fstab e debug)
mkdir -p /etc/systemd/system-generators
for g in netplan systemd-gpt-auto-generator systemd-hibernate-resume-generator systemd-rc-local-generator \
         systemd-run-generator systemd-ssh-generator systemd-system-update-generator \
         systemd-sysv-generator systemd-tpm2-generator systemd-getty-generator; do
    ln -sf /dev/null /etc/systemd/system-generators/$g
done

# moduli caricati da /etc/modules-load.d: nessuno
: >/etc/modules-load.d/modules.conf

chmod 755 /usr/sbin/paddws-init /usr/local/lib/paddws/* /usr/local/bin/deck-mode
mkdir -p /ovl/rw /ovl/root /media/root-ro /data /boot/firmware
rm -f /usr/sbin/policy-rc.d
