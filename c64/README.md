[<img src="../docs/flags/it.svg" alt="" height="14"> **Italiano**](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> English](README.en.md)

# PADD WS – versione Commodore 64

PADD WS per C64 PAL e NTSC, su cartuccia EasyFlash. Gioca la stessa partita del core Rust
([`rust/core`](../rust/core)) bit per bit: campo 320×200, un tick per frame (50 Hz, sull'NTSC 60), aritmetica
Q16.16 a 32 bit in 6502 identica a `fixed.rs` e gli stessi parametri delle altre versioni
(`Tuning::c64()`). Ci sono Classic, EVO, NEXT con le mosse speciali e la scalata (sfidanti, WINS,
allenamento, classifica e sblocchi salvati nella flash), il boss segreto OMEGA, il jukebox, il
singolo, la CPU, l'attract (senza demo) e le musiche del SID. Il logo nel menu di NEXT non c'è:
resta MAIN MENU.

Ci sono due cartucce, una per il PAL e una per l'NTSC (con i parametri del core a 60 Hz). Quella
NTSC finora è stata provata solo in VICE.

### Campo girato

Una seconda versione, su un'altra cartuccia, gira il campo di 90 gradi: le racchette stanno in
basso e in alto, il campo è largo 240 pixel (30 colonne) e alto 200, e nelle 10 colonne a destra
c'è la fascia con nomi, punteggi, riserve, barre del SUPER e punti. Così le astronavi sono in alta
risoluzione: il bianco a un pixel sopra uno strato multicolore, quattro sprite per racchetta, gli
stessi per la racchetta in alto e per quella in basso (si spostano a metà schermo). La partita è
quella del core con `Tuning::c64_rotated()`: la palla attraversa il campo in circa l'86% del tempo
dell'altra cartuccia (il campo è più corto: alla stessa velocità in pixel sarebbe stata troppo
rapida, allo stesso tempo sembrava lenta), e le racchette attraversano i loro 240 pixel nello stesso tempo in cui lì
attraversano i 200 (sull'NTSC lo stesso, a 60 tick al secondo: `Tuning::c64_rotated_ntsc()`). Menu e schermate
fuori dalla partita sono quelli di sempre, ma dove compare una racchetta (scelta, VS, presentazione
di OMEGA, finale) c'è l'astronave della partita. Il salto del TELEPORT si scompone a colonne invece che a righe,
con una maschera di caratteri sopra l'astronave. Rispetto all'altra cartuccia manca la rotazione della
racchetta con il SUPER armato, la TWIST ha tre inclinazioni invece di sette e STRAIGHT SHOT accelera la
palla al più di 1,5 volte (invece di 2), come RISING STRIKE. Si costruisce con `-Rotated` e si verifica con
`--rotated` (sotto).

## Avviare

`paddws-horizontal-pal.crt` e `paddws-horizontal-ntsc.crt` sono nella release
(`paddws-X.Y.Z-c64.zip`), insieme a quelle del campo girato, `paddws-vertical-pal.crt` e
`paddws-vertical-ntsc.crt`; dopo la compilazione sono `c64\build\paddws.crt`,
`c64\build\ntsc\paddws.crt`, `c64\build\rotated\paddws.crt` e
`c64\build\rotated\ntsc\paddws.crt`. Il nome scritto dentro ognuna (lo mostrano VICE e il C64
Ultimate) dice quale è: `PADD WS HORIZONTAL PAL`, `PADD WS VERTICAL NTSC` e così via. Si
monta in VICE o sul C64 Ultimate, oppure si scrive in una EasyFlash con EasyProg, e parte
all'accensione. Perché la classifica resti, il `.crt` deve essere scrivibile; in VICE:

```
x64sc -easyflashcrtwrite -cartcrt paddws-horizontal-pal.crt
```

## Comandi

- Joystick nella porta 2 (giocatore sinistro) e nella porta 1 (destro), oppure una coppia di
  paddle nella porta 1.
- Su e giù muovono la racchetta (doppio tocco: rapida). Verso l'avversario si scatta in avanti
  (e si spara con il BLASTER), dalla parte opposta si rientra. Nel campo girato la racchetta va a
  destra e a sinistra, e verso l'avversario è su per chi gioca in basso, giù per chi gioca in alto;
  le mosse speciali invece si fanno per tutti e due come il giocatore sinistro dell'altra
  cartuccia (↓ ↘ → e → ↓ ↘ + fuoco).
- Fuoco: in NEXT usa il bonus selezionato, che cambia da solo ogni secondo; in EVO scatta.
- Mosse speciali di NEXT, con avanti verso l'avversario: ↓ ↘ → + fuoco STRAIGHT SHOT,
  → ↓ ↘ + fuoco RISING STRIKE. Con i paddle non ci sono: il pulsante scatta e i bonus si
  scelgono e si usano con `F` / `C` (sinistro) e `.` / `-` (destro).
- Tastiera: **5** gettone, fuoco, **RETURN**, **SPAZIO** o **1** Start, **RUN/STOP** pausa (dal
  menu torna all'attract), **Q** torna al menu.

Il menu (joystick o cursori) ha GAME, PLAYERS (solo in CLASSIC ed EVO; in NEXT, dopo lo sblocco,
OPPONENT per l'allenamento), DIFFICULTY, CONTROL, FREE PLAY, ATTRACT SOUND, VOLUME (anche per le
voci) e BORDER, più JUKEBOX quando è sbloccato. Le regole sono in [docs/it/come-si-gioca.md](../docs/it/come-si-gioca.md).

## Compilare

Servono cc65 (ca65 e ld65) in `C:\DEV\@Compiler\cc65` e Python (quello di `.venv`, se c'è) per
`tools/make_crt.py`. VICE, in `C:\DEV\@Compiler\vice`, serve solo per provarla. Con
`PADDWS_COMPILERS` si usa un'altra cartella al posto di `C:\DEV\@Compiler`.

```powershell
.\c64\build.ps1                 # c64\build\paddws.crt
.\c64\build.ps1 -Ntsc           # c64\build\ntsc\paddws.crt
.\c64\build.ps1 -Rotated        # campo girato: c64\build\rotated\paddws.crt (con -Ntsc l'NTSC)
.\c64\shot.ps1 boot.png         # avvia la cartuccia in VICE senza finestra e salva la schermata
```

Su Linux: `sh c64/build.sh` (con `--ntsc` la versione NTSC, con `--rotated` il campo girato; ca65,
ld65 e python3 nel PATH).

Oltre alla cartuccia, in `c64\build` restano `paddws.prg` con le etichette (`paddws.lbl`) e la
mappa (`paddws.map`), il finale della scalata (`paddws.prg.end`), il banco di OMEGA (`paddws.prg.omega`) e i file voce
`voice0-7.prg` (il 7 è OMEGA).
Servono al banco di prova: il `.prg` da solo non parte, gira solo dalla cartuccia.

I file di `c64/gen/` sono generati e stanno nel repository: `tools/gen_c64_assets.py` per grafica,
musica e voci, `paddws-c64 params` per `params.inc` (anche quelli del campo girato),
`tools/gen_c64_rotated.py` per gli altri file del campo girato in `c64/gen/rotated` (dopo
`gen_c64_assets.py`: parte dai suoi file). Non si modificano a mano. Le astronavi del campo girato
si disegnano nell'editor delle racchette, piattaforma "C64 girato"
(`tools/c64_editor.py --paddle-c64h`), su due livelli: il bianco hires e il multicolore sotto.

Le immagini del C64 si ritoccano a mano con `tools/c64_editor.html`, che si apre in Edge o Chrome
senza installare nulla: bitmap hires e multicolor, caratteri, sprite, griglia delle celle con
l'origine a scelta, celle non valide in rosso; *File → Importa e converti* trasforma un'immagine
qualsiasi (anche quella di riferimento) in uno di questi modi, con retino e colori a scelta.
Legge e scrive i PNG a palette dei generatori
(indice = colore del C64), per esempio i ritratti di `assets/characters/portraits/c64` (hires) e
`c64mc` (multicolor, quelli che usa il C64: scelta, VS e sfilata), e ci lascia
un segno: `tools/gen_portraits.py` non sovrascrive più quei file (per rifarne uno dalla sorgente lo
si cancella). Dopo il ritocco: `tools/gen_c64_portraits.py`, poi la build. Dentro VS Code (browser
integrato o Simple Browser) la pagina non può aprire né salvare file: si avvia
`.venv\Scripts\python tools\c64_editor.py` e si apre `http://127.0.0.1:8064/`, che lavora sui PNG
del repository.

Per le schermate ci sono build che partono subito con una partita:

```powershell
.\c64\build.ps1 -Name autostart -Define AUTOSTART     # EVO contro la CPU; con AUTONEXT NEXT, con AUTOCHALLENGE la scalata (TRAINTEST=n l'allenamento)
.\c64\build.ps1 -Name autoend -Define ENDTEST         # il finale della scalata (ENDOMEGA: dopo OMEGA battuto)
.\c64\build.ps1 -Name warning -Define WARNTEST       # scalata a HARD, dopo il GUARDIAN subito l'allarme e OMEGA (OMFORM=n: dalla forma n)
.\c64\build.ps1 -Name unlock -Define UNLOCKTEST,OMEGATEST  # allenamento, OMEGA e jukebox sbloccati
.\c64\build.ps1 -Name juke -Define JUKETEST,JUKETRACK=8 # subito il jukebox, con il brano n (da 0)
.\c64\build.ps1 -Name menu3 -Define MENUTEST=3        # il menu con OPPONENT a 3 (UNLOCKTEST: allenamento sbloccato)
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
cargo run --release -p paddws-c64 -- ui               # scene e menu, voci della scalata, WINS, allenamento, classifica e sblocco nella flash
cargo run --release -p paddws-c64 -- frames           # cicli di ogni frame (attract, partite, finale)
```

Con `--ntsc` prima del comando (`paddws-c64 --ntsc frames`) i passi valgono per la cartuccia
NTSC, compilata prima con `-Ntsc`; con `--rotated` per quella del campo girato (anche insieme). Sono gli stessi passi della GitHub Action `C64`. In più: `ending` gioca solo il finale della
scalata, `profile` dà i cicli per routine, `--build DIR` usa un'altra cartella di build e
`game --ticks N` cambia la durata delle partite (5 minuti di default). Per confrontare i cicli
del banco di prova con quelli di VICE: `tools\c64_vice_frames.py` cattura i frame di una build
di prova e `paddws-c64 --prg NOME vice FILE` li riesegue; con `--frametest` lo stesso strumento
conta in VICE i frame oltre il tempo di una build con `FRAMETEST`.

Prima di toccare il codice di disegno o di scena conviene registrare un golden test, che `game`
non copre: `PADDWS_C64_GOLDEN=record:FILE paddws-c64 frames` salva per ogni frame un'impronta di
quello che si vede e si sente (schermo, colori, sprite, SID) con il raster congelato, e dopo la
modifica `PADDWS_C64_GOLDEN=check:FILE` dice il primo frame diverso. Con `PADDWS_C64_PICK_RAW=1`
le partite sono quasi tutte BLASTER (i colpi a schermo).

## Sorgenti

- `src/main.s` — punto d'ingresso: un solo modulo, che include gli altri file.
- `src/game.s`, `src/math.s` — la partita (`Match` di `game.rs`) e l'aritmetica Q16.16 con il
  generatore.
- `src/next.s`, `src/supers.s`, `src/pick.s` — NEXT, le mosse speciali, le scelte prima della
  partita e la schermata HOW TO PLAY.
- `src/cpu.s` — la CPU (`cpu.rs`).
- `src/omega.s`, `src/jukebox.s` — OMEGA in partita (rete, nome della forma, musica a sezioni) e
  il jukebox, nel banco di OMEGA della cartuccia.
- `src/challenge.s`, `src/intro.s`, `src/ending.s` — CHALLENGE con la classifica, le entrate
  degli avversari nella presentazione, e il finale.
- `src/play.s` — ciclo dei frame, scene, menu, gettoni.
- `src/attract.s`, `src/video.s`, `src/input.s` — attract, grafica, comandi.
- `src/rot_video.s`, `src/rot_shots.s` — il campo girato: sprite, interrupt della mezzeria, campo,
  fascia dell'HUD e laser del BLASTER (al posto delle routine di `video.s` e `pick.s` con lo
  stesso nome).
- `src/sid.s` — il player del SID, tradotto da `mister/rtl/pong_sid.v`.
- `src/voice.s`, `src/voice.inc` — i file voce della scalata (si assemblano a parte, uno per
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
- **Tempo del frame.** Un frame PAL dura 19.656 cicli, uno NTSC 17.095. In partita l'obiettivo è
  restare entro il 90% (17.700 e 15.400); fuori partita basta il frame intero. `paddws-c64 frames`
  conta i cicli veri dall'interrupt della riga 250, compresi quelli che il VIC-II ruba per le
  righe dei caratteri e per gli sprite (modello tarato su VICE), e fallisce se un frame fuori
  partita supera il suo tempo o se in partita troppi superano il 90%. Passi della musica ed
  effetti sonori partono a inizio frame, a un'ora fissa del raster; sprite e riserve si rifanno a
  ogni frame. Il lavoro lungo si divide su più frame o aspetta il frame dopo guardando il raster.
  Sul PAL nessun frame di partita supera il 90%; sull'NTSC ne restano pochi (circa tre su
  mille nel caso peggiore: raffiche del BLASTER con il salto del TELEPORT nel bullet time), e se
  uno supera il frame quello dopo parte subito e recupera.
- **Set di caratteri e sprite quasi finiti.** Dei 256 caratteri ne restano liberi pochi (un
  carattere nuovo ne sostituisce uno dove l'altro non serve, e `tools/gen_c64_assets.py` lo
  controlla) e gli 8 sprite sono tutti usati. Le lettere non sono nella cartuccia: all'avvio si
  copiano dalla ROM dei caratteri del C64, e da lì si fanno anche quelle grandi. Nelle partite
  NEXT i caratteri 64-127 (le lettere grandi e il vuoto dopo) servono ai laser del BLASTER, e
  tornano al loro posto a fine partita: una schermata nuova che li usi li deve rifare. Sopra
  punteggi, barre, riserve e riga di metà campo il laser non copre: il programma fonde al volo il
  suo tratto con il carattere che c'è sotto, che tiene il suo colore.
- **BASIC e KERNAL spenti** (`$01 = $35`): sotto le loro ROM ci sono dati e variabili, e la RAM sotto
  l'I/O si legge e si scrive con `$01 = $34`.
- **Bordo e sfondo** (`$D020`, `$D021`) si scrivono solo quando il colore cambia: ogni scrittura
  mentre il colore è a schermo lascia un punto grigio (il "grey dot") sui VIC-II più recenti.
- **ca65:** dentro un `.proc` le costanti definite fuori si scrivono `::NOME` nelle direttive come
  `.repeat`; i salti oltre ±128 byte usano `jne`, `jeq`, `jcs`, `jcc`.
- **Flash.** La classifica si scrive con i comandi dell'Am29F040 della EasyFlash, senza EAPI: una
  EasyFlash 3 o una cartuccia con un'altra flash vorrebbero l'EAPI. Se la flash non si lascia
  scrivere, il programma se ne accorge e fino allo spegnimento non ci prova più.
