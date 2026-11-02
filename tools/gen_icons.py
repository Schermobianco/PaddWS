"""Genera l'icona di PADD WS: sfondo giallo dello splash e due racchette nere sfalsate.

Ogni dimensione è disegnata a parte con le racchette allineate alla griglia dei pixel,
così l'icona resta nitida anche a 16x16; solo gli angoli arrotondati sono antialiasati.

Uscite:
  assets/icons/paddws_<N>.png       N = 16 ... 1024
  assets/icons/paddws.ico           16-256, per Windows (eseguibile Rust)
  rust/game/icon/icon_<N>.rgba      16, 32, 64: pixel grezzi per l'icona della finestra macroquad

Uso:  .venv\\Scripts\\python tools\\gen_icons.py   (richiede Pillow)
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "assets" / "icons"
RUST_ICON = ROOT / "rust" / "game" / "icon"

YELLOW = (255, 210, 37, 255)          # lo stesso giallo dello splash
BLACK = (0, 0, 0, 255)
SIZES = [16, 24, 32, 48, 64, 128, 256, 512, 1024]
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
SUPERSAMPLE = 8

# racchette in frazioni del lato: sinistra in alto, destra in basso
PAD_X = 0.22
PAD_W = 0.12
PAD_H = 0.44
LEFT_TOP = 0.16
RIGHT_TOP = 0.40


def icon(n: int) -> Image.Image:
    # sfondo con angoli arrotondati, disegnato in grande e ridotto per l'antialiasing
    big = n * SUPERSAMPLE
    radius = round(big * (0.18 if n >= 32 else 0.14))
    bg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(bg).rounded_rectangle((0, 0, big - 1, big - 1), radius=radius, fill=YELLOW)
    im = bg.resize((n, n), Image.LANCZOS)

    # racchette agganciate ai pixel, larghe almeno 2
    w = max(2, round(n * PAD_W))
    h = round(n * PAD_H)
    x_left = round(n * PAD_X)
    x_right = n - x_left - w
    draw = ImageDraw.Draw(im)
    for x, top in ((x_left, round(n * LEFT_TOP)), (x_right, round(n * RIGHT_TOP))):
        draw.rectangle((x, top, x + w - 1, top + h - 1), fill=BLACK)
    return im


def main() -> None:
    ICONS.mkdir(parents=True, exist_ok=True)
    RUST_ICON.mkdir(parents=True, exist_ok=True)
    images = {n: icon(n) for n in SIZES}
    for n, im in images.items():
        im.save(ICONS / f"paddws_{n}.png")
    largest = images[ICO_SIZES[-1]]
    largest.save(ICONS / "paddws.ico", sizes=[(n, n) for n in ICO_SIZES],
                 append_images=[images[n] for n in ICO_SIZES[:-1]])
    for n in (16, 32, 64):
        (RUST_ICON / f"icon_{n}.rgba").write_bytes(images[n].tobytes())
    print(f"icone generate in {ICONS} e {RUST_ICON}")


if __name__ == "__main__":
    main()
