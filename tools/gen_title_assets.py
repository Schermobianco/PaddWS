"""Genera le grafiche dei titoli (comuni a Rust, MiSTer e C64).

Sono scritte disegnate a pixel, non il font ingrandito: i nomi dei sette avversari nelle
presentazioni (uno stile per avversario), HERE COMES A NEW CHALLENGER! e PERFECT. Partono dalle
lettere 8x8 di Press Start 2P (assets/fonts, SIL OFL 1.1), allungate, inclinate, ombreggiate o
riempite di mattoni. Le misure sono in pixel del campo 320x240.

Uscite:
  assets/titles/*.png      immagini a palette (modo P); l'indice è il ruolo del colore, da
                           tradurre nei colori di ogni versione (vedi PALETTE)
  assets/titles/titles.json  ruoli della palette, file, larghezza e altezza

Uso:  .venv\\Scripts\\python tools\\gen_title_assets.py   (richiede Pillow)
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "titles"
FONT = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "PressStart2P-Regular.ttf"), 8)

# indice della palette = ruolo del colore; l'RGB è quello del gioco Rust e serve solo per vedere i PNG
PALETTE = [
    ("transparent", (0, 0, 0)),
    ("black", (0, 0, 0)),          # nero pieno (ombre dentro la targa)
    ("white", (255, 255, 255)),
    ("yellow", (255, 210, 37)),    # il giallo d'accento
    ("dark_yellow", (150, 105, 0)),
    ("gray", (110, 110, 110)),
    ("dark_gray", (55, 55, 55)),
    ("red", (200, 30, 30)),
    ("dark_red", (90, 10, 10)),
]
T, K, W, Y, DY, GR, DG, RD, DR = range(len(PALETTE))


def glyph(ch: str) -> set[tuple[int, int]]:
    """I pixel accesi della lettera 8x8 di Press Start 2P."""
    im = Image.new("1", (8, 8), 0)
    ImageDraw.Draw(im).text((0, 0), ch, font=FONT, fill=1)
    return {(x, y) for y in range(8) for x in range(8) if im.getpixel((x, y))}


def letters(text: str, sx: int = 1, sy: int = 2, step: int = 8) -> list[tuple[int, set[tuple[int, int]]]]:
    """Ogni lettera ingrandita sx x sy, con la sua x di partenza."""
    out = []
    for i, ch in enumerate(text):
        pts = {(x * sx + dx, y * sy + dy) for x, y in glyph(ch) for dx in range(sx) for dy in range(sy)}
        out.append((i * step, pts))
    return out


def text(s: str, sx: int = 1, sy: int = 1, step: int = 8) -> tuple[set[tuple[int, int]], int]:
    """Tutti i pixel della scritta e la sua larghezza."""
    pts = {(ox + x, y) for ox, p in letters(s, sx, sy, step) for x, y in p}
    return pts, max(x for x, _ in pts) + 1


def shear(pts: set[tuple[int, int]], h: int, k: float) -> set[tuple[int, int]]:
    """Corsivo: la riga y si sposta a destra di (h - 1 - y) * k."""
    return {(x + int((h - 1 - y) * k), y) for x, y in pts}


def outline(pts: set[tuple[int, int]]) -> set[tuple[int, int]]:
    return {(x + dx, y + dy) for x, y in pts for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - pts


def brick(x: int, y: int, h: int, w: int) -> bool:
    """Vero dove c'è la malta: mattoni w x h sfalsati di mezzo mattone a righe alterne."""
    return y % h == h - 1 or (x + (w // 2) * ((y // h) % 2)) % w == w - 1


class Canvas:
    def __init__(self, w: int, h: int) -> None:
        self.w, self.h = w, h
        self.px: dict[tuple[int, int], int] = {}

    def put(self, x: int, y: int, c: int) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = c

    def image(self) -> Image.Image:
        """Ritagliata ai pixel usati."""
        xs = [x for x, _ in self.px]
        ys = [y for _, y in self.px]
        x0, y0 = min(xs), min(ys)
        im = Image.new("P", (max(xs) - x0 + 1, max(ys) - y0 + 1), T)
        im.putpalette([v for _, rgb in PALETTE for v in rgb])
        for (x, y), c in self.px.items():
            im.putpixel((x - x0, y - y0), c)
        return im


def arcade() -> Canvas:
    """Classico: lettere alte, metà bianca e metà gialla, ombra in basso a destra."""
    c = Canvas(62, 17)
    pts = {(ox + x + 1, y + 1) for ox, p in letters("ARCADE", 1, 2, 10) for x, y in p}
    for x, y in pts:
        c.put(x + 1, y + 1, DY)
    for x, y in pts:
        c.put(x, y, W if y < 9 else Y)
    return c


def titan() -> Canvas:
    """Altissimo e stretto, fra due travi."""
    c = Canvas(44, 26)
    for x in range(44):
        c.put(x, 0, Y), c.put(x, 1, DY), c.put(x, 24, DY), c.put(x, 25, Y)
    for ox, p in letters("TITAN", 1, 3, 9):
        for x, y in p:
            c.put(ox + x + 1, y + 3, W)
    return c


def hammer() -> Canvas:
    """Pesante: tratti doppi con l'ombra spessa, scintille d'impatto ai lati."""
    c = Canvas(82, 18)
    pts = set()
    for ox, p in letters("HAMMER", 1, 2, 11):
        # tratti doppi verso destra, ma senza chiudere i varchi di un pixel (la M resta una M)
        bold = p | {(x + 1, y) for x, y in p if (x + 2, y) not in p}
        pts |= {(ox + x + 7, y + 1) for x, y in bold}
    for x, y in pts:
        c.put(x + 1, y + 1, DY), c.put(x + 1, y + 2, DY)
    for x, y in pts:
        c.put(x, y, W)
    for x, y in [(1, 8), (2, 8), (3, 8), (2, 5), (3, 6), (2, 11), (3, 10)]:
        c.put(x, y, Y), c.put(81 - x, y, Y)
    return c


def twist() -> Canvas:
    """Lettere su un'onda, bianche e gialle alternate."""
    c = Canvas(50, 22)
    for i, (ox, p) in enumerate(letters("TWIST", 1, 2, 10)):
        dy = round(3 * math.sin(i * 1.3)) + 4
        for x, y in p:
            c.put(ox + x + 1, y + dy, W if i % 2 == 0 else Y)
    return c


def blaster() -> Canvas:
    """Corsivo giallo con la cima bianca, scie di velocità a sinistra."""
    c = Canvas(96, 16)
    for ox, p in letters("BLASTER", 1, 2, 9):
        for x, y in shear(p, 14, 0.34):
            c.put(ox + x + 22, y + 1, W if y < 4 else Y)
    for y, x0, x1, col in [(3, 6, 20, GR), (6, 0, 18, Y), (9, 4, 19, Y), (12, 10, 20, GR)]:
        for x in range(x0, x1):
            c.put(x, y, col)
    return c


def rush() -> Canvas:
    """Corsivo forte con una scia che sfuma a righe alterne."""
    c = Canvas(60, 16)
    for ox, p in letters("RUSH", 1, 2, 11):
        sp = shear(p, 14, 0.5)
        for x, y in sp:
            if y % 2 == 0 and (x - 1, y) not in sp:
                for k, col in ((1, GR), (2, GR), (3, DG), (4, DG)):
                    if (x - k, y) not in sp:
                        c.put(ox + x + 14 - k, y + 1, col)
        for x, y in sp:
            c.put(ox + x + 14, y + 1, W)
    return c


def guardian() -> Canvas:
    """Lettere fatte di mattoni: gialle, con la malta giallo scuro."""
    pts, w = text("GUARDIAN", 1, 2, 10)
    c = Canvas(w, 14)
    for x, y in pts:
        c.put(x, y, DY if brick(x, y, 3, 6) else Y)
    return c


def plate(c: Canvas, x0: int, x1: int, y0: int, y1: int) -> None:
    """Targa rossa con il bordo giallo e gli angoli tagliati."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            cut = min(x - x0, x1 - x, y - y0, y1 - y)
            corner = min(x - x0, x1 - x) + min(y - y0, y1 - y)
            if corner < 4:
                continue
            if cut == 0 or corner == 4:
                col = Y
            elif cut == 2 or corner == 6:
                col = DY
            elif cut > 2:
                col = RD
            else:
                col = DR
            c.put(x, y, col)


def challenger() -> Canvas:
    """HERE COMES / A NEW CHALLENGER! in una targa rossa."""
    c = Canvas(320, 40)
    plate(c, 64, 255, 1, 38)
    p, w = text("HERE COMES", step=9)
    for x, y in p:
        c.put(160 - w // 2 + x + 1, 7 + y, K)
    for x, y in p:
        c.put(160 - w // 2 + x, 6 + y, W)
    p, w = text("A NEW CHALLENGER!", 1, 2, 9)
    ox = 160 - w // 2
    for x, y in p:
        c.put(ox + x + 1, 19 + y, DR)
    for x, y in p:
        c.put(ox + x, 18 + y, W if y < 6 else Y)
    return c


def warning() -> Canvas:
    """WARNING! nella targa rossa di HERE COMES A NEW CHALLENGER!: l'allarme prima di OMEGA."""
    c = Canvas(320, 40)
    plate(c, 64, 255, 1, 38)
    p, w = text("WARNING!", 2, 3, 18)
    ox = 160 - w // 2
    for x, y in p:
        c.put(ox + x + 1, 9 + y, K)
    for x, y in p:
        c.put(ox + x, 8 + y, W if y < 12 else Y)
    return c


# il simbolo omega disegnato a pixel (15x14): arco e due piedi
OMEGA_SIGN = [
    "....#######....",
    "..###.....###..",
    ".##.........##.",
    "##...........##",
    "##...........##",
    "##...........##",
    "##...........##",
    ".##.........##.",
    "..##.......##..",
    "...##.....##...",
    "....##...##....",
    "....##...##....",
    "######...######",
    "######...######",
]


def omega() -> Canvas:
    """Sigillo: il simbolo omega (giallo in alto, rosso in basso, ombra rosso scuro) fra due barre
    rosse, e sotto OMEGA alto e bianco con l'ombra rosso scuro."""
    c = Canvas(80, 34)
    for y, row in enumerate(OMEGA_SIGN):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x + 33, y + 1, DR)
    for y, row in enumerate(OMEGA_SIGN):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x + 32, y, Y if y < 7 else RD)
    for x in range(28):
        for xx in (x, 79 - x):
            c.put(xx, 6, RD), c.put(xx, 7, DR)
    p, w = text("OMEGA", 1, 2, 10)
    ox = 40 - w // 2
    for x, y in p:
        c.put(ox + x + 1, y + 19, DR)
    for x, y in p:
        c.put(ox + x, y + 18, W)
    return c


def perfect() -> Canvas:
    """Cromato: lettere larghe e altissime a fasce bianco, giallo, giallo scuro, filetto sotto."""
    c = Canvas(320, 30)
    p, w = text("PERFECT", 2, 3, 16)
    ox = 160 - w // 2
    for x, y in outline(p):
        c.put(ox + x, 3 + y, DR)
    for x, y in p:
        c.put(ox + x, 3 + y, W if y < 8 else Y if y < 15 else DY)
    for x in range(ox - 2, ox + w + 2):
        c.put(x, 26, Y)
    return c


TITLES = {
    "name_arcade": arcade,
    "name_titan": titan,
    "name_hammer": hammer,
    "name_twist": twist,
    "name_blaster": blaster,
    "name_rush": rush,
    "name_guardian": guardian,
    "challenger": challenger,
    "perfect": perfect,
    "warning": warning,
    "name_omega": omega,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    info = {"palette": [name for name, _ in PALETTE], "titles": {}}
    for name, make in TITLES.items():
        im = make().image()
        im.save(OUT / f"{name}.png", transparency=T, optimize=False)
        info["titles"][name] = {"file": f"{name}.png", "size": list(im.size)}
        print(f"{name}: {im.size[0]}x{im.size[1]}")
    (OUT / "titles.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
