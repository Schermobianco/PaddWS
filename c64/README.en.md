[<img src="../docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

# PADD WS – Commodore 64 version

PADD WS for the PAL and NTSC C64, on an EasyFlash cartridge. It plays the same match as the Rust core
([`rust/core`](../rust/core)) bit for bit: a 320×200 field, one tick per frame (50 Hz, 60 on NTSC), 32-bit
Q16.16 arithmetic in 6502 identical to `fixed.rs`, and the same parameters as the other versions
(`Tuning::c64()`). It has Classic, EVO, NEXT with the special moves and the ladder (challengers,
WINS, training, high scores and unlocks saved in flash), the secret boss OMEGA, the jukebox,
single player, the CPU, the attract mode (without a demo) and the SID music. The logo in the NEXT
menu is not there: MAIN MENU stays.

There are two cartridges, one for PAL and one for NTSC (with the core parameters at 60 Hz). The
NTSC one has only been tested in VICE so far.

## Running it

`paddws.crt` (PAL) and `paddws-ntsc.crt` are in the release (`paddws-X.Y.Z-c64.zip`); after a
build they are `c64\build\paddws.crt` and `c64\build\ntsc\paddws.crt`. Mount it
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

The menu (joystick or cursor keys) has GAME, PLAYERS (only in CLASSIC and EVO; in NEXT, once
unlocked, OPPONENT for training), DIFFICULTY, CONTROL, FREE PLAY, ATTRACT SOUND, VOLUME (voices
included) and BORDER, plus JUKEBOX once unlocked. The rules are in [docs/en/how-to-play.md](../docs/en/how-to-play.md).

## Building

You need cc65 (ca65 and ld65) in `C:\DEV\@Compiler\cc65` and Python (the one in `.venv`, if
present) for `tools/make_crt.py`. VICE, in `C:\DEV\@Compiler\vice`, is only needed to try it out.
`PADDWS_COMPILERS` points to a different folder instead of `C:\DEV\@Compiler`.

```powershell
.\c64\build.ps1                 # c64\build\paddws.crt
.\c64\build.ps1 -Ntsc           # c64\build\ntsc\paddws.crt
.\c64\shot.ps1 boot.png         # runs the cartridge in VICE without a window and saves a screenshot
```

On Linux: `sh c64/build.sh` (`--ntsc` for the NTSC version; ca65, ld65 and python3 on the PATH).

Besides the cartridge, `c64\build` holds `paddws.prg` with its labels (`paddws.lbl`) and memory
map (`paddws.map`), the ladder ending (`paddws.prg.end`), the OMEGA bank (`paddws.prg.omega`) and the voice files
`voice0-7.prg` (7 is OMEGA).
The test bench needs them: the `.prg` does not start on its own, it only runs from the cartridge.

The files in `c64/gen/` are generated and committed: `tools/gen_c64_assets.py` makes the graphics,
music and voices, `paddws-c64 params` makes `params.inc`. Do not edit them by hand.

C64 images can be retouched by hand with `tools/c64_editor.html`, which opens in Edge or Chrome
with nothing to install: hires and multicolour bitmaps, characters, sprites, a cell grid with a
movable origin, invalid cells shown in red; *File → Importa e converti* turns any image (including
the reference image) into one of these modes, with a choice of dithering and colours.
It reads and writes the generators' palette PNGs
(index = C64 colour), such as the portraits in `assets/characters/portraits/c64` (hires) and `c64mc`
(multicolour, the ones the C64 uses: pick, VS and parade), and marks them:
`tools/gen_portraits.py` no longer overwrites those files (delete one to remake it from the
source). After retouching: `tools/gen_c64_portraits.py`, then the build. Inside VS Code (integrated
browser or Simple Browser) the page cannot open or save files: run
`.venv\Scripts\python tools\c64_editor.py` and open `http://127.0.0.1:8064/`, which works on the
repository's PNGs.

For screenshots there are builds that go straight into a match:

```powershell
.\c64\build.ps1 -Name autostart -Define AUTOSTART     # EVO against the CPU; with AUTONEXT NEXT, with AUTOCHALLENGE the ladder (TRAINTEST=n training)
.\c64\build.ps1 -Name autoend -Define ENDTEST         # the ladder ending (ENDOMEGA: after beating OMEGA)
.\c64\build.ps1 -Name warning -Define WARNTEST       # ladder on HARD, right after the GUARDIAN the alarm and OMEGA (OMFORM=n: from form n)
.\c64\build.ps1 -Name unlock -Define UNLOCKTEST,OMEGATEST  # training, OMEGA and jukebox unlocked
.\c64\build.ps1 -Name juke -Define JUKETEST,JUKETRACK=8 # straight to the jukebox, with track n (from 0)
.\c64\build.ps1 -Name menu3 -Define MENUTEST=3        # the menu with OPPONENT at 3 (UNLOCKTEST: training unlocked)
.\c64\build.ps1 -Name intro3 -Define INTROTEST=3      # the level 3 introduction (also CONTTEST: the continue)
.\c64\build.ps1 -Name ft -Define AUTOSTART,FRAMETEST  # frames over time, red digit bottom right (FRAMESTOP: stops at the first)
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
cargo run --release -p paddws-c64 -- ui               # scenes and menu, ladder voices, WINS, training, high scores and unlock in flash
cargo run --release -p paddws-c64 -- frames           # cycles of every frame (attract, matches, ending)
```

With `--ntsc` before the command (`paddws-c64 --ntsc frames`) the steps apply to the NTSC
cartridge, built first with `-Ntsc`. These are the same steps as the `C64` GitHub Action. Also: `ending` plays only the ladder
ending, `profile` gives cycles per routine, `--build DIR` uses another build folder, and
`game --ticks N` changes the length of the matches (5 minutes by default). To compare the test
bench cycles with VICE: `tools\c64_vice_frames.py` captures the frames of a test build and
`paddws-c64 --prg NAME vice FILE` runs them again; with `--frametest` the same tool counts in
VICE the frames that go over their time in a `FRAMETEST` build.

Before touching drawing or scene code, record a golden test, which `game` does not cover:
`PADDWS_C64_GOLDEN=record:FILE paddws-c64 frames` saves for every frame a fingerprint of what is
seen and heard (screen, colours, sprites, SID) with the raster frozen, and after the change
`PADDWS_C64_GOLDEN=check:FILE` reports the first frame that differs. With `PADDWS_C64_PICK_RAW=1`
almost every match is BLASTER (shots on screen).

## Sources

- `src/main.s` — entry point: a single module that includes the other files.
- `src/game.s`, `src/math.s` — the match (`Match` in `game.rs`) and the Q16.16 arithmetic with the
  random generator.
- `src/next.s`, `src/supers.s`, `src/pick.s` — NEXT, the special moves, the choices before the
  match and the HOW TO PLAY screen.
- `src/cpu.s` — the CPU player (`cpu.rs`).
- `src/omega.s`, `src/jukebox.s` — OMEGA in the match (net, form name, music in sections) and the
  jukebox, in the OMEGA bank of the cartridge.
- `src/challenge.s`, `src/intro.s`, `src/ending.s` — CHALLENGE with the high score table, the
  opponents' entrances in the introduction, and the ending.
- `src/play.s` — frame loop, scenes, menu, coins.
- `src/attract.s`, `src/video.s`, `src/input.s` — attract mode, graphics, controls.
- `src/sid.s` — the SID player, translated from `mister/rtl/pong_sid.v`.
- `src/voice.s`, `src/voice.inc` — the ladder voice files (assembled separately, one per
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
- **Frame time.** A PAL frame lasts 19,656 cycles, an NTSC one 17,095. In a match the goal is to
  stay within 90% (17,700 and 15,400); outside a match the whole frame is enough. `paddws-c64
  frames` counts real cycles from the line 250 interrupt, including those the VIC-II steals for
  character rows and sprites (a model calibrated against VICE), and fails if a frame outside a
  match goes over its time or if too many match frames go over 90%. Music steps and sound effects
  start at the beginning of the frame, at a fixed raster time; sprites and reserves are redone
  every frame. Long work is split over several frames, or waits for the next frame by looking at
  the raster. On PAL no match frame goes over 90%; on NTSC a few remain (about three in a
  thousand in the worst case: BLASTER bursts with the TELEPORT jump in bullet time), and if one
  goes over the frame the next one starts at once and catches up.
- **Charset and sprites are nearly used up.** Only a few of the 256 characters are free (a new
  character replaces one where the other is not needed, and `tools/gen_c64_assets.py` checks it),
  and all 8 sprites are taken. The letters are not in the cartridge: at boot they are copied from
  the C64 character ROM, and the big ones are built from there too. In NEXT matches characters
  64-127 (the big letters and the blanks after them) are used by the BLASTER lasers, and go back
  when the match ends: a new screen that uses them has to rebuild them. Over scores, bars,
  reserves and the centre line the laser does not cover anything: the program merges its stroke
  on the fly with the character underneath, which keeps its colour.
- **BASIC and KERNAL are off** (`$01 = $35`): data and variables live under their ROMs, and the RAM
  under I/O is read and written with `$01 = $34`.
- **Border and background** (`$D020`, `$D021`) are written only when the colour changes: every
  write while the colour is on screen leaves a "grey dot" on newer VIC-II chips.
- **ca65:** inside a `.proc`, constants defined outside are written `::NAME` in directives such as
  `.repeat`; branches beyond ±128 bytes use `jne`, `jeq`, `jcs`, `jcc`.
- **Flash.** The high scores are written with the commands of the EasyFlash's Am29F040, without
  EAPI: an EasyFlash 3 or a cartridge with a different flash chip would need EAPI. If the flash
  cannot be written, the program notices and does not try again until power-off.
