# Changelog

Tutte le modifiche rilevanti di PADD WS. Il formato segue
[Keep a Changelog](https://keepachangelog.com/it-IT/1.1.0/) e la numerazione
[Semantic Versioning](https://semver.org/lang/it/):

- **MAJOR**: riscritture o modifiche incompatibili (es. configurazione da migrare);
- **MINOR**: nuove funzionalità compatibili;
- **PATCH**: correzioni.

Le voci nuove vanno sotto **Non rilasciato**; `python tools/release.py minor`
(o `major` / `patch`) le sposta nella nuova versione, aggiorna `paddws/__init__.py`,
crea il commit e il tag `vX.Y.Z`.

## [Non rilasciato]

### Aggiunto
- Web, **menu con il mouse**: la rotella gira la ruota del menu, una voce per scatto (al più
  una ogni 60 ms, così un trackpad non la fa correre), e il click usa sempre la voce attiva, in
  qualunque punto dello schermo; vale anche con MOUSE SPINNER acceso. Il tocco resta com'era.
- C64: la schermata **HOW TO PLAY** delle mosse speciali, come su PC e MiSTer: con SUPER MOVES:
  ON dopo la scelta della racchetta (joystick; non con i paddle né per lo sfidante), una bitmap
  hires dalla cartuccia (banchi 24-25, `gen/howto.bin` da `tools/gen_c64_assets.py`) con le due
  mosse, i passi del joystick, il tiro, la barra e i comandi; 8 s, il fuoco la salta.
- PC, Raspberry e web: il **finale della CHALLENGE** (`rust/game/src/ending_ui.rs`), quando si
  batte l'ultimo avversario, al posto della schermata CHAMPION: CONGRATULATIONS! e la voce
  "YOU WIN!", la sfilata dei sette avversari (racchette vere e nome, uno al secondo) con il timbro
  rosso DEFEATED, il punteggio finale (SCORE che sale, CHAMPION BONUS = premio di vittoria e di
  partita perfetta dell'ultimo livello, TOTAL), "YOU ARE THE PADD WS CHAMPION" con sei tipi di
  fuochi d'artificio (anello, salice, palma, crisantemo, crepitio, cometa che si divide, con il
  razzo e la gravità), i titoli di coda e THE END; poi le iniziali. Circa 57 s, Start lo salta.
  Solo bianco, giallo e rosso: le scintille si diradano invece di scurirsi. Musica: la canzone
  ENDING della ROM del SID se c'è, altrimenti CHAMPION; le canzoni si cercano ora per nome nel
  `sid_music.vh`. Una scena per parte nel giro delle schermate (`9_ending_*`).
- La canzone **ENDING** del finale nella ROM del SID (`tools/gen_sid_music.py`): techno melodica
  in fa diesis minore a 125 BPM, circa un minuto, con un motivo ipnotico a sedicesimi nel filtro
  che si apre piano, una pausa con il wobble sul basso profondo e il drop a metà. Strumenti nuovi
  14 (basso senza filtro) e 15 (motivo nel filtro). Sta dopo i temi, come le mosse speciali: i
  numeri dei temi non cambiano e nel C64 resta fuori da `sid_music.bin`. La ROM è a 4093 byte su
  4096.
- PC, Raspberry e web: la voce **"YOU WIN!"** quando si vince una partita contro la CPU (Classic,
  EVO, NEXT e livelli della CHALLENGE), con la scritta del GAME OVER.
- MiSTer: il **finale della CHALLENGE** (`mister/rtl/ending_render.v`, modo `M_ENDING`) come su PC,
  al posto della schermata CHAMPION e prima delle iniziali: CONGRATULATIONS! e YOU WIN!, la sfilata
  dei sette avversari (racchette con i segni del tipo e nome, disegnate da `next_render.v`) con il
  timbro DEFEATED e i colpi di muro e racchetta, SCORE che sale, CHAMPION BONUS e TOTAL, YOU ARE THE
  PADD WS CHAMPION con i sei tipi di fuochi d'artificio, i titoli di coda e THE END; circa 57 s,
  Start lo salta. Solo bianco, giallo e rosso. Grafica da `tools/gen_ending_assets.py`: scritte in
  Munro su righe di bitmap con una mappa delle righe (i titoli scorrono nella mappa), i punti dei
  fuochi già calcolati per ogni frame a 15 Hz e disegnati in un framebuffer 160x120 a due pagine;
  nessuna divisione in HDL. Musica: la canzone ENDING del SID (la 14), spenta con *Music: Off*.
  Simulatore dei frame: scenario `ending`.
- MiSTer: la voce **"YOU WIN!"** con il GAME OVER di ogni partita vinta contro la CPU (Classic, EVO,
  NEXT e livelli della CHALLENGE) e all'inizio del finale, dalla ROM delle voci di partita
  (`tools/gen_voices.py --mister`: 12 voci, 17.086 byte, indirizzi a 15 bit in `pong_sid.v`).
- PC, Raspberry e web: **gamepad e stick arcade** (`rust/game/src/gamepad.rs`), con
  [gilrs](https://crates.io/crates/gilrs) su Windows, Linux e Raspberry Pi e la Gamepad API del
  browser nel web (`rust/web/gamepad.js`). Due gamepad = due giocatori (il primo a sinistra, il
  secondo a destra; con un gamepad solo e un solo giocatore è suo, da qualunque lato); i tasti
  restano. Levetta o croce muovono la racchetta (doppio tocco = rapido), **A** scatto, **B**
  seleziona e **C** (X o Y) usa il bonus, come nella HOW TO PLAY; **Start** pausa e Start,
  **Select** gettone. La levetta analogica diventa una direzione a 8 vie con zona morta del 35%;
  croce, "cappello" e assi digitali degli stick arcade e delle schede encoder vanno bene così, e
  i pulsanti senza mappatura SDL valgono per numero (1 A, 2 B, 3 C, 9 Select, 10 Start). Mosse
  speciali con le mezzelune del MiSTer (↓ ↘ → + A, → ↓ ↘ + A, `gesture::Stick`, stessi tempi), e
  la HOW TO PLAY mostra i comandi del joystick quando l'ultimo comando usato è un gamepad. Nei
  menu, nelle scelte, nelle iniziali e nelle schermate della CHALLENGE i gamepad valgono come i
  tasti del loro giocatore (`rust/game/src/input.rs`, una mappa per scena), con le direzioni
  tenute che si ripetono: A conferma, B torna indietro; in pausa A riprende e B torna al menu;
  lo Start del gamepad del lato libero fa entrare un nuovo sfidante. Su Linux serve `libudev`
  (`libudev-dev` per compilare: CI e immagine di forge aggiornate).
- Web: le **preferenze del menu** e la classifica della CHALLENGE restano nel `localStorage`
  (`rust/web/storage.js`): lo stesso JSON di `padd_config.json` e `padd_scores.json`, con il nome
  del file come chiave, letto all'avvio e scritto con le stesse chiavi di `save_preferences`.
- C64: il **finale della CHALLENGE** (`c64/src/ending.s`) come su PC, al posto della schermata
  CHAMPION e prima delle iniziali: CONGRATULATIONS! e YOU WIN! con la voce del SID, la sfilata dei
  sette avversari (le racchette vere negli sprite, una al secondo, con il nome) e il timbro rosso
  DEFEATED, SCORE che sale, CHAMPION BONUS e TOTAL, YOU ARE THE PADD WS CHAMPION con i fuochi
  d'artificio (razzi negli sprite che salgono rallentando, sei tipi di scoppio con la gravità:
  anello, salice, palma, crisantemo, crepitio, croce che si divide, a 16,7 passi al secondo in
  caratteri multicolore su due schermi), i titoli di coda a sezioni con lo scorrimento fine e THE
  END; circa 57 s, Start lo salta. Solo bianco, giallo e rosso sul nero (le scintille si diradano),
  bordo nero come nelle altre schermate. Musica: la canzone ENDING della ROM del SID
  (`gen/ending.bin`, canzone `SID_SONG_ENDING` del player). Quasi tutto sta nella cartuccia (banchi
  14-15, l'uscita `paddws.prg.end` di ld65) e gira nella bitmap dell'attract e al posto del set di
  caratteri, che il finale rimette; nel programma, con YOU WIN, 32 byte in più. Nessun frame
  oltre i 16.800 cicli. `paddws-c64 frames` (e `paddws-c64 ending`, solo lui) gioca il finale da capo con
  i controlli di parti, colori e uscita; `ui` lo salta in quattro punti (prima di mezzo secondo no); `sid` confronta la canzone
  con il player Rust. Per le schermate: `.\c64\build.ps1 -Name autoend -Define ENDTEST`.
- C64: la voce **"YOU WIN!"** con il GAME OVER di ogni partita vinta contro la CPU (Classic, EVO,
  NEXT e livelli della CHALLENGE, non l'ultimo: la dice il finale), come su PC. Sta nel banco 13
  della cartuccia con il player delle voci (`tools/make_crt.py`), che il GAME OVER copia due pagine
  per frame; i campioni vanno dove ci sono le tabelle dei quadrati, che poi si rifanno.
- C64: opzione **BORDER** nel menu (BLACK o GRAY, GRAY all'accensione). Con GRAY il bordo è grigio
  scuro in partita e nella demo, così si vedono i limiti del campo, e segue la partita: bianco nel
  lampo del punto (come lo schermo), giallo con il SUPER o una mossa speciale MAX in volo, grigio
  pulsante nel bullet time, rosso lento al match point (lo stesso stato che accelera la musica).
  Con BLACK il bordo di sempre. Si scrive solo quando cambia, nel vblank.
- C64: nella classifica di CHALLENGE (attract e fine della scala) **barre di colore nel bordo**:
  due sfumature che scendono, un colore ogni due righe. Nel bordo in alto il raster si stabilizza
  al ciclo e i colori cambiano nel ritorno orizzontale; accanto allo schermo a metà riga, solo
  nelle righe pari (mai badline): nessun cambio a metà del bordo né "grey dot". La musica resta
  quella di sempre e il bordo torna nero prima della fine del frame.
- C64: le **mosse speciali** di NEXT e CHALLENGE (STRAIGHT SHOT e RISING STRIKE, normali e MAX),
  con la voce **SUPER MOVES** nel menu (spenta all'accensione), identiche al core Rust tick per
  tick: barra, costo, livelli, tiro dritto e più veloce, impennata alla soglia, CPU che le usa e
  che rifà il tempo di reazione all'impennata. Gesto del joystick come sul MiSTer (↓ ↘ → + fuoco,
  → ↓ ↘ + fuoco, con avanti verso l'avversario, tempi a 50 Hz): il fuoco che chiude il gesto usa la
  mossa solo se può partire, altrimenti il bonus selezionato. Con i paddle nessun gesto (il
  riconoscitore della manopola non ci sta). A schermo la barra accanto alle riserve (gialla per
  settore pieno), l'icona gialla della mossa armata accanto alla racchetta, la racchetta gialla con
  la MAX, la scritta "P1 MAX RISING STRIKE!", la palla gialla con la coda nel tiro e a lampi
  all'impennata; suoni MOVE e SPECIAL della ROM della musica (effetti 6 e 7 del player, tracce da
  `mister/rtl/gen/c64`). Il codice sta quasi tutto nella cartuccia e la scelta di NEXT lo copia
  nella RAM del secondo schermo (`$C400`), che in partita non serve; il programma arriva a
  `$BC9F` (le variabili salgono a `$BCA0`) e qualche routine sta da `$0284`. Il banco di prova
  `paddws-c64` gioca 8 partite NEXT con le mosse (CPU contro CPU e giocatori al joystick letti dal
  6502) contro il core, prova 18 gesti in `ui` e misura i frame con le mosse in `frames`.
- MiSTer, C64, PC, Raspberry e web: il **filtro del SID** nelle musiche. Comandi nuovi nelle
  tracce (`tools/gen_sid_music.py`): il taglio (`0xA0` + i 3 bit bassi, poi gli 8 alti) e la sua
  scivolata a ogni passo della canzone (`0xB0` e 16 bit con segno, in 1/32 di passo: il taglio è
  tenuto a 16 bit, senza saturazione, con i limiti controllati dal generatore); negli strumenti, nei
  byte 6 e 7 finora vuoti, il $D417 (risonanza e la voce, che mette il generatore) e il $D418 (modo,
  volume 15). Il filtro vale solo sulle voci 1 e 2: la voce 3, quella degli effetti, non ci passa
  mai. I tre player (`pong_sid.v`, il port Rust e `c64/src/sid.s`, scritture identiche:
  `c64/test/sid_reference.txt`, `rust/sid/tests/writes_*.txt`) riscrivono taglio, $D417 e $D418
  solo quando una nota di uno strumento nel filtro li cambia; a ogni canzone nuova $D418 = $0F e
  $D417 = 0 (una scrittura in più per canzone). Durante la voce della CHALLENGE il filtro è spento
  ($D417 = 0 all'inizio della voce, sul MiSTer e nel file voce del C64) e la prima nota nel filtro
  dopo la voce lo riscrive tutto. Le musiche: il basso di **HAMMER** nel passa-basso risonante, con
  un "reese" leggero (il taglio sale in quattro battute e torna giù in due) e il "wobble" nelle
  ultime due (il taglio riparte alto a ogni nota e si chiude); un'apertura della melodia nel
  **titolo**; un respiro della melodia di **TITAN**. Pensate per l'8580, provate anche con il 6581.
- SID Rust (`rust/sid`): il **filtro dell'8580**, port del modo 8580 di `sid_filter.sv` del MiSTer
  (state variable a 12 dB/ottava, taglio lineare di circa 6 Hz per passo, 1/Q = 2^((4 - res)/8),
  aritmetica intera), un passo ogni 2 cicli del SID e solo quando ci sono voci nel filtro.
- MiSTer, CHALLENGE: **musica dinamica** nel player del SID (`pong_sid.v`) con le regole del SID
  Rust: al match point la canzone avanza a 62,5 Hz (gli effetti restano a 50 Hz, con un divisore
  loro), nel bullet time un passo su due e un'ottava sotto, con le note in corso che cambiano
  ottava subito; insieme si sommano. Scritture ai registri identiche al player Rust nei casi match
  point, bullet time e insieme (`mister/sim/sid/writes.cpp fast|slow|both`), invariate nel caso
  normale (`c64/test/sid_reference.txt`). Le scivolate degli effetti rallentati scrivono ora prima
  il byte alto, come il player Rust.
- MiSTer, CHALLENGE: la **classifica si salva sulla SD**, nella NVRAM dei core arcade
  (`<nvram index="4" size="192"/>` nel `PaddWS.mra`, file `/media/fat/config/nvram/PaddWS.nvm`,
  `mister/rtl/ch_nvram.v`). Si salva con *Save settings* dell'OSD o, con la nuova opzione
  *Autosave scores* (accesa di default), all'apertura dell'OSD dopo un nuovo posto in classifica.
  Un file che manca, incompleto o guasto (intestazione, somma di controllo, campi, ordine dei
  punti) lascia la classifica iniziale. Provato nel simulatore dei frame con un `hps_io` finto
  (scenario `nvram`).
- MiSTer, CHALLENGE: nella **presentazione dell'avversario** la sua racchetta ha i segni del tipo
  come su PC (estremità gialle del TITAN, bande dell'HAMMER, TWIST inclinata, smussi, canne e
  caricatore del BLASTER, immagini dello scatto del RUSH, pezzo di muro del GUARDIAN) ed è rivolta
  verso il giocatore; prima era un rettangolo bianco. La disegna `next_render.v` con la logica
  dell'anteprima della scelta della racchetta. Lo scenario `challenge` del simulatore dei frame
  salva anche gli avversari di tutti i livelli (`ch_lvl*.ppm`).
- MiSTer: la logica di gioco e le CPU avversarie sono il **core Rust vero, eseguito da un
  processore RISC-V** (VexRiscv RV32IM a 60 MHz, licenza MIT) invece che una seconda versione in
  Verilog: libera la gran parte degli ALM e dei DSP del core. Firmware `rust/mister-fw` (crate
  `paddws-mister-fw`, no_std), immagine della BRAM da 64 KB in `mister/rtl/gen/pong_fw_b*.hex`
  (`tools/gen_mister_fw.py`, `--check` per l'impronta dei sorgenti), modulo
  `mister/rtl/pong_logic_rv.v` con le porte della logica in Verilog di prima, seconda uscita della
  PLL a 60 MHz. Verifiche: il firmware su un emulatore contro le 29 tracce (`paddws-fw-sim`, in
  `mister/sim/run.ps1` e `run.sh`), il modulo con Verilator contro le tracce
  (`mister/sim/rv/rv.ps1`; durante il passaggio anche porta per porta contro la logica di prima), i
  frame del core completo prima e dopo. La codifica delle parole di stato delle tracce è ora quella del firmware
  (`paddws_mister_fw::words`).
- NEXT, mosse speciali: chi le esegue **urla il nome della mossa** ("STRAIGHT SHOT!", "RISING
  STRIKE!", voce "da SID" a 4 bit, `tools/gen_voices.py`) e due effetti SID propri: una carica
  che sale all'attivazione e uno schiocco con discesa al colpo (`MOVE` e `SPECIAL` in
  `tools/gen_sid_music.py`, in fondo alla ROM; il C64 li prende da lì per le sue mosse speciali).
- CHALLENGE: la voce dice **"READY?"** all'inizio del conto alla rovescia e **"GO!"** al via.
- MiSTer: anche qui le **urla delle mosse speciali** e **"READY?" / "GO!"** della CHALLENGE, come
  campioni a 4 bit sommati all'uscita audio (SID o campioni originali) senza zittire musica ed
  effetti; ROM delle voci con 11 voci e indice a 4 bit (`tools/gen_voices.py --mister`).
- CHALLENGE: un **tema musicale per ogni avversario**, originale, durante la partita contro la CPU
  (non nella sfida con lo sfidante né nella demo), su PC, web, Raspberry, MiSTer e C64. Suona sulle
  voci 1 e 2 del SID, la 3 resta agli effetti (`tools/gen_sid_music.py`, canzoni 7-13). Si spegne
  con **MUSIC: ON/OFF** nel menu (`game.match_music`) o con l'OSD *Match music* del MiSTer. Sul C64
  il tema viaggia nel file voce dell'avversario e si copia a `$F800`: c'è con il `.d64` e la
  cartuccia, non con il solo `.prg`, e non si può spegnere.
- PC, Raspberry e web: le musiche le suona in tempo reale un **SID scritto in Rust** (crate
  `rust/sid`, `paddws-sid`, licenza MIT, niente reSID) invece delle registrazioni del core MiSTer
  simulato. Il player è il port di quello Verilog (`pong_sid.v`, senza la voce digitalizzata) e
  legge la stessa ROM (`mister/rtl/gen/sid_music.hex`): le scritture ai registri sono identiche
  frame per frame al riferimento `c64/test/sid_reference.txt` (`cargo test -p paddws-sid`). Il SID
  ha solo quello che usano le musiche: tre voci, triangolo, dente di sega, impulso a 12 bit, rumore
  (LFSR a 23 bit), ADSR con le tabelle dei tempi del chip e il contatore esponenziale, DAC
  dell'8580, niente filtro; clock a 1 MHz e media dei cicli su ogni campione d'uscita, come la
  registrazione. Contro le registrazioni (`paddws-sid compare`): livello entro 0,03 dB, RMS per
  frame da 20 ms entro 0,1 dB di media, spettro per ottave entro 0,6 dB fino a 8 kHz. CPU: circa 2,4 ms per
  secondo di musica su PC. Nativo: la sintesi gira nel mixer di quad-snd, copiata in
  `rust/vendor/quad-snd` con una sorgente continua (`set_stream`), sullo stesso dispositivo degli
  effetti; web: `rust/web/sid_audio.js`, uno ScriptProcessor nell'AudioContext degli effetti. Gli
  effetti restano WAV. Tolti gli OGG e `tools/encode_sid_songs.py` (e lewton dalle dipendenze): il
  wasm passa da circa 4,1 a 1,9 MB. Il tema di HAMMER ora gira senza salto (l'OGG durava 768 frame,
  che non sono un multiplo dei 536 del basso).
- CHALLENGE, tema della partita (PC, Raspberry e web): al **match point**, quando uno dei due è a
  un punto dalla vittoria, il tempo accelera di ×1,25 con le note alla stessa altezza e resta così
  fino alla fine della partita; nel **bullet time** la musica rallenta come un nastro a metà
  velocità, un'ottava sotto, e torna normale alla fine (anche nella rampa d'entrata è già a metà).
  Regole di tempo per il MiSTer e il C64 (`rust/sid/src/engine.rs` e `player.rs`):
  - normale: un passo del player ogni 20.000 cicli del SID a 1 MHz (50 Hz);
  - match point: un passo ogni 16.000 cicli (62,5 Hz). MiSTer: il divisore del frame del player
    conta fino a 319.999 invece di 399.999 (a 20 MHz). C64, con il player legato al frame da
    50 Hz: 5 passi ogni 4 frame, meglio con il passo in più a metà frame (stessa sequenza di
    scritture; il tempo regolare conta per le note da un frame della cassa);
  - rallentata: come `fx_slow` per gli effetti, i canali 0-2 della canzone sono serviti un passo
    su due (un `skip` che si alterna a ogni passo e si azzera all'entrata, così il primo passo si
    serve) e scrivono la frequenza dimezzata, prima il byte alto `freq >> 9` e poi il basso
    `freq >> 1`. A ogni cambio, entrata e uscita, al passo dopo (dopo la gestione della canzone
    nuova, prima dei canali) i canali attivi della canzone riscrivono la frequenza in corso,
    dimezzata o intera, con le regole di scrittura di sempre (la voce 3 tace se suona un effetto);
    non serve se la canzone è appena ripartita;
  - le due cose si sommano: nel bullet time al match point un passo su due di quelli da 62,5 Hz.
    La fase degli arpeggi avanza a ogni passo, come ora; gli effetti restano a 50 Hz con le loro
    regole (nel gioco Rust sono campioni WAV e non cambiano).
- CHALLENGE: nella presentazione di ogni livello una voce digitalizzata "da SID" annuncia il nome
  dell'avversario (PC, web, MiSTer e C64). Le voci sono sintetizzate con espeak-ng e ridotte a
  4 bit e 5 kHz (`tools/gen_voices.py`); MiSTer e C64 le suonano con il trucco del registro del
  volume del SID (`$D418`), con l'offset delle voci in test perché si sentano anche sull'8580, e
  il jingle tace durante la voce. Sul C64 la voce di turno si carica dal disco (`paddws.d64`, circa
  8 s con un 1541 senza fast loader); con il solo `paddws.prg` non c'è.
- C64: nuova versione su cartuccia **`paddws.crt`** (EasyFlash) nel pacchetto `-c64.zip`: tutto in
  un file, avvio immediato e voci dalla flash senza caricamenti. Sulla cartuccia la classifica di
  CHALLENGE resta finché il C64 è acceso.
- NEXT: nuovo bonus raro **BULLET** (bullet time) su PC, web, Raspberry, MiSTer e C64. Arriva solo dalle capsule, circa una su 16 (il SUPER resta
  una su 8): per 2 secondi tutto va a metà velocità, con rampe a 3/4 all'inizio e alla fine, tranne
  la racchetta di chi lo attiva. Rallentano la palla (anche CURVE e STEER), la racchetta
  avversaria (anche con l'encoder), le capsule e i colpi del BLASTER avversario; si rallenta il passo
  di ogni tick e non la velocità, così dopo tutto torna come prima. Non lo interrompe un colpo,
  finisce allo scadere o al punto; uno alla volta. La CPU lo tiene per le palle veloci che non
  prenderebbe. A schermo: il bianco diventa grigio tranne la racchetta di chi lo usa, bordata di
  giallo, la palla lascia una scia di immagini e i suoni scendono di un'ottava. Parametri
  `next.bullet_*`; `paddws-trace --bonus-stats` misura palle e punti salvati. Nelle tracce MiSTer
  i bonus della riserva sono ora codici a 4 bit (8 = vuoto).
- CHALLENGE: **HERE COMES A NEW CHALLENGER!** come in Street Fighter 2 (Rust, MiSTer e C64).
  Durante la presentazione di un livello, la partita contro la CPU o il livello superato (tranne
  l'ultimo) un secondo giocatore entra con un credito (o in Free Play) premendo lo Start del lato
  libero: `2` o `1` sul PC, il click dell'encoder sul Raspberry, un dito tenuto 1 s nella metà
  libera sul web, lo Start del joystick sul MiSTer, il fuoco del joystick o il pulsante della
  paddle sul C64. Nelle presentazioni lo invita una scritta lampeggiante. Lo sfidante sceglie
  bonus e racchetta, poi sfida a 5 punti con il campione; il vincitore riprende il livello dal
  suo lato contro la CPU (che ora può giocare anche a sinistra), con un premio pari a quello del
  livello: il campione lo somma ai suoi punti, lo sfidante parte da lì. Il perdente scrive le
  iniziali se entra in classifica. Regole nel core (`Score::duel_bonus`, `Score::after_duel`,
  `Rung::sides`); simulatore dei frame MiSTer: scenario `challenger`.
- Mosse speciali in NEXT e CHALLENGE (Rust e MiSTer; sul C64 vedi sopra), con l'opzione **SUPER MOVES**
  nel menu e *Super moves* nell'OSD (spenta di default). Una barra per giocatore si riempie con i
  colpi, gli scatti che intercettano e i punti subiti; ogni mossa costa mezza barra.
  **STRAIGHT SHOT** (↓ ↘ → + A sul joystick, giù-su + scatto su tastiera, manopola e touch):
  il prossimo tiro parte dritto con la spinta raddoppiata. **RISING STRIKE** (→ ↓ ↘ + A, su-giù
  + scatto): la racchetta salta verso la palla e, se la colpisce entro mezzo secondo, tira a 45°.
  Prima della partita la schermata **HOW TO PLAY** presenta le mosse con il comando del proprio
  dispositivo (Start la salta). Anche la CPU le usa, nelle partite e nella demo. Tracce MiSTer con
  `paddws-trace --supers`; simulatore dei frame: scenario `supers`. Parametri `next.super_*` nella
  configurazione del PC.
- Demo dell'attract per ogni modalità (Rust e MiSTer): dopo la classifica una partita CPU contro
  CPU nella modalità scelta (menu sul PC, OSD sul MiSTer), CLASSIC, EVO, NEXT con bonus e racchette
  a caso per tutti e due, CHALLENGE contro l'avversario di un livello a caso (racchetta, bonus, CPU
  e velocità del livello). Nel riquadro al centro INSERT COIN / PRESS START si alterna al nome
  della modalità; in NEXT e CHALLENGE i crediti vanno in basso, dove non coprono le riserve. Sul
  PC la demo prima non c'era. Sul MiSTer le scritte della demo e del GAME OVER restano sopra la
  grafica di NEXT. Simulatore dei frame: scenario `demo`.
- Versione **Commodore 64** (anteprima, solo PAL), in assembly 6502: `paddws-X.Y.Z-c64.zip` con
  `paddws.prg` e `paddws.d64`. Gioca la stessa partita del core Rust bit per bit (Q16.16 a 32 bit,
  un tick per frame a 50 Hz, campo 320×200), verificata tick per tick nel banco di prova
  `rust/c64` (emulatore 6502) e nella GitHub Action `C64`. C'è tutto: attract con auto-test,
  strisce, logo, titolo e demo; gettoni e menu; Classic, EVO e singolo; contro la CPU (la stessa
  del core, comando per comando); NEXT con scelte, riserve, capsule, tipi di racchetta (con
  l'anteprima) ed effetti; CHALLENGE con la classifica salvata su disco (`PADDWS.HI` sul drive da
  cui parte il programma); musiche ed effetti con il SID vero (player identico a quello del
  MiSTer). Joystick nelle due porte o paddle. Con il joystick basta un pulsante: verso
  l'avversario si scatta in avanti (il BLASTER spara) e in NEXT il bonus selezionato cambia da
  solo ogni secondo, il fuoco lo usa. Mancano NTSC e le prove sull'hardware vero (provata in VICE).
- Sintesi del core MiSTer in locale con lo stesso container Docker della CI (immagine fissata per
  digest in `mister/quartus-image.txt`): `mister/synth.ps1` (Docker Desktop) e `mister/synth.sh`
  (Linux o macchina virtuale, circa 16 minuti con 4 core). In CI la sintesi parte solo sui tag o
  a mano.
- Release in locale, senza GitHub Action: `build.bat` manda il commit alla macchina virtuale
  *forge* (Debian 13 con Docker, `tools/forge`), che fa gli stessi controlli e gli stessi pacchetti
  della CI nell'immagine `paddws-build` (Ubuntu 22.04 con Rust, MinGW, compilazione incrociata
  aarch64, wasm, PowerShell, cc65, Icarus Verilog, Python) e sintetizza il core MiSTer con Quartus;
  i pacchetti tornano in `dist\`, `-Publish` pubblica la release con `gh`. VMware accende e spegne
  forge da solo (`vmrun`). Sulla VM una console con lo stato dal vivo (lavoro in corso, ultima
  build e sintesi, immagini, risorse) e i comandi `forge-stato`, `forge-build`, `forge-sintesi`.
- `build_ongithub.bat`: la release online di prima in un comando (controlli, `tools/release.py`,
  push, Action seguite fino alla fine); senza versione rilancia le Action del tag.
- Modalità **CHALLENGE** (versione Rust e core MiSTer, *Players: Challenge*): da soli contro 7
  avversari CPU, ognuno con un tipo di racchetta diverso, i suoi bonus e un livello proprio della
  CPU; partite NEXT a 7 punti. Punti arcade (colpi, scatti, SUPER e punti con un moltiplicatore
  che sale negli scambi lunghi, premi per la vittoria e la partita perfetta), continue con un
  gettone dallo stesso livello (punteggio azzerato), classifica dei 10 migliori con le iniziali
  (`padd_scores.json`, anche nell'attract). Scala tarata con `paddws-trace --challenge-stats`; la
  difficoltà del menu sposta la velocità della palla (con spinner e paddle conviene HARD). Sul
  MiSTer i livelli della CPU di CHALLENGE sono verificati con una traccia nuova (`trace_ladder`) e
  la classifica resta finché il core è acceso.
- Suoni e musiche del **SID**: sul MiSTer il SID 6581/8580 del core C64 (opzione *Sound*), con un
  player che suona 6 musiche originali (titolo, presentazione del livello, livello superato,
  continue, game over, campione) e gli effetti; su PC, Raspberry e web gli stessi suoni registrati
  dal player simulato (voce SOUND del menu, `game.sid_sound`). Musiche in `tools/gen_sid_music.py`.
- `paddws-trace`: giocatori umani simulati per le statistiche di bilanciamento (`--human`,
  `--skill`, `--human-stats`), con tempi di reazione, ritardo visivo, errori di stima e di
  movimento presi dai modelli del controllo motorio; tre profili (principiante, medio, esperto).
- NEXT, tipi di racchetta (versione Rust e core MiSTer, logica e CPU verificate tick per tick con
  cinque tracce nuove): dopo i bonus si sceglie la racchetta in
  una schermata come quella dei bonus, con l'anteprima a grandezza reale (la CPU sceglie a caso);
  in partita ogni tipo ha il suo segno, i colpi del BLASTER, il suo caricatore (dietro la
  racchetta) e la barriera del GUARDIAN si vedono. Tipi: ARCADE (più capsule: partono ogni 3-4 s
  invece di 4-5 e due su tre vanno a lui; pausa più breve tra due bonus; un po' più corta), TITAN
  (più alta e più lenta), HAMMER (lenta, colpi più veloci), TWIST (passa alla palla parte della sua
  velocità), BLASTER (senza scatto: caricatore da 3 colpi da sparare di fila, che torna pieno 3 s
  dopo il primo colpo; i colpi raccolgono le capsule, anche quelle dell'avversario), RUSH (più
  corta, scatto più lungo; dalla posizione avanzata la racchetta è più rapida e i tiri, anche lo
  scatto che intercetta la palla, partono più veloci) e GUARDIAN (più corta, barriera che rimanda
  una palla mancata e torna ogni 6 punti). Con l'encoder i tipi lenti seguono la manopola con una velocità massima. Valori
  nella sezione `next.paddles` della configurazione, bilanciati con `paddws-trace --paddle-stats N`
  (ogni tipo contro la racchetta senza tipo, CPU contro CPU, tutti i livelli e comandi). Le
  partite NEXT senza tipo restano come prima.
- Avversario controllato dal computer (per ora nella versione Rust): voce **PLAYERS: VS CPU** del
  menu, in Classic, EVO e NEXT. Il livello segue la difficoltà: da EASY, che insegue la palla e la
  manca spesso, a EXPERT, che ne prevede il punto d'arrivo e sbaglia di rado; usa lo scatto in
  avanti, raccoglie le capsule e attiva i bonus. Logica deterministica e senza divisioni in
  `core/src/cpu.rs`, pronta per MiSTer e Python; `paddws-trace --next-stats N --cpu` misura le
  partite tra due CPU.
- Modalità **NEXT** (anteprima, per ora solo nella versione Rust): Classic con lo scatto in avanti
  e i bonus. Scelta di 3 bonus su 5 prima della partita, capsule dalla mezzeria da raccogliere con
  la racchetta, riserva di 3 posti, SUPER raro con tre animazioni; palla più lenta che accelera
  piano. Core deterministico e senza divisioni (`core/src/next.rs`), pronto per Python e MiSTer;
  `paddws-trace --next-stats` per regolarne i valori.
- La versione Python entra nelle release (`paddws-X.Y.Z-python.zip`, GitHub Action `Python` con i
  test); Python, Rust e MiSTer hanno ora un unico numero di versione, aggiornato insieme da
  `tools/release.py` (che accetta anche le anteprime `X.Y.Z-alpha.N`).
- Core MiSTer: modalità **NEXT** e partite **contro la CPU**. Logica di NEXT in `pong_logic.v`,
  verificata bit per bit contro il core Rust con due tracce NEXT da 4 minuti giocate da due CPU
  (`paddws-trace --next`); scelta dei bonus, riserve, capsule ed effetti in `next_render.v`
  (icone e scritte da `tools/gen_next_assets.py`). OSD: *Game type* Classic/EVO/NEXT, *Players*
  Two/One/Vs CPU; pulsanti X (seleziona il bonus) e Y (usa il bonus); Start e gettone passano
  ai pulsanti 9 e 10 del joystick. La demo la giocano due CPU.
- Core MiSTer: CPU in Verilog (`cpu_player.v`), traduzione della CPU Rust verificata comando per
  comando contro le tracce giocate da due CPU (`paddws-trace --cpu-play`, anche in Classic ed EVO).
- Release MiSTer in un unico zip, `PaddWS_MiSTer_AAAAMMGG.zip`, da scompattare nella radice della SD.
- Suono del gettone (`assets/sounds/coin.wav`, generato da `tools/gen_coin_sound.py`) in tutte le
  versioni.
- Opzione per togliere i suoni dell'attract e della demo (gettone e Start si sentono sempre):
  `game.attract_sound` e voce ATTRACT SOUND nel menu del PC, *Attract sound* nell'OSD del MiSTer.
- Conto alla rovescia di 3 secondi (3, 2, 1 con un bip al secondo, poi il via) prima del primo
  servizio, in tutte le versioni; sul MiSTer la cifra segue l'opzione *Scores*.
- Lo scatto in avanti si vede: la racchetta scivola in circa 5 frame invece di teletrasportarsi
  (solo grafica, la logica resta istantanea), in tutte le versioni.
- NEXT: i parametri di palla, capsule e bonus si regolano nella nuova sezione `next` di
  `padd_config.json` (versione Rust): velocità della palla per difficoltà, capsule, probabilità
  del SUPER, moltiplicatori di SMASH, SUPER e SLOW, effetto di CURVE, pause e hit-stop. Se il file
  non ha ancora la sezione, il gioco la aggiunge con i default, che sono quelli del core MiSTer
  (con valori diversi il PC non coincide più con l'FPGA).
- A fine partita in due, sotto GAME OVER, compare chi ha vinto: **P1 WINS** / **P2 WINS**, o
  contro la CPU **YOU WIN** / **CPU WINS** (versione Rust e MiSTer; sul MiSTer anche ruotato verso
  ciascun giocatore con i punteggi verso i giocatori); in NEXT nel colore di accento. Scritte
  negli asset dell'attract.
- Colore di accento `colors.accent` (versione Rust, default il giallo dell'attract; sul MiSTer
  fisso al giallo, stessi punti tranne il menu, che lì è l'OSD), usato con
  parsimonia solo in NEXT: titolo e voce selezionata del menu (con GAME TYPE: NEXT), titolo,
  cursore e READY! della scelta dei bonus, scritta del bonus
  attivato, freccetta del bonus selezionato nella riserva, linee dei portali di TELEPORT, capsula
  del SUPER (in volo e nella riserva) e palla del SUPER in volo, compresa la testa della cometa. Come la
  sezione `next`, viene aggiunto da solo ai file di configurazione che non lo hanno.
- Luminosità del bianco: opzione OSD *White level* sul MiSTer e voce WHITE LEVEL nel menu del PC
  (`game.white_level`), 100%, 87%, 75% o 62%; tutta l'immagine scala in proporzione, così il
  grigio resta distinguibile dal bianco.
- MiSTer: la palla COMETA del SUPER spacca la rete come su PC: i trattini della mezzeria vicini
  alla palla schizzano di lato nel verso del tiro e tornano al loro posto in circa un secondo.
- NEXT: nuovo bonus **STEER** (icona del volante), versione Rust e MiSTer: dopo il colpo su e giù
  guidano la palla fino a 3/4 del campo, con la racchetta ferma; la sterzata (`steer_accel`) porta
  la palla fino a circa 63 gradi. La scelta diventa di 3 bonus su 6. Il tiro guidato fa punto nel
  19-24% dei casi, come SMASH e CURVE (`paddws-trace --bonus-stats`).
- README: tabella dei bonus con le loro icone (PNG, della stessa misura anche nell'app GitHub).
- MiSTer: paddle e spinner (opzioni OSD *Paddle control* e *Spinner speed*). Il paddle dà la
  posizione della racchetta su tutta la corsa (0 = in alto); lo spinner la sposta (gli
  spostamenti positivi la fanno scendere) e lascia funzionare il joystick quando è fermo; con STEER il paddle guida la palla
  girato lontano dalla racchetta, lo spinner con il verso della rotazione. La logica applica la
  posizione come l'encoder del core Rust, verificata con due nuove tracce (EVO con il giocatore
  sinistro all'encoder, NEXT con la CPU sinistra allo spinner).
- Versione web (WebAssembly) per browser, telefoni e tablet Android e iOS (`tools/build-web.ps1`,
  per ora da provare in locale): racchetta che segue il dito, secondo dito per lo scatto,
  tocco su una capsula della riserva per usare il bonus, menu e scelta dei bonus da toccare, pausa
  al centro in alto; in verticale chiede di ruotare il dispositivo; il campo prende le proporzioni
  dello schermo (fino a 2,2:1); manifest per *Aggiungi a Home*. Nel browser del computer il mouse
  fa da dito.
- Versione Rust sul cabinato Raspberry Pi: encoder rotativi con pulsante letti dai GPIO del kernel
  (`/dev/gpiochip*`, Pi 4 e Pi 5, senza il demone pigpio) con gli stessi pin e comandi della
  versione Python, più i pulsanti SELEZIONA e USA di NEXT per giocatore (`e1_select_pin`,
  `e1_activate_pin`, `e2_select_pin`, `e2_activate_pin`); servizio `paddws-rust.service`, che si
  alterna con quello Python; schema di collegamento in `deploy/raspberry/wiring.svg`
  (`tools/gen_wiring.py`).
- Encoder ottici da 360 e 600 impulsi per giro (NPN open collector, per esempio LPD3806) oltre ai
  KY-040, con lo stesso programma: chiavi `pulses_per_revolution` (oltre 30 conta ogni transizione,
  movimento continuo), `turns_per_travel` (giri per tutta la corsa) e `debounce_us` (0 per gli
  ottici) nella sezione `encoder`; lo scatto in avanti va su un pulsante a parte. Schema
  `deploy/raspberry/wiring_optical.svg`.
- Simulatore dei frame MiSTer (`mister/sim/frames/frames.ps1`): ricompila solo quando cambia
  l'RTL e riparte da un checkpoint Verilator a inizio partita; i frame da salvare si scelgono a
  riga di comando.
- PC e web: **mouse come spinner** del giocatore di sinistra (menu **MOUSE SPINNER**, chiave
  `mouse.spinner`, spenta di default; sensibilità `mouse.travel_pixels`). Il cursore resta
  catturato (nella finestra su PC, Pointer Lock nel browser) e il movimento verticale fa da
  encoder ottico: posizione della racchetta, voci dei menu e gesti delle mosse speciali come la
  manopola del cabinato; sinistro = scatto e conferma, destro = seleziona, centrale = usa il
  bonus. Quando è acceso il mouse non fa più da dito nel browser.

### Corretto
- C64: la **coda della palla** a volte compariva davanti alla palla invece che dietro. Dopo un
  rimbalzo, o quando un effetto ripartiva, si riusava l'immagine della coda di prima, con la palla
  nell'angolo della direzione vecchia, finché il frame non aveva il tempo di disegnare quella
  nuova (nei frame carichi, come quelli del colpo, anche per diversi frame). Ora l'immagine di
  prima si usa solo se la palla va nella stessa direzione; se no si vede la palla semplice finché
  la coda nuova non è pronta. Vale anche per la cometa del SUPER, che già si disegnava dalle
  posizioni vere della palla. Il banco `paddws-c64 frames` controlla che non succeda più.
- C64: nelle **iniziali** la lettera in corso spariva per 2,5 secondi ogni 5 (il lampeggio usava il
  bit 7 del contatore dei frame), anche mentre la si cambiava. Ora lampeggia come cursore: spenta
  0,16 s ogni 0,64 s.
- C64: **scritte centrate** nelle schermate prima e dopo la partita: LEVEL n OF 7 e il nome della
  racchetta nella presentazione del livello (8 pixel a sinistra), la classifica di CHALLENGE (16
  pixel a sinistra), WIN BONUS, PERFECT e SCORE di LEVEL CLEAR, SCORE di NEW RECORD, il punteggio
  finale del finale di CHALLENGE e la riga RUN/STOP del menu. Le scritte con un numero dispari di
  caratteri restano mezzo carattere (4 pixel) a sinistra: il set di caratteri è pieno.
- Web, **touch**: macroquad tiene una sola fase per dito e per frame, e quando l'appoggio cadeva
  nello stesso frame del primo movimento o del distacco andava perso. Nel menu a volte la ruota non
  scorreva o il tocco sulla voce gialla non la usava; in partita la racchetta poteva non seguire
  il dito. Ora le dita si leggono una volta per frame (`touch::poll`) e ogni dito arriva sempre
  come appoggio, movimento e distacco.
- Web, **schermo nero su iPhone, iPad e Mac**: macroquad aspetta che ogni suono sia decodificato
  prima di far partire il gioco, e su Safari, con l'audio ancora sospeso prima del primo tocco, la
  decodifica può non finire mai. Ora `audio.js` (copia di quad-snd in `rust/vendor`) legge da sé i
  WAV PCM senza `decodeAudioData`; un suono che non si decodifica, o un browser senza Web Audio,
  danno un gioco muto invece di una pagina ferma. Gli errori della pagina e i panic del gioco
  compaiono in un riquadro rosso in basso (su iPhone la console non si vede senza un Mac).
- Release, pacchetto web: `tools/build-web.ps1` non svuotava `rust/target/web`, e nello zip della
  4.0.0-beta.16 è finito anche un `.wasm` di una build vecchia, mai usato dalla pagina. Ora la
  cartella si ricrea a ogni build.
- C64: nel conto alla rovescia di NEXT un frame poteva superare il budget (circa 18.900 cicli)
  quando l'immagine di una racchetta e una della rotazione del SUPER (circa 10.400 cicli) si
  preparavano nello stesso frame: la rotazione ora parte solo con il frame sotto circa 5.000 cicli.
- EVO e NEXT, **scatto in avanti** che intercetta la palla:
  - con palle veloci in diagonale lo scatto la perdeva spesso, anche quando la racchetta ferma
    l'avrebbe presa: si guardava solo se in quell'istante la palla era all'altezza della
    racchetta. Ora conta tutto il tratto che le resta fino al retro della racchetta di casa;
    il test `rust/core/tests/dash.rs` lo verifica su 4.350 scatti;
  - la palla presa a metà strada riparte dalla faccia della racchetta avanzata e non più da
    dietro.
- NEXT, **GHOST**: la coda della palla restava visibile e tradiva la palla nascosta; con GHOST non
  si disegna più.
- MiSTer, NEXT: con **GHOST** la coda degli effetti (e la scia della cometa e le immagini della palla
  del BULLET) restava disegnata e tradiva dove fosse la palla nascosta: ora non si disegna finché
  GHOST è attivo, come su PC; con la palla nascosta spariscono anche la testa della cometa e le righe
  di STRAIGHT SHOT (`next_render.v`, ingresso `ball_hidden`). Scenario `ghost` del simulatore dei
  frame.
- C64: un pixel grigio lampeggiava nel bordo in basso in tutte le schermate. Bordo e sfondo si
  riscrivevano a ogni frame mentre il raster li disegnava (il "grey dot" del VIC-II); ora si
  scrivono solo quando cambiano.
- C64: il caricatore del BLASTER calava parecchi frame dopo il colpo, perché il disegno dello sprite
  aspettava un frame leggero. Ora le immagini da 0 a 4 colpi si preparano durante il conto alla
  rovescia e cambia solo il puntatore dello sprite.
- CRT del gioco Rust: le linee sottili, come le celle vuote della riserva, sparivano a tratti
  perché lo shader prendeva un solo texel per pixel emulato. Ora il campo viene prima ridotto alle
  righe emulate con la media dei texel.
- C64: in CHALLENGE nessun punteggio entrava in classifica con la classifica iniziale o letta dal
  disco (il posto si calcolava leggendo i punti dal byte sbagliato), quindi le iniziali non
  comparivano mai. Nella scelta dei bonus, con nessun bonus preso la colonna di destra era
  bianca invece che grigia. Il banco di prova controlla tutti e due.
- `mister/sim/run.ps1` si ferma se manca Icarus Verilog invece di ripetere l'esito vecchio.
- C64: il salto del TELEPORT non si vedeva (la racchetta spariva e ricompariva). L'animazione dei
  portali veniva sempre rimandata perché il controllo del raster scattava troppo presto; ora si
  disegna dopo la scena se il frame resta sotto circa 16.000 cicli, con il disegno dei pezzi più
  leggero. Il banco di prova controlla che pezzi e portali compaiano.
- C64: la cometa del SUPER segue la traiettoria vera della palla, con il sistema della coda
  nuova (prima otto comete precalcolate a direzione fissa, ora tolte: 512 byte liberi a `$E000`).
- C64: con TITAN o TWIST la racchetta mostrava un'immagine a strisce gialle e in cima allo schermo
  comparivano pezzi di icone: l'immagine preparata a inizio partita finiva sullo schermo invece
  che nel suo sprite (il puntatore stava in una variabile che il disegno di TITAN e TWIST usa).
  Il banco di prova (`ui`) prepara le immagini di tutti i tipi e controlla che gli schermi restino
  intatti.
- C64: in CHALLENGE (e a volte in NEXT) la racchetta del giocatore non si vedeva. La preparazione
  delle immagini delle racchette a inizio partita usava come lato la riga del raster e rifaceva
  vuota l'immagine sinistra. Il banco di prova ora controlla in NEXT e CHALLENGE che le immagini
  preparate siano pronte e che la racchetta sinistra si veda sempre.
- SID del MiSTer: quando la musica si ferma (inizio partita, attract senza suoni) le voci chiudono
  il gate; prima l'ultima nota della musica restava tenuta.
- Eseguibili Linux compilati su Ubuntu 22.04, così girano anche su Raspberry Pi OS Bookworm
  (glibc 2.36): quelli di 4.0.0-alpha.5 chiedevano la 2.39. La CI fallisce se l'eseguibile chiede
  una glibc più recente della 2.36.
- Versione Rust: salvando le preferenze dal menu `padd_config.json` non viene più riordinato in
  ordine alfabetico; le chiavi restano nell'ordine del file.
- NEXT, scelta dei bonus su PC: i tasti di ciascun giocatore sono centrati sotto la sua colonna
  (prima erano un'unica scritta tagliata dalla mezzeria); contro la CPU compaiono solo quelli di P1.
- MiSTer: l'auto-test non compariva all'accensione (il reset del caricamento del core lo saltava).
- MiSTer: con i punteggi verso i giocatori, INSERT COIN / PRESS START e GAME OVER finivano sopra la
  racchetta avanzata; ora stanno tra la racchetta e la mezzeria.
- MiSTer: il reset dall'OSD azzera anche i crediti.
- MiSTer: il conto alla rovescia è centrato anche con i punteggi verso i giocatori (le cifre del
  font occupano metà della cella e, ruotate in versi opposti, finivano sfalsate).
- MiSTer: in singolo, con i punteggi verso i giocatori, GAME OVER e conto alla rovescia compaiono
  solo verso il giocatore di sinistra.
- MiSTer: il doppio tocco partiva da solo con le piccole correzioni del joystick: ora serve un
  primo tocco breve (fino a ~130 ms) e il secondo entro 200 ms dal rilascio.
- Attract anni '80 al posto dello splash, uguale in Python, Rust e MiSTer (tempi e bitmap 1 bit
  in `assets/attract/`, generati da `tools/gen_attract_assets.py`): auto-test all'accensione,
  strisce che entrano, logo disegnato dal raster con lampo, titolo di 8 s con INSERT COIN /
  PRESS START lampeggianti, crediti e pallina che rimbalza su tutto ciò che è nero.
- Partite a gettoni: un credito per partita (anche in due), tasto **5** o **Select** per il
  gettone; Free Play (default sul PC, opzione OSD sul MiSTer). Fine partita al primo che arriva a
  11 in due, dopo 3 palle perse in singolo (`BALLS n` a schermo), poi GAME OVER e attract.
  Nuove chiavi `game.free_play`, `game.points_to_win`, `game.lives`, `game.self_test`.
- Core MiSTer: attract in hardware (`attract_render.v`) con partita dimostrativa CPU contro CPU
  (solo sul MiSTer), gettoni da joystick e tastiera, file `PaddWS.mra`: il core si installa in
  `_Arcade/` (`.mra`) e `_Arcade/cores/` (`.rbf`); nella release sono in un unico zip,
  `PaddWS_MiSTer_AAAAMMGG.zip`, da scompattare nella radice della SD.
- Core MiSTer provato su DE10-Nano: funziona.
- Difficoltà a 4 livelli (EASY, NORMAL, HARD, EXPERT), con valori separati per il singolo e per la
  partita in due (in due NORMAL è il gioco di prima): accelerazione della palla a ogni colpo e
  velocità massima. Chiave `game.difficulty`, voce DIFFICULTY nel menu del PC, opzione OSD sul
  MiSTer; tabelle nel core Rust, generate per l'HDL da `paddws-trace` e verificate con 3 nuove
  tracce.
- Core MiSTer: doppio tocco su/giù per l'accelerazione rapida, come nell'originale (il tasto B
  resta); opzione OSD *Scores*: verso i giocatori (tavolo, come prima, con GAME OVER e PRESS START
  ripetuti e ruotati per ciascuno) oppure dritti (cabinato, punteggi in alto).
- Icona del gioco (sfondo giallo dello splash, due racchette nere sfalsate), disegnata a parte per
  ogni dimensione da 16 a 1024 px (`tools/gen_icons.py`): incorporata nell'eseguibile Windows
  della versione Rust e usata come icona della finestra in Rust e Python.
- Versione nativa Rust **4.0.0** in `rust/` (anteprime 4.0.0-alpha.1 e alpha.2) (Windows, Linux x86_64, Linux ARM64):
  - `paddws-core`: logica di gioco `no_std` deterministica, solo interi (Q16.16), tick a 240 Hz,
    RNG xorshift32, input esplicito per tick: modello di riferimento per il core MiSTer;
  - `paddws`: gioco completo con macroquad (splash, menu, partita, CRT, 4:3), asset inclusi
    nell'eseguibile, stesso `padd_config.json`;
  - ritmo dei frame: aggancio del dt al refresh, rilevamento del vsync, sincronizzazione GPU
    adattiva, GPU dedicata sui portatili ibridi, priorità MMCSS su Windows.
- GitHub Action che compila e verifica la versione Rust sulle tre piattaforme e allega gli
  eseguibili alle release.
- `tools/rust-env.ps1`: attiva la toolchain Rust portable nella sola sessione corrente.
- Preparazione del core MiSTer ([mister/README.md](mister/README.md)): risoluzione 320×240p a
  15,7 kHz, specifica dell'aritmetica e del formato dei vettori di test.
- `paddws-trace`: genera dal core Rust i parametri Verilog (`pong_params.vh`) e i vettori di test
  tick per tick per il testbench HDL.
- Core MiSTer: `mister/rtl/pong_logic.v`, la logica di gioco in Verilog (FSM, max 7 cicli per
  tick), verificata con `mister/sim/run.ps1` su 5 tracce identiche bit per bit al core Rust.
- Core MiSTer completo: video 320×240p a 15,7 kHz (`video_timing`, `pong_render`), audio dai WAV
  originali (`pong_audio`), joystick e opzioni OSD (`PaddWS.sv` su Template_MiSTer), ROM di font e
  suoni generate da `tools/gen_mister_assets.py`; GitHub Action `MiSTer` con verifica della logica
  e sintesi in Quartus 17.0.2 (Docker), che produce il `.rbf` e lo allega alla release insieme
  agli eseguibili Rust quando il tag coincide con la versione di `rust/Cargo.toml`.
- Opzione `--height` del gioco Rust: con `--width 320 --height 240` si prova sul PC la logica
  del core MiSTer.
- C64, scelta dei bonus di NEXT: il nome e il cursore stavano circa 4 pixel più in alto del centro
  della capsula accanto (2×2 caratteri, con il centro tra due righe). Ora si abbassano di 4 pixel
  con le metà delle lettere, che la cartuccia mette per la scelta al posto delle scritte grandi
  (il set di caratteri è pieno) e che tornano com'erano dopo.
- C64, GHOST: la palla nascosta restava sempre visibile (il disegno ignorava `ghost_phase`).
  Ora si vede solo a lampi come su PC e MiSTer, senza effetti né coda, che la tradirebbero.

### Modificato
- PC, Raspberry e web, **filtro CRT**: `crt_effects.resolution_scale` passa da 6.0 a 1.0 (righe
  emulate 3 × altezza del campo / valore: da 240 a 1.440, scanline molto più fitte) e la
  bombatura scende di un quarto (0,01172 e 0,015625; in `padd_config.json` 0,015 e 0,0225). Chi
  ha nel file la bombatura di prima, mai cambiata a mano, passa alla nuova.
- **YOU WIN** al posto di GAME OVER: quando chi gioca batte la CPU (Classic, EVO, NEXT e livelli
  della CHALLENGE) la partita finisce con la sola scritta YOU WIN, invece di GAME OVER con YOU WIN
  sotto; con la CPU che vince e in due restano GAME OVER e sotto chi ha vinto. Su PC, web,
  Raspberry, MiSTer e C64 (nel giro delle schermate del PC `5_game_over_win`).
- **Punteggi dritti** di default, così non si presume un tavolo con i giocatori seduti ai lati:
  sul PC, web e Raspberry la voce **SCORES** del menu (`game.scores_upright`, UPRIGHT o FACING):
  dritti in alto ai lati della linea centrale, record e palle del singolo a destra, come sul
  MiSTer; FACING è la disposizione di prima, rivolta ai giocatori. Sul MiSTer l'opzione *Scores*
  dell'OSD ora parte da *Upright* (chi aveva salvato una scelta la trova invertita). Il C64 li ha
  sempre dritti.
- **GAME OVER in CHALLENGE** solo quando la partita è finita davvero: a un livello perso si vede
  solo CPU WINS (si può ancora continuare), e GAME OVER, con la sua musica e per il suo tempo,
  quando il CONTINUE scade (o si esce), prima delle iniziali o della classifica. Prima GAME OVER
  compariva prima del CONTINUE e mancava alla fine. Su PC, web, Raspberry, MiSTer e C64 (nel giro
  delle schermate del PC `8_challenge_lost` e `8_challenge_continue_over`).
- C64: la classifica di CHALLENGE non ha più le barre di colore nel bordo, che resta nero.
- Web, **touch** nelle scelte prima della partita: il primo tocco su una racchetta la mostra
  (anteprima e descrizione), un secondo tocco sulla stessa riga la sceglie; il terzo bonus non
  chiude più la scelta, si conferma toccando **OK** in cima alla propria colonna (fino ad allora
  i bonus si possono ancora togliere). Il trascinamento della ruota del menu parte dopo una
  corsa un po' più lunga, così un tocco un po' mosso resta un tocco.
- **Licenza**: il codice di PADD WS (Rust, C64, Python, strumenti) passa dalla MIT alla **GNU GPL
  v3 o successiva** (`LICENSE`): chi lo distribuisce, anche a pagamento e modificato, deve dare i
  sorgenti con la stessa licenza. Il core MiSTer resta GPL v2 o successiva, compatibile perché il
  framework del MiSTer lo è. Le versioni fino alla 4.0.0-beta.16 restano MIT per chi le ha già.
- C64: la CPU usa il BULLET come gli altri bonus, come nel core Rust: prima lo teneva solo per le
  emergenze, e con la riserva piena di BULLET non usava più niente. Si salta al bonus dopo solo con
  un BULLET già armato o in corso.
- C64: il codice della classifica di CHALLENGE sta nella cartuccia (segmento `HSCODE`, copiato a
  `$E000` nel primo frame di disegno della classifica): circa 330 byte liberati nel programma.
- C64, attract: il bordo è giallo anche nei frame in cui si pulisce la bitmap prima delle strisce.
- PC, Raspberry e web: il **menu principale è una ruota** verticale. La voce scelta resta al
  centro, gialla e a 40 px; le altre stanno sopra e sotto su un rullo (0,30 rad per voce), a 30 px
  le vicine e a 20 le altre, sempre più scure verso i bordi; niente riquadri né frecce. Lo
  scorrimento dura 0,18 s e rallenta all'arrivo, la ruota si ferma alla prima e all'ultima voce.
  Su e giù la girano, sinistra e destra cambiano il valore, Invio conferma; la manopola degli
  encoder e il mouse come spinner la fanno girare; sul touch si trascina col dito, un tocco sulla
  voce al centro la cambia o la usa e uno su un'altra voce la porta al centro. Titolo e versione
  restano; le voci sono GAME TYPE, PLAYERS, DIFFICULTY, SUPER MOVES (in NEXT), MUSIC, ATTRACT
  SOUND, WHITE LEVEL, FULLSCREEN, CRT FILTER, MOUSE SPINNER, PLAY e QUIT.
- PC, Raspberry e web: **MUSIC** accende e spegne tutte le musiche (titolo, menu, presentazioni,
  temi della CHALLENGE, livello superato, continue, iniziali, game over), sempre nel menu e non
  solo in CHALLENGE; gli effetti restano. ATTRACT SOUND resta il silenzio di tutto l'attract:
  lì la musica suona solo se sono accese tutte e due. Configurazione: `game.music` al posto di
  `game.sid_sound` e `game.match_music`, che spariscono dal file; se una delle due era `false` la
  musica resta spenta.
- Versione Python: gli effetti WAV "classici" (`ping`, `pong`, `boost`, `error` e `coin.wav`)
  passano da `assets/sounds/` a `paddws/sounds/`, con `tools/gen_sounds.py` e
  `tools/gen_coin_sound.py` che li generano lì: li usa solo lei.
- MiSTer: l'opzione OSD *Match music* diventa **Music: On/Off** (stesso bit 26 dello status) e
  spegne tutte le canzoni del SID, non solo i temi della CHALLENGE: titolo, scelta di NEXT, HOW TO
  PLAY, presentazione, livello superato, continue, iniziali, classifica e game over. Effetti, nome
  dell'avversario e voci di partita restano. *Attract sound: Off* resta il silenzio di tutto
  l'attract (musica ed effetti, non gettone e Start); le due opzioni si sommano. Lo scenario
  `music` del simulatore dei frame controlla che con *Music: Off* non parta nessuna canzone e gli
  effetti sì; lo scenario `mute` guarda ora il player del SID.
- MiSTer: la schermata **HOW TO PLAY** delle mosse speciali è rifatta in stile Neo Geo come quella
  del gioco Rust: per STRAIGHT SHOT e RISING STRIKE la frase dell'effetto, il gesto del controllo
  scelto nell'OSD (joystick arcade di tre quarti inclinato ↓ ↘ → e → ↓ ↘, oppure con paddle e
  spinner la manopola vista dall'alto con la freccia curva della rotazione), "+", il pulsante A
  rosso e DASH, e a destra la palla che parte dritta o che s'impenna; sotto HALF = MOVE e
  FULL = MAX, la legenda dei pulsanti e PRESS START TO SKIP. L'animazione gira di continuo: i passi
  del gesto si accendono uno dopo l'altro con le freccette gialle, poi A si abbassa e la palla
  parte. Nuovo `howto_render.v` con la grafica di `tools/gen_howto_assets.py` (righe delle scritte e
  figurine in 13 M10K, il resto in logica); la vecchia schermata esce da `next_render.v`. Nel
  simulatore dei frame lo scenario `howto`.
- C64: dopo un tick pesantissimo (colpo con le previsioni da rifare, capsula nuova e BULLET nello
  stesso tick), se il frame è già oltre circa 14.800 cicli restano gli sprite del frame prima e il
  resto aspetta come sempre: così anche quei frame restano nel budget (nel banco di prova 6 frame su
  circa 52.000). Il codice delle mosse speciali si copia negli ultimi frame di READY della scelta.
- Effetti sonori dell'opzione **Samples** (PC, web, Raspberry, MiSTer e versione Python): colpo,
  bordo, boost e punto sono ora suoni originali in stile 1972, onde quadre generate da
  `tools/gen_sounds.py` (il gettone era già generato da `tools/gen_coin_sound.py`); la ROM dei
  suoni del MiSTer è rigenerata con `tools/gen_mister_assets.py`.
- NEXT, **GUARDIAN**: al posto della barriera unica che tornava dopo 6 punti c'è un **muro a 5
  settori**, uno per partita. Ogni palla mancata rimbalza sul settore in cui si trova e quel settore
  sparisce. Il muro parte sotto la banda delle riserve: sul MiSTer non copre più la barra delle
  mosse speciali. Il testo della scelta diventa "FIVE-PIECE WALL". Con umani simulati il GUARDIAN
  vince il 53% delle partite contro ARCADE (prima il 45%; con 6 settori il 57%). Su PC, web,
  Raspberry, MiSTer e C64.
- MiSTer, OSD: **Challenge** è ora un valore di "Game type" (Classic, EVO, NEXT, Challenge) e
  non più di "Players", dove con Classic o EVO faceva partire comunque la CHALLENGE.
- MiSTer: le prove delle tracce controllano solo il firmware RISC-V.
- NEXT: velocità massima della palla al livello normale da 9 a 10.
- NEXT, **BLASTER**: caricatore da 4 colpi invece di 3, colpi più veloci (14 px per tick a 60 Hz
  invece di 10). Al posto della barra che si ricaricava dietro la racchetta ci sono le munizioni,
  un rettangolino giallo per colpo in un tratto della racchetta. Su PC, web, Raspberry e MiSTer.
- NEXT, **RUSH**: lo scatto in avanti lascia immagini gialle della racchetta, che sfumano, invece
  delle righe di velocità; anche nella scelta e nella presentazione dell'avversario.
- NEXT, **BULLET**: il bordo giallo della racchetta resta solo mentre è armato.
- NEXT, **SLOW**: il rallentamento dura fino al colpo di chi l'ha usato, non più fino alla fine
  del punto; a quel colpo la palla riparte alla velocità di prima (mai oltre la massima). L'alone
  dura quanto il rallentamento.
- CHALLENGE: nuovi temi.
  - **TITAN**: sempre lento e pesante, ma eroico, in maggiore invece che in do minore.
  - **HAMMER**: drum and bass a circa 180 BPM. Una voce è tutta di batteria (cassa che scende di
    tono a note da un frame, rullante e charleston col rumore), l'altra di un basso profondo.
  - **RUSH** e **BLASTER**: la cassa e il rullante entrano nella voce del basso.
  Il player SID (MiSTer e C64) ha ora 16 strumenti invece di 8, con l'indice a 4 bit.
- CRT del gioco Rust: bombatura dimezzata (le configurazioni con i valori vecchi passano da sole
  ai nuovi).
- CHALLENGE: la voce che annuncia l'avversario è ora urlata, acuta e veloce (circa mezzo secondo),
  come le mosse speciali, invece che grave e lenta.
- NEXT, **mosse speciali**:
  - Ogni mossa spende tutti i settori pieni della barra. Con la barra piena è la **MAX**, più
    forte, con la scritta "MAX" e la racchetta gialla quando è armata.
  - **STRAIGHT SHOT** vale x1,5, x2 la MAX.
  - **RISING STRIKE** non è più un salto della racchetta per salvare le palle lontane, che faceva
    quasi lo stesso lavoro di TELEPORT. Ora è un colpo d'attacco: parte dritto e s'impenna di colpo
    a 45° lontano dalla racchetta avversaria, ai 5/8 del campo (7/8 la MAX). La CPU ci mette il
    suo tempo di reazione ad accorgersene.
  - Le CPU usano le due mosse quando sono già sulla palla, e di solito aspettano la MAX.
  - Tiri vincenti, CPU contro CPU: RISING 14-25%, STRAIGHT 10-24%, tiro normale 11-13%, SUPER
    36-38%.
  - Opzioni `super_rise_max` e `super_rise_seconds` tolte.
- Controlli prima di un push anche sulla macchina forge con i file non ancora committati:
  `forge-check.bat` (`-Synth` per la sintesi del MiSTer), lontano dall'antivirus del PC.
- NEXT: il **BULLET** cambia. Attivato resta armato finché la palla entra nella metà campo di
  chi l'ha lanciato venendo verso di lui (provato anche l'ultimo terzo: durava troppo poco); allora scatta e dura fino alla ribattuta o al punto, non più
  2 secondi fissi (rampa solo in entrata; un punto prima dello scatto non lo consuma). Il gioco
  diventa grigio e sfocato tranne la racchetta di chi lo usa su PC, web e Raspberry; sul MiSTer
  con bordi sfumati; sul C64 solo la logica. Il bordo giallo della racchetta lampeggia mentre è
  armato e sparisce quando scatta. Tolto `next.bullet_seconds`; nelle tracce MiSTer il
  bit 13 della parola 22 dice se è scattato.
- CHALLENGE: i livelli si vincono a 5 punti invece di 7 (Rust, MiSTer e C64). Le percentuali di
  vittoria restano quasi uguali (`paddws-trace --challenge-stats`), le partite durano circa il
  30% in meno. Nella presentazione dell'avversario i suoi bonus hanno anche l'icona, nella
  capsula, sopra il nome.
- C64: con il joystick si rientra dallo scatto spingendo dalla parte opposta all'avversario; verso
  l'avversario si scatta solo con la racchetta a casa (prima la stessa direzione andava e
  tornava). Il banco di prova (`ui`) controlla i quattro casi.
- Il progetto si chiama **PADD WS** (repository `PaddWS`): nuovo logo PADD nello stesso stile
  (splash, attract di Python, Rust, MiSTer e C64, ridisegnato da `tools/gen_splash_logo.py`),
  pacchetti, eseguibili, core MiSTer (`PaddWS.rbf`, `PaddWS.mra`), `.prg`/`.d64`, servizi systemd e
  variabili `PADDWS_*` con il nome nuovo. La configurazione è `padd_config.json` e la classifica
  `padd_scores.json`: al primo avvio i file con il vecchio nome (`pong_config.json`,
  `pong_scores.json`) vengono rinominati. Sul C64 la classifica è `PADDWS.HI` e riparte vuota.
  La cartella `archive/` non è più nel repository. Release e tag precedenti sono stati tolti da
  GitHub: si riparte da 4.0.0-beta.7.
- C64: la coda della palla segue la traiettoria vera. Prima era un'immagine precalcolata in otto
  direzioni (solo 0° e 45° per gli angoli veri della palla); ora è fatta dalle posizioni della
  palla negli ultimi 5 frame, come su PC e MiSTer, piega del rimbalzo compresa. Si prepara a fine
  frame con una cache di 4 sprite: se la forma è già pronta (al più 1 pixel di differenza) basta
  puntarla, altrimenti si disegna con tabelle precalcolate, solo se il frame ha ancora il tempo.
  La firma si aggiorna da quella del frame prima con somme a 8 bit, e il disegno aspetta se il
  frame supererebbe circa 16.500 cicli. Nel banco di prova si disegna nel 12% dei frame con la
  coda, in media +310 cicli per frame di gioco, e il frame più pesante resta quello di prima della
  coda.
- NEXT (Rust, MiSTer, C64): con boost, curva, STEER o SLOW la palla lascia una coda larga quanto
  lei che sfuma dal grigio al nero (0,1 s), al posto dei puntini. Sul C64 la coda è grigia e si
  dirada a retino (sprite della palla multicolore), attaccata alla palla anche in diagonale.
- EVO (Rust, MiSTer, C64): il colpo veloce scatta ogni volta che la palla normale colpisce la
  racchetta dentro la banda grigia; prima serviva il 60% centrale della banda (la soglia dipendeva
  dalla velocità orizzontale) e dalla banda spesso non partiva. La versione Python resta com'era.
- CPU più facile ai livelli NORMAL, HARD ed EXPERT (tutte le versioni tranne Python; EASY resta
  com'era): più errore di mira, più palle mancate e reazione più lenta, perché a NORMAL il
  giocatore medio vinca. Con `paddws-trace --human-stats` il giocatore simulato medio fa circa
  l'84% dei punti a EASY, il 63% a NORMAL, il 44% a HARD e il 27% a EXPERT (prima 84 / 37 / 17 /
  7, media fra tastiera e joystick; a 50 Hz, `--c64`, 86 / 66 / 44 / 29). I livelli di CHALLENGE
  non cambiano.
- CPU (tutte le versioni): dopo lo scatto in avanti resta avanzata 0,3 s mentre la palla si
  allontana, poi torna a casa, così lo scatto si vede; prima tornava subito. Core Rust, CPU del
  MiSTer (`P_CPU_RETURN_TICKS`) e C64 verificati sulle tracce; nella scala di CHALLENGE il livello
  del RUSH diventa un po' più difficile (il giocatore medio lo vince nel 23% delle partite invece
  del 30%).
- NEXT, dopo le prove sul MiSTer: la palla accelera di più a ogni colpo e arriva più veloce ai
  livelli alti (`ball_speedup` 1,06 / 1,10 / 1,14 / 1,18, `ball_max_speed` 7 / 9 / 11 / 13 invece
  di 1,04-1,12 e 6-9), così le partite durano meno e la difficoltà si sente.
- NEXT: TELEPORT salta dove arriverà la palla (previsione con i rimbalzi sui bordi, rifatta a ogni
  tick, quindi segue anche le palle a effetto) invece che alla sua altezza; prende ancora tutte le
  palle. L'animazione segue la palla: la racchetta affonda nel portale mentre la palla va da metà
  campo a 4/10, poi esce dal portale sul punto d'arrivo ed è tutta fuori quando la palla è a 2/10
  del campo, prima che arrivi (su PC e MiSTer).
- Lo scatto in avanti che intercetta la palla non scivola più a schermo: la racchetta compare
  subito sulla palla, che prima sembrava rimbalzare prima del colpo (soprattutto con la CPU).
- MiSTer: le scelte di NEXT (bonus e racchetta) si confermano con **A** invece che con Y.
- NEXT: bonus regolati con partite simulate tra due CPU (`paddws-trace --bonus-stats N`), dove un
  tiro normale vince il 10% delle volte: SMASH (×2,2 e angolata lontano dalla racchetta
  avversaria), CURVE (effetto più forte, che si inverte al rimbalzo) e GHOST (la palla si vede
  solo a lampi per tutto il volo) vincono circa il doppio, SUPER (×3,2 a 45°) il triplo; SLOW toglie un terzo della velocità fino alla fine del punto, per
  raffreddare uno scambio troppo veloce. Scambi da circa 17 s e 9 colpi.
- NEXT: il bonus AIM diventa **TELEPORT**. AIM spostava la racchetta a velocità fissa e contro
  SMASH e SUPER prendeva solo il 71% e il 53% delle palle; ora, quando la palla in arrivo passa
  la metà campo, la racchetta salta alla sua altezza e la segue fino al colpo (prima si muove
  come sempre), e le prende tutte a ogni velocità (`paddws-trace --teleport-stats N`). Il salto ha
  la sua animazione, su PC e MiSTer: la racchetta affonda in una linea orizzontale (il portale)
  ed esce da un'altra all'altezza della palla, in circa 0,2 s, con il suono del boost. Nuova
  icona (due portali e una freccia); con TELEPORT armato la racchetta lampeggia e mostra l'icona
  come con gli altri bonus. Nuovo evento `Teleport` (bit 7), verificato nelle tracce MiSTer.
- Simulazioni dei bonus con tre modi di comandare la racchetta (`--control spinner|joystick|keyboard`,
  anche diversi per i due giocatori): i bonus pesano di più contro tastiera e joystick che contro
  uno spinner; la regolazione è tarata sul joystick.
- CPU più umana: tempo di reazione, errori e palle mancate che crescono con la velocità della
  palla, niente previsione con CURVE e GHOST, scatto in avanti solo quando intercetta davvero.
- Attract: auto-test, strisce e logo durano il doppio (4,8 s, 2,4 s e 2,2 s).
- Accelerazione rapida della racchetta (doppio tocco, tasto B) dimezzata:
  `paddle.fast_acceleration` passa da 2 a 1.
- In singolo il muro non accelera più la palla: accelerano solo i colpi del giocatore, quindi la
  velocità cresce la metà di prima. Le chiavi `ball.kspeed`, `ball.max_speed_1p` e
  `ball.max_speed_2p` sono sostituite da `game.difficulty` (nei vecchi file vengono ignorate).
- Core Rust senza divisioni nel passo di simulazione (reciproci precalcolati, tabella dei
  livelli dell'area boost, punto medio per il contatto), come richiesto dall'hardware.
- Core Rust: dimensioni arrotondate al pixel più vicino e velocità non più troncate all'intero
  (a 320×240 la troncatura rendeva uguali palla normale e potenziata e rallentava il gioco).
- PC, web e Raspberry: la schermata **HOW TO PLAY** delle mosse speciali è rifatta in pixel art
  a 320×240 come nei giochi Neo Geo. Per ogni mossa il comando del controllo in uso si accende
  passo dopo passo (tasti disegnati, con quelli di P2 in due sulla tastiera; manopola dello
  spinner con la freccia curva; mouse; dito che scorre e tocco del secondo dito), poi il pulsante
  si abbassa e nel riquadro a destra la palla parte dritta (STRAIGHT SHOT) o s'impenna (RISING
  STRIKE). Sotto: mezza barra = mossa, barra piena = MAX, i comandi dei bonus e la scritta per
  saltare adatta al controllo. Il giro delle schermate (`--screenshot-tour`) la salva per ogni
  controllo, compreso il joystick con i pulsanti A, B, C del MiSTer.
- C64: la classifica di CHALLENGE della cartuccia EasyFlash **si salva nella sua flash** (prima
  restava in RAM fino allo spegnimento): un posto da 128 byte per salvataggio nel banco 16, con
  riconoscimento e controllo, e la cancellazione del settore (circa 1 s) ogni 32 salvataggi o se
  il posto non è cancellato; un salvataggio interrotto dallo spegnimento lascia quello di prima.
  Comandi dell'Am29F040 nel modo Ultimax, senza l'EAPI (VICE con `-easyflashcrtwrite`, C64
  Ultimate). Le routine che leggono e scrivono la flash stanno nella RAM della cartuccia
  (`c64/src/ef.s`, copiate all'avvio), la classifica a `$0200`. Il banco di prova emula la
  EasyFlash (banchi, modi e comandi della flash) e prova i salvataggi, la cancellazione, un posto
  scritto a metà, dati di prima nella flash e una flash che non si scrive.
- C64: memoria del programma liberata: il titolo dell'attract arriva dalla cartuccia (via il
  decompressore e il titolo compresso); le routine che servono solo all'avvio (`clear_vars`,
  `math_init`, `irq_init`, `video_init`, `input_init`, `sid_init` e l'auto-test dell'accensione)
  stanno nella flash e girano da `$F800`, dove le copia `title_unpack`; la classifica iniziale e la
  sua lettura nel segmento dell'avvio. I caratteri della capsula del BULLET arrivano dalla
  cartuccia. Restano circa 450 byte liberi nel programma (erano una cinquantina nel `.prg` per il
  disco), con lo scatto nuovo e il tempo dinamico della musica già dentro, e circa 780 nel segmento
  dell'avvio.
- C64: **tempo dinamico della musica**, con le regole del SID Rust: al match point la canzone va a
  62,5 Hz (5 passi ogni 4 frame: il passo in più in un frame che ha tempo), nel bullet time avanza
  un passo su due un'ottava sotto, con le note in corso che cambiano ottava al passo dopo; le due
  regole si sommano, gli effetti restano a 50 Hz. `paddws-c64 sid` confronta passo per passo il
  6502 con il player Rust in 6 canzoni, `frames` conta i frame al match point e nel bullet time.
- C64: lo scatto segue il core: la palla presa riparte dalla faccia della racchetta avanzata, e la
  presa guarda il tratto fino al retro della racchetta di casa un tick alla volta (fino a 64
  passi). Il 6502 segue un solo margine verticale e si ferma appena l'esito è deciso: al massimo
  circa 7.300 cicli. `paddws-c64 game` prova anche 4.000 scatti a caso contro il core.

### Rimosso
- PC, Raspberry e web: la voce **SOUND: SID / SAMPLES** e i campioni originali (normali e
  rallentati per il bullet time): effetti sempre del SID. Le voci di partita (urla, READY, GO e il
  nome dell'avversario) restano.
- MiSTer: il valore **Samples** dell'opzione *Sound* (i WAV originali al posto del SID) con il
  player di campioni `rtl/pong_audio.v`, la ROM `rtl/gen/pong_sounds.hex` e `.vh` e la parte dei
  suoni di `tools/gen_mister_assets.py`, che ora genera solo i font. *Sound* è il bit 23 (SID 8580
  o SID 6581): un CFG di prima con Samples suona con l'8580. Le voci di partita (urla delle mosse,
  READY e GO) si sommano all'uscita del SID con tutti e due i filtri, come prima; il nome
  dell'avversario, che solo con i campioni si sommava a parte, resta nel volume del SID.
- MiSTer: la logica di gioco e le CPU in Verilog di prima (`mister/rtl/pong_logic.v`,
  `cpu_player.v`, il testbench `mister/sim/tb_pong_logic.v`), l'opzione `-Old` di
  `mister/sim/rv/rv.ps1` e, da `pong_params.vh`, le tabelle e i parametri che servivano solo a loro
  (restano quelli dei renderer e di `pong_top`); `P_CPU` da `trace_config.vh`. Icarus Verilog non è
  più nell'immagine di forge.
- C64: le versioni su disco (`paddws.d64`) e in `.prg` dal pacchetto `-c64.zip`, con
  `tools/make_d64.py`, il caricamento delle voci da disco e il salvataggio della classifica con il
  KERNAL: resta la cartuccia EasyFlash `paddws.crt`. Il `.prg` si assembla ancora per il banco di
  prova; `c64/shot.ps1` avvia sempre la cartuccia (opzione `-Write` per tenere la flash scritta).
- Gioco Rust: le musiche registrate in OGG (`assets/sounds/sid/*.ogg`) e `tools/encode_sid_songs.py`,
  sostituite dal SID in tempo reale; `soundfile` dalle dipendenze di sviluppo Python.
- MiSTer: `clean.bat` e `rtl/pll/pll_0002_q13.qip` del template, non usati.

## [3.1.0] - 2026-10-28

### Aggiunto
- Supporto per monitor 4:3 e qualsiasi altro formato: con `resolution.width = 0` (nuovo
  default) il campo prende le proporzioni dello schermo (640×480 su 4:3, 853×480 su 16:9).
- Versioning: changelog, tag git, script di rilascio, versione mostrata nel menu e nel log.

### Modificato
- Lo splash viene ritagliato invece che deformato su schermi con proporzioni diverse.
- Il record in singolo (`TOP`) è più grande, leggibile anche con il filtro CRT, e centrato
  sul punteggio.

## [3.0.0] - 2026-10-28

Riordino completo del progetto e motore riscritto.

### Aggiunto
- Package `paddws` con logica di gioco pura in `paddws/core`, test pytest, `pyproject.toml`.
- Fisica a passo fisso (240 Hz) con interpolazione, un aggiornamento per frame presentato,
  rilevamento del vsync ignorato dal driver, sincronizzazione GPU adattiva.
- Filtro CRT a risoluzione interna limitata (720p), voce CRT nel menu.
- Pausa (`P`), attesa alla battuta, opzioni da riga di comando, servizio systemd per il Pi.

### Corretto
- Punteggio in singolo (mancare la palla dava punti, il record non si aggiornava).
- Encoder rotativi di nuovo funzionanti in menu e in partita.
- Schermo intero con proporzioni corrette, scaling HiDPI su Windows.
- Lampo bianco al punto, palla che attraversava le racchette veloci, suono del boost in avanti.
- Contesto OpenGL ES su Raspberry Pi (OpenGL 3.3 non disponibile).

## Versioni precedenti

Ricostruite dalle cartelle di backup in `archive/` (date indicative).

- **2.7** (2025-07) – porting su Arcade con filtro CRT a shader (`archive/v2.7-arcade-original`).
- **2.6** (2025-07) – regolazione del rumore CRT e delle modalità video.
- **2.5** (2025-07) – effetto CRT di pixelazione al posto del bagliore.
- **2.4** (2025-07) – effetti CRT software (`crt_effects.py`).
- **2.3** (2025-07) – taratura dell'accelerazione rapida e del boost in avanti.
- **2.2** (2025-07) – boost in avanti nella modalità EVO.
- **2.1** (2025-07) – scaling automatico sulla risoluzione e configurazione JSON.
- **2.0** (2025-07) – accelerazione progressiva delle racchette e doppio tocco.
- **1.8** (2021-11) – aggiornamento alle nuove API di pygame-menu, build PyInstaller.
- **1.7** (2020-12) – collisioni e punteggio in funzioni dedicate, taratura di palla e racchette.
- **1.6** (2020-08) – loop di menu e di gioco separati, spegnimento del Pi dal menu.
- **1.5** (2020-08) – versione per Raspberry Pi con encoder rotativi.
- **1.1 – 1.4** (2020-08) – prime versioni pygame: menu, modalità CLASSIC ed EVO, suoni, splash.

[Non rilasciato]: https://github.com/Schermobianco/PaddWS/commits/main
