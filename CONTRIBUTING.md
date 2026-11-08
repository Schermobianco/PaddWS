**Italiano** · [English](CONTRIBUTING.en.md)

# Contribuire a PADD WS

PADD WS è un progetto personale, aperto a chi vuole dare una mano: segnalare un errore, provare il
gioco su hardware vero, correggere il codice, portarlo su un'altra macchina. Alcune regole sono più
rigide del solito, perché la stessa partita gira identica in cinque versioni: qui sotto c'è come si
lavora.

## Lingua

- Issue, discussioni e pull request: in italiano o in inglese.
- Commenti e docstring sono in italiano, come il resto del codice. Una PR con i commenti in inglese
  va bene lo stesso: si traducono durante la revisione.
- Le pagine principali della documentazione hanno la versione italiana e quella inglese
  (`README.md` e `README.en.md`, `docs/` e `docs/en/`, `hardware/deck`). Chi ne cambia una aggiorna
  anche l'altra; se non può, lo scrive nella PR.

## Prima di cominciare

- Per un errore o un comportamento strano si apre una [issue](https://github.com/Schermobianco/PaddWS/issues/new/choose)
  con il modulo apposito: versione, piattaforma, e i passi per riprodurlo.
- Per una funzione nuova o una modifica alle regole di gioco conviene aprire prima una issue o una
  discussione: le regole valgono per cinque versioni insieme (vedi sotto), quindi anche un piccolo
  cambiamento ha un costo.
- La versione Python (`python/`) è congelata: si accettano solo correzioni.
- Le domande e le idee vanno nelle [Discussions](https://github.com/Schermobianco/PaddWS/discussions).

## La regola principale: una partita sola

La logica di riferimento è il core Rust (`rust/core`): deterministico, in virgola fissa Q16.16, solo
interi. Il core MiSTer e la versione C64 ne riproducono lo stato tick per tick, e i test lo
verificano bit per bit. Una modifica al gameplay quindi tocca tre implementazioni:

1. `rust/core` (Rust),
2. `mister/` (firmware RISC-V e RTL Verilog, controllati con le tracce di `rust/trace`),
3. `c64/` (assembly 6502, controllato con l'emulatore di `rust/c64`).

Se si conosce solo una delle tre, la PR si apre lo stesso, dicendolo: il resto si porta in
revisione. Una PR che cambia `rust/core` senza gli altri due non si può unire così com'è, perché
fa fallire le verifiche delle tracce.

Alcuni file sono generati e non si modificano a mano: `mister/rtl/gen/*.vh` (da `tools/gen_*`),
`c64/gen/` (da `tools/gen_c64_assets.py`), le bitmap e i tempi dell'attract in `assets/attract/` (da
`tools/gen_attract_assets.py`). Si cambia il generatore e si rigenerano.

Sul C64 un frame non può superare 18.000 cicli (`paddws-c64 frames` lo controlla) e la pagina zero è
piena: vedi [c64/README.md](c64/README.md).

## Compilare e verificare

Le istruzioni complete sono in [docs/sviluppo.md](docs/sviluppo.md). In breve, da `rust/`:

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy --release -p paddws --target wasm32-unknown-unknown -- -D warnings
```

E poi, secondo la parte toccata:

- Python: `pytest -q python`;
- MiSTer: `mister/sim/run.sh` (o `run.ps1` su Windows), che confronta il core con le tracce Rust;
- C64: si assembla con cc65 (`c64/build.ps1`) e si prova contro il core con `cargo run --release -p
  paddws-c64 -- game` (e `params --check`, `math`, `sid`, `ui`, `frames`).

Gli script per Windows cercano gli strumenti portable in `C:\DEV\@Compiler`, oppure nella cartella
indicata dalla variabile `PADDWS_COMPILERS`. Le GitHub Action partono solo a mano: sulle PR le avvia
il maintainer. Non serve far girare tutto; basta dire nella PR che cosa si è provato.

## Pull request

- Una PR per argomento, piccola quando si può.
- Il titolo segue lo stile dei commit: l'area, poi che cosa cambia, ad esempio
  `C64: coda della palla, scritte centrate`.
- Le novità visibili a chi gioca vanno in [CHANGELOG.md](CHANGELOG.md), sotto **Non rilasciato**
  (si possono scrivere in inglese: si traducono in revisione).
- Se cambia qualcosa sullo schermo, una schermata aiuta molto.

## Licenza

Contribuendo si accetta che il proprio codice sia distribuito con la licenza della parte toccata:
GPL v3 o successiva per il gioco (Rust, C64, Python, strumenti), GPL v2 o successiva per il core
MiSTer. Vedi [LICENSE](LICENSE) e [THIRD_PARTY.md](THIRD_PARTY.md).

## Comportamento e sicurezza

Chi partecipa segue il [codice di condotta](CODE_OF_CONDUCT.md). I problemi di sicurezza non vanno
nelle issue pubbliche: vedi [SECURITY.md](SECURITY.md).
