"""Genera le ROM dello schermo a oggetti del core MiSTer (rtl/ui_render.v) e i loro indirizzi per il
firmware delle schermate (rust/mister-ui). Da rilanciare quando cambiano le grafiche comuni
(assets/attract, assets/titles), le scritte di NEXT (tools/gen_next_assets.py), HOW TO PLAY
(tools/gen_howto_assets.py) o il finale (tools/gen_ending_assets.py); poi tools/gen_mister_fw.py.

Uscite (vanno nel repository, così la sintesi e il firmware non richiedono Python):
  mister/rtl/gen/ui_font.hex   font 8x8 (Press Start 2P, come le scritte delle altre versioni): 256
                               codici x 8 righe, un byte per riga, bit 7 = pixel a sinistra
  mister/rtl/gen/ui_gfx.hex    ROM grafica a parole da 32 bit: le immagini una dopo l'altra, righe a
                               passo potenza di due (in parole), pixel da sinistra a destra a partire
                               dai bit alti della parola (1, 2, 4 o 8 bit per pixel); in fondo le righe
                               delle scritte di HOW TO PLAY e del finale, scelte riga per riga dal firmware
  mister/rtl/gen/ui_gfx.vh     dimensione della ROM grafica
  rust/mister-ui/src/assets.rs codici del font (tabella ASCII), posto, misure e formato di ogni immagine,
                               costanti e tabelle delle schermate

Immagini: logo e WS dell'attract, cifre dei punteggi (pong-score.ttf), icone dei bonus, titoli disegnati
(assets/titles: il ruolo del colore a 4 bit, come faceva tools/gen_mister_titles.py), figurine di HOW TO
PLAY, trame della sfilata del finale.

Codici del font: 0-9 le cifre, 10-35 A-Z, 36 spazio, 37 "+", 38 ".", 39 "x", 40 "!" (gli stessi delle
iniziali della classifica), poi gli altri caratteri ASCII stampabili e "©" (0x7F nella tabella ASCII).
Si controlla che ogni scritta delle altre versioni (tools/gen_attract_assets.py, gen_next_assets.py)
composta con le celle del font sia identica alla sua bitmap.

Uso:  .venv\Scripts\python tools\gen_mister_ui.py   (richiede Pillow)
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mister" / "rtl" / "gen"
RUST = ROOT / "rust" / "mister-ui" / "src" / "assets.rs"
FONTS = ROOT / "assets" / "fonts"
TITLES = ROOT / "assets" / "titles"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_attract_assets as attract  # noqa: E402

LEGACY = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ +.x!"
CHARS = LEGACY + "".join(chr(c) for c in range(0x21, 0x7F) if chr(c) not in LEGACY) + "©"
assert len(CHARS) <= 256


def glyph(c: str) -> list[int]:
    """Cella 8x8 di un carattere: come text_mask di gen_attract_assets.py, un byte per riga."""
    img = Image.new("1", (16, 8), 0)
    draw = ImageDraw.Draw(img)
    draw.fontmode = "1"
    draw.text((0, 0), c, font=attract.font(), fill=1)
    rows = []
    for y in range(8):
        rows.append(sum((1 << (7 - x)) for x in range(8) if img.getpixel((x, y))))
        assert not any(img.getpixel((x, y)) for x in range(8, 16)), f"{c!r} esce dalla cella"
    return rows


def check_texts(glyphs: dict[str, list[int]]) -> int:
    """Ogni scritta composta con le celle deve essere identica alla bitmap di gen_attract_assets (e
    alle scritte di gen_next_assets)."""
    import gen_next_assets
    n = 0
    texts = list(attract.STRINGS.values()) + list(gen_next_assets.STRINGS.values())
    for text in texts:
        mask = attract.text_mask(text)
        for y in range(8):
            for x in range(mask.size[0]):
                c = text[x // 8]
                bit = (glyphs[c][y] >> (7 - x % 8)) & 1
                assert bit == mask.getpixel((x, y)), f"{text!r}: pixel ({x}, {y}) diverso"
        n += 1
    return n


class Gfx:
    """ROM grafica: immagini a 1, 2, 4 o 8 bit per pixel, righe a passo 2^stride_sh parole."""

    def __init__(self) -> None:
        self.words: list[int] = []
        self.images: list[tuple[str, int, int, int, int, int]] = []   # nome, base, w, h, bpp_sh, stride_sh

    def add(self, name: str, px: list[list[int]], bpp: int) -> None:
        h, w = len(px), len(px[0])
        bpp_sh = {1: 0, 2: 1, 4: 2, 8: 3}[bpp]
        per_word = 32 // bpp
        need = -(-w // per_word)
        stride_sh = max(0, (need - 1).bit_length())
        stride = 1 << stride_sh
        base = len(self.words)
        for row in px:
            words = [0] * stride
            for u, v in enumerate(row):
                assert 0 <= v < (1 << bpp), (name, v)
                k, s = divmod(u, per_word)
                words[k] |= v << (32 - bpp * (s + 1))
            self.words += words
        self.images.append((name, base, w, h, bpp_sh, stride_sh))


def mask_px(mask: Image.Image) -> list[list[int]]:
    return [[1 if mask.getpixel((x, y)) else 0 for x in range(mask.size[0])] for y in range(mask.size[1])]


def score_digits() -> list[list[list[int]]]:
    """Cifre dei punteggi (pong-score.ttf a 22 pixel), come rasterize di gen_mister_assets.py."""
    font = ImageFont.truetype(str(FONTS / "pong-score.ttf"), 22)
    ascent, descent = font.getmetrics()
    chars = "0123456789"
    width = max(round(font.getlength(c)) for c in chars)
    cells = []
    for c in chars:
        im = Image.new("L", (width, ascent + descent), 0)
        ImageDraw.Draw(im).text((0, 0), c, font=font, fill=255)
        cells.append([[1 if im.getpixel((x, y)) > 127 else 0 for x in range(width)] for y in range(ascent + descent)])
    rows = [y for y in range(ascent + descent) if any(any(cell[y]) for cell in cells)]
    top, bottom = rows[0], rows[-1]
    assert width == 22 and bottom - top + 1 == 22, (width, top, bottom)
    return [cell[top:bottom + 1] for cell in cells]


def title_px(name: str) -> list[list[int]]:
    im = Image.open(TITLES / f"{name}.png")
    assert im.mode == "P", name
    return [[im.getpixel((x, y)) for x in range(im.size[0])] for y in range(im.size[1])]


def attract_consts() -> list[str]:
    """Tempi e posizioni dell'attract (assets/attract/attract.json), come pong_attract.vh."""
    import json
    spec = json.loads((ROOT / "assets" / "attract" / "attract.json").read_text(encoding="utf-8"))
    fr, b, st, lg, t = spec["frames"], spec["boot"], spec["stripes"], spec["logo"], spec["title"]
    ease = st["slide"]
    values = {
        "BOOT_X": b["x"], "BOOT_Y": b["y"], "BOOT_STEP": b["line_step"], "BOOT_GRID_FROM": b["grid_from"],
        "BOOT_LINE_RECIP": -(-65536 // b["line_frames"]), "STRIPE_START_STEP": st["start_step"],
        "SLIDE_LAST": len(ease) - 1, "STRIPE_H": st["height"], "LOGO_X": lg["x"], "LOGO_Y": lg["y"],
        "WIPE_FRAMES": lg["wipe_frames"], "FLASH_FRAMES": lg["flash_frames"], "WS_X": spec["ws"]["x"],
        "WS_Y": spec["ws"]["y"], "LABEL_Y": t["label_y"], "CREDIT_Y": t["credit_y"], "COPYRIGHT_Y": t["copyright_y"],
        "LABEL_FROM": t["label_from"], "BLINK_ON": t["blink_on"], "DEMO_LABEL_Y": spec["demo"]["label_y"],
        "GAME_OVER_Y": spec["game_over"]["label_y"], "WINNER_Y": spec["game_over"]["winner_y"],
    }
    out = ["", "/// Attract (assets/attract/attract.json, come pong_attract.vh).", "pub mod at {"]
    out += [f"    pub const {k}: i32 = {v};" for k, v in values.items()]
    out.append(f"    pub const STRIPE_ROWS: [i32; 3] = {st['rows']};")
    (a0, b0), (a1, b1) = spec["ws"]["off"]
    out.append(f"    pub const WS_OFF: [(i32, i32); 2] = [({a0}, {b0}), ({a1}, {b1})];")
    out.append(f"    pub const BOOT_LINES: [&[u8]; 6] = [{', '.join('b' + json.dumps(attract.BOOT_LINES[i]) for i in range(6))}];")
    left = [round(st["left_end"] * v / 1000) for v in ease]
    right = [round(320 - (320 - st["right_start"]) * v / 1000) for v in ease]
    out.append(f"    pub const STRIPE_LEFT_END: [i32; {len(left)}] = {left};")
    out.append(f"    pub const STRIPE_RIGHT_START: [i32; {len(right)}] = {right};")
    out.append("}")
    return out


def howto_assets(gfx: Gfx) -> list[str]:
    """HOW TO PLAY (dai file di tools/gen_howto_assets.py): righe delle scritte a 2 bit per pixel, una
    dopo l'altra (20 parole), più una vuota; mappa {controllo, y} -> riga; figurine 32x32; freccetta."""
    import re
    vh = (OUT / "pong_howto.vh").read_text(encoding="utf-8")
    nrows = int(re.search(r"HT_TEXT_ROWS = (\d+);", vh).group(1))
    text = [int(v, 16) for v in (OUT / "howto_text.hex").read_text().split()]
    rows = [int(v, 16) for v in (OUT / "howto_rows.hex").read_text().split()]
    spr = [int(v, 16) for v in (OUT / "howto_sprites.hex").read_text().split()]
    base = len(gfx.words)
    for r in range(nrows + 1):
        px = text[320 * r:320 * r + 320] if r < nrows else [0] * 320
        words = [0] * 20
        for u, v in enumerate(px):
            words[u // 16] |= v << (30 - 2 * (u % 16))
        gfx.words += words
    for s in range(10):
        gfx.add(f"ht_sprite_{s}", [spr[1024 * s + 32 * y:1024 * s + 32 * y + 32] for y in range(32)], 4)
    arrow = [re.search(rf"3'd{r}: ht_arrow_row = 5'b([01]+);", vh).group(1) for r in range(7)]
    gfx.add("ht_arrow", [[int(c) for c in a] for a in arrow], 1)
    consts = {k: int(v) for k, v in re.findall(r"(HT_[A-Z0-9_]+) = (\d+)[,;]", vh)}
    out = ["", "/// HOW TO PLAY (mister/rtl/gen/pong_howto.vh e i suoi file).", "pub mod howto {"]
    out += [f"    pub const {k[3:]}: i32 = {v};" for k, v in consts.items()]
    out.append(f"    /// prima parola delle righe delle scritte (20 parole per riga; la riga {nrows} è vuota)")
    out.append(f"    pub const TEXT_BASE: u32 = {base};")
    out.append("    /// riga delle scritte di ogni riga dello schermo, per controllo (joystick, paddle, spinner)")
    out.append("    pub const ROWS: [[u8; 240]; 3] = [")
    for c in range(3):
        m = [rows[256 * c + y] & 0xFF if rows[256 * c + y] & 0x100 else nrows for y in range(240)]
        out.append("        [" + ", ".join(str(v) for v in m) + "],")
    out += ["    ];", "}"]
    return out


def kind_px(kind: int, t: int, r: int, h: int, tilt: int, preview: bool, ghosts: bool, pw: int) -> int:
    """Pixel (t, r) di una racchetta del tipo `kind` (come kind_px del vecchio next_render.v e
    rust/mister-ui/src/paddle.rs): 0 niente (o taglio), 1 corpo, 2 segno, 3 dettaglio, 5-7 immagini
    del RUSH dalla più scura."""
    body = 0 <= t < pw and 0 <= r < h
    if kind == 3:
        d = r - (h >> 1)
        m = abs(tilt)
        sh = (d if m & 1 else 0) + ((d << 1) if m & 2 else 0)
        sh = -(sh >> 3) if tilt < 0 else (sh >> 3)
        return 1 if 0 <= t - sh < pw and 0 <= r < h else 0
    if kind == 2:
        if -(pw // 2) <= t < pw and 0 <= r < h:
            return 3 if r in ((h >> 1) - 10, (h >> 1) - 9, (h >> 1) + 8, (h >> 1) + 9) else 1
        return 0
    if kind == 4:
        c = 0
        if body:
            c = 1
            if ((r == 0 or r == h - 1) and t >= pw - 2) or ((r == 1 or r == h - 2) and t == pw - 1):
                c = 0
        if pw <= t < pw + 2 and r in ((h >> 1) - 4, (h >> 1) - 3, (h >> 1) + 2, (h >> 1) + 3):
            c = 3
        return c
    if kind == 1:
        return (2 if t == 0 and (r < (h >> 3) or r >= h - (h >> 3)) else 1) if body else 0
    if kind == 5:
        c = 1 if body else 0
        if ghosts and 0 <= r < h and -3 * pw <= t < -1 and t not in (-pw - 1, -2 * pw - 1):
            c = 7 if t >= -pw else 6 if t >= -2 * pw else 5
        return c
    if kind == 6:
        c = 1 if body else 0
        q = h >> 2
        if preview and t in (-8, -7) and -q <= r < h + q and ((r + q) & 7) < 5:
            c = 2
        return c
    return 1 if body else 0


def paddle_images(gfx: Gfx) -> list[str]:
    """Racchette della scelta, rivolte a destra (a sinistra si specchiano): l'anteprima a grandezza
    reale (con il pezzo di muro del GUARDIAN e le immagini del RUSH) e la miniatura a metà, un pixel
    ogni due. 4 bit per pixel: i codici di kind_px, i colori dalla tavolozza."""
    import re
    vh = (OUT / "pong_params.vh").read_text(encoding="utf-8")
    heights = [int(re.search(rf"3'd{k}: kind_px_h = (\d+);", vh).group(1)) for k in range(7)]
    pw = int(re.search(r"P_PAD_WIDTH = (\d+);", vh).group(1)) >> 16
    out = ["", "/// Racchette della scelta: immagine, prima colonna t e prima riga r (coordinate del tipo).",
           "pub mod pads {", "    use crate::Img;"]
    for name, half in (("PREVIEW", False), ("MINI", True)):
        entries = []
        for k in range(7):
            h = heights[k]
            tilt = 3 if k == 3 else 0
            pts = {}
            for t in range(-20, 20):
                for r in range(-h, 2 * h):
                    tt, rr = (2 * t, 2 * r) if half else (t, r)
                    c = kind_px(k, tt, rr, h, tilt, not half, True, pw)
                    if c:
                        pts[(t, r)] = c
            t0, t1 = min(p[0] for p in pts), max(p[0] for p in pts) + 1
            r0, r1 = min(p[1] for p in pts), max(p[1] for p in pts) + 1
            px = [[pts.get((t, r), 0) for t in range(t0, t1)] for r in range(r0, r1)]
            gfx.add(f"pad_{name.lower()}_{k}", px, 4)
            n, base, w, hh, bs, ss = gfx.images[-1]
            entries.append(f"(Img {{ base: {base}, w: {w}, h: {hh}, bpp_sh: {bs}, stride_sh: {ss} }}, {t0}, {r0})")
        out.append(f"    pub const {name}: [(Img, i32, i32); 7] = [")
        out += [f"        {e}," for e in entries]
        out.append("    ];")
    out.append("}")
    return out


def ending_assets(gfx: Gfx) -> list[str]:
    """Finale (dai file di tools/gen_ending_assets.py): righe di bitmap a 1 bit da 320 pixel (10 parole,
    una dopo l'altra: si scelgono con la tabella delle righe), mappa delle righe e costanti."""
    import re
    vh = (OUT / "pong_ending.vh").read_text(encoding="utf-8")
    consts = {k: int(v) for k, v in re.findall(r"END_([A-Z0-9_]+) = (\d+)[,;]", vh)}
    text = [int(v, 16) for v in (OUT / "ending_text.hex").read_text().split()]
    words = [int(v, 16) for v in (OUT / "ending_map.hex").read_text().split()]
    base = len(gfx.words)
    for r in range(consts["TEXT_ROWS"]):
        row = text[40 * r:40 * r + 40]
        for k in range(10):
            w = 0
            for b in range(4):
                byte = row[4 * k + b]
                for bit in range(8):          # nel file il bit 0 è il pixel a sinistra
                    if byte >> bit & 1:
                        w |= 1 << (31 - (8 * b + bit))
            gfx.words.append(w)
    out = ["", "/// Finale della scalata (mister/rtl/gen/pong_ending.vh e i suoi file).", "pub mod ending {"]
    out += [f"    pub const {k}: i32 = {v};" for k, v in consts.items()]
    out.append(f"    /// prima parola delle righe di bitmap (10 parole per riga)")
    out.append(f"    pub const TEXT_BASE: u32 = {base};")
    out.append("    /// mappa delle righe: [8:0] riga, [12:9] riga del glifo, [21:13] x, [23:22] scala, [25:24] colore,")
    out.append("    /// [27:26] gruppo, [29:28] riga del punteggio")
    out.append(f"    pub const MAP: [u32; {len(words)}] = [")
    for k in range(0, len(words), 8):
        out.append("        " + " ".join(f"0x{w:08X}," for w in words[k:k + 8]))
    out += ["    ];", "}"]
    return out


# BLASTER è in corsivo (tools/gen_title_assets.py, blaster()): la lettera j, senza l'inclinazione,
# parte dalla colonna BL_X0 + BL_STEP * j; la riga v è spostata a destra di int((h - 1 - v) * BL_K).
# Si controlla sul PNG che ogni pixel delle lettere cada nella sua cella.
BL_X0, BL_STEP, BL_K, BL_LETTERS = 22, 9, 0.34, 7


def guardian_starts(px: list[list[int]]) -> list[int]:
    """GUARDIAN: prima colonna di ogni lettera (gruppi di colonne accese separati da colonne vuote)."""
    w = len(px[0])
    lit = [any(row[x] for row in px) for x in range(w)]
    starts = [x for x in range(w) if lit[x] and (x == 0 or not lit[x - 1])]
    assert len(starts) == 8, starts
    return starts


def blaster_slant(h: int) -> list[int]:
    return [int((h - 1 - v) * BL_K) for v in range(h)]


def check_blaster(px: list[list[int]]) -> None:
    """Ogni pixel a destra delle scie sta nella cella di una delle sette lettere (8 colonne su 9)."""
    h, w = len(px), len(px[0])
    slant = blaster_slant(h)
    used = set()
    for v in range(h):
        for u in range(w):
            if not px[v][u]:
                continue
            d = u - slant[v] - BL_X0
            if d < 0:
                assert u < BL_X0 - 1, (u, v)        # scie di velocità, a sinistra della B
                continue
            assert d % BL_STEP < BL_STEP - 1 and d // BL_STEP < BL_LETTERS, (u, v)
            used.add(d // BL_STEP)
    assert used == set(range(BL_LETTERS)), used


def game_consts() -> list[str]:
    """Misure del gioco (pong_params.vh, dal core), scritte di NEXT e lettere dei titoli disegnati."""
    import re
    import gen_next_assets as nxt
    vh = (OUT / "pong_params.vh").read_text(encoding="utf-8")
    heights = [int(re.search(rf"3'd{k}: kind_px_h = (\d+);", vh).group(1)) for k in range(7)]
    pw = int(re.search(r"P_PAD_WIDTH = (\d+);", vh).group(1)) >> 16
    shots = int(re.search(r"P_BLASTER_SHOTS = (\d+);", vh).group(1))
    cap = 2 * (int(re.search(r"P_CAPSULE_HALF = (\d+);", vh).group(1)) >> 16)
    g = guardian_starts(title_px("name_guardian"))
    bl_h = len(title_px("name_blaster"))
    check_blaster(title_px("name_blaster"))
    slant = blaster_slant(bl_h)
    sin = [round(256 * __import__("math").sin(2 * __import__("math").pi * i / 64)) for i in range(64)]
    q = lambda xs: "[" + ", ".join("b" + __import__("json").dumps(x) for x in xs) + "]"
    return [
        "",
        "/// Misure del gioco (mister/rtl/gen/pong_params.vh) e scritte di NEXT (tools/gen_next_assets.py).",
        "pub mod game {",
        f"    /// altezza in pixel delle racchette di ogni tipo (PaddleKind)",
        f"    pub const KIND_H: [i32; 7] = {heights};",
        f"    pub const PW: i32 = {pw};",
        f"    pub const BLASTER_SHOTS: i32 = {shots};",
        f"    /// lato delle capsule in partita (e nella scelta dei bonus)",
        f"    pub const CAP: i32 = {cap};",
        f"    pub const BONUS_NAMES: [&[u8]; 8] = {q(nxt.NAMES)};",
        f"    pub const KIND_NAMES: [&[u8]; 7] = {q(nxt.KINDS)};",
        f"    pub const KIND_TAGS: [&[u8]; 7] = {q(nxt.TAGS)};",
        f"    pub const MOVE_NAMES: [&[u8]; 2] = {q(nxt.MOVES)};",
        f"    /// GUARDIAN: prima colonna di ogni lettera del nome disegnato",
        f"    pub const GUARDIAN_X: [i32; 8] = {g};",
        f"    /// BLASTER (in corsivo): lettera j dalla colonna BLASTER_X0 + BLASTER_STEP j, riga v spostata di",
        f"    /// BLASTER_SLANT[v]",
        f"    pub const BLASTER_X0: i32 = {BL_X0};",
        f"    pub const BLASTER_STEP: i32 = {BL_STEP};",
        f"    pub const BLASTER_LETTERS: i32 = {BL_LETTERS};",
        f"    pub const BLASTER_SLANT: [i32; {bl_h}] = {slant};",
        f"    pub const BLASTER_CX0: i32 = {BL_X0 + (BL_STEP - 2) // 2 + slant[bl_h // 2]};",
        f"    /// seno in Q8 (sin_q8 di pong_next.vh)",
        f"    pub const SIN_Q8: [i32; 64] = {sin};",
        "}",
    ]


# nomi degli avversari nell'ordine di PaddleKind
KINDS = ["arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian"]


def rust_name(name: str) -> str:

    return "IMG_" + name.upper()


def main() -> None:
    glyphs = {c: glyph(c) for c in CHARS}
    checked = check_texts(glyphs)

    gfx = Gfx()
    logo, ws = attract.splash_masks()
    gfx.add("logo", mask_px(logo), 1)
    gfx.add("ws", mask_px(ws), 1)
    for d, cell in enumerate(score_digits()):
        gfx.add(f"score_{d}", cell, 1)
    import gen_next_assets
    for b, icon in enumerate(gen_next_assets.ICONS):
        gfx.add(f"icon_{b}", [[1 if ch == "#" else 0 for ch in row] for row in icon], 1)
    # titoli disegnati (assets/titles): 4 bit per pixel, il ruolo del colore (0 trasparente)
    # (dalla 4.4.0 anche la targa WARNING! e il sigillo di OMEGA)
    for name in ["challenger", "perfect"] + [f"name_{k}" for k in KINDS] + ["warning", "name_omega"]:
        gfx.add(name, title_px(name), 4)
    paddles = paddle_images(gfx)
    # mezzeria delle schermate di scelta (trattini di 4 righe ogni 8, larghi 2) e bordo delle capsule
    gfx.add("pick_net", [[1, 1] if y % 8 < 4 else [0, 0] for y in range(160)], 1)
    cap = 12
    gfx.add("cap_frame", [[1 if x in (0, cap - 1) or y in (0, cap - 1) else 0 for x in range(cap)] for y in range(cap)], 1)
    # trame a scacchi delle immagini del RUSH nella sfilata del finale (x e y dispari; x + y dispari)
    gfx.add("pat_a", [[1 if (u & 1 and v & 1) else 0 for u in range(32)] for v in range(64)], 1)
    gfx.add("pat_b", [[1 if (u ^ v) & 1 else 0 for u in range(32)] for v in range(64)], 1)
    howto = howto_assets(gfx)
    ending = ending_assets(gfx)

    OUT.mkdir(parents=True, exist_ok=True)
    font_rom = [glyphs[c][y] if i < len(CHARS) else 0 for i, c in enumerate(CHARS + "\0" * (256 - len(CHARS)))
                for y in range(8)]
    (OUT / "ui_font.hex").write_text("".join(f"{b:02x}\n" for b in font_rom), encoding="ascii", newline="\n")
    (OUT / "ui_gfx.hex").write_text("".join(f"{w:08x}\n" for w in gfx.words), encoding="ascii", newline="\n")
    (OUT / "ui_gfx.vh").write_text(
        "// Generato da tools/gen_mister_ui.py: non modificare a mano.\n"
        f"localparam integer UI_GFX_WORDS = {len(gfx.words)};\n"
        f"localparam integer UI_GFX_AW = {max(1, (len(gfx.words) - 1).bit_length())};\n",
        encoding="ascii", newline="\n")

    # il carattere 0x7F (DEL) è "©"
    ascii_map = [CHARS.index(chr(c)) if chr(c) in CHARS else CHARS.index(" ") for c in range(128)]
    ascii_map[0x7F] = CHARS.index("©")
    lines = [
        "//! Generato da tools/gen_mister_ui.py: non modificare a mano.",
        "//! Codici del font 8x8 e immagini della ROM grafica dello schermo a oggetti.",
        "",
        "use crate::Img;",
        "",
        "/// Codice del font di ogni carattere ASCII (quelli che mancano diventano spazi; 0x7F è \"©\").",
        "pub const FONT_MAP: [u8; 128] = [",
    ]
    for k in range(0, 128, 16):
        lines.append("    " + " ".join(f"{v}," for v in ascii_map[k:k + 16]))
    lines += ["];", f"/// Codice di \"©\".", f"pub const CODE_COPY: u8 = {CHARS.index('©')};"]
    cols = [0] * 256
    for i, c in enumerate(CHARS):
        cols[i] = 0
        for y in range(8):
            cols[i] |= glyphs[c][y]
    lines.append("/// Colonne con l'inchiostro di ogni codice del font (bit 7 = colonna 0): le lettere delle")
    lines.append("/// scritte animate sono gruppi di colonne accese, come `verilog_letters` di gen_attract_assets.py.")
    lines.append("pub const FONT_COLS: [u8; 256] = [")
    for k in range(0, 256, 16):
        lines.append("    " + " ".join(f"{v}," for v in cols[k:k + 16]))
    lines += ["];", ""]
    for name, base, w, h, bpp_sh, stride_sh in gfx.images:
        lines.append(f"pub const {rust_name(name)}: Img = Img {{ base: {base}, w: {w}, h: {h}, "
                     f"bpp_sh: {bpp_sh}, stride_sh: {stride_sh} }};")
    lines += attract_consts()
    lines.append("/// Cifre dei punteggi (22x22), dalla 0 alla 9.")
    lines.append("pub const IMG_SCORE: [Img; 10] = [" + ", ".join(rust_name(f"score_{d}") for d in range(10)) + "];")
    lines += game_consts()
    lines += howto
    lines += paddles
    lines += ending
    lines.append("/// Icone 9x9 dei bonus (codici dei bonus).")
    lines.append("pub const IMG_ICON: [Img; 8] = [" + ", ".join(rust_name(f"icon_{b}") for b in range(8)) + "];")
    lines.append("/// Nomi disegnati degli avversari (PaddleKind).")
    lines.append("pub const IMG_NAME: [Img; 7] = [" + ", ".join(rust_name(f"name_{k}") for k in KINDS) + "];")
    RUST.parent.mkdir(parents=True, exist_ok=True)
    RUST.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"font: {len(CHARS)} caratteri, {checked} scritte controllate; grafica: {len(gfx.images)} immagini, "
          f"{len(gfx.words)} parole ({-(-len(gfx.words) * 32 // 10240)} M10K)")


if __name__ == "__main__":
    main()
