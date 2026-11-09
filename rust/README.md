[<img src="../docs/flags/it.svg" alt="" height="14"> **Italiano**](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> English](README.en.md)

# PADD WS – versione Rust

Un unico eseguibile, con font, suoni, musica e grafica dell'attract dentro, per Windows, Linux
x86_64, Linux ARM64 e ARM a 32 bit (Raspberry Pi); lo stesso codice in WebAssembly è la versione
web. Regole e comandi completi in [Come si gioca](../docs/it/come-si-gioca.md).

## Avvio e opzioni

```
paddws [--config FILE] [--fullscreen | --windowed] [--crt | --no-crt] [--width N] [--height N] [--version]
```

`--width 0` prende le proporzioni del monitor, `--width 320 --height 240` è la risoluzione del
core MiSTer. Per le prove: `--screenshot-tour DIR` (una schermata per scena), `--paddle-gallery DIR`
(un'immagine per tipo di racchetta), `--bench SECONDI` (gioca da solo e stampa i tempi dei frame).

La configurazione, `padd_config.json`, si cerca accanto all'eseguibile, poi nella cartella corrente
e in quella superiore (comodo con `cargo run` dentro `rust/`); il menu ci salva le sue scelte, nel
browser restano nel `localStorage`. Chiavi e valori in [Configurazione](../docs/it/configurazione.md).

## Comandi

Sinistra `W` / `S` e `D` per lo scatto, destra `↑` / `↓` e `←`. `5` gettone, `Invio` Start, `P`
pausa, `Esc` menu e uscita, `F11` schermo intero, `C` filtro CRT. Il mouse può fare da manopola
del giocatore di sinistra (**MOUSE SPINNER: ON** nel menu).

## Gamepad e stick arcade

Su PC e Raspberry Pi con [gilrs](https://crates.io/crates/gilrs), nel browser con la Gamepad API
(`web/gamepad.js`). Il primo gamepad collegato è del giocatore di sinistra, il secondo di quello di
destra; chi gioca da solo con un gamepad lo usa da qualunque lato. La tastiera resta attiva.

| comando | in partita | nei menu |
|---|---|---|
| levetta o croce | muove la racchetta (doppio tocco = rapido) | direzioni |
| **A** | scatto in avanti e mosse speciali | conferma |
| **B** | seleziona il bonus (NEXT) | indietro |
| **C** (X o Y) | usa il bonus (NEXT) | |
| **Start** | pausa (poi A riprende, B torna al menu) | Start |
| **Select** | gettone | gettone |

- La levetta analogica diventa una direzione a 8 vie, con il 35% di zona morta: le mezzelune delle
  mosse speciali (↓ ↘ → + **A** STRAIGHT SHOT, → ↓ ↘ + **A** RISING STRIKE, → verso l'avversario)
  si fanno come sullo stick arcade. Stick arcade e schede encoder con la sola croce digitale vanno
  bene così.
- I pulsanti si riconoscono per nome con la mappatura SDL di gilrs; le schede senza mappatura per
  numero: 1 A, 2 B, 3 C, 9 Select, 10 Start.
- Linux e Raspberry Pi: serve `libudev` e l'accesso a `/dev/input/event*` (gruppo `input`).
- Nel browser il gamepad compare dopo la pressione di un suo pulsante, e solo su https o `localhost`.

## Il workspace

```
core/       paddws-core: logica no_std, solo interi (Q16.16), tick a 240 Hz; il modello di riferimento
game/       paddws: il gioco, con macroquad (web/ è la sua pagina per il browser)
sid/        paddws-sid: SID e player della musica in tempo reale; strumento render | compare | bench
trace/      paddws-trace: parametri e tracce per il MiSTer, statistiche tra CPU e umani simulati
c64/        paddws-c64: banco di prova del C64, esegue il 6502 e lo confronta con il core
mister-fw/  firmware RISC-V del core MiSTer (tools/gen_mister_fw.py) e il suo banco di prova paddws-fw-sim
vendor/     copie nostre di miniquad e quad-snd, fuori dal workspace ([patch.crates-io])
```

## Compilare

Su Windows con la toolchain portable in `C:\DEV\@Compiler`:

```powershell
. .\tools\rust-env.ps1          # Rust e MinGW nella sola sessione corrente
cd rust
cargo run --release             # oppure cargo build --release: target\release\paddws.exe
```

Su Debian, Ubuntu e Raspberry Pi OS:

```sh
sudo apt install libx11-dev libxi-dev libgl1-mesa-dev libasound2-dev libudev-dev
cd rust && cargo run --release
```

Gli eseguibili delle release li costruisce la VM [forge](../tools/forge/README.md) (`build_onforge.bat`).

## Versione web

```powershell
.\tools\build-web.ps1           # in rust\target\web
.\tools\build-web.ps1 -Serve    # e un server su http://localhost:8080
```

La prima volta: `rustup target add wasm32-unknown-unknown`. Va aperta da un server web, non con un
doppio clic su `index.html` (vedi `web/LEGGIMI.txt`).

## Controlli prima di un push

Le GitHub Action partono solo a mano: i controlli si fanno in locale.

```powershell
. .\tools\rust-env.ps1; cd rust
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy --release -p paddws --target wasm32-unknown-unknown -- -D warnings
cd ..; .venv\Scripts\python -m pytest -q python
.\mister\sim\run.ps1            # tracce MiSTer contro il core
.\c64\build.ps1                 # poi in rust: paddws-c64 params --check, math, game, sid, ui, frames
```

`cmd /c check_onforge.bat` fa gli stessi controlli su forge con i file come sono ora, senza commit.
Per la diagnostica: `PADDWS_NO_GPU_SYNC=1` toglie l'attesa della GPU dopo ogni frame,
`PADDWS_STARTUP_TIMES` stampa i tempi dell'avvio, `PADDWS_MOUSE_TOUCH` fa del mouse un dito.
