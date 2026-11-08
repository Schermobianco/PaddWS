"""Genera la grafica della schermata HOW TO PLAY delle mosse speciali per il core MiSTer
(mister/rtl/howto_render.v): pixel art in stile Neo Geo a 320x240, come rust/game/src/moves_ui.rs.

Uso:
    python tools/gen_howto_assets.py [--preview CARTELLA]

Tre livelli, composti da howto_render.v:
- scritte (e barre del costo, "+"): righe dello schermo intere, 2 bit per pixel (0 niente,
  1 bianco, 2 grigio, 3 accento), in howto_text.hex; le righe uguali si tengono una volta sola (anche
  le coppie delle scritte grandi e le righe comuni alle varianti joystick, paddle e spinner) e la
  mappa howto_rows.hex dice quale riga va nella riga y dello schermo;
- figurine 32x32 a codici di colore (4 bit) in howto_sprites.hex: joystick inclinati, manopole con
  la freccia della rotazione, pulsante A su e giù, pulsanti piccoli della legenda. I codici "accesi"
  (pallina rossa, bordo della base, freccia della manopola) cambiano colore nel renderer quando il
  passo del gesto è acceso;
- il resto (cornici, frecce tra i passi, racchetta e palla del riquadro del tiro) in logica.

Il disegno segue l'anteprima a 320x240 (stesse coordinate e stesse primitive di Pillow).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "mister" / "rtl" / "gen"
FONT = ROOT / "assets" / "fonts" / "munro.ttf"
W, H = 320, 240
f10 = ImageFont.truetype(str(FONT), 10)
f20 = ImageFont.truetype(str(FONT), 20)

# codici delle scritte (2 bit)
T_WHITE, T_GRAY, T_ACCENT = 1, 2, 3
# codici delle figurine (4 bit): quelli segnati "acceso" dipendono dal passo acceso
S_DARK, S_HOLE, S_SHAFT, S_BALL, S_BASE_EDGE, S_WHITE = 1, 2, 3, 4, 5, 6   # pallina e bordo: acceso
S_RED, S_RED_DARK, S_RED_LIGHT, S_KNOB, S_KNOB_EDGE, S_KNOB_TOP, S_SPIN = 7, 8, 9, 10, 11, 12, 13  # freccia: acceso

# varianti: nome del controllo nel sottotitolo e comando con il joystick (False = manopola)
VARIANTS = [("JOYSTICK", True), ("PADDLE", False), ("SPINNER", False)]
MOVES = [("STRAIGHT SHOT", "NEXT SHOT FLAT AND FAST"), ("RISING STRIKE", "FLAT SHOT WITH A LATE BREAK")]
# legenda dei pulsanti
LEGEND = [("A", "DASH"), ("B", "SELECT"), ("C", "USE")]
SKIP = "PRESS START TO SKIP"

# disposizione (come l'anteprima): riquadri delle mosse da y0 = 42 + 70 * riga, comando sulla riga
# cy = y0 + 44, passi ogni 34 pixel da x = 30, riquadro del tiro da x = 204
BOX_Y0 = [42, 112]
CMD_CY = [y0 + 44 for y0 in BOX_Y0]
STEP_X0, PITCH = 30, 34
BARS_Y = 186
LEGEND_Y = 208
SKIP_Y = 232
# figurine: celle 32x32 con il centro del disegno in (AX, AY); finestra larga SLOT_W
AX, AY, CELL, SLOT_W = 11, 16, 32, 26
# figurine nell'ordine della ROM
SPRITES = ["STICK_D", "STICK_DF", "STICK_F", "SPIN_D", "SPIN_U", "BTN_A", "BTN_A_DOWN"] + \
          [f"SMALL_{i}" for i in range(len(LEGEND))]
SPR = {name: i for i, name in enumerate(SPRITES)}
# passi dei comandi per mossa: joystick (avanti = verso l'avversario, a destra) e manopola
JOY_STEPS = [["STICK_D", "STICK_DF", "STICK_F"], ["STICK_F", "STICK_D", "STICK_DF"]]
KNOB_STEPS = [["SPIN_D", "SPIN_U"], ["SPIN_U", "SPIN_D"]]
DIRS = {"STICK_D": (0, 1), "STICK_DF": (1, 1), "STICK_F": (1, 0)}


def command_x(joystick: bool) -> tuple[list[int], int, int, int]:
    """Centri dei passi, del "+", del pulsante A e inizio della scritta DASH."""
    n = 3 if joystick else 2
    steps = [STEP_X0 + PITCH * i for i in range(n)]
    x = STEP_X0 + PITCH * n
    return steps, x - 6, x + 14, x + 30


# ------------------------------------------------------------------ primitive


def paint_text(img: Image.Image, xy, s: str, font, code: int, anchor: str = "la") -> None:
    """Scritta in Munro senza sfumature: i pixel accesi prendono il codice `code`."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text(xy, s, font=font, fill=255, anchor=anchor)
    img.paste(code, (0, 0, *img.size), mask.point(lambda v: 255 if v > 127 else 0))


def text_length(s: str) -> int:
    return int(ImageDraw.Draw(Image.new("L", (1, 1))).textlength(s, font=f10))


def stick(img: Image.Image, cx: int, cy: int, way: str) -> None:
    """Joystick arcade di tre quarti: base, asta e pallina rossa inclinate nella direzione."""
    d = ImageDraw.Draw(img)
    base_y = cy + 9
    d.rounded_rectangle((cx - 11, base_y - 2, cx + 11, base_y + 4), 2, fill=S_DARK, outline=S_BASE_EDGE)
    d.ellipse((cx - 5, base_y - 3, cx + 5, base_y + 1), fill=S_HOLE)
    dx, dy = DIRS[way]
    bx, by = cx + dx * 7, cy - 6 + dy * 6
    d.line((cx, base_y - 1, bx, by), fill=S_SHAFT, width=2)
    d.ellipse((bx - 5, by - 5, bx + 5, by + 5), fill=S_BALL)
    d.point((bx - 2, by - 3), fill=S_WHITE)
    d.point((bx - 3, by - 2), fill=S_WHITE)


def spinner(img: Image.Image, cx: int, cy: int, down: bool) -> None:
    """Manopola vista dall'alto con la freccia curva della rotazione: giù = senso orario sul lato
    destro, su = antiorario. La punta della freccia è un pixel più corta che nell'anteprima, così
    le due manopole stanno nelle stesse 32 righe."""
    import math

    d = ImageDraw.Draw(img)
    d.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=S_KNOB, outline=S_KNOB_EDGE)
    d.ellipse((cx - 6, cy - 6, cx + 6, cy + 6), fill=S_KNOB_TOP)
    ang = math.radians(60 if down else -60)
    d.line((cx, cy, cx + 5 * math.sin(ang), cy - 5 * math.cos(ang)), fill=S_WHITE, width=1)
    d.arc((cx - 13, cy - 13, cx + 13, cy + 13), -50, 50, fill=S_SPIN, width=2)
    sgn = 1 if down else -1
    tip_y = cy + 10 * sgn
    d.polygon([(cx + 6, tip_y + 3 * sgn), (cx + 12, tip_y - 1 * sgn), (cx + 13, tip_y + 5 * sgn)], fill=S_SPIN)


def button(img: Image.Image, cx: int, cy: int, label: str, pressed: bool, small: bool = False) -> None:
    """Pulsante arcade rosso di tre quarti; premuto scende e si schiarisce."""
    d = ImageDraw.Draw(img)
    r = 7 if small else 9
    base_y = cy + 5
    d.ellipse((cx - r - 1, base_y - r // 2 - 1, cx + r + 1, base_y + r // 2 + 1), fill=S_HOLE)
    h = 1 if pressed else 3
    top = base_y - 2 - h
    # fianco del cilindro: chiuso in basso da un'ellisse (con il solo rettangolo sembrava tagliato)
    d.ellipse((cx - r + 2, base_y - 1 - r // 2, cx + r - 2, base_y - 1 + r // 2), fill=S_RED_DARK)
    d.rectangle((cx - r + 2, top, cx + r - 2, base_y - 1), fill=S_RED_DARK)
    d.ellipse((cx - r + 2, top - r // 2, cx + r - 2, top + r // 2), fill=S_RED_LIGHT if pressed else S_RED,
              outline=S_WHITE if pressed else None)
    paint_text(img, (cx, top), label, f10, S_WHITE, "mm")


def arrow_rows() -> list[str]:
    """Freccetta tra due passi: il triangolo (0, -3) (4, 0) (0, 3), 5 colonne per 7 righe."""
    img = Image.new("L", (5, 7), 0)
    ImageDraw.Draw(img).polygon([(0, 0), (4, 3), (0, 6)], fill=1)
    return ["".join("1" if img.getpixel((x, y)) else "0" for x in range(5)) for y in range(7)]


# ------------------------------------------------------------------ scritte


def text_layer(name: str, joystick: bool) -> Image.Image:
    """Scritte, "+" e barre del costo di una variante, codici a 2 bit."""
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    paint_text(img, (W // 2, 12), "HOW TO PLAY", f20, T_ACCENT, "mm")
    paint_text(img, (W // 2, 28), "SUPER MOVES - " + name, f10, T_GRAY, "mm")
    _, plus_x, _, dash_x = command_x(joystick)
    for (move, effect), y0, cy in zip(MOVES, BOX_Y0, CMD_CY):
        paint_text(img, (16, y0), move, f20, T_ACCENT)
        paint_text(img, (16, y0 + 18), effect, f10, T_WHITE)
        paint_text(img, (plus_x, cy), "+", f20, T_WHITE, "mm")
        paint_text(img, (dash_x, cy + 1), "DASH", f10, T_GRAY, "lm")
    # costo: mezza barra = mossa, barra piena = MAX (barre gialle come quelle pronte del gioco)
    y = BARS_Y
    for label_x, x, fill, what, what_code in ((52, 58, 18, "= MOVE", T_WHITE), (190, 196, 36, "= MAX", T_ACCENT)):
        paint_text(img, (label_x, y + 3), "HALF" if fill < 36 else "FULL", f10, T_WHITE, "rm")
        d.rectangle((x, y, x + 37, y + 5), outline=T_ACCENT)
        d.rectangle((x + 1, y + 1, x + fill, y + 4), fill=T_ACCENT)
        d.line((x + 19, y - 1, x + 19, y + 6), fill=T_ACCENT)
        paint_text(img, (x + 42, y + 3), what, f10, what_code, "lm")
    for x, (_, label) in zip(legend_x(), LEGEND):
        paint_text(img, (x + 12, LEGEND_Y), label, f10, T_GRAY, "lm")
    paint_text(img, (W // 2, SKIP_Y), SKIP, f10, T_GRAY, "mm")
    return img


def legend_x() -> list[int]:
    """Centri dei pulsanti della legenda."""
    xs, x = [], 22
    for _, label in LEGEND:
        xs.append(x)
        x += 24 + text_length(label) + 10
    return xs


def text_rows() -> tuple[list[bytes], list[list[int]], int, int]:
    """Righe distinte delle scritte, mappa (variante, y) -> riga (-1 = vuota) e righe del SKIP."""
    rows: list[bytes] = []
    index: dict[bytes, int] = {}
    maps = []
    for name, joystick in VARIANTS:
        img = text_layer(name, joystick)
        m = []
        for y in range(H):
            row = bytes(img.getpixel((x, y)) for x in range(W))
            if not any(row):
                m.append(-1)
                continue
            if row not in index:
                index[row] = len(rows)
                rows.append(row)
            m.append(index[row])
        maps.append(m)
    # righe della scritta che lampeggia (uguale in tutte le varianti)
    skip = Image.new("L", (W, H), 0)
    paint_text(skip, (W // 2, SKIP_Y), SKIP, f10, T_GRAY, "mm")
    ys = [y for y in range(H) if any(skip.getpixel((x, y)) for x in range(W))]
    return rows, maps, ys[0], ys[-1] + 1


def row_map(maps: list[list[int]]) -> list[int]:
    """ROM della mappa delle righe, indirizzo {controllo (2 bit), y (8 bit)}: bit 8 = la riga ha
    scritte, bit 7-0 = riga della striscia. Il controllo 3 (non usato dall'OSD) vale come lo spinner."""
    rom = []
    for v in range(4):
        m = maps[min(v, len(maps) - 1)]
        rom += [(0x100 | m[y]) if y < H and m[y] >= 0 else 0 for y in range(256)]
    return rom


# ------------------------------------------------------------------ figurine


def sprite_cell(name: str) -> Image.Image:
    """Figurina disegnata con il centro in (AX, AY) di una cella 32x32 (controllo: niente fuori)."""
    big = Image.new("L", (CELL * 2, CELL * 2), 0)
    cx, cy = AX + CELL // 2, AY + CELL // 2
    if name in DIRS:
        stick(big, cx, cy, name)
    elif name.startswith("SPIN"):
        spinner(big, cx, cy, name == "SPIN_D")
    elif name.startswith("BTN_A"):
        button(big, cx, cy, "A", name.endswith("DOWN"))
    else:
        button(big, cx, cy, LEGEND[int(name.split("_")[1])][0], False, small=True)
    box = big.getbbox()
    lo = CELL // 2
    assert box and box[0] >= lo and box[1] >= lo and box[2] <= lo + SLOT_W and box[3] <= lo + CELL, (name, box)
    return big.crop((lo, lo, lo + CELL, lo + CELL))


# ------------------------------------------------------------------ uscite


def vh(rows_n: int, skip: tuple[int, int]) -> str:
    joy_steps, _, joy_btn, _ = command_x(True)
    knob_steps, _, knob_btn, _ = command_x(False)
    leg = legend_x()
    p = [
        "// Generato da tools/gen_howto_assets.py: non modificare a mano.",
        "// Schermata HOW TO PLAY delle mosse speciali (howto_render.v).",
        f"localparam integer HT_TEXT_ROWS = {rows_n};          // righe di 320 pixel in howto_text.hex",
        "// howto_rows.hex: 1024 voci {controllo, y} -> bit 8 la riga ha scritte, bit 7-0 la riga",
        f"localparam integer HT_SPRITES = {len(SPRITES)};            // celle 32x32 in howto_sprites.hex",
        f"localparam integer HT_SKIP_Y0 = {skip[0]}, HT_SKIP_Y1 = {skip[1]};   // righe della scritta che lampeggia",
        "// riquadri delle mosse (cornice da y0 - 4 a y0 + 62, da x = 8 a 311), riga del comando",
        f"localparam integer HT_BOX0_Y = {BOX_Y0[0]}, HT_BOX1_Y = {BOX_Y0[1]}, HT_CY0 = {CMD_CY[0]}, HT_CY1 = {CMD_CY[1]};",
        "// figurine: centro del disegno nella cella (AX, AY), larghezza della finestra di un posto",
        f"localparam integer HT_AX = {AX}, HT_AY = {AY}, HT_SLOT_W = {SLOT_W};",
        "// centri dei passi e del pulsante A: joystick (3 passi) e manopola (2 passi)",
        f"localparam integer HT_JOY_S0 = {joy_steps[0]}, HT_JOY_S1 = {joy_steps[1]}, HT_JOY_S2 = {joy_steps[2]}, HT_JOY_A = {joy_btn};",
        f"localparam integer HT_KNOB_S0 = {knob_steps[0]}, HT_KNOB_S1 = {knob_steps[1]}, HT_KNOB_A = {knob_btn};",
        "// freccette tra i passi: colonna di sinistra (centro del passo + 15), righe da cy - 3",
        f"localparam integer HT_ARROW_DX = {PITCH // 2 - 2};",
        "// legenda: centri dei pulsanti piccoli sulla riga HT_LEG_CY",
        f"localparam integer HT_LEG_CY = {LEGEND_Y - 3}, HT_LEG_X0 = {leg[0]}, HT_LEG_X1 = {leg[1]}, HT_LEG_X2 = {leg[2]};",
        "// figurine",
    ]
    p += [f"localparam [3:0] HT_{name} = 4'd{i};" for i, name in enumerate(SPRITES)]
    p.append("// codici dei colori delle figurine (pallina, bordo della base e freccia della manopola: accesi o spenti)")
    for code, name in ((S_DARK, "DARK"), (S_HOLE, "HOLE"), (S_SHAFT, "SHAFT"), (S_BALL, "BALL"), (S_BASE_EDGE, "BASE_EDGE"),
                       (S_WHITE, "WHITE"), (S_RED, "RED"), (S_RED_DARK, "RED_DARK"), (S_RED_LIGHT, "RED_LIGHT"),
                       (S_KNOB, "KNOB"), (S_KNOB_EDGE, "KNOB_EDGE"), (S_KNOB_TOP, "KNOB_TOP"), (S_SPIN, "SPIN")):
        p.append(f"localparam [3:0] HS_{name} = 4'd{code};")
    p.append("// freccetta tra i passi, 5x7 (bit 4 = colonna di sinistra)")
    p.append("function [4:0] ht_arrow_row(input [2:0] row);")
    p.append("    case (row)")
    p += [f"        3'd{y}: ht_arrow_row = 5'b{bits};" for y, bits in enumerate(arrow_rows())]
    p += ["        default: ht_arrow_row = 5'd0;", "    endcase", "endfunction"]
    return "\n".join(p) + "\n"


def preview(out: Path, rows: list[bytes], maps: list[list[int]], cells: list[Image.Image]) -> None:
    """Strati statici di ogni variante e foglio delle figurine, ingranditi 3 volte."""
    pal = [(0, 0, 0), (255, 255, 255), (150, 150, 150), (255, 210, 37)]
    out.mkdir(parents=True, exist_ok=True)
    for (name, _), m in zip(VARIANTS, maps):
        img = Image.new("RGB", (W, H))
        for y in range(H):
            if m[y] >= 0:
                for x in range(W):
                    img.putpixel((x, y), pal[rows[m[y]][x]])
        img.resize((W * 3, H * 3), Image.NEAREST).save(out / f"text_{name.lower()}.png")
    spal = [(0, 0, 0), (55, 55, 60), (25, 25, 25), (190, 190, 195), (230, 40, 40), (255, 210, 37), (255, 255, 255),
            (230, 40, 40), (140, 20, 20), (255, 110, 110), (30, 30, 35), (110, 110, 115), (80, 80, 88), (255, 210, 37)]
    sheet = Image.new("RGB", (CELL * len(cells), CELL), (40, 0, 40))
    for i, c in enumerate(cells):
        for y in range(CELL):
            for x in range(CELL):
                v = c.getpixel((x, y))
                if v:
                    sheet.putpixel((i * CELL + x, y), spal[v])
    sheet.resize((sheet.width * 6, CELL * 6), Image.NEAREST).save(out / "sprites.png")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--preview", type=Path, help="cartella per le anteprime PNG")
    args = ap.parse_args()
    rows, maps, sk0, sk1 = text_rows()
    assert len(rows) <= 256
    cells = [sprite_cell(name) for name in SPRITES]
    (GEN / "howto_text.hex").write_text("".join(f"{v:x}\n" for row in rows for v in row), encoding="ascii")
    (GEN / "howto_rows.hex").write_text("".join(f"{v:03x}\n" for v in row_map(maps)), encoding="ascii")
    (GEN / "howto_sprites.hex").write_text(
        "".join(f"{c.getpixel((x, y)):x}\n" for c in cells for y in range(CELL) for x in range(CELL)), encoding="ascii")
    (GEN / "pong_howto.vh").write_text(vh(len(rows), (sk0, sk1)), encoding="utf-8")
    if args.preview:
        preview(args.preview, rows, maps, cells)
    print(f"{GEN}: {len(rows)} righe di scritte ({len(rows) * W * 2} bit), {len(cells)} figurine "
          f"({len(cells) * CELL * CELL * 4} bit)")


if __name__ == "__main__":
    main()
