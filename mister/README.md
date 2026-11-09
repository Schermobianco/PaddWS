[<img src="../docs/flags/it.svg" alt="" height="14"> **Italiano**](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> English](README.en.md)

# PADD WS – core MiSTer

Il core FPGA di PADD WS per il MiSTer (DE10-Nano): video 320×240p a 15,7 kHz e 60 Hz, l'attract
anni '80, musiche ed effetti con un SID emulato (8580 o 6581), joystick, paddle e spinner. Ci sono
tutte le modalità, Classic, EVO, NEXT e CHALLENGE, e nell'attract una demo giocata da due CPU.
Regole e comandi completi sono in [Come si gioca](../docs/it/come-si-gioca.md).

La logica di gioco non è riscritta in Verilog: è il core Rust ([`rust/core`](../rust/core)),
compilato per RV32IM ed eseguito da un processore VexRiscv a 60 MHz dentro il core (firmware in
[`rust/mister-fw`](../rust/mister-fw)). Così il MiSTer gioca la stessa partita delle altre versioni,
tick per tick. L'RTL si occupa del resto: video, attract, schermate, audio e comandi.

Il core è stato provato su DE10-Nano quando la logica era ancora in Verilog. La versione con il
RISC-V passa le prove in simulazione e la sintesi, ma va ancora provata sull'hardware, come paddle
e spinner.

## Installazione

Lo zip della release, `PaddWS_MiSTer_AAAAMMGG.zip`, si scompatta nella radice della SD
(`/media/fat/`): mette `PaddWS.mra` in `_Arcade/` e `PaddWS_AAAAMMGG.rbf` in `_Arcade/cores/`, con i
testi delle licenze in `_Arcade/cores/PaddWS_licenses/`. Il gioco compare tra i titoli arcade e non
servono ROM.

## Classifica sulla SD

La classifica di CHALLENGE si salva nella NVRAM, come nei core arcade:
`/media/fat/config/nvram/PaddWS.nvm`. Con *Autosave scores: On* (il default), dopo ogni modifica il
MiSTer la salva la prossima volta che si apre l'OSD; con *Off* solo con *Save settings* del menu di
sistema. Funziona solo avviando il core dal `.mra`: dal `.rbf` la classifica dura finché il core
resta acceso. Un file guasto viene ignorato e resta la classifica iniziale.

## Comandi e opzioni

Su e giù muovono la racchetta (un doppio tocco veloce dà il movimento rapido), **A** è lo scatto in
avanti, **B** il rapido, **X** e **Y** scelgono e usano il bonus in NEXT, **Start** avvia e
**Select** mette un gettone. Da tastiera `5` è il gettone e `1` lo Start, come nei core arcade. Le
mosse speciali si fanno con le mezzelune del joystick, o con un giro avanti e indietro della
manopola, più **A**.

Nell'OSD (F12) ci sono la modalità (*Game type*), i giocatori, Free Play, la difficoltà, i punteggi
dritti o rivolti ai giocatori per il tavolo, i suoni dell'attract, il SID 8580 o 6581, i volumi di
musica ed effetti, il salvataggio della classifica, la luminosità del bianco, il comando delle
racchette (joystick, paddle o spinner) e la velocità dello spinner. Scanline e filtri sono quelli
del MiSTer.

## Compilare

La sintesi usa Quartus Prime Lite 17.0.2 dentro il container Docker
`theypsilon/quartus-lite-c5`, fissato per digest in `quartus-image.txt`: serve solo Docker, non
l'account Intel. Il `.rbf` esce in `mister/output_files/PaddWS.rbf`.

```powershell
.\mister\synth.ps1        # Windows con Docker Desktop
sh mister/synth.sh        # Linux o una VM con Docker
```

I due script stampano risorse e slack, e falliscono se il timing non è rispettato.

Di solito la sintesi la fa la VM *forge* ([tools/forge](../tools/forge/README.md)): `build_onforge.bat`
dal PC per tutta la release, `forge-sintesi` sulla VM per il solo core (circa 16 minuti). In
alternativa c'è la GitHub Action `MiSTer`, che parte solo a mano e dura circa mezz'ora.

I file in `rtl/gen/` sono generati e stanno nel repository, così la sintesi non richiede né Rust né
Python. Non si modificano a mano: si cambia il generatore e si rilancia.

| file | generatore |
|---|---|
| `pong_fw_b0..3.hex`, `pong_fw.vh` (firmware) | `tools/gen_mister_fw.py` |
| `pong_params.vh` | `paddws-trace` (scritto in `sim/trace/`, da copiare in `rtl/gen/`) |
| `pong_fonts.vh` | `tools/gen_mister_assets.py` |
| `pong_attract.vh` | `tools/gen_attract_assets.py` |
| `pong_next.vh` | `tools/gen_next_assets.py` |
| `pong_challenge.vh` | `tools/gen_challenge_assets.py` |
| `howto_*.hex`, `pong_howto.vh` | `tools/gen_howto_assets.py` |
| `ending_*.hex`, `pong_ending.vh` | `tools/gen_ending_assets.py` |
| `sid_music.hex`, `sid_music.vh` | `tools/gen_sid_music.py` |
| `sid_voices.hex`, `sid_voices.vh` | `tools/gen_voices.py --mister` |

Il firmware richiede Rust con il target `riscv32im-unknown-none-elf` (l'ambiente portable di
`tools\rust-env.ps1`). Dopo ogni modifica a `rust/core` va rigenerato con
`python tools/gen_mister_fw.py`, altrimenti il core MiSTer resta alla logica vecchia.

## Prove

```powershell
.\mister\sim\run.ps1
```

Rigenera con `paddws-trace` le 29 tracce di riferimento del core Rust (Classic, EVO, NEXT, tipi di
racchetta, mosse speciali, CPU, spinner) e le fa giocare al firmware su un emulatore RV32IM
(`paddws-fw-sim`): lo stato deve coincidere bit per bit a ogni tick. Controlla anche, con
`gen_mister_fw.py --check`, che il firmware in `rtl/gen` sia allineato ai sorgenti. Su Linux, nella
CI e su forge si usa `sim/run.sh`.

Per vedere il core completo c'è il simulatore dei frame, con Verilator:

```powershell
.\mister\sim\frames\frames.ps1 [scenario] [frame o intervalli...] [-f] [-u]
.\mister\sim\frames\frames.ps1 next 1300 1400-1420
```

Ricompila il modello solo se l'RTL è cambiato, va a circa 3,5 frame al secondo e salva le immagini
PPM in `mister/sim/frames/`. Al primo frame di partita salva un checkpoint, da cui ripartono le
esecuzioni seguenti; `-f` lo ignora, `-u` mette le scritte dritte. Gli scenari più utili:

- nessuno: accensione, gettone, demo e partita a un giocatore fino al GAME OVER;
- `demo`: le demo delle quattro modalità, una per giro dell'attract;
- `next`, `kinds`: NEXT contro la CPU; `kinds` prende i tipi di racchetta dalla variabile
  `PONG_KINDS` (codici di `PaddleKind`, `4,6` se manca);
- `supers`, `howto`: le mosse speciali in partita e la schermata HOW TO PLAY;
- `bullet`, `ghost`, `warp`, `steer`: i singoli bonus;
- `challenge`, `challenger`, `ending`: CHALLENGE, l'ingresso di un secondo giocatore e il finale;
- `nvram`: la classifica sulla SD con un `hps_io` finto;
- `win`, `perfect`, `paddle`, `spin`, `mute`, `music`: fine partita, paddle e spinner, audio.

L'elenco completo, con quello che ogni scenario controlla, è in testa a `sim/frames/frames.cpp`.

Altri banchi di prova, più lenti o più specifici:

- `.\mister\sim\rv\rv.ps1 [-Traces trace,...] [-Ticks N]`: il VexRiscv vero con il firmware contro
  le tracce di `run.ps1`, ciclo per ciclo, con i tempi di ogni tick (tutte: circa un'ora);
- `.\mister\sim\sid\render.ps1 [cartella]`: canzoni ed effetti del player del SID in WAV (senza
  cartella riscrive gli effetti in `assets/sounds/sid`);
- `.\mister\sim\sid\writes.ps1`: le scritture del player nei registri del SID, il riferimento del
  player Rust e di quello del C64.

Gli script cercano la OSS CAD Suite (Verilator) e MinGW in `C:\DEV\@Compiler`, o nella cartella
indicata da `PADDWS_COMPILERS`.

## Sorgenti

- `PaddWS.sv`: collegamento al framework `sys/` di Template_MiSTer (OSD, joystick, PLL, video, audio).
- `rtl/pong_top.v`: sequenza attract, partite, gettoni e CHALLENGE; i 4 tick a 240 Hz di ogni frame.
- `rtl/pong_logic_rv.v`: il processore (`rtl/vexriscv/`), la RAM del firmware e i registri.
- `rtl/*_render.v`: campo, attract, NEXT, HOW TO PLAY, CHALLENGE e finale.
- `rtl/pong_sid.v` e `rtl/sid/`: player musicale e voci, con il SID del core C64 del MiSTer.
- `rtl/ch_nvram.v`: la classifica sulla SD.
- `sim/`: tracce, simulatore dei frame, banchi di prova del processore e del SID.

## Da sapere

- Il margine di timing è sottile e i DSP sono tutti occupati: niente divisioni né moduli nell'RTL,
  e i renderer calcolano posizioni e limiti una volta per frame, poi solo confronti.
- I 4 tick di un frame partono all'inizio del vblank e devono finire prima della fotografia della
  riga 261, che i renderer usano per tutto il frame successivo.
- I bit 24, 25 e 26 dello status dell'OSD sono liberi, ma nei CFG vecchi possono valere 1: non
  vanno riusati.
- `sim/tb_pong_top.v` (Icarus) non è più allineato alle porte di `pong_top`: al suo posto si usa il
  simulatore dei frame.

## Licenza

Il framework `sys/` di Template_MiSTer è GPL v2, quindi il core è GPL v2 o successiva
([LICENSE](LICENSE)). Il SID in `rtl/sid` è in parte CERN-OHL-S v2
([rtl/sid/README.md](rtl/sid/README.md)), il VexRiscv è MIT. Il resto del progetto, firmware
compreso, è GPL v3 o successiva: vedi [THIRD_PARTY.md](../THIRD_PARTY.md).
