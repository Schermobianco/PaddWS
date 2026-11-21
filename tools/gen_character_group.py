"""Compone l'immagine di gruppo dei personaggi delle racchette di NEXT.

Parte dalle otto immagini singole (assets/characters/source/<nome>.jpg, su fondo nero) e le
dispone come un poster: OMEGA grande dietro, HAMMER, TWIST, GUARDIAN e BLASTER ai lati, ARCADE,
TITAN e RUSH davanti. Ogni personaggio viene scontornato dal fondo nero: si prendono i pixel non
scuri, si allarga la maschera di qualche pixel per tenere il contorno nero e si riempiono i buchi
interni, così dove due personaggi si sovrappongono quello davanti conserva il suo contorno.

La seconda uscita è la stessa composizione con OMEGA, il boss segreto, in sagoma (`silhouette`):
quasi nero con un'ombra della sua luminosità, la scia viola smorzata e solo gli occhi accesi. La
forma da scontornare si calcola sui colori originali, quindi la sagoma resta intera.

Uscite:
  assets/characters/group.jpg          3840x2160
  assets/characters/group_locked.jpg   la stessa con OMEGA in sagoma

Uso:  .venv\\Scripts\\python tools\\gen_character_group.py   (richiede Pillow e numpy)
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "characters" / "source"
OUT = ROOT / "assets" / "characters" / "group.jpg"
OUT_LOCKED = ROOT / "assets" / "characters" / "group_locked.jpg"
W, H = 3840, 2160

# OMEGA in sagoma: colore di fondo, quanto resta della luminosità del disegno, quanto resta della
# scia viola; riquadro della lente HAL-9000 in pixel di source/omega.jpg (1376x768)
SILHOUETTE = np.array([14, 10, 20], dtype=float)
SHADE = 0.14
AURA = 0.28
OMEGA_EYES = (634, 222, 742, 330)

# soglia (massimo dei tre canali) oltre la quale un pixel non è fondo
INK = 45

# dal fondo verso il primo piano: (nome, altezza del riquadro, centro x, fondo y, specchiato)
# Composizione epica con OMEGA alto dietro e GUARDIAN davanti al centro con lo scudo
LAYOUT = [
    ("omega",    1620, 1920, 1780, False),
    ("blaster",   900, 1020, 1060, True),
    ("rush",      860, 2940,  960, False),
    ("hammer",   1040,  760, 1660, False),
    ("titan",    1040, 3040, 1740, False),
    ("arcade",    980,  760, 2140, False),
    ("twist",     960, 3080, 2150, False),
    ("guardian", 1180, 1920, 2150, False),
]

# frazione della larghezza da sfumare a destra (prima dell'eventuale specchiatura): il laser di
# BLASTER è tagliato dal bordo nell'immagine originale e così si dissolve invece di finire di netto
FADE_RIGHT = {"blaster": 0.13}


def dilate(m: np.ndarray, r: int) -> np.ndarray:
    """Allarga la maschera booleana di r pixel (quadrato, separabile)."""
    out = m.copy()
    for d in range(1, r + 1):
        out[:, d:] |= m[:, :-d]
        out[:, :-d] |= m[:, d:]
    rows = out.copy()
    for d in range(1, r + 1):
        out[d:, :] |= rows[:-d, :]
        out[:-d, :] |= rows[d:, :]
    return out


def silhouette(rgba: Image.Image, eyes: tuple[float, float, float, float]) -> Image.Image:
    """Il personaggio quasi nero: un'ombra della luminosità sopra `SILHOUETTE`, il viola della scia
    smorzato, e la lente HAL-9000 (ellisse in `eyes`, in pixel di `rgba`) accesa."""
    a = np.asarray(rgba).astype(float)
    rgb = a[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    out = SILHOUETTE + lum[..., None] * SHADE
    magenta = (rgb[..., 0] > 120) & (rgb[..., 2] > 120) & (rgb[..., 1] < 110)
    ys, xs = np.mgrid[0:rgba.height, 0:rgba.width]
    ex0, ey0, ex1, ey1 = eyes
    cx, cy = (ex0 + ex1) / 2.0, (ey0 + ey1) / 2.0
    rx, ry = max((ex1 - ex0) / 2.0, 1.0), max((ey1 - ey0) / 2.0, 1.0)
    in_lens = ((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2 <= 1.0
    glow = in_lens & (rgb[..., 0] > 90) & (rgb[..., 2] > 90)
    out = np.where((magenta & ~glow)[..., None], rgb * AURA, out)
    out = np.where(glow[..., None], rgb, out)
    a[..., :3] = out
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def cutout(name: str, height: int, locked: bool = False) -> Image.Image:
    """Personaggio scontornato, scalato perché il suo riquadro sia alto `height`; con `locked`
    OMEGA è in sagoma."""
    im = Image.open(SRC / f"{name}.jpg").convert("RGB")
    ink = np.asarray(im).max(axis=2) > INK
    ys, xs = np.nonzero(ink)
    pad = 30
    box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0),
           min(xs.max() + pad + 1, im.width), min(ys.max() + pad + 1, im.height))
    im = im.crop(box)
    scale = height / im.height
    im = im.resize((round(im.width * scale), height), Image.LANCZOS)
    m = dilate(np.asarray(im).max(axis=2) > INK, max(2, round(10 * scale)))
    # buchi interni: tutto ciò che il fondo esterno non raggiunge. copy(): floodfill non
    # modifica un'immagine che condivide la memoria (in sola lettura) con l'array numpy
    mask = Image.fromarray(np.pad(~m, 1, constant_values=True).astype(np.uint8) * 255).copy()
    ImageDraw.floodfill(mask, (0, 0), 128)
    outside = np.asarray(mask)[1:-1, 1:-1] == 128
    rgba = im.convert("RGBA")
    rgba.putalpha(Image.fromarray((~outside).astype(np.uint8) * 255))
    if locked and name == "omega":
        ex0, ey0, ex1, ey1 = OMEGA_EYES
        rgba = silhouette(rgba, ((ex0 - box[0]) * scale, (ey0 - box[1]) * scale,
                                 (ex1 - box[0]) * scale, (ey1 - box[1]) * scale))
    return rgba


def fade_right(sprite: Image.Image, frac: float) -> Image.Image:
    """Sfuma verso il trasparente l'ultima frazione `frac` della larghezza."""
    a = np.asarray(sprite).copy()
    n = round(sprite.width * frac)
    ramp = np.linspace(1.0, 0.0, n) ** 1.5
    a[:, -n:, 3] = (a[:, -n:, 3] * ramp).astype(np.uint8)
    return Image.fromarray(a)


def compose(locked: bool) -> Image.Image:
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    for name, height, cx, bottom, flip in LAYOUT:
        sprite = cutout(name, height, locked)
        if name in FADE_RIGHT:
            sprite = fade_right(sprite, FADE_RIGHT[name])
        if flip:
            sprite = sprite.transpose(Image.FLIP_LEFT_RIGHT)
        canvas.alpha_composite(sprite, (round(cx - sprite.width / 2), round(bottom - sprite.height)))
    return canvas.convert("RGB")


def main() -> None:
    for locked, out in ((False, OUT), (True, OUT_LOCKED)):
        compose(locked).save(out, quality=92)
        print(f"{out.relative_to(ROOT)}: {W}x{H}")


if __name__ == "__main__":
    main()
