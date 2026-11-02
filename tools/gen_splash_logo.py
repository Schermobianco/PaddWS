"""Ridisegna la scritta PADD nello splash (assets/images/splash.png, 800x480).

Le lettere sono geometriche come quelle del logo originale: aste larghe 20 px, P con la pancia
in alto, A ad arco (come la N del vecchio logo) con la traversa all'altezza della pancia della P,
D con l'asta e un mezzo ellisse. Occupano esattamente lo spazio del vecchio logo (x 245-548,
y 191-291), cioè la bitmap 152x51 che tools/gen_attract_assets.py ritaglia nello schermo 320x240;
strisce e scritta WS restano quelle dello splash.

Le forme sono disegnate in grande e ridotte con la media dei pixel, per l'antialiasing.

Dopo:  tools/gen_attract_assets.py e tools/gen_c64_assets.py

Uso:  .venv\\Scripts\\python tools\\gen_splash_logo.py   (richiede Pillow)
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SPLASH = ROOT / "assets" / "images" / "splash.png"

YELLOW = (255, 210, 37)
SS = 8                          # sovracampionamento
CLEAR = (238, 180, 559, 300)    # zona del logo da ripulire: le strisce finiscono a x 230 e ripartono a 562
STEM = 20                       # spessore delle aste
TOP, BOTTOM = 193, 292          # aste: dalla riga 193 alla 291 compresa


def letters(d: ImageDraw.ImageDraw) -> None:
    """Disegna PADD in coordinate dello splash (bordi esclusi a destra e in basso)."""
    def rect(x0, y0, x1, y1, fill):
        d.rectangle((x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1), fill=fill)

    def box(cx, cy, rx, ry):
        return ((cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS - 1, (cy + ry) * SS - 1)

    def ellipse(cx, cy, rx, ry, fill):
        d.ellipse(box(cx, cy, rx, ry), fill=fill)

    def right_half(cx, cy, rx, ry, fill):
        d.pieslice(box(cx, cy, rx, ry), -90, 90, fill=fill)

    # P: asta, pancia alta 61 px (rettangolo + semicerchio), occhiello alto 23
    rect(245, TOP, 245 + STEM, BOTTOM, 1)
    rect(265, TOP, 276, 254, 1)
    ellipse(276, 223.5, 30.5, 30.5, 1)
    rect(265, 212, 277, 235, 0)
    ellipse(277, 223.5, 11.5, 11.5, 0)
    rect(240, TOP, 245, BOTTOM, 0)      # il cerchio della pancia non deve uscire a sinistra dell'asta

    # A: arco largo 72 (raggio 36, sopra fino alla riga 191), traversa a filo della pancia della P
    ax, acx, acy = 313, 349, 227
    ellipse(acx, acy, 36, 36, 1)
    rect(ax, acy, ax + 72, BOTTOM, 1)
    ellipse(acx, acy, 16, 16, 0)
    rect(ax + STEM, acy, ax + 72 - STEM, BOTTOM, 0)
    rect(ax + STEM, 235, ax + 72 - STEM, 254, 1)

    # D: asta e mezzo ellisse (53 x 49,5), larghe 73; la seconda finisce dove finiva la G
    for x in (395, 476):
        cx, cy = x + STEM, (TOP + BOTTOM) / 2
        right_half(cx, cy, 53, (BOTTOM - TOP) / 2, 1)
        right_half(cx, cy, 53 - STEM, (BOTTOM - TOP) / 2 - STEM, 0)
        rect(x, TOP, cx, BOTTOM, 1)


def main() -> None:
    im = Image.open(SPLASH).convert("RGB")
    x0, y0, x1, y1 = CLEAR
    w, h = x1 - x0, y1 - y0
    # maschera in grande della sola zona del logo, con l'origine spostata all'angolo della zona
    big = Image.new("L", (im.width * SS, im.height * SS), 0)
    letters(ImageDraw.Draw(big))
    mask = big.crop((x0 * SS, y0 * SS, x1 * SS, y1 * SS)).point(lambda v: 255 if v else 0)
    mask = mask.resize((w, h), Image.BOX)
    # nero dove c'è la lettera, giallo dello splash altrove (con i bordi sfumati)
    zone = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), Image.new("RGB", (w, h), YELLOW), mask)
    im.paste(zone, (x0, y0))
    im.save(SPLASH)
    print(f"logo PADD in {SPLASH}")


if __name__ == "__main__":
    main()
