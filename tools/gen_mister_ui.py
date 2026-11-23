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
                               delle scritte di HOW TO PLAY e del finale, scelte riga per riga dal firmware.
                               Le prime 32.768 parole; il resto in ui_gfx2.hex (almeno una parola): con
                               una sola memoria oltre l'indirizzo a 15 bit Quartus metteva in logica le
                               RAM del framework (circa 18.000 ALM in più)
  mister/rtl/gen/ui_gfx.vh     dimensioni delle due parti della ROM grafica
  rust/mister-ui/src/assets.rs codici del font (tabella ASCII), posto, misure e formato di ogni immagine,
                               costanti e tabelle delle schermate

Immagini: logo e WS dell'attract, cifre dei punteggi (pong-score.ttf), icone dei bonus, titoli disegnati
(assets/titles: il ruolo del colore a 4 bit, come faceva tools/gen_mister_titles.py), figurine di HOW TO
PLAY, ritratti dei personaggi (assets/characters/portraits: scelta della racchetta, schermo VS,
sfilata del finale).

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

    def drop_last(self) -> None:
        """Toglie l'ultima immagine aggiunta (con `add`), e le sue parole in fondo alla ROM."""
        name, base, w, h, bpp_sh, stride_sh = self.images.pop()
        del self.words[base:]

    def add_packed(self, name: str, px: list[list[int]], bpp: int) -> int:
        """Immagine con le righe una dopo l'altra, senza il passo potenza di due: il firmware la legge
        con la tabella delle righe (riga della sorgente in parole dalla base). Restituisce le parole
        per riga."""
        h, w = len(px), len(px[0])
        per_word = 32 // bpp
        assert w % per_word == 0, (name, w)
        row_words = w // per_word
        base = len(self.words)
        for row in px:
            words = [0] * row_words
            for u, v in enumerate(row):
                assert 0 <= v < (1 << bpp), (name, v)
                k, s = divmod(u, per_word)
                words[k] |= v << (32 - bpp * (s + 1))
            self.words += words
        self.images.append((name, base, w, h, {1: 0, 2: 1, 4: 2, 8: 3}[bpp], 0))
        return row_words


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
    # NEXT sotto il logo (spec["next"], vedi next_spec di tools/gen_attract_assets.py)
    nx = spec["next"]
    for name, v in (("NEXT_X", nx["x"]), ("NEXT_Y", nx["y"]), ("NEXT_PITCH", nx["pitch"]), ("NEXT_START", nx["start"]),
                    ("NEXT_STEP", nx["step"]), ("NEXT_LETTER_FRAMES", nx["letter_frames"]),
                    ("NEXT_LINE_X", nx["line"]["x"]), ("NEXT_LINE_Y", nx["line"]["y"]), ("NEXT_LINE_H", nx["line"]["h"]),
                    ("NEXT_LINE_START", nx["line"]["start"]), ("NEXT_LINE_FRAMES", nx["line"]["frames"])):
        out.append(f"    pub const {name}: i32 = {v};")
    out.append(f"    pub const NEXT_AMP: [u8; {len(nx['amp'])}] = {nx['amp']};")
    out.append(f"    pub const NEXT_PRESENT: [u16; {len(nx['present'])}] = {nx['present']};")
    out.append(f"    pub const NEXT_NOISE: [u8; {len(nx['noise'])}] = {nx['noise']};")
    out.append(f"    pub const NEXT_LINE_HALF: [u8; {len(nx['line']['half'])}] = {nx['line']['half']};")
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


def paddle_images(gfx: Gfx) -> list[str]:
    """Racchette dei personaggi fuori dalla partita, ferme (tools/paddle_shapes.py: gli sprite e gli
    effetti di kind_px di next_render.v), rivolte a destra (a sinistra si specchiano), a grandezza reale.
    PREVIEW per la scelta e lo schermo VS: TWIST inclinata e le immagini dello scatto del RUSH;
    PLAIN per le forme di OMEGA e la sua rottura nel finale (le stesse, tranne TWIST dritta e RUSH
    senza le immagini). 8 bit per pixel: il colore è la base
    della tavolozza (pal::PADS, o pal::PADS_OMEGA con il corpo di OMEGA) più il valore del pixel, da
    1 a PAL_COLORS (PAL: i colori comuni, poi i tre toni di ogni personaggio)."""
    import json
    import re
    import paddle_shapes as ps
    vh = (OUT / "pong_params.vh").read_text(encoding="utf-8")
    heights = [int(re.search(rf"3'd{k}: kind_px_h = (\d+);", vh).group(1)) for k in range(7)]
    pw = int(re.search(r"P_PAD_WIDTH = (\d+);", vh).group(1)) >> 16
    assert pw in (4, 5), "corpo largo 4 (MiSTer) o 5 (PC)"
    spec = json.loads((PORTRAITS / "portraits.json").read_text(encoding="utf-8"))
    accents = [tuple(spec["accent"][k]) for k in KINDS]
    # valori dei pixel: i ruoli comuni, poi i tre toni del personaggio k da 13 + 3 k
    shared = [ps.BODY, ps.SHADE, ps.GRAY, ps.GRAY_LIGHT, ps.DARK, ps.DARK_DEEP, ps.BLACK, ps.SIGNAL, ps.SHADOW,
              ps.GHOST1, ps.GHOST2, ps.GHOST3]
    marks = [ps.MARK, ps.MARK_DARK, ps.MARK_LIGHT]
    rush = accents[ps.RUSH]
    colors = [ps.RGB[r] for r in shared[:9]]
    # immagini dello scatto del RUSH: il suo colore al 18, 36 e 54% sul nero, come su PC
    colors += [tuple(round(c * 0.18 * k) for c in rush) for k in (1, 2, 3)]
    for a in accents:
        ramp = ps.mark_ramp(a)
        colors += [ramp[m] for m in marks]

    def value(kind: int, role: int) -> int:
        if role in marks:
            return 1 + len(shared) + 3 * kind + marks.index(role)
        return 1 + shared.index(role)

    out = ["", "/// Racchette fuori dalla partita: immagine, prima colonna t (0 = retro del corpo) e prima riga r.",
           "pub mod pads {", "    use crate::Img;"]
    for name, preview in (("PREVIEW", True), ("PLAIN", False)):
        entries = []
        for k in range(7):
            h = heights[k]
            px = ps.render(k, h, tilt=3 if preview and k == ps.TWIST else 0, pw=pw)
            if preview and k == ps.RUSH:
                # immagini dello scatto dietro, come la scelta del PC (sotto l'intercettore): la sagoma
                # dello sprite
                s = ps.ship(k)
                su0, su1 = s.u_range()
                for g, role in ((1, ps.GHOST1), (2, ps.GHOST2), (3, ps.GHOST3)):
                    off = -2 * pw * (4 - g)
                    for u in range(su0, su1 + 1):
                        c = ps.col(u, pw)
                        if c is None:
                            continue
                        for v in range(h):
                            if s.at(u, v * s.h // h) != ps.NONE:
                                px.setdefault((c + off, v), role)
            u0, u1 = min(p[0] for p in px), max(p[0] for p in px) + 1
            v0, v1 = min(p[1] for p in px), max(p[1] for p in px) + 1
            img = [[value(k, px[(u, v)]) if (u, v) in px else 0 for u in range(u0, u1)] for v in range(v0, v1)]
            gfx.add(f"pad_{name.lower()}_{k}", img, 8)
            n, base, w, hh, bs, ss = gfx.images[-1]
            entries.append(f"(Img {{ base: {base}, w: {w}, h: {hh}, bpp_sh: {bs}, stride_sh: {ss} }}, {u0 + 3}, {v0})")
            if not preview and k not in (ps.TWIST, ps.RUSH):
                entries[-1] = previews[k]
                gfx.drop_last()
        if preview:
            previews = entries
        out.append(f"    pub const {name}: [(Img, i32, i32); 7] = [")
        out += [f"        {e}," for e in entries]
        out.append("    ];")
    out.append(f"    /// Colori dei valori 1..={len(colors)} dei pixel (a partire da pal::PADS + 1).")
    out.append(f"    pub const PAL: [u32; {len(colors)}] = [")
    for i in range(0, len(colors), 8):
        out.append("        " + " ".join(f"0x{r:02X}{g:02X}{b:02X}," for r, g, b in colors[i:i + 8]))
    out.append("    ];")
    # corpo di OMEGA: viola (anche con l'easter egg RED) e il suo tono in ombra
    omega = [(0xA0, 0x40, 0xE0), (0xA0, 0x40, 0xE0)]
    out.append("    /// Corpo e corpo in ombra di OMEGA (valori 1 e 2): viola (anche con l'easter egg).")
    out.append("    pub const OMEGA_BODY: [[u32; 2]; 2] = [")
    for c in omega:
        s = ps.body_shade(c)
        out.append(f"        [0x{c[0]:02X}{c[1]:02X}{c[2]:02X}, 0x{s[0]:02X}{s[1]:02X}{s[2]:02X}],")
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


# parole della prima memoria della ROM grafica (indirizzo a 15 bit)
GFX_SPLIT = 32768
# finestra della DDR3 nello spazio delle immagini (ui_render.v): 4 ritratti grandi (2 mostrati e 2 in
# preparazione), o i medi della sfilata (8 mostrati e uno in preparazione), o un'astronave
WIN_BASE = 0x8000
WIN_WORDS = 5184

# nomi degli avversari nell'ordine di PaddleKind
KINDS = ["arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian"]
PORTRAITS = ROOT / "assets" / "characters" / "portraits"


def portrait_px(name: str, size: tuple[int, int], cut: bool = False) -> list[list[int]]:
    """Ritratto a ruoli (tools/gen_portraits.py, la variante dei PC): l'indice del PNG è il ruolo del
    colore; qui il ruolo + 1, perché 0 è trasparente. Con `cut` (i ritratti grandi, che stanno sulla
    griglia delle schermate prima della partita) il nero collegato ai bordi, lo sfondo, è trasparente."""
    im = Image.open(PORTRAITS / f"{name}.png")
    assert im.mode == "P" and im.size == size, (name, im.mode, im.size)
    w, h = im.size
    px = [[im.getpixel((x, y)) + 1 for x in range(w)] for y in range(h)]
    if cut:
        todo = [(x, y) for y in range(h) for x in range(w) if x in (0, w - 1) or y in (0, h - 1)]
        while todo:
            x, y = todo.pop()
            if not (0 <= x < w and 0 <= y < h) or px[y][x] != 1:
                continue
            px[y][x] = 0
            todo += [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
    return px


def portrait_assets(gfx: Gfx, ddr: Gfx) -> list[str]:
    """Ritratti della scelta della racchetta, dello schermo VS e della sfilata del finale: grandi
    (88x104, i sette tipi e OMEGA svelato) con le righe una dopo l'altra (11 parole: il firmware le
    sceglie con la tabella delle righe, senza il passo di 16 parole), caselle della griglia (32x32, i
    sette tipi e OMEGA in sagoma), medi della sfilata (64x72, normali e sconfitti, e OMEGA in sagoma).
    4 bit per pixel: il ruolo + 1; i colori dei ruoli di ogni personaggio vanno nella tavolozza.
    Grandi e medi stanno nella DDR3 (`ddr`, file paddws_gfx.rom: la base è la parola nel file), le
    caselle nella ROM grafica."""
    import json
    spec = json.loads((PORTRAITS / "portraits.json").read_text(encoding="utf-8"))
    roles = spec["roles"]
    big, small, mid = tuple(spec["big"]), (spec["small"], spec["small"]), tuple(spec["mid"])
    names = KINDS + ["omega"]
    row_words = {ddr.add_packed(f"pt_big_{n}", portrait_px(n, big, cut=True), 4) for n in names}
    assert len(row_words) == 1
    for n in KINDS:
        gfx.add(f"pt_small_{n}", portrait_px(f"{n}_small", small), 4)
    gfx.add("pt_small_omega", portrait_px("omega_small", small), 4)
    for n in names:
        ddr.add(f"pt_mid_{n}", portrait_px(f"{n}_mid", mid), 4)
        ddr.add(f"pt_mid_{n}_defeated", portrait_px(f"{n}_mid_defeated", mid), 4)
    ddr.add("pt_mid_omega_locked", portrait_px("omega_mid_locked", mid), 4)

    def rgb(c: list[int]) -> str:
        return f"0x{c[0]:02X}{c[1]:02X}{c[2]:02X}"

    pal = []
    for n in names:
        accent = spec["accent"][n]
        cols = []
        for role in roles:
            if role == "accent":
                cols.append(rgb(accent))
            elif role == "accent_dark":
                cols.append(rgb([int(c * spec["dark"] + 0.5) for c in accent]))  # come round() di Rust
            else:
                cols.append(rgb(spec["grays"][role]))
        pal.append("[" + ", ".join(cols) + "]")
    out = ["", "/// Ritratti dei personaggi (assets/characters/portraits, tools/gen_portraits.py): 4 bit per pixel,",
           "/// il ruolo del colore + 1; i tipi nell'ordine di PaddleKind, poi OMEGA.", "pub mod portraits {",
           "    use crate::Img;", "    use crate::assets::*;",
           "    /// grandi (nella DDR3): righe di BIG_ROW_WORDS parole una dopo l'altra (tabella delle righe);",
           "    /// OMEGA svelato",
           "    pub const BIG: [Img; 8] = [" + ", ".join(rust_name(f"pt_big_{n}") for n in names) + "];",
           f"    pub const BIG_ROW_WORDS: i32 = {row_words.pop()};",
           "    /// caselle della griglia; OMEGA in sagoma",
           "    pub const SMALL: [Img; 8] = [" + ", ".join(rust_name(f"pt_small_{n}") for n in names) + "];",
           "    /// sfilata del finale (nella DDR3): normale e sconfitto",
           "    pub const MID: [[Img; 2]; 8] = [" + ", ".join(
               f"[{rust_name(f'pt_mid_{n}')}, {rust_name(f'pt_mid_{n}_defeated')}]" for n in names) + "];",
           "    pub const MID_LOCKED: Img = IMG_PT_MID_OMEGA_LOCKED;",
           "    /// riga dopo l'ultima con il disegno in ogni ritratto grande (art_bottom di portraits.json):",
           "    /// i nomi dello schermo VS e della scelta ci centrano sotto",
           "    pub const ART_BOTTOM: [i32; 8] = [" + ", ".join(str(spec["art_bottom"][n]) for n in names) + "];",
           "    /// la più bassa: i ritratti scendono di ART_BASE - ART_BOTTOM e finiscono tutti sulla stessa riga",
           f"    pub const ART_BASE: i32 = {spec['art_base']};",
           f"    /// colori RGB dei ruoli 1-{len(roles)} di ogni personaggio",
           f"    pub const PAL: [[u32; {len(roles)}]; 8] = [{', '.join(pal)}];",
           "}"]
    return out


SHIPS_DIR = ROOT / "assets" / "ships"
SHIP_W, SHIP_H = 160, 90


def ship_assets(ddr: Gfx) -> list[str]:
    """Illustrazioni isometriche delle astronavi (assets/ships/*.png, 160x90 a 4 bit per pixel):
    indice 0 trasparente (sfondo nero), 1..15 i 15 colori principali di ciascuna nave; righe
    impaccate (20 parole per riga, usate con ltrow nella schermata THE END). Nella DDR3."""
    row_words_set = set()
    pals = []
    for n in KINDS:
        src = Image.open(SHIPS_DIR / f"{n}.png").convert("RGB")
        # campionamento nativo 5:1 (224x126), poi riduzione pulita a 160x90
        nat = src.resize((src.width // 5, src.height // 5), Image.NEAREST)
        small = nat.resize((SHIP_W, SHIP_H), Image.NEAREST)
        px_rgb = list(small.getdata())
        counts: dict[tuple[int, int, int], int] = {}
        for c in px_rgb:
            if c != (0, 0, 0):
                counts[c] = counts.get(c, 0) + 1
        # fino a 15 colori più frequenti (quasi tutte le navi ne hanno 14-16 non neri)
        top = [c for c, _ in sorted(counts.items(), key=lambda kv: -kv[1])[:15]]
        while len(top) < 15:
            top.append((0, 0, 0))

        def nearest(c: tuple[int, int, int]) -> int:
            if c == (0, 0, 0):
                return 0
            best_i, best_d = 1, 10**9
            for idx, tc in enumerate(top, start=1):
                d = (c[0] - tc[0]) ** 2 + (c[1] - tc[1]) ** 2 + (c[2] - tc[2]) ** 2
                if d < best_d:
                    best_d, best_i = d, idx
            return best_i

        cache = {c: nearest(c) for c in counts}
        grid = [[0 if small.getpixel((x, y)) == (0, 0, 0) else cache[small.getpixel((x, y))]
                 for x in range(SHIP_W)] for y in range(SHIP_H)]
        row_words_set.add(ddr.add_packed(f"ship_{n}", grid, 4))
        pals.append("[" + ", ".join(f"0x{r:02X}{g:02X}{b:02X}" for r, g, b in top) + "]")
    assert len(row_words_set) == 1
    out = [
        "",
        "/// Illustrazioni isometriche delle astronavi (assets/ships/*.png, 160x90 a 4 bpp) per THE END,",
        "/// nella DDR3.",
        "pub mod ships {",
        "    use crate::Img;",
        "    use crate::assets::*;",
        "    pub const ART: [Img; 7] = [" + ", ".join(rust_name(f"ship_{n}") for n in KINDS) + "];",
        f"    pub const ROW_WORDS: i32 = {row_words_set.pop()};",
        "    /// Tavolozza 1..=15 di ciascuna astronave (caricata in pal::SHIP durante THE END).",
        "    pub const PAL: [[u32; 15]; 7] = [",
        *[f"        {p}," for p in pals],
        "    ];",
        "}",
    ]
    return out


def rust_name(name: str) -> str:

    return "IMG_" + name.upper()


def main() -> None:
    glyphs = {c: glyph(c) for c in CHARS}
    checked = check_texts(glyphs)

    gfx = Gfx()
    logo, ws = attract.splash_masks()
    gfx.add("logo", mask_px(logo), 1)
    gfx.add("ws", mask_px(ws), 1)
    gfx.add("next", mask_px(attract.next_mask()), 1)
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
    # VS dello schermo VS a scala 3 (lo schermo a oggetti ingrandisce solo di 2, 4 e 8)
    vs = [glyphs["V"][y // 3] << 8 | glyphs["S"][y // 3] for y in range(24)]
    gfx.add("vs3", [[(vs[y] >> (15 - x // 3)) & 1 for x in range(48)] for y in range(24)], 1)
    howto = howto_assets(gfx)
    ending = ending_assets(gfx)
    # immagini nella DDR3 (file paddws_gfx.rom, caricato dal .mra all'avvio): il firmware le copia
    # nella finestra (WIN_BASE) quando servono; la loro base è la parola nel file
    ddr = Gfx()
    portraits = portrait_assets(gfx, ddr)
    ships = ship_assets(ddr)
    assert len(gfx.words) <= WIN_BASE, f"ROM grafica oltre la finestra della DDR3 ({len(gfx.words)} parole)"

    OUT.mkdir(parents=True, exist_ok=True)
    font_rom = [glyphs[c][y] if i < len(CHARS) else 0 for i, c in enumerate(CHARS + "\0" * (256 - len(CHARS)))
                for y in range(8)]
    (OUT / "ui_font.hex").write_text("".join(f"{b:02x}\n" for b in font_rom), encoding="ascii", newline="\n")
    # due memorie: le prime GFX_SPLIT parole e il resto (vedi l'intestazione)
    low, high = gfx.words[:GFX_SPLIT], gfx.words[GFX_SPLIT:] or [0]
    (OUT / "ui_gfx.hex").write_text("".join(f"{w:08x}\n" for w in low), encoding="ascii", newline="\n")
    (OUT / "ui_gfx2.hex").write_text("".join(f"{w:08x}\n" for w in high), encoding="ascii", newline="\n")
    # DDR3: parole a 32 bit little endian, nell'ordine del file (due per parola a 64 bit della DDR3)
    (OUT / "paddws_gfx.rom").write_bytes(b"".join(w.to_bytes(4, "little") for w in ddr.words))
    (OUT / "ui_gfx.vh").write_text(
        "// Generato da tools/gen_mister_ui.py: non modificare a mano.\n"
        f"localparam integer UI_GFX_WORDS = {len(gfx.words)};\n"
        f"localparam integer UI_GFX_AW = {max(1, (len(gfx.words) - 1).bit_length())};\n"
        f"// prima parte (ui_gfx.hex) e seconda (ui_gfx2.hex, dall'indirizzo {GFX_SPLIT})\n"
        f"localparam integer UI_GFX1_WORDS = {len(low)};\n"
        f"localparam integer UI_GFX2_WORDS = {len(high)};\n"
        f"localparam integer UI_GFX2_AW = {max(1, (len(high) - 1).bit_length())};\n"
        f"// finestra della DDR3: base nello spazio delle immagini e parole\n"
        f"localparam integer UI_WIN_BASE = {WIN_BASE};\n"
        f"localparam integer UI_WIN_WORDS = {WIN_WORDS};\n"
        f"// file paddws_gfx.rom (parole a 32 bit)\n"
        f"localparam integer UI_DDR_WORDS = {len(ddr.words)};\n",
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
    lines.append("// immagini nella DDR3: `base` è la parola nel file paddws_gfx.rom; si disegnano dopo averle")
    lines.append("// copiate nella finestra (`Win`)")
    for name, base, w, h, bpp_sh, stride_sh in ddr.images:
        lines.append(f"pub const {rust_name(name)}: Img = Img {{ base: {base}, w: {w}, h: {h}, "
                     f"bpp_sh: {bpp_sh}, stride_sh: {stride_sh} }};")
    lines.append("/// Finestra della DDR3 nello spazio delle immagini: base e parole (ui_render.v).")
    lines.append(f"pub const WIN_BASE: u16 = {WIN_BASE};")
    lines.append(f"pub const WIN_WORDS: u16 = {WIN_WORDS};")
    lines.append("/// Parole del file paddws_gfx.rom.")
    lines.append(f"pub const DDR_WORDS: u32 = {len(ddr.words)};")
    lines += attract_consts()
    lines.append("/// Cifre dei punteggi (22x22), dalla 0 alla 9.")
    lines.append("pub const IMG_SCORE: [Img; 10] = [" + ", ".join(rust_name(f"score_{d}") for d in range(10)) + "];")
    lines += game_consts()
    lines += howto
    lines += paddles
    lines += ending
    lines += portraits
    lines += ships
    lines.append("/// Icone 9x9 dei bonus (codici dei bonus).")
    lines.append("pub const IMG_ICON: [Img; 8] = [" + ", ".join(rust_name(f"icon_{b}") for b in range(8)) + "];")
    lines.append("/// Nomi disegnati degli avversari (PaddleKind).")
    lines.append("pub const IMG_NAME: [Img; 7] = [" + ", ".join(rust_name(f"name_{k}") for k in KINDS) + "];")
    RUST.parent.mkdir(parents=True, exist_ok=True)
    RUST.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"font: {len(CHARS)} caratteri, {checked} scritte controllate; grafica: {len(gfx.images)} immagini, "
          f"{len(gfx.words)} parole ({-(-len(gfx.words) * 32 // 10240)} M10K); DDR3: {len(ddr.images)} immagini, "
          f"{len(ddr.words)} parole, finestra {WIN_WORDS} parole ({-(-WIN_WORDS * 32 // 10240)} M10K)")


if __name__ == "__main__":
    main()
