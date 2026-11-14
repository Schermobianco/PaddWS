"""Genera la grafica del finale della CHALLENGE per il core MiSTer (mister/rtl/ending_render.v), come
rust/game/src/ending_ui.rs su uno schermo 320x240.

Uso:
    python tools/gen_ending_assets.py [--preview CARTELLA]

Uscite in mister/rtl/gen/:
- ending_text.hex: righe di bitmap a 1 bit larghe 160 pixel (20 byte per riga, bit 0 = pixel a
  sinistra), un byte per riga del file. Le scritte sono in Munro 10 px (le righe comuni di tutte le
  scritte, la stessa linea di base), il renderer le ingrandisce 2 o 3 volte; le righe uguali si
  tengono una volta sola. In fondo, contigue, le cifre "0123456789+" in celle larghe END_CELL e il
  timbro DEFEATED già ruotato (64x36);
- ending_map.hex: la mappa delle righe, una parola da 32 bit per riga dello schermo di ogni parte
  (le finestre END_WIN_* delle parti fisse, poi i titoli di coda, che scorrono): riga della bitmap,
  riga del glifo, x della scritta, scala, colore, gruppo (le scritte che compaiono dopo) e numero
  della riga (SCORE, premio, totale), vedi `map_word`;
- ending_fw.hex: i fuochi d'artificio, parole da 16 bit: prima l'indice, due parole (inizio e
  numero dei punti) per ogni fuoco e frame a 15 Hz (fuoco * 80 + frame), poi i punti, celle di
  2x2 pixel relative al punto dello scoppio (dx 6 bit e dy 8 bit con segno, colore 2 bit). I punti
  sono quelli di ending_ui.rs (razzo, sei tipi di scoppio, scintille che si diradano), già portati
  alla griglia 160x120 e senza doppioni; i fuochi dello stesso tipo hanno gli stessi punti;
- pong_ending.vh: durate delle parti, finestre della mappa, posizioni, tabella dei fuochi.

Solo bianco, giallo e rosso, come su PC.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "mister" / "rtl" / "gen"
FONT = ROOT / "assets" / "fonts" / "munro.ttf"
W, H = 320, 240
ROW_W = 160                      # larghezza di una riga della bitmap (le scritte a scala 1)
f10 = ImageFont.truetype(str(FONT), 10)

# colori della mappa
C_WHITE, C_YELLOW, C_RED, C_FLASH = 0, 1, 2, 3
# numeri delle righe del punteggio
N_NONE, N_SCORE, N_BONUS, N_TOTAL = 0, 1, 2, 3

# ------------------------------------------------------------------ tempi (frame a 60 Hz)

FPS = 60
CONGRATS, PARADE, SCORE, CHAMPION, THE_END = 3.5, 9.0, 9.0, 7.0, 3.0
YOU_WIN_AT = 1.0
PARADE_STEP, STAMP_AFTER = 1.0, 0.5
SCORE_COUNT, BONUS_COUNT, TOTAL_AT = 3.0, 1.0, 4.5
CREDITS_SPEED, CREDITS_HOLD = 70.0, 2.0      # unità a 480 righe al secondo
SKIP_AFTER = 0.5
FLASH_CONGRATS, FLASH_END = 0.5, 0.66

CREDITS = [
    ("title", "PADD WS"),
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
    ("title", "THANK YOU FOR PLAYING"),
]
ADVANCE = {"title": 70.0, "head": 70.0, "text": 38.0, "gap": 60.0}
# a 320x240 (Munro 10 px a scala n = corpo / 20 del gioco Rust): titoli a scala 3 gialli, sezioni a
# scala 2 gialle, voci a scala 2 bianche
CRED_STYLE = {"title": (3, C_YELLOW), "head": (2, C_YELLOW), "text": (2, C_WHITE)}


def frames(s: float) -> int:
    return round(s * FPS)


def credits_layout() -> list[tuple[str, str, float]]:
    y, out = 0.0, []
    for kind, text in CREDITS:
        y += ADVANCE[kind]
        out.append((kind, text, y))
    return out


def credits_seconds() -> float:
    return (20.0 + 240.0 + credits_layout()[-1][2]) / CREDITS_SPEED


PART_LEN = [frames(CONGRATS), frames(PARADE), frames(SCORE), frames(CHAMPION),
            frames(credits_seconds() + CREDITS_HOLD), frames(THE_END)]
CRED_SMAX = round((20.0 + 240.0 + credits_layout()[-1][2]) / 2)    # pixel di scorrimento a 320x240

# ------------------------------------------------------------------ scritte


def render(text: str) -> tuple[int, Image.Image]:
    ascent, descent = f10.getmetrics()
    w = max(1, round(f10.getlength(text)))
    img = Image.new("L", (w + 4, ascent + descent), 0)
    ImageDraw.Draw(img).text((0, 0), text, font=f10, fill=255)
    return w, img.point(lambda v: 255 if v > 127 else 0)


GLYPHS = "0123456789+"


def all_strings() -> list[str]:
    fixed = ["CONGRATULATIONS!", "YOU WIN!", "YOUR OPPONENTS", "FINAL SCORE", "SCORE", "CHAMPION BONUS",
             "TOTAL", "YOU ARE THE", "PADD WS CHAMPION", "THE END"]
    return fixed + [t for k, t in CREDITS if k != "gap"]


class Text:
    """Le scritte a scala 1 con le righe comuni (linea di base unica) e le cifre in celle."""

    def __init__(self) -> None:
        raw = {s: render(s) for s in all_strings()}
        glyphs = [render(c) for c in GLYPHS]
        every = list(raw.values()) + glyphs
        height = every[0][1].height
        rows = [y for y in range(height) if any(img.getpixel((x, y)) for _, img in every for x in range(img.width))]
        self.top, bottom = rows[0], rows[-1]
        self.gh = bottom - self.top + 1
        self.cell = max(w for w, _ in glyphs) + 1
        self.masks: dict[str, list[list[int]]] = {}
        self.width: dict[str, int] = {}
        for s, (w, img) in raw.items():
            if w > ROW_W:
                raise SystemExit(f"scritta troppo larga per una riga di {ROW_W} pixel: {s} ({w})")
            self.width[s] = w
            self.masks[s] = [[1 if img.getpixel((x, self.top + y)) else 0 for x in range(w)] for y in range(self.gh)]
        # cifre centrate nella cella, come il font a celle di gen_challenge_assets.py
        self.strip = [[0] * (len(GLYPHS) * self.cell) for _ in range(self.gh)]
        for i, (w, img) in enumerate(glyphs):
            ox = i * self.cell + (self.cell - 1 - w) // 2
            for y in range(self.gh):
                for x in range(w):
                    if img.getpixel((x, self.top + y)):
                        self.strip[y][ox + x] = 1


def stamp_bitmap() -> list[list[int]]:
    """Segno dell'avversario battuto nella sfilata del MiSTer: "K.O." rosso in Munro 10 a scala 2, a
    pixel pieni, centrato sulla racchetta (che next_render intanto spegne). Il timbro inclinato
    DEFEATED di ending_ui.rs, largo 55 pixel su colonne di 45, a 320x240 si sovrapponeva a quelli
    vicini e a 1 bit non si leggeva."""
    sw, sh, k = 64, 36, 2
    f = ImageFont.truetype(str(FONT), 10)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    left, top, right, bottom = probe.textbbox((0, 0), "K.O.", font=f)
    flat = Image.new("L", (right - left, bottom - top), 0)
    ImageDraw.Draw(flat).text((-left, -top), "K.O.", font=f, fill=255)
    fw, fh = flat.size
    if fw * k > sw or fh * k > sh:
        raise SystemExit(f"K.O. troppo grande per il segno {sw}x{sh}: {fw * k}x{fh * k}")
    out = [[0] * sw for _ in range(sh)]
    x0, y0 = (sw - fw * k) // 2, (sh - fh * k) // 2
    for y in range(fh * k):
        for x in range(fw * k):
            if flat.getpixel((x // k, y // k)) > 127:
                out[y0 + y][x0 + x] = 1
    return out


# ------------------------------------------------------------------ disposizione

# parti: 0 congratulazioni, 1 sfilata, 2 punteggio, 3 campione, 4 titoli, 5 THE END
# righe (centro della scritta a 320x240), scala, colore, gruppo, numero
PARADE_Y = 92                     # centro delle racchette (185 a 480 righe)
PARADE_NAME_Y = 145               # centro dei nomi
STAMP_W, STAMP_H = 64, 36
STAMP_CY = PARADE_Y - 4           # centro del K.O., poco sopra il centro delle racchette


def column_x(i: int) -> int:
    return round(W * (2 * i + 1) / 14)


def score_columns(t: Text) -> tuple[int, int]:
    """Centro delle etichette e x della prima cifra delle righe del punteggio (a scala 2)."""
    lw = max(t.width[s] for s in ("SCORE", "CHAMPION BONUS", "TOTAL")) * 2
    dw = 7 * t.cell * 2
    d = max(lw // 2, dw // 2) + 6
    return W // 2 - d, W // 2 + d - dw // 2


def static_parts(t: Text) -> dict[int, list[tuple]]:
    lx, _ = score_columns(t)
    return {
        0: [("CONGRATULATIONS!", 110, 3, C_FLASH, 0, N_NONE, None),
            ("YOU WIN!", 145, 2, C_WHITE, 1, N_NONE, None)],
        1: [("YOUR OPPONENTS", 25, 2, C_YELLOW, 0, N_NONE, None)],
        2: [("FINAL SCORE", 40, 2, C_YELLOW, 0, N_NONE, None),
            ("SCORE", 80, 2, C_WHITE, 0, N_SCORE, lx),
            ("CHAMPION BONUS", 105, 2, C_YELLOW, 1, N_BONUS, lx),
            ("TOTAL", 145, 2, C_WHITE, 2, N_TOTAL, lx)],
        3: [("YOU ARE THE", 180, 2, C_WHITE, 0, N_NONE, None),
            ("PADD WS CHAMPION", 205, 3, C_YELLOW, 0, N_NONE, None)],
        5: [("THE END", 120, 3, C_FLASH, 0, N_NONE, None)],
    }


def map_word(bitrow: int, g: int, xoff: int, scale: int, color: int, group: int, num: int) -> int:
    assert 0 <= bitrow < 512 and 0 <= g < 16 and 0 <= xoff < 512 and 1 <= scale <= 3
    return bitrow | g << 9 | xoff << 13 | scale << 22 | color << 24 | group << 26 | num << 28


class Builder:
    def __init__(self, t: Text) -> None:
        self.t = t
        self.rows: list[bytes] = []
        self.index: dict[bytes, int] = {}

    def row(self, bits: list[int], dedupe: bool = True) -> int:
        b = bytearray(ROW_W // 8)
        for x, v in enumerate(bits):
            if v:
                b[x >> 3] |= 1 << (x & 7)
        key = bytes(b)
        if dedupe and key in self.index:
            return self.index[key]
        self.rows.append(key)
        if dedupe:
            self.index.setdefault(key, len(self.rows) - 1)
        return len(self.rows) - 1


def lines_of(t: Text, items: list[tuple], b: Builder) -> dict[int, int]:
    """Righe dello schermo -> parola della mappa per un gruppo di scritte (y = centro)."""
    out: dict[int, int] = {}
    for s, cy, scale, color, group, num, cx in items:
        w = t.width[s] * scale
        x0 = (W - w) // 2 if cx is None else cx - w // 2
        y0 = cy - (t.gh * scale) // 2
        for g in range(t.gh):
            bits = t.masks[s][g]
            if not any(bits) and num == N_NONE:
                continue
            br = b.row(bits)
            for k in range(scale):
                y = y0 + g * scale + k
                if y in out:
                    raise SystemExit(f"scritte sovrapposte alla riga {y}: {s}")
                out[y] = map_word(br, g, x0, scale, color, group, num)
    return out


# ------------------------------------------------------------------ fuochi d'artificio

FW_FPS = 15
RISE = 14
G = 0.12
KINDS = ["ring", "willow", "palm", "chrysanthemum", "crackle", "crossette"]
F_WHITE, F_YELLOW, F_RED = 1, 2, 3
MARGIN = 130.0          # come ending_ui.rs con lo schermo 4:3 (640 unità di larghezza a 480 righe)
SKY_W = 640.0
FW_STRIDE = 80          # frame per fuoco nell'indice (razzo e scoppio: al massimo 14 + 62)


class Rng:
    """xorshift32 come paddws_core::Rng."""

    def __init__(self, seed: int) -> None:
        self.s = seed if seed else 0x2545F491

    def next_u32(self) -> int:
        x = self.s
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.s = x
        return x

    def below(self, n: int) -> int:
        return ((self.next_u32() >> 16) * n) >> 16


def show() -> list[dict]:
    rng = Rng(0xF1AE2026)
    last = int(CHAMPION * FW_FPS) - 30
    out: list[dict] = []
    start = 0
    while start < last:
        out.append({"kind": KINDS[len(out) % len(KINDS)], "x": rng.below(1000) / 1000.0,
                    "y": 70.0 + rng.below(160), "start": start, "seed": rng.next_u32() | 1})
        start += 6 + rng.below(8)
    return out


def alive(k: float, i: int, t: int) -> bool:
    return k > 0.0 and ((i * 7 + t * 3) % 10) < k * 10.0


def particles(dots: list, t: int, n: int, speed: float, color: int, life: float, size: int, trail: int,
              drag: float) -> None:
    for a in range(n):
        ang = a * 2 * math.pi / n
        for back in range(trail + 1):
            tt = max(t - back * 2, 0)
            dist = speed * (1.0 - drag ** tt) / (1.0 - drag)
            x = dist * math.cos(ang)
            y = dist * math.sin(ang) + G * (tt * tt) / 2.0
            k = max(1.0 - tt / life, 0.0) * (1.0 - back / (trail + 1))
            if alive(k, a + back, tt):
                dots.append((x, y, size if back == 0 else 1, color))


def burst(kind: str, t: int, seed: int) -> list:
    """Punti (x, y, size, colore) dello scoppio al frame t, unità a 480 righe dal centro."""
    dots: list = []
    if kind == "ring":
        particles(dots, t, 20, 4.0, F_YELLOW, 26.0, 2, 0, 0.97)
    elif kind == "willow":
        particles(dots, t, 24, 2.6, F_YELLOW, 50.0, 1, 6, 0.95)
    elif kind == "palm":
        particles(dots, t, 7, 4.5, F_RED, 34.0, 3, 4, 0.97)
    elif kind == "chrysanthemum":
        particles(dots, t, 16, 2.2, F_WHITE, 28.0, 2, 0, 0.97)
        particles(dots, t, 28, 4.2, F_RED, 30.0, 2, 0, 0.97)
    elif kind == "crackle":
        rng = Rng(seed)
        for i in range(60):
            ang = rng.below(6283) / 1000.0
            v = 0.5 + rng.below(3500) / 1000.0
            dist = v * min(t, 18)
            x = dist * math.cos(ang)
            y = dist * math.sin(ang) + G * (t * t) / 3.0
            if t < 40 and (t + i) % 3 != 0:
                dots.append((x, y, 1, F_WHITE if (t + i) % 2 == 1 else F_YELLOW))
    else:   # crossette
        split = 12
        for a in range(4):
            ang = a * math.pi / 2 + math.pi / 4
            tt = min(t, split)
            bx = 4.5 * tt * math.cos(ang)
            by = 4.5 * tt * math.sin(ang) + G * tt * tt / 2.0
            if t < split:
                dots.append((bx, by, 2, F_WHITE))
                continue
            u = t - split
            for b in range(4):
                ang2 = ang + (b - 1.5) * 0.5
                x = bx + 2.5 * u * math.cos(ang2)
                y = by + 2.5 * u * math.sin(ang2) + G * (u * u) / 2.0
                k = max(1.0 - u / 22.0, 0.0)
                if alive(k, a * 4 + b, u):
                    dots.append((x, y, 2, F_YELLOW))
    return dots


def rocket(age: int, y: float) -> list:
    k = age / RISE
    ry = 480.0 - (480.0 - y) * (1.0 - (1.0 - k) ** 2) - y
    return [(0.0, ry, 2, F_WHITE)] + [(0.0, ry + t * 6.0, 1, F_YELLOW) for t in (1, 2)]


def cells(dots: list) -> list[tuple[int, int, int]]:
    """Punti -> celle 2x2 pixel (4 unità) relative al centro dello scoppio; il quadrato grande (size 3,
    3,5 pixel) prende 2x2 celle. Senza doppioni: resta l'ultimo, come nel disegno in ordine."""
    out: dict[tuple[int, int], int] = {}
    for x, y, size, color in dots:
        if size >= 3:
            cx0, cy0 = math.floor((2 + x - 2) / 4), math.floor((2 + y - 2) / 4)
            for dx in (0, 1):
                for dy in (0, 1):
                    out.pop((cx0 + dx, cy0 + dy), None)
                    out[(cx0 + dx, cy0 + dy)] = color
        else:
            c = (math.floor((2 + x) / 4), math.floor((2 + y) / 4))
            out.pop(c, None)
            out[c] = color
    return [(dx, dy, c) for (dx, dy), c in out.items()]


def fw_centre(fw: dict) -> tuple[int, int]:
    cx = MARGIN + fw["x"] * (SKY_W - 2 * MARGIN)
    return math.floor(cx / 4), math.floor(fw["y"] / 4)


def fireworks() -> tuple[list[int], list[dict], int]:
    fws = show()
    words_idx = [0] * (len(fws) * FW_STRIDE * 2)
    dots_words: list[int] = []
    shared: dict[tuple, tuple[int, int]] = {}
    base = len(words_idx)
    max_frame = 0
    for i, fw in enumerate(fws):
        for age in range(FW_STRIDE):
            if age < RISE:
                key = ("rocket", i, age)
                pts = cells(rocket(age, fw["y"]))
            else:
                t = age - RISE
                key = (fw["kind"], fw["seed"] if fw["kind"] == "crackle" else 0, t)
                pts = cells(burst(fw["kind"], t, fw["seed"]))
            if not pts:
                continue
            max_frame = max(max_frame, age)
            if key not in shared:
                start = base + len(dots_words)
                for dx, dy, c in pts:
                    if not (-32 <= dx < 32 and -128 <= dy < 128):
                        raise SystemExit(f"punto fuori dai campi: {dx}, {dy}")
                    dots_words.append((dx & 0x3F) | (dy & 0xFF) << 6 | c << 14)
                shared[key] = (start, len(pts))
            start, n = shared[key]
            if n > 255:
                raise SystemExit("troppi punti in un frame")
            words_idx[(i * FW_STRIDE + age) * 2] = start
            words_idx[(i * FW_STRIDE + age) * 2 + 1] = n
    if max_frame >= FW_STRIDE:
        raise SystemExit("fuoco troppo lungo")
    return words_idx + dots_words, fws, len(dots_words)


# ------------------------------------------------------------------ uscite


def write_hex(path: Path, values: list[int], digits: int) -> None:
    path.write_text("\n".join(f"{v:0{digits}x}" for v in values) + "\n", newline="\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=Path, help="cartella per le anteprime PNG delle parti")
    args = ap.parse_args()

    t = Text()
    b = Builder(t)
    # cifre e timbro in fondo alle righe, contigui: si indirizzano con la riga del glifo
    strip_row0 = len(b.rows)
    for y in range(t.gh):
        b.row(t.strip[y], dedupe=False)
    stamp = stamp_bitmap()
    stamp_row0 = len(b.rows)
    for y in range(STAMP_H):
        b.row(stamp[y], dedupe=False)

    # finestre delle parti fisse: dalla prima all'ultima riga con una scritta
    words: list[int] = []
    windows: dict[int, tuple[int, int, int]] = {}
    for part, items in static_parts(t).items():
        lines = lines_of(t, items, b)
        top, bottom = min(lines), max(lines)
        windows[part] = (top, bottom - top + 1, len(words))
        words += [lines.get(y, 0) for y in range(top, bottom + 1)]
    # titoli di coda: riga del contenuto = riga dello schermo + scorrimento; la riga c del contenuto è
    # dove sta la scritta con lo scorrimento a zero (centro a 250 + y/2: entra dal basso)
    items = []
    for kind, text, y in credits_layout():
        if kind == "gap":
            continue
        scale, color = CRED_STYLE[kind]
        items.append((text, round(250 + y / 2), scale, color, 0, N_NONE, None))
    lines = lines_of(t, items, b)
    c0, c1 = min(lines), max(lines)
    cred_base = len(words)
    words += [lines.get(y, 0) for y in range(c0, c1 + 1)]
    cred_len = c1 - c0 + 1

    fw_words, fws, ndots = fireworks()
    if len(b.rows) > 512:
        raise SystemExit("troppe righe di bitmap")
    if len(words) > 2048:
        raise SystemExit("mappa troppo lunga")

    text_bytes = [x for r in b.rows for x in r]
    write_hex(GEN / "ending_text.hex", text_bytes, 2)
    write_hex(GEN / "ending_map.hex", words, 8)
    write_hex(GEN / "ending_fw.hex", fw_words, 4)

    _, dig_x0 = score_columns(t)
    v = ["// Generato da tools/gen_ending_assets.py: non modificare a mano.",
         "// Finale della CHALLENGE (ending_render.v): tempi in frame a 60 Hz, finestre della mappa, posizioni",
         "// a 320x240, tabella dei fuochi d'artificio.",
         *[f"localparam integer END_LEN{i} = {n};" for i, n in enumerate(PART_LEN)],
         f"localparam integer END_TOTAL = {sum(PART_LEN)};",
         f"localparam integer END_YOU_WIN_AT = {frames(YOU_WIN_AT)};",
         f"localparam integer END_SKIP_AFTER = {frames(SKIP_AFTER)};",
         f"localparam integer END_BEAT = {frames(STAMP_AFTER)};   // sfilata: un avversario ogni 2 battute, il timbro alla seconda",
         f"localparam integer END_SCORE_COUNT = {frames(SCORE_COUNT)};",
         f"localparam integer END_BONUS_END = {frames(SCORE_COUNT + BONUS_COUNT)};",
         f"localparam integer END_TOTAL_AT = {frames(TOTAL_AT)};",
         f"localparam integer END_FLASH0 = {frames(FLASH_CONGRATS)}, END_FLASH5 = {frames(FLASH_END)};",
         f"localparam integer END_TEXT_ROWS = {len(b.rows)}, END_TEXT_BYTES = {len(text_bytes)};",
         f"localparam integer END_MAP_SIZE = {len(words)};",
         f"localparam integer END_FW_SIZE = {len(fw_words)};   // {ndots} punti",
         f"localparam integer END_GLYPH_H = {t.gh}, END_CELL = {t.cell};",
         f"localparam integer END_STRIP_ROW0 = {strip_row0}, END_STAMP_ROW0 = {stamp_row0};",
         f"localparam integer END_STAMP_W = {STAMP_W}, END_STAMP_H = {STAMP_H}, END_STAMP_Y0 = {STAMP_CY - STAMP_H // 2};",
         f"localparam integer END_DIG_X0 = {dig_x0};",
         f"localparam integer END_PARADE_Y = {PARADE_Y}, END_PARADE_NAME_Y = {PARADE_NAME_Y};",
         *[f"localparam integer END_COL{i} = {column_x(i)};" for i in range(7)],
         ]
    for part in (0, 1, 2, 3, 5):
        top, h, base = windows[part]
        v.append(f"localparam integer END_WIN{part}_TOP = {top}, END_WIN{part}_H = {h}, END_WIN{part}_BASE = {base};")
    v += [f"localparam integer END_CRED_C0 = {c0}, END_CRED_LEN = {cred_len}, END_CRED_BASE = {cred_base};",
          f"localparam integer END_CRED_SMAX = {CRED_SMAX};",
          f"localparam integer END_FWS = {len(fws)}, END_FW_STRIDE = {FW_STRIDE};",
          "// fuoco i: frame del lancio (a 15 Hz) e cella del punto dello scoppio (griglia 160x120)",
          "function [6:0] fw_start(input [3:0] i);", "    case (i)",
          *[f"        4'd{i}: fw_start = 7'd{fw['start']};" for i, fw in enumerate(fws)],
          "        default: fw_start = 7'd127;", "    endcase", "endfunction",
          "function [7:0] fw_cx(input [3:0] i);", "    case (i)",
          *[f"        4'd{i}: fw_cx = 8'd{fw_centre(fw)[0]};   // {fw['kind']}" for i, fw in enumerate(fws)],
          "        default: fw_cx = 8'd0;", "    endcase", "endfunction",
          "function [6:0] fw_cy(input [3:0] i);", "    case (i)",
          *[f"        4'd{i}: fw_cy = 7'd{fw_centre(fw)[1]};" for i, fw in enumerate(fws)],
          "        default: fw_cy = 7'd0;", "    endcase", "endfunction"]
    if len(fws) > 15:
        raise SystemExit("troppi fuochi")
    (GEN / "pong_ending.vh").write_text("\n".join(v) + "\n", newline="\n")
    print(f"finale: {len(b.rows)} righe di bitmap ({len(text_bytes)} byte), mappa {len(words)} righe, "
          f"{len(fws)} fuochi, {ndots} punti ({len(fw_words)} parole); parti {PART_LEN} = {sum(PART_LEN)} frame")
    print("larghezze:", ", ".join(f"{s} {t.width[s]}" for s in all_strings()))

    if args.preview:
        preview(args.preview, t, b, words, windows, (c0, cred_len, cred_base), fw_words, fws, stamp, strip_row0)


def preview(out: Path, t: Text, b: Builder, words: list[int], windows: dict, cred: tuple, fw_words: list[int],
            fws: list[dict], stamp: list[list[int]], strip_row0: int) -> None:
    """Anteprime delle parti con la stessa mappa e gli stessi punti del renderer."""
    out.mkdir(parents=True, exist_ok=True)
    pal = {0: (255, 255, 255), 1: (255, 210, 37), 2: (230, 40, 40)}

    def bit(row: int, x: int) -> int:
        return (b.rows[row][x >> 3] >> (x & 7)) & 1 if 0 <= x < ROW_W else 0

    def draw_text(img: Image.Image, y: int, word: int) -> None:
        scale = (word >> 22) & 3
        if not scale:
            return
        br, g, xoff, color, num = word & 511, (word >> 9) & 15, (word >> 13) & 511, (word >> 24) & 3, (word >> 28) & 3
        for x in range(W):
            if num and x >= score_columns(t)[1]:
                u = (x - score_columns(t)[1]) // scale
                j = u // t.cell
                if j < 7:
                    code = 10 if (num == N_BONUS and j == 0) else (j + 3) % 10
                    if bit(strip_row0 + g, code * t.cell + u % t.cell):
                        img.putpixel((x, y), pal[color & 1 if color != 3 else 1])
                continue
            d = x - xoff
            if d >= 0 and bit(br, d // scale):
                img.putpixel((x, y), pal[1 if color == 3 else color])

    for part in (0, 1, 2, 3, 5):
        img = Image.new("RGB", (W, H))
        top, h, base = windows[part]
        for y in range(top, top + h):
            draw_text(img, y, words[base + y - top])
        if part == 1:
            # i timbri si sovrappongono agli angoli: il renderer legge due timbri per pixel (le due porte
            # della ROM), quello della colonna e il vicino
            for i in range(7):
                for yy in range(STAMP_H):
                    for xx in range(STAMP_W):
                        x = column_x(i) - 1 - STAMP_W // 2 + xx
                        if stamp[yy][xx] and 0 <= x < W:
                            img.putpixel((x, STAMP_CY - STAMP_H // 2 + yy), pal[2])
        if part == 3:
            f = 40
            for i, fw in enumerate(fws):
                age = f - fw["start"]
                if not 0 <= age < FW_STRIDE:
                    continue
                start, n = fw_words[(i * FW_STRIDE + age) * 2], fw_words[(i * FW_STRIDE + age) * 2 + 1]
                cx, cy = fw_centre(fw)
                for k in range(n):
                    wd = fw_words[start + k]
                    dx = (wd & 0x3F) - ((wd & 0x20) << 1)
                    dy = ((wd >> 6) & 0xFF) - (((wd >> 6) & 0x80) << 1)
                    x, y = cx + dx, cy + dy
                    if 0 <= x < 160 and 0 <= y < 120:
                        c = pal[{1: 0, 2: 1, 3: 2}[wd >> 14]]
                        for q in range(4):
                            img.putpixel((2 * x + (q & 1), 2 * y + (q >> 1)), c)
        img.resize((W * 2, H * 2), Image.NEAREST).save(out / f"ending_part{part}.png")
    c0, n, base = cred
    img = Image.new("RGB", (W, H))
    s = 200
    for y in range(H):
        c = y + s - c0
        if 0 <= c < n:
            draw_text(img, y, words[base + c])
    img.resize((W * 2, H * 2), Image.NEAREST).save(out / "ending_credits.png")


if __name__ == "__main__":
    main()
