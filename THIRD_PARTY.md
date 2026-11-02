# Licenze e componenti di terzi

Il codice di PADD WS (Python, Rust, C64, strumenti in `tools/`) è distribuito con licenza GNU GPL
v3 o successiva: vedi [LICENSE](LICENSE). Fanno eccezione le parti elencate qui sotto, ognuna con la
sua licenza. Tutte le dipendenze sono compatibili con la GPL v3 (la libreria `hound`, solo
Apache-2.0, lo è con la v3 e non con la v2).

## Core MiSTer (`mister/`)

| componente | autori | licenza |
|---|---|---|
| framework `mister/sys/` ([Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer)) | Sorgelig e altri | GNU GPL v2 |
| core PADD WS (`mister/PaddWS.sv`, `mister/rtl/`) | Schermobianco | GNU GPL v2 o successiva, perché unito al framework |
| processore RISC-V VexRiscv (`mister/rtl/vexriscv/VexRiscv.v`), generato da [SpinalHDL/VexRiscv](https://github.com/SpinalHDL/VexRiscv), variante *standard* di [pythondata-cpu-vexriscv](https://github.com/litex-hub/pythondata-cpu-vexriscv) | Spinal HDL contributors | MIT ([testo](mister/rtl/vexriscv/LICENSE), provenienza in [README](mister/rtl/vexriscv/README.md)) |
| emulazione del SID (`mister/rtl/sid/`) dal [core C64 del MiSTer](https://github.com/MiSTer-devel/C64_MiSTer) | Dag Lem ([reDIP-SID](https://github.com/daglem/reDIP-SID)), Alexey Melnikov | `sid_dac.sv` e `sid_filter.sv`: CERN-OHL-S v2 ([testo](mister/rtl/sid/LICENSE-CERN-OHL-S-2.0.txt)); gli altri file sono senza intestazione, come nel core di origine |

Il testo della GPL v2 è in [mister/LICENSE](mister/LICENSE). Le modifiche fatte ai file del SID
sono descritte in [mister/rtl/sid/README.md](mister/rtl/sid/README.md). Chi riceve il core
(`PaddWS_MiSTer_*.zip`) ha diritto ai sorgenti corrispondenti, come richiesto da GPL v2 e
CERN-OHL-S v2.

## Font (`assets/fonts/`)

| font | autore | licenza |
|---|---|---|
| `munro.ttf` ([Munro](https://www.fontsquirrel.com/fonts/munro)) | Ed Merritt, [Ten by Twenty](http://www.tenbytwenty.com/) | SIL Open Font License 1.1 ([testo](assets/fonts/OFL-Munro.txt)) |
| `pong-score.ttf` ([Pong Score](https://fontstruct.com/fontstructions/show/1158273/pong_score)) | pwnzor.ak, FontStruct | CC0 1.0 (pubblico dominio) |

I due font sono anche nelle ROM del core MiSTer, come bitmap generate dai file TTF.

## Dipendenze

- Versione Rust: crate da crates.io (macroquad, fontdue, serde, serde_json, gpiocdev, gilrs,
  embed-resource, windows-sys e le loro dipendenze), tutte con licenze permissive (MIT,
  Apache-2.0, Zlib, BSD-3-Clause, Unicode-3.0). L'elenco completo è in `rust/Cargo.lock`.
- [gilrs](https://gitlab.com/gilrs-project/gilrs) (i gamepad su Windows, Linux e Raspberry Pi,
  MIT o Apache-2.0) include le mappature dei controller di
  [SDL_GameControllerDB](https://github.com/mdqinc/SDL_GameControllerDB) (zlib); su Linux si
  collega a `libudev` del sistema (LGPL-2.1, libreria dinamica).
- quad-snd 0.2.8 (l'audio di macroquad, di Fedor Logachev, MIT o Apache-2.0) è copiata in
  `rust/vendor/quad-snd/` con una piccola modifica al mixer per la musica del SID
  ([testo MIT](rust/vendor/quad-snd/LICENSE-MIT), modifiche in testa al suo `Cargo.toml`).
- Versione web: il JavaScript di miniquad e quad-snd, MIT o Apache-2.0; i plugin di `rust/web/`
  (`sid_audio.js`, `gamepad.js`, `storage.js`) sono di PADD WS (GPL v3 o successiva).
- Versione Python: [Arcade](https://github.com/pythonarcade/arcade) (MIT) e, sul Raspberry Pi,
  [pigpio](https://github.com/joan2937/pigpio) (Unlicense).
