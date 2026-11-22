"""Genera mister/rtl/gen/pong_paddles.vh: sprite, colori e tabelle delle racchette dei personaggi
del core MiSTer (kind_px e muro del GUARDIAN in mister/rtl/next_render.v).

Gli sprite sono quelli di assets/ships/sprites (letti da tools/paddle_shapes.py con le regole di
rust/game/src/ships.rs) sulle colonne del MiSTer: si toglie la colonna subito dietro la faccia del
PC. Ne escono le righe di ruoli (`sp_px`) e le costanti delle animazioni: agganci dei motori, delle
armi e speciali, settori del GUARDIAN, cabina di ARCADE, canne e indicatore dei colpi del BLASTER.
Da rilanciare dopo ogni ritocco agli sprite.

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


def sprites() -> list[str]:
    """Sprite delle astronavi sulle colonne del MiSTer e costanti delle animazioni."""
    import re
    vh = (OUT.parent / "pong_params.vh").read_text(encoding="utf-8")
    heights = [int(re.search(rf"3'd{k}: kind_px_h = (\d+);", vh).group(1)) for k in range(7)]
    ships = [ps.ship(k) for k in range(7)]
    for k, s in enumerate(ships):
        assert s.h == heights[k], f"{ps.KINDS[k]}: sprite alto {s.h}, la racchetta {heights[k]}"
    out = ["// ------------------------------------------------- sprite delle astronavi",
           "// Righe dello sprite del tipo k (assets/ships/sprites) sulle colonne del MiSTer (u con la faccia a 0;",
           "// la colonna del PC subito dietro la faccia e' tolta): 4 bit per pixel, il ruolo KR_*, la colonna",
           "// SP_U0_k nei bit 3:0. Gli agganci sono gia' tolti (sono le costanti piu' sotto)."]
    widths = []
    for k, s in enumerate(ships):
        u0, u1 = s.u_range()
        cols = [u for u in range(u0, u1 + 1) if ps.col(u, 4) is not None]
        mu = [ps.col(u, 4) for u in cols]
        assert mu == list(range(mu[0], mu[0] + len(mu))), "colonne contigue"
        w = len(cols)
        widths.append(w)
        out.append(f"localparam integer SP_U0_{k} = {mu[0]}, SP_W_{k} = {w}, SP_H_{k} = {s.h};")
        out.append(f"function [{4 * w - 1}:0] sp_row{k}(input [5:0] v);")
        out.append("    case (v)")
        for v in range(s.h):
            val = sum(s.at(u, v) << (4 * i) for i, u in enumerate(cols))
            if val:
                out.append(f"        6'd{v}: sp_row{k} = {4 * w}'h{val:0{w}X};")
        out += [f"        default: sp_row{k} = {4 * w}'d0;", "    endcase", "endfunction"]
    out += [f"localparam integer SP_WMAX = {max(widths)};",
            "// ruolo dello sprite del tipo `kind` al pixel (u, v), KR_NONE fuori",
            "function [3:0] sp_px(input [2:0] kind, input signed [11:0] u, input signed [11:0] v);",
            "    reg [4*SP_WMAX-1:0] row;",
            "    reg signed [11:0] c;",
            "    reg in;",
            "    begin",
            "        row = {4*SP_WMAX{1'b0}};",
            "        c = 12'sd0;",
            "        in = 1'b0;",
            "        case (kind)"]
    for k in range(7):
        out.append(f"            3'd{k}: begin c = u - SP_U0_{k}; in = c >= 0 && c < SP_W_{k} && v >= 0 && v < SP_H_{k}; "
                   f"row = sp_row{k}(v[5:0]); end")
    out += ["            default: in = 1'b0;", "        endcase",
            "        sp_px = in ? row[{c[5:0], 2'b00} +: 4] : 4'd0;", "    end", "endfunction"]

    def table(name: str, rows: list[tuple[int, int, int]]) -> list[str]:
        t = [f"function signed [11:0] {name}(input [2:0] kind, input [1:0] i);", "    case ({kind, i})"]
        t += [f"        {{3'd{k}, 2'd{i}}}: {name} = {v};" for k, i, v in rows]
        t += [f"        default: {name} = 12'sd0;", "    endcase", "endfunction"]
        return t
    out.append("// agganci dei motori e speciali (TWIST: getti di manovra, RUSH: scie alari), dall'alto: numero,")
    out.append("// colonna dell'ugello (quella subito davanti all'aggancio), prima riga e righe del getto")
    for name, attr in (("eng", "engines"), ("spc", "specials")):
        lists = [getattr(s, attr) for s in ships]
        out.append(f"function [1:0] sp_{name}_n(input [2:0] kind);")
        out.append("    case (kind)")
        out += [f"        3'd{k}: sp_{name}_n = 2'd{len(a)};" for k, a in enumerate(lists) if a]
        out += [f"        default: sp_{name}_n = 2'd0;", "    endcase", "endfunction"]
        for fld, fn in (("x", lambda a: ps.col(a.u, 4) + 1), ("y", lambda a: a.v), ("r", lambda a: a.rows)):
            out += table(f"sp_{name}_{fld}", [(k, i, fn(a)) for k, al in enumerate(lists) for i, a in enumerate(al)])
    b = ships[ps.BLASTER]
    assert len(b.weapons) == 2, "BLASTER: due agganci delle armi"
    barrel = b.front() - 1
    g0, g1 = b.mark_rows
    lit = [g1 + 1 - ps.jround(f / 19 * (g1 - g0 + 1)) for f in (0, 3, 6, 9, 13, 16, 19)]
    w0 = b.weapons[0]
    gun = ps.jround(abs(b.h / 2 - (w0.v + w0.rows / 2)))
    out.append("// BLASTER: agganci delle armi (colonna e righe, davanti alle bocche), colonne delle canne, prima")
    out.append("// riga accesa dell'indicatore dei colpi (il verde fino alla faccia) per i colpi nel caricatore e")
    out.append("// distanza dei due fasci dal centro della racchetta")
    out.append(f"localparam integer SP_GUN_X0 = {ps.col(b.weapons[0].u, 4)}, SP_GUN_Y0 = {b.weapons[0].v}, "
               f"SP_GUN_R0 = {b.weapons[0].rows},")
    out.append(f"                   SP_GUN_X1 = {ps.col(b.weapons[1].u, 4)}, SP_GUN_Y1 = {b.weapons[1].v}, "
               f"SP_GUN_R1 = {b.weapons[1].rows}, SP_BARREL = {barrel}, BGUN_DY = {gun};")
    out.append("function signed [11:0] bl_lit(input [2:0] ammo);")
    out.append("    case (ammo)")
    out += [f"        3'd{a}: bl_lit = {v};" for a, v in enumerate(lit)]
    out += [f"        default: bl_lit = {lit[6]};", "    endcase", "endfunction"]
    out.append("// ARCADE: prima colonna della cabina (i pixel nel colore del personaggio)")
    out.append(f"localparam integer SP_CAB_U0 = {ps.col(ships[ps.ARCADE].mark_u0, 4)};")
    sec = ships[ps.GUARDIAN].sectors
    out.append("// GUARDIAN: righe [y0, y1) delle cinque piastre (i pezzi tra le giunture dello sprite); le giunture")
    out.append("// tra una piastra e l'altra vanno con quella sotto")
    out.append("function signed [11:0] gs_y0(input [2:0] c);")
    out.append("    case (c)")
    out += [f"        3'd{c}: gs_y0 = {y0};" for c, (y0, _) in enumerate(sec)]
    out += ["        default: gs_y0 = 12'sd0;", "    endcase", "endfunction",
            "function signed [11:0] gs_y1(input [2:0] c);", "    case (c)"]
    out += [f"        3'd{c}: gs_y1 = {y1};" for c, (_, y1) in enumerate(sec)]
    out += ["        default: gs_y1 = 12'sd0;", "    endcase", "endfunction"]
    return out


def main() -> None:
    lines = ["// Generato da tools/gen_mister_paddles.py: non modificare a mano.",
             "// Colori e tabelle delle racchette dei personaggi (next_render.v).",
             f"localparam integer PD_HIT_FRAMES = {HIT_FRAMES}, PD_FIRE_FRAMES = {FIRE_FRAMES}, "
             f"PD_CRACK_FRAMES = {CRACK_FRAMES}, PD_BREAK_FRAMES = {BREAK_FRAMES},",
             f"                   PD_BLINK_FRAMES = {BLINK_FRAMES}, PD_BARRIER_FRAMES = {BARRIER_FRAMES};"]
    for part in (colors(), sprites(), sparks(), ring(), casing(), build(), chips(), crumble()):
        lines += [""] + part
    # file generati del MiSTer in ASCII: le lettere accentate dei commenti con l'apostrofo
    text = "\n".join(lines) + "\n"
    for c, r in zip("àèéìòù", ("a'", "e'", "e'", "i'", "o'", "u'")):
        text = text.replace(c, r)
    OUT.write_text(text, encoding="ascii", newline="\n")
    print(OUT)


if __name__ == "__main__":
    main()
