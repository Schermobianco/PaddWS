"""Genera mister/rtl/gen/pong_challenge.vh: scritte della modalità CHALLENGE per il core MiSTer.

Uso:
    python tools/gen_challenge_assets.py

Scritte fisse in Munro a 10 px come quelle di NEXT (tools/gen_next_assets.py), con la stessa linea
di base, più un font a celle di larghezza fissa per le parti che cambiano (punteggi, livello,
iniziali, conto alla rovescia): codici 0-9 cifre, 10-35 lettere, 36 spazio, 37 "+", 38 ".", 39 "x",
40 "!" (l'ultima lettera delle iniziali, aggiunta in fondo: i codici di prima non cambiano).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from gen_attract_assets import verilog_rom

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mister" / "rtl" / "gen" / "pong_challenge.vh"
LEVELS = 7

STRINGS = {
    **{f"ch_intro{i}": f"LEVEL {i + 1} OF {LEVELS}" for i in range(LEVELS - 1)},
    f"ch_intro{LEVELS - 1}": "FINAL LEVEL",
    **{f"ch_clear{i}": f"LEVEL {i + 1} CLEAR" for i in range(LEVELS - 1)},
    f"ch_clear{LEVELS - 1}": "CHAMPION!",
    "ch_first": "FIRST TO",   # il numero dei punti viene da rung_points
    "ch_score": "SCORE",
    "ch_hi": "HI",
    "ch_win": "WIN BONUS",
    "ch_perfect": "PERFECT",
    "ch_beat": "YOU BEAT EVERY PADDLE",
    "ch_press": "PRESS START",
    "ch_coin": "INSERT COIN",
    "ch_cont": "CONTINUE?",
    "ch_reset": "SCORE RESETS TO 0",
    "ch_record": "NEW RECORD!",
    "ch_enter": "ENTER YOUR INITIALS",
    "ch_hint": "UP DOWN TO CHOOSE, A TO CONFIRM",
    "ch_table": "CHALLENGE HIGH SCORES",
    # un secondo giocatore entra durante la scalata (schermata a scala 4)
    "ch_here": "HERE COMES",
    "ch_newch": "A NEW CHALLENGER!",
}

GLYPHS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ +.x!"


def render(font: ImageFont.FreeTypeFont, text: str) -> tuple[int, Image.Image]:
    ascent, descent = font.getmetrics()
    w = max(1, round(font.getlength(text)))
    img = Image.new("L", (w + 4, ascent + descent), 0)
    ImageDraw.Draw(img).text((0, 0), text, font=font, fill=255)
    return w, img.point(lambda v: 255 if v > 127 else 0)


def main() -> None:
    font = ImageFont.truetype(str(ROOT / "assets/fonts/munro.ttf"), 10)
    raw = {name: render(font, text) for name, text in STRINGS.items()}
    glyphs = [render(font, c) for c in GLYPHS]
    # righe comuni a scritte e glifi (stessa linea di base)
    every = list(raw.values()) + glyphs
    height = every[0][1].height
    rows = [y for y in range(height) if any(img.getpixel((x, y)) for _, img in every for x in range(img.width))]
    top, bottom = rows[0], rows[-1]
    masks = {name: img.crop((0, top, w, bottom + 1)).convert("1") for name, (w, img) in raw.items()}
    cell = max(w for w, _ in glyphs) + 1
    gh = bottom - top + 1

    parts = ["// Generato da tools/gen_challenge_assets.py: non modificare a mano.\n"]
    parts += [verilog_rom(name, mask) for name, mask in masks.items()]
    # famiglie per livello: titolo della presentazione e del livello superato
    for fam in ("ch_intro", "ch_clear"):
        lines = [f"function [8:0] {fam}_w(input [2:0] lvl);", "    case (lvl)"]
        lines += [f"        3'd{i}: {fam}_w = {masks[f'{fam}{i}'].size[0]};" for i in range(LEVELS)]
        lines += [f"        default: {fam}_w = 0;", "    endcase", "endfunction",
                  f"function {fam}_lit(input [2:0] lvl, input [9:0] dx, input [9:0] dy);", "    case (lvl)"]
        lines += [f"        3'd{i}: {fam}_lit = {fam}{i}_lit(dx, dy);" for i in range(LEVELS)]
        lines += [f"        default: {fam}_lit = 1'b0;", "    endcase", "endfunction"]
        parts.append("\n".join(lines) + "\n")
    # font a celle: riga `row` del glifo `code`, centrato nella cella
    lines = [f"localparam CH_CELL = {cell};", f"localparam CH_GLYPH_H = {gh};",
             f"function [{cell - 1}:0] glyph_row(input [5:0] code, input [3:0] row);",
             "    case ({code, row})"]
    for code, (w, img) in enumerate(glyphs):
        g = img.crop((0, top, w, bottom + 1))
        ox = (cell - 1 - w) // 2
        for y in range(gh):
            bits = ["0"] * cell
            for x in range(w):
                if g.getpixel((x, y)):
                    bits[ox + x] = "1"
            if "1" in bits:
                lines.append(f"        {{6'd{code}, 4'd{y}}}: glyph_row = {cell}'b{''.join(bits)};")
    lines += [f"        default: glyph_row = {cell}'d0;", "    endcase", "endfunction",
              "function glyph_lit(input [5:0] code, input [9:0] dx, input [9:0] dy);",
              f"    reg [{cell - 1}:0] r;", "    begin",
              "        r = glyph_row(code, dy[3:0]);",
              f"        glyph_lit = (dx < {cell} && dy < {gh}) ? r[{cell - 1} - dx] : 1'b0;",
              "    end", "endfunction"]
    parts.append("\n".join(lines) + "\n")
    OUT.write_text("\n".join(parts), encoding="utf-8", newline="\n")
    sizes = ", ".join(f"{n} {m.size[0]}" for n, m in masks.items())
    print(f"{OUT}: cella {cell}x{gh}, {sizes}")


if __name__ == "__main__":
    main()
