[<img src="../docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

# PADD WS – Commodore 64 version

PADD WS for the PAL C64, on an EasyFlash cartridge. It plays the same match as the Rust core
([`rust/core`](../rust/core)) bit for bit: a 320×200 field, one tick per frame at 50 Hz, 32-bit
Q16.16 arithmetic in 6502 identical to `fixed.rs`, and the same parameters as the other versions
(`Tuning::c64()`). It has Classic, EVO, NEXT with the special moves, single player, the CPU,
CHALLENGE with the high score table saved in flash, the attract mode and the SID music.

PAL only (no NTSC for now). So far it has been tested in VICE, not yet on a real C64.

## Running it

`paddws.crt` is in the release (`paddws-X.Y.Z-c64.zip`), or in `c64\build` after a build. Mount it
in VICE or on the C64 Ultimate, or write it to an EasyFlash with EasyProg; it starts at power-on.
For the high scores to stick, the `.crt` must be writable; in VICE:

```
x64sc -easyflashcrtwrite -cartcrt paddws.crt
```

## Controls

- Joysticks in port 2 (left player) and port 1 (right), or a pair of paddles in port 1.
- Up and down move the paddle (double tap: fast). Towards the opponent is the forward dash (and
  the BLASTER shot), the opposite direction brings the paddle back.
- Fire: in NEXT it uses the selected power-up, which changes by itself every second; in EVO it
  dashes.
- NEXT special moves, with forward towards the opponent: ↓ ↘ → + fire STRAIGHT SHOT,
  → ↓ ↘ + fire RISING STRIKE. Paddles have none: the button dashes, and power-ups are selected
  and used with `F` / `C` (left) and `.` / `-` (right).
- Keyboard: **5** coin, fire, **RETURN**, **SPACE** or **1** Start, **RUN/STOP** pause (back to the
  attract mode from the menu), **Q** back to the menu.

The menu (joystick or cursor keys) has GAME, PLAYERS, DIFFICULTY, CONTROL, FREE PLAY, ATTRACT
SOUND, VOLUME and BORDER. The rules are in [docs/en/how-to-play.md](../docs/en/how-to-play.md).

## Building

You need cc65 (ca65 and ld65) in `C:\DEV\@Compiler\cc65` and Python (the one in `.venv`, if
present) for `tools/make_crt.py`. VICE, in `C:\DEV\@Compiler\vice`, is only needed to try it out.
`PADDWS_COMPILERS` points to a different folder instead of `C:\DEV\@Compiler`.

```powershell
.\c64\build.ps1                 # c64\build\paddws.crt
.\c64\shot.ps1 boot.png         # runs the cartridge in VICE without a window and saves a screenshot
```

On Linux: `sh c64/build.sh` (ca65, ld65 and python3 on the PATH).

Besides the cartridge, `c64\build` holds `paddws.prg` with its labels (`paddws.lbl`) and memory
map (`paddws.map`), the CHALLENGE ending (`paddws.prg.end`) and the voice files `voice0-6.prg`.
The test bench needs them: the `.prg` does not start on its own, it only runs from the cartridge.

The files in `c64/gen/` are generated and committed: `tools/gen_c64_assets.py` makes the graphics,
music and voices, `paddws-c64 params` makes `params.inc`. Do not edit them by hand.

For screenshots there are builds that go straight into a match:

```powershell
.\c64\build.ps1 -Name autostart -Define AUTOSTART     # EVO against the CPU; with AUTONEXT NEXT, with AUTOCHALLENGE CHALLENGE
.\c64\build.ps1 -Name autoend -Define ENDTEST         # the CHALLENGE ending
.\c64\shot.ps1 out.png -Prg autostart                # screenshot after -Cycles cycles (15 million by default)
```

`shot.ps1` also takes `-Sid 8580`, `-Wav out.wav` (records the sound, at normal speed) and
`-Write` (the saved high scores stay in the `.crt`).

## Testing

The test bench (`rust/c64`, program `paddws-c64`) loads `paddws.prg`, its labels and the cartridge
into a 6502 emulator, calls routines by label, compares the results with the Rust core and counts
cycles. It emulates only what the program needs from the C64: the RAM under I/O, the raster line,
CIA2 timer A with its NMI, and the EasyFlash with its flash commands. Build the cartridge first.

```powershell
. .\tools\rust-env.ps1; cd rust
cargo run --release -p paddws-c64 -- params --check   # c64\gen\params.inc matches the core (without --check it rewrites it)
cargo run --release -p paddws-c64 -- math             # arithmetic and random generator against fixed.rs and rng.rs
cargo run --release -p paddws-c64 -- game             # whole matches, state compared with the core on every tick
cargo run --release -p paddws-c64 -- sid              # SID player against the Verilog one and the Rust one
cargo run --release -p paddws-c64 -- ui               # scenes and menu, CHALLENGE voices, high scores in flash
cargo run --release -p paddws-c64 -- frames           # cycles of every frame (attract, demo, matches, ending)
```

These are the same steps as the `C64` GitHub Action. Also: `ending` plays only the CHALLENGE
ending, `profile` gives cycles per routine, `--build DIR` uses another build folder, and
`game --ticks N` changes the length of the matches (5 minutes by default).

## Sources

- `src/main.s` — entry point: a single module that includes the other files.
- `src/game.s`, `src/math.s` — the match (`Match` in `game.rs`) and the Q16.16 arithmetic with the
  random generator.
- `src/next.s`, `src/supers.s`, `src/pick.s` — NEXT, the special moves, the choices before the
  match and the HOW TO PLAY screen.
- `src/cpu.s` — the CPU player (`cpu.rs`).
- `src/challenge.s`, `src/ending.s` — CHALLENGE with the high score table, and the ending.
- `src/play.s` — frame loop, scenes, menu, coins.
- `src/attract.s`, `src/video.s`, `src/input.s` — attract mode, graphics, controls.
- `src/sid.s` — the SID player, translated from `mister/rtl/pong_sid.v`.
- `src/voice.s`, `src/voice.inc` — the CHALLENGE voice files (assembled separately, one per
  opponent).
- `src/crt.s`, `src/unpack.s`, `src/ef.s`, `src/ef.inc` — cartridge boot and flash access.
- `paddws.cfg` — the ld65 memory map, with a comment on what uses what.
- `test/sid_reference.txt` — the SID writes of the Verilog player, for `paddws-c64 sid`.

## Limits to know about

- **Same logic as the core.** Every change to `rust/core` has to be brought over here too (and to
  the MiSTer): `paddws-c64 game` checks it tick by tick.
- **Memory is almost gone.** The zero page is full and the program has only a few bytes left: new
  code usually goes into the cartridge and is copied to RAM when needed (like the special moves,
  the high score table and the ending). Free space is in `c64\build\paddws.map`.
- **Shared temporaries.** `m_t` and `ptr` do not keep a value across a `jsr`.
- **18,000 cycles per frame.** `paddws-c64 frames` fails if a frame goes over. Its raster model (58
  cycles per line) is approximate: with frames close to the limit, check in VICE too. Long work is
  split over several frames, or waits for the next frame by looking at the raster.
- **Charset and sprites are used up.** All 256 characters are taken (a new character replaces one
  where the other is not needed, and `tools/gen_c64_assets.py` checks it), and so are the 8
  sprites.
- **BASIC and KERNAL are off** (`$01 = $35`): data and variables live under their ROMs, and the RAM
  under I/O is read and written with `$01 = $34`.
- **Border and background** (`$D020`, `$D021`) are written only when the colour changes: every
  write while the colour is on screen leaves a "grey dot" on newer VIC-II chips.
- **ca65:** inside a `.proc`, constants defined outside are written `::NAME` in directives such as
  `.repeat`; branches beyond ±128 bytes use `jne`, `jeq`, `jcs`, `jcc`.
- **Flash.** The high scores are written with the commands of the EasyFlash's Am29F040, without
  EAPI: an EasyFlash 3 or a cartridge with a different flash chip would need EAPI. If the flash
  cannot be written, the program notices and does not try again until power-off.
