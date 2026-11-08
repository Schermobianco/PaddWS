# Development

[← README](../../README.en.md) · [<img src="../flags/it.svg" alt="" height="14"> Italiano](../sviluppo.md) · [<img src="../flags/gb.svg" alt="" height="14"> **English**](development.md)

Contributors: see also [CONTRIBUTING.en.md](../../CONTRIBUTING.en.md).

## One game, five versions

The reference game logic is the **Rust core** (`rust/core`): deterministic, Q16.16 fixed point,
integers only and no divisions. The **MiSTer core** reproduces its state tick by tick, verified bit
for bit with test vectors; so does the **C64 version**, run in a 6502 emulator and compared with the
core at every tick. The web version is the Rust version compiled to WebAssembly. The Python version
is the first one and is frozen: fixes only.

## Layout

```
rust/            Rust version: deterministic core (core), game also for the web (game, web), SID (sid),
                 MiSTer traces (trace) and RISC-V firmware (mister-fw), C64 test bench (c64),
                 patched copies of miniquad and quad-snd (vendor)
mister/          MiSTer core: Verilog RTL, simulation, Quartus project (Template_MiSTer framework)
c64/             Commodore 64 version in 6502 (preview), verified against the Rust core
python/          Python version
  paddws/          the package
    core/            pure game logic (match, parameters, double tap), no graphics dependencies
    app.py           window: letterbox scaling, audio, frame pacing
    attract.py       attract sequence
    scenes.py        attract, menu, match
    config.py        typed configuration, JSON loading and saving
    crt.py           CRT filter
    hardware.py      encoders (pigpio), Raspberry Pi detection, shutdown
  tests/           pytest tests
assets/          fonts, images, sounds, icons, attract bitmaps and timings (shared by all versions)
deploy/raspberry systemd service and boot configuration; SD card image of the Deck (deck)
hardware/        3D-printable console: the Deck (SolidCraft model and STEP, Bambu Studio project)
tools/           release, portable Rust environment, generators for icons, attract, sounds and MiSTer
                 ROMs, SID music (gen_sid_music.py, played by the Rust SID in rust/sid), CHALLENGE
                 texts, forge VM for releases
docs/            documentation, screenshots and icons
```

Each version has its own README (in Italian): [Rust](../../rust/README.md),
[MiSTer](../../mister/README.md), [Commodore 64](../../c64/README.md),
[Raspberry Pi](../../deploy/raspberry/README.md).

## Running from source

Rust version (on Windows with the portable toolchain; Linux and details in
[rust/README.md](../../rust/README.md)):

```powershell
. .\tools\rust-env.ps1
cd rust
cargo run --release
```

On Linux, install the libraries first
(`sudo apt install libx11-dev libxi-dev libgl1-mesa-dev libasound2-dev libudev-dev`), then
`cd rust && cargo run --release`.

Python version:

```sh
python -m venv .venv
.venv\Scripts\activate            # Linux/macOS: source .venv/bin/activate
pip install -e "./python[dev]"
python -m paddws                  # or: python python/main.py, or: paddws
```

Options: `--config FILE`, `--fullscreen` / `--windowed`, `--crt` / `--no-crt`, `--debug`.

## Web version

```powershell
.\tools\build-web.ps1          # paddws.wasm, page and JavaScript in rust\target\web
.\tools\build-web.ps1 -Serve   # plus a server on http://localhost:8080 (from a phone: http://<PC>:8080)
```

The first time you need the WebAssembly target: `rustup target add wasm32-unknown-unknown` (after
`. .\tools\rust-env.ps1`). The page is in [`rust/web/`](../../rust/web/): `index.html` and the
game's JavaScript plugins (SID music, gamepad, `localStorage`, full screen on touch devices); the
JavaScript of miniquad and quad-snd comes from their copies in `rust/vendor`. You can try it from a
phone on the same network with `-Serve` (the Windows firewall must let port 8080 through).

It is online on GitHub Pages, <https://schermobianco.github.io/PaddWS/>, from the `gh-pages`
branch: after the release, `build_onforge.bat -Publish` puts the contents of the web zip there
([`tools/publish-pages.ps1`](../../tools/publish-pages.ps1), which can also be run on its own).

## Tests and checks

```sh
pytest -q python                        # Python version
cd rust && cargo test                   # Rust core and game
.\mister\sim\run.ps1                    # HDL logic against the Rust core (sim/run.sh on Linux)
.\c64\build.ps1                         # C64 version (c64/build.sh on Linux), then:
cd rust && cargo run --release -p paddws-c64 -- game   # against the Rust core
```

The GitHub Actions `Python`, `Rust`, `MiSTer` and `C64` run the same checks; `MiSTer` also
synthesises the core with Quartus 17.0.2, `C64` assembles the program with cc65 and tries it in the
test bench (see [c64/README.md](../../c64/README.md), in Italian). They only run manually (*Run
workflow*, `gh workflow run`, `build_ongithub.bat` or `check_ongithub.bat`). The same checks run
locally with `build_onforge.bat -CheckOnly`, or, on files not committed yet, with `check_onforge.bat`.

Without the *forge* machine, `check_ongithub.bat` runs the same checks with the Actions: it puts the
files as they are now (uncommitted ones too) in a temporary commit on a `check/...` branch, starts
the four Actions, follows them to the end (on an error it shows the last lines of the failed job)
and deletes the branch. `-NoSynth` skips the MiSTer synthesis (about half an hour less), `-NoWait`
exits right after starting them. The branch and the commit leave the current branch and the index
alone; the repository is public, so for a few minutes the uncommitted files are visible on GitHub.
On branches the Actions publish nothing: they attach the packages to the release only on tags.

## Smoothness and latency (Rust version)

- Fixed 1/240 s physics step with interpolated rendering: identical movement at 60, 120, 144 or
  165 Hz and input applied within ~4 ms.
- A single update per presented frame, paced by vsync; if the driver ignores vsync the game
  detects it and caps itself at the monitor's refresh rate.
- GPU sync after every frame: no frames queued by the driver, ~1 frame of latency (turned off
  automatically if, with the compositor in use, it would drop frames).
- CRT filter computed at 720p at most and then scaled up: at 1440p/4K it stays within the frame
  budget.
- Audio "warmed up" at startup (every sound played once at zero volume): no hitch the first time
  a sound plays.
- Continuous collisions: the ball can't pass through the paddle at any speed.

## Versions and releases

[Semantic Versioning](https://semver.org/), a single number for the whole project: Python
(`python/paddws/__init__.py`), Rust (`rust/Cargo.toml`), MiSTer core and C64 version are released
together with the same number (a test checks that the Python and Rust ones match). The version is
shown in the menu, in the log at startup and with `--version`. Changes are described in
[CHANGELOG.md](../../CHANGELOG.md) (in Italian).

To release: add the entries under **Non rilasciato** (Unreleased) in the changelog, then

```sh
python tools/release.py minor      # or patch / major / X.Y.Z / X.Y.Z-beta.N, --dry-run to try it
git push --follow-tags
```

The script updates the Python and Rust version (with `Cargo.lock`) and the changelog (`-alpha.N`
and `-beta.N` previews leave the entries under **Non rilasciato**), creates the commit and the tag
`vX.Y.Z`. The packages are then built in one of two ways:

- `build_onforge.bat` runs the checks and builds the packages locally, in `dist\`, on the *forge* virtual
  machine ([tools/forge](../../tools/forge/README.en.md)): it starts and stops it by itself, and the PC
  only needs git and ssh. The VM is created once with `create_forge.bat` (VMware Workstation, about
  ten minutes, no questions asked). `build_onforge.bat -Publish` then publishes the release of the tag with `gh` and
  the web version on GitHub Pages. The release notes come from the changelog
  (`tools/release_notes.py X.Y.Z`): for previews, only the entries added or changed since the
  previous tag.
- `build_ongithub.bat VERSION` does everything online: checks, `tools/release.py`, push, starts the
  GitHub Actions on the tag and follows them up to the release (MiSTer core included); without a
  version it reruns the failed Actions of the tag already on the commit. At the end it adds the
  notes and puts the web version on GitHub Pages; only the Deck SD card image is missing, which
  only *forge* builds.
