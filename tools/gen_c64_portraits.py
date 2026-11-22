"""Schermate dei personaggi del C64 (4.5.0): la scelta della racchetta di NEXT con i ritratti, come
rust/game/src/paddle_ui.rs `PaddlePick::draw`, lo schermo VS e la sfilata del finale. Bitmap hires
(2 colori per cella 8x8), le righe dei ritratti in bitmap multicolor (pixel doppi, nero e 3 colori
per cella 4x8): kpick.s, kvs.s e parade.s accendono il multicolor solo lì, con lo split del raster.

Parte dai ritratti multicolor per il C64 di tools/gen_portraits.py (assets/characters/portraits/c64mc)
e dai nomi disegnati di assets/titles (qui con ombre e scie: la bitmap tiene due
colori per cella, ogni cella prende la coppia che li rende meglio). Le scritte (titolo, P1/P2/CPU, OK,
frasi, comandi, READY!, tempo) non sono nei file: le scrive il programma con i glifi della ROM dei
caratteri (c64/src/kpick.s), qui le loro celle hanno solo il colore.

Uscite in c64/gen:
  kpick.bin   nella cartuccia dal banco KP_BANK (tools/make_crt.py, dopo il codice di kpick.s):
              lo sfondo (31 pagine di bitmap da $E000, 4 di colori da $C000, 4 di Color RAM da
              $D800), poi i pannelli dei sette tipi, prima per il lato sinistro e poi per il destro
              (ritratto specchiato, multicolor, da c64mc/): 17 righe di celle da 11, per riga 88 byte
              di bitmap, 11 di colori e 11 di Color RAM, ogni pannello da una pagina nuova; li usano
              la scelta e lo schermo VS
  kpick.inc   costanti per kpick.s

Uso:  .venv\\Scripts\\python tools\\gen_c64_portraits.py   (richiede Pillow)
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_c64_assets import C64_RGB, TITLE_SPEC, title_roles  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PORTRAITS = ROOT / "assets" / "characters" / "portraits" / "c64mc"
OUT = ROOT / "c64" / "gen"

NAMES = ["arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian"]
C_BLACK, C_WHITE, C_RED, C_PURPLE, C_YELLOW, C_ORANGE, C_BROWN = 0, 1, 2, 4, 7, 8, 9
C_DGRAY, C_GRAY, C_LGRAY = 11, 12, 15

# disposizione (paddle_ui.rs, in celle del C64 a partire dalla riga TOP del campo 320x240)
PORTRAIT_COL = (0, 29)          # ritratti grandi 11x13 celle dalla riga 5
PORTRAIT_ROW = 5
PANEL_W, PANEL_H = 11, 17       # pannello: il ritratto e sotto il nome (righe 18-21)
NAME_CY = 160                   # centro del nome (pixel)
GRID_X, GRID_Y, CELL = 96, 40, 32
NET_X, COURT_Y, COURT_H = 159, 104, 72
TITLE_ROW = 0
LABEL_ROW, LABEL_COL, OK_COL = 4, (4, 33), (8, 30)
TAG_ROW, TAG_COL = 22, (2, 22)  # frasi del tipo: 16 caratteri centrati nella metà
HINT_ROW, HINT_COL = 24, (3, 23)
HINT_LEN = 14                   # " STICK + FIRE "
READY_COL = 17                  # READY! al centro
TIMER_ROW, TIMER_COL = 2, 17    # due cifre del punteggio (3x3 caratteri, draw_secs)
SPRITE_ROW = 23                 # riga vuota (colori neri): le immagini degli sprite (cursore,
                                # riquadri delle sigle, poi le sigle, che fa il programma)
MC_ROW0, MC_ROW1 = 5, 17        # righe di celle in multicolor: ritratti, griglia e campo fin sopra
                                # il nome (lo split del raster di kpick.s)

# ruoli dei titoli -> colori del C64 (titles.rs paint: l'accento è il giallo del C64)
TITLE_C64 = {"black": C_BLACK, "white": C_WHITE, "yellow": C_YELLOW, "dark_yellow": C_ORANGE,
             "gray": C_GRAY, "dark_gray": C_DGRAY, "red": C_RED, "dark_red": C_BROWN}

# punto di domanda della casella di OMEGA (disegnato qui: niente glifi della ROM nei file), a
# pixel doppi per le righe multicolor (una X = due pixel)
QUESTION_MC = [
    ".XX.",
    "X..X",
    "...X",
    "..X.",
    ".X..",
    ".X..",
    "....",
    ".X..",
    ".X..",
]

Img = list[list[int]]           # numeri dei colori del C64, righe di pixel


def blank(w: int, h: int) -> Img:
    return [[C_BLACK] * w for _ in range(h)]


def paste(dst: Img, src: Img, x0: int, y0: int, transparent: int | None = None) -> None:
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c != transparent:
                dst[y0 + y][x0 + x] = c


def png(name: str) -> Img:
    im = Image.open(PORTRAITS / f"{name}.png")
    assert im.mode == "P", name
    w, h = im.size
    return [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]


def mirror(img: Img) -> Img:
    return [row[::-1] for row in img]


def name_art(kind: str) -> Img:
    """Il nome disegnato del tipo, nei colori del C64; trasparente = -1."""
    roles = TITLE_SPEC["palette"]
    px = title_roles(f"name_{kind}")
    # le ombre (giallo e rosso scuri) si tolgono, come nelle presentazioni del C64; il giallo scuro
    # resta dove è disegno: le travi di TITAN e la malta di GUARDIAN
    drop = {"transparent", "dark_red"} | ({"dark_yellow"} if kind not in ("titan", "guardian") else set())
    return [[-1 if roles[r] in drop else TITLE_C64[roles[r]] for r in row] for row in px]


def dist(a: int, b: int) -> int:
    return sum((p - q) ** 2 for p, q in zip(C64_RGB[a], C64_RGB[b]))


def cell_bitmap(img: Img, cx: int, cy: int, force: tuple[int, int] | None = None) -> tuple[bytes, int, int]:
    """Gli 8 byte e il colore (fg << 4 | bg) della cella (cx, cy) di img, con la coppia di colori
    (il nero compreso) che la rende meglio, o quella data; poi l'errore (0 se esatta)."""
    px = [img[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]
    if force:
        pairs = [force]
    else:
        used = sorted(set(px) | {C_BLACK})
        pairs = [(a, b) for i, a in enumerate(used) for b in used[i:]]
    best = None
    for a, b in pairs:
        err = sum(min(dist(p, a), dist(p, b)) for p in px)
        if best is None or err < best[0]:
            best = (err, a, b)
    err, a, b = best
    fg, bg = (a, b) if a != C_BLACK else (b, a)
    data = bytearray(8)
    for y in range(8):
        for x in range(8):
            p = px[y * 8 + x]
            if dist(p, fg) < dist(p, bg):
                data[y] |= 0x80 >> x
    return bytes(data), fg << 4 | bg, err


def mc_cell(img: Img, cx: int, cy: int) -> tuple[bytes, int, int]:
    """La cella (cx, cy) di img (pixel doppi: le due metà di ogni coppia uguali) in bitmap
    multicolor: 8 byte, colore dello schermo (%01 nel nibble alto, %10 nel basso), Color RAM (%11);
    il nero è lo sfondo ($D021, %00). Al più 3 colori oltre il nero."""
    px = [[img[cy * 8 + y][cx * 8 + 2 * x] for x in range(4)] for y in range(8)]
    assert all(img[cy * 8 + y][cx * 8 + 2 * x] == img[cy * 8 + y][cx * 8 + 2 * x + 1]
               for y in range(8) for x in range(4)), f"cella {cx}, {cy}: pixel non doppi"
    used = sorted({c for row in px for c in row} - {C_BLACK})
    assert len(used) <= 3, f"cella {cx}, {cy}: {len(used)} colori oltre il nero"
    code = {C_BLACK: 0, **{c: i + 1 for i, c in enumerate(used)}}
    used += [C_BLACK] * (3 - len(used))
    data = bytes(sum(code[c] << (6 - 2 * x) for x, c in enumerate(row)) for row in px)
    return data, used[0] << 4 | used[1], used[2]


def cursor_sprite() -> bytes:
    """Cursore: cornice gialla di 4 pixel su una casella di 32x32, sprite espanso in x e in y."""
    rows = []
    for y in range(21):
        bits = 0
        if y < 16:
            for x in range(16):
                if y < 2 or y >= 14 or x < 2 or x >= 14:
                    bits |= 1 << (23 - x)
        rows.append(bits.to_bytes(3, "big"))
    return b"".join(rows) + bytes(1)


def tag_box(w: int) -> bytes:
    """Riquadro nero della sigla del cursore: w pixel per 9 righe, sprite espanso in x."""
    row = (((1 << w) - 1) << (24 - w)).to_bytes(3, "big")
    return row * 9 + bytes(64 - 27)


def background() -> tuple[Img, dict[tuple[int, int], int], set[tuple[int, int]]]:
    """Lo sfondo: griglia delle caselle con le cornici, il "?" di OMEGA e la rete del campo. Poi i
    colori delle celle delle scritte e le celle col "?"."""
    img = blank(320, 200)
    for i in range(8):
        # cornice nera (ai lati di una coppia di pixel: le righe sono multicolor): sul C64 una
        # grigia toglierebbe un colore a ogni cella del bordo
        x0, y0 = GRID_X + (i % 4) * CELL, GRID_Y + (i // 4) * CELL
        paste(img, png(f"{NAMES[i]}_small" if i < 7 else "omega_small"), x0, y0)
        for t in range(CELL):
            for x, y in ((x0 + t, y0), (x0 + t, y0 + CELL - 1), (x0, y0 + t), (x0 + 1, y0 + t),
                         (x0 + CELL - 2, y0 + t), (x0 + CELL - 1, y0 + t)):
                img[y][x] = C_BLACK
    # "?" di OMEGA, centrato in basso nella casella (paddle_ui: centro a 6 pixel dal fondo), a
    # pixel doppi
    x0, y0 = GRID_X + 3 * CELL + CELL // 2 - 4, GRID_Y + CELL + CELL - 6 - 4
    qcells = set()
    for y, row in enumerate(QUESTION_MC):
        for x, ch in enumerate(row):
            if ch == "X":
                img[y0 + y][x0 + 2 * x] = img[y0 + y][x0 + 2 * x + 1] = C_PURPLE
                qcells.add(((x0 + 2 * x) // 8, (y0 + y) // 8))
    # nelle celle del "?" la sagoma sparisce: solo viola e nero
    for cx, cy in qcells:
        for y in range(cy * 8, cy * 8 + 8):
            for x in range(cx * 8, cx * 8 + 8):
                if img[y][x] != C_PURPLE:
                    img[y][x] = C_BLACK
    # rete: trattini di 2x5 pixel ogni 8 righe (da una x pari: una coppia nelle righe multicolor)
    y = COURT_Y + 2
    while y < COURT_Y + COURT_H:
        for dy in range(5):
            img[y + dy][NET_X - 1] = img[y + dy][NET_X] = C_WHITE
        y += 8
    text: dict[tuple[int, int], int] = {}

    def span(row: int, col: int, n: int, color: int) -> None:
        for c in range(col, col + n):
            text[(c, row)] = color
    span(TITLE_ROW, 12, 16, C_YELLOW)
    for side in range(2):
        span(LABEL_ROW, LABEL_COL[side], 3, C_WHITE)
        span(LABEL_ROW, OK_COL[side], 2, C_YELLOW)
        span(TAG_ROW, TAG_COL[side], 16, C_WHITE)
        span(HINT_ROW, HINT_COL[side], HINT_LEN, C_LGRAY)
    span(HINT_ROW, READY_COL, 6, C_YELLOW)
    for r in range(3):
        span(TIMER_ROW + r, TIMER_COL, 6, C_WHITE)
    return img, text, qcells


def pick_screen() -> tuple[bytes, bytes, bytes]:
    """Bitmap (8.000 byte), colori (1.000) e Color RAM (1.000) dello sfondo della scelta."""
    img, text, qcells = background()
    bitmap, colors, cram = bytearray(8000), bytearray(1000), bytearray(1000)
    lossy = 0
    # lo split del raster cambia modo durante l'ultima riga di pixel prima della riga MC_ROW0 e la
    # prima dopo la riga MC_ROW1: lì niente pixel accesi
    for x in range(320):
        assert img[MC_ROW0 * 8 - 1][x] == C_BLACK and img[(MC_ROW1 + 1) * 8][x] == C_BLACK, x
    for cy in range(25):
        for cx in range(40):
            i = cy * 40 + cx
            if (cx, cy) in text:
                assert not MC_ROW0 <= cy <= MC_ROW1, ("scritta nelle righe multicolor", cx, cy)
                colors[i] = text[(cx, cy)] << 4 | C_BLACK
                continue
            if MC_ROW0 <= cy <= MC_ROW1:
                bitmap[i * 8:i * 8 + 8], colors[i], cram[i] = mc_cell(img, cx, cy)
                continue
            force = (C_PURPLE, C_BLACK) if (cx, cy) in qcells else None
            data, colors[i], err = cell_bitmap(img, cx, cy, force)
            bitmap[i * 8:i * 8 + 8] = data
            lossy += err > 0
    # riga 1 e riga 2 fino alla colonna 16: vuote, nere su nero (il codice dei cursori, make_crt.py)
    assert not any(bitmap[320:2 * 320 + 17 * 8]) and not any(colors[40:2 * 40 + 17])
    # immagine dello sprite del cursore nella riga vuota, nera su nero
    at = SPRITE_ROW * 320
    assert not any(bitmap[at:at + 320]) and not any(colors[SPRITE_ROW * 40:SPRITE_ROW * 40 + 40])
    bitmap[at:at + 64] = cursor_sprite()
    bitmap[at + 64:at + 128] = tag_box(9)          # 1P, 2P: 18 pixel
    bitmap[at + 128:at + 192] = tag_box(13)        # CPU: 26 pixel
    return bytes(bitmap), bytes(colors), bytes(cram)


def panel(kind: str, side: int) -> tuple[bytes, Img]:
    """Il pannello del tipo per il lato: ritratto multicolor (specchiato a destra; le righe dello split)
    e nome sotto, hires, centrato sul ritratto e dentro lo schermo come in paddle_ui.rs. Righe di
    celle: 88 byte di bitmap, 11 di colori e 11 di Color RAM (0 nelle righe del nome). Anche
    l'immagine resa, per le prove."""
    img = blank(PANEL_W * 8, PANEL_H * 8)
    portrait = png(kind)
    paste(img, mirror(portrait) if side else portrait, 0, 0)
    art = name_art(kind)
    w, h = len(art[0]), len(art)
    x0 = PORTRAIT_COL[side] * 8
    mid = x0 + PANEL_W * 4
    half = w / 2 + 2
    cx = min(max(mid, half), 320 - half)
    ax, ay = round(cx - w / 2) - x0, NAME_CY - round(h / 2) - PORTRAIT_ROW * 8
    assert 0 <= ax and ax + w <= PANEL_W * 8 and 13 * 8 <= ay and ay + h <= PANEL_H * 8, (kind, ax, ay)
    paste(img, art, ax, ay, transparent=-1)
    out = bytearray()
    shown = blank(PANEL_W * 8, PANEL_H * 8)
    mc_rows = MC_ROW1 - PORTRAIT_ROW + 1
    # la prima riga di pixel dopo lo split: vuota (pick_screen)
    assert all(img[mc_rows * 8][x] == C_BLACK for x in range(PANEL_W * 8)), kind
    for cy in range(PANEL_H):
        colors = bytearray()
        if cy < mc_rows:
            cram = bytearray()
            for cx in range(PANEL_W):
                data, color, c3 = mc_cell(img, cx, cy)
                out += data
                colors.append(color)
                cram.append(c3)
                four = (C_BLACK, color >> 4, color & 15, c3)
                for y in range(8):
                    for x in range(8):
                        shown[cy * 8 + y][cx * 8 + x] = four[data[y] >> (6 - 2 * (x // 2)) & 3]
            out += colors + cram
            continue
        for cx in range(PANEL_W):
            data, color, err = cell_bitmap(img, cx, cy)
            out += data
            colors.append(color)
            fg, bg = color >> 4, color & 15
            for y in range(8):
                for x in range(8):
                    shown[cy * 8 + y][cx * 8 + x] = fg if data[y] & (0x80 >> x) else bg
        out += colors + bytes(PANEL_W)
    return bytes(out), shown


# ------------------------------------------------------------------ schermo VS
#
# Lo schermo VS della presentazione di CHALLENGE (challenge_ui.rs `Stage::vs`, c64/src/kvs.s), dopo
# la parte con il nome detto dalla voce. Ritratti e nomi dei tipi sono i pannelli della scelta: dei
# ritratti (multicolor) le prime 12 righe, nelle righe 2-13 (VS_MC_ROW0-VS_MC_ROW1, lo split del
# raster di kvs.s: la riga 1 è il livello, in hires); i nomi (righe 13-16 del pannello) nelle righe
# 15-18. OMEGA ha due pannelli suoi, il ritratto svelato e il sigillo (18 righe: il sigillo, più
# alto, nelle righe 14-18). Qui: i colori dello schermo (le scritte senza pixel), le tre grandezze
# della scritta VS (disegnata qui, a pixel doppi: è nelle righe multicolor) e i pannelli di OMEGA.

VS_STAMP_COL, VS_STAMP_ROW, VS_STAMP_W, VS_STAMP_H = 16, 2, 8, 4   # riquadro della scritta VS
VS_MC_ROW0, VS_MC_ROW1 = 2, 13  # righe multicolor: i ritratti (le prime 12 righe), la scritta VS, la rete
VS_LEVEL_ROW = 1
VS_CODE4_ROW, VS_CODE4_COL, VS_CODE4_LEN = 14, 11, 18     # celle vuote e nere: codice di kvs.s,
                                                          # anche nella riga dopo (KV_CODE5)
VS_TAG_ROW = 19
VS_ICON_ROW = 20
VS_FIRST_ROW = 22
VS_SCORE_ROW = 23               # SCORE e HI (intro_hud); la riga 24 tiene codice
OMEGA_PANEL_H = 18
OMEGA_NAME_CY = 148 - 33 / 2    # challenge_ui.rs vs_name_y: in fondo a VS_NAME_BOTTOM
# lettere della scritta VS, 8x8 (non sono i glifi della ROM)
VS_FONT = {
    "V": ["XX....XX", "XX....XX", "XX....XX", ".XX..XX.", ".XX..XX.", "..XXXX..", "...XX...", "........"],
    "S": [".XXXXXX.", "XX......", "XX......", ".XXXXX..", "......XX", "......XX", "XXXXXXX.", "........"],
}


def vs_stamp(scale: int) -> bytes:
    """La scritta VS a `scale` volte, centrata nel riquadro di VS_STAMP_W x VS_STAMP_H celle: le
    celle riga per riga, 8 byte ciascuna."""
    w, h = VS_STAMP_W * 8, VS_STAMP_H * 8
    img = blank(w, h)
    tw, th = 16 * scale, 8 * scale
    x0, y0 = (w - tw) // 2, (h - th) // 2
    for i, ch in enumerate("VS"):
        for y, row in enumerate(VS_FONT[ch]):
            for x, c in enumerate(row):
                if c == "X":
                    for dy in range(scale):
                        for dx in range(scale):
                            img[y0 + y * scale + dy][x0 + (i * 8 + x) * scale + dx] = C_YELLOW
    # a pixel doppi (righe multicolor): una coppia accesa se lo è uno dei due pixel; giallo = %01, il
    # colore dello schermo nel nibble alto
    for row in img:
        for x in range(0, w, 2):
            row[x] = row[x + 1] = C_YELLOW if C_YELLOW in (row[x], row[x + 1]) else C_BLACK
    out = bytearray()
    for cy in range(VS_STAMP_H):
        for cx in range(VS_STAMP_W):
            data, color, c3 = mc_cell(img, cx, cy)
            assert color & 0xF0 in (0, C_YELLOW << 4) and c3 == 0 and color & 15 == 0
            out += data
    return bytes(out)


def omega_panel(side: int) -> bytes:
    """Pannello di OMEGA per il lato: il ritratto svelato (multicolor) e sotto il sigillo, come
    panel() con mc."""
    img = blank(PANEL_W * 8, OMEGA_PANEL_H * 8)
    portrait = png("omega")
    paste(img, mirror(portrait) if side else portrait, 0, 0)
    roles = TITLE_SPEC["palette"]
    art = [[-1 if roles[r] in ("transparent", "dark_red") else TITLE_C64[roles[r]] for r in row]
           for row in title_roles("name_omega")]
    w, h = len(art[0]), len(art)
    x0 = PORTRAIT_COL[side] * 8
    half = w / 2 + 2
    cx = min(max(x0 + PANEL_W * 4, half), 320 - half)
    ax, ay = round(cx - w / 2) - x0, round(OMEGA_NAME_CY - h / 2) - 8      # pannello dalla riga 1
    assert 0 <= ax and ax + w <= PANEL_W * 8 and 13 * 8 <= ay and ay + h <= OMEGA_PANEL_H * 8, (ax, ay)
    paste(img, art, ax, ay, transparent=-1)
    # lo split si spegne nella prima riga di pixel della riga 14 dello schermo (13 del pannello)
    assert all(img[13 * 8][x] == C_BLACK for x in range(PANEL_W * 8))
    out = bytearray()
    for cy in range(OMEGA_PANEL_H):
        colors, cram = bytearray(), bytearray(PANEL_W)
        for cx in range(PANEL_W):
            if cy < 13:
                data, color, cram[cx] = mc_cell(img, cx, cy)
            else:
                data, color, _ = cell_bitmap(img, cx, cy)
            out += data
            colors.append(color)
        out += colors + cram
    return bytes(out)


def vs_colors() -> bytes:
    """Colori dello schermo VS (4 pagine da $C000): neri, salvo le celle delle scritte (il livello
    giallo, i motti bianchi, le icone gialle, FIRST TO grigio, i punti bianchi). Scala, rete, ritratti
    e nomi li colora il programma."""
    colors = bytearray(1024)

    def span(row: int, col: int, n: int, color: int) -> None:
        for c in range(col, col + n):
            colors[row * 40 + c] = color << 4 | C_BLACK
    span(VS_LEVEL_ROW, 11, 18, C_YELLOW)
    span(VS_TAG_ROW, 0, 40, C_WHITE)
    for r in (VS_ICON_ROW, VS_ICON_ROW + 1):
        span(r, 0, 40, C_YELLOW)
    span(VS_FIRST_ROW, 0, 40, C_LGRAY)
    span(VS_SCORE_ROW, 0, 40, C_WHITE)
    span(0, 0, 40, C_WHITE)            # P1 e P2 della sfida, i duelli vinti (la scala la colora il programma)
    for r in range(VS_STAMP_ROW, VS_STAMP_ROW + VS_STAMP_H):
        span(r, VS_STAMP_COL, VS_STAMP_W, C_YELLOW)
    return bytes(colors)


def vs_data(lines: list[str], first_bank: int) -> bytes:
    """Dati del VS dopo le 4 pagine del codice (kvs.s): i colori, una pagina per il codice della riga
    24 e tre per quello nei caratteri 64-159 (tools/make_crt.py), le tre scritte VS, i pannelli di
    OMEGA."""
    data = bytearray(vs_colors()) + bytes(256) + bytes(3 * 256) + bytes(3 * 256)
    lines.append(f"KV_COLORS = $80 + 4          ; pagina dei colori (4), poi una per la riga 24, tre per")
    lines.append(f"KV_ROW24P = $80 + 8          ; i caratteri 64-159 e tre per le celle delle righe 14-15 (il")
    lines.append(f"KV_CHARSP = $80 + 9          ; codice: tools/make_crt.py)")
    lines.append(f"KV_CODE4P = $80 + 12")
    at = 0xE000 + VS_CODE4_ROW * 320 + VS_CODE4_COL * 8
    lines.append(f"KV_CODE4  = ${at:04X}        ; riga {VS_CODE4_ROW} dalla colonna {VS_CODE4_COL}, {VS_CODE4_LEN} celle (KVCODE4)")
    lines.append(f"KV_CODE5  = ${at + 320:04X}        ; e la riga dopo (KVCODE5)")
    assert at >> 8 == 0xF1 and (at + 320 + VS_CODE4_LEN * 8 - 1) >> 8 == 0xF3, "KVCODE4-5: le tre pagine $F100-$F3FF"
    for scale in (4, 3, 2):
        lines.append(f"KV_STAMP{scale} = $80 + {4 + len(data) // 256}")
        data += vs_stamp(scale)
    for side in range(2):
        lines.append(f"KV_OMEGA{side}  = $80 + {4 + len(data) // 256}    ; pannello di OMEGA, lato {side}")
        data += omega_panel(side)
        data += bytes(-len(data) % 256)
    assert 4 * 256 + len(data) <= 0x4000
    lines += [
        f"KV_BANK_REL = {first_bank}    ; banco del VS (codice e dati) da KP_BANK",
        f"KV_STAMP_COL = {VS_STAMP_COL}",
        f"KV_STAMP_ROW = {VS_STAMP_ROW}",
        f"KV_STAMP_W = {VS_STAMP_W}",
        f"KV_STAMP_H = {VS_STAMP_H}",
        f"KV_MC_ROW0 = {VS_MC_ROW0}",
        f"KV_MC_ROW1 = {VS_MC_ROW1}",
        f"KV_OMEGA_H = {OMEGA_PANEL_H}",
        f"KV_LEVEL_ROW = {VS_LEVEL_ROW}",
        f"KV_TAG_ROW = {VS_TAG_ROW}",
        f"KV_ICON_ROW = {VS_ICON_ROW}",
        f"KV_FIRST_ROW = {VS_FIRST_ROW}",
        f"KV_SCORE_ROW = {VS_SCORE_ROW}",
    ]
    return bytes(data)


# ------------------------------------------------------------------ sfilata del finale
#
# La sfilata del finale di CHALLENGE (ending_ui.rs `draw_parade`, c64/src/parade.s): otto ritratti
# medi (8x9 celle) in due file da quattro, in bitmap multicolor (c64mc/; le righe dei ritratti, lo
# split del raster di parade.s), ognuno prima normale e poi sconfitto con il timbro DEFEATED rosso,
# dritto, a lettere 3x5 a pixel doppi alte il doppio (5x7 a pixel doppi non ci stanno in 64 pixel);
# OMEGA svelato se battuto, se no in sagoma. Pannelli: 9 righe di celle da 8, per riga 64 byte di
# bitmap, 8 di colori e 8 di Color RAM.

PR_W, PR_H = 8, 9
FONT3x5 = {                     # lettere del timbro multicolor (una X = una coppia di pixel)
    "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
    "E": ["XXX", "X..", "XX.", "X..", "XXX"],
    "F": ["XXX", "X..", "XX.", "X..", "X.."],
    "A": [".X.", "X.X", "XXX", "X.X", "X.X"],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
}
PR_STAMP_ROW = 6                # timbro nelle righe di celle 6-7 (sul PC centrato 14 pixel sopra il fondo)


def parade_panel(name: str, defeated: bool) -> bytes:
    """Pannello della sfilata: il ritratto medio multicolor, sconfitto con il timbro (righe di celle
    PR_STAMP_ROW e dopo): righe rosse sopra e sotto e DEFEATED in lettere 3x5 a pixel doppi, alte
    il doppio, sul nero. Per riga 64 byte di bitmap, 8 di colori, 8 di Color RAM."""
    img = png(name)
    assert len(img) == PR_H * 8 and len(img[0]) == PR_W * 8, name
    if defeated:
        y0, w = PR_STAMP_ROW * 8, PR_W * 8
        for y in range(16):
            for x in range(w):
                img[y0 + y][x] = C_RED if y in (0, 15) else C_BLACK
        for i, ch in enumerate("DEFEATED"):         # 8 lettere da 3 coppie + 7 spazi: 31 coppie su 32
            for r, row in enumerate(FONT3x5[ch]):
                for c, v in enumerate(row):
                    if v == "X":
                        for dy in range(2):
                            x = 2 * (i * 4 + c)
                            img[y0 + 3 + 2 * r + dy][x] = img[y0 + 3 + 2 * r + dy][x + 1] = C_RED
    out = bytearray()
    for cy in range(PR_H):
        colors, cram = bytearray(), bytearray()
        for cx in range(PR_W):
            data, color, c3 = mc_cell(img, cx, cy)
            out += data
            colors.append(color)
            cram.append(c3)
        out += colors + cram
    return bytes(out)


def parade_data(lines: list[str]) -> bytes:
    """Dati della sfilata dopo le 4 pagine del suo codice: una pagina per quello nella riga 0 della
    bitmap (PRCODE2, tools/make_crt.py), i pannelli dei sette tipi e di OMEGA, normali e sconfitti
    (tipo * 2 + sconfitto), poi OMEGA in sagoma; uno ogni 3 pagine."""
    data = bytearray(256)
    names = [n + "_mid" for n in NAMES + ["omega"]]
    for n in names:
        for d in (False, True):
            p = parade_panel(n + "_defeated" if d else n, d)
            assert len(p) <= 3 * 256
            data += p + bytes(3 * 256 - len(p))
    data += parade_panel("omega_mid_locked", False)
    data += bytes(-len(data) % 256)
    assert 4 * 256 + len(data) <= 0x4000
    lines += [
        "",
        "; sfilata del finale (parade.s): pannelli 8x9 celle, uno ogni 3 pagine dalla $80 + 4 del banco",
        "; KP_BANK + PR_BANK_REL (tipo * 2 + sconfitto; OMEGA come tipo 7, poi OMEGA in sagoma)",
        f"PR_W = {PR_W}",
        f"PR_H = {PR_H}",
        f"PR_ROW_BYTES = {PR_W * 10}         ; bitmap, colori, Color RAM",
        "PR_CODE2P = $80 + 4     ; il codice della riga 0 della bitmap (PRCODE2)",
        "PR_PAGE0 = $80 + 5",
        f"PR_LOCKED = $80 + 5 + {len(names) * 2 * 3}",
    ]
    return bytes(data)


def render(img: Img) -> Image.Image:
    h, w = len(img), len(img[0])
    im = Image.new("RGB", (w, h))
    im.putdata([C64_RGB[c] for row in img for c in row])
    return im


def main() -> None:
    bitmap, colors, cram = pick_screen()
    data = bytearray(bitmap[:0x1F00] + colors + bytes(24) + cram + bytes(24))     # 31 + 4 + 4 pagine
    assert len(data) == 39 * 256
    first = len(data)
    lines = ["; Generato da tools/gen_c64_portraits.py: non modificare a mano.", ""]
    panels = []
    for side in range(2):
        for kind in NAMES:
            p, _ = panel(kind, side)
            assert len(p) == PANEL_H * PANEL_W * 10
            panels.append(p)
    lines += [
        f"KP_BG_PAGES   = 31          ; bitmap da $E000 (le ultime 8 celle le pulisce il programma)",
        f"KP_COL_PAGES  = 4           ; colori da $C000",
        f"KP_CRAM_PAGES = 4           ; Color RAM da $D800",
        f"KP_MC_ROW0    = {MC_ROW0}           ; righe di celle in multicolor (lo split del raster)",
        f"KP_MC_ROW1    = {MC_ROW1}",
        f"KP_PANEL_W    = {PANEL_W}",
        f"KP_PANEL_H    = {PANEL_H}",
        f"KP_PANEL_ROW  = {PORTRAIT_ROW}",
        f"KP_PANEL_COL0 = {PORTRAIT_COL[0]}",
        f"KP_PANEL_COL1 = {PORTRAIT_COL[1]}",
        f"KP_GRID_X     = {GRID_X}",
        f"KP_GRID_Y     = {GRID_Y}",
        f"KP_LABEL_ROW  = {LABEL_ROW}",
        f"KP_LABEL_COL0 = {LABEL_COL[0]}",
        f"KP_LABEL_COL1 = {LABEL_COL[1]}",
        f"KP_OK_COL0    = {OK_COL[0]}",
        f"KP_OK_COL1    = {OK_COL[1]}",
        f"KP_TAG_ROW    = {TAG_ROW}",
        f"KP_TAG_COL0   = {TAG_COL[0]}",
        f"KP_TAG_COL1   = {TAG_COL[1]}",
        f"KP_HINT_ROW   = {HINT_ROW}",
        f"KP_HINT_COL0  = {HINT_COL[0]}",
        f"KP_HINT_COL1  = {HINT_COL[1]}",
        f"KP_READY_COL  = {READY_COL}",
        f"KP_TIMER_ROW  = {TIMER_ROW}",
        f"KP_TIMER_COL  = {TIMER_COL}",
        f"KP_SPRITE     = ($E000 + {SPRITE_ROW * 320} - $C000) / 64    ; cursore, poi i due riquadri e le due sigle",
        "; pannelli (lato * 7 + tipo): banco (da KP_BANK) e pagina nella finestra a 16K ($80-$BF)",
    ]
    banks, pages = [], []
    # nel primo banco: 4 pagine di codice, lo sfondo, poi i pannelli che ci stanno
    offset = 4 * 256 + first
    image = bytearray(data)
    for p in panels:
        offset = (offset + 255) & ~255
        if offset // 0x4000 != (offset + len(p) - 1) // 0x4000:
            offset = (offset // 0x4000 + 1) * 0x4000
        banks.append(offset // 0x4000)
        pages.append(0x80 + (offset % 0x4000) // 256)
        at = offset - 4 * 256
        image += bytes(at - len(image)) + p
        offset += len(p)
    lines.append("; (88 + 11 + 11 byte per riga: bitmap, colori, Color RAM)")
    lines.append(".define KP_MC_BANK " + ", ".join(str(b) for b in banks))
    lines.append(".define KP_MC_PAGE " + ", ".join(f"${p:02X}" for p in pages))
    # il VS nel banco dopo: 4 pagine per il suo codice (kvs.s, le mette tools/make_crt.py), i dati
    vs_bank = max(banks) + 1
    lines.append("")
    lines.append("; schermo VS (kvs.s): pagine nella finestra a 16K del banco KP_BANK + KV_BANK_REL")
    vs = vs_data(lines, vs_bank)
    image += bytes(vs_bank * 0x4000 - 4 * 256 - len(image)) + bytes(4 * 256) + vs
    # la sfilata nel banco dopo: 4 pagine per il suo codice (parade.s), i dati
    pr_bank = vs_bank + 1
    pr = parade_data(lines)
    lines.append(f"PR_BANK_REL = {pr_bank}")
    image += bytes(pr_bank * 0x4000 - 4 * 256 - len(image)) + bytes(4 * 256) + pr
    lines.append(f"KP_BANKS      = {pr_bank + 1}")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "kpick.bin").write_bytes(bytes(image))
    (OUT / "kpick.inc").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"c64/gen/kpick.bin: {len(image)} byte, {pr_bank + 1} banchi")


def preview(path: str, left: str = "arcade", right: str = "blaster") -> None:
    """Prova: lo sfondo con i due pannelli, come si vede (senza scritte né sprite)."""
    bitmap, colors, cram = pick_screen()
    shown = blank(320, 200)
    for cy in range(25):
        for cx in range(40):
            c = colors[cy * 40 + cx]
            four = (C_BLACK, c >> 4, c & 15, cram[cy * 40 + cx])
            for y in range(8):
                b = bitmap[(cy * 40 + cx) * 8 + y]
                for x in range(8):
                    if MC_ROW0 <= cy <= MC_ROW1:
                        shown[cy * 8 + y][cx * 8 + x] = four[b >> (6 - 2 * (x // 2)) & 3]
                    else:
                        shown[cy * 8 + y][cx * 8 + x] = c >> 4 if b & (0x80 >> x) else c & 15
    for side, kind in enumerate((left, right)):
        _, p = panel(kind, side)
        paste(shown, p, PORTRAIT_COL[side] * 8, PORTRAIT_ROW * 8)
    render(shown).resize((960, 600), Image.NEAREST).save(path)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        preview(*sys.argv[1:])
    else:
        main()
