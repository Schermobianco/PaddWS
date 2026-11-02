"""Grafica della versione C64: set di caratteri, sprite e tabelle per c64/src.

Uscite in c64/gen/ (vanno nel repository, così l'assemblaggio non richiede Python):
  charset.bin   256 caratteri 8x8 (2 KB): vuoto, mezzeria, muro del singolo, cifre del punteggio
                (celle di 3x3 caratteri), font Munro monospazio, scritte grandi a scala 2
  pick_bank.bin il banco PICK_BANK della cartuccia (tools/make_crt.py): il set di caratteri per la
                scelta dei bonus, con al posto delle scritte grandi le metà delle lettere abbassate
                di 4 pixel (alta e bassa), come il centro della capsula accanto (il programma ne
                copia le pagine PICK_PAGES da PICK_FIRST); poi la pagina $FF00, che l'avvio copia
                sotto il KERNAL: a $FF40 i caratteri della capsula del BULLET e quelli che
                sostituisce (bullet_chars), a $FFC0 l'RTS di VOICE_COUNT, a $FFC3 i caratteri di
                PRESS START che in NEXT fanno la barra delle mosse speciali; poi title.bin (8
                pagine), che l'avvio copia sotto l'I/O
  sprites.bin   sprite (64 byte ciascuno): palla normale (4x4) e con il boost (6x6), posti delle
                racchette, linee del raster dell'attract, bande grigie EVO di 1-10 righe
  title.bin     del titolo dell'attract in bitmap hires solo le righe di caratteri che l'attract
                copia (logo con WS, copyright): due blocchi di righe intere, 320 byte ciascuna
  labels.bin    INSERT COIN e PRESS START a scala 2, nelle celle della bitmap
  credits.bin   FREE PLAY e CREDIT 0-9, nelle celle della bitmap
  (in assets.inc anche gli effetti della palla di NEXT come elenco di quadrati: il programma li
  disegna a inizio partita a $E000; e per le mosse speciali i caratteri della barra, le icone
  della mossa armata e le tracce degli effetti MOVE e SPECIAL dalla ROM della musica del MiSTer)
  assets.inc    codici dei caratteri, posizioni e tempi dell'attract per l'assembler
  voiceN.bin    campioni del nome dell'avversario di CHALLENGE per il tipo di racchetta N (ordine
                di `PaddleKind`), dai .raw4 di assets/sounds/voice (tools/gen_voices.py): src/voice.s
                li mette con il player nei file voce della cartuccia
  ready.bin, go.bin  "READY?" e "GO!" del conto alla rovescia di CHALLENGE, dagli stessi .raw4: nel
                file voce dell'avversario del primo livello
  you_win.bin   "YOU WIN!": il banco della vittoria della cartuccia (tools/make_crt.py), per il
                GAME OVER contro la CPU e il finale di CHALLENGE
  ending_chars.bin, ending.inc  set di caratteri del finale di CHALLENGE (src/ending.s): il font
                monospazio ai suoi codici, le lettere a scala 2, il timbro DEFEATED e i punti
                multicolore dei fuochi d'artificio

Le cifre del punteggio vengono da assets/fonts/pong-score.ttf a 22 px come sul MiSTer; le scritte
grandi sono le bitmap dell'attract (assets/attract/*.png, Munro 10 px) ingrandite a scala 2, come
le scritte sovrapposte del MiSTer.

Uso:  .venv\\Scripts\\python tools\\gen_c64_assets.py   (richiede Pillow)
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from gen_next_assets import ICONS
from gen_voices import NAMES as VOICE_NAMES

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "c64" / "gen"
FONTS = ROOT / "assets" / "fonts"
ATTRACT = ROOT / "assets" / "attract"
VOICES = ROOT / "assets" / "sounds" / "voice"

# caratteri del font monospazio (codici ASCII 32-95, come la tabella in assets.inc)
FONT_CHARS = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
FONT_DRAWN = "!+-./0123456789:>?ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# scelta dei bonus: caratteri sostituiti dalle metà delle lettere (pagine intere)
PICK_FIRST = 64
PICK_PAGES = 3

# scritte grandi (bitmap dell'attract a scala 2): nome dell'asset
BIG_TEXTS = ["game_over", "p1_wins", "p2_wins", "you_win", "cpu_wins", "insert_coin", "press_start"]

Tile = tuple[int, ...]   # 8 byte, bit 7 = pixel a sinistra


class Charset:
    def __init__(self) -> None:
        self.tiles: list[Tile] = []
        self.index: dict[Tile, int] = {}
        self.given: list[int] = []      # codici dati da add, in ordine (chi usa quale carattere)

    def add(self, tile: Tile, unique: bool = False) -> int:
        """Codice del carattere (riusa quelli uguali, salvo `unique`)."""
        if not unique and tile in self.index:
            self.given.append(self.index[tile])
            return self.index[tile]
        code = len(self.tiles)
        assert code < 256, "set di caratteri pieno"
        self.tiles.append(tile)
        self.index.setdefault(tile, code)
        self.given.append(code)
        return code


def tiles_of(pixels: list[list[bool]], w_chars: int, h_chars: int) -> list[list[Tile]]:
    """Immagine (righe di pixel) -> righe di caratteri 8x8."""
    rows = []
    for cy in range(h_chars):
        row = []
        for cx in range(w_chars):
            tile = []
            for y in range(8):
                byte = 0
                for x in range(8):
                    py, px = cy * 8 + y, cx * 8 + x
                    if py < len(pixels) and px < len(pixels[py]) and pixels[py][px]:
                        byte |= 0x80 >> x
                tile.append(byte)
            row.append(tuple(tile))
        rows.append(row)
    return rows


def render(font: ImageFont.FreeTypeFont, text: str, size: tuple[int, int], offset: tuple[int, int]) -> list[list[bool]]:
    im = Image.new("L", size, 0)
    ImageDraw.Draw(im).text(offset, text, font=font, fill=255)
    return [[im.getpixel((x, y)) > 127 for x in range(size[0])] for y in range(size[1])]


def ink_rows(font: ImageFont.FreeTypeFont, chars: str, height: int) -> tuple[int, int]:
    """Prima e ultima riga con l'inchiostro di tutti i caratteri disegnati a (0, 0)."""
    rows: set[int] = set()
    for c in chars:
        px = render(font, c, (32, height), (0, 0))
        rows |= {y for y in range(height) if any(px[y])}
    return min(rows), max(rows)


def score_digits(cs: Charset) -> list[list[int]]:
    """Cifre del punteggio a 22 px in celle di 24x24 (3x3 caratteri), come sul MiSTer."""
    font = ImageFont.truetype(str(FONTS / "pong-score.ttf"), 22)
    top, bottom = ink_rows(font, "0123456789", 40)
    assert bottom - top + 1 <= 24
    out = []
    for d in "0123456789":
        px = render(font, d, (24, 40), (1, 1 - top))
        rows = tiles_of(px[:24], 3, 3)
        out.append([cs.add(t) for row in rows for t in row])
    return out


def text_font(cs: Charset) -> list[int]:
    """Font Munro 10 px monospazio: ogni lettera centrata in un carattere, riga 7 vuota."""
    font = ImageFont.truetype(str(FONTS / "munro.ttf"), 10)
    # righe dell'inchiostro di lettere e cifre (la barra sporge di una riga e viene tagliata)
    top, bottom = ink_rows(font, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", 24)
    assert bottom - top + 1 <= 7, (top, bottom)
    codes = []
    for c in FONT_CHARS:
        if c == " ":
            codes.append(0)
            continue
        if c not in FONT_DRAWN:
            codes.append(0)
            continue
        w = round(font.getlength(c))
        px = render(font, c, (8, 24), ((8 - w) // 2, -top))
        codes.append(cs.add(tiles_of(px[:8], 1, 1)[0][0]))
    return codes


def big_text(cs: Charset, name: str) -> tuple[int, list[int]]:
    """Bitmap dell'attract a scala 2, centrata in una fascia di caratteri alta 2: (larghezza, codici)."""
    im = Image.open(ATTRACT / f"{name}.png").convert("RGBA")
    w, h = im.size
    w_chars = (2 * w + 2 + 7) // 8
    ox = (w_chars * 8 - 2 * w) // 2
    oy = (16 - 2 * h) // 2
    pixels = [[False] * (w_chars * 8) for _ in range(16)]
    for y in range(h):
        for x in range(w):
            if im.getpixel((x, y))[3] > 127:
                for dy in range(2):
                    for dx in range(2):
                        pixels[oy + 2 * y + dy][ox + 2 * x + dx] = True
    rows = tiles_of(pixels, w_chars, 2)
    return w_chars, [cs.add(t) for row in rows for t in row]


SPRITE_BANDS = 10  # altezze della banda grigia EVO (la più alta: area di 8 pixel, 9 righe)
CAP = 12           # lato della capsula disegnata, come sul MiSTer (la capsula del C64 è di 10 pixel)
BONUSES = len(ICONS)
B_SUPER = 5
B_BULLET = 7       # solo dalle capsule, mai armato: niente icona del bonus armato
assert BONUSES == B_BULLET + 1


def icon_lit(b: int, dx: int, dy: int) -> bool:
    return 0 <= dx < 9 and 0 <= dy < 9 and ICONS[b][dy][dx] == "#"


def capsule(b: int, inv: bool) -> list[list[bool]]:
    """Capsula CAP x CAP come cap_px del MiSTer: bordo e icona, oppure piena con l'icona vuota."""
    o = (CAP - 9) // 2
    rows = []
    for dy in range(CAP):
        row = []
        for dx in range(CAP):
            border = dx in (0, CAP - 1) or dy in (0, CAP - 1)
            ic = icon_lit(b, dx - o, dy - o)
            row.append(not ic if inv else border or ic)
        rows.append(row)
    return rows


def sprite_of(pixels: list[list[bool]]) -> bytes:
    """Sprite hires con l'immagine in alto a sinistra."""
    data = bytearray(64)
    for y, row in enumerate(pixels):
        for x, on in enumerate(row):
            if on:
                data[3 * y + x // 8] |= 0x80 >> (x % 8)
    return bytes(data)


def cap_tiles(b: int) -> list[Tile]:
    """Capsula b della riserva in 2x2 caratteri, normale e in negativo (8 caratteri)."""
    out = []
    for inv in (False, True):
        px = [[False] * 16 for _ in range(16)]
        for y, row in enumerate(capsule(b, inv)):
            for x, on in enumerate(row):
                px[2 + y][2 + x] = on
        out += [t for row in tiles_of(px, 2, 2) for t in row]
    return out


def next_chars(cs: Charset, lines: list[str], spare: list[int]) -> bytes:
    """NEXT: capsule della riserva e della scelta in 2x2 caratteri (la capsula a 2 pixel dal bordo,
    passo di 16 pixel come sul MiSTer), normali e in negativo, posto vuoto a puntini e freccetta del
    selezionato sotto la capsula.

    Il set di caratteri è pieno: le 8 della capsula del BULLET (che c'è solo in partita, nella
    riserva) prendono in NEXT il posto dei caratteri `spare`, che in NEXT non servono; il programma
    li scambia a inizio partita (bullet_chars in video.s, con i caratteri originali per le altre).
    Restituisce i 128 byte da $FF40: i caratteri della capsula, poi quelli originali."""
    codes = []
    for b in range(BONUSES):
        if b != B_BULLET:
            codes += [cs.add(t) for t in cap_tiles(b)]
    bullet = cap_tiles(B_BULLET)
    assert len(spare) == len(bullet) and len(set(bullet)) == len(bullet)
    assert not any(t in cs.index for t in bullet), "capsula del BULLET già nel set"
    codes += spare
    lines.append("; NEXT: capsule 2x2 (alto sinistra, alto destra, basso sinistra, basso destra), per bonus")
    lines.append("; normale e in negativo: indice = bonus * 8 + negativo * 4")
    lines.append(".define CAP_CHARS " + ", ".join(str(c) for c in codes))
    lines.append("; BULLET: le sue capsule della riserva al posto dei caratteri BULLET_C0-7 (bullet_chars),")
    lines.append("; con quelli originali per le partite che non sono NEXT")
    for i, c in enumerate(spare):
        lines.append(f"BULLET_C{i} = {c}")
    bullet_bytes = bytes(v for t in bullet for v in t) + bytes(v for c in spare for v in cs.tiles[c])
    # posto vuoto: bordo a puntini (pixel accesi a scacchiera, come x[0] == y[0] sul MiSTer)
    px = [[False] * 16 for _ in range(16)]
    for dy in range(CAP):
        for dx in range(CAP):
            if (dx in (0, CAP - 1) or dy in (0, CAP - 1)) and (dx + dy) % 2 == 0:
                px[2 + dy][2 + dx] = True
    empty = [cs.add(t) for row in tiles_of(px, 2, 2) for t in row]
    lines.append(".define CAP_EMPTY " + ", ".join(str(c) for c in empty))
    # freccetta: 2 pixel sotto la capsula, larga 5, 3 e 1 pixel attorno al centro della capsula
    px = [[False] * 16 for _ in range(8)]
    center = 2 + CAP // 2
    for r, half in enumerate((2, 1, 0)):
        for x in range(center - half, center + half + 1):
            px[r][x] = True
    arrow = [cs.add(t) for t in tiles_of(px, 2, 1)[0]]
    lines.append(f"CH_ARROW_L = {arrow[0]}")
    lines.append(f"CH_ARROW_R = {arrow[1]}")
    # muro del GUARDIAN: due pixel a cavallo di due colonne (x 7-8 e 311-312), tratti di 5 righe
    # ogni 8 come sul MiSTer, ma tutti dentro il carattere (righe 1-5): il colore e la presenza
    # vanno per riga di caratteri (settori del muro), così nessun tratto resta a metà
    dash = [1 if 1 <= y <= 5 else 0 for y in range(8)]
    lines.append(f"CH_BAR_R = {cs.add(tuple(0x01 * d for d in dash), unique=True)}    ; pixel 7 della colonna")
    lines.append(f"CH_BAR_L = {cs.add(tuple(0x80 * d for d in dash), unique=True)}    ; pixel 0 della colonna")
    # colpo del BLASTER: due tratti di 7 pixel nelle righe 1 e 5 del carattere, dal pixel p (0, 2,
    # 4, 6) del primo carattere; quello che avanza nel secondo
    shot = []
    for p in (0, 2, 4, 6):
        bits = sum(0x80 >> x for x in range(p, p + 7) if x < 8), sum(0x80 >> (x - 8) for x in range(p, p + 7) if x >= 8)
        for half in bits:
            shot.append(cs.add((0, half, 0, 0, 0, half, 0, 0)) if half else 0)
    lines.append(".define SHOT_CHARS " + ", ".join(str(c) for c in shot) + "    ; per fase: primo, secondo")
    # STEER: segni dove finisce la guida, 2 pixel a cavallo di due colonne, alti 6 righe in cima e
    # in fondo allo schermo
    top = [1 if y < 6 else 0 for y in range(8)]
    bottom = [1 if y >= 2 else 0 for y in range(8)]
    for name, rows in (("TOP", top), ("BOTTOM", bottom)):
        lines.append(f"CH_STEER_{name}_R = {cs.add(tuple(0x01 * r for r in rows), unique=True)}")
        lines.append(f"CH_STEER_{name}_L = {cs.add(tuple(0x80 * r for r in rows), unique=True)}")
    lines.append("")
    return bullet_bytes


# NEXT: effetti della palla, sprite disegnati a inizio partita nella bitmap dell'attract ($E000, che
# in partita non serve): gli aloni di SLOW, sprite normali con la palla nel pixel (9, 7). La coda
# grigia e la cometa del SUPER invece il programma le disegna in partita dalle posizioni vere della
# palla (video.s, trail_end): qui solo il retino per età e i quadrati ritagliati della coda.
FX_RING_BALL = (9, 7)  # pixel della palla nell'alone
TRAIL_N = 5            # coda: posizioni passate della palla (0,1 s a 50 Hz), più quelle a metà tra due
# retino ordinato 4x4 (Bayer): la coda grigia sfuma diradandosi verso la fine
BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


TRAIL_ROWS = 24        # righe per età nel retino della coda (21 dello sprite, arrotondate)
TRAIL_SPAN = 48        # coordinate dei quadrati della coda nello sprite + 16: da 0 a 47


def trail_dither() -> list[int]:
    """Retino della coda: per ogni età (0 = a metà tra la palla e la posizione di un frame fa,
    1 = un frame fa, ... 2 * TRAIL_N - 1 = la più vecchia) e riga dello sprite, il byte dello sprite
    multicolore con %01 nei quattro pixel doppi accesi. Densità da quasi piena a quasi vuota."""
    out = []
    for age in range(2 * TRAIL_N):
        density = 1 - (age + 1) / (2 * TRAIL_N + 1)
        for row in range(TRAIL_ROWS):
            out.append(sum(0x40 >> (2 * p) for p in range(4) if BAYER4[row % 4][p] < density * 16))
    return out


def trail_tables() -> list[str]:
    """Quadrati della coda già ritagliati allo sprite (12 pixel doppi x 21 righe), per lato 4 e 6:
    indice = coordinata del bordo sinistro (o alto) nello sprite + 16, più 48 per il lato 6.
    Per la x: primo byte della riga, maschera dei pixel doppi in quel byte e nel successivo (0 se
    il quadrato sta in un byte solo; nel primo 0 se è fuori); per la y: prima riga * 3 e righe."""
    b0, lm, rm, base, rows, r0s = [], [], [], [], [], []
    pair_bits = [0xC0, 0x30, 0x0C, 0x03]
    for size in (4, 6):
        for c in range(TRAIL_SPAN):
            x0, x1 = max(c - 16, 0), min(c - 16 + size - 1, 23)
            first = left = right = 0
            if x0 <= x1:
                i0, i1 = x0 // 2, x1 // 2
                first = i0 // 4
                for i in range(i0, i1 + 1):
                    if i // 4 == first:
                        left |= pair_bits[i % 4]
                    else:
                        right |= pair_bits[i % 4]
            b0.append(first)
            lm.append(left)
            rm.append(right)
            y0, y1 = max(c - 16, 0), min(c - 16 + size - 1, 20)
            n = max(y1 - y0 + 1, 0)
            rows.append(n)
            base.append(3 * y0 if n else 0)
            r0s.append(y0 if n else 0)
    ages = [TRAIL_ROWS * a for a in range(2 * TRAIL_N)]
    hexes = lambda v: ", ".join(f"${b:02X}" for b in v)
    return [
        f"TRAIL_SPAN = {TRAIL_SPAN}    ; coda: coordinate dei quadrati nello sprite + 16, da 0 a 47",
        ".define TRAIL_X_B0 " + hexes(b0),
        ".define TRAIL_X_LM " + hexes(lm),
        ".define TRAIL_X_RM " + hexes(rm),
        ".define TRAIL_Y_BASE " + hexes(base),
        ".define TRAIL_Y_ROWS " + hexes(rows),
        ".define TRAIL_Y_R0 " + hexes(r0s),
        ".define TRAIL_AGE " + hexes(ages),
    ]


def fx_image(cells: set[tuple[int, int]]) -> bytes:
    """Sprite hires dai pixel (x, y) accesi, griglia 24x21."""
    data = bytearray(64)
    for x, y in cells:
        if 0 <= x < 24 and 0 <= y < 21:
            data[3 * y + x // 8] |= 0x80 >> (x % 8)
    return bytes(data)


def next_fx_sprites() -> tuple[bytes, list[str]]:
    """Alone di SLOW (palla 4 e 6 pixel, quadrato di lato triplo, a puntini perché sul MiSTer è
    grigio)."""
    images = []
    rx, ry = FX_RING_BALL
    for size in (4, 6):
        cx, cy = rx + size / 2, ry + size / 2
        side = 3 * size
        x0, y0 = round(cx - side / 2), round(cy - side / 2)
        cells = {(rx + i, ry + j) for i in range(size) for j in range(size)}
        for t in range(side):
            for x, y in ((x0 + t, y0), (x0 + t, y0 + side - 1), (x0, y0 + t), (x0 + side - 1, y0 + t)):
                if (x + y) % 2 == 0:
                    cells.add((x, y))
        images.append(fx_image(cells))
    lines = [
        f"FX_SPRITES = {len(images)}    ; effetti della palla: 2 aloni",
        f"FX_RING_X = {FX_RING_BALL[0]}",
        f"FX_RING_Y = {FX_RING_BALL[1]}",
        f"TRAIL_N = {TRAIL_N}    ; coda: posizioni passate della palla",
        "; coda: retino per età (2 * TRAIL_N, TRAIL_ROWS righe ciascuna), %01 nei pixel doppi accesi",
        ".define TRAIL_DITHER " + ", ".join(f"${b:02X}" for b in trail_dither()),
        *trail_tables(),
    ]
    return b"".join(images), lines


def fx_squares() -> list[str]:
    """Aloni di next_fx_sprites come quadrati (x, y, lato) per immagine, chiusi da $FF: il programma
    li disegna a inizio partita."""
    out = []
    rx, ry = FX_RING_BALL
    for size in (4, 6):
        cx, cy = rx + size / 2, ry + size / 2
        side = 3 * size
        x0, y0 = round(cx - side / 2), round(cy - side / 2)
        sq = [(rx, ry, size)]
        cells = set()
        for t in range(side):
            for x, y in ((x0 + t, y0), (x0 + t, y0 + side - 1), (x0, y0 + t), (x0 + side - 1, y0 + t)):
                if (x + y) % 2 == 0:
                    cells.add((x, y))
        sq += [(x, y, 1) for x, y in sorted(cells)]
        out.append(sq)
    # controllo: gli stessi pixel delle immagini di next_fx_sprites (dentro la griglia)
    data, _ = next_fx_sprites()
    for k, sq in enumerate(out):
        cells = set()
        for x, y, size in sq:
            cells |= {(x + i, y + j) for i in range(size) for j in range(size)}
        assert fx_image(cells) == data[64 * k:64 * k + 64], k
    flat = []
    for sq in out:
        for x, y, size in sq:
            flat += [x & 0xFF, y & 0xFF, size]
        flat.append(0xFF)
    return ["; aloni: quadrati (x, y, lato) per immagine, $FF alla fine di ognuna",
            ".define FX_SQUARES " + ", ".join(map(str, flat))]


def next_sprites() -> tuple[bytes, list[str]]:
    """NEXT: capsule in campo (CAP x CAP, il SUPER anche in negativo per il lampeggio) e icone 9x9
    del bonus armato (non del BULLET, che non resta armato)."""
    data = b"".join(sprite_of(capsule(b, False)) for b in range(BONUSES))
    data += sprite_of(capsule(B_SUPER, True))
    icons = [b for b in range(BONUSES) if b != B_BULLET]
    assert icons == list(range(len(icons))), "icone per codice del bonus"
    data += b"".join(sprite_of([[icon_lit(b, x, y) for x in range(9)] for y in range(9)]) for b in icons)
    return data, [f"SPRITE_CAPS = {BONUSES}", f"SPRITE_ICONS = {len(icons)}", f"CAP_DRAW = {CAP}"]


# ------------------------------------------------------------------------- mosse speciali
#
# NEXT con le mosse speciali (c64/src/supers.s): barra di ciascun giocatore accanto alle riserve,
# icona della mossa armata accanto alla racchetta, effetti del SID dell'attivazione e del colpo.

BAR_CHARS = 5           # barra: un carattere per 0, 2, 4, 6 e 8 pixel pieni
BAR_ORIG = 0xC3         # originali dei caratteri della barra nella pagina $FF00 (dopo VOICE_COUNT)
# icone 8x8 (bit 7 = pixel a sinistra), per il giocatore sinistro: STRAIGHT SHOT (freccia verso
# l'avversario) e RISING STRIKE (dritta, poi in alto); il destro le ha specchiate
SUPER_ICONS = {
    "STRAIGHT": (0x00, 0x00, 0x04, 0x06, 0xFF, 0x06, 0x04, 0x00),
    "RISE": (0x00, 0x07, 0x03, 0x05, 0x08, 0xF0, 0x00, 0x00),
}
# la ROM della musica (la stessa del MiSTer e del player 6502)
SID_GEN = ROOT / "mister" / "rtl" / "gen"
SID_VH = SID_GEN / "sid_music.vh"
SID_HEX = SID_GEN / "sid_music.hex"


def mirror8(b: int) -> int:
    return int(f"{b:08b}"[::-1], 2)


def bar_glyph(px: int) -> bytes:
    """Cella della barra: bordo sopra e sotto (righe 0 e 4), pieno per `px` pixel da sinistra."""
    fill = (0xFF << (8 - px)) & 0xFF
    return bytes((0xFF, fill, fill, fill, 0xFF, 0, 0, 0))


def supers_assets(lines: list[str], charset: bytes, demo_only: set[int], pick_range: range) -> bytes:
    """Barra, icone e tracce degli effetti delle mosse speciali (definizioni in assets.inc).

    Il set di caratteri è pieno: la barra prende in NEXT il posto di BAR_CHARS caratteri di PRESS
    START, che si vede solo nella demo (EVO), contigui e fuori dalle pagine della scelta dei bonus;
    supers.s li scrive a inizio partita, bullet_chars rimette gli originali (restituiti qui, per la
    pagina $FF00) nelle altre partite. Le tracce MOVE e SPECIAL sono quelle della ROM della musica
    (tools/gen_sid_music.py le mette in fondo, dopo i temi, fuori da sid_music.bin): qui si
    prendono da sid_music.hex, con gli indirizzi di sid_music.vh (SID_GEN)."""
    free = sorted(c for c in demo_only if c >= pick_range.stop)
    bar = free[:BAR_CHARS]
    assert bar == list(range(bar[0], bar[0] + BAR_CHARS)), f"caratteri della barra non contigui: {bar}"
    lines.append("; NEXT, mosse speciali: barra al posto di caratteri di PRESS START (supers.s, bullet_chars)")
    lines.append(f"BAR_C0 = {bar[0]}")
    lines.append(f"BAR_CHARS = {BAR_CHARS}")
    glyphs = b"".join(bar_glyph(2 * i) for i in range(BAR_CHARS))
    lines.append(".define BAR_GLYPHS " + ", ".join(f"${b:02X}" for b in glyphs))
    icons = []
    for name in ("STRAIGHT", "RISE"):
        icons += [SUPER_ICONS[name], tuple(mirror8(b) for b in SUPER_ICONS[name])]
    lines.append("; icone della mossa armata: STRAIGHT SHOT sinistro e destro, RISING STRIKE sinistro e destro")
    lines.append(".define SUPER_ICONS " + ", ".join(f"${b:02X}" for icon in icons for b in icon))
    vh = SID_VH.read_text(encoding="utf-8")
    rom = [int(v, 16) for v in SID_HEX.read_text(encoding="utf-8").split()]

    def param(name: str) -> int:
        for line in vh.splitlines():
            if line.startswith(f"localparam {name} ="):
                return int(line.split("=")[1].split(";")[0])
        raise SystemExit(f"{SID_VH}: manca {name}")

    starts = sorted(int(line.split("12'd")[1].rstrip(";")) for line in vh.splitlines() if "12'd" in line)
    assert param("SID_ROM_SIZE") == len(rom), "sid_music.hex e sid_music.vh non vanno insieme"
    fx = {}
    for line in vh.splitlines():
        if "sid_fx_start =" in line and "3'd" in line:
            fx[int(line.split("3'd")[1].split(":")[0])] = int(line.split("12'd")[1].rstrip(";"))
    for name in ("MOVE", "SPECIAL"):
        start = fx[param(f"SID_FX_{name}")]
        end = min([s for s in starts if s > start] + [len(rom)])
        track = rom[start:end]
        assert track and start >= param("SID_ROM_BASE_SIZE"), name
        lines.append(f".define SID_TRACK_{name} " + ", ".join(f"${b:02X}" for b in track))
    return bytes(charset[8 * bar[0] : 8 * (bar[0] + BAR_CHARS)])


def sprite(w: int, h: int) -> bytes:
    """Sprite hires con un quadrato pieno w x h in alto a sinistra."""
    data = bytearray(64)
    for y in range(h):
        bits = ((1 << w) - 1) << (24 - w)
        data[3 * y : 3 * y + 3] = bits.to_bytes(3, "big")
    return bytes(data)


# ----------------------------------------------------------------------------------- attract
#
# L'attract delle altre versioni è definito su 320x240 a 60 Hz (assets/attract/attract.json): sul
# C64 lo schermo è 320x200 e i frame sono a 50 Hz. Le parti centrali salgono di 20 righe, le
# scritte in basso si avvicinano; i tempi si convertono in frame a 50 Hz.

SPEC = json.loads((ATTRACT / "attract.json").read_text(encoding="utf-8"))
W64, H64 = 320, 200
Y_SHIFT = 20
LABEL_Y = 153          # INSERT COIN / PRESS START a scala 2 (righe di caratteri 19-20)
CREDIT_Y = 176         # CREDIT n / FREE PLAY (riga 22)
COPYRIGHT_Y = 190


def f50(frames60: float) -> int:
    """Frame a 60 Hz -> frame a 50 Hz."""
    return round(frames60 * 50 / 60)


def png_pixels(name: str) -> list[list[bool]]:
    im = Image.open(ATTRACT / f"{name}.png").convert("RGBA")
    w, h = im.size
    return [[im.getpixel((x, y))[3] > 127 for x in range(w)] for y in range(h)]


class Bitmap:
    """Bitmap hires 320x200 a 1 bit (1 = nero sul titolo giallo)."""

    def __init__(self) -> None:
        self.px = [[False] * W64 for _ in range(H64)]

    def put(self, pixels: list[list[bool]], x0: int, y0: int, value: bool = True, scale: int = 1) -> None:
        for y, row in enumerate(pixels):
            for x, lit in enumerate(row):
                if lit:
                    for dy in range(scale):
                        for dx in range(scale):
                            self.px[y0 + scale * y + dy][x0 + scale * x + dx] = value

    def rect(self, x0: int, y0: int, w: int, h: int) -> None:
        for y in range(y0, y0 + h):
            for x in range(max(0, x0), min(W64, x0 + w)):
                self.px[y][x] = True

    def cells(self, c0: int, c1: int, r0: int, r1: int) -> bytes:
        """Byte delle celle (colonne c0..c1, righe di celle r0..r1), nell'ordine della memoria del VIC."""
        out = bytearray()
        for cy in range(r0, r1 + 1):
            for cx in range(c0, c1 + 1):
                for row in range(8):
                    b = 0
                    for x in range(8):
                        if self.px[cy * 8 + row][cx * 8 + x]:
                            b |= 0x80 >> x
                    out.append(b)
        return bytes(out)

    def c64(self) -> bytes:
        return self.cells(0, 39, 0, 24)


def centered(width: int) -> int:
    return round((W64 - width) / 2)


def attract_assets(lines: list[str]) -> dict[str, bytes]:
    st, logo, ws, t = SPEC["stripes"], SPEC["logo"], SPEC["ws"], SPEC["title"]
    rows = [int(r) - Y_SHIFT for r in st["rows"]]
    height, left_end, right_start = int(st["height"]), int(st["left_end"]), int(st["right_start"])
    logo_px, ws_px = png_pixels("logo"), png_pixels("ws")
    lx, ly = int(logo["x"]), int(logo["y"]) - Y_SHIFT
    wx, wy = int(ws["x"]), int(ws["y"]) - Y_SHIFT
    # titolo completo: strisce, WS (giallo dentro la striscia), logo, copyright
    title = Bitmap()
    for r in rows:
        title.rect(0, r, left_end, height)
        title.rect(right_start, r, W64 - right_start, height)
    title.put(ws_px, wx, wy, value=False)
    title.put(logo_px, lx, ly)
    cp = png_pixels("copyright")
    title.put(cp, centered(len(cp[0])), COPYRIGHT_Y)
    # scritte che cambiano: tutte le varianti nelle stesse celle, così la nuova copre la vecchia
    def strip(variants: list[list[tuple[list[list[bool]], int]]], y: int, scale: int, cell_rows: int):
        x0 = min(x for parts in variants for _, x in parts)
        x1 = max(x + scale * len(p[0]) for parts in variants for p, x in parts)
        c0, c1 = x0 // 8, (x1 - 1) // 8
        r0 = y // 8
        data = bytearray()
        for parts in variants:
            bm = Bitmap()
            for p, x in parts:
                bm.put(p, x, y, scale=scale)
            data += bm.cells(c0, c1, r0, r0 + cell_rows - 1)
        return c0, c1 - c0 + 1, r0, bytes(data)

    def label(name: str) -> list[tuple[list[list[bool]], int]]:
        p = png_pixels(name)
        return [(p, centered(2 * len(p[0])))]

    lab_c0, lab_w, lab_r0, labels = strip([label("insert_coin"), label("press_start")], LABEL_Y, 2, 2)

    def credit(parts: list[str]) -> list[tuple[list[list[bool]], int]]:
        pix = [png_pixels(n) for n in parts]
        x = centered(sum(len(p[0]) for p in pix))
        out = []
        for p in pix:
            out.append((p, x))
            x += len(p[0])
        return out

    credit_variants = [credit(["free_play"])] + [credit(["credit", f"digit_{n}"]) for n in range(10)]
    cr_c0, cr_w, cr_r0, credits = strip(credit_variants, CREDIT_Y, 1, 1)
    # bordi delle strisce a 50 Hz (la tabella dell'attract è a 60 Hz, in millesimi)
    slide60 = st["slide"]
    n50 = f50(len(slide60) - 1) + 1
    prog = [slide60[min(len(slide60) - 1, round(k * 60 / 50))] / 1000 for k in range(n50)]
    left = [round(left_end * p) for p in prog]
    right = [round((W64 - right_start) * p) for p in prog]
    fr = SPEC["frames"]
    b = SPEC["boot"]
    consts = {
        "AT_BOOT_FRAMES": f50(fr["boot"]),
        "AT_STRIPES_FRAMES": f50(fr["stripes"]),
        "AT_LOGO_FRAMES": f50(fr["logo"]),
        "AT_TITLE_FRAMES": f50(fr["title"]),
        "AT_DEMO_FRAMES": f50(fr["demo"]),
        "AT_GAME_OVER_FRAMES": f50(fr["game_over"]),
        "AT_BOOT_LINE_FRAMES": f50(b["line_frames"]),
        "AT_BOOT_GRID_FROM": f50(b["grid_from"]),
        "AT_CURSOR_HALF": f50(b["cursor_period"] / 2),
        "AT_STRIPE_STEP": f50(st["start_step"]),
        "AT_SLIDE_LAST": n50 - 1,
        "AT_STRIPE_H": height,
        "AT_STRIPE_LEFT": left_end,
        "AT_STRIPE_RIGHT": right_start,
        "AT_LOGO_Y": ly,
        "AT_LOGO_H": len(logo_px),
        "AT_LOGO_X": lx,
        "AT_LOGO_W": len(logo_px[0]),
        "AT_LOGO_C0": lx // 8,
        "AT_LOGO_C1": (lx + len(logo_px[0]) - 1) // 8,
        "AT_WIPE_FRAMES": f50(logo["wipe_frames"]),
        "AT_FLASH_FRAMES": int(logo["flash_frames"]),
        "AT_WS_Y": wy,
        "AT_WS_H": len(ws_px),
        "AT_WS_C0": wx // 8,
        "AT_WS_C1": (wx + len(ws_px[0]) - 1) // 8,
        "AT_BLINK_PERIOD": f50(t["blink_period"]),
        "AT_BLINK_ON": f50(t["blink_on"]),
        "AT_LABEL_FROM": f50(t["label_from"]),
        "AT_LABEL_C0": lab_c0,
        "AT_LABEL_W": lab_w,
        "AT_LABEL_R0": lab_r0,
        "AT_CREDIT_C0": cr_c0,
        "AT_CREDIT_W": cr_w,
        "AT_CREDIT_R0": cr_r0,
        # pallina del titolo: posizione e velocità in pixel * 64, a 50 Hz
        "AT_BALL_X": int(t["ball"]["x"]) * 64,
        "AT_BALL_Y": (int(t["ball"]["y"]) - Y_SHIFT) * 64,
        "AT_BALL_VX": round(t["ball"]["vx"] * 60 / 50 * 64),
        "AT_BALL_VY": round(t["ball"]["vy"] * 60 / 50 * 64),
        "AT_BALL_SIZE": int(t["ball"]["size"]),
        "AT_COPYRIGHT_Y": COPYRIGHT_Y,
        "AT_COPYRIGHT_H": len(cp),
    }
    lines.append("")
    lines.append("; attract (attract.json riportato a 320x200 e 50 Hz)")
    lines += [f"{k} = {v}" for k, v in consts.items()]
    for i, r in enumerate(rows):
        lines.append(f"AT_STRIPE_Y{i} = {r}")
    off = [(f50(a), f50(b2)) for a, b2 in ws["off"]]
    lines.append(".define AT_WS_OFF " + ", ".join(f"{a}, {b2}" for a, b2 in off))
    lines.append("; strisce: pixel coperti a sinistra e a destra, frame per frame")
    lines.append(".define AT_SLIDE_LEFT " + ", ".join(map(str, left)))
    lines.append(".define AT_SLIDE_RIGHT " + ", ".join(map(str, right)))
    # del titolo servono solo le righe di caratteri con il logo e WS (blocco A) e con il copyright
    # (blocco B): l'attract li copia nella bitmap a schermo
    # del blocco A solo le colonne del logo e di WS
    full = title.c64()
    a0, a1 = min(ly, wy) // 8, (max(ly + len(logo_px), wy + len(ws_px)) - 1) // 8 + 1
    b0, b1 = COPYRIGHT_Y // 8, (COPYRIGHT_Y + len(cp) - 1) // 8 + 1
    c0, c1 = lx // 8, (wx + len(ws_px[0]) - 1) // 8 + 1
    assert a1 <= b0 and c0 <= wx // 8
    lines.append(f"TITLE_A_ROW = {a0}    ; righe di caratteri del blocco A in title.bin, poi il B")
    lines.append(f"TITLE_A_END = {a1}")
    lines.append(f"TITLE_A_C0 = {c0}    ; colonne del blocco A (il B è largo tutto lo schermo)")
    lines.append(f"TITLE_A_W = {c1 - c0}")
    lines.append(f"TITLE_B_ROW = {b0}")
    lines.append(f"TITLE_B_END = {b1}")
    slim = b"".join(full[r * 320 + c0 * 8:r * 320 + c1 * 8] for r in range(a0, a1))
    slim += full[b0 * 320:b1 * 320]
    # nella cartuccia (pick_bank.bin): l'avvio lo copia sotto l'I/O
    lines.append(f"TITLE_SIZE = {len(slim)}    ; byte di title.bin")
    return {"title.bin": slim, "labels.bin": labels, "credits.bin": credits}


# Finale di CHALLENGE (src/ending.s): un set di caratteri suo, che il finale copia sopra quello del
# programma (e alla fine rimette): il font monospazio resta ai suoi codici (le routine del
# programma scrivono con FONT_MAP), il resto è del finale
END_FW_BASE = 192      # fuochi d'artificio, multicolore: codice = base + colore * 16 + quadranti
END_FW_COLORS = 3      # %01 bianco ($D022), %10 giallo ($D023), %11 rosso (colore del carattere)
END_BIG = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ!"     # scala 2: 2x2 caratteri per lettera
END_STAMP_W, END_STAMP_H = 5, 3                     # timbro DEFEATED: caratteri
# lettere 3x5 del timbro
STAMP_FONT = {
    "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
    "E": ["XXX", "X..", "XX.", "X..", "XXX"],
    "F": ["XXX", "X..", "XX.", "X..", "X.."],
    "A": ["XXX", "X.X", "XXX", "X.X", "X.X"],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
}


def stamp_pixels() -> list[list[bool]]:
    """Timbro DEFEATED inclinato di 18 gradi (in salita verso destra) in 40x24 pixel: le lettere 3x5
    a scaletta lungo la base inclinata, il riquadro con le linee inclinate."""
    import math
    w, h = 8 * END_STAMP_W, 8 * END_STAMP_H
    px = [[False] * w for _ in range(h)]

    def put(x: int, y: int) -> None:
        if 0 <= x < w and 0 <= y < h:
            px[y][x] = True

    ang = math.radians(18)
    cx, cy = w / 2, h / 2
    text = "DEFEATED"
    tw = len(text) * 4 - 1
    for i, ch in enumerate(text):
        lx = -tw / 2 + i * 4 + 1.5
        x0 = round(cx + lx * math.cos(ang) - 1.5)
        y0 = round(cy - lx * math.sin(ang) - 2.5)
        for r, row in enumerate(STAMP_FONT[ch]):
            for c, v in enumerate(row):
                if v == "X":
                    put(x0 + c, y0 + r)
    hw, hh = tw / 2 + 2, 6.0
    corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
    pts = [(cx + x * math.cos(ang) + y * math.sin(ang), cy - x * math.sin(ang) + y * math.cos(ang)) for x, y in corners]
    for i in range(4):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for k in range(n + 1):
            t = k / n
            put(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t))
    return px


def fw_glyph(color: int, mask: int) -> Tile:
    """Carattere multicolore dei fuochi: un punto di 2x2 pixel al centro di ogni quadrante acceso
    (bit 0 alto a sinistra, 1 alto a destra, 2 basso a sinistra, 3 basso a destra), sulla griglia
    di 4 pixel; colore 0 bianco (%01), 1 giallo (%10), 2 rosso (%11)."""
    pair = color + 1
    rows = [0] * 8
    for q in range(4):
        if mask >> q & 1:
            col = 2 * (q & 1) + 1                   # pixel multicolore 1 o 3 (pixel 2-3 o 6-7)
            for r in (4 * (q >> 1) + 1, 4 * (q >> 1) + 2):
                rows[r] |= pair << (6 - 2 * col)
    return tuple(rows)


# Titoli di coda, come CREDITS di rust/game/src/ending_ui.rs: titolo grande (2 righe), titolo di
# sezione, voce; GAP lascia due righe in più. Il titolo finale va su due righe grandi.
END_CREDITS = [
    ("big", "PADD WS"),
    ("head", "GAME DESIGN AND PROGRAMMING"),
    ("text", "SCHERMOBIANCO"),
    ("head", "PLATFORMS"),
    ("text", "PC  WEB  RASPBERRY PI"),
    ("text", "MISTER FPGA"),
    ("text", "COMMODORE 64"),
    ("head", "MUSIC AND SOUND"),
    ("text", "ORIGINAL SID MUSIC"),
    ("text", "SID SOUND EFFECTS"),
    ("text", "ANNOUNCER VOICES"),
    ("head", "THE CHALLENGERS"),
    ("text", "ARCADE   TITAN   HAMMER"),
    ("text", "TWIST   BLASTER   RUSH"),
    ("text", "AND GUARDIAN"),
    ("head", "THIRD-PARTY WORKS"),
    ("text", "MUNRO FONT  ED MERRITT"),
    ("text", "PONG SCORE FONT  PWNZOR.AK"),
    ("text", "MISTER FRAMEWORK  SORGELIG"),
    ("text", "SID EMULATION  DAG LEM  A. MELNIKOV"),
    ("text", "VEXRISCV  SPINALHDL"),
    ("text", "MACROQUAD  FEDOR LOGACHEV"),
    ("text", "GILRS  SDL GAMECONTROLLERDB"),
    ("text", "PYTHON ARCADE  PIGPIO"),
    ("head", "SPECIAL THANKS"),
    ("text", "THE MISTER FPGA COMMUNITY"),
    ("text", "THE COMMODORE 64 SCENE"),
    ("gap", ""),
    ("big", "THANK YOU"),
    ("big", "FOR PLAYING"),
]
CRED_STYLE = {"text": 0, "head": 1, "big": 2}
CRED_BLANK = {"text": 1, "head": 2, "big": 2}       # righe vuote prima della riga


def credits_tables() -> list[str]:
    """Titoli di coda in righe virtuali (da 0, la prima riga): per riga il numero della riga di testo
    (da 1; con il bit 7 la seconda riga di un titolo grande), per riga di testo colonna, stile,
    lunghezza e testo."""
    rows: list[int] = []
    cols, styles, lens, offs, texts = [], [], [], [], []
    extra = 0
    off = 0
    for kind, text in END_CREDITS:
        if kind == "gap":
            extra = 2
            continue
        assert all(c in FONT_DRAWN + " " for c in text), text
        big = kind == "big"
        width = len(text) * (2 if big else 1)
        assert width <= 40, text
        if rows:
            rows += [0] * (CRED_BLANK[kind] + extra)
        extra = 0
        n = len(cols) + 1
        rows.append(n)
        if big:
            rows.append(n | 0x80)
        cols.append((40 - width) // 2)
        styles.append(CRED_STYLE[kind])
        lens.append(len(text))
        offs.append(off)
        texts.append(text)
        off += len(text)
    last = max(i for i, r in enumerate(rows) if r and not r & 0x80)
    return [
        "; titoli di coda (righe virtuali da 0): per riga 0 o la riga di testo (da 1, bit 7: seconda",
        "; riga di un titolo grande); per riga di testo colonna, stile (0 voce bianca, 1 titolo giallo,",
        "; 2 grande giallo), lunghezza, inizio nel testo",
        f"END_CRED_LINES = {len(cols)}",
        f"END_CRED_ROWS = {len(rows)}",
        f"END_CRED_LAST = {last}    ; prima riga dell'ultima riga di testo",
        ".define END_CRED_ROW " + ", ".join(str(r) for r in rows),
        ".define END_CRED_COL " + ", ".join(str(c) for c in cols),
        ".define END_CRED_STYLE " + ", ".join(str(s) for s in styles),
        ".define END_CRED_LEN " + ", ".join(str(n) for n in lens),
        ".define END_CRED_OFF " + ", ".join(str(o) for o in offs),
        ".define END_CRED_TEXT " + ", ".join(f'"{t}"' for t in texts),
    ]


# Fuochi d'artificio (fireworks.py e ending_ui.rs): un passo ogni FW_FRAMES frame (16,7 al secondo,
# FW_T del passo del PC a 15), posizioni sulla griglia di 4 pixel (80x50, la parte alta dello
# schermo) in 8.8, velocità con segno in 1/256 di griglia per passo, gravità in 1/256 per passo al
# quadrato, attrito v -= v >> 5. Il razzo è uno sprite che sale in FW_RISE frame.
FW_FRAMES = 3
FW_T = FW_FRAMES / 50 * 15
FW_UNIT = 200 / 480 / 4                 # griglia per unità dello schermo alto 480
FW_RISE = 45                            # frame del razzo (14 passi del PC)
FW_GRAV = 3
FW_SLOTS, FW_MAX = 4, 24                # fuochi accesi insieme, scintille per fuoco
FW_CHAMPION = 350                       # frame di YOU ARE THE PADD WS CHAMPION


def fireworks_tables() -> list[str]:
    import math
    import random

    def v(speed: float, ang: float) -> tuple[int, int]:
        s = speed * FW_UNIT * FW_T * 256
        vx, vy = round(s * math.cos(ang)), round(s * math.sin(ang))
        assert -128 <= vx <= 127 and -128 <= vy <= 127, (speed, vx, vy)
        return vx & 0xFF, vy & 0xFF

    def ring(n: int, speed: float, color: int, phase: float = 0.0) -> list[tuple[int, int, int]]:
        return [(*v(speed, phase + a * math.tau / n), color) for a in range(n)]

    W, Y, R = 0xC0, 0xD0, 0xE0              # codice dei caratteri per colore (END_FW_BASE)
    life = lambda t: math.ceil(t / FW_T)    # noqa: E731 (passi del PC -> passi del C64)
    rng = random.Random(0xF1AE2026)
    crackle = []
    for i in range(20):
        ang = rng.uniform(0, math.tau)
        crackle.append((*v(0.5 + rng.uniform(0, 3.5), ang), W))
    split = life(12)
    cross = [(*v(4.5, a * math.pi / 2 + math.pi / 4), W) for a in range(4) for _ in range(4)]
    cross_split = [(*v(2.5, a * math.pi / 2 + math.pi / 4 + (b - 1.5) * 0.5), Y) for a in range(4) for b in range(4)]
    # tipo: scintille, vita, gravità, attrito (shift, 0 = niente), scia, blocco, divisione, crepitio
    kinds = [
        ("RING", ring(18, 4.0, Y), life(26), FW_GRAV, 5, 0, 0, 0, 0),
        ("WILLOW", ring(12, 2.6, Y, 0.13), life(50), FW_GRAV, 5, 2, 0, 0, 0),
        ("PALM", ring(7, 4.5, R, 0.3), life(34), FW_GRAV, 5, 2, 0, 0, 0),
        ("CHRYSANTHEMUM", ring(8, 2.2, W, 0.2) + ring(14, 4.2, R), life(30), FW_GRAV, 5, 0, 0, 0, 0),
        ("CRACKLE", crackle, life(40), 2, 0, 0, life(18), 0, 1),
        ("CROSSETTE", cross, life(34), FW_GRAV, 0, 0, 0, split, 0),
    ]
    vx, vy, vc = [], [], []
    rows = {k: [] for k in ("N", "LIFE", "GRAV", "DRAG", "TRAIL", "FREEZE", "SPLIT", "FLICK", "OFF")}
    for name, parts, lf, grav, drag, trail, freeze, spl, flick in kinds:
        assert len(parts) <= FW_MAX and lf < 128
        for key, val in zip(rows, (len(parts), lf, grav, drag, trail, freeze, spl, flick, len(vx))):
            rows[key].append(val)
        for x, y, c in parts:
            vx.append(x)
            vy.append(y)
            vc.append(c)
    split_off = len(vx)
    for x, y, c in cross_split:
        vx.append(x)
        vy.append(y)
        vc.append(c)
    assert len(vx) < 256
    # lo spettacolo: i tipi a turno, uno ogni 7-14 passi fino a poco prima della fine
    show = []
    last = FW_CHAMPION // FW_FRAMES - life(30)
    start = 0
    rng = random.Random(0x2026F1AE)
    while start < last:
        gx = round((54 + rng.uniform(0, 212)) / 4)
        gy = round((70 + rng.uniform(0, 160)) * 200 / 480 / 4)
        cy = gy * 4 + 2
        v0 = round((200 - cy) * 256 / (FW_RISE / 2 + 0.5))
        acc = round(v0 / FW_RISE)
        assert v0 < 0x10000 and acc < 256
        show.append((start, len(show) % len(kinds), gx, gy, v0, acc))
        start += round((6 + rng.randrange(8)) / FW_T)
    lines = [
        "; fuochi d'artificio: tipi (anello, salice, palma, crisantemo, crepitio, croce che si divide)",
        f"FW_FRAMES = {FW_FRAMES}    ; frame per passo",
        f"FW_RISE = {FW_RISE}    ; frame del razzo",
        f"FW_SLOTS = {FW_SLOTS}",
        f"FW_MAX = {FW_MAX}",
        f"FW_KINDS = {len(kinds)}",
        f"FW_SPLIT_OFF = {split_off}    ; velocità dopo la divisione (CROSSETTE)",
        f"FW_SHOW = {len(show)}",
    ]
    for key, vals in rows.items():
        lines.append(f".define FW_K_{key} " + ", ".join(str(x) for x in vals))
    lines.append(".define FW_VX " + ", ".join(str(x) for x in vx))
    lines.append(".define FW_VY " + ", ".join(str(x) for x in vy))
    lines.append(".define FW_VC " + ", ".join(str(x) for x in vc))
    for i, key in enumerate(("STEP", "KIND", "GX", "GY")):
        lines.append(f".define FW_S_{key} " + ", ".join(str(s[i]) for s in show) + ", 255" * (key == "STEP"))
    lines.append(".define FW_S_V0 " + ", ".join(str(s[4]) for s in show))
    lines.append(".define FW_S_ACC " + ", ".join(str(s[5]) for s in show))
    return lines


def ending_assets(charset: bytes, font: list[int]) -> tuple[bytes, list[str]]:
    """Set di caratteri del finale (2 KB) e le sue costanti (ending.inc)."""
    keep = {0} | {c for c in font if c}
    tiles: dict[int, Tile] = {c: tuple(charset[8 * c : 8 * c + 8]) for c in keep}
    fw_codes = range(END_FW_BASE, END_FW_BASE + 16 * END_FW_COLORS)
    for color in range(END_FW_COLORS):
        for mask in range(16):
            tiles[END_FW_BASE + 16 * color + mask] = fw_glyph(color, mask) if mask else (0,) * 8
    free = [c for c in range(1, 256) if c not in keep and c not in fw_codes]
    index: dict[Tile, int] = {}

    def add(tile: Tile) -> int:
        if not any(tile):
            return 0
        if tile in index:
            return index[tile]
        code = free.pop(0)
        tiles[code] = tile
        index[tile] = code
        return code

    lines = ["; Generato da tools/gen_c64_assets.py: non modificare a mano.", "",
             "; finale di CHALLENGE (src/ending.s): set di caratteri ending_chars.bin", ""]
    # scala 2: ogni pixel del font monospazio diventa 2x2, quattro caratteri per lettera
    font_map = {ch: font[i] for i, ch in enumerate(FONT_CHARS)}
    big = []
    for ch in END_BIG:
        t = tiles[font_map[ch]]
        px = [[bool(t[y // 2] & 0x80 >> (x // 2)) for x in range(16)] for y in range(16)]
        big.append([add(tile) for row in tiles_of(px, 2, 2) for tile in row])
    # indice della lettera grande per ASCII 32-95 (0 = spazio)
    idx = [END_BIG.index(ch) + 1 if ch in END_BIG else 0 for ch in FONT_CHARS]
    lines.append("; scala 2: indice (da 1) per ASCII 32-95, poi i caratteri in alto a sinistra, in alto")
    lines.append("; a destra, in basso a sinistra, in basso a destra (indice 0 = spazio)")
    lines.append(".define END_BIG_IDX " + ", ".join(str(i) for i in idx))
    for q, name in enumerate(("TL", "TR", "BL", "BR")):
        lines.append(f".define END_BIG_{name} 0, " + ", ".join(str(b[q]) for b in big))
    stamp = stamp_pixels()
    codes = [add(t) for row in tiles_of(stamp, END_STAMP_W, END_STAMP_H) for t in row]
    lines.append(f"END_STAMP_W = {END_STAMP_W}")
    lines.append(f"END_STAMP_H = {END_STAMP_H}")
    lines.append(".define END_STAMP " + ", ".join(str(c) for c in codes))
    lines.append(f"END_FW_BASE = {END_FW_BASE}    ; fuochi: base + colore * 16 + quadranti (multicolore)")
    lines.append(f"END_CHARS_USED = {256 - len(free)}")
    lines += credits_tables() + fireworks_tables()
    out = bytearray(2048)
    for c, t in tiles.items():
        out[8 * c : 8 * c + 8] = bytes(t)
    return bytes(out), lines


def voice_files() -> dict[str, bytes]:
    """Campioni delle voci di CHALLENGE, uno per tipo di racchetta: i .raw4 come sono (16 livelli in
    due nibble, 8 = silenzio), controllati perché il player li suona fino all'ultimo byte."""
    files = {}
    for kind, name in enumerate(VOICE_NAMES):
        raw = (VOICES / f"{name.lower()}.raw4").read_bytes()
        assert raw, name    # (che con il player stia in VOICE_PAGES pagine lo controlla voice.s)
        files[f"voice{kind}.bin"] = raw
    # READY e GO del conto alla rovescia, uguali per tutti: solo nel file del primo livello; YOU
    # WIN nel banco della vittoria (tools/make_crt.py), per il GAME OVER e il finale
    for name in ("ready", "go", "you_win"):
        raw = (VOICES / f"{name}.raw4").read_bytes()
        assert raw, name
        files[f"{name}.bin"] = raw
    return files


def main() -> None:
    cs = Charset()
    lines: list[str] = ["; Generato da tools/gen_c64_assets.py: non modificare a mano.", ""]
    blank = cs.add((0,) * 8)
    # mezzeria: due pixel a cavallo tra le colonne 19 e 20 (x = 159 e 160), 4 righe accese e 4 spente
    line_l = cs.add((1, 1, 1, 1, 0, 0, 0, 0), unique=True)
    line_r = cs.add((0x80, 0x80, 0x80, 0x80, 0, 0, 0, 0), unique=True)
    # muro del singolo: x 298-301, colonna 37, pixel 2-5
    wall = cs.add((0x3C,) * 8, unique=True)
    lines += [
        f"CH_BLANK  = {blank}",
        f"CH_LINE_L = {line_l}    ; mezzeria, colonna 19",
        f"CH_LINE_R = {line_r}    ; mezzeria, colonna 20",
        f"CH_WALL   = {wall}    ; muro del singolo, colonna 37",
        "",
    ]
    digits = score_digits(cs)
    lines.append("; cifre del punteggio: 9 caratteri per cifra (3 righe di 3)")
    lines.append(".define SCORE_TILES " + ", ".join(str(c) for d in digits for c in d))
    font = text_font(cs)
    lines.append("; font monospazio: codice del carattere per ASCII 32-95")
    lines.append(".define FONT_MAP " + ", ".join(str(c) for c in font))
    font_first, font_last = min(c for c in font if c), max(font)
    assert font_last - font_first + 1 == len(set(font) - {0}), "font non contiguo"
    lines.append(f"FONT_FIRST = {font_first}")
    lines.append(f"FONT_CHARS = {font_last - font_first + 1}")
    demo_only: set[int] = set()     # caratteri di INSERT COIN e PRESS START, solo nella demo (EVO)
    assert BIG_TEXTS[-2:] == ["insert_coin", "press_start"]
    big_from = 0
    big_given = len(cs.given)
    big_tiles = len(cs.tiles)
    for name in BIG_TEXTS:
        first = len(cs.tiles)
        if name == "insert_coin":
            big_from = len(cs.given)
        w, codes = big_text(cs, name)
        if name in ("insert_coin", "press_start"):
            demo_only |= {c for c in codes if c >= first}
        lines.append(f"BIG_{name.upper()}_W = {w}")
        lines.append(f".define BIG_{name.upper()} " + ", ".join(str(c) for c in codes))
    after_big = len(cs.given)
    big_end = len(cs.tiles)
    # auto-test: cursore a blocco e reticolo (righe ogni 16 pixel, l'ultima in fondo allo schermo)
    cursor = cs.add((0xF8,) * 8, unique=True)
    top, left_line = 0xFF, 0x80
    grid = {
        "GRID_TL": (top,) + (left_line,) * 7,
        "GRID_T": (top,) + (0,) * 7,
        "GRID_L": (left_line,) * 8,
        "GRID_TLB": (top,) + (left_line,) * 6 + (top,),
        "GRID_TB": (top,) + (0,) * 6 + (top,),
    }
    lines.append(f"CH_CURSOR = {cursor}")
    spare = [cursor]
    for name, tile in grid.items():
        code = cs.add(tile)
        spare.append(code)
        lines.append(f"CH_{name} = {code}")
    # caratteri per la capsula del BULLET in NEXT: cursore e reticolo (solo l'auto-test
    # dell'accensione), il muro del singolo e uno di INSERT COIN / PRESS START della demo
    spare.append(wall)
    spare.append(min(demo_only))
    bullet_bytes = next_chars(cs, lines, spare)
    # CHALLENGE: bande della schermata del nuovo sfidante (HERE COMES A NEW CHALLENGER!)
    lines.append(f"CH_SOLID = {cs.add((0xFF,) * 8, unique=True)}")
    files = attract_assets(lines)
    # i caratteri presi dal BULLET non servono ad altro: quelli dell'auto-test e il muro dati una
    # volta sola, quello della demo solo a INSERT COIN e PRESS START
    for c in spare[:-1]:
        assert cs.given.count(c) == 1, c
    assert spare[-1] not in cs.given[:big_from] + cs.given[after_big:], spare[-1]
    lines.append(f"CHARSET_USED = {len(cs.tiles)}")
    OUT.mkdir(parents=True, exist_ok=True)
    charset = bytearray(2048)
    for i, t in enumerate(cs.tiles):
        charset[8 * i : 8 * i + 8] = bytes(t)
    (OUT / "charset.bin").write_bytes(bytes(charset))
    end_chars, end_lines = ending_assets(bytes(charset), font)
    (OUT / "ending_chars.bin").write_bytes(end_chars)
    (OUT / "ending.inc").write_text("\n".join(end_lines) + "\n", encoding="utf-8", newline="\n")
    # scelta dei bonus: le metà delle lettere del font (codice + PICK_TOP la alta, abbassata di 4
    # pixel; + PICK_BOTTOM la bassa, in cima al carattere) al posto delle scritte grandi, che nella
    # scelta non ci sono (né altri usi di quei caratteri: il BULLET ne prende uno solo in partita)
    pick_range = range(PICK_FIRST, PICK_FIRST + PICK_PAGES * 32)
    assert big_tiles <= pick_range.start and pick_range.stop <= big_end, (big_tiles, big_end)
    assert not any(c in pick_range for c in cs.given[:big_given] + cs.given[after_big:] if c != spare[-1])
    n = font_last - font_first + 1
    assert PICK_FIRST + 2 * n <= pick_range.stop
    pick = bytearray(charset)
    for i in range(n):
        t = cs.tiles[font_first + i]
        pick[8 * (PICK_FIRST + i) : 8 * (PICK_FIRST + i) + 8] = bytes(4) + bytes(t[:4])
        pick[8 * (PICK_FIRST + n + i) : 8 * (PICK_FIRST + n + i) + 8] = bytes(t[4:]) + bytes(4)
    # pagina $FF00: bitmap (vuota), caratteri del BULLET a $FF40, RTS a $FFC0 (VOICE_COUNT), poi
    # gli originali dei caratteri della barra delle mosse speciali (supers_assets)
    page = bytearray(256)
    page[0x40:0xC0] = bullet_bytes
    page[0xC0] = 0x60
    page[BAR_ORIG : BAR_ORIG + 8 * BAR_CHARS] = supers_assets(lines, charset, demo_only, pick_range)
    title = files["title.bin"]
    assert len(title) <= 0x800
    (OUT / "pick_bank.bin").write_bytes(bytes(pick) + bytes(page) + title + bytes(0x800 - len(title)))
    lines.append(f"PICK_FIRST = {PICK_FIRST}    ; scelta dei bonus: caratteri sostituiti (pagine intere)")
    lines.append(f"PICK_PAGES = {PICK_PAGES}")
    # sprite: palla 4x4, palla 6x6, due posti per le racchette (rifatte a ogni frame), linea di
    # 24 pixel e di 8 (il raster che scende sul logo), banda grigia EVO larga 4 pixel e alta 1-10
    # righe (non espansa, sopra la racchetta: la banda cade sulla riga esatta)
    line24, line8 = bytearray(64), bytearray(64)
    line24[0:3] = b"\xff\xff\xff"
    line8[0] = 0xFF
    bands = b"".join(sprite(4, h) for h in range(1, SPRITE_BANDS + 1))
    lines.append(f"SPRITE_BANDS = {SPRITE_BANDS}")
    # NEXT: capsule (8 più il SUPER in negativo) e icone del bonus armato (7, non il BULLET)
    nxt, nxt_lines = next_sprites()
    lines += nxt_lines
    sprites = sprite(4, 4) + sprite(6, 6) + bytes(128) + bytes(line24) + bytes(line8) + bands + nxt
    lines.append(f"SPRITES_N = {len(sprites) // 64}")
    (OUT / "sprites.bin").write_bytes(sprites)
    _, fx_lines = next_fx_sprites()
    lines += fx_lines
    lines += fx_squares()
    files |= voice_files()
    for name, data in files.items():
        (OUT / name).write_bytes(data)
    (OUT / "assets.inc").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"c64/gen: {len(cs.tiles)} caratteri su 256, {len(sprites) // 64} sprite, attract")


if __name__ == "__main__":
    main()
