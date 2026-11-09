# PADD WS – versione Rust

Versione nativa del gioco: un unico eseguibile (font, suoni e grafica dell'attract inclusi), per
Windows, Linux x86_64, Linux ARM64 e ARM a 32 bit (Raspberry Pi).

## Compilare ed eseguire

Windows, con la toolchain portable in `C:\DEV\@Compiler` (vedi `tools/rust-env.ps1`):

```powershell
. .\tools\rust-env.ps1          # attiva Rust e MinGW nella sola sessione corrente
cd rust
cargo run --release              # oppure: cargo build --release -> target\release\paddws.exe
cargo test
```

Linux (Debian/Ubuntu/Raspberry Pi OS):

```sh
sudo apt install libx11-dev libxi-dev libgl1-mesa-dev libasound2-dev libudev-dev
cd rust && cargo run --release
```

Gli eseguibili delle release (Windows, Linux x86_64, ARM64 e ARM a 32 bit) li costruisce la
macchina virtuale *forge* con `build_onforge.bat` ([tools/forge](../tools/forge/README.md)), insieme al core
per MiSTer, con la data di compilazione nel nome come vuole la convenzione MiSTer (es.
`PaddWS_20261028.rbf`), e al suo `PaddWS.mra`, insieme in `PaddWS_MiSTer_AAAAMMGG.zip`. La GitHub
Action `Rust`, lanciata a mano da `build_ongithub.bat`, fa gli stessi controlli e pacchetti.

## Uso

Stessi comandi e stesso `padd_config.json` della versione Python (il file viene cercato
accanto all'eseguibile, nella cartella corrente e in quella superiore).

```
paddws [--config FILE] [--fullscreen | --windowed] [--crt | --no-crt] [--width N] [--height N] [--version]
```

Con `--width 320 --height 240` si gioca la stessa logica del core MiSTer.

### Mouse come spinner

Con `mouse.spinner: true` (o **MOUSE SPINNER: ON** nel menu, che lo salva) il mouse fa da
manopola del giocatore di sinistra, su PC e nel browser: `game/src/mouse.rs` cattura il cursore
(`set_cursor_grab`: nella finestra su PC, Pointer Lock nel browser) e passa il movimento verticale
di ogni frame a `Encoders::mouse` (`game/src/encoder.rs`), che lo tratta come un encoder ottico:
stessi eventi del cabinato (rotazione, click, SELEZIONA, USA), quindi stessi menu, stessa racchetta
(`top_offset`) e stessi gesti delle mosse speciali (`gesture.track`). Sensibilità:
`mouse.travel_pixels` (pixel di mouse per tutta la corsa, default 1000). Con gli encoder del
cabinato attivi l'opzione non conta; quando è accesa il mouse non fa da dito nel browser.

### Menu a ruota

Il menu principale (`Menu` in `game/src/scenes.rs`) è una ruota verticale: la voce scelta al
centro, gialla e a 40 px, le altre sopra e sotto su un rullo (circa 0,30 rad per voce), a 30 px le
vicine e a 20 le altre, sempre più scure verso i bordi. Lo scorrimento da una voce all'altra dura
0,18 s e rallenta all'arrivo; la ruota si ferma alla prima e all'ultima voce. Su e giù (tasti,
gamepad, manopola dell'encoder o mouse come spinner) la girano, sinistra e destra cambiano il
valore, Invio, Start, A o il click confermano. Sul touch si trascina col dito; un tocco sulla voce
al centro la cambia o la usa, un tocco su un'altra la porta al centro.

### Gamepad e stick arcade

`game/src/gamepad.rs`: con [gilrs](https://crates.io/crates/gilrs) su Windows, Linux e Raspberry
Pi, con la Gamepad API del browser nel web (`web/gamepad.js`, plugin miniquad: gilrs nel browser
richiederebbe wasm-bindgen). Il primo gamepad collegato è del giocatore di sinistra, il secondo di
quello di destra; da soli con un gamepad solo è di chi gioca, da qualunque lato. I tasti restano.

| comando | in partita | nei menu |
|---|---|---|
| levetta o croce | su e giù muovono la racchetta (doppio tocco = rapido) | su, giù, sinistra, destra |
| **A** | scatto in avanti (e mosse speciali) | conferma |
| **B** | seleziona il bonus (NEXT) | indietro |
| **C** (X o Y sui gamepad) | usa il bonus (NEXT) | |
| **Start** | pausa (in pausa A riprende, B torna al menu) | Start, conferma |
| **Select** | gettone | gettone |

- La levetta analogica diventa una direzione a 8 vie con una zona morta del 35% (ogni direzione
  occupa 45°): le diagonali delle mosse speciali si riconoscono come sullo stick arcade. Gli stick
  arcade e le schede encoder dei cabinati senza levetta analogica (croce digitale, "cappello" o
  assi digitali) vanno bene così come sono.
- Mosse speciali: le mezzelune del core MiSTer, ↓ ↘ → + **A** (STRAIGHT SHOT) e → ↓ ↘ + **A**
  (RISING STRIKE), con → verso l'avversario (`gesture::Stick`, stessi tempi: 0,3 s tra le
  direzioni, 0,25 s per **A**). La HOW TO PLAY mostra i comandi del joystick quando l'ultimo
  comando usato è stato un gamepad.
- Nei menu, nelle scelte dei bonus e della racchetta, nelle iniziali e nelle schermate della
  CHALLENGE i gamepad valgono come i tasti del loro giocatore (`game/src/input.rs`: ogni scena
  dice quale tasto fa ciascun comando); le direzioni tenute si ripetono. In CHALLENGE lo Start del
  gamepad del lato libero è quello di un nuovo sfidante.
- Pulsanti: per nome con la mappatura di SDL inclusa in gilrs (A in basso, B a destra, X e Y
  valgono C); le schede senza mappatura per numero: 1 A, 2 B, 3 C, 9 Select, 10 Start.
- Linux e Raspberry Pi: servono `libudev` (c'è in Raspberry Pi OS; per compilare `libudev-dev`)
  e l'accesso a `/dev/input/event*` (l'utente nel gruppo `input`, come `pi` di default).
- Nel browser il gamepad compare dopo la pressione di un suo pulsante, e solo nelle pagine
  sicure (https o `localhost`).

### Finale della CHALLENGE

`game/src/ending_ui.rs`: battuto l'ultimo avversario, al posto della schermata del livello
superato parte il finale, in circa 57 s, poi le iniziali della classifica (Start salta tutto).
Solo bianco, giallo e rosso, senza sfumature (le scintille si diradano invece di scurirsi).

1. CONGRATULATIONS! lampeggiante e, dopo un secondo, YOU WIN! con la sua voce (3,5 s).
2. La sfilata dei 7 avversari, uno al secondo con le racchette vere e il nome; mezzo secondo dopo
   il timbro rosso DEFEATED (9 s).
3. Il punteggio: SCORE che sale in 3 s, poi CHAMPION BONUS (il premio dell'ultimo livello,
   `Score::win_bonus`, vittoria e partita perfetta) e TOTAL (9 s). Il core non ha un premio di
   fine gioco a parte.
4. YOU ARE THE PADD WS CHAMPION con i fuochi d'artificio: anello, salice, palma, crisantemo a due
   colori, crepitio e cometa che si divide, ognuno con il razzo che sale e la gravità (7 s).
5. I titoli di coda, a 70 unità al secondo, poi THE END.

Musica: la canzone `ending` della ROM del SID se c'è, altrimenti `champion`: le canzoni si cercano
per nome in `sid_music.vh` (`Song::number`), così una canzone nuova non sposta le altre. La voce
"YOU WIN!" (`assets/sounds/voice/you_win.wav`) si sente anche quando si vince una partita contro
la CPU (Classic, EVO, NEXT, livelli della CHALLENGE), insieme alla scritta del GAME OVER, quando
nessun'altra voce parla; all'ultimo livello la dice il finale. Se un giocatore vince senza punti
dell'avversario (anche in due, mai la CPU) la scritta e la voce sono PERFECT
(`assets/sounds/voice/perfect.wav`): da sola al posto di YOU WIN, o al posto di GAME OVER sopra chi
ha vinto.

### Contro il computer

Nel menu **PLAYERS** passa da TWO a VS CPU a ONE: con VS CPU il giocatore di destra è il computer
(`core/src/cpu.rs`), in Classic, EVO e NEXT; in NEXT sceglie da solo i suoi bonus. Il livello è
quello di DIFFICULTY: EASY insegue la palla e ne manca circa una su cinque, NORMAL, HARD ed EXPERT
prevedono il punto d'arrivo con meno errori. Con due CPU, in Classic a NORMAL si arriva in media a
9 colpi per punto, a EXPERT a 42.

### NEXT (anteprima)

Modalità a due giocatori con bonus, scelta dal menu (GAME TYPE: CLASSIC, EVO, NEXT). Prima della
partita ognuno sceglie 3 bonus su 5 (P1: W/S e C, P2: frecce e -; dopo 10 s vale la scelta
predefinita). In partita le capsule partono dalla mezzeria e si raccolgono toccandole; contengono
uno dei bonus scelti da chi le riceve, o raramente il SUPER.

| | seleziona | attiva | scatto in avanti |
|---|---|---|---|
| P1 | F | C | D |
| P2 | . | - | freccia sinistra |

Bonus: TELEPORT, SMASH, SLOW, CURVE, GHOST e SUPER (animazione a caso tra rotazione della
racchetta, hit-stop e cometa). `paddws-trace --bonus-stats 60` misura l'efficacia di ognuno in
partite tra due CPU (tiro col bonus vincente contro tiro normale); `paddws-trace --teleport-stats
2000` conta le palle prese con TELEPORT a velocità crescenti, fino al SUPER. I valori si regolano
nella sezione `next` di `padd_config.json` (vedi il README principale). Durante NEXT il tasto C
non cambia il filtro CRT. Logica in
`core/src/next.rs`, grafica in `game/src/next_ui.rs`; `paddws-trace --next-stats 200` misura
durata degli scambi e uso dei bonus con i giocatori simulati (Classic e NEXT a confronto).

Giocatori umani simulati (`trace/src/human.rs`, solo per le statistiche): con `--human`
(e `--skill principiante|medio|esperto`) `--next-stats`, `--bonus-stats` e `--paddle-stats`
giocano con loro invece che con la CPU; `paddws-trace --human-stats 60 [--next] [--control
spinner,joystick]` mette ogni profilo contro la CPU a ogni livello (punti vinti, durata di scambi
e partite, palle mancate). Il modello unisce risultati noti del controllo motorio: tempo di
reazione ex-gaussiano, ritardo visivo con proiezione in avanti della palla, errore di stima della
velocità proporzionale alla velocità (Weber) più un errore per rimbalzo, piano rifatto ogni
100-160 ms, rumore motorio proporzionale al movimento, mano sulla manopola a jerk minimo con
durata dalla legge di Fitts, latenza di pressione e rilascio su joystick e tastiera, scatto a
tempo solo con la racchetta all'altezza della palla. I bonus li decide la CPU del gioco.

Verifica: `--screenshot-tour DIR` salva una schermata di ogni scena; `--paddle-gallery DIR` un'immagine
ingrandita di ogni tipo di racchetta (da cui è composta `docs/icons/paddles.png` del README); `--bench SECONDI` gioca da
solo e stampa le statistiche dei frame (`dropped` = frame persi rispetto alla frequenza del
monitor). `PADDWS_NO_GPU_SYNC=1` disattiva l'attesa della GPU dopo ogni frame (diagnostica).

## Struttura

```
core/   paddws-core: logica di gioco no_std, solo interi (Q16.16), tick fisso 240 Hz (50 Hz sul C64),
        RNG xorshift32 con seme, input esplicito per tick, nessuna divisione nel passo
        di simulazione -> modello di riferimento per il core MiSTer
game/   paddws: finestra, grafica, audio e CRT con macroquad (OpenGL 2 / GLES 2)
trace/  paddws-trace: parametri Verilog e vettori di test per il core MiSTer (vedi mister/);
        con --c64 tracce e statistiche della versione C64 (campo 320x200, un tick per frame a 50 Hz)
sid/    paddws-sid: il SID e il player della musica in Rust, per suonare le musiche in tempo reale;
        strumento paddws-sid (render, compare, bench)
vendor/ quad-snd (l'audio di macroquad) con la sorgente continua per la musica: fuori dal workspace
```

Il core è deterministico: stessi parametri, seme e sequenza di `Input` danno la stessa partita
bit per bit (`same_seed_and_inputs_give_identical_matches`). I valori della configurazione,
espressi per tick a 60 Hz come in Python, vengono convertiti una volta sola in `Params`.

## Musica del SID

Le musiche le suona in tempo reale un SID scritto per PADD WS (`sid/`, licenza GPL v3 come il resto, niente reSID):
il port in Rust del player Verilog del MiSTer (`mister/rtl/pong_sid.v`) legge la stessa ROM
(`mister/rtl/gen/sid_music.hex`, da `tools/gen_sid_music.py`) e pilota un SID semplificato con
solo quello che usano le musiche: tre voci, triangolo, dente di sega, impulso a 12 bit e rumore
(LFSR a 23 bit), ADSR con le tabelle dei tempi del chip e il contatore esponenziale, DAC lineari
dell'8580 e il filtro dell'8580, niente forme d'onda combinate, ring o sync. Clock a 1 MHz come nel
core; ogni campione d'uscita è la media dei cicli che copre, come la registrazione del core simulato.

- Filtro: port del modo 8580 di `mister/rtl/sid/sid_filter.sv` (state variable a 12 dB/ottava,
  passa-basso, passa-banda e passa-alto, taglio lineare di circa 6 Hz per passo del registro,
  1/Q = 2^((4 - res)/8)) con la stessa aritmetica intera, un passo ogni 2 cicli del SID; gira solo
  quando ci sono voci nel filtro. Lo usano HAMMER, il titolo e TITAN (comandi e strumenti nel
  docstring di `tools/gen_sid_music.py`).
- Le scritture ai registri sono identiche, frame per frame, a quelle del player Verilog
  (`c64/test/sid_reference.txt`, e `sid/tests/writes_*.txt` al match point e nel bullet time):
  `cargo test -p paddws-sid`.
- Il suono si confronta con le registrazioni del core simulato
  (`..\mister\sim\sid\render.ps1 CARTELLA`, che fuori dagli asset tiene anche le canzoni):
  `cargo run --release -p paddws-sid -- compare theme_hammer CARTELLA\theme_hammer.wav` misura
  livello, RMS per frame da 20 ms, spettro per ottave e correlazione della forma d'onda. Sulle 13
  canzoni il livello resta entro 0,03 dB e la correlazione della forma d'onda tra 0,97 e 0,999;
  con il filtro (titolo, HAMMER, TITAN) lo spettro per ottave resta entro 0,3 dB.
- `paddws-sid render CANZONE OUT.wav [--fast] [--slow]` registra una canzone, `paddws-sid bench`
  misura la CPU (circa 4 ms per secondo di musica su un PC, lo 0,4% di un core, con metà delle
  canzoni nel filtro: senza filtro circa 2,4 ms, il filtro aggiunge circa 2,5-3 ms quando lavora).
- Nativo: la sintesi gira nel thread audio di quad-snd. `vendor/quad-snd` è la quad-snd 0.2.8 di
  macroquad con `set_stream`, una sorgente che il mixer somma agli effetti (`[patch.crates-io]`
  in `Cargo.toml`): un solo dispositivo audio, la stessa latenza degli effetti (circa 90 ms).
- Web: `web/sid_audio.js` (plugin miniquad) chiede i campioni a `paddws_music_fill` con uno
  ScriptProcessor da 2048 campioni nello stesso AudioContext di quad-snd, che parte al primo gesto.
  Funziona anche servito in http dalla rete locale, dove l'AudioWorklet non c'è.
- Tempo: al match point del tema di CHALLENGE il player passa da 50 a 62,5 passi al secondo, nel
  bullet time serve la canzone un passo su due con le frequenze dimezzate. Le regole, da replicare
  sul MiSTer e sul C64, sono in `sid/src/engine.rs` e nel CHANGELOG.
- Gli effetti restano campioni WAV registrati dal core simulato (`assets/sounds/sid/`), con le
  copie rallentate per il bullet time. Non c'è più la scelta dei campioni originali: quelli
  (`python/paddws/sounds/`) servono solo alla versione Python.
- **MUSIC VOLUME** (`game.music_volume`) ed **EFFECTS VOLUME** (`game.effects_volume`), da 0 a
  100 a passi di 10: il guadagno è il quadrato del valore (50% = un quarto, circa -12 dB), così i
  passi si sentono simili. La musica cambia volume subito (`SidMusic::set_gain`), a 0 non suona;
  gli effetti e le voci prendono il volume a ogni `play_sound`. **ATTRACT SOUND** spegne tutto il
  suono dell'attract. Le chiavi di prima (`game.music`, e prima `game.sid_sound` e
  `game.match_music`) diventano `game.music_volume` (0 se una di loro spegneva la musica) e
  spariscono dal file. Nel browser i volumi sono gli stessi del PC anche sui telefoni.

## Fluidità

- Fisica a 240 Hz con interpolazione del rendering.
- Vsync verificato all'avvio: se il driver lo ignora, limite alla frequenza del monitor.
- Con il vsync funzionante il dt viene agganciato ai multipli del periodo di refresh, così i
  ritardi di risveglio della CPU non diventano micro-scatti.
- `glFinish` dopo ogni frame (latenza ~1 frame), disattivato se fa perdere frame.
- Su Windows: GPU dedicata sui portatili ibridi (`NvOptimusEnablement`), priorità "sopra il
  normale" e thread registrato in MMCSS come "Games".
- CRT a risoluzione interna limitata (720p) con righe emulate fisse (576 con il default
  `resolution_scale` 2.5): stesso aspetto in finestra e a schermo intero.

Misure su RTX 3060 Laptop, monitor 2560×1440 a 165 Hz: 6,06 ms per frame in finestra e a
schermo intero, con e senza CRT; 11 prove su 12 senza frame persi (una con 1 frame perso).

## Differenze rispetto alla versione Python

- Non ancora supportati: encoder rotativi su Raspberry Pi, finestra senza bordi (`title_bar: false`).
- `crt_effects.resolution_scale` fissa le righe emulate (3 × altezza del campo / valore) invece
  di dipendere dalla risoluzione dello schermo.
- La versione Linux è compilata dalla GitHub Action ma non ancora provata su un Pi reale.
