"""Genera mister/rtl/gen/pong_challenge.vh: scritte della modalità CHALLENGE per il core MiSTer.

Uso:
    python tools/gen_challenge_assets.py

Scritte fisse in Press Start 2P a 8 px come quelle di NEXT (tools/gen_next_assets.py), più lo stesso
font in celle di 8x8 pixel per le parti che cambiano (punteggi, livello, iniziali, conto alla
rovescia): codici 0-9 cifre, 10-35 lettere, 36 spazio, 37 "+", 38 ".", 39 "x", 40 "!" (l'ultima
lettera delle iniziali, aggiunta in fondo: i codici di prima non cambiano).
"""

from __future__ import annotations

from pathlib import Path

from gen_attract_assets import CELL, text_mask, verilog_rom

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mister" / "rtl" / "gen" / "pong_challenge.vh"
LEVELS = 7

STRINGS = {
    **{f"ch_intro{i}": f"LEVEL {i + 1} OF {LEVELS}" for i in range(LEVELS - 1)},
    f"ch_intro{LEVELS - 1}": "FINAL LEVEL",
    **{f"ch_clear{i}": f"LEVEL {i + 1} CLEAR" for i in range(LEVELS - 1)},
    f"ch_clear{LEVELS - 1}": "CHAMPION!",
    "ch_train": "TRAINING",   # titolo della presentazione nell'allenamento, al posto di LEVEL n OF 7
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
    "ch_table": "HIGH SCORES",
    # un secondo giocatore entra durante la scalata (schermata a scala 4)
    "ch_here": "HERE COMES",
    "ch_newch": "A NEW CHALLENGER!",
}

GLYPHS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ +.x!"


def main() -> None:
    masks = {name: text_mask(text) for name, text in STRINGS.items()}
    # celle del font: il glifo nelle prime 7 colonne, l'ottava è lo spazio fra i caratteri
    glyphs = [text_mask(c).crop((0, 0, CELL, CELL)) for c in GLYPHS]
    cell, gh = CELL, CELL

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
    # font a celle: riga `row` del glifo `code` (colonne 0-6, la 7 è lo spazio)
    lines = [f"localparam CH_CELL = {cell};", f"localparam CH_GLYPH_H = {gh};",
             f"function [{cell - 1}:0] glyph_row(input [5:0] code, input [3:0] row);",
             "    case ({code, row})"]
    for code, g in enumerate(glyphs):
        for y in range(gh):
            bits = ["1" if g.getpixel((x, y)) else "0" for x in range(cell)]
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
