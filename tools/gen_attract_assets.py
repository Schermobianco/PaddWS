"""Genera gli asset della sequenza attract (comuni a Python, Rust e MiSTer).

Tutto è definito su uno schermo virtuale 320x240 (la risoluzione del core MiSTer): le
versioni desktop lo ingrandiscono di altezza/240 intorno al centro dello schermo.

Uscite:
  assets/attract/attract.json   tempi (in frame a 60 Hz), posizioni e colori
  assets/attract/*.png          bitmap a 1 bit (bianco su trasparente, da colorare al disegno):
                                logo PADD, scritta WS, testi in Munro 10 px, cifre
  mister/rtl/gen/pong_attract.vh  le stesse bitmap come funzioni ROM Verilog

Uso:  .venv\\Scripts\\python tools\\gen_attract_assets.py   (richiede Pillow)
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "attract"
VERILOG = ROOT / "mister" / "rtl" / "gen" / "pong_attract.vh"

W, H = 320, 240

BOOT_LINES = ["PADD WS  V4.0", "", "RAM ........ OK", "ROM ........ OK", "VIDEO 240P .. OK", "AUDIO ...... OK"]
STRINGS = {
    "insert_coin": "INSERT COIN",
    "press_start": "PRESS START",
    "credit": "CREDIT ",
    "free_play": "FREE PLAY",
    "copyright": "© 2026 SCHERMOBIANCO",
    "game_over": "GAME OVER",
    # chi ha vinto, sotto GAME OVER: in due, o contro la CPU
    "p1_wins": "P1 WINS",
    "p2_wins": "P2 WINS",
    "you_win": "YOU WIN",
    "cpu_wins": "CPU WINS",
    # vittoria senza punti dell'avversario: al posto di YOU WIN, o di GAME OVER sopra chi ha vinto
    "perfect": "PERFECT",
    "balls": "BALLS ",
    # modalità della demo, alternate a INSERT COIN / PRESS START
    "mode_classic": "CLASSIC",
    "mode_evo": "EVO",
    "mode_next": "NEXT",
    "mode_challenge": "CHALLENGE",
    **{f"boot_{i}": line for i, line in enumerate(BOOT_LINES) if line},
}

# animazione delle strisce: easeOutBack, con il superamento limitato al 4%
SLIDE_FRAMES = 42


def ease_out_back(x: float) -> float:
    c = 1.6
    return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2


def splash_masks() -> tuple[Image.Image, Image.Image]:
    """Logo PADD (nero dello splash tra le strisce) e scritta WS (giallo dentro la striscia)."""
    im = Image.open(ROOT / "assets/images/splash.png").convert("RGB")
    small = im.resize((400, 240), Image.NEAREST).crop((40, 0, 360, 240))     # "cover" a 320x240
    px = small.load()
    black = lambda x, y: sum(px[x, y]) < 200
    logo = Image.new("1", (152, 51), 0)
    for y in range(51):
        for x in range(152):
            logo.putpixel((x, y), 1 if black(82 + x, 94 + y) else 0)
    ws = Image.new("1", (22, 8), 0)
    for y in range(8):
        for x in range(22):
            ws.putpixel((x, y), 0 if black(241 + x, 136 + y) else 1)
    return logo, ws


def text_masks() -> dict[str, Image.Image]:
    font = ImageFont.truetype(str(ROOT / "assets/fonts/munro.ttf"), 10)
    ascent, descent = font.getmetrics()
    raw = {}
    for name, text in {**STRINGS, **{f"digit_{d}": str(d) for d in range(10)}}.items():
        w = max(1, round(font.getlength(text)))
        img = Image.new("L", (w + 4, ascent + descent), 0)
        ImageDraw.Draw(img).text((0, 0), text, font=font, fill=255)
        raw[name] = (w, img.point(lambda v: 255 if v > 127 else 0))
    # righe comuni a tutti i testi: stessa linea di base per scritte e cifre
    rows = [y for y in range(ascent + descent) if any(img.getpixel((x, y)) for _, img in raw.values() for x in range(img.width))]
    top, bottom = rows[0], rows[-1]
    out = {}
    for name, (w, img) in raw.items():
        mask = img.crop((0, top, w, bottom + 1)).convert("1")
        out[name] = mask
    return out


def save_mask(mask: Image.Image, path: Path) -> None:
    rgba = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    rgba.putalpha(mask.convert("L").point(lambda v: 255 if v else 0))
    rgba.save(path)


def verilog_rom(name: str, mask: Image.Image) -> str:
    w, h = mask.size
    row_bits = max(1, (h - 1).bit_length())
    lines = [f"localparam {name.upper()}_W = {w};", f"localparam {name.upper()}_H = {h};",
             f"function [{w - 1}:0] {name}_row(input [{row_bits - 1}:0] row);", "    case (row)"]
    for y in range(h):
        bits = "".join("1" if mask.getpixel((x, y)) else "0" for x in range(w))
        if "1" in bits:
            lines.append(f"        {row_bits}'d{y}: {name}_row = {w}'b{bits};")
    lines += [f"        default: {name}_row = {w}'d0;", "    endcase", "endfunction"]
    # pixel acceso a distanza (dx, dy) dall'angolo: uno scostamento negativo, a 10 bit, diventa
    # un numero grande e cade fuori dalla bitmap, quindi basta sottrarre l'origine
    lines += [f"function {name}_lit(input [9:0] dx, input [9:0] dy);",
              f"    reg [{w - 1}:0] r;",
              "    begin",
              f"        r = {name}_row(dy[{row_bits - 1}:0]);",
              f"        {name}_lit = (dx < {w} && dy < {h}) ? r[{w - 1} - dx] : 1'b0;",
              "    end",
              "endfunction"]
    return "\n".join(lines) + "\n"


def verilog_table(name: str, values: list[int], index_bits: int) -> str:
    lines = [f"function [8:0] {name}(input [{index_bits - 1}:0] i);", "    case (i)"]
    lines += [f"        {index_bits}'d{i}: {name} = 9'd{v};" for i, v in enumerate(values)]
    lines += [f"        default: {name} = 9'd{values[-1]};", "    endcase", "endfunction"]
    return "\n".join(lines) + "\n"


def verilog_timing(spec: dict, ease: list[int]) -> str:
    """Tempi in frame e tabelle precalcolate: l'hardware non deve dividere né moltiplicare."""
    fr, b, st, lg, t = spec["frames"], spec["boot"], spec["stripes"], spec["logo"], spec["title"]
    values = {
        "AT_BOOT_FRAMES": fr["boot"], "AT_STRIPES_FRAMES": fr["stripes"], "AT_LOGO_FRAMES": fr["logo"],
        "AT_TITLE_FRAMES": fr["title"], "AT_DEMO_FRAMES": fr["demo"], "AT_GAME_OVER_FRAMES": fr["game_over"],
        "AT_BOOT_X": b["x"], "AT_BOOT_Y": b["y"], "AT_BOOT_STEP": b["line_step"], "AT_BOOT_LINE_FRAMES": b["line_frames"],
        "AT_BOOT_GRID_FROM": b["grid_from"],
        # reciproco (2^16 / frame per riga, per eccesso): frame / line_frames = frame * R >> 16
        "AT_BOOT_LINE_RECIP": -(-65536 // b["line_frames"]), "AT_STRIPE_START_STEP": st["start_step"], "AT_SLIDE_LAST": len(ease) - 1,
        "AT_STRIPE_H": st["height"], "AT_LOGO_X": lg["x"], "AT_LOGO_Y": lg["y"], "AT_WIPE_FRAMES": lg["wipe_frames"],
        "AT_FLASH_FRAMES": lg["flash_frames"], "AT_WS_X": spec["ws"]["x"], "AT_WS_Y": spec["ws"]["y"],
        "AT_LABEL_Y": t["label_y"], "AT_CREDIT_Y": t["credit_y"], "AT_COPYRIGHT_Y": t["copyright_y"],
        "AT_LABEL_FROM": t["label_from"], "AT_BLINK_PERIOD": t["blink_period"], "AT_BLINK_ON": t["blink_on"],
        "AT_DEMO_LABEL_Y": spec["demo"]["label_y"], "AT_GAME_OVER_Y": spec["game_over"]["label_y"],
        "AT_WINNER_Y": spec["game_over"]["winner_y"],
    }
    lines = [f"localparam integer {k} = {v};" for k, v in values.items()]
    lines += [f"localparam integer AT_STRIPE_ROW_{i} = {r};" for i, r in enumerate(st["rows"])]
    (a0, b0), (a1, b1) = spec["ws"]["off"]
    lines.append(f"localparam integer AT_WS_OFF0_A = {a0}, AT_WS_OFF0_B = {b0}, AT_WS_OFF1_A = {a1}, AT_WS_OFF1_B = {b1};")
    out = "\n".join(lines) + "\n"
    # strisce: bordo destro di quella sinistra e bordo sinistro di quella destra a ogni frame
    slide_bits = (len(ease) - 1).bit_length()
    out += verilog_table("stripe_left_end", [round(st["left_end"] * v / 1000) for v in ease], slide_bits)
    out += verilog_table("stripe_right_start", [round(W - (W - st["right_start"]) * v / 1000) for v in ease], slide_bits)
    # righe del logo già disegnate durante il raster
    wipe_bits = (lg["wipe_frames"] - 1).bit_length()
    out += verilog_table("logo_wipe_rows", [51 * f // lg["wipe_frames"] for f in range(lg["wipe_frames"])], wipe_bits)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    logo, ws = splash_masks()
    texts = text_masks()
    images = {"logo": logo, "ws": ws, **texts}
    for name, mask in images.items():
        save_mask(mask, OUT / f"{name}.png")

    ease = [round(min(ease_out_back(k / SLIDE_FRAMES), 1.04) * 1000) if k else 0 for k in range(SLIDE_FRAMES + 1)]
    spec = {
        "screen": [W, H],
        "colors": {"yellow": [255, 210, 37], "black": [0, 0, 0], "white": [255, 255, 255],
                   "phosphor": [212, 247, 200], "gray": [180, 180, 180]},
        "frames": {"boot": 288, "stripes": 144, "logo": 132, "title": 480, "demo": 1200, "game_over": 180},
        "boot": {"lines": [f"boot_{i}" if line else None for i, line in enumerate(BOOT_LINES)],
                 "x": 40, "y": 60, "line_step": 14, "line_frames": 30, "cursor": [5, 8], "cursor_period": 20,
                 "grid_from": 228, "grid_step": 16},
        "stripes": {"rows": [96, 115, 134], "height": 12, "left_end": 75, "right_start": 241,
                    "start_step": 12, "slide": ease},
        "logo": {"x": 82, "y": 94, "wipe_frames": 84, "flash_frames": 3},
        "ws": {"x": 241, "y": 136, "off": [[0, 15], [30, 45]]},
        "title": {"label_y": 172, "label_scale": 2, "credit_y": 204, "copyright_y": 222,
                  "blink_period": 60, "blink_on": 37, "label_from": 54,
                  "ball": {"x": 10, "y": 60, "vx": 1.6, "vy": 1.1667, "size": 4}},
        "demo": {"label_y": 112, "box_pad": 6, "credit_x": 8, "credit_y": 6},
        "game_over": {"label_y": 112, "winner_y": 132},
        "texts": {name: list(mask.size) for name, mask in images.items()},
    }
    (OUT / "attract.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")

    parts = ["// Generato da tools/gen_attract_assets.py: non modificare a mano.\n", verilog_timing(spec, ease)]
    parts += [verilog_rom(name, mask) for name, mask in images.items() if not name.startswith("digit_")]
    VERILOG.write_text("\n".join(parts), encoding="utf-8")
    print(f"{len(images)} bitmap in {OUT}; tabella delle strisce {ease}")


if __name__ == "__main__":
    main()
