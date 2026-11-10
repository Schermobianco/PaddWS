[<img src="../docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="../docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

# PADD WS – MiSTer core

The PADD WS FPGA core for the MiSTer (DE10-Nano): 320×240p video at 15.7 kHz and 60 Hz, the 80s
attract mode, music and sound effects on an emulated SID (8580 or 6581), joystick, paddle and
spinner. Every mode is there, Classic, EVO, NEXT and CHALLENGE, and the attract shows a demo played
by two CPUs. The full rules and controls are in [How to play](../docs/en/how-to-play.md).

The game logic is not rewritten in Verilog: it is the Rust core ([`rust/core`](../rust/core)),
compiled for RV32IM and run by a VexRiscv processor at 60 MHz inside the core (firmware in
[`rust/mister-fw`](../rust/mister-fw)). That way the MiSTer plays the same match as the other
versions, tick for tick. The RTL takes care of the rest: video, attract, screens, audio and input.

The core was tested on a DE10-Nano back when the logic was still in Verilog. The RISC-V version
passes the simulation tests and synthesis, but still has to be tried on the hardware, like paddle
and spinner.

## Installation

The release zip, `PaddWS_MiSTer_YYYYMMDD.zip`, is unpacked into the root of the SD card
(`/media/fat/`): it puts `PaddWS.mra` in `_Arcade/` and `PaddWS_YYYYMMDD.rbf` in `_Arcade/cores/`,
with the license texts in `_Arcade/cores/PaddWS_licenses/`. The game shows up among the arcade
titles and needs no ROMs.

## High scores on the SD card

The CHALLENGE high-score table is saved in NVRAM, like in the arcade cores:
`/media/fat/config/nvram/PaddWS.nvm`. With *Autosave scores: On* (the default), after every change
the MiSTer saves it the next time the OSD is opened; with *Off* only through *Save settings* in the
system menu. It only works when the core is started from the `.mra`: started from the `.rbf`, the
table lasts until the core is switched off. A broken file is ignored and the default table stays.

## Controls and options

Up and down move the paddle (a quick double tap gives the fast movement), **A** is the forward
dash, **B** the fast movement, **X** and **Y** select and use the power-up in NEXT, **Start**
starts and **Select** inserts a coin. On the keyboard `5` is the coin and `1` is Start, like in the
arcade cores. Special moves are joystick quarter circles, or a back-and-forth turn of the knob,
followed by **A**.

The OSD (F12) has the mode (*Game type*), players, Free Play, difficulty, scores upright or facing
the players for a table, attract sounds, SID 8580 or 6581, music and effects volume, high-score
saving, white level, paddle control (joystick, paddle or spinner) and spinner speed. Scanlines and
filters are the MiSTer's own.

## Building

Synthesis uses Quartus Prime Lite 17.0.2 inside the Docker container `theypsilon/quartus-lite-c5`,
pinned by digest in `quartus-image.txt`: all you need is Docker, no Intel account. The `.rbf` ends
up in `mister/output_files/PaddWS.rbf`.

```powershell
.\mister\synth.ps1        # Windows with Docker Desktop
sh mister/synth.sh        # Linux or a VM with Docker
```

Both scripts print resources and slack, and fail if timing is not met.

Usually the *forge* VM does the synthesis ([tools/forge](../tools/forge/README.en.md)):
`build_onforge.bat` from the PC for the whole release, `forge-sintesi` on the VM for the core alone
(about 16 minutes). The alternative is the `MiSTer` GitHub Action, which only runs by hand and
takes about half an hour.

The files in `rtl/gen/` are generated and committed, so synthesis needs neither Rust nor Python.
Don't edit them by hand: change the generator and run it again.

| file | generator |
|---|---|
| `pong_fw_b0..3.hex`, `pong_fw.vh` (firmware) | `tools/gen_mister_fw.py` |
| `pong_params.vh` | `paddws-trace` (written to `sim/trace/`, to be copied into `rtl/gen/`) |
| `pong_fonts.vh` | `tools/gen_mister_assets.py` |
| `pong_attract.vh` | `tools/gen_attract_assets.py` |
| `pong_next.vh` | `tools/gen_next_assets.py` |
| `pong_challenge.vh` | `tools/gen_challenge_assets.py` |
| `howto_*.hex`, `pong_howto.vh` | `tools/gen_howto_assets.py` |
| `ending_*.hex`, `pong_ending.vh` | `tools/gen_ending_assets.py` |
| `sid_music.hex`, `sid_music.vh` | `tools/gen_sid_music.py` |
| `sid_voices.hex`, `sid_voices.vh` | `tools/gen_voices.py --mister` |

The firmware needs Rust with the `riscv32im-unknown-none-elf` target (the portable environment of
`tools\rust-env.ps1`). After any change to `rust/core` it has to be rebuilt with
`python tools/gen_mister_fw.py`, otherwise the MiSTer core keeps the old logic.

## Testing

```powershell
.\mister\sim\run.ps1
```

It regenerates with `paddws-trace` the 29 reference traces of the Rust core (Classic, EVO, NEXT,
paddle types, special moves, CPU, spinner) and plays them back on the firmware in an RV32IM
emulator (`paddws-fw-sim`): the state must match bit for bit on every tick. It also checks, with
`gen_mister_fw.py --check`, that the firmware in `rtl/gen` is in step with the sources. On Linux,
in CI and on forge the script is `sim/run.sh`.

To see the whole core there is the frame simulator, built with Verilator:

```powershell
.\mister\sim\frames\frames.ps1 [scenario] [frames or ranges...] [-f] [-u]
.\mister\sim\frames\frames.ps1 next 1300 1400-1420
```

It rebuilds the model only when the RTL has changed, runs at about 3.5 frames per second and saves
PPM images in `mister/sim/frames/`. On the first frame of a match it saves a checkpoint that later
runs start from; `-f` ignores it, `-u` makes the text upright. The most useful scenarios:

- none: power-on, coin, demo and a one-player match up to GAME OVER;
- `demo`: the demos of the four modes, one per attract loop;
- `next`, `kinds`: NEXT against the CPU; `kinds` takes the paddle types from the `PONG_KINDS`
  variable (`PaddleKind` codes, `4,6` if unset);
- `supers`, `howto`: special moves in a match and the HOW TO PLAY screen;
- `bullet`, `ghost`, `warp`, `steer`: single power-ups;
- `challenge`, `challenger`, `ending`: CHALLENGE, a second player joining in and the ending;
- `nvram`: the SD high scores with a fake `hps_io`;
- `win`, `perfect`, `paddle`, `spin`, `mute`, `music`: end of match, paddle and spinner, audio.

The full list, with what each scenario checks, is at the top of `sim/frames/frames.cpp`.

Other test benches, slower or more specific:

- `.\mister\sim\rv\rv.ps1 [-Traces trace,...] [-Ticks N]`: the real VexRiscv with the firmware
  against the traces from `run.ps1`, cycle by cycle, with the timing of each tick (all of them:
  about an hour);
- `.\mister\sim\sid\render.ps1 FOLDER [-Voice]`: songs, effects and voices of the SID as WAV
  files, the reference for the Rust SID (`paddws-sid compare`);
- `.\mister\sim\sid\writes.ps1`: the player's writes to the SID registers, the reference for the
  Rust player and the C64 one.

The scripts look for the OSS CAD Suite (Verilator) and MinGW in `C:\DEV\@Compiler`, or in the
folder given by `PADDWS_COMPILERS`.

## Sources

- `PaddWS.sv`: glue to the Template_MiSTer `sys/` framework (OSD, joystick, PLL, video, audio).
- `rtl/pong_top.v`: attract sequence, matches, coins and CHALLENGE; the four 240 Hz ticks of each frame.
- `rtl/pong_logic_rv.v`: the processor (`rtl/vexriscv/`), the firmware RAM and the registers.
- `rtl/*_render.v`: playfield, attract, NEXT, HOW TO PLAY, CHALLENGE and ending.
- `rtl/pong_sid.v` and `rtl/sid/`: music player and voices, with the SID from the MiSTer C64 core.
- `rtl/ch_nvram.v`: the SD high scores.
- `sim/`: traces, frame simulator, test benches for the processor and the SID.

## Good to know

- The timing margin is thin and the DSPs are all used: no divisions or modulo in the RTL, and the
  renderers work out positions and bounds once per frame, then only compare.
- The four ticks of a frame start at the beginning of vblank and must be done before the snapshot
  on line 261, which the renderers use for the whole next frame.
- Bits 24, 25 and 26 of the OSD status are free, but old CFG files may have them set: don't reuse
  them.
- `sim/tb_pong_top.v` (Icarus) no longer matches the ports of `pong_top`: use the frame simulator
  instead.

## License

The Template_MiSTer `sys/` framework is GPL v2, so the core is GPL v2 or later
([LICENSE](LICENSE)). The SID in `rtl/sid` is partly CERN-OHL-S v2
([rtl/sid/README.md](rtl/sid/README.md)), VexRiscv is MIT. The rest of the project, firmware
included, is GPL v3 or later: see [THIRD_PARTY.md](../THIRD_PARTY.md).
