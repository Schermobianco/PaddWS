"""Genera il logo del menu NEXT (comune a Rust, MiSTer e C64): la scritta PADD con tre strisce per
lato, al posto di MAIN MENU in modalità NEXT.

Il logo è ridisegnato in proporzione da assets/images/splash.png (800x480: ridotta a 400x240 e
tagliata al centro diventa il campo 320x240, quindi x_splash = (x + 40) * 2, y_splash = y * 2):
  - zona di PADD nel campo 320x240: il riquadro x 82..233, y 94..144 con gli estremi destro e basso
    esclusi (151x50, come un crop di PIL);
  - ridotta con BOX a 78x26 e soglia al 50% (pixel acceso se almeno metà è nera);
  - poi le correzioni fatte a mano sulla prima prova: la seconda D è la copia esatta della prima,
    due colonne vuote fra tutte le lettere, tolta la riga vuota in alto: 79x25;
  - niente WS.
Tre strisce per lato, spesse 6 e lunghe 40, alle righe 0, 10 e 19 del logo, a 4 pixel dal logo;
si spengono verso l'esterno in 5 gradini da 8 pixel (1,0 / 0,72 / 0,48 / 0,3 / 0,16 del giallo).
Le misure sono in pixel del campo 320x240.

Uscite:
  assets/titles/menu_logo.png   immagine a palette (modo P): 0 trasparente, 1-5 il giallo d'accento
                                moltiplicato per LEVELS (1 = pieno), da tradurre nei colori di ogni
                                versione come i ruoli delle grafiche dei titoli
  assets/titles/menu_logo.json  livelli, misure e posizione nel campo (x, y dell'angolo in alto a
                                sinistra dell'immagine, strisce comprese)

Uso:  .venv\\Scripts\\python tools\\gen_menu_logo.py   (richiede Pillow)
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPLASH = ROOT / "assets" / "images" / "splash.png"
OUT = ROOT / "assets" / "titles"

# zona di PADD nel campo 320x240 (x0, y0, x1, y1 con x1 e y1 esclusi) e misura della riduzione
ZONE = (82, 94, 233, 144)
BOX = (78, 26)
# strisce: righe del logo, spessore, lunghezza, distanza dal logo, gradini verso l'esterno
STRIPE_ROWS = (0, 10, 19)
STRIPE_H, STRIPE_W, STRIPE_GAP = 6, 40, 4
LEVELS = (1.0, 0.72, 0.48, 0.3, 0.16)
# posizione: in alto, dove era MAIN MENU (il logo centrato nel campo, la cima alla riga 32)
FIELD_W, TOP = 320, 32
# colore d'accento, solo per vedere il PNG (le versioni usano il loro)
ACCENT = (255, 210, 37)


def padd_mask() -> list[list[int]]:
    """PADD ridotto e corretto: righe di 0/1."""
    im = Image.open(SPLASH).convert("L")
    x0, y0, x1, y1 = ZONE
    crop = im.crop(((x0 + 40) * 2, y0 * 2, (x1 + 40) * 2, y1 * 2))
    small = crop.resize(BOX, Image.BOX)
    w, h = small.size
    # il logo è nero sul giallo: acceso dove almeno metà dei pixel ridotti è nera
    rows =[[1 if small.getpixel((x, y)) < 128 else 0 for x in range(w)] for y in range(h)]
    # lettere: gruppi di colonne non vuote
    cols = [any(rows[y][x] for y in range(h)) for x in range(w)]
    letters: list[tuple[int, int]] = []
    x = 0
    while x < w:
        if cols[x]:
            s = x
            while x < w and cols[x]:
                x += 1
            letters.append((s, x))
        else:
            x += 1
    assert len(letters) == 4, f"attese 4 lettere (PADD), trovate {len(letters)}: {letters}"
    glyphs = [[row[s:e] for row in rows] for s, e in letters]
    glyphs[3] = [list(r) for r in glyphs[2]]      # la seconda D è la copia della prima
    out = []
    for y in range(h):
        line: list[int] = []
        for i, g in enumerate(glyphs):
            if i:
                line += [0, 0]                    # due colonne vuote fra le lettere
            line += g[y]
        out.append(line)
    # tolte le righe vuote in alto e in basso
    while out and not any(out[0]):
        out.pop(0)
    while out and not any(out[-1]):
        out.pop()
    return out


def main() -> None:
    mask = padd_mask()
    lh, lw = len(mask), len(mask[0])
    assert (lw, lh) == (79, 25), f"logo di {lw}x{lh}, atteso 79x25"
    side = STRIPE_W + STRIPE_GAP
    w, h = side * 2 + lw, lh
    im = Image.new("P", (w, h), 0)
    pal = [0, 0, 0]
    for k in LEVELS:
        pal += [round(c * k) for c in ACCENT]
    im.putpalette(pal + [0] * (768 - len(pal)))
    for y in range(lh):
        for x in range(lw):
            if mask[y][x]:
                im.putpixel((side + x, y), 1)
    step = STRIPE_W // len(LEVELS)
    for r in STRIPE_ROWS:
        for y in range(r, r + STRIPE_H):
            for i in range(STRIPE_W):
                level = 1 + i // step              # 1 vicino al logo, 5 all'esterno
                im.putpixel((STRIPE_W - 1 - i, y), level)
                im.putpixel((side + lw + STRIPE_GAP + i, y), level)
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / "menu_logo.png", transparency=0, optimize=False)
    x = (FIELD_W - lw) // 2 - side
    info = {
        "file": "menu_logo.png",
        "size": [w, h],
        "levels": list(LEVELS),
        "logo": {"x": side, "y": 0, "w": lw, "h": lh},
        "position": {"x": x, "y": TOP},
    }
    (OUT / "menu_logo.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"menu_logo: {w}x{h}, PADD {lw}x{lh}, nel campo a {x},{TOP}")


if __name__ == "__main__":
    main()
