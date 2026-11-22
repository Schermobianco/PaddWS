"""Genera mister/rtl/gen/pong_paddles.vh: colori e tabelle delle racchette dei personaggi del core
MiSTer (kind_px e muro del GUARDIAN in mister/rtl/next_render.v).

Le animazioni sono quelle di rust/game/src/paddle_ui.rs e next_ui.rs, con il tempo in frame a 60 Hz
(i contatori di pong_top) e le colonne del corpo largo 4 del MiSTer (tools/paddle_shapes.py: si toglie
la colonna 0 del PC, quelle davanti scalano di 1). Qui ci sono solo le parti con seni, quadrati e
arrotondamenti, già calcolate: il resto delle forme è scritto in kind_px.

Uso:  .venv\\Scripts\\python tools\\gen_mister_paddles.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import paddle_shapes as ps

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mister" / "rtl" / "gen" / "pong_paddles.vh"
PORTRAITS = ROOT / "assets" / "characters" / "portraits" / "portraits.json"

# frame delle animazioni (60 Hz), come i secondi di paddle_ui.rs e next_ui.rs
HIT_FRAMES = 30          # SPARK_SECONDS e RING_SECONDS
FIRE_FRAMES = 26         # FIRE_SECONDS
CRACK_FRAMES = 9         # il corso si crepa per 0,15 s
BREAK_FRAMES = 39        # BREAK_SECONDS
BLINK_FRAMES = 15        # BARRIER_BLINK_SECONDS
BARRIER_FRAMES = 42      # BARRIER_FLASH_SECONDS


def col(x: int) -> int:
    """Colonna del PC sul corpo largo 4 (x != 0)."""
    assert x != 0
    return x if x < 0 else x - 1


def rgb(c) -> str:
    return f"24'h{c[0]:02X}{c[1]:02X}{c[2]:02X}"


def sparks() -> list[str]:
    """HAMMER: pixel delle scintille (du, dv) dalla faccia e dalla riga del colpo, per posa (8 al secondo)."""
    out = ["// HAMMER: posa delle scintille (0-3, 8 al secondo) al frame `f` dal colpo potente",
           "function [1:0] pd_spark_pose(input [4:0] f);",
           "    pd_spark_pose = " + " : ".join(f"(f < 5'd{math.ceil(k * 60 / 8)}) ? 2'd{k - 1}" for k in (1, 2, 3)) + " : 2'd3;",
           "endfunction",
           "// pixel (du, dv) delle scintille alla posa `pose`, contati dalla faccia e dalla riga del colpo",
           "function pd_spark(input [1:0] pose, input signed [11:0] du, input signed [11:0] dv);",
           "    case (pose)"]
    for pose in range(4):
        p = (pose + 1) / 4
        pts = set()
        for j in range(6):
            an = math.radians(-70 + j * 28)
            d = 2 + p * 7
            for dd in (d, d - 1.5):
                x = ps.jround(1 + math.cos(an) * dd)
                if x != 0:
                    pts.add((col(x), ps.jround(math.sin(an) * dd)))
        cond = " ||\n                   ".join(f"(du == {u} && dv == {v})" for u, v in sorted(pts))
        out.append(f"        2'd{pose}: pd_spark = {cond};")
    out += ["        default: pd_spark = 1'b0;", "    endcase", "endfunction"]
    return out


def ring() -> list[str]:
    """TWIST: l'onda del colpo, un anello di raggio 3 + 7 p: un pixel ci sta se 16 (du^2 + dv^2) è tra
    (4 r - 2)^2 e (4 r + 2)^2."""
    lo, hi = [], []
    for f in range(HIT_FRAMES):
        r = 3 + f / HIT_FRAMES * 7
        lo.append(round((4 * r - 2) ** 2))
        hi.append(round((4 * r + 2) ** 2))
    out = ["// TWIST: onda al frame `f` dal colpo (0-29): il pixel (du, dv) dal centro dell'estremità è",
           "// sull'anello se pd_ring_lo <= 16 (du^2 + dv^2) < pd_ring_hi",
           "function [12:0] pd_ring_lo(input [4:0] f);", "    case (f)"]
    out += [f"        5'd{f}: pd_ring_lo = 13'd{v};" for f, v in enumerate(lo)]
    out += ["        default: pd_ring_lo = 13'd8191;", "    endcase", "endfunction",
            "function [12:0] pd_ring_hi(input [4:0] f);", "    case (f)"]
    out += [f"        5'd{f}: pd_ring_hi = 13'd{v};" for f, v in enumerate(hi)]
    out += ["        default: pd_ring_hi = 13'd0;", "    endcase", "endfunction"]
    return out


def casing() -> list[str]:
    """BLASTER: il bossolo che vola dietro, dal frame 2 al 25 dallo sparo."""
    xs, ys = {}, {}
    for f in range(2, FIRE_FRAMES):
        p = (f - 2) / 24
        xs[f] = ps.jround(-7 - p * 10)
        ys[f] = ps.jround(-6 * math.sin(p * math.pi) + p * 4)
    out = ["// BLASTER: bossolo al frame `f` dallo sparo (2-25): colonna e riga dalla prima del colpo vuotato",
           "function signed [5:0] pd_case_x(input [4:0] f);", "    case (f)"]
    out += [f"        5'd{f}: pd_case_x = {v};" for f, v in xs.items()]
    out += ["        default: pd_case_x = 6'sd31;", "    endcase", "endfunction",
            "function signed [5:0] pd_case_y(input [4:0] f);", "    case (f)"]
    out += [f"        5'd{f}: pd_case_y = {v};" for f, v in ys.items()]
    out += ["        default: pd_case_y = 6'sd0;", "    endcase", "endfunction"]
    return out


def build() -> list[str]:
    """GUARDIAN: un corso cade da 14 pixel in 15 frame prima di posarsi."""
    out = ["// GUARDIAN: spostamento del corso che cade, `d` frame dall'inizio della caduta (0-14)",
           "function signed [4:0] pd_build_dy(input [3:0] d);", "    case (d)"]
    for d in range(15):
        out.append(f"        4'd{d}: pd_build_dy = {-ps.jround((1 - ps.smooth(d / 15)) * 14)};")
    out += ["        default: pd_build_dy = 5'sd0;", "    endcase", "endfunction"]
    return out


def chips() -> list[str]:
    """GUARDIAN: le quattro schegge del corso rotto, dal frame in cui finisce la crepa."""
    n = BREAK_FRAMES - CRACK_FRAMES
    xs, ys = [], []
    for a in range(n):
        p = a / 30
        xs.append([ps.jround(-7 - p * (5 + 2 * j)) for j in range(4)])
        ys.append([ps.jround(1 + j * 1.5 + (j - 1.5) * p * 3) for j in range(4)])
    out = [f"// GUARDIAN: schegge del corso rotto al frame `a` dalla fine della crepa (0-{n - 1}): colonna e riga",
           "// (dalla prima del corso) della scheggia j (le pari larghe 2 e scure, le dispari 1 e grigie)",
           "function signed [5:0] pd_chip_x(input [4:0] a, input [1:0] j);", "    case ({a, j})"]
    out += [f"        {{5'd{a}, 2'd{j}}}: pd_chip_x = {xs[a][j]};" for a in range(n) for j in range(4)]
    out += ["        default: pd_chip_x = 6'sd31;", "    endcase", "endfunction",
            "function signed [5:0] pd_chip_y(input [4:0] a, input [1:0] j);", "    case ({a, j})"]
    out += [f"        {{5'd{a}, 2'd{j}}}: pd_chip_y = {ys[a][j]};" for a in range(n) for j in range(4)]
    out += ["        default: pd_chip_y = 6'sd0;", "    endcase", "endfunction"]
    return out


def crumble() -> list[str]:
    """Muro in campo: dopo il lampo il blocco si sbriciola in 8 schegge che vanno verso il fondo e
    cadono (next_ui.rs), con il blu che si scurisce."""
    n = BARRIER_FRAMES - BLINK_FRAMES
    dx, dy, tone = [], [], []
    for f in range(n):
        k = f / n
        dx.append([ps.jround(k * (3 + m * 3)) for m in range(3)])
        dy.append(ps.jround(k * k * 10))
        fade = 1 - 0.5 * k
        tone.append(0 if fade > 0.88 else 1 if fade > 0.71 else 2)
    out = [f"// muro del GUARDIAN in campo: schegge del blocco al frame `f` dalla fine del lampo (0-{n - 1}):",
           "// spostamento verso il fondo (per j % 3), caduta e tono del blu (0 pieno, 1 e 2 più scuri)",
           "function [3:0] pd_crumble_dx(input [4:0] f, input [1:0] m);", "    case ({f, m})"]
    out += [f"        {{5'd{f}, 2'd{m}}}: pd_crumble_dx = {dx[f][m]};" for f in range(n) for m in range(3)]
    out += ["        default: pd_crumble_dx = 4'd0;", "    endcase", "endfunction",
            "function [3:0] pd_crumble_dy(input [4:0] f);", "    case (f)"]
    out += [f"        5'd{f}: pd_crumble_dy = {v};" for f, v in enumerate(dy)]
    out += ["        default: pd_crumble_dy = 4'd0;", "    endcase", "endfunction",
            "function [1:0] pd_crumble_tone(input [4:0] f);", "    case (f)"]
    out += [f"        5'd{f}: pd_crumble_tone = 2'd{v};" for f, v in enumerate(tone)]
    out += ["        default: pd_crumble_tone = 2'd2;", "    endcase", "endfunction"]
    return out


def colors() -> list[str]:
    spec = json.loads(PORTRAITS.read_text(encoding="utf-8"))
    out = ["// colori dei personaggi (accent di portraits.json, come i segni del PC): pieno, scurito,",
           "// schiarito, per tipo (PaddleKind); e il corpo in ombra dei colori del corpo"]
    for k, name in enumerate(ps.KINDS):
        ramp = ps.mark_ramp(tuple(spec["accent"][name]))
        out.append(f"localparam [23:0] PD_MARK{k} = {rgb(ramp[ps.MARK])}, PD_MARK_DARK{k} = {rgb(ramp[ps.MARK_DARK])}, "
                   f"PD_MARK_LIGHT{k} = {rgb(ramp[ps.MARK_LIGHT])};")
    for name, c in (("WHITE", (255, 255, 255)), ("GRAY", (0xB4, 0xB4, 0xB4)), ("ACCENT", (0xFF, 0xD2, 0x25)),
                    ("OMEGA_RED", (0xE6, 0x28, 0x28)), ("OMEGA_PURPLE", (0xA0, 0x40, 0xE0))):
        out.append(f"localparam [23:0] PD_{name}_SH = {rgb(ps.body_shade(c))};")
    for name, role in (("SHADOW", ps.SHADOW), ("GRAY", ps.GRAY), ("GRAY_LIGHT", ps.GRAY_LIGHT), ("DARK", ps.DARK),
                       ("DARK_DEEP", ps.DARK_DEEP)):
        out.append(f"localparam [23:0] PD_{name} = {rgb(ps.RGB[role])};")
    # TITAN: sul PC (paddle_ui.rs) l'ombra è doppia e più scura, una lontana (26, 26, 38) al 175/255
    # e sopra quella vicina (40, 40, 52) al 115/255, sul nero. Sul MiSTer si usa la lontana da sola:
    # con le due sovrapposte, provata sul MiSTer, l'ombra sembrava ancora troppo chiara
    far = tuple(round(c * 175 / 255) for c in (26, 26, 38))
    out.append(f"localparam [23:0] PD_SHADOW_TITAN = {rgb(far)};")
    rush = tuple(spec["accent"]["rush"])
    for i in (1, 2, 3):
        out.append(f"localparam [23:0] PD_RUSH_GHOST{i} = {rgb(tuple(round(c * 0.18 * i) for c in rush))};")
    blue = tuple(spec["accent"]["guardian"])
    out.append(f"localparam [23:0] PD_WALL = {rgb(blue)}, PD_WALL_LIGHT = 24'hBED6FF, "
               f"PD_WALL1 = {rgb(tuple(round(c * 0.8) for c in blue))}, PD_WALL2 = {rgb(tuple(round(c * 0.6) for c in blue))};")
    return out


def main() -> None:
    lines = ["// Generato da tools/gen_mister_paddles.py: non modificare a mano.",
             "// Colori e tabelle delle racchette dei personaggi (next_render.v).",
             f"localparam integer PD_HIT_FRAMES = {HIT_FRAMES}, PD_FIRE_FRAMES = {FIRE_FRAMES}, "
             f"PD_CRACK_FRAMES = {CRACK_FRAMES}, PD_BREAK_FRAMES = {BREAK_FRAMES},",
             f"                   PD_BLINK_FRAMES = {BLINK_FRAMES}, PD_BARRIER_FRAMES = {BARRIER_FRAMES};"]
    for part in (colors(), sparks(), ring(), casing(), build(), chips(), crumble()):
        lines += [""] + part
    # file generati del MiSTer in ASCII: le lettere accentate dei commenti con l'apostrofo
    text = "\n".join(lines) + "\n"
    for c, r in zip("àèéìòù", ("a'", "e'", "e'", "i'", "o'", "u'")):
        text = text.replace(c, r)
    OUT.write_text(text, encoding="ascii", newline="\n")
    print(OUT)


if __name__ == "__main__":
    main()
