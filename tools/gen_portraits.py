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
Le misure sono multipli di 8 (11x13 e 4x4 caratteri). Un ritratto del C64 ritoccato a mano con
tools/c64_editor.html (blocco tEXt "c64edit" nel PNG) non viene sovrascritto: per rifarlo dalla
sorgente si cancella il file.

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
from PIL import Image, ImageDraw

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
C64_ACCENT = {"arcade": 7, "titan": 8, "hammer": 2, "twist": 4, "blaster": 5, "rush": 3,
              "guardian": 14, "omega": 4}

# Inquadratura Space Age (sorgenti 1376x768): (fx, fy, big_src_w, big_up, big_shift_x, small_src_w, small_up)
# Ravvicinata sul volto e sul busto come gli originali, così i ritratti 88x104 e 32x32 restano grandi e nitidi
FRAME_SPEC = {
    "arcade":   (680, 245, 720, 0.30,  -20, 390, 0.44),
    "titan":    (687, 235, 860, 0.27,    0, 440, 0.44),
    "hammer":   (745, 240, 790, 0.28, -140, 430, 0.44),
    "twist":    (680, 235, 820, 0.28,    0, 430, 0.44),
    "blaster":  (675, 245, 820, 0.28,  105, 420, 0.44),
    "rush":     (870, 235, 820, 0.28, -120, 430, 0.44),
    "guardian": (688, 220, 800, 0.25,    0, 390, 0.42),
    "omega":    (695, 255, 800, 0.31,    0, 420, 0.45),
}
# Ritocchi di inquadratura solo per i ritratti grandi (88x104) di PC, web e MiSTer: dove si può
# evitare il taglio ai lati senza rimpicciolire troppo il personaggio lo si include intero (HAMMER,
# GUARDIAN, pugno destro di RUSH) o si tengono dentro i pugni di TITAN prima della sfumatura.
BIG_PC_SPEC = {
    "titan":    (687, 235, 980, 0.27,    0, 440, 0.44),
    "hammer":   (745, 240, 845, 0.28, -205, 430, 0.44),
    "rush":     (870, 235, 830, 0.28,  -55, 430, 0.44),
    "guardian": (688, 220, 895, 0.25,    0, 390, 0.42),
}
# Matrice Bayer 4x4 centrata in 0 per sfumare i bordi tagliati dei ritratti grandi verso il nero
BAYER4 = (np.array([
    [ 0,  8,  2, 10],
    [12,  4, 14,  6],
    [ 3, 11,  1,  9],
    [15,  7, 13,  5],
], dtype=float) + 0.5) / 16.0 - 0.5
BIG_EDGE_FADE = 10
BIG_EDGE_DITHER = 28.0
# lente HAL-9000 magenta di OMEGA Space Age (pixel di source/omega.jpg 1376x768)
OMEGA_LENS = (636, 210, 744, 316)


def omega_locked(im: Image.Image) -> Image.Image:
    """Sagoma scura del Monolite OMEGA con la sola lente circolare HAL-9000 magenta accesa."""
    rgb = np.asarray(im.convert("RGB"), dtype=float)
    h, w, _ = rgb.shape
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    bg = rgb.max(axis=2) <= 25
    out = np.array([14.0, 10.0, 20.0]) + lum[..., None] * 0.16
    magenta = (rgb[..., 0] > 120) & (rgb[..., 2] > 120) & (rgb[..., 1] < 110)
    ys, xs = np.mgrid[0:h, 0:w]
    ex0, ey0, ex1, ey1 = OMEGA_LENS
    cx, cy = (ex0 + ex1) / 2.0, (ey0 + ey1) / 2.0
    rx, ry = (ex1 - ex0) / 2.0, (ey1 - ey0) / 2.0
    in_lens = ((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2 <= 1.0
    glow = in_lens & (rgb[..., 0] > 90) & (rgb[..., 2] > 90)
    out = np.where((magenta & ~glow)[..., None], rgb * 0.30, out)
    out = np.where(glow[..., None], rgb, out)
    out = np.where(bg[..., None], 0.0, out)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def source(name: str, defeated: bool, locked: bool) -> Image.Image:
    """Il disegno del personaggio, sconfitto (<nome>_defeated.jpg) o no; `locked` per OMEGA in sagoma."""
    im = Image.open(SRC / (f"{name}_defeated.jpg" if defeated else f"{name}.jpg")).convert("RGB")
    if locked:
        im = omega_locked(im)
    return im


def palette(name: str) -> np.ndarray:
    accent = ACCENT[name]
    cols = [GRAYS[r] for r in ROLES[:5]] + [accent, tuple(round(c * DARK) for c in accent)]
    return np.array(cols, dtype=float)


def crop_hires(name: str, w: int, h: int, defeated: bool = False, locked: bool = False,
               spec: dict[str, tuple] | None = None) -> Image.Image:
    """Ritaglia la regione esatta da FRAME_SPEC ad alta risoluzione (senza downscale sfocato)."""
    im = source(name, defeated, locked)
    fx, fy, b_sw, b_up, b_sh, s_sw, s_up = (spec or FRAME_SPEC).get(name, FRAME_SPEC[name])
    small = (w == SMALL and h == SMALL)
    use_sw = s_sw if small else b_sw
    use_up = s_up if small else b_up
    use_sh = 0 if small else b_sh
    if defeated and not small:
        # Leggero respiro in alto per far entrare completamente le stelline stordite sopra i caschi
        use_sw = round(use_sw * 1.12)
        use_up = min(0.42, use_up + 0.06)
    fx = fx + use_sh
    src_h = use_sw * h / w
    x0, y0 = round(fx - use_sw / 2), round(fy - src_h * use_up)
    x1, y1 = round(fx + use_sw / 2), round(fy + src_h * (1 - use_up))
    pad = 400
    big = Image.new("RGB", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0))
    big.paste(im, (pad, pad))
    return big.crop((x0 + pad, y0 + pad, x1 + pad, y1 + pad))


def framed(name: str, w: int, h: int, src_w: int, up: float, shift: int,
           defeated: bool = False, locked: bool = False,
           spec: dict[str, tuple] | None = None) -> Image.Image:
    """Inquadra il personaggio Space Age sul volto/busto (FRAME_SPEC) come gli originali."""
    return crop_hires(name, w, h, defeated=defeated, locked=locked, spec=spec).resize((w, h), Image.LANCZOS)


def _exterior_bg(rgb: np.ndarray, thresh: int = 24) -> np.ndarray:
    """Maschera dello sfondo nero esterno connesso ai bordi."""
    dark = rgb.max(axis=2) < thresh
    mask = Image.fromarray(np.pad(dark, 1, constant_values=True).astype(np.uint8) * 255).copy()
    ImageDraw.floodfill(mask, (0, 0), 128)
    return np.asarray(mask)[1:-1, 1:-1] == 128


def _classify_c64_hires(rgb: np.ndarray, name: str, locked: bool = False) -> tuple[np.ndarray, np.ndarray]:
    """Classifica ogni pixel ad alta risoluzione in uno dei ruoli piatti C64 (0=BLACK, 1=WHITE,
    15=LGREY, 12=GRAY, C64_ACCENT[name]) PRIMA del downscale, evitando aloni grigi anti-aliasing."""
    arr = rgb.astype(float)
    h, w = arr.shape[:2]
    ext = _exterior_bg(arr, thresh=24)
    mx = arr.max(axis=2)
    mn = arr.min(axis=2)
    sat = np.where(mx > 1, (mx - mn) / np.maximum(mx, 1.0), 0.0)
    lum = arr @ np.array([0.299, 0.587, 0.114])
    acc = C64_ACCENT[name]

    if locked:
        is_acc = (~ext) & (sat > 0.25) & (mx > 75)
        is_blk = ext | ((~is_acc) & (lum < 22))
        idx = np.full((h, w), 11, dtype=np.uint8)
        idx[lum > 70] = 12
        idx[is_blk] = 0
        idx[is_acc] = acc
        return idx, ext

    if name == "guardian":
        bdom = (arr[..., 2] - arr[..., 0]) > 18
        is_blue_bright = (~ext) & bdom & (lum > 186) & (sat < 0.55)
        is_blue_dark = (~ext) & bdom & (lum < 58)
        is_acc = (~ext) & (sat > 0.22) & (mx > 55) & (~is_blue_bright) & (~is_blue_dark)
    else:
        # Richiede saturazione più netta sui pixel molto chiari/scuri per evitare aloni sul casco bianco
        sat_thr = np.where((lum > 195) | (lum < 55), 0.36, 0.26)
        is_acc = (~ext) & (sat > sat_thr) & (mx > 52)
        is_blue_bright = np.zeros((h, w), dtype=bool)
        is_blue_dark = np.zeros((h, w), dtype=bool)

    is_blk = ext | is_blue_dark | ((~is_acc) & (~is_blue_bright) & (lum < 66))
    is_wht = is_blue_bright | ((~is_blk) & (~is_acc) & (lum >= 172))
    is_gray = (~is_blk) & (~is_acc) & (~is_wht) & (lum < 126)

    idx = np.full((h, w), 15, dtype=np.uint8)
    idx[is_gray] = 12
    idx[is_wht] = 1
    idx[is_blk] = 0
    idx[is_acc] = acc
    return idx, ext


def _enhance_guardian_barrier(hi_rgb: np.ndarray, hi_idx: np.ndarray, hi_ext: np.ndarray) -> np.ndarray:
    """Fa emergere chiaramente le mani e la griglia esagonale dietro la barriera blu di GUARDIAN."""
    arr = hi_rgb.astype(float)
    h = arr.shape[0]
    out = hi_idx.copy()
    y0 = int(h * 0.36)
    sub = arr[y0:]
    bdom = (sub[..., 2] - sub[..., 0]) > 15
    lum = sub @ np.array([0.299, 0.587, 0.114])
    gx = np.abs(np.diff(lum, axis=1, prepend=lum[:, :1]))
    gy = np.abs(np.diff(lum, axis=0, prepend=lum[:1, :]))
    grad = np.maximum(gx, gy)
    sub_idx = out[y0:]
    sub_ext = hi_ext[y0:]
    sub_idx[(~sub_ext) & bdom & (lum > 168)] = 1
    sub_idx[(~sub_ext) & bdom & (lum < 118) & (grad > 12)] = 0
    out[y0:] = sub_idx
    return out


def _pool_pixel_art(hi_idx: np.ndarray, hi_ext: np.ndarray, w: int, h: int, name: str,
                    small: bool = False) -> tuple[np.ndarray, np.ndarray]:
    """Ridimensiona la mappa etichettata a (w, h) per pooling a priorità pixel-art (senza sfocature
    RGB): preserva contorni neri netti da 1px e dettagli colorati sottili."""
    H, W = hi_idx.shape
    acc = C64_ACCENT[name]
    ys = np.linspace(0, H, h + 1).round().astype(int)
    xs = np.linspace(0, W, w + 1).round().astype(int)

    out = np.zeros((h, w), dtype=np.uint8)
    for j in range(h):
        y0, y1 = ys[j], max(ys[j] + 1, ys[j + 1])
        for i in range(w):
            x0, x1 = xs[i], max(xs[i] + 1, xs[i + 1])
            blk = hi_idx[y0:y1, x0:x1]
            eb = hi_ext[y0:y1, x0:x1]
            n = blk.size
            n_ext = int(eb.sum())
            if n_ext >= n * 0.55:
                out[j, i] = 0
                continue
            c_blk = int((blk == 0).sum())
            c_wht = int((blk == 1).sum())
            c_lgr = int((blk == 15).sum())
            c_gry = int((blk == 12).sum())
            c_dgr = int((blk == 11).sum())
            c_acc = int((blk == acc).sum())
            c_int_blk = c_blk - n_ext

            # Contorno nero interno netto (ma lascia emergere il colore su visiere/monocoli crepati)
            if c_int_blk >= max(1, n * 0.26) and (c_acc < n * 0.22 or c_int_blk >= n * 0.45):
                out[j, i] = 0
                continue
            if c_acc >= max(1, n * 0.28):
                out[j, i] = 1 if c_wht >= n * 0.52 else acc
                continue
            counts = [(c_wht, 1), (c_lgr, 15), (c_gry, 12), (c_dgr, 11), (c_acc, acc), (c_blk, 0)]
            _, best_col = max(counts, key=lambda x: x[0])
            if small and best_col == 15 and c_wht >= n * 0.25:
                best_col = 1
            out[j, i] = best_col

    dark = out == 0
    mask = Image.fromarray(np.pad(dark, 1, constant_values=True).astype(np.uint8) * 255).copy()
    ImageDraw.floodfill(mask, (0, 0), 128)
    ext_lo = np.asarray(mask)[1:-1, 1:-1] == 128
    return out, ext_lo


def _solve_c64_cells(idx: np.ndarray, ext: np.ndarray, name: str, small: bool = False,
                     locked: bool = False) -> tuple[np.ndarray, float]:
    """Risolve ogni cella 8x8 con al massimo 2 colori piatti (ZERO dithering Bayer):
    - ogni cella che tocca lo sfondo nero esterno ha SEMPRE 0 (BLACK) obbligatorio;
    - VIETATO far sanguinare il colore accento sui caschi/volti bianchi (WHITE <-> ACCENT = 1e6),
      così i confini usano il nero come contorno/ombra naturale invece di macchiare il casco;
    - nelle celle interne con sottili righe nere tra bianco e accento (es. fascia sul petto o anelli),
      permette (WHITE, ACCENT) per mantenere continue le bande colorate."""
    h, w = idx.shape
    pal = np.array(C64_PALETTE, dtype=float)
    acc = C64_ACCENT[name]
    if locked:
        cand = [0, 11, 12, acc]
    elif small:
        cand = [0, 1, 12, acc] if name in ("titan", "hammer", "omega") else [0, 1, 15, acc]
    else:
        cand = [0, 1, 15, 12, acc]

    all_pairs = list(combinations(cand, 2))
    blk_pairs = [(0, c) for c in cand if c != 0]

    def build_cost(internal: bool) -> np.ndarray:
        cm = np.zeros((16, 16), dtype=float)
        for s in set(cand + [0, 1, 15, 12, 11, acc]):
            for t in cand:
                if s == t:
                    continue
                d = float(((pal[s] - pal[t]) ** 2).sum())
                if s in (1, 15) and t == acc:
                    d = 1e6
                elif s == acc and t in (1, 15):
                    d = 1e6
                elif s == 12 and t == acc:
                    d = 4e5
                elif s == acc and t == 12:
                    d = 4e5
                elif s == 0 and t != 0:
                    if internal and t == acc:
                        d *= 0.85
                    elif internal and t == 12:
                        d *= 1.2
                    else:
                        d *= 2.8
                elif s == 1 and t == 0:
                    d *= 1.45
                elif s == acc and t == 0:
                    d *= 1.35 if internal else 1.05
                elif s == 1 and t == 15:
                    d *= 1.9
                elif s == 15 and t == 1:
                    d *= 0.55
                cm[s, t] = d
        return cm

    cm_ext = build_cost(internal=False)
    cm_int = build_cost(internal=True)

    out = np.zeros((h, w), dtype=np.uint8)
    total_err = 0.0
    for cy in range(0, h, 8):
        for cx in range(0, w, 8):
            cell = idx[cy:cy + 8, cx:cx + 8].reshape(-1)
            cbg = ext[cy:cy + 8, cx:cx + 8].reshape(-1)
            uniq = set(cell.tolist())
            if len(uniq) <= 2 and uniq.issubset(cand):
                out[cy:cy + 8, cx:cx + 8] = cell.reshape(8, 8)
                continue
            has_bg = bool(cbg.any())
            n_blk = int((cell == 0).sum())
            cm = cm_int if ((not small) and (not has_bg) and n_blk <= 18) else cm_ext
            pairs = blk_pairs if has_bg else all_pairs
            best_e = 1e30
            best_px = cell
            for a, b in pairs:
                ca = cm[cell, a]
                cb = cm[cell, b]
                pick_b = cb < ca
                if has_bg:
                    pick_b = np.where(cbg, False, pick_b)
                e = float(np.where(pick_b, cb, ca).sum())
                if has_bg and b == 15 and (cell == 1).sum() >= 5:
                    e *= 1.4
                if e < best_e:
                    best_e = e
                    best_px = np.where(pick_b, b, a).astype(np.uint8)
            out[cy:cy + 8, cx:cx + 8] = best_px.reshape(8, 8)
            total_err += best_e
    return out, total_err


def c64(name: str, w: int, h: int, src_w: int, up: float, shift: int,
        defeated: bool = False, locked: bool = False) -> Image.Image:
    """Versione C64 hires pixel art (max 2 colori piatti per cella 8x8, zero Bayer):
    quantizza ad alta risoluzione, riduce a pixel-art netta, allinea alla griglia 8x8 con shift
    sub-cella ottimo e garantisce sfondo nero e caschi bianchi puliti senza attribute-clash."""
    small = (w == SMALL and h == SMALL)
    hi_im = crop_hires(name, w, h, defeated=defeated, locked=locked)
    hi_rgb = np.asarray(hi_im)
    hi_idx, hi_ext = _classify_c64_hires(hi_rgb, name, locked=locked)
    if name == "guardian" and not defeated and not locked and h >= MID_H:
        hi_idx = _enhance_guardian_barrier(hi_rgb, hi_idx, hi_ext)

    base_idx, base_ext = _pool_pixel_art(hi_idx, hi_ext, w, h, name, small=small)

    best_err = 1e30
    best_out = base_idx
    rng = range(-3, 4) if not small else range(-2, 3)
    for dy in rng:
        for dx in rng:
            sh_idx = np.zeros_like(base_idx)
            sh_ext = np.ones_like(base_ext)
            sy0, sy1 = max(0, -dy), min(h, h - dy)
            sx0, sx1 = max(0, -dx), min(w, w - dx)
            ty0, ty1 = max(0, dy), min(h, h + dy)
            tx0, tx1 = max(0, dx), min(w, w + dx)
            sh_idx[ty0:ty1, tx0:tx1] = base_idx[sy0:sy1, sx0:sx1]
            sh_ext[ty0:ty1, tx0:tx1] = base_ext[sy0:sy1, sx0:sx1]
            out, err = _solve_c64_cells(sh_idx, sh_ext, name, small=small, locked=locked)
            if err < best_err:
                best_err = err
                best_out = out

    # Pulizia micro-granelli (<= 3px) di accento isolati sullo sfondo nero (rispettando max 2 colori/cella)
    acc = C64_ACCENT[name]
    if not defeated and not locked and not small:
        vis = np.zeros_like(best_out, dtype=bool)
        for y in range(h):
            for x in range(w):
                if best_out[y, x] != acc or vis[y, x]:
                    continue
                comp = [(y, x)]
                vis[y, x] = True
                qi = 0
                while qi < len(comp):
                    cy0, cx0 = comp[qi]
                    qi += 1
                    for dy0, dx0 in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        ny, nx = cy0 + dy0, cx0 + dx0
                        if 0 <= ny < h and 0 <= nx < w and not vis[ny, nx] and best_out[ny, nx] == acc:
                            vis[ny, nx] = True
                            comp.append((ny, nx))
                if len(comp) <= 3:
                    for cy0, cx0 in comp:
                        cell_u = set(np.unique(best_out[(cy0 // 8) * 8:(cy0 // 8 + 1) * 8,
                                                        (cx0 // 8) * 8:(cx0 // 8 + 1) * 8]).tolist())
                        if 0 in cell_u or len(cell_u) == 1:
                            best_out[cy0, cx0] = 0

    im = Image.new("P", (w, h))
    im.putdata(best_out.flatten().tolist())
    im.putpalette([v for rgb in C64_PALETTE for v in rgb])
    return im


def fade_cut_edges(lo: np.ndarray, pal: np.ndarray) -> np.ndarray:
    """Sfuma verso il nero i soli lati (sinistro e/o destro) dove il ritratto grande tocca il bordo."""
    raw = ((lo[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(3).argmin(2)
    cut_l = bool((raw[:, 0] != 0).any())
    cut_r = bool((raw[:, -1] != 0).any())
    if not (cut_l or cut_r):
        return lo
    h, w, _ = lo.shape
    xs = np.arange(w, dtype=float)
    mask = np.ones((h, w), dtype=float)
    if cut_l:
        t = np.clip(xs / float(BIG_EDGE_FADE), 0.0, 1.0)
        mask = np.minimum(mask, (t * t * (3.0 - 2.0 * t))[None, :])
    if cut_r:
        t = np.clip((w - 1 - xs) / float(BIG_EDGE_FADE), 0.0, 1.0)
        mask = np.minimum(mask, (t * t * (3.0 - 2.0 * t))[None, :])
    out = lo * mask[:, :, None]
    in_fade = (mask > 0.0) & (mask < 1.0)
    bayer = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    out = np.where(in_fade[:, :, None], np.clip(out + bayer[:, :, None] * BIG_EDGE_DITHER, 0.0, 255.0), out)
    if cut_l:
        out[:, 0, :] = 0.0
    if cut_r:
        out[:, -1, :] = 0.0
    return out


def portrait(name: str, w: int, h: int, src_w: int, up: float, shift: int,
             defeated: bool = False, locked: bool = False) -> Image.Image:
    is_big = (w == BIG_W and h == BIG_H and not defeated and not locked)
    spec = BIG_PC_SPEC if is_big else None
    lo = np.asarray(framed(name, w, h, src_w, up, shift, defeated, locked, spec=spec), dtype=float)
    pal = palette(name)
    if is_big:
        lo = fade_cut_edges(lo, pal)
    roles = ((lo[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(3).argmin(2).astype(np.uint8)
    out = Image.new("P", (w, h))
    out.putdata(roles.flatten().tolist())
    # i colori della palette servono solo a vedere i PNG; il gioco usa gli indici
    out.putpalette([int(v) for rgb in pal for v in rgb])
    return out


def hand_edited(path: Path) -> bool:
    """Vero se il PNG è stato salvato da tools/c64_editor.html (blocco tEXt "c64edit")."""
    if not path.exists():
        return False
    with Image.open(path) as im:
        return "c64edit" in im.info


def main() -> None:
    (OUT / "c64").mkdir(parents=True, exist_ok=True)
    kept = []
    for make, folder in ((portrait, OUT), (c64, OUT / "c64")):
        def save(image: Image.Image, stem: str) -> None:
            path = folder / f"{stem}.png"
            if folder != OUT and hand_edited(path):
                kept.append(stem)       # ritoccato a mano: resta com'è
                return
            image.save(path, optimize=True)

        for name in NAMES:
            save(make(name, BIG_W, BIG_H, BIG_SRC_W, 0.0, 0), name)
            save(make(name, SMALL, SMALL, SMALL_SRC_W, 0.0, 0), f"{name}_small")
        save(make("omega", SMALL, SMALL, SMALL_SRC_W, 0.0, 0, locked=True), "omega_small")
        save(make("omega", BIG_W, BIG_H, BIG_SRC_W, 0.0, 0), "omega")
        # finale: ritratti medi, normali e sconfitti; OMEGA anche in sagoma (non ancora battuto)
        for name in NAMES + ["omega"]:
            save(make(name, MID_W, MID_H, BIG_SRC_W, 0.0, 0), f"{name}_mid")
            save(make(name, MID_W, MID_H, BIG_SRC_W, 0.0, 0, defeated=True), f"{name}_mid_defeated")
        save(make("omega", MID_W, MID_H, BIG_SRC_W, 0.0, 0, locked=True), "omega_mid_locked")
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
    if kept:
        print(f"  C64 ritoccati a mano, non sovrascritti: {', '.join(kept)}")


if __name__ == "__main__":
    main()
