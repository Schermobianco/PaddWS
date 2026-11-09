[<img src="../docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

# PADD WS – Rust version

A single executable, with fonts, sounds, music and attract graphics built in, for Windows, Linux
x86_64, Linux ARM64 and 32-bit ARM (Raspberry Pi); the same code compiled to WebAssembly is the web
version. Full rules and controls in [How to play](../docs/en/how-to-play.md).

## Launching and options

```
paddws [--config FILE] [--fullscreen | --windowed] [--crt | --no-crt] [--width N] [--height N] [--version]
```

`--width 0` follows the monitor's aspect ratio, `--width 320 --height 240` is the MiSTer core's
resolution. For testing: `--screenshot-tour DIR` (one screenshot per scene), `--paddle-gallery DIR`
(one image per paddle type), `--bench SECONDS` (plays by itself and prints frame timings).

The configuration, `padd_config.json`, is looked up next to the executable, then in the current
folder and in its parent (handy with `cargo run` inside `rust/`); the menu saves its choices there,
in the browser they stay in `localStorage`. Keys and values in [Configuration](../docs/en/configuration.md).

## Controls

Left `W` / `S` and `D` to dash, right `↑` / `↓` and `←`. `5` coin, `Enter` Start, `P` pause,
`Esc` menu and quit, `F11` fullscreen, `C` CRT filter. The mouse can act as the left player's knob
(**MOUSE SPINNER: ON** in the menu).

## Gamepads and arcade sticks

On PC and Raspberry Pi through [gilrs](https://crates.io/crates/gilrs), in the browser through the
Gamepad API (`web/gamepad.js`). The first gamepad plugged in belongs to the left player, the second
to the right one; playing alone with one gamepad, it works from either side. The keyboard stays on.

| control | in a match | in menus |
|---|---|---|
| stick or d-pad | moves the paddle (double tap = fast) | directions |
| **A** | forward dash and special moves | confirm |
| **B** | select the power-up (NEXT) | back |
| **C** (X or Y) | use the power-up (NEXT) | |
| **Start** | pause (then A resumes, B goes back to the menu) | Start |
| **Select** | coin | coin |

- The analog stick becomes an 8-way direction with a 35% dead zone, so the quarter circles of the
  special moves (↓ ↘ → + **A** STRAIGHT SHOT, → ↓ ↘ + **A** RISING STRIKE, → towards the opponent)
  work as on an arcade stick. Arcade sticks and encoder boards with only a digital d-pad work as
  they are.
- Buttons are recognised by name through gilrs's SDL mapping; boards without a mapping by number:
  1 A, 2 B, 3 C, 9 Select, 10 Start.
- Linux and Raspberry Pi: `libudev` is needed, plus access to `/dev/input/event*` (`input` group).
- In the browser a gamepad shows up after one of its buttons is pressed, and only on https or `localhost`.

## The workspace

```
core/       paddws-core: no_std logic, integers only (Q16.16), 240 Hz tick; the reference model
game/       paddws: the game, built on macroquad (web/ is its browser page)
sid/        paddws-sid: SID and music player in real time; render | compare | bench tool
trace/      paddws-trace: MiSTer parameters and traces, statistics for CPU and simulated players
c64/        paddws-c64: C64 test bench, runs the 6502 code and compares it with the core
mister-fw/  RISC-V firmware of the MiSTer core (tools/gen_mister_fw.py) and its test bench paddws-fw-sim
vendor/     our copies of miniquad and quad-snd, outside the workspace ([patch.crates-io])
```

## Building

On Windows with the portable toolchain in `C:\DEV\@Compiler`:

```powershell
. .\tools\rust-env.ps1          # Rust and MinGW for the current session only
cd rust
cargo run --release             # or cargo build --release: target\release\paddws.exe
```

On Debian, Ubuntu and Raspberry Pi OS:

```sh
sudo apt install libx11-dev libxi-dev libgl1-mesa-dev libasound2-dev libudev-dev
cd rust && cargo run --release
```

Release executables are built by the [forge](../tools/forge/README.en.md) VM (`build_onforge.bat`).

## Web version

```powershell
.\tools\build-web.ps1           # into rust\target\web
.\tools\build-web.ps1 -Serve    # plus a server on http://localhost:8080
```

The first time: `rustup target add wasm32-unknown-unknown`. It must be opened from a web server,
not by double-clicking `index.html` (see `web/LEGGIMI.txt`, in Italian).

## Checks before a push

GitHub Actions only run by hand: the checks are done locally.

```powershell
. .\tools\rust-env.ps1; cd rust
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy --release -p paddws --target wasm32-unknown-unknown -- -D warnings
cd ..; .venv\Scripts\python -m pytest -q python
.\mister\sim\run.ps1            # MiSTer traces against the core
.\c64\build.ps1                 # then in rust: paddws-c64 params --check, math, game, sid, ui, frames
```

`cmd /c check_onforge.bat` runs the same checks on forge with the files as they are now, no commit.
For diagnostics: `PADDWS_NO_GPU_SYNC=1` turns off the GPU wait after each frame,
`PADDWS_STARTUP_TIMES` prints startup timings, `PADDWS_MOUSE_TOUCH` turns the mouse into a finger.
