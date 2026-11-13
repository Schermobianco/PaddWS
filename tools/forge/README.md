[<img src="../../docs/flags/it.svg" alt="" height="14"> **Italiano**](README.md) · [<img src="../../docs/flags/gb.svg" alt="" height="14"> English](README.en.md)

# forge: la macchina di build della release

*forge* è una macchina virtuale Debian con Docker che costruisce tutta la release: controlli,
eseguibili, versione web, C64, core MiSTer e immagine della SD del Deck. È la strada normale per le
release; le GitHub Action sono l'alternativa (`build_ongithub.bat`, e `check_ongithub.bat` per i
soli controlli). Dal PC si lancia `build_onforge.bat`, che:

1. accende forge se è spenta (VMware Workstation, `vmrun`, senza finestra);
2. le manda i sorgenti del commit attuale, con i fine riga del repository come il checkout della CI;
3. aspetta che forge faccia controlli e pacchetti (`build.sh`);
4. riprende i pacchetti in `dist\`;
5. la rispegne, se l'aveva accesa lui.

Opzioni: `-Publish` (pubblica la release del tag con `gh`), `-PublishOnly` (pubblica i pacchetti
già in `dist\`, senza ricostruire), `-NoCheck`, `-CheckOnly`, `-SkipMister`, `-KeepVm`. Per provare i file non ancora committati c'è `check_onforge.bat` (`-Synth` per fare
anche la sintesi del MiSTer).

## Creare forge

### Con VMware Workstation, in automatico

Serve un PC Windows 10 o 11 con:

- VMware Workstation (gratuito per uso personale);
- Python 3.9 o successivo e git;
- il client OpenSSH (in Windows c'è già);
- circa 100 GB liberi sul disco;
- abbastanza RAM da darne 16 GB alla VM.

Dalla radice del repository:

```bat
create_forge.bat
```

In pochi minuti (sei o sette, scaricamento compreso), senza domande:

1. scarica l'immagine cloud di Debian 13 (circa 300 MB) e ne controlla lo SHA-512; resta in
   `%LOCALAPPDATA%\PaddWS\forge` per la volta dopo;
2. ne fa il disco della VM, da 80 GB, in `Documenti\Virtual Machines\forge`;
3. accende la VM con un piccolo CD per cloud-init, che crea l'utente `forge` con la chiave ssh del
   PC (`~/.ssh/id_ed25519`, creata se manca) e i comandi `sudo` senza password;
4. lancia `setup.sh`, che installa Docker e prepara la console;
5. spegne la VM, toglie il CD, aggiunge `Host forge` a `~/.ssh/config` (la versione vecchia resta
   in `config.bak`) e scrive `forge.local.psd1` nella radice del repository.

Da lì basta `build_onforge.bat`. La prima build scarica l'immagine di Quartus (circa 3 GB) e
costruisce l'immagine `paddws-build`, quindi dura di più: poco meno di un'ora. Dalla seconda volta
si ricompila solo quello che è cambiato.

Le opzioni si vedono con `create_forge.bat --help`. Quelle che servono di più:

| opzione | predefinito | |
|---|---|---|
| `--dir CARTELLA` | `Documenti\Virtual Machines\forge` | dove mettere la VM |
| `--cpus N` | metà dei processori del PC, al massimo 8 | la sintesi del MiSTer li usa tutti |
| `--memory MB` | 16384 | sotto 8192 Quartus non ci sta |
| `--disk GB` | 80 | il disco cresce man mano, non occupa subito tutto |
| `--console-password` | | chiede una password per entrare dalla console della VM; senza, si entra solo con `ssh forge` |
| `--deck` | | prepara anche la cache dell'immagine del Deck (qualche ora, vedi sotto) |

La VM non compare da sola nella libreria di VMware: per vederla, *File → Open* e il file `forge.vmx`.
Per rifarla da capo si cancella da VMware (*Manage → Delete from Disk*) e si rilancia
`create_forge.bat`.

L'indirizzo IP lo dà il DHCP della rete NAT di VMware e di solito non cambia. Se cambia,
`build_onforge.bat` lo chiede a VMware, va avanti con quello nuovo e ricorda di correggere
`HostName` in `~/.ssh/config`.

### A mano, su un'altra macchina

forge può essere anche una VM di un altro programma (Hyper-V, VirtualBox, Proxmox) o un computer
Debian 13 qualsiasi, raggiungibile con ssh. Basta:

1. Debian 13 senza ambiente grafico, con il server SSH: 8 core, 16 GB di RAM, 80 GB di disco;
2. un utente con `sudo` senza password, come root:
   `echo "UTENTE ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/UTENTE`;
3. dal PC:
   - la chiave ssh nella VM:
     `type %USERPROFILE%\.ssh\id_ed25519.pub | ssh UTENTE@IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"`;
   - in `~/.ssh/config` una voce `Host forge` con `HostName IP` e `User UTENTE`;
   - poi `scp tools/forge/setup.sh forge:` e `ssh forge sudo sh setup.sh`, e un riavvio per il
     font della console;
4. nella radice del repository, `forge.local.psd1` (non versionato):

   ```powershell
   @{
       Host = 'forge'
       Vmx  = 'D:\VM\forge\forge.vmx'   # solo con VMware: per accenderla e spegnerla da build_onforge.bat
   }
   ```

   Senza `Vmx` forge va accesa a mano prima di `build_onforge.bat`.

### Cache per l'immagine del Deck

L'immagine della SD del Deck parte da Raspberry Pi OS Lite e usa un kernel e un Mesa compilati
apposta. Si preparano una volta, in `~/forge/deck-cache`, con `deck-cache.sh`:

- `lite.img`: Raspberry Pi OS Lite Trixie armhf (circa 600 MB da scaricare);
- `kernel.tar`: il kernel del Deck, compilato incrociato (una ventina di minuti);
- `mesa.tar`: Mesa senza LLVM, compilato in un ARM emulato (più di un'ora).

Si fa insieme alla VM con `create_forge.bat --deck`, oppure dopo: `build_onforge.bat -KeepVm`,
che lascia forge accesa con i sorgenti, poi `ssh forge sh forge/src/tools/forge/deck-cache.sh`
(dalla console di forge basta `forge-deck`). Se si interrompe, si rilancia: quello che è già pronto
non si rifà. Senza la cache la release salta solo l'immagine del Deck.

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
   `mister/quartus-image.txt`) e fa lo zip della SD;
4. se c'è la cache del Deck, costruisce dal pacchetto armv7 l'immagine della SD del Deck,
   `paddws-X.Y.Z-deck-pi2.img.xz` ([deploy/raspberry/deck](../../deploy/raspberry/deck/README.md),
   circa 10 minuti, con `sudo`).

I pacchetti restano in `~/forge/out` con `BUILD.txt` (versione, commit, esito). Le crate e la
cartella `target` restano nei volumi Docker `forge-cargo` e `forge-target`: dalla seconda volta si
ricompila solo quello che è cambiato. Con 8 core e 16 GB una release completa dura una ventina di
minuti, tre quarti dei quali per Quartus.

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
- `forge-sintesi`: solo il core MiSTer;
- `forge-deck`: prepara la cache dell'immagine del Deck.
