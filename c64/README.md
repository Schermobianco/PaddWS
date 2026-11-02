# PADD WS – versione Commodore 64

Stato: **in sviluppo** (fase 8 di 9: attract, demo, gettoni e menu; Classic, EVO e singolo si
giocano, anche contro la CPU, con musiche ed effetti del SID. NEXT è completo: scelte, riserve,
capsule, tipi di racchetta ed effetti, BULLET e mosse speciali compresi. CHALLENGE è completo, con la classifica salvata nella flash della cartuccia,
il nome dell'avversario, READY? e GO! detti dal SID, il tema dell'avversario in partita e il finale. Esce come cartuccia EasyFlash.
Mancano NTSC e le prove sull'hardware). È nelle release come anteprima, solo PAL.

## Avviare

`paddws-X.Y.Z-c64.zip` contiene `paddws.crt`, la cartuccia EasyFlash (tutto in un file: programma,
voci di CHALLENGE, classifica). Si scrive nella flash di una EasyFlash con EasyProg, oppure si monta
sul C64 Ultimate o in un emulatore; parte all'accensione, senza caricamenti. La classifica di
CHALLENGE si salva nella flash della cartuccia, quindi resta anche da spenti: sul C64 Ultimate e in
VICE il `.crt` deve essere scrivibile (in VICE: `x64sc -easyflashcrtwrite -cartcrt paddws.crt`,
oppure *Save image when changed* nelle impostazioni della EasyFlash).

La versione C64 gioca la stessa partita del core Rust ([`rust/core`](../rust/core)), bit per bit:

- campo 320×200 (tutto lo schermo del VIC-II);
- un tick per frame a 50 Hz (PAL; la struttura è pronta per NTSC);
- stessi parametri delle altre versioni (`Tuning::c64()`), convertiti sulla frequenza e sul campo;
- aritmetica Q16.16 a 32 bit in 6502, identica a `fixed.rs`.

## Scelte

- **Un tick per frame.** Lo schermo mostra uno stato per frame, quindi più tick per frame
  costerebbero cicli senza differenze visibili. Le collisioni sono continue, quindi anche il SUPER
  (circa 20 px per tick) non attraversa le racchette. A 240 Hz i parametri restano quelli di
  sempre: le tracce del MiSTer sono identiche.
- **Previsioni a passi di un tick.** CPU e TELEPORT prevedono il punto d'arrivo della palla con lo
  stesso orizzonte delle altre versioni. Un passo per tick fa sì che la previsione non cambi lungo
  un tratto rettilineo: il 6502 la calcola una volta per tratto e resta identico al core (la CPU
  la rifà dopo un evento che tocca la palla, il TELEPORT quando la palla cambia velocità o non
  avanza come previsto).
- **Moltiplicazioni** con le tabelle dei quarti di quadrato (8×8 bit), i byte nulli saltati e
  tutto srotolato: al massimo circa 1.200 cicli per un prodotto Q16.16 completo, molto meno con i
  valori di gioco. Il generatore (xorshift32) fa gli shift con due tabelle: 166 cicli.
- **Budget del frame** (circa 18.000 cicli utili su 19.656 in PAL): la demo resta sotto i 15.200;
  le partite NEXT e CHALLENGE contro la CPU arrivano a circa 16.800 nei frame più pesanti (un
  colpo che attiva un bonus mentre la CPU rifà la previsione), anche con le mosse speciali, circa
  17.900 con il BULLET sempre in gioco e il tema del BLASTER. Un tick pesantissimo (colpo con le
  previsioni da rifare, capsula nuova e BULLET nello stesso tick, circa 12.000 cicli più la CPU)
  lascerebbe il frame oltre il budget: se dopo la scena il frame è già oltre circa 14.800 cicli
  restano gli sprite del frame prima (nel banco di prova 6 frame su circa 52.000) e il resto
  aspetta come sempre. Il tema di CHALLENGE
  costa fino a circa 1.700 cicli nei frame in cui partono due note (circa 2.500 con le frequenze
  riscritte quando cambia il bullet time): se il frame è già oltre i 15.500 cicli il tick della
  musica aspetta il prossimo (circa un frame ogni 1.200). Il lavoro che si ripete uguale si
  salta (le immagini delle racchette si rifanno solo quando cambia l'altezza, la tastiera si legge
  riga per riga solo con un tasto premuto), quello lungo si divide su più frame (pulizia della
  bitmap delle strisce, schermo della demo, schermate e classifica di CHALLENGE).

Bilanciamento misurato con `paddws-trace --c64` (giocatori umani simulati): scambi e partite
simili alle altre versioni, con gli scambi di NEXT più lunghi del 17% circa. Nella scala di
CHALLENGE l'ultimo livello è un po' più facile: il giocatore medio con il joystick batte il boss
nel 33% delle partite, contro il 22% su PC.

## Compilare e verificare

Toolchain portable in `C:\DEV\@Compiler`: cc65 (ca65/ld65) e VICE (x64sc).

```powershell
.\c64\build.ps1                     # c64\build: paddws.crt; paddws.prg (etichette, mappa) e voci per il banco di prova
.\c64\shot.ps1 boot.png             # avvia la cartuccia in VICE e salva la schermata
.\c64\shot.ps1 v.png -Prg autoch -Sid 8580 -Wav v.wav -Cycles 26000000
                                    # un'altra build, con il suono in WAV (-Write: la flash scritta resta nel .crt)
. .\tools\rust-env.ps1; cd rust
cargo run --release -p paddws-c64 -- params   # c64\gen\params.inc dal core Rust (--check per verificarlo)
cargo run --release -p paddws-c64 -- math     # aritmetica 6502 contro il core Rust
cargo run --release -p paddws-c64 -- game     # partite intere, stato confrontato a ogni tick
cargo run --release -p paddws-c64 -- sid      # player del SID contro quello Verilog, temi di CHALLENGE compresi; tempo dinamico e canzone del finale contro il player Rust
cargo run --release -p paddws-c64 -- ui       # ogni scena e routine del menu torna; voci di CHALLENGE, caratteri della scelta, classifica nella flash, gesti e schermo delle mosse speciali; finale saltato, YOU WIN nel GAME OVER
cargo run --release -p paddws-c64 -- frames   # attract, partite EVO, NEXT (anche con le mosse speciali e con il BULLET sempre in gioco e il tema del BLASTER) e CHALLENGE (P1 al joystick, con il tema, le voci e le mosse speciali): nessun frame oltre il budget; bordo della partita (BORDER GRAY), barre della classifica, il finale da capo
cargo run --release -p paddws-c64 -- ending   # solo il finale, come alla fine di frames
cargo run --release -p paddws-c64 -- profile  # cicli per routine: demo, partita, tick NEXT con due CPU
```

La cartuccia di ogni run della GitHub Action `C64` si scarica tra gli artifact (`paddws-c64`).

Il `.prg` da solo non parte (gira dalla cartuccia, che lo copia in RAM): serve al banco di prova
(`rust/c64`, `paddws-c64`), che lo carica con le etichette (`paddws.lbl`) e la cartuccia in un
emulatore 6502 (verificato con il test funzionale di Klaus Dormann), chiama le routine per
etichetta e confronta i risultati con il core Rust, contando i cicli. Del C64 emula anche la RAM
sotto l'I/O, la riga del raster e il timer A del CIA2 con l'NMI, per le voci di CHALLENGE, e la
EasyFlash: banchi, modi (a 8K, 16K, Ultimax, con la RAM che nel modo Ultimax non c'è) e i comandi
della flash. `ui` controlla che senza file voce (presentazione e conto alla rovescia) non succeda
nulla; poi gioca una scala con i 7 file copiati dalla cartuccia nell'ordine dei livelli (uguali ai
file voce), con le immagini degli effetti sopra il file: il volume riceve i campioni di ogni nome, di READY e di
GO nell'ordine, uno per NMI, READY parte al primo frame del conto alla rovescia e GO al via (prima
solo l'attacco), il tema arriva a `$F800`; senza il file del primo livello gli altri non dicono
niente, `VOICE_STOP` e `sid_song` fermano subito la voce. Poi `ef_pick` (i caratteri della scelta
dei bonus e di nuovo quelli di prima), le mosse speciali (sotto) e la classifica nella flash: 70
salvataggi, ognuno uguale
all'avvio, con le due cancellazioni del settore; un posto scritto a metà che non conta; dati di
prima nella flash, che il salvataggio cancella; una flash che non si scrive, che il programma
lascia stare; mai un accesso alla RAM che nel modo Ultimax non c'è. `frames` copia il file voce
dalla cartuccia in ogni presentazione (fuori dal budget, come un caricamento: circa 60.000 cicli
a schermo fermo), conta gli NMI nei cicli del frame, controlla READY e GO in ogni conto alla rovescia
di CHALLENGE (anche nella sfida con lo sfidante) e che il tema suoni in tutte le partite contro la
CPU di CHALLENGE e in nessun'altra; in più una partita NEXT con le mosse speciali (P1 fa i gesti
del joystick, la CPU usa le mosse) e, con le mosse accese, quella con il BULLET sempre in gioco e
le due di CHALLENGE: il codice delle mosse dev'essere quello del `.prg` e barre, icone,
racchetta gialla, scritta, palla gialla ed effetti del SID devono comparire. `game` gioca 33
partite da 5 minuti (EVO a tutte le difficoltà, Classic, singolo, manopola, CPU contro CPU, NEXT
con tutti i tipi di racchetta, 8 NEXT con le mosse speciali: CPU contro CPU e giocatori al
joystick, letti dal 6502 con `read_input` e `build_input` e dati al core così) con gli stessi
comandi sul 6502 e sul core, e confronta palla, racchette, punteggi, generatore, eventi, stato di
NEXT (BULLET compreso: chi l'ha attivato, se è scattato e la rampa; mosse speciali: barra, mossa
armata e livello, tiro in volo e livello, soglia dell'impennata) e punti arcade di CHALLENGE dopo
ogni tick; con le CPU confronta anche i comandi, tick per tick. Le partite NEXT passano tutte per il bullet time; in quelle con lo script ogni tanto un
BULLET entra nella riserva vuota (uguale nel core e nel 6502), così ci sono anche BULLET armati
quando arriva un punto. `game` fallisce se nel totale manca uno dei casi: armato, scattato, finito
alla ribattuta, ancora armato dopo un punto; e, per le mosse speciali, se manca una mossa o un
livello, una mossa della CPU, un gesto da sinistra o da destra, un colpo con la mossa,
un'impennata, una mossa persa al punto o il fuoco di un gesto che attiva il bonus perché la mossa
non può partire. Poi 4.000 scatti in EVO con palle a caso nella fascia
tra la faccia di casa e quella avanzata (ogni inclinazione, anche orizzontale, e velocità da quella
della battuta più lenta): stesso stato del core dopo il tick, e devono esserci palle prese e no.

## Logica

`src/game.s` traduce `Match` di `rust/core/src/game.rs` routine per routine, con la stessa
sequenza di operazioni. Le macro a 32 bit di `src/math.s` accettano indirizzi, indirizzi
indicizzati (`{pad_y,x}`: le racchette sono vettori indicizzati con X = lato × 4) e costanti
(`{#P_WIDTH}`). I parametri sono in `gen/params.inc`, generato dal core (`paddws-c64 params`).

Cicli per tick, su circa 18.000 disponibili in un frame PAL (grafica, SID e input ne usano
3.000-5.000): senza CPU circa 2.700 in media; con due CPU circa 5.000 in Classic ed EVO (al
massimo 10.200) e 6.500 in NEXT (al massimo circa 15.000, quando un rimbalzo fa rifare insieme la
previsione della CPU e quella del TELEPORT).

### Scatto

Come `Match::ball_in_forward_area`: lo scatto prende la palla se è in arrivo tra la faccia di casa
e quella avanzata e se, nel tratto fino al retro della racchetta di casa percorso un tick alla
volta (al massimo 64 passi, senza rimbalzi), passa all'altezza della racchetta; presa, riparte
dalla faccia della racchetta avanzata (`forward_boost`). Il 6502 dà lo stesso esito con meno
lavoro: dei due margini verticali ((h + r) ∓ (y - y racchetta)) segue solo quello che cresce di
|vy| a ogni passo (l'altro è 2(h + r) meno il primo), si ferma al primo passo in cui è positivo
(presa se lo è anche l'altro, altrimenti mai più) e con vy = 0 guarda solo il primo passo. Nel caso
peggiore, 64 passi con la battuta più lenta (|vx| di circa 1 pixel per tick), circa 7.300 cicli;
il tick più pesante delle prove di `game` sullo scatto è di circa 9.900.

### Mosse speciali

`src/supers.s` traduce `Next::super_moves` (rust/core/src/next.rs) e `Cpu::special` (cpu.rs), con
l'opzione **SUPER MOVES** del menu (`cfg_super`, spenta all'accensione), per NEXT e CHALLENGE.
Spente, la partita è quella di prima: le chiamate nel tick guardano `sm_on` e lo stato resta a
zero.
- **Barra** (`sm_meter`, 0-64): +2 a ogni colpo, +4 con lo scatto che intercetta la palla (il bit
  7 di `sm_dash`: `next_on_hit` riceve il carry dallo scatto), +8 per un punto subito, fino al
  massimo; resta da un punto all'altro.
- **Mossa** (`IN_STRAIGHT`, `IN_RISE` in `in_flags`, alla fine del tick NEXT, fuori dalla
  battuta): costa 32 e spende tutti i settori pieni, il livello è quanti (1, 2 = MAX). Non parte
  con un'altra mossa o un bonus armato; mentre è armata non si attivano bonus. `sm_arm`: 1-2
  STRAIGHT SHOT, 3-4 RISING STRIKE.
- **Al colpo:** STRAIGHT SHOT mette vy = 0 e `boost += boost >> (shift + 2 - livello)` (x1,5,
  x2 la MAX, sul boost che il colpo ha già: HAMMER, RUSH, scatto); RISING STRIKE mette vy = 0 e
  la soglia (`sm_rise`: indice di quattro soglie intere, 5/8 o 7/8 del campo da chi colpisce).
  Passata la soglia (prima di CURVE e STEER, come in `ball_motion`) vy diventa ±|vx|, lontano
  dalla racchetta verso cui va la palla; le previsioni delle CPU si rifanno (quella tenuta da
  parte guarda vx e boost, non vy) e la CPU che riceve rifà il tempo di reazione (`cpu_wrise`).
- **CPU** (`sm_cpu`, se non attiva un bonus): con la palla in arrivo già vista, la mossa pronta,
  la racchetta entro mezza altezza dal punto d'arrivo previsto e nessun errore di mira voluto,
  un'estrazione `below(odds * 2)` dal suo generatore (odds = probabilità dei bonus, il doppio con
  un settore solo): 0 STRAIGHT SHOT, 1 RISING STRIKE.
- **Gesto del joystick** (`sm_joy`, in `next_keys`), come `move_gesture` del MiSTer con i tempi a
  50 Hz: per giù, giù-avanti e avanti si contano i frame da quando erano tenuti (avanti = verso
  l'avversario: destra per il sinistro, sinistra per il destro); giù, giù-avanti, avanti +
  fuoco = STRAIGHT SHOT, avanti, giù, giù-avanti + fuoco = RISING STRIKE, le direzioni a non più
  di 15 frame (0,3 s) l'una dall'altra, il fuoco entro 13 (0,25 s) dall'ultima. Il fuoco che
  chiude il gesto diventa la mossa solo se la mossa può partire (barra, niente di armato, palla in
  gioco), e allora non attiva il bonus; altrimenti attiva il bonus come sempre. Avanti è anche lo
  scatto: la mezzaluna con la racchetta a casa scatta in avanti, come con un avanti qualsiasi.
- **Paddle:** nessun gesto. Il riconoscitore della manopola del MiSTer (tratti rapidi giù-su o
  su-giù + pulsante) costa circa 400 byte e non c'è posto; con i paddle le mosse non si usano (la
  CPU sì).
- **A schermo:** la barra di ciascun giocatore accanto alle riserve (riga 1, colonne 6-9 e
  30-33): quattro caratteri con il bordo sopra e sotto e il pieno a passi di 2 pixel (un passo
  ogni 4 unità), grigi, gialli per settore pieno (mossa pronta; tutta gialla la MAX). I 5
  caratteri prendono in NEXT il posto di caratteri di PRESS START, che si vede solo nella demo:
  `sm_init` li scrive a inizio partita, `bullet_chars` rimette gli originali nelle altre partite
  (40 byte a `$FFC3`, dalla cartuccia all'avvio). La mossa armata ha l'icona gialla accanto alla
  racchetta nello sprite dell'icona del bonus (freccia verso l'avversario per STRAIGHT SHOT,
  freccia che piega in su per RISING STRIKE, preparate nei primi frame a `$E940`); la MAX fa
  gialla la racchetta. All'attivazione la scritta "P1 STRAIGHT SHOT!" o "P1 MAX RISING
  STRIKE!" in basso, come quella dei bonus. Nel tiro della mossa la palla è gialla con la coda;
  quando RISING STRIKE s'impenna lampeggia bianca per 12 frame.
- **Suoni:** gli effetti MOVE (attivazione) e SPECIAL (colpo) della ROM della musica, che
  `tools/gen_sid_music.py` mette in fondo, dopo i temi, fuori da `gen/sid_music.bin`:
  `tools/gen_c64_assets.py` prende le due tracce dalla ROM del MiSTer (la variante del C64,
  `mister/rtl/gen/c64`) e il player le ha come effetti 6 e 7 (`fx_start`), con le priorità del
  player Verilog (SPECIAL dopo il punto, MOVE anche dopo il BOOST). Partono in `sm_hud`, se il
  frame ha tempo, e prendono il posto dell'effetto rimandato del tick. Le voci urlate del PC e del
  MiSTer non ci stanno.
- **Dove sta:** il programma è quasi pieno. Il grosso (circa 1.000 byte) è nella cartuccia
  (segmento `SMCODE`, nel `.prg` da `$D800`, cioè nel banco 4 della ROML da `$9000`) e gira a
  `$C400`, nella RAM del secondo schermo, che serve solo ai colori della bitmap dell'attract: la
  scelta di NEXT lo copia negli ultimi 4 frame di READY, una pagina per frame (`sm_page`, circa
  3.800 cicli). Ogni partita NEXT passa dalla scelta, e l'attract, che ricopre quella RAM, viene
  sempre dopo. Le routine piccole usate anche fuori dal tick (pronta, barra, punto, icona:
  segmento `LOWCODE`) stanno a `$0284-$0313`, dove `title_unpack` le copia all'avvio; nel
  programma restano le chiamate (circa 190 byte), il menu, `sm_page`, `sm_init`, il colpo e la
  scritta.

Il banco di prova `ui` copia il codice con `sm_page` e controlla la voce del menu, 18 gesti del
joystick dai due lati (le due mezzelune, avanti prima della mezzaluna, barra sotto il costo o
vuota, gesto lento, fuoco tardi, mezzaluna all'indietro o in su, la battuta), la scritta, la barra
e le tracce degli effetti 6 e 7 contro quelle della ROM della musica. Per le schermate in VICE:
`.\c64\build.ps1 -Name autosm -Define AUTOSTART,AUTONEXT,SMTEST` (mosse accese, NEXT CPU contro
CPU), con anche `SMFULL` le barre sempre piene.

### BULLET

Il BULLET (bullet time, `src/next.s`) arriva solo dalle capsule: un'estrazione a 16 bit del
generatore (`rng_next`, come `Rng::bits16`) sotto `P_SUPER_CUT` dà il SUPER, sotto `P_BULLET_CUT`
il BULLET, altrimenti uno dei bonus scelti (codice 7; il posto vuoto della riserva è 8). Non
resta tra i bonus armati del giocatore, ma uno alla volta (armato o in corso blocca gli altri):

- **armato:** dall'attivazione finché la palla è nella metà campo di chi l'ha attivato
  (`P_BULLET_ZONE`: x < 160 a sinistra, x > 160 a destra) e va verso di lui;
  nessun rallentamento. Un punto non lo consuma;
- **scattato** (`bullet_step` all'inizio del tick, e già all'attivazione se la palla è lì):
  rallenta tutto tranne la racchetta di chi l'ha attivato. Il passo del tick diventa
  `v - (v >> k)` (`slow_v`), con `k` più piccolo nei primi `P_BULLET_RAMP` tick; la velocità
  memorizzata non cambia. Rallentano il passo della palla e le accelerazioni di CURVE e STEER, la
  racchetta avversaria (anche con la manopola, al passo di una mano veloce), le capsule e i colpi
  avversari del BLASTER; lo scatto in avanti no;
- **finito:** all'inizio del tick in cui la palla non va più verso chi l'ha attivato (l'ha
  ribattuta), oppure al punto.

Lo stato sta in due byte: `nx_bside` è chi l'ha attivato (0 o 4, il bit 7 acceso se non c'è) e
`nx_btimer` è 0 finché non scatta, poi i tick di rampa rimasti + 1 (si ferma a 1). Così tutto quello
che guarda solo il bullet time in corso controlla `nx_btimer` come prima. La condizione "palla
verso di lui e oltre la soglia del suo lato" è la stessa del TELEPORT, con un'altra soglia
(`ball_in_zone`: Y sceglie la soglia del TELEPORT o quella del BULLET, oggi tutte e due a metà campo; le soglie sono pixel
interi, quindi a sinistra basta la parte intera di x; `ball_toward` serve anche alla CPU).

Per restare nel frame:
- capsule e colpi hanno sempre velocità ± costante: i loro passi rallentati sono costanti
  calcolate dall'assembler (`cap_sx`, `cap_sy`, `shot_sx`), niente shift a ogni tick;
- il passo da rallentare sta nel prodotto delle moltiplicazioni (`m_p`, in pagina zero), che lì
  non servono;
- le previsioni di CPU e TELEPORT non si rifanno a ogni tick (circa 1.600 cicli l'una): con la
  palla rallentata il risultato cambia, ma si aggiorna dall'ultimo passo della palla
  (`cpu_step`, `pred_advance`). Il resto della divisione dei passi perde il passo orizzontale
  (sotto zero, un passo in meno); la y senza bordi prende il passo verticale, meno vy per il
  passo in meno; poi si rifanno solo le riflessioni sui bordi (`fold_y`). Esce lo stesso numero
  del calcolo da capo.

La CPU lo usa come gli altri bonus (stessa probabilità quando la palla arriva), e in più nelle
emergenze (`bullet_rescue` in `src/cpu.s`, come `Cpu::bullet_rescue`): palla in arrivo, vista,
veloce e vicina, punto d'arrivo fuori dalla racchetta, nessun errore di mira voluto e nessun
BULLET armato o in corso. Allora lo seleziona e lo attiva, con probabilità 16 volte più alta degli
altri bonus. Con un BULLET già armato o in corso, se è selezionato passa al successivo.

## Come si gioca

L'attract è quello delle altre versioni:
1. auto-test, solo all'accensione;
2. strisce che entrano, logo che si scopre con il raster bianco e un lampo (bordo giallo, come
   lo sfondo);
3. titolo con la pallina che rimbalza sul nero;
4. classifica di CHALLENGE, con le barre di colore nel bordo;
5. demo CPU contro CPU (EVO, Normal);
6. di nuovo le strisce.

Gettoni e partenza:
- **5** inserisce un gettone, fino a 9 crediti; Free Play è acceso di default.
- **FUOCO**, **RETURN**, **SPAZIO** o **1** spendono un credito e aprono il menu. Le stesse scritte
  INSERT COIN, PRESS START e CREDIT n delle altre versioni dicono cosa serve.

Il menu si usa con il joystick (o i cursori): su e giù scelgono la voce, sinistra, destra o il
fuoco cambiano il valore, e il fuoco su **PLAY** inizia la partita. **RUN/STOP** torna
all'attract. Le voci:
- GAME: Classic, EVO o NEXT (EVO e NEXT sono a due: con PLAYERS ONE si torna a Classic);
- PLAYERS: uno, due, contro la CPU (a destra, al livello della difficoltà) o CHALLENGE (solo
  NEXT: con un altro gioco diventa VS CPU);
- DIFFICULTY;
- CONTROL: joystick o paddle;
- FREE PLAY;
- ATTRACT SOUND: suoni e musica dell'attract (gettone e Start si sentono sempre);
- SUPER MOVES: le mosse speciali in NEXT e CHALLENGE (spente all'accensione);
- BORDER: BLACK o GRAY (GRAY all'accensione). Il campo occupa tutto lo schermo: con GRAY il bordo
  è grigio scuro in partita (e nella demo), così si vedono le pareti, e segue la partita (sotto,
  *Bordo*). BLACK è il bordo di sempre.

In partita **RUN/STOP** mette in pausa e **Q** torna al menu. In due vince chi arriva a 11; in
singolo si gioca contro il muro con 3 palle. Dopo il GAME OVER si torna all'attract.

| | giocatore sinistro | giocatore destro |
|---|---|---|
| joystick | porta 2 | porta 1 |
| su / giù | racchetta (doppio tocco = rapido) | idem |
| verso l'avversario | scatto in avanti (EVO, NEXT), sparo del BLASTER: destra | idem: sinistra |
| dalla parte opposta | rientro dallo scatto: sinistra | idem: destra |
| fuoco | NEXT: usa il bonus selezionato; EVO: scatto in avanti | idem |
| SUPER MOVES | ↓ ↘ → + fuoco STRAIGHT SHOT, → ↓ ↘ + fuoco RISING STRIKE | ↓ ↙ ← + fuoco, ← ↓ ↙ + fuoco |
| paddle (coppia nella porta 1) | paddle X, pulsante = scatto; F / C sceglie / usa | paddle Y; . / - |

In NEXT con il joystick il bonus selezionato (in negativo, con la freccetta) cambia da solo ogni
secondo tra quelli in riserva: basta un pulsante, il fuoco, per usarlo al momento giusto.

Oltre ai bonus scelti, le capsule portano a volte il SUPER o il BULLET, gialli. Il BULLET è il
bullet time: attivato aspetta (la racchetta lampeggia come con un bonus armato) e scatta quando la
palla entra nella propria metà campo verso di sé; allora tutto rallenta tranne la propria racchetta,
finché la palla non è ribattuta o c'è un punto.

Con **SUPER MOVES: ON** ognuno ha accanto alle riserve la barra delle mosse speciali, che si
riempie colpendo (di più con lo scatto che intercetta la palla e quando si subisce un punto) e
diventa gialla quando una mossa è pronta: a metà la mossa normale, piena la MAX. Le mosse sono le
mezzelune dei picchiaduro, come sul MiSTer, con avanti verso l'avversario: STRAIGHT SHOT (tiro
dritto e più veloce) e RISING STRIKE (dritto, poi s'impenna lontano dall'avversario). Il fuoco
che chiude la mezzaluna usa la mossa se può partire, altrimenti il bonus selezionato; la
mezzaluna con la racchetta a casa la fa anche scattare in avanti. Con i paddle non ci sono gesti.
Anche la CPU usa le mosse. Non c'è la schermata HOW TO PLAY del PC e del MiSTer.

NEXT comincia con due schermate, come sulle altre versioni: ognuno sceglie 3 bonus su 6 e poi il
tipo di racchetta (su e giù, fuoco per prendere o lasciare; con i paddle si gira il paddle),
con accanto a ogni lista la racchetta sotto il cursore a grandezza reale (sprite 3 e 4, come in
partita: TWIST inclinata, BLASTER con il caricatore pieno). Dopo
10 secondi vale quello che c'è. Contro la CPU, la CPU sceglie da sola. In partita le riserve sono
in alto, tre posti per lato: il bonus selezionato è in negativo, con una freccetta sotto.

## CHALLENGE

`src/challenge.s` segue `rust/core/src/challenge.rs` e le schermate del PC e del MiSTer. Da soli
contro i 7 avversari della scala, ognuno con la sua racchetta, i suoi bonus e un livello della
CPU più alto; la velocità della palla parte dalla difficoltà del menu. Bonus e racchetta si
scelgono una volta, all'inizio. Ogni livello:
1. presentazione dell'avversario (racchetta, bonus, punti per vincere, punteggio e record);
2. partita NEXT a 5 punti, con i punti arcade in basso e il moltiplicatore sopra;
3. livello superato (con i premi per la vittoria e la partita perfetta) o continue: con un
   credito (o Free Play) si rigioca lo stesso livello con i punti da zero, altrimenti la scala
   finisce.

Punti come `Score::on_tick`: colpi, scatti riusciti e SUPER di chi gioca e punti segnati, con il
moltiplicatore che sale di uno ogni 4 colpi dello scambio (fino a ×8). Alla fine, se il miglior
punteggio entra nei primi 10, si scrivono le iniziali (su e giù, fuoco) e si vede la classifica.

La classifica si salva nella flash della cartuccia dopo le iniziali e si legge all'avvio (vedi
*Cartuccia EasyFlash*); con la flash cancellata c'è la classifica iniziale.

### Voci: nome dell'avversario, READY? e GO!

Come su PC e MiSTer il SID parla con il trucco del registro del volume (`$D418`): campioni a 4 bit
a 5000 Hz (`assets/sounds/voice/*.raw4`, da `tools/gen_voices.py`, copiati in `gen/voiceN.bin`,
`gen/ready.bin` e `gen/go.bin` da `tools/gen_c64_assets.py`). 0,5 s dopo l'inizio della
presentazione dice il nome dell'avversario (0,38-0,54 s); nel conto alla rovescia prima della
partita, contro la CPU e nella sfida con lo sfidante, "READY?" al primo frame e "GO!" al via, al
posto del bip (i bip dei secondi restano). Nel programma non c'è posto né per le voci né per il
player: stanno nei file voce (`src/voice.s`), uno per avversario e un banco della cartuccia
ciascuno, che prima della presentazione `ef_voice` copia a `$E000`: 16 pagine in circa 60.000
cicli (tre frame a schermo fermo), con la ROML del banco a `$8000` (modo a 8K, `$01 = $37`).

- **File:** ogni file ha il nome e il tema dell'avversario (1,3-1,7 KB). READY, GO (circa 1 KB
  l'una) e il player sono uguali per tutti: viaggiano solo nel file dell'avversario del primo
  livello (ARCADE: 4 KB), che una scala copia sempre per primo, e restano in memoria finché
  la scala continua:
  - `$EB20-$EFFF` (`VOICE_RES`): il player e READY, già al loro posto con la copia, sopra le
    immagini degli effetti e delle racchette di NEXT (`$E000-$E93F`). Gli altri file finiscono
    prima (al massimo a `$E695`);
  - `$FA01-$FEA7` (`VOICE_GO`): gli NMI del player e GO, dopo il tema; il file del primo livello ce
    li copia al terzo frame della presentazione (circa 14.000 cicli, quando lo schermo è già
    disegnato e non si può ancora uscire), poi mette il salto a `VOICE_COUNT`.

  Il file del primo livello riempie quasi tutto lo spazio da `$E000` a `$EFFF` (46 byte liberi):
  `voice.s` controlla che non sfori. Ogni banco ha anche la parte da `VOICE_RES` del file del
  primo livello (`tools/make_crt.py`), perché la copia prende sempre 16 pagine. Senza il file del
  primo livello gli altri non direbbero niente (`VOICE_COUNT` resta un RTS).
- **Chiamate** (`src/voice.inc`): `VOICE_TICK` a ogni frame della presentazione, `VOICE_STOP`
  quando finisce (partita o nuovo sfidante: la voce si ferma subito). `VOICE_COUNT` (`$FFC0`, tre
  byte sotto il KERNAL dopo i caratteri del BULLET) a ogni frame del conto alla rovescia con i
  frame rimasti: `start_game` ci mette un RTS, il file del primo livello il salto al suo conto, che
  dice READY al primo frame e GO 4 frame prima del via. `sid_song` ferma subito una voce ancora in
  corso (`VOICE_HUSH`): GO appena dopo il via, se si torna al menu, o READY se entra uno sfidante.
  Nel programma le voci costano poche decine di byte (la copia, le chiamate, i controlli nel
  player della musica, nelle immagini e nella copia delle racchette).
- **Player** (nel file, `say`): prende il SID e lo rende da solo, con gli NMI del timer A del CIA2,
  senza altre chiamate (il conto alla rovescia si può interrompere): volume a 8 (il silenzio dei
  campioni) e le tre voci con il bit di test e l'impulso, un'uscita ferma al massimo che sale con
  l'attacco. Il volume moltiplica tutta l'uscita del SID, e questo DC fa da segnale: sul 6581 si
  somma a quello del suo mixer, sull'8580 (che quasi non ne ha) è quello che rende udibile la
  voce. In VICE la voce è circa due volte più forte del jingle con il 6581, un po' più debole
  (circa -3 dB) con l'8580. Dopo 4 frame (un NMI a frame) un NMI ogni 197 cicli scrive un
  campione (49 o 53 cicli ciascuno, circa 5.100 per frame); finiti i campioni volume a 8 e gate
  chiusi, e dopo 6 frame di rilascio del DC voci spente, volume a 15 e il vettore dell'NMI del
  programma.
- **Musica:** mentre il vettore dell'NMI punta al player (byte alto con il bit 7 acceso, quello
  del programma no) `sid_tick` e `sid_fx` non scrivono nel SID: il jingle e il tema si fermano e
  riprendono dopo (le note già suonate restano mute fino alla nota dopo), il bip del via non suona,
  un gettone durante la voce non suona.
- **Frame:** durante una voce nessuno spegne l'I/O (`$01` resta `$35`): la copia delle immagini
  delle racchette sotto l'I/O aspetta che finisca (nel conto le racchette sono ferme, in partita
  si usano le immagini già preparate, anche quelle del caricatore del BLASTER). Anche le immagini degli
  effetti e delle racchette di NEXT aspettano la fine di READY, poi si preparano in circa 35
  frame, prima di GO. La presentazione è una schermata ferma: con gli NMI i suoi frame arrivano a
  circa 3.400 cicli; il conto alla rovescia con READY e GO resta sotto i 15.700, i primi frame
  della partita con GO sono leggeri (la palla è lontana dalle racchette).

### Tema dell'avversario

Come sul MiSTer (canzoni 7-13 di `tools/gen_sid_music.py`), nella partita contro la CPU suona in
ripetizione il tema dell'avversario del livello, uno per tipo di racchetta, sulle voci 1 e 2 (la 3
resta agli effetti). Nella sfida tra due giocatori, nelle altre modalità e nella demo solo gli
effetti.

- **Dove:** il tema viaggia nel file voce dell'avversario (`gen/themeK_0.bin` basso e
  `themeK_1.bin` melodia, al massimo 255 byte ciascuno: le tracce non hanno indirizzi assoluti).
  Al primo frame della presentazione il file le copia a `$F800` e `$F900` e mette la fine della
  terza traccia, vuota, a `$FA00` (circa 4.500 cicli in un frame leggero): da `hud_reset` in poi
  `$E000-$E93F` torna alle immagini degli effetti, mentre `$F800-$FF3F` in partita serve solo al
  tema e alle voci. Nella ROM del programma (`gen/sid_music.bin`) i temi non ci sono: la canzone
  `SID_SONG_THEME` (7) del player legge le tracce da lì.
- **Filtro:** come sul MiSTer il player (`src/sid.s`) suona i comandi del filtro del SID (taglio,
  scivolata del taglio, $D417 e $D418 degli strumenti: formato in `tools/gen_sid_music.py`) con le
  stesse scritture; li usano HAMMER, TITAN e il titolo. Il file voce spegne il filtro ($D417 = 0)
  quando prende il SID, e intanto `sid_tick` rimette a 0 la sua copia di $D417: la prima nota nel
  filtro dopo la voce lo riscrive tutto.
- **Quando:** a fine presentazione `VOICE_STOP` restituisce la canzone del tema (senza file resta
  0, il silenzio) in `match_song`, che la partita dopo consuma: la sfida con un nuovo sfidante
  resta senza musica.
- **Budget:** se quando tocca alla musica il frame è già oltre circa 15.500 cicli (`SID_LATE` in
  `src/play.s`), il tick del player aspetta il frame dopo, come gli effetti rimandati: le
  scritture nel SID sono le stesse, un frame più tardi.
- **Tempo dinamico**, come il SID Rust (`rust/sid/src/engine.rs`), solo per la canzone (canali
  0-2); gli effetti restano a 50 Hz e alla loro altezza. In partita `match_tempo` (`src/play.s`)
  dà a `sid_tempo` (`src/sid.s`) i due stati a ogni frame:
  - **match point** (in due, uno dei giocatori a un punto dalla vittoria, fino alla fine della
    partita): 62,5 passi al secondo, cioè 5 ogni 4 frame, con le note alla stessa altezza. Ogni 4
    frame `sid_tick` mette da parte un passo della canzone in più (`sid_extra`), che `sid_more`
    fa subito dopo, se il frame ha ancora tempo, o in un frame dopo: le scritture sono le stesse,
    nella stessa sequenza;
  - **bullet time** (il BULLET scattato): un passo della canzone su due e le frequenze dimezzate,
    un'ottava sotto (prima il byte alto, poi il basso, come gli effetti rallentati del MiSTer); al
    cambio, in entrata e in uscita, al passo dopo si riscrivono subito le frequenze delle note in
    corso.

  Le due regole si sommano. `paddws-c64 sid` confronta passo per passo le scritture del 6502 con
  quelle del player Rust (`paddws-sid`, verificato contro il Verilog) in 6 canzoni, temi compresi:
  match point, bullet time che entra ed esce (anche per un frame solo), e tutte e due insieme, e
  controlla che al match point i passi siano 5 ogni 4 frame.
- **Byte:** nel programma il tema costa 15 byte (la canzone 7 nel player, `match_song`); il tick
  rimandato altri 11, ripagati da una frequenza della nota letta con `set_freq`.
- **Niente opzione** per spegnerlo, al contrario del MiSTer (Match music: Off): nel programma non
  c'è posto.

### YOU WIN!

Come sul PC, "YOU WIN!" con il GAME OVER di ogni partita vinta contro la CPU (Classic, EVO, NEXT e
livelli di CHALLENGE; all'ultimo livello la dice il finale) e all'inizio del finale. I campioni
(`assets/sounds/voice/you_win.raw4`, 2.548 byte, in `gen/you_win.bin`) stanno nel banco della
vittoria della cartuccia (13, `tools/make_crt.py`) con il player delle voci: 16 pagine da copiare a
`WIN_RUN` (`$EB00-$FAFF`, `src/voice.inc`), cioè il player e READY come li lascia il file del primo
livello da `VOICE_RES`, i campioni a `WIN_SAMPLES` (`$F000`, con il descrittore per `VOICE_SAY` a
`$F9FC`) e la pagina degli NMI del player a `$FA00`, uguale a quella che il file del primo livello
copia a `VOICE_GO` (`VOICE_GO_SRC`). In CHALLENGE player e NMI sono già lì e restano uguali; nelle
altre partite arrivano con la copia.

- **GAME OVER** (`enter_over`, `over_scene` in `src/play.s`): contro la CPU, se vince chi gioca,
  due pagine per frame (circa 7.700 cicli), poi `VOICE_SAY`: la voce parte circa 0,2 s dopo la
  scritta; il jingle del GAME OVER aspetta, come con READY. I campioni prendono il posto delle
  tabelle dei quadrati e del tema: alla fine del GAME OVER `math_invalidate` (le rifà `math_step`
  nella schermata dopo o nell'attract), e il tema torna con il file voce della presentazione dopo.
- **Byte:** nel programma circa 60 (le chiamate, `win_pg`).

### Finale

`src/ending.s` segue `rust/game/src/ending_ui.rs`: quando si batte l'ultimo avversario, al posto
della schermata CHAMPION e prima delle iniziali (`enter_clear` passa a `end_enter`). Sei parti con
i tempi del PC (circa 57 s in tutto); Start (il fuoco di chi gioca, RETURN, SPAZIO o 1) lo salta
dopo mezzo secondo e va dritto alle iniziali:

1. **CONGRATULATIONS!** a scala 2 che lampeggia giallo e bianco, dopo un secondo **YOU WIN!** con
   la voce;
2. **sfilata**: YOUR OPPONENTS, poi un avversario al secondo, con la sua racchetta vera (sprite
   0-6 come le anteprime della scelta, `pad_image`: TWIST inclinata, BLASTER con il caricatore
   pieno, segni gialli) e il nome sotto (su due righe alterne: in 40 pixel un nome di 8 lettere non
   sta), e mezzo secondo dopo il **timbro rosso DEFEATED**, inclinato, in 5x3 caratteri sopra la
   racchetta (gli sprite stanno dietro le scritte);
3. **punteggio**: FINAL SCORE, SCORE che sale in 3 s fino ai punti prima del premio, CHAMPION
   BONUS (vittoria e partita perfetta dell'ultimo livello, già sommati) in 1 s, poi TOTAL a scala 2;
4. **YOU ARE THE PADD WS CHAMPION** con i **fuochi d'artificio**: razzi negli sprite 0-2 (testa
   bianca e scia gialla) che salgono rallentando in 0,9 s, poi lo scoppio; sei tipi a turno come
   `fireworks.py` e il PC: anello, salice e palma con la scia, crisantemo (bianco dentro, rosso
   fuori), crepitio che sfarfalla bianco e giallo e si ferma, croce che si divide in quattro rami;
5. **titoli di coda** a sezioni (titoli gialli, voci bianche, PADD WS e THANK YOU FOR PLAYING a
   scala 2), dal basso finché l'ultima riga arriva al centro, poi fermi 2 s;
6. **THE END** che lampeggia.

- **Colori:** solo bianco, giallo e rosso sul nero; le scintille non si scuriscono, si diradano
  (come `alive` di `ending_ui.rs`: la fase `(i * 7 + t * 3) mod 10` sotto una soglia che scende con
  la vita). Il bordo resta nero, come in tutte le schermate fuori dalla partita: BORDER GRAY è per
  la partita e la demo, e un bordo grigio stonerebbe con i tre colori del finale. `$D025` (il grigio
  dei segni delle racchette) è giallo nella sfilata e per i razzi, poi torna grigio.
- **Musica:** la canzone ENDING della ROM del SID (`tools/gen_sid_music.py`, la 14 del MiSTer), che
  il generatore scrive anche in `gen/ending.bin` (le tre tracce di fila, 1.595 byte, con gli offset
  in `gen/sid_music.inc`); nel player è `SID_SONG_ENDING`, dopo il tema (`src/sid.s`). Le tracce
  non hanno indirizzi assoluti e il player le legge con un puntatore a 16 bit, quindi possono
  superare i 255 byte. La voce la ferma per un secondo, poi riprende. Niente effetti: la terza voce
  della canzone è la batteria. `paddws-c64 sid` confronta la canzone con il player Rust.
- **Caratteri:** un set del finale (`gen/ending_chars.bin`, `tools/gen_c64_assets.py`) al posto di
  quello del programma, che alla fine torna dalla cartuccia: il font monospazio resta ai suoi codici
  (le routine del programma scrivono come sempre), più le lettere a scala 2 (il font a pixel
  doppi, 2x2 caratteri), il timbro e i 48 punti dei fuochi.
- **Fuochi:** un passo ogni 3 frame (16,7 al secondo, il PC fa 15), diviso nei tre frame: lo
  schermo nascosto vuoto e un fuoco, due fuochi, l'ultimo e lo scambio degli schermi (`$C000` e
  `$C400`). Al più 4 fuochi accesi, 24 scintille ciascuno; ogni scintilla ha la posizione in 8.8
  su una griglia di 4 pixel (80x36 nel cielo) e la velocità con segno a 8 bit, con la gravità e
  l'attrito (`v -= v >> 4` a passi alterni). Il punto è un carattere **multicolore**: 2x2 pixel nel
  centro di ognuno dei quattro quadranti, con il colore nei bit (`%01` bianco in `$D022`, `%10`
  giallo in `$D023`, `%11` il rosso del colore del carattere, uguale per tutto il cielo), così il
  doppio buffer non tocca la RAM dei colori. Codice `$C0 + colore * 16 + quadranti`: un punto si
  aggiunge alla cella con un AND e un OR. Lo spettacolo (tipo, posto, partenza e spinta del razzo)
  e le velocità delle scintille vengono da `tools/gen_c64_assets.py`.
- **Titoli:** testo in righe virtuali (`gen/ending.inc`), scorrimento fine con `$D011` (24 righe) a
  0,56 pixel per frame. Lo schermo nascosto si prepara 5 righe per frame; a ogni riga intera si
  scambiano gli schermi e si scrivono i colori delle righe con il testo, nel vblank: arrivano prima
  che il raster raggiunga la prima riga di caratteri (il banco di prova controlla il ciclo di ogni
  scrittura).
- **Frame:** fra una parte e l'altra due frame a schermo spento (nel primo si pulisce lo schermo,
  circa 11.500 cicli, nel secondo la parte nuova lo disegna). Il frame più pesante è nei fuochi,
  circa 16.800 cicli con la musica.
- **Dove sta:** nel programma solo `end_enter` (la prima pagina dalla cartuccia), la scena e la
  canzone nel player. Il resto è nella cartuccia, banchi 14-15 (`paddws.prg.end`, un'uscita in più
  di ld65, aree `END*` di `paddws.cfg`), e gira nella bitmap dell'attract, che dopo si rifà sempre
  da capo:

  | area | dove | quando |
  |---|---|---|
  | `ENDA` | `$E000-$EAFF` | la pagina 0 (avvio, scena, copia) da `end_enter`, il resto nei primi frame: le parti, i dati dei titoli |
  | `ENDB`, `ENDC` | `$EC00-$EFFF`, `$FB00-$FEFF` | primi frame: la canzone, il punteggio |
  | `ENDCH` | `$C800-$CFFF` | primi frame: il set di caratteri del finale |
  | campioni di YOU WIN | `$F000-$F9FF` | primi frame, dal banco della vittoria |
  | `ENDD`, `ENDE` | `$EB00-$EBFF`, `$F000-$FAFF` | dopo la voce (il player è a `$EB20`, i suoi NMI a `$FA01`): razzo, fuochi, codice dei titoli |

  Le copie sono di 3 pagine per frame (circa 11.500 cicli), a schermo spento all'inizio e nei frame
  leggeri di CONGRATULATIONS dopo la voce (mai con gli NMI della voce: la copia accende le ROM). Le
  scintille (672 byte) usano la RAM del codice della sfilata e del punteggio, che a quel punto non
  serve più. Alla fine il set di caratteri del programma torna dalla cartuccia (3 frame), poi
  `math_invalidate` (qui c'erano campioni e fuochi) e la musica delle iniziali.
- **Byte:** nel programma il finale costa meno della schermata CHAMPION di cui ha preso il posto
  (circa 30 byte liberati: `end_enter`, la scena e la canzone contro le scritte e i salti di
  CHAMPION); con YOU WIN nel GAME OVER il programma cresce di 32 byte e di una variabile.

Il banco di prova (`paddws-c64 frames`, o `ending` da solo) gioca il finale da capo con `frame`, NMI
della voce compresi: ogni frame nel budget, le scritte delle parti ai loro tempi (lettere a scala 2,
numeri del punteggio, racchette, timbri, nomi), YOU WIN una volta in `$D418`, scintille di tutti e
sei i tipi, i colori dei titoli prima del raster, nessun colore fuori da bianco, giallo e rosso, e
all'uscita le iniziali con tutto com'era (set di caratteri, `$D016`, `$D025`, `$D01B`, sprite, NMI,
canzone, tabelle dei quadrati da rifare). `ui` lo salta in quattro punti (anche durante la voce; prima di mezzo secondo no) e
controlla YOU WIN nel GAME OVER. Per le schermate in VICE: `.\c64\build.ps1 -Name autoend -Define
ENDTEST` parte dall'ultimo livello appena vinto, con il player delle voci in memoria.

### Cartuccia EasyFlash

`paddws.crt` (`tools/make_crt.py`, tipo hardware 32) ha banchi da 16 KB (`src/ef.inc`):

| banchi | contenuto |
|---|---|
| 0 (ROMH) | avvio (`src/crt.s`): a `$E000` nel modo Ultimax dell'accensione, con i vettori |
| 1-4 | il programma (`paddws.prg`), da `$0800` a `$CFFF`, poi l'immagine delle routine di `src/ef.s`, le routine dell'avvio, da `$D800` (banco 4, ROML da `$9000`) il codice delle mosse speciali e da `$DC00` (ROML da `$9400`) quello della classifica |
| 5-11 (ROML) | le 7 voci, i file di `src/voice.s` senza l'indirizzo di caricamento; da `VOICE_RES` in ognuno la parte che resta del file del primo livello (player e READY) |
| 12 (ROML) | `gen/pick_bank.bin`: il set di caratteri della scelta dei bonus e la pagina `$FF00` (caratteri della capsula del BULLET, l'RTS di `VOICE_COUNT`) |
| 13 (ROML) | banco della vittoria: YOU WIN! con il player delle voci, 16 pagine per `$EB00-$FAFF` (vedi *YOU WIN!*) |
| 14-15 (ROML) | il finale di CHALLENGE (`paddws.prg.end`, vedi *Finale*) |
| 16 (ROML) | la classifica, scritta dal programma (settore 2 della flash ROML, banchi 16-23, solo per lei); nella ROMH i vettori, che puntano a un RTI |

All'accensione l'avvio copia nei 256 byte di RAM dell'EasyFlash (`$DF00`) il caricatore, e la sua
fine a `$0110`. Il caricatore passa al modo a 16K, fa la parte del reset del KERNAL che serve (CIA,
pagine 0, 2 e 3, vettori, VIC e schermo, senza la prova della RAM) e copia il programma pagina per
pagina; la fine mette al suo posto, a `$DF00`, le routine di `src/ef.s` (256 byte, che nel `.prg`
stanno a `$D000`, dopo l'area del VIC), spegne la cartuccia (`$DE02 = $04`) e salta allo stub
BASIC. Le routine di `src/ef.s` leggono e scrivono la flash, quindi devono stare fuori dalla RAM
che la cartuccia copre; nel programma non costano byte:
- `ef_voice`: la voce di un tipo (o i posti della classifica) a `$E000`, 16 pagine;
- `ef_pick`: i caratteri della scelta dei bonus, o di nuovo quelli originali (dal programma
  nella flash);
- `ef_hi_write`, `ef_hi_erase`: la classifica (sotto).

Le copie accendono la ROML del banco (modo a 8K, `$01 = $37`), con gli interrupt spenti. VICE
avvisa che manca l'EAPI: il programma non lo usa (sotto).

**Classifica nella flash** (`hi_load`, `hi_save` in `src/challenge.s`, `src/ef.s`): ogni
salvataggio scrive un posto da 128 byte nei primi 4 KB del banco 16 (la classifica, 80 byte, due
byte di riconoscimento `HP` e un controllo: l'EOR di tutto il posto vale `$A5`), nel primo posto
libero dopo quelli già scritti. All'avvio `hi_load` (nel segmento INIT) copia i 32 posti a `$E000`
e prende l'ultimo completo: un posto scritto a metà, per uno spegnimento durante il salvataggio,
non conta e resta quello di prima. Finiti i 32 posti, o se il posto da scrivere non è cancellato
(una EasyFlash vera può avere nella flash i dati di prima), si cancella il settore (circa 1 s) e
si ricomincia dal primo: un salvataggio perso solo se si spegne proprio allora. Se dopo la
cancellazione non si scrive nemmeno il primo posto, la cartuccia non si lascia scrivere e il
programma non ci prova più fino allo spegnimento.

La flash si scrive solo nel modo Ultimax, l'unico in cui il C64 manda alla cartuccia anche le
scritture: della RAM del C64 restano solo `$0000-$0FFF` e l'I/O, perciò la classifica sta a
`$0200` (pagina che il KERNAL, spento, non usa più). I comandi sono quelli dell'Am29F040 della
EasyFlash, senza l'EAPI: sblocco (`$AA` a `$x555`, `$55` a `$x2AA`), poi `$A0` e il byte, oppure
`$80`, di nuovo lo sblocco e `$30` per il settore; finché lavora la flash dà lo stato, poi il dato
(si aspetta al massimo circa 2 s per byte e 10 s per il settore). Interrupt spenti e musica muta
durante la scrittura: circa 1 ms per un posto, 1 s in più con la cancellazione. Un NMI (RESTORE)
trova i vettori della ROMH del banco 16, che puntano a un RTI. In VICE la scrittura è emulata e
resta nel `.crt` con `-easyflashcrtwrite`; il C64 Ultimate supporta la scrittura della flash. Una
EasyFlash 3 o una cartuccia con un'altra flash vorrebbero l'EAPI, che sceglie i comandi giusti
per la flash montata.

**Nuovo sfidante** (come `rust/core/src/challenge.rs`): durante la presentazione, la partita
contro la CPU (anche nel conto alla rovescia) e il livello superato (tranne l'ultimo), il fuoco
del lato libero (porta 2 a sinistra, porta 1 a destra; con le paddle il pulsante del lato libero)
fa entrare un secondo giocatore, con un credito (tasto 5) o in Free Play. In alto sul lato libero
lampeggia "P2 PRESS START" (o "P2 INSERT COIN"). Dopo "HERE COMES A NEW CHALLENGER!" lo sfidante
sceglie bonus e racchetta, il campione tiene i suoi, e si gioca una sfida a 5 punti senza punti
arcade. Il vincitore riprende il livello da 0-0 dal suo lato (la CPU può stare a sinistra,
`cpu_side`) con un premio pari a quello del livello: il campione lo somma ai suoi punti, lo
sfidante parte da lì. Il perdente scrive le iniziali con il suo joystick se entra in classifica.
Nella scena dello sfidante il campione salta le schermate solo con il suo fuoco o con RETURN,
SPAZIO e 1.

## Attract

`src/attract.s` usa due modi video:
- l'auto-test è a caratteri, verde fosforo, con il reticolo finale;
- strisce, logo e titolo sono una bitmap hires gialla e nera a `$E000`.

`tools/gen_c64_assets.py` riporta `assets/attract/attract.json` a 320×200 e 50 Hz. Prepara il
titolo completo (`gen/title.bin`, 1.928 byte), le scritte che cambiano già nelle loro celle
(`gen/labels.bin`, `gen/credits.bin`) e la tabella dello scorrimento delle strisce. Il titolo sta
nella cartuccia (banco 12, `gen/pick_bank.bin`): all'avvio `src/unpack.s` lo copia a `$E000` e da
lì nella RAM sotto l'I/O a `$D800`, e il banco di prova controlla che il risultato sia identico a
`title.bin`.

Durante l'attract:
- le strisce si ridisegnano frame per frame, ma solo quelle che si muovono;
- il logo si copia dal titolo a `$D800` riga per riga (con l'I/O spento per la riga), sotto un
  raster bianco fatto con quattro sprite;
- la pallina del titolo (uno sprite nero) rimbalza sui pixel neri della bitmap, un asse alla
  volta come in `attract.rs`;
- il bordo è giallo come lo sfondo, anche nei frame a schermo spento in cui si pulisce la bitmap
  prima delle strisce (bianco nel lampo del logo).

**Classifica con le barre nel bordo** (`src/challenge.s`, `hs_bars`). Nella classifica di
CHALLENGE (dopo il titolo, e alla fine di una scala) il processore non ha altro da fare: dopo la
musica il frame aspetta il raster e scrive in `$D020` una sfumatura, due barre ogni 64 righe (rossa
e gialla, blu e azzurra), un colore ogni due righe dalla riga 28 alla 240, che scende di due righe
ogni due frame; poi il bordo torna nero, prima dell'interrupt della riga 250. Una scrittura in
`$D020` si vede se cade mentre il bordo è a schermo (cambio a metà riga, e il "grey dot" dei VIC-II
nuovi), quindi:
- nel bordo in alto (righe 28-50, senza badline: 63 cicli per riga) il raster si stabilizza al
  ciclo nelle righe 20-26: l'attesa di `$D012` lascia 7 cicli d'incertezza, e in ognuna delle sei
  righe dopo una lettura al confine della riga dà un ciclo in più a chi è in anticipo. Poi il
  colore cambia al ciclo 7 di ogni riga pari, nel ritorno orizzontale, con il tempo contato;
- accanto allo schermo (righe 52-240) si scrive a metà riga, dove c'è lo schermo e il bordo non si
  disegna, così l'incertezza dell'attesa non conta; solo nelle righe pari, che non sono mai badline
  (nelle badline il VIC ferma il processore per 40 cicli in mezzo alla riga).

Il codice della classifica e delle barre sta nella cartuccia (segmento `HSCODE`, sotto). Il frame
della classifica arriva a circa 17.700 cicli nel banco di prova, quasi tutti di attesa; mentre
`math_step` rifà le tabelle dei quadrati (i primi frame dopo il titolo) le barre non ci sono. In
VICE ogni riga del bordo ha un colore solo; `paddws-c64 frames` controlla i colori scritti, il
budget, lo scorrimento e il bordo nero alla fine e all'uscita.

## Memoria

| indirizzi | contenuto |
|---|---|
| `$0002-$00FF` | pagina zero, tutta usata: le variabili più usate (palla, racchette, punteggio, eventi, immagini delle racchette, scelte) |
| `$0200-$0253` | classifica di CHALLENGE e posto della flash: si vedono anche nel modo Ultimax della cartuccia (il KERNAL, che usava la pagina, resta spento) |
| `$0254-$0283` | stato delle mosse speciali (barre, mosse armate, tiro, soglia, gesti, barre a schermo) |
| `$0284-$0313` | routine sempre in memoria (segmento `LOWCODE`, quasi pieno), copiate all'avvio da `title_unpack`; da `$0314` i vettori del KERNAL, che restano liberi |
| `$0334-$03FF` | stato delle CPU (il buffer della cassetta: il KERNAL non lo tocca) |
| `$0400-$07FF` | tabelle degli shift del generatore, stato di NEXT e delle scelte |
| `$0801-$BC9F` | programma (stub BASIC, codice, dati), con poche decine di byte liberi alla fine |
| `$BCA0-$BFFF` | variabili (2 byte liberi); nel `.prg` al loro posto quello che serve solo all'avvio (segmento INIT, circa 510 byte ancora liberi): `title_unpack` e `hi_load` con la classifica iniziale, poi l'immagine di `LOWCODE` |
| `$C000-$C3FF` | schermo (nel `.prg` ci sono gli sprite, copiati sotto l'I/O all'avvio) |
| `$C400-$C7FF` | secondo schermo (colori della bitmap); in NEXT il codice delle mosse speciali (segmento `SMCODE`, 1.013 byte), copiato dalla cartuccia nella scelta |
| `$C800-$CFFF` | set di caratteri (`gen/charset.bin`, da `tools/gen_c64_assets.py`), caricato già lì; tutti i 256 caratteri sono usati (in NEXT 8 sono la capsula del BULLET, nella scelta dei bonus 86 sono le metà delle lettere); nel finale di CHALLENGE il suo set (`gen/ending_chars.bin`), poi di nuovo questo dalla cartuccia |
| `$D000-$D7FF` | sprite (RAM sotto l'I/O) |
| `$D800-$DF87` | titolo dell'attract, copiato dalla cartuccia (RAM sotto l'I/O) |
| `$D000-$D0FF` | nel `.prg`: l'immagine delle routine di `src/ef.s`, che la cartuccia copia a `$DF00`; da `$D100` le routine dell'avvio, da `$D800` il codice delle mosse speciali e da `$DC00` quello della classifica (solo nella flash) |
| `$DF00-$DFFF` | RAM dell'EasyFlash (I/O): prima il caricatore, poi le routine di `src/ef.s` |
| `$E000-$FF3F` | bitmap (attract); in partita immagini degli effetti e delle racchette di NEXT (`$E000-$E93F`); nella presentazione di CHALLENGE il file voce a `$E000`; nel finale di CHALLENGE il suo codice, la canzone e i fuochi (`$E000-$FEFF`, vedi *Finale*) |
| `$EB00-$FAFF` | nel GAME OVER vinto contro la CPU: il player delle voci e YOU WIN (i campioni a `$F000`, sulle tabelle dei quadrati) |
| `$E000-$E2D0` | dentro la bitmap: nella classifica di CHALLENGE il suo codice e le barre del bordo (segmento `HSCODE`, 721 byte), copiati dalla cartuccia nel primo frame di disegno (`hs_load`); da `$E400` i colori delle barre (320 byte, `hs_init`) |
| `$E940-$EA3F` | dentro la bitmap: in NEXT con le mosse speciali le 4 icone della mossa armata, preparate nei primi frame della partita |
| `$EB20-$EFFF` | dentro la bitmap: in CHALLENGE player e READY, dal file voce del primo livello, per tutta la scala |
| `$F800-$FA00` | dentro la bitmap: in CHALLENGE il tema dell'avversario, copiato dal file voce (una traccia per pagina) |
| `$FA01-$FEA7` | dentro la bitmap: in CHALLENGE gli NMI del player e GO, copiati dal file voce del primo livello |
| `$F000-$F7FF` | tabelle dei quadrati, dentro la bitmap: si rifanno dopo strisce, logo e titolo |
| `$F800-$FB7C` | solo all'avvio: le routine che servono lì (segmento BOOTCODE: `clear_vars`, `math_init`, `irq_init`, `video_init`, `input_init`, `sid_init` e l'auto-test dell'accensione, fino alle strisce), copiate dalla cartuccia da `title_unpack` (nel `.prg` da `$D100`, dopo l'immagine della RAM della cartuccia) |
| `$FF40-$FFBF` | caratteri della capsula del BULLET e quelli che sostituisce (sotto il KERNAL, tra la bitmap e i vettori: copiati all'avvio dalla cartuccia) |
| `$FFC0-$FFC2` | `VOICE_COUNT`: RTS o il salto al conto alla rovescia del file voce |
| `$FFC3-$FFEA` | i caratteri di PRESS START che la barra delle mosse speciali prende in NEXT (`bullet_chars` li rimette) |

Il VIC è nel banco 3. BASIC e KERNAL sono sempre spenti (`$01 = $35`): dati e variabili stanno
anche sotto le loro ROM; le copie dalla cartuccia le accendono per un momento,
con gli interrupt spenti, ma girano nella RAM della cartuccia e scrivono nella RAM sotto. Il banco di prova emula la RAM sotto l'I/O, separata dai
registri come sul C64.

## Grafica

- **Sprite:**
  - palla: sprite 0, 4×4 o 6×6 pixel;
  - area boost EVO: sprite 1 e 2, grigi, non espansi e sopra le racchette, così la banda cade
    sulla riga esatta (`sprites.bin` ha una banda per ogni altezza da 1 a 10 righe);
  - racchette: sprite 3 e 4, multicolore ed espanse in verticale (pixel di 2x2): corpo bianco
    (grigio a tratti con un bonus armato o con il proprio BULLET armato e non ancora scattato),
    segni dei tipi di NEXT in giallo (`$D026`) e grigio
    (`$D025`), come `kind_px` del MiSTer: estremità di TITAN, bande di HAMMER, inclinazione di
    TWIST, canne e caricatore del BLASTER (come su PC, un tratto giallo di n / 4 righe per
    colpo e niente ricarica a schermo). Il RUSH non ha segni: le immagini gialle dello scatto
    del PC (tra casa e la posizione avanzata, 90 pixel) non stanno nello sprite di 24 pixel e
    non ci sono sprite liberi. Il corpo è al centro
    dell'immagine, con i segni dietro e davanti; per la racchetta destra l'immagine si specchia.
    Si rifà solo quando cambiano altezza, tipo o variante, al massimo una al frame;
  - NEXT: capsule in volo negli sprite 5-7 (12×12 come sul MiSTer, il SUPER giallo e a tratti in
    negativo, il BULLET giallo) e icone grigie dei bonus armati negli sprite 1-2 (con STEER il
    volante giallo; il BULLET non ha icona; con una mossa speciale armata la sua icona gialla);
    la quarta capsula prende lo sprite 1 o 2 se è libero. Con la capsula del BULLET le immagini sono 32, quante ne stanno a `$D000`.
- **NEXT in caratteri** (gli sprite sono finiti): riserve in alto, muro tratteggiato del
  GUARDIAN e colpi del BLASTER, a passi di 2 pixel sulla riga di caratteri più vicina. Il muro
  ha 5 settori, uno per partita e senza ricarica: la palla mancata rimbalza solo se il settore
  in cui sta il suo centro è in piedi, e il settore cade (`next_barrier`, `g_sector`: i confini
  sono pixel interi, basta la parte intera della y). A schermo, sotto le riserve, i settori in
  piedi hanno colori alterni (giallo e arancione); quello colpito lampeggia 0,3 s e sparisce.
  I settori non sono allineati ai caratteri: ogni riga prende il settore del suo centro, con la
  stessa regola della logica (il disegno è approssimato al carattere, la logica no) e si
  riscrivono solo le righe dei settori cambiati. I colpi si disegnano nel vblank
  rimettendo prima quello che c'era sotto. In basso la scritta del bonus attivato ("P1 SMASH!",
  "P1 BULLET!"), in cima e in fondo i segni gialli di STEER dove finisce la guida.
- **Capsula del BULLET nelle riserve:** il set di caratteri è pieno, e servono 8 caratteri
  (normale e in negativo, 2×2). In NEXT prendono il posto di caratteri che lì non servono: cursore
  e reticolo dell'auto-test (solo all'accensione), il muro del singolo e uno di INSERT COIN, che
  c'è solo nella demo (EVO). `bullet_chars` li scambia quando si disegna il campo: in NEXT la
  capsula, nelle altre partite i caratteri originali. Il generatore sceglie i caratteri e controlla
  che non servano altrove; i 128 byte stanno nella RAM libera sotto il KERNAL (`$FF40`), dove li
  copia l'avvio dalla cartuccia.
- **Scelta dei bonus:** la capsula (2×2 caratteri) ha il centro tra due righe, il testo no. Nome
  e cursore accanto si abbassano di 4 pixel con le metà delle lettere: nella riga della capsula la
  metà alta (abbassata), in quella sotto la metà bassa. Sono 86 caratteri che `ef_pick` copia
  dalla cartuccia (banco 12) al posto delle scritte grandi (codici 64-159: 3 pagine, circa 11.000
  cicli, in un frame da solo con lo schermo vuoto) e rimette com'erano nella scelta della racchetta
  o uscendo con RUN/STOP. `tools/gen_c64_assets.py` controlla che nella scelta quei caratteri non
  servano ad altro; `print_low` scrive le due metà con gli indirizzi calcolati una volta per riga,
  così una colonna intera sta ancora in un frame.
- **GHOST:** dopo il tiro la palla si vede solo a lampi (`Next::ball_hidden`: 5 tick ogni 20),
  sempre senza effetti né coda, che seguirebbero la palla anche quando non si vede; le posizioni
  per la coda si tengono lo stesso, così quando il GHOST finisce la coda riparte giusta.
- **Bullet time**, solo con il BULLET scattato (da armato c'è solo la racchetta a tratti), con la
  palette di sempre come su PC e MiSTer, nessun colore nuovo e niente sfocato: diventa grigio
  quello che è bianco (mezzeria, punteggi, racchetta avversaria, capsule bianche), tranne
  la racchetta di chi l'ha attivato. La palla ha la coda grigia lunga il doppio: le posizioni
  passate avanzano un frame sì e uno no. Mezzeria e punteggi si ricolorano solo all'inizio e alla
  fine (circa 1.500 cicli, con il frame già avanti al prossimo).
- **Effetti della palla di NEXT** nello sprite della palla: coda grigia (boost, curva, STEER,
  SUPER, SLOW, BULLET), cometa gialla del SUPER, alone di SLOW a tratti.
  - La coda è fatta dalle posizioni vere della palla negli ultimi 5 frame (0,1 s, come su PC e
    MiSTer), più quelle a metà tra due frame quando la palla va così veloce che non si toccano,
    sempre più rade con l'età. Segue quindi la traiettoria, anche la piega di un rimbalzo.
  - Si prepara a fine frame, quando il resto è fatto, con le posizioni di questo tick; il
    puntatore dello sprite cambia nel vblank.
  - Cache di 4 sprite, ciascuno con la sua "firma": posizioni nello sprite, angolo e lato della
    palla. A velocità costante la forma vista dalla palla si ripete, cambia solo l'arrotondamento
    ai pixel. Se uno sprite ha una firma che differisce al più di 1 pixel per valore, basta
    puntarlo (prima quello che si vede, confronto srotolato). Altrimenti si disegna nello sprite
    usato meno di recente, mai in quello in vista, e solo se il frame resta comunque sotto circa
    16.500 cicli (il disegno ne costa al massimo circa 4.000); se no resta l'immagine di prima,
    agganciata alla palla.
  - La firma si ricava da quella del frame prima: le posizioni scalano di un posto e si spostano
    del movimento della palla, con una somma a 8 bit (il calcolo completo solo quando cambiano
    angolo o lato della palla).
  - Nel banco di prova si disegna solo nel 12% dei frame con la coda (dopo rimbalzi, colpi e
    curve): in media circa 310 cicli per frame di gioco in più, e il frame più pesante resta
    quello di prima della coda (circa 17.200 cicli).
  - Quadrati già ritagliati, righe del retino e maschere vengono da tabelle
    (`tools/gen_c64_assets.py`).
  - La cometa del SUPER usa le stesse posizioni e la stessa cache: sprite hires espanso (il
    doppio di strada), testa piena attorno alla palla e quadrati gialli che si rimpiccioliscono
    con l'età, quindi anche lei segue la traiettoria. Non ci sono più code precalcolate.
  - Le immagini delle racchette (TWIST per ogni inclinazione, BLASTER per ogni numero di colpi
    nel caricatore, così cala nel frame del colpo; gli altri tipi una) e gli
    aloni si preparano a inizio partita, un pezzo per frame, nella bitmap dell'attract (`$E000`),
    che in partita non serve.
- **Racchette di NEXT in movimento:** con il SUPER armato (animazione della rotazione) la
  racchetta gira: otto angoli su mezzo giro, preparati a inizio partita all'altezza del tipo,
  sprite hires espanso. Nel salto del TELEPORT la racchetta affonda in un portale giallo ed esce
  dall'altro sul punto d'arrivo, seguendo la palla come sul MiSTer: il pezzo che affonda è nello
  sprite della racchetta, quello che esce nello sprite dell'icona del bonus. Il salto si disegna
  dopo la scena, se il frame resta sotto circa 16.000 cicli; il banco di prova (`frames`)
  controlla che i pezzi e i portali si vedano.
- **Lavori rimandabili:** prima di rifare un'immagine di racchetta, un posto delle riserve, la
  scritta del bonus, i punti di CHALLENGE o di avviare un effetto sonoro il programma guarda la
  riga del raster (`$D012`); se il frame è già avanti aspetta il prossimo.
- **Caratteri:**
  - mezzeria, muro del singolo, punteggi (cifre di `pong-score.ttf` in celle di 3×3 caratteri);
  - testi nel font Munro;
  - GAME OVER e il vincitore a scala 2.
- **Bordo** (`border_game` in `src/play.s`, `apply_shadows`): bordo (`$D020`) e sfondo (`$D021`)
  hanno due registri ombra. Il bordo è quello dello sfondo quando lo sfondo non è nero (lampo bianco
  del punto, giallo dell'attract), altrimenti `sh_brd`, che fuori dalla partita è 0 (nero). In
  partita e nella demo, con BORDER GRAY, `border_game` lo sceglie a ogni frame (solo se il frame
  ha tempo, dopo la musica), in quest'ordine:
  - giallo con il SUPER (`nx_super`) o una mossa speciale MAX (`sm_fl` di livello 2) in volo;
  - grigio pulsante nel bullet time: scuro, medio, chiaro, medio, 8 frame ciascuno;
  - rosso al match point, 32 frame ogni 64: lo stato è quello del tempo della musica
    (`match_tempo`, che la fa accelerare);
  - grigio scuro (anche nel conto alla rovescia, nella demo e nel GAME OVER).

  I registri si scrivono solo quando il colore cambia, nel vblank: ogni scrittura con il colore a
  schermo lascia un "grey dot" sui VIC-II nuovi. `paddws-c64 frames` prova `border_game` caso per
  caso e conta i colori nelle partite.
- **Posizioni:** si calcolano come in `mister/rtl/pong_render.v`, cioè un pixel è acceso se il suo
  centro cade nel rettangolo. I registri degli sprite si copiano nel VIC durante il vblank, che
  comincia con un interrupt alla riga 250.
- **Schermate:** `.\c64\build.ps1 -Name autostart -Define AUTOSTART` produce una versione che parte
  subito con una partita, da fotografare con `.\c64\shot.ps1 out.png -Prg autostart` (con anche
  `AUTONEXT` la partita è NEXT, con `AUTOCHALLENGE` CHALLENGE). Con `-Name autoend -Define
  ENDTEST` parte il finale di CHALLENGE.
