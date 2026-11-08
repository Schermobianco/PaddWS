# Configurazione

[← README](../../README.md) · [<img src="../flags/it.svg" alt="" height="14"> **Italiano**](configurazione.md) · [<img src="../flags/gb.svg" alt="" height="14"> English](../en/configuration.md)

Riguarda la versione Rust su PC e Raspberry Pi. La versione Python, congelata, legge lo stesso
file ma conosce solo le chiavi di CLASSIC ed EVO (`resolution`, `ball`, `paddle`, `boost`,
`encoder`, `crt_effects`, `colors` e le chiavi di base di `game`): modalità, giocatori, volumi,
bianco, zoom, punteggi, colore di accento, mouse e la sezione `next` sono solo della versione Rust.
Il MiSTer ha le opzioni nell'OSD, il Commodore 64 nel menu; nel browser le scelte del menu restano
nel `localStorage`.

## padd_config.json

`padd_config.json` viene letto all'avvio: la versione Rust lo cerca accanto all'eseguibile, poi
nella cartella corrente e in quella superiore; la versione Python nella cartella che contiene
`python/`. Con `--config FILE` se ne usa un altro. Le chiavi mancanti prendono il valore di default,
quelle sconosciute vengono ignorate (la versione Python le segnala nel log); la versione Rust
aggiunge al file le chiavi nuove, con i loro default.
Dimensioni e velocità sono espresse per la risoluzione di riferimento 800×480 e scalate su
`resolution`. Dal menu si cambiano e si salvano modalità e giocatori, schermo intero, filtro CRT,
difficoltà, volumi della musica e degli effetti, suoni dell'attract, luminosità del bianco, zoom,
punteggi e mouse come spinner.

Con `resolution.width = 0` (default) il campo prende le proporzioni del monitor con l'altezza
indicata: 640×480 su 4:3, 853×480 su 16:9, 800×480 sul display del Pi, quindi niente bande nere.
Una larghezza esplicita (es. `640` per un cabinato 4:3) fissa il campo; se lo schermo ha
proporzioni diverse compaiono le bande nere (`game.keep_aspect`) invece della deformazione.

| chiave | default | |
|---|---|---|
| `game.fullscreen`, `crt_effects.enabled` | `false` | schermo intero (`F11`) e filtro CRT (`C`); il `padd_config.json` del pacchetto li accende |
| `game.free_play` | `true` | senza gettoni; con `false` serve un credito per partita (tasto `5`) |
| `game.points_to_win` | `11` | punti per vincere in due |
| `game.lives` | `3` | palle in singolo |
| `game.difficulty` | `1` | 0 EASY, 1 NORMAL, 2 HARD, 3 EXPERT |
| `game.game_type` | `"next"` | modalità scelta nel menu (**GAME TYPE**): `"classic"`, `"evo"` o `"next"` |
| `game.players` | `"challenge"` | giocatori scelti nel menu (**PLAYERS**): `"two"`, `"cpu"`, `"challenge"` o `"one"` |
| `game.self_test` | `true` | auto-test all'avvio |
| `game.attract_sound` | `true` | suoni e musica dell'attract, e musica del menu (gettone e Start si sentono sempre) |
| `game.music_volume` | `100` | volume di tutte le musiche in percento, da 0 (nessuna musica) a 100 (menu **MUSIC VOLUME**, a passi del 10%). Prende il posto di `game.music` (e prima di `game.sid_sound` e `game.match_music`): se una di loro era `false` parte da 0 |
| `game.effects_volume` | `100` | volume degli effetti e delle voci in percento (menu **EFFECTS VOLUME**) |
| `game.white_level` | `100` | luminosità del bianco in percento (menu: 100, 87, 75, 62), tutta l'immagine in proporzione |
| `game.zoom` | `100` | spessore della pallina e delle racchette in percento, urti compresi (menu **ZOOM**: 100, 125, 150, 175, 200), per gli schermi piccoli; altezza delle racchette e campo restano gli stessi |
| `game.scores_upright` | `true` | punteggi dritti in alto (menu **SCORES: UPRIGHT**); con `false` rivolti ai giocatori seduti ai lati di un tavolo (**FACING**) |
| `colors.accent` | `[255, 210, 37]` | colore di accento (il giallo dell'attract): la voce scelta del menu; solo in NEXT: titolo del menu, titolo e cursore della scelta, scritta del bonus attivato, freccetta della riserva, portali di TELEPORT, volante e segni del limite di STEER, capsula e palla del SUPER, capsula del BULLET e bordo della racchetta di chi lo ha armato |
| `mouse.spinner` | `false` | il mouse come spinner del giocatore di sinistra (menu **MOUSE SPINNER**); con gli encoder del cabinato non conta |
| `mouse.travel_pixels` | `1000` | pixel di movimento del mouse per portare la racchetta da un bordo all'altro |
| `game.vsync`, `game.keep_aspect`, `game.serve_delay` | | sincronia verticale, bande nere, attesa alla battuta |
| `crt_effects.resolution_scale` | `2.5` | versione Rust: righe emulate dal filtro CRT: 3 × altezza del campo / valore (576 a 480 righe). Il default di prima, `1.0`, passa da solo a `2.5` |

Le altre sezioni (`ball`, `paddle`, `boost`, `encoder`, `crt_effects`, `colors`) sono nel
`padd_config.json` del pacchetto, che in qualche punto si scosta dai default del codice (filtro CRT
acceso, curvatura dello schermo, grigio chiaro).

## Difficoltà

La difficoltà regola quanto accelera la palla a ogni colpo e la sua velocità massima (pixel per
frame a 800×480); in singolo accelerano solo i colpi del giocatore, non il muro.

| difficoltà | singolo | in due | NEXT |
|---|---|---|---|
| EASY | +5% / 8 | +15% / 6 | +6% / 7 |
| NORMAL | +10% / 10 | +25% / 8 | +10% / 10 |
| HARD | +15% / 12 | +25% / 10 | +14% / 11 |
| EXPERT | +25% / 15 | +30% / 12 | +18% / 13 |

## Parametri di NEXT

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
| `hitstop_seconds` | `0.1667` (1/6 s) | fermo del gioco del SUPER con hit-stop |
| `super_meter_max`, `super_cost` | `64`, `32` | barra delle mosse speciali (sempre accese; la vecchia chiave `super_moves` sparisce dal file) e costo di una mossa |
| `super_gain_hit`, `super_gain_dash`, `super_gain_conceded` | `2`, `4`, `8` | barra guadagnata con un colpo, con lo scatto che intercetta, con un punto subito |
| `super_straight_multiplier` | `2` | spinta del tiro con STRAIGHT SHOT MAX (1 + 1/2ⁿ: 2, 1,5, 1,25…); la mossa normale ha la metà dell'aggiunta |
| `super_min_speed_straight`, `super_min_speed_rise` | `0.5`, `0.375` | velocità orizzontale minima della palla al colpo di STRAIGHT SHOT e di RISING STRIKE, in frazione della massima della difficoltà: una mossa a inizio scambio non parte più lenta |

I tipi di racchetta sono nella sezione `next.paddles`.

## Cabinato Raspberry Pi

Sul cabinato gira la versione Python oppure quella Rust (con NEXT, la CPU e gli encoder letti
direttamente dai GPIO, anche sul Pi 5), ciascuna con il suo servizio systemd. Installazione e
schema di collegamento di encoder e pulsanti: [deploy/raspberry/README.md](../../deploy/raspberry/README.md).
