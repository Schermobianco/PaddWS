"""Compone docs/icons/paddles.png, i sette tipi di racchetta della guida, dalle immagini del gioco.

Le immagini le salva il gioco Rust con `paddws --windowed --paddle-gallery CARTELLA` (con una copia
della configurazione e il filtro CRT spento): ogni racchetta a 6 pixel per pixel arcade, con i
segni in azione. Qui si ritagliano, si riportano a 3 pixel per pixel arcade (in proporzione tra
loro) e si mettono in fila con il nome in Press Start 2P e la sigla nel colore del personaggio.

Uso:  .venv\\Scripts\\python tools\\gen_paddles_doc.py CARTELLA
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "icons" / "paddles.png"
FONT = ROOT / "assets" / "fonts" / "PressStart2P-Regular.ttf"
PORTRAITS = ROOT / "assets" / "characters" / "portraits" / "portraits.json"
KINDS = ("arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian")
CODES = ("VAUS-84", "COLOSSUS", "MJOLNIR", "VORTEX", "VIPER-X", "PHANTOM", "AEGIS")
CELL, SHIPS_H, H = 140, 172, 236     # colonna, fascia delle astronavi, altezza dell'immagine


def ship(path: Path) -> Image.Image:
    """La racchetta ritagliata (tutto quello che non è nero) e dimezzata, a pixel netti."""
    im = Image.open(path).convert("RGB")
    box = im.point(lambda v: 255 if v > 12 else 0).getbbox()
    im = im.crop(box)
    return im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.NEAREST)


def main() -> None:
    src = Path(sys.argv[1])
    accent = json.loads(PORTRAITS.read_text(encoding="utf-8"))["accent"]
    out = Image.new("RGB", (CELL * len(KINDS), H))
    draw = ImageDraw.Draw(out)
    name_font, code_font = ImageFont.truetype(str(FONT), 12), ImageFont.truetype(str(FONT), 8)
    for i, kind in enumerate(KINDS):
        s = ship(src / f"paddle_{kind}.png")
        assert s.width <= CELL and s.height <= SHIPS_H, f"{kind}: {s.size} non sta nella colonna"
        x0 = i * CELL
        out.paste(s, (x0 + (CELL - s.width) // 2, (SHIPS_H - s.height) // 2 + 4))
        for text, font, y, color in ((kind.upper(), name_font, SHIPS_H + 14, (255, 255, 255)),
                                     (CODES[i], code_font, SHIPS_H + 36, tuple(accent[kind]))):
            w = draw.textlength(text, font=font)
            draw.text((x0 + (CELL - w) / 2, y), text, font=font, fill=color)
    out.save(OUT)
    print(OUT, out.size)


if __name__ == "__main__":
    main()
