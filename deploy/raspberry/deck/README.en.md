[<img src="../../../docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="../../../docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

# Deck system

microSD image for the [Deck](../../../hardware/deck/README.en.md): 32-bit Raspberry Pi 2, official 7"
display on DSI, 600-pulse optical encoders, audio from the jack. It is made to boot quickly straight
into the game, with no text on screen, and to survive the power being cut at any moment: from power
on to the game splash it takes about 8 seconds.

Script messages, comments and the names of the files on the image are in Italian, like the rest of
the code.

## How it is made

| partition | | |
|---|---|---|
| 1 `BOOTFS` (FAT, 128 MB) | firmware, kernel, `config.txt`, `cmdline.txt`, `secret/wifi.txt`, `secret/ssh.txt` | not mounted; only read briefly for the network |
| 2 `rootfs` (ext4) | Raspberry Pi OS Lite Trixie 32-bit, slimmed down | always **read-only**: a RAM overlay sits on top |
| 3 `paddws-data` (ext4, 64 MB) | `/data`: `padd_config.json`, `padd_scores.json`, the Deck's ssh keys, `readahead.list` | the only one written to, with data journaling too |

- **Pulling the plug**: the kernel mounts the system read-only and `paddws-init` (in place of
  `init`) puts a RAM overlay on top, so nothing is ever written to the system partition. The game
  writes to `/data` only when a setting changes or a score enters the table; if the power goes out
  right then and the file is left half written, at boot `prepare` puts back the last good copy.
- **Boot**: the game starts before systemd. `paddws-init` mounts `/data`, `/sys` and `/dev/shm`,
  loads the display and audio drivers straight away, starts reading ahead the libraries that will be
  needed and launches `early`: as soon as the screen is there it starts cage (a Wayland compositor
  for a single application, full screen and without a cursor), and as soon as audio is there the
  game, native Wayland, as root and with the seatd built into libseat. `early` also writes the udev
  entry of the video card, which cage wants and udev would only write later. systemd starts when
  the game is ready, so as not to steal CPU and SD time from it; then `paddws.service` adopts this
  first instance and restarts the game if it quits.
- **What is left out**: initramfs, cloud-init, first boot wizard, swap, Bluetooth, automatic
  updates, login console, useless systemd generators, disk checks; the USB driver only starts with
  the network, after the game. The kernel modules are already decompressed, and `cmdline.txt`
  skips the slow initialisations the Deck does not use (tracing, CPU frequency, counters).
- **Custom kernel**: `kernel7-deck.img` is the Raspberry Pi 6.18 kernel (`kernel/`) without
  tracing, with the display, audio and overlay drivers built in, so no modules have to be loaded
  from the SD. The Raspberry Pi OS kernel stays on the boot partition: remove the line
  `kernel=kernel7-deck.img` at the end of `config.txt` to go back to it.
- **Mesa without LLVM**: the Raspberry Pi OS Mesa carries LLVM (117 MB) for software rendering,
  which the Deck does not use; reading it from the SD at every boot cost seconds. The image has a
  Mesa rebuilt with the vc4 driver only (`mesa/`).
- **Read-ahead**: on the first boot of each image `readahead-gen` notes which parts of which files
  cage and the game use (`/data/readahead.list`); from the following boots `paddws-init` has them
  read in the background while the rest starts.
- **Why not X**: with the classic X server (`modesetting` driver) the DSI display of the Pi 2 stays
  black with the Raspberry Pi OS 6.18 kernel, even though X and the game are drawing: the panel
  breaks the first time X starts and does not recover until a reboot. With cage (wlroots), the way
  Raspberry Pi OS runs its desktop today, the same game shows up.
- **No text**: no rainbow, no logo, no kernel or systemd messages (they go to console 3, which is
  not shown), no blinking cursor.
- **Network**: 12 seconds after boot `paddws-net.timer` reads `secret/wifi.txt`, then starts
  NetworkManager, avahi and ssh. The Deck is called `deck.local`; you log in as `pi` only with the
  keys put in `secret/ssh.txt` (no password). The Deck's own ssh keys are created on the first boot
  in `/data`. An Ethernet cable works too.
- **Test log**: with the word `paddws.log` in `cmdline.txt`, one minute after boot the Deck writes
  `deck-log.txt` to the boot partition (system log, network, display, USB), to read on the PC. If
  `deck-debug.sh` is there too, it runs it first (as root) and adds its output. Without
  `paddws.log` the boot partition is never written to.

## WiFi

With the SD in the PC, open `secret\wifi.txt` on the `BOOTFS` partition with Notepad and fill in
the two lines (`rete` means network; the key names stay in Italian):

```
rete=YourNetworkName
password=YourPassword
```

The TL-WN725N dongle (all versions) works without installing anything. To log in with ssh, copy
your public key into `secret\ssh.txt` (for example the contents of
`C:\Users\<name>\.ssh\id_ed25519.pub`), one per line.

## Maintenance

```sh
ssh pi@deck.local
deck-mode            # ro (normal) or rw (maintenance)
deck-mode rw         # reboots with a writable system: apt, file changes...
deck-mode ro         # reboots read-only again
```

In `rw` mode do not cut the power: shut down with `sudo poweroff`. Alternatively, add or remove the
word `paddws.rw` at the end of `cmdline.txt` by hand from the PC.

The game is in `/opt/paddws` (read-only), its configuration in `/data/padd_config.json`;
`deck_config.json` next to the executable is the starting one, put back if the file in `/data` is
damaged: 600-pulse encoders, CRT filter off and ZOOM at 125% (thicker ball and paddles, can be
changed in the menu). Game log: `/media/paddws-run/early.log` (the first instance, started before
systemd) and `journalctl -u paddws` (the following ones).

## Building the image

On the forge VM the release does it, once `tools/forge/deck-cache.sh` has prepared Lite, Mesa and
the kernel ([tools/forge](../../../tools/forge/README.en.md)). By hand, on x86 Linux, as root, with
`qemu-user-static`, `rsync`, `parted` and `dosfstools`:

```sh
curl -LO https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2026-10-06/2026-10-06-raspios-trixie-armhf-lite.img.xz
xz -d 2026-10-06-raspios-trixie-armhf-lite.img.xz
sudo bash mesa/build-mesa.sh 2026-10-06-raspios-trixie-armhf-lite.img mesa.tar   # once
bash kernel/build-kernel.sh 2026-10-06-raspios-trixie-armhf-lite.img kernel.tar     # once
sudo bash build-image.sh 2026-10-06-raspios-trixie-armhf-lite.img \
    paddws-X.Y.Z-linux-armv7.tar.gz deck.img mesa.tar kernel.tar
```

`build-mesa.sh` builds Mesa without LLVM, with the vc4 driver only (more than an hour: it compiles
on an emulated ARM); without `mesa.tar` (or with `-`) the image uses the Mesa from the packages,
which is slower to start. `build-kernel.sh` cross-compiles the kernel (`crossbuild-essential-armhf`,
`bc`, `bison`, `flex`, `libssl-dev`, `kmod`, `git`; about twenty minutes); without `kernel.tar` the
image uses the Raspberry Pi OS kernel. `build-image.sh` takes about ten minutes and writes
`deck.img` and `deck.img.xz`, the one to publish; the rest of the SD stays free.

To write it from Windows, from a PowerShell **run as administrator** (the disk number comes from
`Get-Disk`; the script only accepts USB/SD disks up to 64 GB and reads everything back to check):

```powershell
.\write-sd.ps1 -Image deck.img -Disk 2
.\write-sd.ps1 -Image deck.img -Disk 2 -Secret ..\..\..\secret\pi2img   # plus WiFi and keys
```

With `-Secret`, after writing, the script copies `wifi.txt` and `ssh.txt` from that folder into
`secret\` on the boot partition. In the local repository the folder is `secret\pi2img\`, excluded
from git (`.git/info/exclude`): that is where you keep your own WiFi and ssh key.

Raspberry Pi Imager ("Use custom") works too, **without** the OS customisations.

| file | |
|---|---|
| `build-image.sh` | builds the image from the Lite |
| `setup-chroot.sh` | the part that runs inside the image: packages, user, services |
| `mesa/` | `build-mesa.sh`: Mesa without LLVM, vc4 only |
| `kernel/` | `build-kernel.sh` and `deck.config`: the custom kernel |
| `boot/` | `config.txt`, `cmdline.txt`, `secret/wifi.txt`, `secret/ssh.txt` |
| `rootfs/` | the files copied into the system: `paddws-init`, the services, `early`, `run`, `prepare`, `session`, `net`, `readahead`, `deck-mode` |
| `write-sd.ps1` | writes and checks the SD from Windows |
