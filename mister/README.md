# PADD WS – core MiSTer FPGA

Stato: **core completo, sintetizzato e funzionante su DE10-Nano** (prova del 2026-10-28, versione
senza attract; l'attract è verificato in simulazione).

- Logica di gioco e CPU avversarie: il **core Rust vero** (`rust/core`) eseguito da un processore
  RISC-V soft (VexRiscv RV32IM a 60 MHz, `rtl/pong_logic_rv.v`, firmware `rust/mister-fw`): vedi
  [Logica sul RISC-V](#logica-sul-risc-v). 29 tracce (`sim/run.ps1`), identiche bit per bit al
  core Rust: 8 da 60 s (EVO, classica, 1 giocatore, semi e difficoltà diversi), 2 con la CPU, 1 con
  l'encoder (paddle/spinner), 17 NEXT da 4 minuti con capsule e bonus (anche BULLET), tipi di
  racchetta, mosse speciali e CPU, e `trace_bul_wait`, a 128 Hz, con il BULLET armato che aspetta
  la palla (a 240 Hz la CPU lo usa solo con la palla già vicina). La logica in Verilog di prima è
  stata tolta dal repository (resta nella storia di git, fino alla versione 4.0.0-beta.12).
- Video 320×240p (15,723 kHz / 60,012 Hz misurati in simulazione), punteggi ruotati, linea
  centrale, aree boost; musiche ed effetti con il SID (8580 o 6581); joystick, paddle e spinner
  MiSTer; opzioni da OSD.
- Attract anni '80 (`rtl/attract_render.v`) con gli stessi tempi e bitmap delle versioni Rust e
  Python (`rtl/gen/pong_attract.vh`): auto-test all'accensione, strisce, logo, titolo con la
  pallina che rimbalza sul nero e, solo qui, una partita dimostrativa CPU contro CPU.
- Gettoni: un credito per partita (anche in due), Free Play da OSD; fine partita al primo che
  arriva a 11 (due giocatori) o dopo 3 palle perse (singolo), poi GAME OVER e di nuovo l'attract.
- Sintesi con Quartus 17.0.2 nella GitHub Action `MiSTer` (immagine Docker
  `theypsilon/quartus-lite-c5`, fissata per digest in `quartus-image.txt`), tempi rispettati. La
  sintesi dura circa mezz'ora. La Action parte solo a mano (*Run workflow* o
  `build_ongithub.bat`): sui tag `vX.Y.Z` il file `.rbf` va nella release insieme agli eseguibili
  Rust. In locale, con lo stesso container: `.\synth.ps1` (Docker Desktop) o
  `sh synth.sh` (Linux o una macchina virtuale con Docker). L'immagine è pubblica su Docker Hub
  (circa 3 GB): non serve l'account Altera/Intel. Il `.rbf` esce in `output_files/`.
- La macchina virtuale di build della release, *forge* ([tools/forge](../tools/forge/README.md)),
  sintetizza il core con lo stesso container: `build_onforge.bat` dal PC, o `forge-sintesi` sulla VM.

Installazione sulla SD: scompattare `PaddWS_MiSTer_AAAAMMGG.zip` (dalla release o dalla run)
nella radice della SD, `/media/fat/`: mette `PaddWS.mra` in `_Arcade/` e `PaddWS_AAAAMMGG.rbf` in
`_Arcade/cores/`. Il gioco compare tra i
titoli arcade; non servono ROM.

Da fare: prova dell'attract, di paddle e spinner su DE10-Nano.
Il modello di riferimento è il core Rust ([`rust/core`](../rust/core)): l'hardware deve
riprodurne lo stato tick per tick, bit per bit.

## Scelte

- **Video 320×240 a ~60 Hz, 15,7 kHz (240p)**: la risoluzione arcade più diffusa, 4:3 con
  pixel quadrati, nativa sui CRT a 15 kHz. Niente filtro CRT nel core: scanline, maschere
  e shader li applica lo scaler del MiSTer (opzioni video del menu).
- **Fisica a 240 Hz**: 4 tick per frame, eseguiti in sequenza durante il vblank.
- **Logica intera**: Q16.16 su 32 bit con segno, nessuna divisione nel passo di simulazione.

### Timing video

| | attivo | front porch | sync | back porch | totale |
|---|---|---|---|---|---|
| orizzontale (pixel) | 320 | 12 | 32 | 60 | 424 |
| verticale (righe) | 240 | 3 | 3 | 16 | 262 |

Pixel clock 6,667 MHz = 20 MHz / 3, dal PLL del template: 15,723 kHz, 60,012 Hz. La PLL ha una
seconda uscita a 60 MHz, dallo stesso VCO, per il processore della logica (`rtl/pll/pll_0002.v`,
`output_clock_frequency1`: è il solo valore da cambiare per il ripiego a 40 MHz).

## Aritmetica (da rispettare esattamente)

Definita in [`rust/core/src/fixed.rs`](../rust/core/src/fixed.rs):

- `mul(a, b) = (a * b) / 2^16` con intermedio a 64 bit e **troncamento verso lo zero**
  (in HDL: valore assoluto, shift, ripristino del segno);
- `mul_recip(a, r) = (a * r) / 2^24`, stesso troncamento; `r` è un reciproco Q8.24 precalcolato;
- shift aritmetici a destra (`>> 1`) solo dove indicati nel codice (punto medio del contatto);
- RNG xorshift32 (`x ^= x << 13; x ^= x >> 17; x ^= x << 5`), seme 0 sostituito da `0x2545F491`.
  Nel core servono solo: `range(2, 4)` e `range(1, 3)` = `lo + (x & 1)`, `sign()` = bit 31
  (0 → +1), `unit()` = `(x >> 15) - 2^16`. Ogni chiamata avanza lo stato una volta.

L'ordine delle operazioni di un tick è quello di `Match::step` in
[`rust/core/src/game.rs`](../rust/core/src/game.rs): input → racchette → attesa battuta →
movimento palla → bordi → contatto/rimbalzo oppure punto.

## Parametri e vettori di test

```powershell
. .\tools\rust-env.ps1; cd rust
cargo run --release -p paddws-trace -- --out ..\mister\sim\trace --seed 1        # 2 giocatori EVO
cargo run --release -p paddws-trace -- --out ..\mister\sim\trace_1p --players 1 --classic
```

- `pong_params.vh` – i parametri che servono ai renderer e a `pong_top` come
  `localparam signed [31:0]` (Q16.16; i reciproci `*_INV_*` sono Q8.24), altezze dei tipi di
  racchetta e salti del TELEPORT per il disegno (`kind_px_h`, `kind_warp_shift`), livelli e
  classifica iniziale di CHALLENGE (`rung_*`, `ch_*`). Il resto dei parametri sta nel firmware,
  cioè nel core Rust. La copia per la sintesi è in `rtl/gen/` (320×240), uguale a quella di
  `sim/trace`.
- `trace_config.vh` – `P_SEED`, `P_PLAYERS`, `P_EVO`, `P_DIFFICULTY` e le altre opzioni della
  partita registrata (solo prove).
- `trace_input.hex` – una riga per tick, 32 bit: bit 0–7 giocatore sinistro, 8–15 destro
  (bit 0 su, 1 giù, 2 rapido, 3 scatto in avanti, che vale per un solo tick, 6 posizione da
  encoder in questo tick); bit 16–23 e 24–31 posizione dell'encoder del sinistro e del destro
  (pixel tra il bordo alto e la racchetta, `top_offset` del core Rust). Nelle tracce con
  `--control spinner,...` il giocatore sinistro (o la CPU) usa l'encoder; `P_CPU_SIDES` e
  `P_CONTROL` in `trace_config.vh` dicono quali lati gioca la CPU e con quali comandi.
- `trace_state.hex` – una riga per tick, stato **dopo** il tick: 19 parole da 32 bit
  concatenate (152 cifre esadecimali), in quest'ordine:

| # | contenuto |
|---|---|
| 0–5 | palla: x, y, vx, vy, boost, raggio |
| 6–9 | racchetta sinistra: x, y, velocità, flag |
| 10–13 | racchetta destra: x, y, velocità, flag |
| 14 | punteggi: sinistro bit 0–15, destro bit 16–31 |
| 15 | record del giocatore singolo |
| 16 | tick di attesa della battuta |
| 17 | eventi del tick |
| 18 | stato del RNG |

  Flag racchetta: bit 0–7 direzione (int8), bit 8 rapido, bit 16–23 livello area boost.
  Eventi: bit 0 muro, 1 colpo, 2 boost, 3 punto, 4 capsula raccolta, 5 bonus attivato, 6 SUPER,
  7 salto del TELEPORT, 8 sparo del BLASTER, 9 rimbalzo sul muro del GUARDIAN.
  Input: bit 4 seleziona e bit 5 attiva il bonus (NEXT), bit 7 sparo del BLASTER (il core MiSTer
  ha il BLASTER senza scatto, che spara con il bit 3).

Nelle tracce NEXT (`--next`, giocate da due CPU) seguono altre 26 parole, per 45 in tutto:

| # | contenuto |
|---|---|
| 19 | tick alla prossima capsula |
| 20 | bit 0–15 tick dell'alone di SLOW, 16–31 tick di rampa rimasti del BULLET scattato |
| 21 | accelerazione di CURVE |
| 22 | effetti: bit 0 palla fantasma, 1 lato del fantasma, 2 SUPER in volo, 3–4 animazione, 5 palla guidata (STEER), 6 lato di chi guida, 7 su, 8 giù, 9–10 tiro di una mossa speciale, 11 BULLET armato o in corso, 12 attivato dal destro, 13 BULLET scattato (bullet time), 16–31 tick di fermo |
| 23–24 | giocatori: bit 0–3, 4–7 e 8–11 riserva (3 bonus da 4 bit, 8 = vuoto), 12–13 selezionato, 14–15 animazione del SUPER, 16–19 bonus armato (8 = nessuno), 20–31 pausa tra le attivazioni |
| 25–44 | capsule 0–3: x, y, vx, vy, flag (bit 3 presente, 0–2 bonus: il BULLET è 15) |

  Bonus: 0 TELEPORT, 1 SMASH, 2 SLOW, 3 CURVE, 4 GHOST, 5 SUPER, 6 STEER, 7 BULLET (solo dalle
  capsule, come il SUPER; non va nel bonus armato del giocatore: il suo stato è nella parola 22).
  Il BULLET non ha una durata: `P_BULLET_RAMP_TICKS` è la rampa d'entrata. Con 8 bonus i codici
  della riserva e del bonus armato sono a 4 bit: `bonus_code` in `rust/mister-fw/src/words.rs`
  (la codifica è una sola, per le tracce e per il firmware). Da `pong_logic_rv.v` le stesse parole
  escono come `player0/1`, `next_flags` e, per la parola 20, `slow_timer` e `bullet_timer`.

Nelle tracce NEXT con i tipi di racchetta (`--next --paddles TIPO,TIPO`; `P_KINDS` in
`trace_config.vh`, 3 bit per lato, 7 = senza tipo) seguono altre 30 parole, per 75 in tutto:

| # | contenuto |
|---|---|
| 45–46 | giocatori: bit 0–2 tipo, 3 muro del GUARDIAN non ancora tutto caduto, 4–7 colpi del BLASTER in volo (uno per posto), 8–10 colpi nel caricatore, 16–31 ricarica del caricatore |
| 47–48 | giocatori: bit 0–7 settori del muro del GUARDIAN in piedi (bit 0 in alto, 5 settori), 16–31 pausa prima del colpo successivo |
| 49–72 | colpi del BLASTER, 4 per giocatore (prima il sinistro): x, y, vx (0 se non in volo) |
| 73–74 | `Paddle::motion` delle due racchette (spostamento smorzato, serve a TWIST) |

  Nelle tracce con un BLASTER la CPU spara un colpo alla volta: paddws-trace aggiunge raffiche
  con il bit 7 (che la CPU non comanda) per provare il caricatore da 4 colpi.

  Tipi: 0 ARCADE, 1 TITAN, 2 HAMMER, 3 TWIST, 4 BLASTER, 5 RUSH, 6 GUARDIAN.

Nelle tracce con le mosse speciali (`--next --supers`; `P_SUPERS` in `trace_config.vh`) l'input è
di 40 bit (10 cifre esadecimali: mossa del sinistro nei bit 32-33, del destro nei bit 34-35;
1 STRAIGHT SHOT, 2 RISING STRIKE), la mossa in volo è nei bit 9-10 della parola 22 e seguono 2
parole, una per giocatore: bit 0-7 barra, 8-9 livello di STRAIGHT SHOT armato, 10-11 livello di
RISING STRIKE armata (0 = niente, 2 = MAX); solo nella parola del giocatore sinistro anche il
livello del tiro della mossa in volo (bit 12-13) e l'impennata di RISING STRIKE ancora da arrivare
(bit 14); bit 16-31 a zero (47 parole, 77 con i tipi di racchetta). Il testbench confronta anche le
mosse comandate dalle CPU.

Con i default (60 s di gioco) ogni traccia contiene ~20–30 colpi, boost con restringimento
dell'area e diversi punti; la modalità a un giocatore va verificata a parte.

## Architettura

```
PaddWS.sv (emu)        collegamento a sys/: hps_io (OSD, joystick), PLL 20 e 60 MHz, arcade_video, audio
└── rtl/pong_top.v     sequenza attract/demo/partita/GAME OVER, gettoni, 4 tick per frame nel vblank
    ├── pong_logic_rv.v logica di gioco e CPU (demo e avversario): il core Rust sul processore
    │   │              RISC-V, con la RAM da 64 KB e i registri verso pong_top
    │   └── vexriscv/  VexRiscv RV32IM (MIT, vedi rtl/vexriscv/README.md)
    ├── next_render.v  NEXT: scelta dei bonus, riserve, capsule ed effetti; racchetta
    │                  dell'avversario nella presentazione di CHALLENGE e racchette della sfilata
    │                  del finale
    ├── howto_render.v HOW TO PLAY delle mosse speciali: scritte, figurine e animazione del gesto
    ├── challenge_render.v CHALLENGE: presentazione, livello superato, continue, iniziali,
    │                  classifica e punti in partita
    ├── ch_nvram.v     classifica di CHALLENGE sulla SD (NVRAM del MiSTer, file PaddWS.nvm)
    ├── ending_render.v finale della CHALLENGE: parti e tempi, scritte, timbri DEFEATED, punteggio,
    │                  fuochi d'artificio (framebuffer 160x120 a due pagine), titoli di coda
    ├── attract_render.v auto-test, strisce, logo e titolo; dice a pong_top dove il titolo è nero
    ├── video_timing.v 424x262 a 20 MHz / 3
    ├── pong_render.v  rettangoli fotografati a fine frame -> confronti per pixel; testo ruotato;
    │                  scritte della demo e del GAME OVER
    └── pong_sid.v     player musicale per il SID: 3 voci di canzone + effetti sulla voce 3,
        │              voce digitalizzata della CHALLENGE con il volume del SID, voci di partita
        │              (urla delle mosse, READY, GO e YOU WIN) come campioni sommati all'uscita
        └── sid/       SID 6581/8580 dal core C64 del MiSTer (vedi rtl/sid/README.md)
rtl/gen/               generati: pong_params.vh (paddws-trace), font (tools/gen_mister_assets.py),
                       pong_attract.vh (tools/gen_attract_assets.py), musiche ed effetti del SID
                       (sid_music.hex e .vh, tools/gen_sid_music.py), voci "da SID": nomi, urla delle
                       mosse, READY, GO e YOU WIN (sid_voices.hex e .vh, tools/gen_voices.py --mister),
                       firmware del processore (pong_fw_b0..3.hex e pong_fw.vh, tools/gen_mister_fw.py),
                       HOW TO PLAY (howto_*.hex e pong_howto.vh, tools/gen_howto_assets.py), finale
                       della CHALLENGE (ending_*.hex e pong_ending.vh, tools/gen_ending_assets.py)
```

## Logica sul RISC-V

La logica di gioco è il core Rust (`paddws-core`, il modello di riferimento) compilato per RV32IM
ed eseguito da un VexRiscv in `rtl/pong_logic_rv.v`: a ogni tick `Cpu::input` per i lati della CPU
e `Match::step`, poi le parole di stato. Non c'è più una seconda implementazione da tenere uguale:
una modifica al core arriva al MiSTer rigenerando il firmware.

**Firmware** (`rust/mister-fw`, crate `paddws-mister-fw`, no_std): `map.rs` (indirizzi e
registri: è la specifica di `pong_logic_rv.v`), `words.rs` (parole di stato e comandi, la stessa
codifica delle tracce), `engine.rs` (nuova partita, tick, CPU, modifiche di prova), `main.rs`
(avvio e registri, solo per `riscv32im-unknown-none-elf`). `python tools/gen_mister_fw.py` lo
compila (profilo `fw`, opt-level 3) e scrive l'immagine della RAM in `rtl/gen/pong_fw_b0..3.hex`
(un file per byte, letti con `$readmemh`) e `pong_fw.vh`, con l'impronta dei sorgenti:
`--check` (in `sim/run.ps1` e `run.sh`) dice se i file generati sono rimasti indietro. I byte
compilati non cambiano con la cartella del progetto né con la versione del gioco. La sintesi non
richiede Rust.

- Dimensioni: 51.264 byte di codice e costanti, 4,8 KB di `.bss` (stato del firmware: i parametri
  delle quattro difficoltà, calcolati all'avvio perché `Params::new` usa la virgola mobile in
  software, la partita e le due CPU), stack misurato 6,8 KB su 9,5 KB liberi, con una sentinella
  sul fondo che ferma il firmware se viene sovrascritta. Niente `.data`.
- Avvio: ~251.000 istruzioni (parametri), poi aspetta le richieste. Nuova partita ~15.500
  istruzioni, tick 600–1.900 in media secondo la modalità.

**Memoria** (`map.rs`): RAM da 64 KB a `0x0000_0000` (codice, costanti, `.bss`, stack; quattro BRAM
da 8 bit a due porte, istruzioni e dati), registri a `0xF000_0000` (bit 31 a uno: il VexRiscv non
li mette in cache). In lettura: `0x000` STATUS (bit 0-7 numero della partita, bit 8 tick da fare),
`0x004` partita (giocatori, EVO, NEXT, mosse, difficoltà, bonus, tipi), `0x008` seme, `0x00C` CPU
(livelli e comandi), `0x010`/`0x014` semi delle CPU, `0x018` comandi del tick (come
`trace_input.hex`), `0x01C` mosse e lati della CPU, `0x020` `TICK_HZ`, `0x024` campo, `0x040` e
`0x080` modifiche di prova. In scrittura: `0x000` fine (con il numero della partita servita),
`0x004` errore del firmware, `0x008` modifiche applicate, `0x100 + 4·i` parola di stato `i`: le 77
delle tracce più altezze, `Ball::dx`, tick, modalità e i comandi effettivi del tick (86 parole).
Fuori da NEXT le parole dei bonus e dei tipi hanno valori fissi (riserve vuote, nessun tipo).

**Protocollo e clock**: `reset` (nuova partita) e `step` (tick) arrivano da `pong_top` a 20 MHz
come prima e alzano `busy`; gli ingressi si registrano lì. Il processore e la RAM girano a 60 MHz
(`clk_cpu`, stessa PLL, fronti allineati): il firmware legge i registri, scrive le parole in una
copia ombra e poi la fine; al primo fronte a 20 MHz dopo, le 86 parole passano alle uscite tutte
nello stesso ciclo e `busy` si abbassa. Una nuova partita arrivata durante un tick lo annulla (la
fine con il numero vecchio non conta). I passaggi tra i due clock sono tutti da registro a registro:
Quartus li analizza con la relazione vera tra i fronti (al peggio 16,7 ns) e non servono eccezioni
nel file SDC.

**Tempi**: `pong_top` esegue i 4 tick di un frame di fila dall'inizio del vblank, e devono finire
prima della fotografia per il render alla riga 261: 21 righe, 26.712 cicli a 20 MHz. La cache
istruzioni del VexRiscv è di 4 KB e il codice di un tick NEXT è di circa 7 KB, quindi conta il
clock: a 20 MHz i frame NEXT con due CPU (demo) superavano il tempo fino al 16% delle volte. A 60
MHz il frame peggiore delle tracce è di 11.600 cicli a 20 MHz (con due CPU), il tick medio va da
~460 (Classic) a ~2.000 (NEXT con due CPU) cicli a 20 MHz. Con il ripiego a 40 MHz il frame peggiore
sarebbe ~17.400 cicli. Una nuova partita invece richiede ~15.500 istruzioni (soprattutto copie di
`Match` e `Params`), ~13.000 cicli a 20 MHz: le uscite cambiano una decina di righe dopo il `reset`,
non subito come con la logica in Verilog di prima. Si vede solo nel frame in cui parte la partita, e solo se il
`reset` arriva a ridosso della fotografia (nel simulatore dei frame: `sup_t0` dello scenario
`supers`).

**Modifiche di prova**: il simulatore dei frame cambia lo stato della partita (punteggi, bonus
armato, riserva, barre, una capsula) scrivendo i registri `patch`/`patch_n` di `pong_logic_rv`,
che il firmware applica all'inizio del tick dopo, e insieme la parola visibile. Nella sintesi
quei registri non si scrivono mai e restano a zero.

Comandi: su/giù (doppio tocco = rapido, come nell'originale: un tocco breve e di nuovo la stessa
direzione entro 200 ms), **A** = scatto in avanti (EVO e NEXT), **B** = rapido, **X** = seleziona
il bonus, **Y** = usa il bonus (NEXT), **Start** = inizia la partita, **Select** = gettone (da
tastiera: **5** gettone, **1** start, come nei cabinati MAME).
Opzioni da OSD (F12): modalità (*Game type*: Challenge, il default, NEXT, EVO o Classic), giocatori (*Players*:
due, uno o contro la CPU; NEXT con "uno" si gioca contro la CPU, in Challenge non conta; un valore
Challenge rimasto in *Players* da un CFG di prima vale contro la CPU), Free Play, difficoltà (dalla partita successiva; vale anche per la
CPU; la demo usa sempre Normal e la modalità scelta qui: CLASSIC, EVO, NEXT con bonus e racchette
a caso, CHALLENGE contro l'avversario di un livello a caso), punteggi dritti (*Scores: Upright*, il default: cabinato o monitor) o verso i giocatori (tavolo), suoni
dell'attract (*Attract sound*, vedi sotto), luminosità del bianco (*White level*: 100%, 87%,
75% o 62%, tutta l'immagine in proporzione), comando delle racchette (*Paddle control*:
joystick, paddle o spinner) e velocità dello spinner, filtro del SID (*Sound*: SID 8580 o SID
6581), volumi della musica e degli effetti (*Music volume*, *Effects volume*, vedi sotto),
salvataggio automatico della classifica di CHALLENGE
(*Autosave scores*, vedi [Classifica sulla SD](#classifica-sulla-sd)), proporzioni, effetti di
scansione, reset.

Volumi e audio dell'attract:

- *Music volume* (bit 31:28 dello status) ed *Effects volume* (bit 35:32), da 100% (il primo valore,
  il default) a 0% a passi del 10%. Il player li applica come guadagno di ogni voce del SID
  (`vol_gain` in `rtl/pong_sid.v`, 64 = 1: il quadrato del volume, come nel gioco Rust), che scala
  l'inviluppo della voce (`rtl/sid/sid_voice.sv`, marcato PaddWS): il DC delle voci e il volume del
  SID ($D418) non cambiano, quindi cambiare volume non dà colpi. Le voci 1 e 2 sono della musica,
  la 3 degli effetti mentre ne suona uno e altrimenti della musica; la voce digitalizzata con il
  nome dell'avversario (voci 2 e 3) e le voci di partita (urla delle mosse, READY, GO e YOU WIN)
  seguono gli effetti. Con il SID 6581 il DC proprio del chip resta, quindi a 0% il nome
  dell'avversario si sente ancora, piano. Al 100% le scritture e il suono sono quelli di prima.
- *Music volume: 0%* spegne tutte le canzoni del SID, ovunque: titolo, scelta di NEXT, HOW TO
  PLAY, presentazione, livello superato, finale, continue, iniziali, classifica, game over e i temi
  degli avversari in partita. Fino alla 4.0.0-beta.19 c'era *Music: On/Off* (bit 26, ora libero ma
  nei CFG vecchi può valere 1).
- *Attract sound: Off* (bit 11) zittisce tutto l'attract, demo compresa: musica ed effetti; il
  gettone e Start si sentono sempre. Con *Attract sound: On* e *Music volume: 0%* nell'attract
  restano solo gli effetti (strisce, pallina del titolo, demo).

*Sound* è il bit 23. In un CFG di prima il valore Samples (bit 24:23 = 2, i campioni WAV, tolti)
ha il bit 23 a zero e suona quindi con il SID 8580; il bit 24, libero, nei CFG vecchi può valere 1
e non va riusato.

**CHALLENGE** (*Game type: Challenge*, sempre in NEXT): dopo la scelta di bonus e racchetta, 7
livelli contro avversari CPU, uno per tipo di racchetta, con i bonus e il livello di CPU del gioco
Rust (`rtl/gen/pong_params.vh`: `rung_*`, livelli della CPU 4-10 del core Rust, verificati con
la traccia `trace_ladder`). Presentazione dell'avversario (**A** o Start la salta) con la sua
racchetta rivolta verso il giocatore e i segni del tipo come su PC (estremità gialle del TITAN,
bande dell'HAMMER, TWIST inclinata, smussi, canne e caricatore pieno del BLASTER, immagini gialle
dello scatto del RUSH, pezzo di muro del GUARDIAN): la disegna `next_render.v` (ingresso `intro`)
con la stessa logica dell'anteprima della scelta della racchetta, partita a 7,
livello superato con i premi o continue: 10 secondi per un gettone e Start, punti da zero. Punti
arcade come su PC (colpi, scatti, SUPER e punti con il moltiplicatore dello scambio, solo shift e
somme) in basso a destra; a fine sessione le iniziali (su/giù e **A**) per la classifica dei 10
migliori, che compare anche nell'attract tra il titolo e la demo. La classifica si salva sulla
SD (vedi sotto). Schermate in `rtl/challenge_render.v`, scritte da
`tools/gen_challenge_assets.py`; con la difficoltà dell'OSD cambia la velocità della palla.
Nuovo sfidante (`M_CHALLENGER`): durante presentazione, partita contro la CPU e livello superato
(tranne l'ultimo) lo Start del lato libero (joystick 2 o tasto `2`, oppure joystick 1 o `1` se il
campione è a destra) con un credito fa entrare un secondo giocatore: "HERE COMES A NEW
CHALLENGER!", scelta dello sfidante (il lato del campione resta bloccato, ingresso `lock` di
`next_render.v`), sfida a `rung_points` senza punti arcade; il vincitore riprende il livello dal
suo lato (`ch_side`, la CPU di sinistra prende il livello dell'avversario) con il premio
`ch_win_bonus` del livello, il perdente scrive le iniziali se entra in classifica. Simulatore dei
frame: scenario `challenger`.

**Finale** (`M_ENDING`, `rtl/ending_render.v`), come `rust/game/src/ending_ui.rs`: battuto l'ultimo
avversario, dopo il GAME OVER, al posto della schermata CHAMPION e prima delle iniziali; circa 57 s
(3.416 frame), Start lo salta dopo mezzo secondo. Musica: la canzone ENDING del SID
(`SID_SONG_ENDING`, la 14). Solo bianco, giallo e rosso sul nero, senza sfumature.

1. CONGRATULATIONS! (lampeggia giallo e bianco) e, dopo un secondo, YOU WIN! con la voce (3,5 s).
2. La sfilata dei sette avversari, uno al secondo con un colpo sul muro, con le racchette e i segni
   del tipo come nella presentazione (le disegna `next_render.v`, ingresso `parade`: dettagli gialli,
   immagini del RUSH gialle che si diradano a scacchiera) e il nome; mezzo secondo dopo, con un colpo
   di racchetta, il timbro rosso DEFEATED inclinato di 18 gradi (9 s).
3. Il punteggio: SCORE che sale in 3 s (un passo di 1/180 a frame con gli shift), CHAMPION BONUS (il
   premio dell'ultimo livello, vittoria e partita perfetta, come `Score::win_bonus`) in 1 s, poi
   TOTAL (9 s).
4. YOU ARE THE PADD WS CHAMPION con i fuochi d'artificio di `ending_ui.rs` (7 s): anello, salice,
   palma, crisantemo bianco e rosso, crepitio e cometa che si divide, con il razzo e la gravità.
5. I titoli di coda, a 35 pixel al secondo fino all'ultima riga al centro, e 2 s di sosta.
6. THE END (lampeggia, 3 s), poi le iniziali o la classifica.

Le scritte sono Munro 10 px a scala 2 o 3 (scala 3 con il reciproco, `(d * 171) >> 9`): una bitmap
a 1 bit di righe da 160 pixel (`ending_text.hex`, 6 M10K circa), le cifre del punteggio in celle e il
timbro già ruotato (il renderer ne legge due per pixel dalle due porte della M10K, perché i timbri
vicini si sovrappongono agli angoli). Una mappa (`ending_map.hex`), letta una volta per riga nella
cancellazione orizzontale, dice per ogni riga dello schermo quale riga di bitmap, dove, a che scala
e colore; i titoli di coda sono una finestra della mappa che scorre. I fuochi sono punti già
calcolati da `tools/gen_ending_assets.py` con le formule di `ending_ui.rs`, per ogni fuoco e frame a
15 Hz, sulla griglia di celle 2x2 pixel (`ending_fw.hex`, 6.058 punti, i fuochi dello stesso tipo li
condividono): un disegnatore li scrive in un framebuffer 160x120 a 2 bit con due pagine (10 M10K),
cancellando e ridisegnando la pagina nascosta a ogni frame dei fuochi (circa 21.000 cicli su 4
frame) e scambiando le pagine nel vblank. Nessuna divisione, solo confronti, somme e contatori.
La voce "YOU WIN!" la dice anche il GAME OVER di ogni partita vinta contro la CPU (vedi le voci di
partita). Simulatore dei frame: scenario `ending`.

### Classifica sulla SD

La classifica di CHALLENGE usa la NVRAM dei core arcade del MiSTer, come i core con `hiscore.v`.
`PaddWS.mra` ha `<nvram index="4" size="192"/>`: all'avvio del core il MiSTer manda il file
`/media/fat/config/nvram/PaddWS.nvm`, se c'è, come download di `hps_io` con indice 4. Per salvarlo
lo rilegge dal core con un upload sullo stesso indice e lo scrive nella stessa cartella:

- **a mano**: voce *Save settings* del menu di sistema dell'OSD (salva anche le opzioni);
- **in automatico** (*Autosave scores: On*, il default): dopo una modifica della classifica il core
  alza `ioctl_upload_req` e il MiSTer salva la prossima volta che si apre l'OSD (F12). Con *Off* la
  classifica si salva solo a mano.

Vale solo con il core avviato dal `.mra` (`_Arcade`): avviato dal `.rbf` il MiSTer non gestisce la
NVRAM e la classifica resta finché il core è acceso.

Il file (`rtl/ch_nvram.v`) è di 192 byte: `PWS` e la versione (1), poi a 16 + 16·i il posto i
(i = 0 il primo): tre codici del font delle iniziali, il livello raggiunto (8 = scala finita), i
punti su 24 bit e in BCD su 4 byte, dal byte basso; l'ultimo byte fa tornare 0x5A la somma di
tutti i byte. Il file arriva prima in una piccola RAM e passa alla classifica solo se è intero, con
l'intestazione e la somma giuste, i campi nei limiti e i punti in ordine non crescente; se manca o è
guasto resta la classifica iniziale (`ch_default_*` di `pong_params.vh`), e il primo salvataggio lo
riscrive. In upload ogni byte esce dalla classifica com'è in quel momento; la somma la ricalcola di
continuo un contatore (192 cicli). Un posto inserito durante un salvataggio resta da salvare.

**SID**: suoni e musiche passano per il SID del core C64 del MiSTer (filtro 8580 o 6581 da OSD),
con le moltiplicazioni in logica perché i DSP sono tutti usati (+1.000 ALM circa). `pong_sid.v` è
un player in stile C64 a 50 Hz che legge da una ROM le tracce scritte in
`tools/gen_sid_music.py` (musiche originali: titolo, presentazione del livello, livello superato,
continue, game over, campione e i 7 temi degli avversari di CHALLENGE, canzoni 7-13 nell'ordine di
`PaddleKind`, e il finale, la 14, dopo i temi) e suona gli effetti sulla voce 3. In partita c'è musica solo in CHALLENGE contro la
CPU: il tema dell'avversario (`SID_SONG_THEME0 + rung_kind`), in ripetizione sulle voci 1 e 2; non
nella sfida tra due giocatori né nella demo, e mai con *Music volume: 0%*. Gli
scenari `challenge` e `challenger` del simulatore dei frame controllano la canzone in partita. Le
versioni PC, Raspberry e web suonano le musiche in tempo reale con il port in Rust del player
(`rust/sid`, stesse scritture ai registri) e usano per gli effetti i WAV registrati dal player
simulato con Verilator (`mister\sim\sid\render.ps1`, in `assets/sounds/sid` a 44,1 kHz).

**Filtro del SID** nelle musiche (formato nel docstring di `tools/gen_sid_music.py`): il taglio
(`0xA0` + i 3 bit bassi, poi gli 8 alti) e la sua scivolata a ogni passo della canzone (`0xB0` e
16 bit con segno, in 1/32 di passo) sono comandi di traccia, con il taglio tenuto a 16 bit (5 bit
di frazione) e senza saturazione: i limiti li controlla il generatore. $D417 e $D418 degli
strumenti nel filtro stanno nei byte 6 e 7, finora vuoti; il generatore mette nel $D417 il bit
della voce, e il filtro vale solo per le voci 1 e 2: la voce 3, quella degli effetti, non ci passa
mai. Il player tiene una copia di $D417 e $D418 e li riscrive, con il taglio, solo quando una nota
di uno strumento nel filtro li cambia; a ogni canzone nuova $D418 = $0F e $D417 = 0. Il volume resta
15. Usano il filtro il basso di HAMMER (passa-basso risonante, un "reese" leggero e il "wobble"
nelle ultime due battute), un'apertura della melodia nel titolo e un respiro della melodia di
TITAN, pensati per l'8580 e provati anche con il 6581. Durante la **voce della CHALLENGE** il filtro
è spento: all'inizio $D417 = 0 (il DC delle voci 2 e 3 non passa dal filtro), i campioni scritti in
$D418 hanno il modo a 0, alla fine $D418 = $0F, e intanto la copia del player resta $D417 = 0; la
prima nota nel filtro dopo la voce (il tema parte mentre la voce si spegne) lo riscrive tutto. Lo
stesso fanno il player Rust e quello del C64 (`c64/src/sid.s`), con le stesse scritture.

**Musica dinamica**, con le regole di `rust/sid/src/engine.rs`: al **match point** (uno dei due a un
punto dalla vittoria, `music_fast` di `pong_top`, fino alla fine della partita) la canzone avanza a
62,5 Hz (un passo ogni 320.000 cicli invece di 400.000, scelto a ogni passo per quello dopo) con le
note alla stessa altezza, mentre gli effetti restano a 50 Hz con un divisore e una fase degli
arpeggi loro; nel **bullet time** (`bul_on`) i canali della canzone avanzano un passo su due e
scrivono le frequenze dimezzate, come gli effetti rallentati, e a ogni entrata e uscita le note in
corso riscrivono subito la frequenza. Le due regole si sommano. Verifica: `writes.exe fast`, `slow` e
`both` (`mister/sim/sid/writes.cpp`) registrano le scritture del player Verilog nei tre casi, da
confrontare con il player Rust (`paddws_sid::player::Player`, un passo per frame del registro);
`writes.ps1` le salva in `rust/sid/tests/` per `cargo test -p paddws-sid`; senza argomento il
riferimento del C64 e del player Rust (`c64/test/sid_reference.txt`).

**Voce della CHALLENGE**: nella presentazione di ogni livello una voce digitalizzata dice il nome
dell'avversario, 0,5 s dopo l'inizio come su PC (`ANNOUNCE_AFTER`). I campioni sono quelli del
gioco Rust (`assets/sounds/voice/*.raw4`, 5000 Hz, 4 bit, 8 = silenzio), nella ROM
`rtl/gen/sid_voices.hex` (17.086 byte, `python tools/gen_voices.py --mister`; 12 voci con l'indice a
4 bit e gli indirizzi a 15 bit: 0-6 i nomi nell'ordine di `PaddleKind`, 7-8 le urla delle mosse
nell'ordine di `Special`, 9 READY, 10 GO, 11 YOU WIN; numeri in `VOICE_*` di `sid_voices.vh`). `pong_sid.v` li suona
con il trucco del registro del volume del C64 ($D418): ogni campione diventa il volume del SID,
che moltiplica anche l'offset DC dell'uscita. Il SID di `rtl/sid` lo riproduce come i chip veri:
il 6581 ha un DC suo, l'8580 no; per questo, come i player di campioni per l'8580, le voci 2 e 3
danno un DC costante (impulso con il bit di test) e la voce si sente con tutti e due i filtri.
Intanto il jingle tace (le sue scritture si saltano) e gli effetti aspettano; il DC sale e scende
con l'inviluppo (70 e 120 ms) per non dare un colpo secco. Se la presentazione si salta o arriva
uno sfidante la voce si ferma. Registrazione di prova: `.\mister\sim\sid\render.ps1 CARTELLA 8580 -Voice`
(`intro_voice_<nome>.wav`, `intro_voice_stop.wav`, effetti rallentati `<effetto>_slow.wav`).

**Voci di partita**, come su PC: all'attivazione di una mossa speciale (eventi `Straight` e `Rise`,
bit 10 e 11 di `sound_events`, anche nella demo se ha i suoni) l'urlo con il nome della mossa,
insieme all'effetto SID della mossa; in CHALLENGE (contro la CPU e nella sfida) "READY?" al primo
frame del conto alla rovescia e "GO!" al via, al posto del suo effetto (i bip dei secondi restano);
"YOU WIN!" con la scritta YOU WIN (da sola, al posto di GAME OVER) quando un giocatore batte la CPU (Classic, EVO, NEXT e i
livelli della CHALLENGE, non l'ultimo: lì la dice il finale, un secondo dopo CONGRATULATIONS!).
Non usano il trucco del volume: un secondo player in `pong_sid.v` legge la stessa ROM dal secondo
porto delle M10K e dà il campione a 4 bit (`call_level`), che `pong_top` somma all'uscita del SID,
con l'8580 e con il 6581, come `(livello - 8) << 11` (±16.384, sopra effetti e musica del SID, che
arrivano a ~7.600 e ~15.000) con la saturazione; musica ed effetti continuano. Una voce nuova
interrompe quella in corso; se nello stesso frame partono due mosse si sente STRAIGHT SHOT.

**Paddle e spinner**: con *Paddle* la manopola dà la posizione della racchetta su tutta la corsa
(0 = in alto), a ogni tick. Con *Spinner* gli spostamenti di ogni frame (×1, ×2, ×4 o ×½ con
*Spinner speed*) si sommano alla posizione della racchetta, che con lo spinner fermo si muove
anche con il joystick. Con STEER la racchetta è ferma: il paddle guida la palla se girato oltre
1/8 di racchetta da dove si trova, lo spinner con il verso della rotazione.

**NEXT**: dopo Start ognuno sceglie 3 bonus su 6 (su/giù e **A**, 10 secondi; la CPU sceglie da
sola), poi la racchetta (su/giù e **A** per confermare, 10 secondi; la CPU sceglie a caso), poi partita con capsule dalla mezzeria da toccare con la racchetta, riserva di 3 in alto,
**X** per scegliere e **Y** per usare il bonus. Logica: il core Rust stesso (`pong_logic_rv.v`),
grafica in `next_render.v` (icone e scritte da `tools/gen_next_assets.py`).
Ogni tipo di racchetta ha il suo segno come su PC; TWIST si inclina con uno scorrimento a gradini
delle righe (solo shift e somme), il RUSH vibra di un pixel. Il GUARDIAN ha dietro la racchetta (a
`P_GUARDIAN_BARRIER_X` dal bordo) un muro a 5 settori uguali, uno per partita, che non torna: va da
`P_GUARDIAN_TOP` (sotto la banda delle riserve, quindi senza toccare la barra delle mosse in alto)
al fondo del campo, con i confini `P_GUARDIAN_BOUND1..4`, decrescenti (y del core, verso l'alto, in pixel interi:
`next_render` le converte in righe dello schermo; a 320x240 settori da 43-44 righe). Ogni palla mancata
rimbalza sul settore in cui sta il centro della palla, se è ancora in piedi (il primo settore
comprende anche la banda in alto), e quel settore cade. Il firmware scrive la maschera dei settori
nelle parole 47-48 (`aux0/1`, bit 0 = settore in alto); `pong_top` ricava il settore colpito dalla
differenza tra la maschera del frame prima e quella del frame con l'evento 9 e lo fa lampeggiare
per 18 frame, poi sparisce. `next_render` disegna in ogni settore i tratti di 5 righe ogni 8, da 2
righe dopo l'inizio a 2 righe prima della fine: tra un settore e l'altro resta uno spazio di 4 righe
(come `next_ui.rs`, solo confronti con costanti e un multiplexer dei confini). Con le mosse speciali
la barra, che qui sta sotto la riserva (righe 22-26) ed esce dalla banda, lascia il primo tratto
alla riga 29, 2 righe sotto la barra.
**BULLET** (bullet time), raro come il SUPER e solo dalle capsule (gialle). Attivato resta
armato finché la palla entra nell'ultimo terzo del campo dalla parte di chi l'ha attivato andando
verso di lui (`Params::bullet_zone`, controllo
all'inizio di ogni tick e subito all'attivazione); allora scatta e rallenta tutto tranne la sua
racchetta (palla con CURVE e STEER, racchetta e manopola dell'avversario, capsule, colpi del
BLASTER avversario) con il passo `v - (v >>> k)` (3/4 nei primi 0,25 s, poi metà), una
sottrazione e un multiplexer senza moltiplicatori. Finisce all'inizio del tick in cui la palla non
va più verso di lui (l'ha ribattuta) o al punto; un punto prima dello scatto non lo consuma. Uno
alla volta, armato o in corso. La CPU lo usa come gli altri bonus e in più, con una probabilità
più alta, per salvare una palla che non prenderebbe (`Cpu::bullet_rescue`). A schermo, con la palette di sempre: da armato la racchetta di chi l'ha
attivato ha un bordo giallo che lampeggia piano (128 tick acceso, 128 spento); scattato il bordo
sparisce (come su PC), la racchetta resta bianca e nitida e il resto diventa grigio e "sfocato": palla, linea
centrale, punteggi, racchetta avversaria e capsule in volo sono grigi e palla, racchetta avversaria,
linea centrale e capsule hanno un alone che scurisce a 1, 2 e 3 pixel dal bordo (distanza = scarto
in x + scarto in y, solo sottrazioni e confronti; la profondità sale da 1 a 3 durante la rampa).
Non c'è un framebuffer, quindi è un'approssimazione con i bordi morbidi: l'alone di `pong_render`
si calcola un ciclo prima del colore (ogni pixel dura 3 cicli), quello delle capsule esce da
`next_render` e `pong_top` lo mette solo sullo sfondo nero. La scia della palla è lunga il doppio
con le immagini grigie della palla; scritta "P1 BULLET!" all'attivazione. Nel bullet time gli
effetti del SID suonano un'ottava sotto e più lenti.
Simulatore dei frame: scenario `bullet`. Il BLASTER spara con **A**, fino a
4 colpi di fila; dietro la racchetta, dal basso, un rettangolino giallo di 3 righe (passo 4) per
colpo nel caricatore: spariscono a ogni colpo e tornano tutti con la ricarica. Il RUSH, mentre
scatta in avanti, lascia tre immagini gialle della racchetta tra la posizione di casa e quella
attuale, più scure verso casa, che sfumano in 15 frame (tre colori fissi, nessuna moltiplicazione);
nella scelta della racchetta il suo segno sono tre immagini attaccate dietro. Il TELEPORT prevede il punto d'arrivo della
palla come nel core Rust e l'animazione dei portali segue la x della palla.
La partita dimostrativa ora è giocata da due CPU come quella del gioco Rust.

**Mosse speciali** (sempre accese in NEXT, CHALLENGE e nelle loro demo; fino alla 4.0.0-beta.19
c'era l'opzione OSD *Super moves*): barra
per giocatore sotto la riserva (tacca al costo, gialla quando una mossa è pronta), mosse e regole
identiche al core Rust (le esegue il firmware di `pong_logic_rv.v`). La mossa spende tutti i
settori pieni della barra (`P_SUPER_COST` ciascuno, al massimo 2) e ha il loro numero come livello;
il 2 è "MAX". Tutte e due si armano per il colpo successivo: STRAIGHT SHOT parte orizzontale con il
boost ×1,5 (×2 al livello 2), RISING STRIKE parte orizzontale e passati i 5/8 del campo (7/8 al
livello 2, contati da chi colpisce) s'impenna a 45 gradi lontano dalla racchetta avversaria. A
schermo, come su PC: con la mossa armata il suo segno giallo accanto alla racchetta (dove va
l'icona del bonus armato), la faccia della racchetta e la barra che lampeggiano e al livello 2 la
racchetta gialla; la scritta "P1 STRAIGHT SHOT!" all'attivazione e al colpo, con "MAX" davanti al
livello 2 (livello armato dalle parole delle mosse, quello del tiro dai bit 12-13); un quadrato
giallo per 12 frame dove RISING STRIKE s'impenna (il bit 14 torna a zero con la mossa in volo).
`pong_top` riconosce l'attivazione dalla barra scesa di almeno mezzo settore nel frame (32 o 64).
Comandi:
- joystick: ↓ ↘ → + **A** = STRAIGHT SHOT, → ↓ ↘ + **A** = RISING STRIKE (→ = verso l'avversario),
  al massimo 0,3 s tra le direzioni e 0,25 s tra l'ultima e **A**;
- paddle e spinner: la manopola gira veloce in giù e torna su, poi **A** = STRAIGHT SHOT; in su e
  di nuovo giù, poi **A** = RISING STRIKE (ogni tratto almeno 30 unità entro 0,3 s);
- l'**A** che chiude il gesto diventa la mossa solo se la mossa può partire, altrimenti resta lo
  scatto (o lo sparo del BLASTER).

Riconoscimento in `move_gesture` (in fondo a `pong_top.v`).

Prima della partita la schermata **HOW TO PLAY** (`M_HOWTO`, in `howto_render.v`), in stile Neo Geo
come quella del gioco Rust: per STRAIGHT SHOT e RISING STRIKE la frase dell'effetto, il gesto del
controllo scelto nell'OSD (*Paddle control*: joystick arcade di tre quarti inclinato ↓ ↘ → e → ↓ ↘,
oppure, con paddle e spinner, la manopola vista dall'alto con la freccia curva della rotazione),
"+", il pulsante **A** rosso e DASH, e a destra un riquadro con la palla che parte dritta o che
s'impenna; sotto il costo (HALF = MOVE, FULL = MAX), la legenda dei pulsanti e PRESS START TO SKIP.
L'animazione gira di continuo con i tempi del gioco Rust: i passi del gesto si accendono uno dopo
l'altro con le freccette gialle, poi A si abbassa e la palla parte. Start o **A** la saltano, dopo
8 s parte da sola. La grafica viene da `tools/gen_howto_assets.py` in tre livelli: le righe dello
schermo che hanno scritte (e le barre del costo), 2 bit per pixel e ogni riga una volta sola, con
una mappa {controllo, riga} -> riga (`howto_text.hex`, `howto_rows.hex`, 8 M10K); 10 figurine 32x32
a codici di colore (`howto_sprites.hex`, 5 M10K), che il renderer colora secondo il passo acceso; il
resto (cornici, freccette, racchetta e palla del tiro) in logica, con le posizioni calcolate una
volta per frame. Due cicli di ritardo, nessun DSP.
Il reset azzera anche i crediti; l'auto-test compare solo all'accensione.
Scanline, maschere e shader sono quelli del MiSTer.

Licenza: il framework `sys/` di Template_MiSTer è GPLv2, quindi anche il core MiSTer lo è
([LICENSE](LICENSE)); l'emulazione del SID in `rtl/sid` ha in parte la licenza CERN-OHL-S v2 (vedi
[rtl/sid/README.md](rtl/sid/README.md)). Il resto del progetto, firmware compreso, è GPL v3 o
successiva (compatibile, perché il framework è GPL v2 "o successiva"): vedi
[THIRD_PARTY.md](../THIRD_PARTY.md). Lo zip della release contiene i testi delle licenze in
`_Arcade/cores/PaddWS_licenses/`.

## Verifica

```powershell
.\mister\sim\run.ps1      # rigenera le tracce e prova il firmware contro le tracce
.\mister\sim\rv\rv.ps1   # pong_logic_rv con Verilator: tracce intere, cicli per tick e per frame
```

1. Firmware: `python tools/gen_mister_fw.py --check` (impronta dei sorgenti) e `paddws-fw-sim`
   (`rust/mister-fw/src/bin/fw_sim.rs`), un emulatore RV32IM con il modello dei registri che esegue
   l'immagine di `rtl/gen` contro tutte le tracce: parole di stato e comandi delle CPU (anche quelle
   con lo spinner e a 128 Hz), ~45 s. Con `--native` lo stesso `Engine` gira sul PC; `--profile`
   conta le istruzioni per funzione. In `sim/run.ps1` e `sim/run.sh` (CI e forge).
2. `pong_logic_rv` con Verilator ([`sim/rv`](sim/rv): `tb_rv_top.v`, `tb_rv.cpp`, `rv.ps1`):
   VexRiscv, RAM, registri e firmware contro le tracce intere (parole e comandi effettivi), ciclo
   per ciclo; `-Traces trace,trace_1p` solo alcune tracce, `-Ticks N` solo i primi tick. Misura i cicli per tick e per frame (4 tick allineati, contro i 26.712
   cicli del vblank); `-Ratio 2` prova il ripiego a 40 MHz. Le 29 tracce richiedono circa un'ora
   (6 alla volta). `trace_bul_wait` usa un modello a parte con i parametri a 128 Hz.
3. Simulazione del core completo con Icarus ([`sim/tb_pong_top.v`](sim/tb_pong_top.v)): non è più
   aggiornata alle porte di `pong_top` (la sostituiscono i frame qui sotto).
4. Istantanee dell'intera sequenza con Verilator ([`sim/frames/frames.cpp`](sim/frames/frames.cpp)):
   accensione, gettone, demo, partita a un giocatore fino al GAME OVER, salvate in PPM; altri
   scenari per NEXT, TELEPORT, il muto dell'attract, il vincitore e le demo delle quattro modalità
   (`demo`: un gettone, nessuno Start, l'OSD cambia modalità a ogni giro), le mosse speciali
   (`supers`: HOW TO PLAY, mezzelune e RISING STRIKE con l'impennata; `howto`: la sola schermata HOW
   TO PLAY, un giro dell'animazione col joystick, uno con lo spinner e un pezzo col paddle,
   `howto_*.ppm`, circa 260 frame) e il BULLET (`bullet`: il giocatore lo usa
   con la palla in arrivo ancora nella metà della CPU, `bul_*.ppm` ogni 4 frame da armato, nel
   bullet time fino alla ribattuta e poco dopo), CHALLENGE (`challenge`: una schermata per modo e,
   nella prima presentazione, le racchette degli avversari di tutti i livelli, `ch_lvl1..7.ppm`, e
   due rivolte a destra), GHOST (`ghost`: con GHOST in volo nessun pixel di coda attorno alla palla,
   `gh*.ppm`), la classifica sulla SD (`nvram`: un `hps_io` finto manda tre file da
   scartare e uno buono e rilegge ogni volta l'immagine, `nv_scores.ppm`) e il finale della
   CHALLENGE (`ending`: livello 1 vinto con la voce YOU WIN, poi l'ultimo livello e il finale, con le
   parti lunghe accorciate dal contatore, `end_*.ppm`, e Start in THE END che porta alle iniziali). `sim\frames\frames.ps1
   [scenario] [frame ...]` ricompila il modello se l'RTL è cambiato e lo esegue (con il processore
   a 60 MHz più lento di prima; `--threads` e `-O3` non lo rendono più veloce). Al primo frame di partita salva un
   checkpoint (`--savable`): le esecuzioni seguenti con lo stesso eseguibile ripartono da lì se i
   frame richiesti vengono dopo, e una ricompilazione lo invalida.
5. Sintesi in Quartus, prova su DE10-Nano (superata con la logica in Verilog; da rifare con il
   RISC-V).

## Toolchain (da installare in `C:\DEV\@Compiler`)

- **Quartus Prime Lite 17.0.2** con il supporto Cyclone V: la versione usata dai core MiSTer.
- **Template_MiSTer** (framework `sys/` ufficiale) come base del progetto.
- Rust con il target `riscv32im-unknown-none-elf` (toolchain portable, `tools\rust-env.ps1`), solo
  per rigenerare il firmware con `tools/gen_mister_fw.py`.
- Simulatore: **OSS CAD Suite** (Icarus Verilog, Verilator, Yosys) in `C:\DEV\@Compiler\oss-cad-suite`
  — installata. Per Verilator serve `VERILATOR_ROOT=...\oss-cad-suite\share\verilator`.

Quartus 17.0.x è la versione richiesta dal README ufficiale di Template_MiSTer: le versioni più
nuove non portano vantaggi sulla Cyclone V della DE10-Nano e rendono incompatibili i file di
progetto. Il download dal sito Altera richiede il login: va scaricato a mano.
