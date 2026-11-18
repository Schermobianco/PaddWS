"""Genera i ritratti della scelta della racchetta di NEXT (comuni a tutte le versioni).

Partono dai disegni dei personaggi (assets/characters/source/<nome>.jpg, fondo nero) e sono in
pixel del campo 320x240:
  - <nome>.png        ritratto grande BIG_W x BIG_H, il personaggio intero con i suoi oggetti;
  - <nome>_small.png  casella della griglia SMALL x SMALL, il volto;
  - omega_small.png   la casella di OMEGA, il boss segreto, in sagoma (non si sceglie);
  - omega.png         OMEGA svelato, ritratto grande, nello schermo VS della sua presentazione;
  - <nome>_mid.png, <nome>_mid_defeated.png  ritratti medi MID_W x MID_H della sfilata del finale,
    normale e sconfitto (<nome>_defeated.jpg), anche di OMEGA, svelato quando è battuto;
  - omega_mid_locked.png  OMEGA in sagoma nella sfilata, quando non è ancora battuto.
Sono immagini a palette (modo P) in cui l'indice è il ruolo del colore (ROLES), da tradurre nei
colori di ogni versione come le grafiche dei titoli: ogni pixel prende il ruolo più vicino tra nero,
bianco, tre grigi, il colore del personaggio (ACCENT) e lo stesso scurito (DARK). Nessun vincolo di
cella: il C64 li riconverte con i suoi (2 colori ogni 8x8).

Gli stessi ritratti per il C64 (sottocartella c64/): bitmap hires, in ogni cella 8x8 al massimo
2 colori tra nero, bianco, i tre grigi e il colore del personaggio (C64_ACCENT), scelti per
cella; l'indice della palette è il numero del colore del C64 (tavolozza Colodore, solo per vederli).
Le misure sono multipli di 8 (11x13 e 4x4 caratteri).

L'inquadratura del ritratto grande è larga BIG_SRC_W pixel della sorgente intorno al volto (FACE),
spostata di SHIFT (positivo: il personaggio va a sinistra, per far entrare fucile e laser di
BLASTER). Nel gioco il ritratto del giocatore di destra è specchiato.

Uscite:
  assets/characters/portraits/*.png            PC, web e MiSTer (ruoli dei colori)
  assets/characters/portraits/c64/*.png        C64 (numeri dei colori, 2 per cella 8x8)
  assets/characters/portraits/portraits.json   ruoli, misure e colori dei personaggi

Uso:  .venv\\Scripts\\python tools\\gen_portraits.py   (richiede Pillow e numpy)
"""

from __future__ import annotations

import json
from itertools import combinations
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from gen_character_group import OMEGA_EYES, silhouette

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "characters" / "source"
OUT = ROOT / "assets" / "characters" / "portraits"

NAMES = ["arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian"]
BIG_W, BIG_H = 88, 104
SMALL = 32
MID_W, MID_H = 64, 72
BIG_SRC_W = 1750
SMALL_SRC_W = 900

# ruoli dei colori (indice della palette) e il loro RGB per i PC; ACCENT e ACCENT_DARK dipendono dal
# personaggio
ROLES = ["black", "white", "light_gray", "gray", "dark_gray", "accent", "accent_dark"]
GRAYS = {"black": (0, 0, 0), "white": (255, 255, 255), "light_gray": (195, 195, 195),
         "gray": (130, 130, 130), "dark_gray": (70, 70, 70)}
ACCENT = {
    "arcade": (255, 210, 30), "titan": (230, 120, 40), "hammer": (230, 40, 40),
    "twist": (150, 70, 200), "blaster": (70, 190, 70), "rush": (60, 200, 220),
    "guardian": (90, 150, 255), "omega": (224, 64, 255),
}
DARK = 0.55

# tavolozza Colodore del C64 (come colodore.vpl di VICE) e i colori usati
C64_PALETTE = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x96, 0x28, 0x2E), (0x5B, 0xD6, 0xCE),
    (0x9F, 0x2D, 0xAD), (0x41, 0xB9, 0x36), (0x27, 0x24, 0xC4), (0xEF, 0xF3, 0x47),
    (0x9F, 0x48, 0x15), (0x5E, 0x35, 0x00), (0xDA, 0x5F, 0x66), (0x47, 0x47, 0x47),
    (0x78, 0x78, 0x78), (0x91, 0xFF, 0x84), (0x68, 0x64, 0xFF), (0xAE, 0xAE, 0xAE),
]
C64_GRAYS = [0, 1, 15, 12, 11]          # nero, bianco, grigio chiaro, grigio, grigio scuro
# retino ordinato 4x4 (soglie tra 0 e 1) e quanto costa usarlo nella scelta dei due colori
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16
DITHER_COST = 0.7
C64_ACCENT = {"arcade": 7, "titan": 8, "hammer": 2, "twist": 4, "blaster": 5, "rush": 3,
              "guardian": 14, "omega": 4}

# centro del volto nei disegni (pixel della sorgente), spostamento dell'inquadratura grande
FACE = {
    "arcade": (1366, 555), "titan": (1477, 406), "hammer": (1503, 512), "twist": (1294, 427),
    "blaster": (1409, 474), "rush": (1648, 474), "guardian": (1375, 346), "omega": (1529, 346),
}
SHIFT = {"blaster": 330, "hammer": -330, "twist": 150}
# volto nei disegni dei personaggi sconfitti, dove è spostato rispetto all'originale
FACE_DEFEATED: dict[str, tuple[int, int]] = {"rush": (1720, 474)}
# altezza del volto dall'alto del riquadro (frazione)
BIG_UP, SMALL_UP = 0.30, 0.40


def source(name: str, defeated: bool, locked: bool) -> Image.Image:
    """Il disegno del personaggio, sconfitto (<nome>_defeated.jpg) o no; `locked` per OMEGA in sagoma."""
    im = Image.open(SRC / (f"{name}_defeated.jpg" if defeated else f"{name}.jpg")).convert("RGBA")
    if locked:
        im = silhouette(im, OMEGA_EYES)
    return im.convert("RGB")


def palette(name: str) -> np.ndarray:
    accent = ACCENT[name]
    cols = [GRAYS[r] for r in ROLES[:5]] + [accent, tuple(round(c * DARK) for c in accent)]
    return np.array(cols, dtype=float)


def framed(name: str, w: int, h: int, src_w: int, up: float, shift: int,
           defeated: bool = False, locked: bool = False) -> Image.Image:
    """Il riquadro w x h del disegno: largo src_w pixel della sorgente, volto a `up` dall'alto."""
    fx, fy = FACE_DEFEATED.get(name, FACE[name]) if defeated else FACE[name]
    fx += shift
    src_h = src_w * h / w
    box = (fx - src_w / 2, fy - src_h * up, fx + src_w / 2, fy + src_h * (1 - up))
    return source(name, defeated, locked).crop(tuple(round(v) for v in box)).resize((w, h), Image.LANCZOS)


def c64(name: str, w: int, h: int, src_w: int, up: float, shift: int,
        defeated: bool = False, locked: bool = False) -> Image.Image:
    """Versione C64: per ogni cella 8x8 la coppia di colori che la rende meglio, mescolati con il
    retino ordinato 4x4 (`BAYER`): ogni pixel sta sul segmento tra i due colori e il retino sceglie
    in proporzione, così i grigi sfumano invece di cambiare a blocchi da una cella all'altra. La
    coppia si sceglie sull'errore del segmento più una penalità per il retino (`DITHER_COST`), che
    preferisce i colori pieni quando bastano."""
    src = framed(name, w, h, src_w, up, shift, defeated, locked)
    lo = np.asarray(src.filter(ImageFilter.UnsharpMask(1, 80, 2)), dtype=float)
    pal = np.array(C64_PALETTE, dtype=float)
    cand = C64_GRAYS + [C64_ACCENT[name]]
    threshold = np.tile(BAYER, (2, 2)).reshape(-1)
    out = np.zeros((h, w), dtype=np.uint8)
    for cy in range(0, h, 8):
        for cx in range(0, w, 8):
            cell = lo[cy:cy + 8, cx:cx + 8].reshape(-1, 3)
            best = None
            for a, b in combinations(cand, 2):
                ca, cb = pal[a], pal[b]
                dv = cb - ca
                n = (dv * dv).sum()
                t = np.clip(((cell - ca) * dv).sum(1) / n, 0, 1)
                err = ((cell - (ca + t[:, None] * dv)) ** 2).sum() + DITHER_COST * (t * (1 - t) * n).sum()
                if best is None or err < best[0]:
                    best = (err, a, b, t)
            _, a, b, t = best
            out[cy:cy + 8, cx:cx + 8] = np.where(t > threshold, b, a).reshape(8, 8)
    im = Image.new("P", (w, h))
    im.putdata(out.flatten().tolist())
    im.putpalette([v for rgb in C64_PALETTE for v in rgb])
    return im


def portrait(name: str, w: int, h: int, src_w: int, up: float, shift: int,
             defeated: bool = False, locked: bool = False) -> Image.Image:
    lo = np.asarray(framed(name, w, h, src_w, up, shift, defeated, locked), dtype=float)
    pal = palette(name)
    roles = ((lo[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(3).argmin(2).astype(np.uint8)
    out = Image.new("P", (w, h))
    out.putdata(roles.flatten().tolist())
    # i colori della palette servono solo a vedere i PNG; il gioco usa gli indici
    out.putpalette([int(v) for rgb in pal for v in rgb])
    return out


def main() -> None:
    (OUT / "c64").mkdir(parents=True, exist_ok=True)
    for make, folder in ((portrait, OUT), (c64, OUT / "c64")):
        def save(image: Image.Image, stem: str) -> None:
            image.save(folder / f"{stem}.png", optimize=True)

        for name in NAMES:
            save(make(name, BIG_W, BIG_H, BIG_SRC_W, BIG_UP, SHIFT.get(name, 0)), name)
            save(make(name, SMALL, SMALL, SMALL_SRC_W, SMALL_UP, 0), f"{name}_small")
        save(make("omega", SMALL, SMALL, SMALL_SRC_W, SMALL_UP, 0, locked=True), "omega_small")
        save(make("omega", BIG_W, BIG_H, BIG_SRC_W, BIG_UP, 0), "omega")
        # finale: ritratti medi, normali e sconfitti; OMEGA anche in sagoma (non ancora battuto)
        for name in NAMES + ["omega"]:
            shift = SHIFT.get(name, 0)
            save(make(name, MID_W, MID_H, BIG_SRC_W, BIG_UP, shift), f"{name}_mid")
            save(make(name, MID_W, MID_H, BIG_SRC_W, BIG_UP, shift, defeated=True), f"{name}_mid_defeated")
        save(make("omega", MID_W, MID_H, BIG_SRC_W, BIG_UP, 0, locked=True), "omega_mid_locked")
    spec = {
        "roles": ROLES,
        "grays": {k: list(v) for k, v in GRAYS.items()},
        "accent": {k: list(v) for k, v in ACCENT.items()},
        "dark": DARK,
        "big": [BIG_W, BIG_H],
        "small": SMALL,
        "mid": [MID_W, MID_H],
        "c64_accent": C64_ACCENT,
    }
    (OUT / "portraits.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(NAMES)} ritratti grandi, {len(NAMES) + 1} caselle")


if __name__ == "__main__":
    main()
