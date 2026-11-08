# Configuration

[← README](../../README.en.md) · [<img src="../flags/it.svg" alt="" height="14"> Italiano](../configurazione.md) · [<img src="../flags/gb.svg" alt="" height="14"> **English**](configuration.md)

This page is about the Rust version on PC and Raspberry Pi. The Python version, which is frozen,
reads the same file but only knows the CLASSIC and EVO keys (`resolution`, `ball`, `paddle`,
`boost`, `encoder`, `crt_effects`, `colors` and the basic keys of `game`): mode, players, volumes,
white level, zoom, scores, accent colour, mouse and the `next` section exist only in the Rust
version. The MiSTer has its options in the OSD, the Commodore 64 in its menu; in the browser the
menu choices are kept in `localStorage`.

## padd_config.json

`padd_config.json` is read at startup: the Rust version looks for it next to the executable, then
in the current folder and in its parent; the Python version in the folder that contains `python/`.
`--config FILE` uses a different file. Missing keys take their default value, unknown keys are
ignored (the Python version reports them in the log); the Rust version adds new keys to the file,
with their defaults.
Sizes and speeds are given for the 800×480 reference resolution and scaled to `resolution`. The
menu changes and saves mode and players, full screen, CRT filter, difficulty, music and effects
volumes, attract sound, white level, zoom, scores and mouse as a spinner.

With `resolution.width = 0` (the default) the playfield takes the monitor's aspect ratio at the
given height: 640×480 on 4:3, 853×480 on 16:9, 800×480 on the Pi display, so there are no black
bars. An explicit width (e.g. `640` for a 4:3 cabinet) fixes the playfield; if the screen has a
different aspect ratio, black bars appear (`game.keep_aspect`) instead of stretching.

| key | default | |
|---|---|---|
| `game.fullscreen`, `crt_effects.enabled` | `false` | full screen (`F11`) and CRT filter (`C`); the `padd_config.json` in the package turns them on |
| `game.free_play` | `true` | no coins; with `false` each match costs a credit (key `5`) |
| `game.points_to_win` | `11` | points to win a two-player match |
| `game.lives` | `3` | balls in single-player |
| `game.difficulty` | `1` | 0 EASY, 1 NORMAL, 2 HARD, 3 EXPERT |
| `game.game_type` | `"next"` | mode chosen in the menu (**GAME TYPE**): `"classic"`, `"evo"` or `"next"` |
| `game.players` | `"challenge"` | players chosen in the menu (**PLAYERS**): `"two"`, `"cpu"`, `"challenge"` or `"one"` |
| `game.self_test` | `true` | self-test at startup |
| `game.attract_sound` | `true` | attract mode sounds and music, and menu music (coin and Start are always heard) |
| `game.music_volume` | `100` | volume of all music in percent, from 0 (no music) to 100 (menu **MUSIC VOLUME**, in 10% steps). It replaces `game.music` (and before it `game.sid_sound` and `game.match_music`): if one of them was `false` it starts from 0 |
| `game.effects_volume` | `100` | volume of effects and voices in percent (menu **EFFECTS VOLUME**) |
| `game.white_level` | `100` | brightness of white in percent (menu: 100, 87, 75, 62), the whole picture in proportion |
| `game.zoom` | `100` | thickness of ball and paddles in percent, collisions included (menu **ZOOM**: 100, 125, 150, 175, 200), for small screens; paddle height and playfield stay the same |
| `game.scores_upright` | `true` | scores upright at the top (menu **SCORES: UPRIGHT**); with `false` they face the players sitting at the sides of a table (**FACING**) |
| `colors.accent` | `[255, 210, 37]` | accent colour (the attract yellow): the selected menu item; in NEXT only: menu title, title and cursor of the picks, name of the activated power-up, reserve arrow, TELEPORT portals, STEER wheel and limit marks, SUPER capsule and ball, BULLET capsule and the paddle border of whoever armed it |
| `mouse.spinner` | `false` | the mouse as the left player's spinner (menu **MOUSE SPINNER**); ignored with the cabinet encoders |
| `mouse.travel_pixels` | `1000` | mouse movement in pixels to take the paddle from one edge to the other |
| `game.vsync`, `game.keep_aspect`, `game.serve_delay` | | vertical sync, black bars, wait before the serve |
| `crt_effects.resolution_scale` | `2.5` | Rust version: lines emulated by the CRT filter: 3 × playfield height / value (576 at 480 lines). The old default, `1.0`, is changed to `2.5` automatically |

The other sections (`ball`, `paddle`, `boost`, `encoder`, `crt_effects`, `colors`) are in the
`padd_config.json` of the package, which differs from the code defaults in a few places (CRT filter
on, screen curvature, light grey).

## Difficulty

The difficulty sets how much the ball speeds up at each hit and its top speed (pixels per frame at
800×480); in single-player only the player's hits speed it up, not the wall.

| difficulty | single-player | two players | NEXT |
|---|---|---|---|
| EASY | +5% / 8 | +15% / 6 | +6% / 7 |
| NORMAL | +10% / 10 | +25% / 8 | +10% / 10 |
| HARD | +15% / 12 | +25% / 10 | +14% / 11 |
| EXPERT | +25% / 15 | +30% / 12 | +18% / 13 |

## NEXT parameters

The `next` section tunes the ball, capsules and power-ups of the NEXT mode in the Rust version; if
it is missing, the game adds it to the file with the defaults. The defaults are the same as in the
MiSTer core: with different values the PC no longer matches the FPGA, so they are meant for trying
out new tunings (good values are then carried over to the Rust core and the MiSTer).

| key | default | |
|---|---|---|
| `ball_speedup`, `ball_max_speed` | `[1.06, 1.10, 1.14, 1.18]`, `[7, 10, 11, 13]` | speed-up at each hit and top speed, per difficulty |
| `capsule_size`, `capsule_speed`, `capsule_drift` | `26`, `2.5`, `0.3` | side, speed and vertical drift of the capsules |
| `hud_band` | `48` | band at the top reserved for the reserves |
| `spawn_seconds`, `spawn_jitter_seconds` | `4`, `1` | seconds between two capsules, plus a random part |
| `super_odds` | `8` | one capsule in 8 holds the SUPER |
| `bullet_odds` | `16` | one capsule in 16 holds the BULLET (0 = never) |
| `bullet_ramp_seconds` | `0.25` | ramp-in of the BULLET (which lasts until the return or the point) |
| `bullet_speed`, `bullet_ramp_speed` | `0.5`, `0.75` | speed of the rest of the game during the BULLET and in the ramp (1 − 1/2ⁿ: 0.5, 0.75, 0.875…) |
| `cooldown_seconds` | `2` | minimum pause between two power-ups of the same player |
| `smash_multiplier`, `super_multiplier` | `2.2`, `3.2` | horizontal speed of the shot with SMASH and SUPER |
| `slow_multiplier`, `slow_seconds` | `0.65`, `1` | speed left with SLOW; `slow_seconds` no longer has an effect (the aura lasts as long as the slowdown) |
| `curve_accel` | `0.3` | strength of CURVE |
| `steer_accel` | `0.3` | STEER steering with up or down held (the steered ball reaches about 63° at most) |
| `hitstop_seconds` | `0.1667` (1/6 s) | game freeze of the SUPER with hit-stop |
| `super_meter_max`, `super_cost` | `64`, `32` | special move meter (always on; the old `super_moves` key disappears from the file) and cost of a move |
| `super_gain_hit`, `super_gain_dash`, `super_gain_conceded` | `2`, `4`, `8` | meter gained with a hit, with a dash that intercepts the ball, with a point conceded |
| `super_straight_multiplier` | `2` | push of the STRAIGHT SHOT MAX (1 + 1/2ⁿ: 2, 1.5, 1.25…); the normal move adds half as much |

The paddle types are in the `next.paddles` section.

## Raspberry Pi cabinet

The cabinet runs either the Python version or the Rust one (with NEXT, the CPU and the encoders read
directly from the GPIO, on the Pi 5 too), each with its own systemd service. Installation and
wiring of encoders and buttons: [deploy/raspberry/README.md](../../deploy/raspberry/README.md) (in
Italian).
