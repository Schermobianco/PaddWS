# Sistema del Deck

Immagine della microSD per il [Deck](../../../hardware/deck/README.md): Raspberry Pi 2 a 32 bit, display
ufficiale da 7" sul DSI, encoder ottici da 600 impulsi, audio dal jack. È fatta per partire in fretta
dritta nel gioco, senza scritte, e per sopportare la corrente tolta in qualunque momento: dalla
corrente allo splash del gioco passano circa 8 secondi.

## Come è fatta

| partizione | | |
|---|---|---|
| 1 `BOOTFS` (FAT, 128 MB) | firmware, kernel, `config.txt`, `cmdline.txt`, `secret/wifi.txt`, `secret/ssh.txt` | non montata; solo letta un attimo per la rete |
| 2 `rootfs` (ext4) | Raspberry Pi OS Lite Trixie a 32 bit, ridotto | sempre in **sola lettura**: sopra c'è un overlay in RAM |
| 3 `paddws-data` (ext4, 64 MB) | `/data`: `padd_config.json`, `padd_scores.json`, chiavi ssh del Deck, `readahead.list` | l'unica scritta, con il journal anche dei dati |

- **Spegnimento brutale**: il kernel monta il sistema in sola lettura e `paddws-init` (al posto di
  `init`) ci mette sopra un overlay in RAM, quindi niente viene mai scritto sulla partizione del
  sistema. In `/data` il gioco scrive solo quando si cambia un'impostazione o si entra in
  classifica; se la corrente manca proprio in quel momento e il file resta a metà, all'avvio
  `prepare` rimette la copia dell'ultima volta buona.
- **Avvio**: il gioco parte prima di systemd. `paddws-init` monta `/data`, `/sys` e `/dev/shm`,
  carica subito i driver di display e audio, comincia a leggere in anticipo le librerie che
  serviranno e lancia `early`: appena c'è lo schermo parte cage (un compositor Wayland per una
  sola applicazione, a tutto schermo e senza cursore), e appena c'è l'audio il gioco, nativo
  Wayland, come root e con il seatd incorporato in libseat. `early` scrive anche la voce di udev
  della scheda video, che cage vuole e che udev scriverebbe solo più tardi. systemd parte quando
  il gioco è pronto, per non rubargli CPU e SD; poi `paddws.service` adotta questa prima istanza
  e la fa ripartire se il gioco si chiude.
- **Cosa non c'è**: initramfs, cloud-init, primo avvio, swap, Bluetooth, aggiornamenti automatici,
  console di login, generatori di systemd inutili, controlli dei dischi; il driver USB parte solo
  con la rete, dopo il gioco. I moduli del kernel sono già decompressi e in `cmdline.txt` si
  saltano le inizializzazioni lente che il Deck non usa (tracing, frequenza della CPU, contatori).
- **Kernel su misura**: `kernel7-deck.img` è il kernel 6.18 di Raspberry Pi (`kernel/`) senza
  tracing, con dentro i driver di display, audio e overlay, senza moduli da caricare dalla SD.
  Il kernel di Raspberry Pi OS resta nella partizione di boot: basta togliere la riga
  `kernel=kernel7-deck.img` in fondo a `config.txt` per tornare a quello.
- **Mesa senza LLVM**: il Mesa di Raspberry Pi OS si porta dietro LLVM (117 MB) per il rendering
  software, che il Deck non usa; letto dalla SD a ogni avvio costava secondi. L'immagine ha un
  Mesa ricompilato con il solo driver vc4 (`mesa/`).
- **Lettura anticipata**: al primo avvio di ogni immagine `readahead-gen` annota quali pezzi di
  file usano cage e il gioco (`/data/readahead.list`); dagli avvii dopo `paddws-init` li fa
  leggere in sottofondo, mentre il resto parte.
- **Perché non X**: con il server X classico (driver `modesetting`) il display DSI del Pi 2 resta
  nero con il kernel 6.18 di Raspberry Pi OS, anche se X e il gioco disegnano: il pannello si
  rompe al primo avvio di X e non si riprende fino al riavvio. Con cage (wlroots), la strada che
  Raspberry Pi OS usa oggi per il desktop, lo stesso gioco si vede.
- **Niente scritte**: niente arcobaleno, logo o messaggi del kernel e di systemd (vanno sulla
  console 3, invisibile), niente cursore lampeggiante.
- **Rete**: 12 secondi dopo l'avvio `paddws-net.timer` legge `secret/wifi.txt`, poi avvia
  NetworkManager, avahi e ssh. Il Deck si chiama `deck.local`; si entra come `pi` solo con le
  chiavi messe in `secret/ssh.txt` (nessuna password). Le chiavi ssh del Deck stesso si creano al primo avvio in `/data`.
  Va bene anche il cavo Ethernet.
- **Registro di prova**: con la parola `paddws.log` in `cmdline.txt`, un minuto dopo l'avvio il
  Deck scrive `deck-log.txt` nella partizione di boot (registro di sistema, rete, display, USB),
  da leggere sul PC. Se lì c'è anche `deck-debug.sh`, lo esegue prima (come root) e ne aggiunge
  l'uscita. Senza `paddws.log` la partizione di boot non viene mai scritta.

## WiFi

Con la SD nel PC, nella partizione `BOOTFS` si apre `secret\wifi.txt` con il Blocco note e si
completano le due righe:

```
rete=NomeDellaRete
password=LaPassword
```

La chiavetta TL-WN725N (tutte le versioni) funziona senza installare nulla. Per entrare con ssh si
copia in `secret\ssh.txt` la propria chiave pubblica (per esempio il contenuto di
`C:\Users\<nome>\.ssh\id_ed25519.pub`), una per riga.

## Manutenzione

```sh
ssh pi@deck.local
deck-mode            # ro (normale) oppure rw (manutenzione)
deck-mode rw         # riavvia con il sistema scrivibile: apt, modifiche ai file...
deck-mode ro         # riavvia di nuovo in sola lettura
```

In modalità `rw` non si toglie la corrente: si spegne con `sudo poweroff`. In alternativa si può
aggiungere o togliere a mano la parola `paddws.rw` in fondo a `cmdline.txt` dal PC.

Il gioco è in `/opt/paddws` (sola lettura), la sua configurazione in `/data/padd_config.json`;
`deck_config.json` accanto all'eseguibile è quella di partenza, rimessa se il file in `/data` è
rovinato: encoder da 600 impulsi, filtro CRT spento e ZOOM al 125% (pallina e racchette più
spesse, da cambiare nel menu). Registro del gioco: `/media/paddws-run/early.log` (la prima istanza, partita prima di
systemd) e `journalctl -u paddws` (le successive).

## Costruire l'immagine

Su Linux x86 (per esempio la VM forge), come root, con `qemu-user-static`, `rsync`, `parted` e
`dosfstools`:

```sh
curl -LO https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2026-10-06/2026-10-06-raspios-trixie-armhf-lite.img.xz
xz -d 2026-10-06-raspios-trixie-armhf-lite.img.xz
sudo bash mesa/build-mesa.sh 2026-10-06-raspios-trixie-armhf-lite.img mesa.tar   # una volta
bash kernel/build-kernel.sh 2026-10-06-raspios-trixie-armhf-lite.img kernel.tar     # una volta
sudo bash build-image.sh 2026-10-06-raspios-trixie-armhf-lite.img \
    paddws-X.Y.Z-linux-armv7.tar.gz deck.img mesa.tar kernel.tar
```

`build-mesa.sh` compila Mesa senza LLVM, con il solo driver vc4 (più di un'ora: si compila in un
ARM emulato); senza `mesa.tar` (o con `-`) l'immagine usa il Mesa dei pacchetti, più lento ad
avviarsi. `build-kernel.sh` compila il kernel incrociato (`crossbuild-essential-armhf`, `bc`,
`bison`, `flex`, `libssl-dev`, `kmod`, `git`; una ventina di minuti); senza `kernel.tar`
l'immagine usa il kernel di Raspberry Pi OS.
`build-image.sh` ci mette una decina di minuti e scrive `deck.img` e `deck.img.xz`, quella da
pubblicare; il resto della SD resta libero.

Per scriverla da Windows, da un PowerShell **come amministratore** (il numero del disco si legge con
`Get-Disk`; lo script accetta solo dischi USB/SD fino a 64 GB e rilegge tutto per verifica):

```powershell
.\write-sd.ps1 -Image deck.img -Disk 2
.\write-sd.ps1 -Image deck.img -Disk 2 -Secret ..\..\..\secret\pi2img   # e poi WiFi e chiavi
```

Con `-Secret` lo script, dopo la scrittura, copia `wifi.txt` e `ssh.txt` di quella cartella in
`secret\` della partizione di boot. Nel repository locale la cartella è `secret\pi2img\`, esclusa
da git (`.git/info/exclude`): lì si tengono la propria WiFi e la propria chiave ssh.

Va bene anche Raspberry Pi Imager ("Use custom"), **senza** le personalizzazioni del sistema
operativo.

| file | |
|---|---|
| `build-image.sh` | costruisce l'immagine dalla Lite |
| `setup-chroot.sh` | la parte che gira dentro l'immagine: pacchetti, utente, servizi |
| `mesa/` | `build-mesa.sh`: Mesa senza LLVM, solo vc4 |
| `kernel/` | `build-kernel.sh` e `deck.config`: il kernel su misura |
| `boot/` | `config.txt`, `cmdline.txt`, `secret/wifi.txt`, `secret/ssh.txt` |
| `rootfs/` | i file copiati nel sistema: `paddws-init`, i servizi, `early`, `run`, `prepare`, `session`, `net`, `readahead`, `deck-mode` |
| `write-sd.ps1` | scrive e verifica la SD da Windows |
