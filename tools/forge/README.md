# forge: la macchina di build della release

*forge* è una macchina virtuale Debian con Docker che costruisce la release come le GitHub Action,
anche quando le Action non ci sono (per esempio con i minuti di GitHub finiti). Dal PC si lancia
`build_onforge.bat`, che:

1. accende forge se è spenta (VMware Workstation, `vmrun`, senza finestra);
2. le manda i sorgenti del commit attuale, con i fine riga del repository come il checkout della CI;
3. aspetta che forge faccia controlli e pacchetti (`build.sh`);
4. riprende i pacchetti in `dist\`;
5. la rispegne, se l'aveva accesa lui.

Opzioni: `-Publish` (pubblica la release del tag con `gh`), `-NoCheck`, `-CheckOnly`, `-SkipMister`,
`-KeepVm`. Sul PC servono solo git, ssh e, per pubblicare, gh.

## Cosa fa forge

`build.sh`:

1. costruisce l'immagine `paddws-build` dal `Dockerfile` (solo la prima volta e quando cambia):
   Ubuntu 22.04 come i runner Linux della CI, con
   - Rust con i target Linux x86_64, aarch64 e armv7 (compilazione incrociata), Windows (MinGW) e wasm32;
   - PowerShell per `tools/build-web.ps1`;
   - cc65;
   - Python con le dipendenze della versione Python e pytest;
2. nel container `forge-build` (`build-all.sh`) fa:
   - i controlli della CI: clippy `-D warnings` e test Rust, banco di prova del C64 contro il core
     Rust, tracce MiSTer, pytest;
   - i pacchetti Windows, Linux x86_64, aarch64 e armv7 (glibc al massimo 2.36, per Raspberry Pi OS
     Bookworm a 64 e a 32 bit), web, Python e C64;
3. sintetizza il core MiSTer con Quartus (`mister/synth.sh`, immagine fissata per digest in
   `mister/quartus-image.txt`) e fa lo zip della SD.
4. se c'è `~/forge/deck-cache`, costruisce dal pacchetto armv7 l'immagine della SD del Deck,
   `paddws-X.Y.Z-deck-pi2.img.xz` ([deploy/raspberry/deck](../../deploy/raspberry/deck/README.md),
   circa 10 minuti, con `sudo`). La cartella si prepara una volta: `lite.img` (Raspberry Pi OS Lite
   Trixie armhf, decompressa), `mesa.tar` (`mesa/build-mesa.sh`) e `kernel.tar`
   (`kernel/build-kernel.sh`); senza `lite.img` l'immagine si salta.

I pacchetti restano in `~/forge/out` con `BUILD.txt` (versione, commit, esito). Le crate e la
cartella `target` restano nei volumi Docker `forge-cargo` e `forge-target`: dalla seconda volta si
ricompila solo quello che è cambiato.

## Console

`status.sh` mostra:

- la scritta FORGE;
- il lavoro in corso (fase della build o di Quartus, tempo trascorso);
- l'ultima build e l'ultima sintesi (slack peggiore, risorse dell'FPGA);
- le immagini;
- CPU, memoria e disco.

La prima console lo mostra dal vivo fin dall'avvio; l'accesso è sulla seconda (Alt+F2). A ogni
accesso, anche con `ssh forge`, si hanno i comandi:

- `forge-stato`: vista dal vivo, Ctrl+C per uscire;
- `forge-build`: rifà la release dai sorgenti in `~/forge/src`;
- `forge-sintesi`: solo il core MiSTer.

## Preparare forge da zero

1. VMware Workstation: Debian 13 netinst, senza ambiente grafico, con il server SSH; 4 core, 8 GB di
   RAM, 80 GB di disco. Rete NAT.
2. Nella console della VM, come root: `apt install -y sudo`, l'utente nel gruppo `sudo` e, per i
   comandi senza password, `echo "UTENTE ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/UTENTE`.
3. Dal PC:
   - la chiave ssh nella VM:
     `type %USERPROFILE%\.ssh\id_ed25519.pub | ssh UTENTE@IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"`;
   - in `~/.ssh/config` una voce `Host forge` con `HostName IP` e `User UTENTE`;
   - poi `scp tools/forge/setup.sh forge:` e `ssh forge sudo sh setup.sh`.

   `setup.sh` installa Docker, open-vm-tools e la sincronizzazione dell'ora, chiama la macchina
   forge e prepara la console. Va poi riavviata una volta, per il font della console.
4. Nella radice del repository, `forge.local.psd1` (non versionato):

   ```powershell
   @{
       Host = 'forge'
       Vmx  = 'D:\VM\forge\forge.vmx'   # per accenderla e spegnerla da build_onforge.bat
   }
   ```

La prima build scarica l'immagine di Quartus (circa 3 GB) e costruisce `paddws-build`.
