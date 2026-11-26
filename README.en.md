[<img src="docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/paddws-logo-dark.png">
    <img src="docs/paddws-logo-light.png" alt="PADD WS" width="800">
  </picture>
</p>

Table-top Pong for two players sitting at opposite ends of the screen, with an 80s arcade attract
mode, coin-op credits and an arcade mode like in fighting games: a ladder against seven opponents,
with power-ups and special moves, where a friend can join in and challenge you at any time. It runs
on PC, in the browser, in a Raspberry Pi cabinet, on the MiSTer FPGA and on the Commodore 64, and
everywhere it plays exactly the same match.

<p align="center"><img src="docs/badges/powered-by-sid.svg" alt="Powered by SID 6581 / 8580" width="250"></p>

Music, sound effects and voices come from a SID, the Commodore 64 sound chip: the real one on the
C64, the one from the C64 core on the MiSTer and a SID written in Rust on PC, Raspberry and web.

## Play now

**<https://schermobianco.github.io/PaddWS/>**: in the browser, on a computer, a phone or a tablet
(in landscape). On the phone the paddle follows your finger; on the computer you play with the
keyboard, a gamepad or the mouse.

## Screenshots

| | |
|---|---|
| ![Attract mode title with NEXT, with the CRT filter](docs/screenshots/attract-crt.jpg) | ![NEXT: paddle pick with the characters](docs/screenshots/next-paddles.png) |
| Attract mode title with NEXT, with the CRT filter | NEXT: paddle pick, with the characters |
| ![NEXT: the ladder's VS screen](docs/screenshots/challenge-intro.png) | ![NEXT: BLASTER against GUARDIAN](docs/screenshots/next-kinds.png) |
| The ladder: the VS screen before each opponent | The characters' paddles: BLASTER against GUARDIAN |
| ![MiSTer core: title](docs/screenshots/mister-title.png) | ![MiSTer core: paddle pick](docs/screenshots/mister-pick.png) |
| MiSTer core at 320×240: title after the coin | MiSTer core: paddle pick, with the characters |
| ![Commodore 64, vertical cartridge: the VS screen](docs/screenshots/c64-vertical-challenge.png) | ![Commodore 64, horizontal cartridge: the VS screen](docs/screenshots/c64-challenge.png) |
| Commodore 64, vertical cartridge (rotated field): the ladder's VS screen | Commodore 64, horizontal cartridge: the ladder's VS screen |
| ![Commodore 64, vertical cartridge: NEXT match](docs/screenshots/c64-vertical-next.png) | ![Commodore 64, horizontal cartridge: NEXT match](docs/screenshots/c64-next.png) |
| Commodore 64, vertical: NEXT, high-resolution spaceships and the HUD on the right | Commodore 64, horizontal: NEXT, ARCADE against ARCADE |

More screenshots in [How to play](docs/en/how-to-play.md#screenshots).

## Modes

**NEXT**, the main mode, works like the arcade mode of a fighting game:

- alone you climb a ladder against 7 CPU opponents, each with its own paddle, power-ups and theme,
  up to the final boss; there is arcade scoring, continues, a high-score table and an ending;
- a second player joins whenever they like (*HERE COMES A NEW CHALLENGER!*): the winner of the duel
  carries on up the ladder, and duels won in a row are counted;
- 7 paddle types, 6 power-ups that arrive in capsules to be collected and two special moves
  performed with a sequence of inputs;
- finishing the ladder unlocks training against the opponent of your choice;
- finish it on HARD or EXPERT without continues and you meet OMEGA, the secret boss that becomes
  all the others; beating it unlocks the jukebox with the game's themes.

There are also **CLASSIC**, good old Pong (two players, against the CPU or alone against a wall),
and **EVO**, for two players or against the CPU, where a ball hit with the centre of the paddle
powers up and the forward dash intercepts it.

Rules, power-ups, paddles, moves and controls: **[How to play](docs/en/how-to-play.md)**.

## Versions

| version | runs on | download |
|---|---|---|
| **Web** (Rust in WebAssembly) | browser on computers, Android, iPhone and iPad | play [online](https://schermobianco.github.io/PaddWS/), or `paddws-X.Y.Z-web.zip` |
| **Rust** (macroquad), a single executable | Windows, Linux x86_64, Raspberry Pi (Linux ARM64 and 32-bit ARM) | `paddws-X.Y.Z-windows-x86_64.zip`, `-linux-x86_64.tar.gz`, `-linux-aarch64.tar.gz`, `-linux-armv7.tar.gz`: runs straight away |
| **MiSTer core** FPGA, 320×240 at 15 kHz | DE10-Nano with MiSTer | `PaddWS_MiSTer_YYYYMMDD.zip`: unzip it into the root of the SD card (`/media/fat`), it shows up among the arcade titles; or with update_all ([how](mister/README.en.md#installation)) |
| **Commodore 64** (PAL and NTSC), 6502 assembly | C64, C64 Ultimate, VICE | `paddws-X.Y.Z-c64.zip`: the EasyFlash cartridges `paddws-horizontal-pal.crt` and `paddws-horizontal-ntsc.crt`, and the rotated-field ones, `paddws-vertical-pal.crt` and `paddws-vertical-ntsc.crt` |
| **Python** (Arcade 3.3), the first version | Windows, Linux, macOS, Raspberry Pi | `paddws-X.Y.Z-python.zip`: `pip install -r python/requirements.txt`, then `python python/main.py` |

Everything is in the [releases](https://github.com/Schermobianco/PaddWS/releases). The Python
version is frozen: it has CLASSIC and EVO, without the CPU or NEXT. What each version
has: [table](docs/en/how-to-play.md#features-by-version).

The reference game logic is the Rust core: deterministic, integers only, in fixed point. The
MiSTer core and the C64 version reproduce its state tick by tick, verified bit for bit.

## Controls at a glance

| | keys |
|---|---|
| PC, left player | `W` / `S` up and down, `D` dash, `F` / `C` select and use the power-up |
| PC, right player | `↑` / `↓`, `←` dash, `.` / `-` power-up |
| PC, general | `5` coin, `Enter` or `1` Start, `P` pause, `Esc` menu, `F11` full screen, `C` CRT filter (outside NEXT) |
| gamepads and arcade sticks | stick or d-pad, **A** dash, **B** / **C** power-up, **Start**, **Select** coin |
| phones and tablets | the paddle follows your finger, a second finger dashes, a tap on ❚❚ pauses |
| MiSTer | joystick, paddle or spinner; options in the OSD |
| Commodore 64 | joysticks in ports 2 and 1, or two paddles in port 1 |

All the controls, including the mouse as a spinner and the cabinet's encoders:
[How to play](docs/en/how-to-play.md#controls).

## A console to print

[![Render of the assembled Deck](hardware/deck/previews/render.png)](hardware/deck/README.en.md)

The [Deck](hardware/deck/README.en.md) is a 3D-printable table-top console: a Raspberry Pi with
the official 7" display, a knob on an optical encoder at each end and the DASH, SELECT and USE
buttons. It comes with the SolidCraft model and a STEP file, the Bambu Studio project with the
parts already split into plates (no supports, one colour per plate) and the assembly instructions.
For the Pi 2 there is a ready-made [SD card image](deploy/raspberry/deck/README.en.md)
(`paddws-X.Y.Z-deck-pi2.img.xz` in the releases): it boots into the game in about 8 seconds and is
switched off by pulling the plug.

| | |
|---|---|
| ![The Deck seen from above](hardware/deck/previews/top.png) | ![The Deck with a transparent top](hardware/deck/previews/inside.png) |
| From above: knobs with 20 notches, DASH, SELECT and USE at both ends | Inside: pillars, display bars and dovetails between the two halves |

## Documentation

- [How to play](docs/en/how-to-play.md): modes, power-ups, paddles, special moves, the NEXT ladder,
  sound, controls for every version.
- [Configuration](docs/en/configuration.md): `padd_config.json`, difficulty, NEXT parameters,
  Raspberry Pi cabinet.
- [Development](docs/en/development.md): structure, building, tests and checks, releases.
- [Ball angle](docs/en/ball-angle.pdf) (PDF): how the direction is chosen at launch and on hits,
  the TWIST paddle and a comparison with the 1972 Pong.
- [The Deck](hardware/deck/README.en.md): the console to print, parts, components and assembly.
- [Raspberry Pi cabinet](deploy/raspberry/README.en.md): models, encoder wiring, installation.
- The individual versions: [Rust](rust/README.en.md), [MiSTer core](mister/README.en.md),
  [Commodore 64](c64/README.en.md).
- What's new in each version (in Italian): [CHANGELOG.md](CHANGELOG.md).

## Contributing

Bugs and ideas go in an issue, changes in a pull request, in English or Italian. How the work is
done and which checks are needed is explained in [CONTRIBUTING.en.md](CONTRIBUTING.en.md). Questions go to
[Discussions](https://github.com/Schermobianco/PaddWS/discussions); everyone taking part follows the
[code of conduct](CODE_OF_CONDUCT.md), and security issues are reported privately
([SECURITY.md](SECURITY.md)).

## Supporting the project

PADD WS is free and will stay free. If you'd like to buy me a coffee, you can do it on Ko-fi:

<a href="https://ko-fi.com/P5P1D4YFE"><img src="https://storage.ko-fi.com/cdn/kofi6.png?v=6" alt="Buy me a coffee on Ko-fi" height="36"></a>

## License

Copyright © 2020-2026 Schermobianco.

The PADD WS code (Rust, C64, Python, tools) is free software: you can redistribute and modify it
under the terms of the [GNU General Public License v3](LICENSE) or, at your option, any later
version. Whoever distributes it, even for a fee and even modified, must provide the source code
under the same license. The MiSTer core is GPL v2 or later, because it is built on the MiSTer
framework ([mister/LICENSE](mister/LICENSE)), and includes the SID emulation of the MiSTer C64
core, partly under the CERN-OHL-S v2 license. Fonts, dependencies and the other third-party parts
are listed in [THIRD_PARTY.md](THIRD_PARTY.md), with their licenses. Up to 4.0.0-beta.16 the code
was distributed under the MIT license.
