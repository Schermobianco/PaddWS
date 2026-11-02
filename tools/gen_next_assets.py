"""Genera mister/rtl/gen/pong_next.vh: icone e scritte della modalità NEXT per il core MiSTer.

Uso:
    python tools/gen_next_assets.py

Le icone 9x9 sono le stesse di rust/game/src/next_ui.rs (stesso ordine dei codici dei bonus:
0 TELEPORT, 1 SMASH, 2 SLOW, 3 CURVE, 4 GHOST, 5 SUPER, 6 STEER, 7 BULLET); le scritte usano il font Munro a 10 px
come quelle dell'attract (tools/gen_attract_assets.py), con una linea di base comune. Per le mosse
speciali: i loro nomi, "MAX" davanti al nome della mossa di livello 2 e i segni 9x9 della mossa
armata accanto alla racchetta (SPECIAL_ICONS di next_ui.rs, per il giocatore di sinistra: quello di
destra li specchia). La schermata HOW TO PLAY ha un generatore suo, tools/gen_howto_assets.py.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from gen_attract_assets import verilog_rom

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mister" / "rtl" / "gen" / "pong_next.vh"

ICONS = [
    ["#.......#", "#.......#", "#....#..#", "#.....#.#", "#.#######", "#.....#.#", "#....#..#", "#.......#", "#.......#"],
    ["......##.", ".....##..", "....##...", "...##....", "..######.", "....##...", "...##....", "..##.....", ".##......"],
    ["#########", ".#.....#.", "..#...#..", "...#.#...", "....#....", "...#.#...", "..#.#.#..", ".#.###.#.", "#########"],
    ["......###", ".....####", "....#.###", "...#.....", "..#......", "..#......", "..#......", "...#.....", "....####."],
    ["..#.#.#..", ".........", "#.......#", ".........", "#...#...#", ".........", "#.......#", ".........", "..#.#.#.."],
    ["#...#...#", ".#..#..#.", "..#.#.#..", "...###...", "#########", "...###...", "..#.#.#..", ".#..#..#.", "#...#...#"],
    ["..#####..", ".#.....#.", "#.......#", "#.......#", "#########", "#...#...#", "#...#...#", ".#..#..#.", "..#####.."],
    ["..#......", ".#..#....", "#..#.....", "#.#.####.", "#.#.#####", "#.#.####.", "#..#.....", ".#..#....", "..#......"],
]

# BULLET (codice 7) arriva solo dalle capsule; nel core MiSTer i codici dei bonus sono a 4 bit e il
# posto vuoto è 8 (vedi rust/trace, `bonus_code`)
NAMES = ["TELEPORT", "SMASH", "SLOW", "CURVE", "GHOST", "SUPER", "STEER", "BULLET"]
# mosse speciali, nell'ordine dei codici di `Special` meno 1
MOVES = ["STRAIGHT SHOT", "RISING STRIKE"]
# segni della mossa armata, nell'ordine dei codici di `Special` meno 1 (come SPECIAL_ICONS di next_ui.rs)
SPECIAL_ICONS = [
    ["....#....", ".....#...", "......#..", ".......#.", "#.#######", ".......#.", "......#..", ".....#...", "....#...."],
    ["...######", ".......##", "......#.#", ".....#..#", "....#...#", "...#.....", "..#......", ".#.......", "#........"],
]
# tipi di racchetta, nell'ordine di `PaddleKind`, con la frase della schermata di scelta
KINDS = ["ARCADE", "TITAN", "HAMMER", "TWIST", "BLASTER", "RUSH", "GUARDIAN"]
TAGS = ["MORE BONUSES", "TALL BUT SLOW", "POWER SHOTS", "TILTS WITH SPEED", "SHOOTS CAPSULES", "LONG DASH",
        "FIVE-PIECE WALL"]
STRINGS = {
    "nx_pick": "PICK 3 BONUSES",
    "nx_ready": "READY!",
    "nx_p1": "P1",
    "nx_p2": "P2",
    "nx_cpu": "CPU",
    "nx_of3": "/3",
    "nx_cursor": ">",
    "nx_bang": "!",
    **{f"nx_name{i}": name for i, name in enumerate(NAMES)},
    "nx_ppick": "PICK YOUR PADDLE",
    "nx_ok": "OK",
    **{f"nx_kind{i}": name for i, name in enumerate(KINDS)},
    **{f"nx_tag{i}": tag for i, tag in enumerate(TAGS)},
    **{f"nx_move{i}": name for i, name in enumerate(MOVES)},
    "nx_max": "MAX",
}


def text_masks() -> dict[str, Image.Image]:
    font = ImageFont.truetype(str(ROOT / "assets/fonts/munro.ttf"), 10)
    ascent, descent = font.getmetrics()
    raw = {}
    for name, text in STRINGS.items():
        w = max(1, round(font.getlength(text)))
        img = Image.new("L", (w + 4, ascent + descent), 0)
        ImageDraw.Draw(img).text((0, 0), text, font=font, fill=255)
        raw[name] = (w, img.point(lambda v: 255 if v > 127 else 0))
    # righe comuni a tutte le scritte (stessa linea di base), come nell'attract
    rows = [y for y in range(ascent + descent)
            if any(img.getpixel((x, y)) for _, img in raw.values() for x in range(img.width))]
    top, bottom = rows[0], rows[-1]
    return {name: img.crop((0, top, w, bottom + 1)).convert("1") for name, (w, img) in raw.items()}


def icon_rom() -> str:
    lines = ["// icone 9x9 dei bonus: riga `row` dell'icona `bonus` (bit 8 = colonna di sinistra)",
             "function [8:0] icon_row(input [2:0] bonus, input [3:0] row);", "    case ({bonus, row})"]
    for b, icon in enumerate(ICONS):
        for r, text in enumerate(icon):
            bits = text.replace("#", "1").replace(".", "0")
            if "1" in bits:
                lines.append(f"        {{3'd{b}, 4'd{r}}}: icon_row = 9'b{bits};")
    lines += ["        default: icon_row = 9'd0;", "    endcase", "endfunction",
              "function icon_lit(input [2:0] bonus, input [9:0] dx, input [9:0] dy);",
              "    reg [8:0] r;",
              "    begin",
              "        r = icon_row(bonus, dy[3:0]);",
              "        icon_lit = (dx < 9 && dy < 9) ? r[8 - dx] : 1'b0;",
              "    end",
              "endfunction"]
    return "\n".join(lines) + "\n"


def special_rom() -> str:
    lines = ["// segni 9x9 della mossa armata: riga `row` del segno della mossa `m` (0 STRAIGHT SHOT,",
             "// 1 RISING STRIKE; bit 8 = colonna di sinistra, per il giocatore di sinistra)",
             "function [8:0] special_row(input m, input [3:0] row);", "    case ({m, row})"]
    for m, icon in enumerate(SPECIAL_ICONS):
        for r, text in enumerate(icon):
            bits = text.replace("#", "1").replace(".", "0")
            if "1" in bits:
                lines.append(f"        {{1'd{m}, 4'd{r}}}: special_row = 9'b{bits};")
    lines += ["        default: special_row = 9'd0;", "    endcase", "endfunction",
              "function special_lit(input m, input [9:0] dx, input [9:0] dy);",
              "    reg [8:0] r;",
              "    begin",
              "        r = special_row(m, dy[3:0]);",
              "        special_lit = (dx < 9 && dy < 9) ? r[8 - dx] : 1'b0;",
              "    end",
              "endfunction"]
    return "\n".join(lines) + "\n"


def names_rom(masks: dict[str, Image.Image], func: str, prefix: str, count: int, arg: str, bits: int) -> str:
    """Scritta per codice (nome di un bonus, di un tipo di racchetta, frase): larghezza e pixel acceso."""
    lines = [f"function [{bits - 1}:0] {func}_w(input [2:0] {arg});", f"    case ({arg})"]
    lines += [f"        3'd{i}: {func}_w = {masks[f'{prefix}{i}'].size[0]};" for i in range(count)]
    lines += [f"        default: {func}_w = 0;", "    endcase", "endfunction",
              f"function {func}_lit(input [2:0] {arg}, input [9:0] dx, input [9:0] dy);",
              f"    case ({arg})"]
    lines += [f"        3'd{i}: {func}_lit = {prefix}{i}_lit(dx, dy);" for i in range(count)]
    lines += [f"        default: {func}_lit = 1'b0;", "    endcase", "endfunction"]
    return "\n".join(lines) + "\n"


def sin_rom() -> str:
    """Seno in Q8 (256 = 1) su 64 passi per giro: la racchetta che ruota con il SUPER."""

    lines = ["function signed [9:0] sin_q8(input [5:0] i);", "    case (i)"]
    lines += [f"        6'd{i}: sin_q8 = {round(256 * math.sin(2 * math.pi * i / 64))};" for i in range(64)]
    lines += ["    endcase", "endfunction"]
    return "\n".join(lines) + "\n"


def main() -> None:
    masks = text_masks()
    parts = ["// Generato da tools/gen_next_assets.py: non modificare a mano.\n", icon_rom(), special_rom(), sin_rom()]
    parts += [verilog_rom(name, mask) for name, mask in masks.items()]
    parts.append(names_rom(masks, "name", "nx_name", len(NAMES), "bonus", 6))
    parts.append(names_rom(masks, "kind_name", "nx_kind", len(KINDS), "kind", 7))
    parts.append(names_rom(masks, "tag", "nx_tag", len(TAGS), "kind", 7))
    parts.append(names_rom(masks, "move", "nx_move", len(MOVES), "move", 7))
    OUT.write_text("\n".join(parts), encoding="utf-8")
    sizes = ", ".join(f"{n} {m.size[0]}x{m.size[1]}" for n, m in masks.items())
    print(f"{OUT}: {len(ICONS)} icone, {sizes}")


if __name__ == "__main__":
    main()
