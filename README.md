# PADD WS

Pong da tavolo per due giocatori seduti ai lati opposti dello schermo, con l'attract dei cabinati
anni '80, le partite a gettoni e quattro modalità di gioco. Esiste in quattro versioni che giocano
la stessa identica partita:

| versione | dove gira | cartella |
|---|---|---|
| **Python** (Arcade 3.3) | Windows, Linux, macOS, cabinati Raspberry Pi con encoder rotativi | [paddws/](paddws) |
| **Rust** (macroquad), un unico eseguibile | Windows, Linux x86_64, Linux ARM64 (Raspberry Pi) | [rust/](rust/README.md) |
| **Core MiSTer FPGA**, 320×240 a 15 kHz | DE10-Nano con MiSTer | [mister/](mister/README.md) |
| **Commodore 64** (anteprima, PAL), assembly 6502 | C64, C64 Ultimate, emulatori (VICE) | [c64/](c64/README.md) |

**Si gioca anche nel browser**, dal computer, dal telefono o dal tablet:
<https://schermobianco.github.io/PaddWS/> (la versione Rust in WebAssembly, aggiornata a ogni
release).

La logica di gioco di riferimento è il core Rust: deterministico, solo interi, nessuna divisione.
Il core MiSTer ne riproduce lo stato tick per tick, verificato bit per bit con vettori di test, e
lo stesso fa la versione C64, verificata in un emulatore 6502.

## Schermate

| | |
|---|---|
| ![Titolo dell'attract con il filtro CRT](docs/screenshots/attract-crt.jpg) | ![Conto alla rovescia prima del servizio](docs/screenshots/countdown.png) |
| Titolo dell'attract, con il filtro CRT | Conto alla rovescia prima del servizio |
| ![NEXT: scelta dei bonus](docs/screenshots/next-pick.png) | ![NEXT: riserve, capsule e SUPER armato](docs/screenshots/next-game.png) |
| NEXT: ognuno sceglie 3 bonus su 6 | NEXT: riserve in alto, capsule in volo, racchetta che ruota con il SUPER |
| ![NEXT: presentazione delle mosse speciali](docs/screenshots/next-howto.png) | ![NEXT: STRAIGHT SHOT in volo](docs/screenshots/next-supers.png) |
| NEXT: HOW TO PLAY, le mosse speciali prima della partita | NEXT: barre delle mosse accanto alle riserve, STRAIGHT SHOT in volo |
| ![Core MiSTer: titolo](docs/screenshots/mister-title.png) | ![Core MiSTer: demo NEXT](docs/screenshots/mister-demo.png) |
| Core MiSTer a 320×240: titolo dopo il gettone | Core MiSTer: demo CPU contro CPU della modalità scelta (qui NEXT) |
| ![Commodore 64: titolo](docs/screenshots/c64-title.png) | ![Commodore 64: partita NEXT](docs/screenshots/c64-next.png) |
| Commodore 64: titolo dopo il gettone | Commodore 64: NEXT contro la CPU (BLASTER, capsula del SUPER) |
| ![Commodore 64: scelta dei bonus](docs/screenshots/c64-pick.png) | ![Commodore 64: CHALLENGE](docs/screenshots/c64-challenge.png) |
| Commodore 64: scelta dei bonus (la CPU ha già scelto) | Commodore 64: presentazione del primo avversario di CHALLENGE |

Le schermate PC vengono da `paddws --screenshot-tour DIR` (versione Rust), quelle MiSTer dalla
simulazione del core con Verilator (`mister/sim/frames`), quelle C64 da VICE (`c64/shot.ps1`).

## Scaricare

Ogni [release](https://github.com/Schermobianco/PaddWS/releases) contiene:

- `paddws-X.Y.Z-python.zip` – versione Python: `pip install -r requirements.txt`, poi `python main.py`;
- `paddws-X.Y.Z-windows-x86_64.zip`, `paddws-X.Y.Z-linux-x86_64.tar.gz`,
  `paddws-X.Y.Z-linux-aarch64.tar.gz` – versione Rust, si avvia direttamente;
- `PaddWS_MiSTer_AAAAMMGG.zip` – core MiSTer: si scompatta nella radice della SD (`/media/fat`),
  il gioco compare tra i titoli arcade;
- `paddws-X.Y.Z-c64.zip` – versione Commodore 64: `paddws.crt`, cartuccia EasyFlash (la
  classifica di CHALLENGE si salva nella sua flash).

## Avvio dai sorgenti (Python)

```sh
python -m venv .venv
.venv\Scripts\activate            # Linux/macOS: source .venv/bin/activate
pip install -e ".[dev]"
python -m paddws                  # oppure: python main.py, oppure: paddws
```

Opzioni: `--config FILE`, `--fullscreen` / `--windowed`, `--crt` / `--no-crt`, `--debug`.
Per la versione Rust vedi [rust/README.md](rust/README.md), per il MiSTer [mister/README.md](mister/README.md).

## Come si gioca

All'accensione parte l'attract: auto-test, strisce, logo e titolo con la pallina che rimbalza su
tutto ciò che è nero, la classifica di CHALLENGE e una partita dimostrativa, CPU contro CPU, nella
modalità scelta (nel menu sul PC, nell'OSD sul MiSTer). La demo mostra CLASSIC, EVO, NEXT con bonus
e racchette a caso, oppure CHALLENGE contro l'avversario di un livello a caso, con il nome della
modalità al centro; sul C64 la demo è sempre EVO, nella versione Python non c'è. Con un gettone, o
in Free Play, Start apre il menu (sul MiSTer avvia subito la partita con le opzioni dell'OSD); ogni
partita costa un credito, anche in due. La partita comincia dopo un conto alla rovescia di 3
secondi.

Nelle versioni Rust, MiSTer e C64 si può giocare anche da soli contro il computer, in tutte le
modalità (menu: **PLAYERS: VS CPU**); la bravura della CPU segue la difficoltà. Da soli c'è anche
la scalata **CHALLENGE** (vedi sotto).

- **CLASSIC** – Pong classico, 1 o 2 giocatori. In due vince chi arriva per primo a 11; in singolo
  si gioca contro un muro con 3 palle, ogni rimbalzo vale un punto e `TOP` è il record.
- **EVO** (2 giocatori) – colpire la palla nell'area grigia al centro della racchetta la potenzia
  (l'area si restringe a ogni boost); lo scatto in avanti intercetta la palla e la rilancia.
- **NEXT** (2 giocatori o contro la CPU, versione Rust e MiSTer) – Classic con lo scatto in
  avanti e i bonus: prima della partita ognuno sceglie 3 bonus su 6; le capsule partono dalla
  mezzeria e si raccolgono toccandole con la racchetta, poi si scelgono e si attivano dalla
  riserva in alto. Ogni capsula mostra il simbolo del suo bonus:

| bonus | effetto |
|:---:|---|
| <img src="docs/icons/teleport.png" alt="" width="40" height="40"><br>**TELEPORT** | quando la palla in arrivo supera la metà campo, la racchetta entra in un portale ed esce da un altro nel punto in cui arriverà la palla, in tempo per prenderla |
| <img src="docs/icons/smash.png" alt="" width="40" height="40"><br>**SMASH** | il prossimo tiro parte più veloce e angolato, lontano dall'avversario |
| <img src="docs/icons/slow.png" alt="" width="40" height="40"><br>**SLOW** | la palla perde un terzo della velocità finché chi l'ha usato non la colpisce: allora riparte alla velocità di prima |
| <img src="docs/icons/curve.png" alt="" width="40" height="40"><br>**CURVE** | il prossimo tiro curva, e la curva si inverte a ogni rimbalzo |
| <img src="docs/icons/ghost.png" alt="" width="40" height="40"><br>**GHOST** | dopo il prossimo tiro la palla si vede solo a lampi |
| <img src="docs/icons/steer.png" alt="" width="40" height="40"><br>**STEER** | dopo il prossimo tiro i comandi su e giù guidano la palla, con una sterzata limitata, fino a 3/4 del campo (segnati in giallo sui bordi); intanto la racchetta resta ferma |
| <img src="docs/icons/super.png" alt="" width="40" height="40"><br>**SUPER** | raro, solo dalle capsule: tiro velocissimo, con un'animazione a caso tra racchetta che ruota, hit-stop e cometa che spacca la rete |
| <img src="docs/icons/bullet.png" alt="" width="40" height="40"><br>**BULLET** | raro, solo dalle capsule (circa una su 16): bullet time difensivo. Una volta attivato resta armato (il bordo giallo della racchetta lampeggia) finché la palla non entra nella propria metà campo, diretta verso di sé; allora, con un'entrata graduale, tutto va a metà velocità (palla con CURVE e STEER, racchetta avversaria, capsule, colpi del BLASTER avversario) tranne la propria racchetta, fino alla ribattuta o al punto. Il resto del gioco diventa grigio e sfocato (sul MiSTer con bordi sfumati, sul C64 solo grigio) e la palla lascia una scia di immagini. Se si subisce un punto prima che scatti, il bonus non si consuma; se ne usa uno alla volta |

### Tipi di racchetta (NEXT)

Dopo i bonus ognuno sceglie la sua racchetta (la CPU a caso; in CHALLENGE ogni avversario ha la
sua). Ogni tipo ha un vantaggio, un piccolo prezzo e un segno che lo fa riconoscere in partita (in
giallo nell'immagine, con le racchette in proporzione). I tipi sono bilanciati perché ognuno vinca
circa metà dei punti contro la racchetta normale.

![I sette tipi di racchetta, in proporzione, con i loro segni](docs/icons/paddles.png)

| tipo | vantaggio | prezzo |
|---|---|---|
| **ARCADE** | più capsule: partono ogni 3-4 s invece di 4-5 e due su tre vanno a lui (se l'avversario non è ARCADE); pausa più breve tra due bonus | più corta (0,8) |
| **TITAN** | più alta (1,2) | più lenta (0,8) |
| **HAMMER** | i tiri partono più veloci (×1,25, se la palla non ha già un boost) | lenta (0,75) |
| **TWIST** | passa alla palla metà della sua velocità verticale: colpendo in movimento si dà angolo; si inclina con la velocità | — |
| **BLASTER** | spara: caricatore di 4 colpi veloci da sparare di fila, mostrati come rettangolini gialli dietro la racchetta (si ricarica 3 s dopo il primo colpo); i colpi raccolgono le capsule, anche quelle dirette all'avversario | niente scatto in avanti: spara con quel tasto |
| **RUSH** | scatto in avanti più lungo (×1,5), che prende la palla più spesso; dalla posizione avanzata i tiri partono più veloci (×1,15, anche lo scatto che intercetta la palla) e più vicini all'avversario; la racchetta avanzata è anche più rapida (×1,15) | più corta (0,85) |
| **GUARDIAN** | un muro a 5 settori dietro la racchetta, uno per partita: ogni palla mancata rimbalza sul settore all'altezza della palla, che poi sparisce | più corta (0,8) |

Con l'encoder (o con paddle e spinner sul MiSTer) i tipi più lenti seguono la manopola, ma con una
velocità massima. I valori sono nella sezione `next.paddles` della configurazione.

### Mosse speciali (NEXT)

Mosse da picchiaduro che si fanno con un gesto del controllo (versioni Rust, MiSTer e C64). Si
accendono con **SUPER MOVES: ON** nel menu (sul MiSTer, OSD *Super moves*) e valgono per le partite
NEXT, per la CHALLENGE e per la demo dell'attract; sono le stesse per tutti i tipi di racchetta.
Prima della partita la schermata **HOW TO PLAY**, in pixel art come nei giochi Neo Geo, le
presenta: il comando del controllo in uso (tastiera, gamepad o stick arcade, spinner del cabinato,
mouse o touch) si accende passo dopo passo, la palla parte con l'effetto della mossa, e sotto ci
sono il costo e i comandi dei bonus. Start (o il clic, o un tocco) la salta; in CHALLENGE compare
solo prima del primo livello.

La barra accanto alla riserva si riempie giocando: un po' a ogni colpo, il doppio con lo scatto
che intercetta la palla, di più quando si subisce un punto; non si svuota tra un punto e l'altro. La barra
ha due settori e una mossa ne spende quanti ne sono pieni: con mezza barra parte la mossa normale,
con la barra piena la **MAX**, più forte. Si può usare subito o aspettare la MAX, rischiando che la
palla giusta non torni. Quando una mossa è pronta la barra diventa gialla. Una mossa alla volta,
non durante la battuta e non con un bonus armato (e mentre una mossa è armata non si attivano
bonus).

| mossa | effetto |
|---|---|
| **STRAIGHT SHOT** | il prossimo tiro parte dritto, senza angolo, a una volta e mezza la spinta del colpo (il doppio la MAX); vale un tiro solo, e si perde se l'avversario lo intercetta con lo scatto |
| **RISING STRIKE** | il prossimo tiro parte dritto e, passati i 5/8 del campo (i 7/8 la MAX), s'impenna di colpo a 45° lontano dalla racchetta avversaria: inganna chi si era già messo sulla traiettoria |

| comando | STRAIGHT SHOT | RISING STRIKE |
|---|---|---|
| tastiera | giù, su + scatto | su, giù + scatto |
| joystick (MiSTer, gamepad e stick arcade su PC, Raspberry e web) | ↓ ↘ → + **A** (→ = verso l'avversario) | → ↓ ↘ + **A** |
| joystick (C64) | ↓ ↘ → + fuoco (→ = verso l'avversario) | → ↓ ↘ + fuoco |
| encoder, paddle, spinner | la manopola gira veloce in giù e torna su, poi click (**A**) | gira veloce in su e torna giù, poi click (**A**) |
| mouse come spinner (PC e web) | il mouse scorre veloce in giù e torna su, poi clic sinistro | scorre veloce in su e torna giù, poi clic sinistro |
| touch (telefoni e tablet) | il dito che muove la racchetta scorre veloce in giù sullo schermo e torna su, poi un tocco con un secondo dito | lo stesso dito scorre veloce in su e torna giù, poi un tocco con un secondo dito |

Le direzioni vanno date entro 0,3 s l'una dall'altra e lo scatto entro 0,25 s dall'ultima. Lo
scatto che chiude il gesto diventa la mossa solo se la mossa può partire; altrimenti resta uno
scatto normale. Anche la CPU usa le mosse, quando è già sulla palla, e di solito aspetta la MAX;
quando un RISING STRIKE s'impenna, le serve il suo tempo di reazione per accorgersene, come a una
persona.

Sul C64 il fuoco che chiude la mezzaluna usa la mossa se può partire, altrimenti il bonus
selezionato (lo scatto è il joystick verso l'avversario); con i paddle non ci sono gesti, la demo
dell'attract resta EVO e non c'è la schermata HOW TO PLAY. Barra, icona della mossa armata, scritta
"P1 MAX STRAIGHT SHOT!" e suoni ci sono, le voci urlate no (vedi [c64/README.md](c64/README.md)).

### CHALLENGE

Da soli contro 7 avversari CPU, versione Rust, MiSTer e C64 (menu **PLAYERS: CHALLENGE**, sul MiSTer
OSD *Players: Challenge*). Si scelgono una volta bonus e racchetta, poi ogni livello presenta il suo
avversario: un tipo di racchetta diverso per livello, i suoi 3 bonus e una CPU sempre più forte,
dall'ARCADE del primo livello al GUARDIAN del boss finale. Le partite sono NEXT a 5 punti.

- **Punti arcade**: colpi, scatti riusciti, SUPER e punti segnati, con un moltiplicatore che sale
  negli scambi lunghi (fino a ×8); a ogni livello vinto un premio, doppio se l'avversario non ha
  fatto punti.
- **Continue**: perso un livello, 10 secondi per inserire un gettone (o premere Start in Free
  Play) e riprovare lo stesso livello, con i punti da zero.
- **Classifica**: i 10 migliori con le iniziali, mostrata anche nell'attract. Sul PC si salva in
  `padd_scores.json` accanto alla configurazione; sul MiSTer resta finché il core è acceso.
- **Nuovo sfidante**, come in Street Fighter 2: durante la presentazione di un livello, la
  partita contro la CPU o il livello superato, un secondo giocatore con un credito (o in Free
  Play) preme il suo Start (sul PC `2`, o `1` se il campione gioca a destra; sul web un dito
  tenuto 1 s nella metà libera) e compare **HERE COMES A NEW CHALLENGER!**. Lo sfidante sceglie
  bonus e racchetta e si gioca una sfida a 5 punti: chi vince riprende il livello contro la CPU
  dal suo lato, con un premio pari a quello del livello (il campione lo aggiunge ai suoi punti,
  lo sfidante parte da lì); chi perde scrive le iniziali se entra in classifica.
- **Finale**: battuto l'ultimo avversario arrivano CONGRATULATIONS e la voce "YOU WIN!", la
  sfilata dei sette avversari con il timbro DEFEATED, il punteggio finale con il premio del
  campione (la vittoria dell'ultimo livello, più la partita perfetta), "YOU ARE THE PADD WS
  CHAMPION" con i fuochi d'artificio, i titoli di coda e THE END, in circa un minuto, con una
  musica tutta sua; poi le iniziali. Start lo salta. La voce "YOU WIN!" si sente anche a ogni
  partita vinta contro la CPU.
- **Voce**: nella presentazione una voce digitalizzata "da SID" annuncia il nome dell'avversario
  (su C64 e MiSTer con il trucco del registro del volume del SID; sul C64 dalla cartuccia).
- **Musiche degli avversari**: in partita contro la CPU ogni avversario ha il suo tema, sulle prime
  due voci del SID (la terza resta agli effetti). Si spengono con **MUSIC: OFF** nel menu (OSD
  *Music* sul MiSTer, che spegne tutte le musiche); sul C64 il tema arriva con la voce, dalla
  cartuccia.

La scala è tarata per un giocatore medio con il joystick (vince il primo livello quasi sempre, il
boss circa una volta su quattro); la difficoltà del menu sposta la velocità della palla: con spinner
o paddle conviene HARD o EXPERT.

### Suono

Suoni e musiche passano per un **SID** (il chip del Commodore 64): sul MiSTer è quello del core C64
(OSD *Sound*: SID 8580 o SID 6581; *Music: Off* spegne tutte le musiche, non gli effetti); su PC,
Raspberry e web (menu **MUSIC: ON / OFF**, che spegne tutte le musiche e lascia gli effetti) le
musiche le suona in tempo reale un SID scritto in Rust con lo stesso player (`rust/sid`), gli
effetti sono registrati dal core simulato. **ATTRACT SOUND: OFF** rende muto l'attract, musica
compresa: nell'attract la musica si sente solo se sono accesi sia ATTRACT SOUND sia MUSIC. Le
musiche sono originali: il titolo, la presentazione dei livelli, il livello superato, il continue,
il game over, il campione e il finale; in partita solo gli effetti, tranne in CHALLENGE, dove ogni
avversario ha il suo tema. Il tema accelera al match point (×1,25, stesse note) e nel bullet time
rallenta di un'ottava, come un nastro a metà velocità. Alcune musiche usano il filtro del SID (il
basso di HAMMER, il titolo, TITAN, il finale) e sono pensate per l'8580.

### Comandi su PC

| | giocatore sinistro | giocatore destro |
|---|---|---|
| su / giù | `W` / `S` | `↑` / `↓` |
| scatto in avanti (EVO, NEXT) | `D` | `←` |
| NEXT: seleziona / attiva il bonus | `F` / `C` | `.` / `-` |
| NEXT: STRAIGHT SHOT / RISING STRIKE | `S` `W` + `D` / `W` `S` + `D` | `↓` `↑` + `←` / `↑` `↓` + `←` |
| encoder (Raspberry) | rotazione = posizione, click = scatto, click lungo = menu | idem |
| mouse come spinner (opzione) | movimento verticale = posizione, sinistro = scatto, destro / centrale = seleziona / usa il bonus | — |

Doppio tocco su o giù = accelerazione rapida. `5` gettone, `Invio` / `Spazio` / `1` Start,
`P` pausa, `Esc` menu e uscita, `F11` schermo intero, `C` filtro CRT (non durante NEXT).
Il menu è una ruota: `↑` / `↓` la girano (la voce scelta resta al centro, gialla), `←` / `→`
cambiano il valore, `Invio` conferma; con l'encoder o il mouse come spinner la gira la manopola,
sul touch il dito (un tocco sulla voce al centro la usa, su un'altra la porta al centro).

**Gamepad e stick arcade** (PC, Raspberry e web): il primo collegato è del giocatore di sinistra,
il secondo di quello di destra; se si gioca da soli con un solo gamepad, è di chi gioca. Levetta o
croce per muovere (la levetta analogica con le diagonali, per le mosse), **A** scatto e mosse
speciali, **B** seleziona e **C** (X o Y) usa il bonus, come nella HOW TO PLAY; **Start** pausa e
Start, **Select** gettone. Nei menu si usano le direzioni, **A** conferma e **B** torna indietro;
in pausa **A** riprende e **B** torna al menu. Funzionano anche gli stick arcade USB e le schede
encoder dei cabinati, che non hanno la levetta analogica (vedi
[rust/README.md](rust/README.md#gamepad-e-stick-arcade)).

**Mouse come spinner** (PC e web, menu **MOUSE SPINNER: ON** o `mouse.spinner` nella
configurazione, spento di default): il mouse diventa la manopola del giocatore di sinistra, come
l'encoder del cabinato. Il cursore resta catturato nella finestra (su Windows si libera quando la
finestra passa in secondo piano) e il movimento verticale porta la racchetta all'altezza
corrispondente: `mouse.travel_pixels` pixel di mouse per tutta la corsa. Clic sinistro = scatto in
avanti (e Start, conferma nel menu), destro = seleziona il bonus, centrale (rotella) = usa il
bonus; mosse speciali come con lo spinner. Nei menu il movimento sceglie la voce e il clic la
usa. Il giocatore di destra resta sulla tastiera. Nel browser il cursore si cattura con il
Pointer Lock dopo il primo clic sulla pagina; `Esc` lo rilascia e un altro clic lo riprende.

Sul MiSTer: joystick su/giù (oppure paddle o spinner), **A** scatto in avanti, **B** rapido,
**X** / **Y** seleziona e usa il bonus (NEXT), **Start**, **Select** gettone; da tastiera `5` e `1`.
Le mosse speciali si fanno con le mezzelune del joystick + **A** (vedi sopra). Le opzioni (modalità,
giocatori, Free Play, difficoltà, punteggi dritti (default) o verso i giocatori, suoni dell'attract,
luminosità del bianco, paddle o spinner, mosse speciali) sono nell'OSD.

### Telefoni e tablet (versione web)

La versione Rust gira anche nel browser (WebAssembly), su Android e iOS, in orizzontale (in
verticale chiede di ruotare il dispositivo). Da soli o contro la CPU tutto lo schermo è del
giocatore; in due ognuno ha la sua metà.

- la racchetta segue il dito, all'altezza del dito; con STEER il dito sopra o sotto la racchetta
  ferma sterza la palla;
- un secondo dito, mentre il primo tiene la racchetta, fa lo scatto in avanti;
- mosse speciali: il dito della racchetta scorre veloce in giù e torna su (o in su e torna giù),
  poi un tocco del secondo dito;
- NEXT: un tocco su una capsula della propria riserva in alto usa subito quel bonus;
- menu: si trascina la ruota col dito, un tocco sulla voce al centro la cambia o la usa;
- scelta dei bonus: si toccano i tre bonus (un altro tocco li toglie), poi OK in cima alla colonna;
- scelta della racchetta: un tocco la mostra, un secondo tocco sulla stessa riga la sceglie;
- nell'attract un tocco vale come Start;
- pausa: un tocco sul simbolo ❚❚ in cima alla linea centrale; in pausa si tocca per riprendere o
  su MENU (RESUME, nel menu, riprende la partita);
- CHALLENGE: lo sfidante entra tenendo il dito per un secondo dietro la racchetta della CPU (P2
  HOLD HERE).

Nel browser del computer il mouse fa da dito (o da spinner, con **MOUSE SPINNER: ON** nel menu)
e la tastiera e i gamepad funzionano come su PC. Le preferenze del menu e la classifica della
CHALLENGE restano nel browser (`localStorage`). Sui dispositivi touch il primo tocco porta a
schermo intero (Android, iPad) e lo schermo resta acceso; su iPhone lo schermo intero si ottiene
con *Condividi → Aggiungi a Home* (su Android anche con *Installa app*). L'audio parte al primo
tocco.

## Configurazione (PC)

`padd_config.json` viene letto all'avvio; le chiavi mancanti prendono il valore di default, quelle
sconosciute vengono segnalate e ignorate. Dimensioni e velocità sono espresse per la risoluzione
di riferimento 800×480 e scalate su `resolution`. Dal menu si cambiano e si salvano schermo
intero, filtro CRT, difficoltà, musica, suoni dell'attract, luminosità del bianco, mosse speciali e
mouse come spinner.

Con `resolution.width = 0` (default) il campo prende le proporzioni del monitor con l'altezza
indicata: 640×480 su 4:3, 853×480 su 16:9, 800×480 sul display del Pi, quindi niente bande nere.
Una larghezza esplicita (es. `640` per un cabinato 4:3) fissa il campo; se lo schermo ha
proporzioni diverse compaiono le bande nere (`game.keep_aspect`) invece della deformazione.

| chiave | default | |
|---|---|---|
| `game.free_play` | `true` | senza gettoni; con `false` serve un credito per partita (tasto `5`) |
| `game.points_to_win` | `11` | punti per vincere in due |
| `game.lives` | `3` | palle in singolo |
| `game.difficulty` | `1` | 0 EASY, 1 NORMAL, 2 HARD, 3 EXPERT |
| `game.self_test` | `true` | auto-test all'avvio |
| `game.attract_sound` | `true` | suoni e musica dell'attract (gettone e Start si sentono sempre) |
| `game.music` | `true` | tutte le musiche (menu **MUSIC**); gli effetti restano. Prende il posto di `game.sid_sound` e `game.match_music`: se una delle due era `false` la musica resta spenta |
| `game.white_level` | `100` | luminosità del bianco in percento (menu: 100, 87, 75, 62), tutta l'immagine in proporzione |
| `game.scores_upright` | `true` | punteggi dritti in alto (menu **SCORES: UPRIGHT**); con `false` rivolti ai giocatori seduti ai lati di un tavolo (**FACING**) |
| `colors.accent` | `[255, 210, 37]` | colore di accento (il giallo dell'attract): la voce scelta del menu; solo in NEXT: titolo del menu, titolo e cursore della scelta, scritta del bonus attivato, freccetta della riserva, portali di TELEPORT, volante e segni del limite di STEER, capsula e palla del SUPER, capsula del BULLET e bordo della racchetta di chi lo ha armato |
| `mouse.spinner` | `false` | il mouse come spinner del giocatore di sinistra (menu **MOUSE SPINNER**); con gli encoder del cabinato non conta |
| `mouse.travel_pixels` | `1000` | pixel di movimento del mouse per portare la racchetta da un bordo all'altro |
| `game.vsync`, `game.keep_aspect`, `game.serve_delay` | | sincronia verticale, bande nere, attesa alla battuta |

La difficoltà regola quanto accelera la palla a ogni colpo e la sua velocità massima (pixel per
frame a 800×480); in singolo accelerano solo i colpi del giocatore, non il muro. I valori di NEXT
si cambiano nella sezione `next` (vedi sotto).

| difficoltà | singolo | in due | NEXT |
|---|---|---|---|
| EASY | +5% / 8 | +15% / 6 | +4% / 6 |
| NORMAL | +10% / 10 | +25% / 8 | +7% / 7 |
| HARD | +15% / 12 | +25% / 10 | +9% / 8 |
| EXPERT | +25% / 15 | +30% / 12 | +12% / 9 |

### Parametri di NEXT

La sezione `next` regola palla, capsule e bonus della modalità NEXT nella versione Rust; se manca,
il gioco la aggiunge al file con i default. I default sono gli stessi del core MiSTer: con valori
diversi il PC non coincide più con l'FPGA, quindi servono per provare nuove regolazioni (i valori
buoni si riportano poi nel core Rust e nel MiSTer).

| chiave | default | |
|---|---|---|
| `ball_speedup`, `ball_max_speed` | `[1.06, 1.10, 1.14, 1.18]`, `[7, 10, 11, 13]` | accelerazione a ogni colpo e velocità massima, per difficoltà |
| `capsule_size`, `capsule_speed`, `capsule_drift` | `26`, `2.5`, `0.3` | lato, velocità e deriva verticale delle capsule |
| `hud_band` | `48` | fascia in alto riservata alle riserve |
| `spawn_seconds`, `spawn_jitter_seconds` | `4`, `1` | secondi tra due capsule, più una parte casuale |
| `super_odds` | `8` | una capsula su 8 contiene il SUPER |
| `bullet_odds` | `16` | una capsula su 16 contiene il BULLET (0 = mai) |
| `bullet_ramp_seconds` | `0.25` | rampa di entrata del BULLET (dura fino alla ribattuta o al punto) |
| `bullet_speed`, `bullet_ramp_speed` | `0.5`, `0.75` | velocità del resto del gioco durante il BULLET e nella rampa (1 − 1/2ⁿ: 0,5, 0,75, 0,875…) |
| `cooldown_seconds` | `2` | pausa minima tra due bonus dello stesso giocatore |
| `smash_multiplier`, `super_multiplier` | `2.2`, `3.2` | velocità orizzontale del tiro con SMASH e SUPER |
| `slow_multiplier`, `slow_seconds` | `0.65`, `1` | velocità che resta con SLOW; `slow_seconds` non conta più (l'alone dura quanto il rallentamento) |
| `curve_accel` | `0.3` | effetto di CURVE |
| `steer_accel` | `0.3` | sterzata di STEER con su o giù premuti (la palla guidata arriva al massimo a circa 63°) |
| `hitstop_seconds` | `0.167` | fermo del gioco del SUPER con hit-stop |
| `super_moves` | `false` | mosse speciali accese (si cambia anche dal menu) |
| `super_meter_max`, `super_cost` | `64`, `32` | barra delle mosse speciali e costo di una mossa |
| `super_gain_hit`, `super_gain_dash`, `super_gain_conceded` | `2`, `4`, `8` | barra guadagnata con un colpo, con lo scatto che intercetta, con un punto subito |
| `super_straight_multiplier` | `2` | spinta del tiro con STRAIGHT SHOT MAX (1 + 1/2ⁿ: 2, 1,5, 1,25…); la mossa normale ha la metà dell'aggiunta |

## Fluidità e latenza

- Fisica a passo fisso di 1/240 s con interpolazione del rendering: movimento identico a
  60, 120, 144 o 165 Hz e input applicato entro ~4 ms.
- Un solo aggiornamento per frame presentato, cadenzato dal vsync; se il driver ignora il
  vsync il gioco lo rileva e si limita alla frequenza del monitor.
- Sincronizzazione con la GPU dopo ogni frame: niente frame accodati dal driver, ~1 frame di
  latenza (disattivata da sola se con il compositor in uso farebbe perdere frame).
- Filtro CRT calcolato al massimo a 720p e poi ingrandito: a 1440p/4K resta nel budget del frame.
- Audio, glifi e GC "pre-riscaldati" all'avvio: nessuno scatto alla prima occorrenza.
- Collisioni continue: la palla non può attraversare la racchetta a nessuna velocità.

## Struttura

```
paddws/          versione Python
  core/            logica di gioco pura (match, parametri, doppio tocco), senza dipendenze grafiche
  app.py           finestra: scaling letterbox, audio, ritmo dei frame
  attract.py       sequenza attract
  scenes.py        attract, menu, partita
  config.py        configurazione tipizzata, caricamento e salvataggio JSON
  crt.py           filtro CRT
  hardware.py      encoder (pigpio), rilevamento Raspberry Pi, spegnimento
rust/            versione Rust: core deterministico, gioco, generatore di tracce per il MiSTer
mister/          core MiSTer: RTL Verilog, simulazione, progetto Quartus (framework Template_MiSTer)
c64/             versione Commodore 64 in 6502 (anteprima), verificata contro il core Rust
assets/          font, immagini, suoni, icone, bitmap e tempi dell'attract (comuni a tutte le versioni)
deploy/raspberry servizio systemd e configurazione di boot
tools/           rilascio, ambiente Rust portable, generatori di icone, attract, suoni e ROM MiSTer,
                 musiche del SID (gen_sid_music.py, suonate dal SID Rust di rust/sid) e scritte di
                 CHALLENGE
tests/           test pytest della versione Python
```

## Test

```sh
pytest                                  # versione Python
cd rust && cargo test                   # core e gioco Rust
.\mister\sim\run.ps1                    # logica HDL contro il core Rust (sim/run.sh su Linux)
cd rust && cargo run --release -p paddws-c64 -- game   # versione C64 contro il core Rust
```

Le GitHub Action `Python`, `Rust`, `MiSTer` e `C64` eseguono gli stessi controlli; la `MiSTer`
sintetizza anche il core con Quartus 17.0.2, la `C64` assembla il programma con cc65 e lo prova nel
banco di prova (vedi [c64/README.md](c64/README.md)). Partono solo a mano (*Run workflow*, `gh
workflow run` o `build_ongithub.bat`). Gli stessi controlli girano in locale con
`build.bat -CheckOnly`.

## Raspberry Pi

Sul cabinato gira la versione Python oppure quella Rust (con NEXT, la CPU e gli encoder letti
direttamente dai GPIO, anche sul Pi 5), ciascuna con il suo servizio systemd. Installazione e
schema di collegamento di encoder e pulsanti: [deploy/raspberry/README.md](deploy/raspberry/README.md).

## Versione web

```powershell
.\tools\build-web.ps1          # paddws.wasm, pagina e JavaScript in rust\target\web
.\tools\build-web.ps1 -Serve   # e un server su http://localhost:8080 (dal telefono: http://<PC>:8080)
```

La prima volta serve il target WebAssembly: `rustup target add wasm32-unknown-unknown` (dopo
`. .\tools\rust-env.ps1`). La pagina è in [`rust/web/`](rust/web/); il JavaScript è quello di
miniquad e quad-snd nelle versioni di `Cargo.lock`. Dal telefono sulla stessa rete si prova con
`-Serve` (il firewall di Windows deve lasciar passare la porta 8080).

Online è su GitHub Pages, <https://schermobianco.github.io/PaddWS/>, dal ramo `gh-pages`:
`build.bat -Publish` ci mette, dopo la release, il contenuto dello zip web
([`tools/publish-pages.ps1`](tools/publish-pages.ps1), lanciabile anche da solo).

## Commodore 64

Versione in assembly 6502 (anteprima, solo PAL) che gioca la stessa partita del core Rust, bit per
bit: aritmetica Q16.16 a 32 bit, un tick per frame a 50 Hz, campo di 320×200 pixel. Ha tutto
quello delle altre versioni: attract, gettoni e menu, Classic, EVO e singolo, la CPU (la stessa del
core, comando per comando), NEXT con tipi di racchetta, effetti e mosse speciali, CHALLENGE con il
finale e la classifica salvata nella flash della cartuccia, musiche ed effetti sul SID vero.

- **Avvio:** dal pacchetto `paddws-X.Y.Z-c64.zip`, la cartuccia EasyFlash `paddws.crt` (C64
  Ultimate, EasyFlash vera scritta con EasyProg, VICE): tutto in un file, avvio immediato e voce
  della CHALLENGE senza caricamenti; la classifica si salva nella flash della cartuccia e resta
  anche da spenti (in VICE con `-easyflashcrtwrite`).
- **Comandi:** joystick nella porta 2 (sinistra) e 1 (destra), oppure una coppia di paddle nella
  porta 1. Su e giù muovono la racchetta, il fuoco scatta in avanti (e spara con il BLASTER); in
  NEXT sinistra sceglie il bonus e destra lo usa. Tasto **5** gettone, fuoco o **RETURN** Start,
  **RUN/STOP** pausa, **Q** menu.
- **Verifica:** il banco di prova `rust/c64` esegue il programma in un emulatore 6502 e confronta
  ogni tick con il core Rust, conta i cicli di ogni frame e confronta il player del SID con quello
  del MiSTer.

Compilazione, memoria, grafica e scelte tecniche: [c64/README.md](c64/README.md). Mancano NTSC e
le prove sull'hardware vero (finora provata in VICE).

## Versioni

Numerazione [Semantic Versioning](https://semver.org/lang/it/), una sola per tutto il progetto:
Python (`paddws/__init__.py`), Rust (`rust/Cargo.toml`), core MiSTer e versione C64 escono insieme
con lo stesso numero (un test controlla che quelli di Python e Rust coincidano). La versione
compare nel menu, nel log all'avvio e con `--version`. Le modifiche sono descritte in
[CHANGELOG.md](CHANGELOG.md).

Per rilasciare: aggiungere le voci sotto **Non rilasciato** nel changelog, poi

```sh
python tools/release.py minor      # oppure patch / major / X.Y.Z / X.Y.Z-beta.N, --dry-run per provare
git push --follow-tags
```

Lo script aggiorna la versione di Python e Rust e il changelog (le anteprime `-alpha.N` e
`-beta.N` lasciano le voci in **Non rilasciato**), crea il commit e il tag `vX.Y.Z`. I pacchetti
si costruiscono poi in uno di questi due modi:
- `build_ongithub.bat VERSIONE` fa tutto online: controlli, `tools/release.py`, push, avvia le
  GitHub Action sul tag e le segue fino alla release (core MiSTer compreso); senza versione rilancia
  le Action del tag già presente sul commit (per esempio dopo un blocco dei minuti di GitHub).
- `build.bat` fa gli stessi controlli e gli stessi pacchetti in locale, in `dist\`, sulla macchina
  virtuale *forge* ([tools/forge](tools/forge/README.md)): la accende e la spegne da solo, e sul PC
  bastano git e ssh. `build.bat -Publish` pubblica poi la release del tag con `gh`.

## Licenza

Copyright © 2020-2026 Schermobianco.

Il codice di PADD WS (Rust, C64, Python, strumenti) è software libero: si può ridistribuire e
modificare secondo la [GNU General Public License v3](LICENSE) o, a scelta, una versione successiva.
Chi lo distribuisce, anche a pagamento e anche modificato, deve dare i sorgenti con la stessa
licenza. Il core MiSTer è GPL v2 o successiva, perché costruito sul framework del MiSTer
([mister/LICENSE](mister/LICENSE)), e include l'emulazione del SID del core C64 del MiSTer, in parte
con licenza CERN-OHL-S v2. Font, dipendenze e le altre parti di terzi sono elencati in
[THIRD_PARTY.md](THIRD_PARTY.md), con le loro licenze. Fino alla 4.0.0-beta.16 il codice era
distribuito con licenza MIT.
