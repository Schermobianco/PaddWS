"""Genera i font del core MiSTer dai TTF originali.

Uscita in mister/rtl/gen/ (va nel repository, così la sintesi non richiede Python):
  pong_fonts.vh   glifi come funzioni ROM Verilog, una riga di pixel per indirizzo

Uso:  .venv\\Scripts\\python tools\\gen_mister_assets.py   (richiede Pillow)
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "assets" / "fonts"
OUT = ROOT / "mister" / "rtl" / "gen"

# (nome Verilog, file, dimensione in pixel, caratteri)
FONT_SPECS = [
    ("SCORE", "pong-score.ttf", 22, "0123456789"),      # punteggi: cifre a segmenti
    ("TEXT", "munro.ttf", 10, "0123456789TOP "),         # scritta TOP: Munro alla sua dimensione nativa
]


def rasterize(path: Path, size: int, chars: str) -> tuple[int, list[list[str]]]:
    """Glifi in celle di larghezza fissa (avanzamento massimo), righe ritagliate sull'inchiostro comune."""
    font = ImageFont.truetype(str(path), size)
    ascent, descent = font.getmetrics()
    width = max(round(font.getlength(c)) for c in chars)
    cells = []
    for c in chars:
        im = Image.new("L", (width, ascent + descent), 0)
        ImageDraw.Draw(im).text((0, 0), c, font=font, fill=255)
        cells.append([[im.getpixel((x, y)) > 127 for x in range(width)] for y in range(ascent + descent)])
    rows = [y for y in range(ascent + descent) if any(any(cell[y]) for cell in cells)]
    top, bottom = rows[0], rows[-1]
    glyphs = [["".join("1" if p else "0" for p in cell[y]) for y in range(top, bottom + 1)] for cell in cells]
    return width, glyphs


def font_verilog(name: str, width: int, chars: str, glyphs: list[list[str]]) -> str:
    height = len(glyphs[0])
    char_bits = max(1, (len(chars) - 1).bit_length())
    row_bits = max(1, (height - 1).bit_length())
    fn = f"{name.lower()}_glyph"
    lines = [
        f"// Font {name}: {len(chars)} caratteri \"{chars}\", celle {width}x{height}, bit {width - 1} = pixel a sinistra",
        f"localparam {name}_W = {width};",
        f"localparam {name}_H = {height};",
    ]
    for i, c in enumerate(chars):
        label = {" ": "SPACE"}.get(c, c)
        if not label.isdigit():
            lines.append(f"localparam [{char_bits - 1}:0] {name}_CH_{label} = {char_bits}'d{i};")
    lines.append(f"function [{width - 1}:0] {fn}(input [{char_bits - 1}:0] ch, input [{row_bits - 1}:0] row);")
    lines.append(f"    case ({{ch, row}})")
    for i, glyph in enumerate(glyphs):
        for r, bits in enumerate(glyph):
            if "1" in bits:
                lines.append(f"        {{{char_bits}'d{i}, {row_bits}'d{r}}}: {fn} = {width}'b{bits};")
    lines.append(f"        default: {fn} = {width}'d0;")
    lines.append("    endcase")
    lines.append("endfunction")
    return "\n".join(lines) + "\n"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    parts = ["// Generato da tools/gen_mister_assets.py: non modificare a mano.\n"]
    for name, file, size, chars in FONT_SPECS:
        width, glyphs = rasterize(FONTS / file, size, chars)
        parts.append(font_verilog(name, width, chars, glyphs))
        print(f"font {name}: {len(chars)} glifi {width}x{len(glyphs[0])}")
    (OUT / "pong_fonts.vh").write_text("\n".join(parts), encoding="utf-8")


if __name__ == "__main__":
    main()
