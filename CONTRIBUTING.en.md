[Italiano](CONTRIBUTING.md) · **English**

# Contributing to PADD WS

PADD WS is a personal project, open to anyone who wants to help: reporting a bug, trying the game
on real hardware, fixing the code, porting it to another machine. Some rules are stricter than
usual, because the same match runs identically in five versions: this page explains how the work
is done.

## Language

- Issues, discussions and pull requests: Italian or English.
- Comments and docstrings are in Italian, like the rest of the code. A PR with English comments is
  fine all the same: they get translated during the review.
- The main documentation pages exist in Italian and in English (`README.md` and `README.en.md`,
  `docs/` and `docs/en/`, `hardware/deck`). If you change one, update the other too; if you can't,
  say so in the PR.

## Before you start

- For a bug or some odd behaviour, open an [issue](https://github.com/Schermobianco/PaddWS/issues/new/choose)
  with the bug report form: version, platform and the steps to reproduce it.
- For a new feature or a change to the game rules, open an issue or a discussion first: the rules
  apply to five versions at once (see below), so even a small change has a cost.
- The Python version (`python/`) is frozen: only fixes are accepted.
- Questions and ideas go to [Discussions](https://github.com/Schermobianco/PaddWS/discussions).

## The main rule: one single game

The reference logic is the Rust core (`rust/core`): deterministic, Q16.16 fixed point, integers
only. The MiSTer core and the C64 version reproduce its state tick by tick, and the tests check it
bit for bit. So a gameplay change touches three implementations:

1. `rust/core` (Rust),
2. `mister/` (RISC-V firmware and Verilog RTL, checked against the traces from `rust/trace`),
3. `c64/` (6502 assembly, checked with the emulator in `rust/c64`).

If you only know one of the three, open the PR anyway and say so: the rest can be ported during
the review. A PR that changes `rust/core` without the other two can't be merged as it is, because
it makes the trace checks fail.

Some files are generated and must not be edited by hand: `mister/rtl/gen/*.vh` (from
`tools/gen_*`), `c64/gen/` (from `tools/gen_c64_assets.py`), the attract mode bitmaps and timings in
`assets/attract/` (from `tools/gen_attract_assets.py`). Change the generator and regenerate them.

On the C64 a frame can't take more than 18,000 cycles (`paddws-c64 frames` checks it) and the zero
page is full: see [c64/README.md](c64/README.md) (in Italian).

## Building and checking

The full instructions are in [docs/en/development.md](docs/en/development.md). In short, from
`rust/`:

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy --release -p paddws --target wasm32-unknown-unknown -- -D warnings
```

Then, depending on what you touched:

- Python: `pytest -q python`;
- MiSTer: `mister/sim/run.sh` (or `run.ps1` on Windows), which checks the core against the Rust
  traces;
- C64: assemble with cc65 (`c64/build.ps1`) and test against the core with `cargo run --release -p
  paddws-c64 -- game` (and `params --check`, `math`, `sid`, `ui`, `frames`).

The Windows scripts look for portable tools in `C:\DEV\@Compiler`, or in the folder named by the
`PADDWS_COMPILERS` environment variable. GitHub Actions only run manually: the maintainer starts
them on pull requests. You don't need to run everything; just say in the PR what you tested.

## Pull requests

- One topic per PR, small when possible.
- The title follows the commit style: the area, then what changes, e.g.
  `C64: ball trail, centred texts`.
- Changes that players will notice go in [CHANGELOG.md](CHANGELOG.md), under **Non rilasciato**
  (Unreleased); English is fine, they get translated during the review.
- If something changes on screen, a screenshot helps a lot.

## License

By contributing you agree that your code is distributed under the license of the part you touched:
GPL v3 or later for the game (Rust, C64, Python, tools), GPL v2 or later for the MiSTer core. See
[LICENSE](LICENSE) and [THIRD_PARTY.md](THIRD_PARTY.md).

## Conduct and security

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md). Security issues don't go in
public issues: see [SECURITY.md](SECURITY.md).
