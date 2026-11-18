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
# scia viola; riquadro degli occhi in pixel di source/omega.jpg (lì il viola resta acceso)
SILHOUETTE = np.array([14, 10, 20], dtype=float)
SHADE = 0.10
AURA = 0.30
OMEGA_EYES = (1330, 280, 1620, 410)

# soglia (massimo dei tre canali) oltre la quale un pixel non è fondo
INK = 45

# dal fondo verso il primo piano: (nome, altezza del riquadro, centro x, fondo y, specchiato)
LAYOUT = [
    ("omega", 1450, 1920, 1570, False),
    ("hammer", 780, 640, 1470, False),
    ("twist", 780, 1200, 1550, False),
    ("blaster", 700, 3200, 1450, False),
    # specchiato: lo scudo guarda il centro e il colpo di BLASTER non gli arriva in faccia
    ("guardian", 800, 2640, 1550, True),
    # il fondo piatto del blocco coincide con il bordo inferiore: RUSH esce dall'inquadratura
    ("rush", 820, 3020, 2178, False),
    ("arcade", 880, 1010, 2150, False),
    ("titan", 1080, 1980, 2150, False),
]

# frazione della larghezza da sfumare a destra: il laser di BLASTER è tagliato dal bordo
# nell'immagine originale e così si dissolve invece di finire di netto
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
    smorzato, il viola degli occhi (nel riquadro `eyes`, in pixel di `rgba`) acceso."""
    a = np.asarray(rgba).astype(float)
    rgb = a[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    out = SILHOUETTE + lum[..., None] * SHADE
    magenta = (rgb[..., 0] > 150) & (rgb[..., 2] > 150) & (rgb[..., 1] < 110)
    ys, xs = np.mgrid[0:rgba.height, 0:rgba.width]
    ex0, ey0, ex1, ey1 = eyes
    in_eyes = (xs >= ex0) & (xs < ex1) & (ys >= ey0) & (ys < ey1)
    out = np.where((magenta & ~in_eyes)[..., None], rgb * AURA, out)
    out = np.where((magenta & in_eyes)[..., None], rgb, out)
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
