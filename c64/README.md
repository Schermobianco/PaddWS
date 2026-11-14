[<img src="../docs/flags/it.svg" alt="" height="14"> **Italiano**](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> English](README.en.md)

# PADD WS – versione Commodore 64

PADD WS per C64 PAL, su cartuccia EasyFlash. Gioca la stessa partita del core Rust
([`rust/core`](../rust/core)) bit per bit: campo 320×200, un tick per frame a 50 Hz, aritmetica
Q16.16 a 32 bit in 6502 identica a `fixed.rs` e gli stessi parametri delle altre versioni
(`Tuning::c64()`). Ci sono Classic, EVO, NEXT con le mosse speciali, il singolo, la CPU,
CHALLENGE con la classifica salvata nella flash, l'attract e le musiche del SID.

Solo PAL (NTSC per ora no). Finora è stata provata in VICE, non ancora su un C64 vero.

## Avviare

`paddws.crt` è nella release (`paddws-X.Y.Z-c64.zip`) o in `c64\build` dopo la compilazione. Si
monta in VICE o sul C64 Ultimate, oppure si scrive in una EasyFlash con EasyProg, e parte
all'accensione. Perché la classifica resti, il `.crt` deve essere scrivibile; in VICE:

```
x64sc -easyflashcrtwrite -cartcrt paddws.crt
```

## Comandi

- Joystick nella porta 2 (giocatore sinistro) e nella porta 1 (destro), oppure una coppia di
  paddle nella porta 1.
- Su e giù muovono la racchetta (doppio tocco: rapida). Verso l'avversario si scatta in avanti
  (e si spara con il BLASTER), dalla parte opposta si rientra.
- Fuoco: in NEXT usa il bonus selezionato, che cambia da solo ogni secondo; in EVO scatta.
- Mosse speciali di NEXT, con avanti verso l'avversario: ↓ ↘ → + fuoco STRAIGHT SHOT,
  → ↓ ↘ + fuoco RISING STRIKE. Con i paddle non ci sono: il pulsante scatta e i bonus si
  scelgono e si usano con `F` / `C` (sinistro) e `.` / `-` (destro).
- Tastiera: **5** gettone, fuoco, **RETURN**, **SPAZIO** o **1** Start, **RUN/STOP** pausa (dal
  menu torna all'attract), **Q** torna al menu.

Il menu (joystick o cursori) ha GAME, PLAYERS, DIFFICULTY, CONTROL, FREE PLAY, ATTRACT SOUND,
VOLUME e BORDER. Le regole sono in [docs/it/come-si-gioca.md](../docs/it/come-si-gioca.md).

## Compilare

Servono cc65 (ca65 e ld65) in `C:\DEV\@Compiler\cc65` e Python (quello di `.venv`, se c'è) per
`tools/make_crt.py`. VICE, in `C:\DEV\@Compiler\vice`, serve solo per provarla. Con
`PADDWS_COMPILERS` si usa un'altra cartella al posto di `C:\DEV\@Compiler`.

```powershell
.\c64\build.ps1                 # c64\build\paddws.crt
.\c64\shot.ps1 boot.png         # avvia la cartuccia in VICE senza finestra e salva la schermata
```

Su Linux: `sh c64/build.sh` (ca65, ld65 e python3 nel PATH).

Oltre alla cartuccia, in `c64\build` restano `paddws.prg` con le etichette (`paddws.lbl`) e la
mappa (`paddws.map`), il finale di CHALLENGE (`paddws.prg.end`) e i file voce `voice0-6.prg`.
Servono al banco di prova: il `.prg` da solo non parte, gira solo dalla cartuccia.

I file di `c64/gen/` sono generati e stanno nel repository: `tools/gen_c64_assets.py` per grafica,
musica e voci, `paddws-c64 params` per `params.inc`. Non si modificano a mano.

Per le schermate ci sono build che partono subito con una partita:

```powershell
.\c64\build.ps1 -Name autostart -Define AUTOSTART     # EVO contro la CPU; con AUTONEXT NEXT, con AUTOCHALLENGE CHALLENGE
.\c64\build.ps1 -Name autoend -Define ENDTEST         # il finale di CHALLENGE
.\c64\build.ps1 -Name intro3 -Define INTROTEST=3      # la presentazione del livello 3 (anche CONTTEST: il continue)
.\c64\build.ps1 -Name ft -Define AUTOSTART,FRAMETEST  # frame oltre il tempo, cifra rossa in basso a destra (FRAMESTOP: si ferma al primo)
.\c64\shot.ps1 out.png -Prg autostart                # schermata dopo -Cycles cicli (15 milioni di default)
```

`shot.ps1` accetta anche `-Sid 8580`, `-Wav out.wav` (registra il suono, a velocità normale) e
`-Write` (la classifica scritta resta nel `.crt`).

## Verificare

Il banco di prova (`rust/c64`, programma `paddws-c64`) carica `paddws.prg`, le etichette e la
cartuccia in un emulatore 6502, chiama le routine per etichetta, confronta i risultati con il core
Rust e conta i cicli. Del C64 emula quello che serve: la RAM sotto l'I/O, la riga del raster, il
timer A del CIA2 con l'NMI e la EasyFlash con i suoi comandi della flash. Prima va compilata la
cartuccia.

```powershell
. .\tools\rust-env.ps1; cd rust
cargo run --release -p paddws-c64 -- params --check   # c64\gen\params.inc in pari con il core (senza --check lo riscrive)
cargo run --release -p paddws-c64 -- math             # aritmetica e generatore contro fixed.rs e rng.rs
cargo run --release -p paddws-c64 -- game             # partite intere, stato confrontato con il core a ogni tick
cargo run --release -p paddws-c64 -- sid              # player del SID contro quello Verilog e quello Rust
cargo run --release -p paddws-c64 -- ui               # scene e menu, voci di CHALLENGE, classifica nella flash
cargo run --release -p paddws-c64 -- frames           # cicli di ogni frame (attract, demo, partite, finale)
```

Sono gli stessi passi della GitHub Action `C64`. In più: `ending` gioca solo il finale di
CHALLENGE, `profile` dà i cicli per routine, `--build DIR` usa un'altra cartella di build e
`game --ticks N` cambia la durata delle partite (5 minuti di default).

## Sorgenti

- `src/main.s` — punto d'ingresso: un solo modulo, che include gli altri file.
- `src/game.s`, `src/math.s` — la partita (`Match` di `game.rs`) e l'aritmetica Q16.16 con il
  generatore.
- `src/next.s`, `src/supers.s`, `src/pick.s` — NEXT, le mosse speciali, le scelte prima della
  partita e la schermata HOW TO PLAY.
- `src/cpu.s` — la CPU (`cpu.rs`).
- `src/challenge.s`, `src/intro.s`, `src/ending.s` — CHALLENGE con la classifica, le entrate
  degli avversari nella presentazione, e il finale.
- `src/play.s` — ciclo dei frame, scene, menu, gettoni.
- `src/attract.s`, `src/video.s`, `src/input.s` — attract, grafica, comandi.
- `src/sid.s` — il player del SID, tradotto da `mister/rtl/pong_sid.v`.
- `src/voice.s`, `src/voice.inc` — i file voce di CHALLENGE (si assemblano a parte, uno per
  avversario).
- `src/crt.s`, `src/unpack.s`, `src/ef.s`, `src/ef.inc` — avvio della cartuccia e accesso alla
  flash.
- `paddws.cfg` — la mappa della memoria per ld65, con il commento su chi usa cosa.
- `test/sid_reference.txt` — le scritture del SID del player Verilog, per `paddws-c64 sid`.

## Limiti da conoscere

- **Stessa logica del core.** Ogni modifica a `rust/core` va portata anche qui (e sul MiSTer):
  `paddws-c64 game` lo verifica tick per tick.
- **Memoria quasi finita.** La pagina zero è piena e nel programma restano pochi byte liberi:
  il codice nuovo va di solito nella cartuccia, da copiare in RAM quando serve (come le mosse
  speciali, la classifica e il finale). Lo spazio libero si legge in `c64\build\paddws.map`.
- **Variabili temporanee condivise.** `m_t` e `ptr` non tengono un valore attraverso una `jsr`.
- **18.000 cicli per frame.** `paddws-c64 frames` fallisce se un frame li supera. Il suo modello del
  raster (58 cicli per riga) è approssimato: con frame vicini al limite conviene controllare anche
  in VICE. Il lavoro lungo si divide su più frame o aspetta il frame dopo guardando il raster.
- **Set di caratteri e sprite finiti.** I 256 caratteri sono tutti usati (un carattere nuovo
  ne sostituisce uno dove l'altro non serve, e `tools/gen_c64_assets.py` lo controlla) e gli 8
  sprite pure.
- **BASIC e KERNAL spenti** (`$01 = $35`): sotto le loro ROM ci sono dati e variabili, e la RAM sotto
  l'I/O si legge e si scrive con `$01 = $34`.
- **Bordo e sfondo** (`$D020`, `$D021`) si scrivono solo quando il colore cambia: ogni scrittura
  mentre il colore è a schermo lascia un punto grigio (il "grey dot") sui VIC-II più recenti.
- **ca65:** dentro un `.proc` le costanti definite fuori si scrivono `::NOME` nelle direttive come
  `.repeat`; i salti oltre ±128 byte usano `jne`, `jeq`, `jcs`, `jcc`.
- **Flash.** La classifica si scrive con i comandi dell'Am29F040 della EasyFlash, senza EAPI: una
  EasyFlash 3 o una cartuccia con un'altra flash vorrebbero l'EAPI. Se la flash non si lascia
  scrivere, il programma se ne accorge e fino allo spegnimento non ci prova più.
