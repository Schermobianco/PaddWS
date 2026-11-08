# Sviluppo

[← README](../README.md) · [<img src="flags/it.svg" alt="" height="14"> **Italiano**](sviluppo.md) · [<img src="flags/gb.svg" alt="" height="14"> English](en/development.md)

Per chi vuole contribuire: vedi anche [CONTRIBUTING.md](../CONTRIBUTING.md).

## Un solo gioco, cinque versioni

La logica di gioco di riferimento è il **core Rust** (`rust/core`): deterministico, in virgola fissa
Q16.16, solo interi e nessuna divisione. Il **core MiSTer** ne riproduce lo stato tick per tick,
verificato bit per bit con vettori di test; lo stesso fa la **versione C64**, eseguita in un
emulatore 6502 e confrontata con il core a ogni tick. La versione web è la versione Rust compilata
in WebAssembly. La versione Python è la prima ed è congelata: solo correzioni.

## Struttura

```
rust/            versione Rust: core deterministico (core), gioco anche web (game, web), SID (sid),
                 tracce (trace) e firmware RISC-V (mister-fw) del MiSTer, banco di prova del C64 (c64),
                 copie modificate di miniquad e quad-snd (vendor)
mister/          core MiSTer: RTL Verilog, simulazione, progetto Quartus (framework Template_MiSTer)
c64/             versione Commodore 64 in 6502 (anteprima), verificata contro il core Rust
python/          versione Python
  paddws/          il pacchetto
    core/            logica di gioco pura (match, parametri, doppio tocco), senza dipendenze grafiche
    app.py           finestra: scaling letterbox, audio, ritmo dei frame
    attract.py       sequenza attract
    scenes.py        attract, menu, partita
    config.py        configurazione tipizzata, caricamento e salvataggio JSON
    crt.py           filtro CRT
    hardware.py      encoder (pigpio), rilevamento Raspberry Pi, spegnimento
  tests/           test pytest
assets/          font, immagini, suoni, icone, bitmap e tempi dell'attract (comuni a tutte le versioni)
deploy/raspberry servizio systemd e configurazione di boot; immagine della SD del Deck (deck)
hardware/        console da stampare in 3D: il Deck (modello SolidCraft e STEP, progetto Bambu Studio)
tools/           rilascio, ambiente Rust portable, generatori di icone, attract, suoni e ROM MiSTer,
                 musiche del SID (gen_sid_music.py, suonate dal SID Rust di rust/sid), scritte di
                 CHALLENGE, VM forge per le release
docs/            documentazione, schermate e icone
```

Ogni versione ha il suo README: [Rust](../rust/README.md), [MiSTer](../mister/README.md),
[Commodore 64](../c64/README.md), [Raspberry Pi](../deploy/raspberry/README.md).

## Avvio dai sorgenti

Versione Rust (su Windows con la toolchain portable; Linux e dettagli in
[rust/README.md](../rust/README.md)):

```powershell
. .\tools\rust-env.ps1
cd rust
cargo run --release
```

Versione Python:

```sh
python -m venv .venv
.venv\Scripts\activate            # Linux/macOS: source .venv/bin/activate
pip install -e "./python[dev]"
python -m paddws                  # oppure: python python/main.py, oppure: paddws
```

Opzioni: `--config FILE`, `--fullscreen` / `--windowed`, `--crt` / `--no-crt`, `--debug`.

## Versione web

```powershell
.\tools\build-web.ps1          # paddws.wasm, pagina e JavaScript in rust\target\web
.\tools\build-web.ps1 -Serve   # e un server su http://localhost:8080 (dal telefono: http://<PC>:8080)
```

La prima volta serve il target WebAssembly: `rustup target add wasm32-unknown-unknown` (dopo
`. .\tools\rust-env.ps1`). La pagina è in [`rust/web/`](../rust/web/): `index.html` e i plugin
JavaScript del gioco (musica del SID, gamepad, `localStorage`, schermo intero sul touch); il
JavaScript di miniquad e quad-snd viene dalle loro copie in `rust/vendor`. Dal telefono sulla
stessa rete si prova con `-Serve` (il firewall di Windows deve lasciar passare la porta 8080).

Online è su GitHub Pages, <https://schermobianco.github.io/PaddWS/>, dal ramo `gh-pages`:
`build_onforge.bat -Publish` ci mette, dopo la release, il contenuto dello zip web
([`tools/publish-pages.ps1`](../tools/publish-pages.ps1), lanciabile anche da solo).

## Test e verifiche

```sh
pytest -q python                        # versione Python
cd rust && cargo test                   # core e gioco Rust
.\mister\sim\run.ps1                    # logica HDL contro il core Rust (sim/run.sh su Linux)
.\c64\build.ps1                         # versione C64 (c64/build.sh su Linux), poi:
cd rust && cargo run --release -p paddws-c64 -- game   # contro il core Rust
```

Le GitHub Action `Python`, `Rust`, `MiSTer` e `C64` eseguono gli stessi controlli; la `MiSTer`
sintetizza anche il core con Quartus 17.0.2, la `C64` assembla il programma con cc65 e lo prova nel
banco di prova (vedi [c64/README.md](../c64/README.md)). Partono solo a mano (*Run workflow*, `gh
workflow run` o `build_ongithub.bat`). Gli stessi controlli girano in locale con
`build_onforge.bat -CheckOnly`, oppure, sui file non ancora committati, con `check_onforge.bat`.

## Fluidità e latenza (versione Rust)

- Fisica a passo fisso di 1/240 s con interpolazione del rendering: movimento identico a
  60, 120, 144 o 165 Hz e input applicato entro ~4 ms.
- Un solo aggiornamento per frame presentato, cadenzato dal vsync; se il driver ignora il
  vsync il gioco lo rileva e si limita alla frequenza del monitor.
- Sincronizzazione con la GPU dopo ogni frame: niente frame accodati dal driver, ~1 frame di
  latenza (disattivata da sola se con il compositor in uso farebbe perdere frame).
- Filtro CRT calcolato al massimo a 720p e poi ingrandito: a 1440p/4K resta nel budget del frame.
- Audio "pre-riscaldato" all'avvio (ogni suono suonato una volta a volume zero): nessuno scatto
  alla prima occorrenza.
- Collisioni continue: la palla non può attraversare la racchetta a nessuna velocità.

## Versioni e release

Numerazione [Semantic Versioning](https://semver.org/lang/it/), una sola per tutto il progetto:
Python (`python/paddws/__init__.py`), Rust (`rust/Cargo.toml`), core MiSTer e versione C64 escono insieme
con lo stesso numero (un test controlla che quelli di Python e Rust coincidano). La versione
compare nel menu, nel log all'avvio e con `--version`. Le modifiche sono descritte in
[CHANGELOG.md](../CHANGELOG.md).

Per rilasciare: aggiungere le voci sotto **Non rilasciato** nel changelog, poi

```sh
python tools/release.py minor      # oppure patch / major / X.Y.Z / X.Y.Z-beta.N, --dry-run per provare
git push --follow-tags
```

Lo script aggiorna la versione di Python e Rust (con `Cargo.lock`) e il changelog (le anteprime `-alpha.N` e
`-beta.N` lasciano le voci in **Non rilasciato**), crea il commit e il tag `vX.Y.Z`. I pacchetti
si costruiscono poi in uno di questi due modi:

- `build_onforge.bat` fa i controlli e i pacchetti in locale, in `dist\`, sulla macchina virtuale *forge*
  ([tools/forge](../tools/forge/README.md)): la accende e la spegne da solo, e sul PC bastano git
  e ssh. `build_onforge.bat -Publish` pubblica poi la release del tag con `gh` e la versione web su GitHub
  Pages. Le note della release vengono dal changelog (`tools/release_notes.py X.Y.Z`): per le
  anteprime solo le voci nuove o cambiate dal tag precedente.
- `build_ongithub.bat VERSIONE` fa tutto online: controlli, `tools/release.py`, push, avvia le
  GitHub Action sul tag e le segue fino alla release (core MiSTer compreso); senza versione rilancia
  le Action fallite del tag già presente sul commit. Alla fine mette le note e la versione web su
  GitHub Pages; manca solo l'immagine della SD del Deck, che fa solo *forge*.
