"""Asset della versione C64 con il campo girato (c64/gen/rotated, build -Rotated).

Parte dai file di c64/gen (tools/gen_c64_assets.py) e cambia solo quello che il campo girato
disegna in un altro modo:

- charset.bin  il set del gioco; i caratteri 1-3 restano quelli di oggi (li usano la scelta dei
               bonus e la classifica): quelli del campo girato (ROT_GL_FIELD: il muro destro del
               campo, CH_LINE_R, colonna 30, pixel 0-1; il muro del singolo in alto, CH_WALL, riga 1,
               pixel 4-7) li mette draw_field, la mezzeria orizzontale (CH_LINE_L, riga 12, pixel
               3 e 4, cioè le righe 99 e 100) la rete (net_setup); today_glyphs rimette quelli di
               oggi (ROT_GL_TODAY)
- sprites.bin  gli sprite del gioco con le bande grigie EVO in orizzontale (4 righe, larghe 1-10)
- paddles.bin  le pose delle astronavi per la cartuccia (PAD_BANK): per tipo (0-6, poi 7 senza tipo:
               la barra bianca delle altre partite) e lato (0 in basso, faccia in alto; 1 in alto,
               capovolta) un blocco di 4 pagine da (tipo * 2 + lato) * $400. Ogni pagina è una posa:
               hires sinistro, hires destro, multicolore sinistro, multicolore destro. Pagina 0 la
               posa di sempre (TWIST dritta); TWIST pagine 1 e 2 inclinata di -TWIST_T e +TWIST_T;
               BLASTER pagine 1 e 2 i soli sprite multicolore dei livelli 0-1 e 2-3 del caricatore
               (il livello 4 è la posa di sempre). La pagina 3 resta vuota (in RAM è quella delle
               immagini rifatte), salvo nel GUARDIAN: la posa di sempre, da cui guard_page parte
               per i corsi persi, un corso per frame
- rotated.inc  costanti per l'assembly (ROT_*)

Le astronavi vengono da assets/ships/sprites/c64hires (PNG v2 dell'editor: 1 bianco, 2-4
multicolore, 5-7 bianco sopra 2-4, 16 e oltre agganci).
Uso: python tools/gen_c64_rotated.py
"""
import json
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "c64" / "gen"
OUT = GEN / "rotated"
SHIPS = ROOT / "assets" / "ships" / "sprites" / "c64hires"
NAMES = ("arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian")
K_TWIST, K_BLASTER, K_GUARDIAN, K_NONE = 3, 4, 6, 7
SPR_W, SPR_H = 48, 21
TWIST_T = 2          # inclinazione delle pose della TWIST (come la variante 2 di pad_image)
BAND_ROWS = 4        # banda EVO: spessa quanto la racchetta
NONE_LEN = 40        # barra delle altre partite (P_PAD_H)


def consts(path: Path) -> dict[str, int]:
    """Costanti NOME = valore (decimali o $esadecimali) di un file .inc."""
    out = {}
    for m in re.finditer(r"^([A-Z_][A-Z0-9_]*)\s*=\s*(\$[0-9A-Fa-f]+|\d+)", path.read_text(encoding="utf-8"), re.M):
        v = m.group(2)
        out[m.group(1)] = int(v[1:], 16) if v.startswith("$") else int(v)
    return out


def define(path: Path, name: str) -> list[int]:
    m = re.search(rf"^\.define {name} (.*)$", path.read_text(encoding="utf-8"), re.M)
    return [int(v.strip()[1:], 16) if v.strip().startswith("$") else int(v) for v in m.group(1).split(",")]


def ship(name: str) -> tuple[list[list[int]], list[list[int]], int, int, int]:
    """Racchetta in basso (faccia in alto) in una griglia 21x48: (hires, multicolore 0/2/3/4,
    sporgenza oltre la faccia, prima colonna, lunghezza). Riga r = colonna w-1-r del PNG, x = riga del PNG +
    scostamento pari (le coppie del multicolore restano allineate)."""
    im = Image.open(SHIPS / f"{name}.png")
    w, h = im.size
    meta = json.loads(im.info.get("paddedit", "{}"))
    assert meta.get("v") == 2, f"{name}: serve il PNG v2"
    nose = meta.get("front", 0)
    p = [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]
    drawn = [x for x in range(w) if any(0 < p[y][x] < 16 for y in range(h))]
    assert w - drawn[0] <= SPR_H, f"{name}: più di {SPR_H} colonne di profondità"
    assert h <= SPR_W and h % 2 == 0, f"{name}: lunghezza {h}"
    off = ((SPR_W - h) // 2) & ~1
    hi = [[0] * SPR_W for _ in range(SPR_H)]
    mc = [[0] * SPR_W for _ in range(SPR_H)]
    for r in range(w - drawn[0]):
        c = w - 1 - r
        for y in range(h):
            v = p[y][c]
            hi[r][off + y] = 1 if v in (1, 5, 6, 7) else 0
            mc[r][off + y] = v if 2 <= v <= 4 else v - 3 if 5 <= v <= 7 else 0
    return hi, mc, nose, off, h


def bar() -> tuple[list[list[int]], list[list[int]], int, int, int]:
    """La barra bianca delle partite senza tipo: 4 righe, NONE_LEN pixel."""
    off = (SPR_W - NONE_LEN) // 2
    hi = [[1 if r < 4 and off <= x < off + NONE_LEN else 0 for x in range(SPR_W)] for r in range(SPR_H)]
    mc = [[0] * SPR_W for _ in range(SPR_H)]
    return hi, mc, 0, off, NONE_LEN


def shear(g: list[list[int]], t: int, off: int, length: int) -> list[list[int]]:
    """TWIST inclinata: ogni coppia di colonne scende di ((coppia - metà) * t) >> 3 righe (le righe
    di pad_image, qui colonne)."""
    out = [[0] * SPR_W for _ in range(SPR_H)]
    n = length // 2
    for x in range(SPR_W):
        k = (x - off) // 2
        s = ((k - n // 2) * t) >> 3 if 0 <= x - off < length else 0
        for r in range(SPR_H):
            if g[r][x] and 0 <= r + s < SPR_H:
                out[r + s][x] = g[r][x]
    return out


def sprite_hi(g: list[list[int]], x0: int) -> bytes:
    out = bytearray(64)
    for r in range(SPR_H):
        for x in range(24):
            if g[r][x0 + x]:
                out[r * 3 + x // 8] |= 0x80 >> (x % 8)
    return bytes(out)


def sprite_mc(g: list[list[int]], x0: int) -> bytes:
    out = bytearray(64)
    # %01 grigio chiaro ($D025, COL_GRAY come oggi: anche la coda della palla), %10 colore del tipo,
    # %11 grigio scuro ($D026: in partita grigio scuro, fuori bianco come oggi; rot_video.s)
    bits = {2: 3, 3: 2, 4: 1}
    for r in range(SPR_H):
        for k in range(12):
            v = g[r][x0 + 2 * k] or g[r][x0 + 2 * k + 1]
            if v:
                out[r * 3 + k // 4] |= bits[v] << (6 - 2 * (k % 4))
    return bytes(out)


def pose(hi: list[list[int]], mc: list[list[int]]) -> bytes:
    return sprite_hi(hi, 0) + sprite_hi(hi, 24) + sprite_mc(mc, 0) + sprite_mc(mc, 24)


def flip(g: list[list[int]]) -> list[list[int]]:
    return g[::-1]


def magazine(mc: list[list[int]], level: int, levels: int, off: int, length: int) -> list[list[int]]:
    """BLASTER con il caricatore al livello `level` (0..levels): il colore del tipo (%10) diventa
    grigio scuro (%01) nelle colonne oltre la parte accesa, contata da sinistra (come pad_image
    dall'alto)."""
    lit = off + length * level // levels
    return [[2 if v == 3 and x >= lit else v for x, v in enumerate(row)] for row in mc]


# Salto del TELEPORT (warp_image di video.s, girato e fatto con i caratteri): l'astronave si
# scompone a colonne di due pixel dello schermo dove era, poi si ricompone dove arriva. La colonna
# k dello schermo ha la classe (k * 5) & 7, la classe c la soglia (c * 11) >> 2; con l'avanzamento
# a (0-32) una classe è piena, in luce o vuota. Sopra l'astronave (gli sprite dietro i caratteri)
# caratteri neri con accese le colonne in luce e vuote (la nascondono lì); dove una cella non ha
# colonne vuote, a scacchiera, caratteri nel colore del tipo con le colonne in luce a puntini.
# Una cella ha 4 colonne: con la colonna di celle C le classi (4 * (C & 1) + 5 * j) & 7.
WARP_LEVELS = 33
WARP_TH = [(c * 11) >> 2 for c in range(8)]


def warp_states(arrive: bool, a: int) -> tuple[int, ...]:
    """Per classe 0 vuota, 1 in luce, 2 piena: alla partenza piena finché a non arriva alla soglia,
    in luce per 8 passi, poi vuota; all'arrivo il contrario, con le soglie rovesciate."""
    if arrive:
        return tuple(0 if t < 22 - a else 1 if t < 30 - a else 2 for t in WARP_TH)
    return tuple(0 if t <= a - 8 else 1 if t <= a else 2 for t in WARP_TH)


def warp_tables() -> dict[str, list[int]]:
    """Per (arrivo * 33 + avanzamento): WB0/WB1 il byte del carattere nero delle colonne di celle
    pari e dispari (colonne in luce e vuote accese), WL0/WL1 quello delle colonne in luce (il
    carattere in accento, nelle righe dei puntini), WEL bit 0 e 1 le colonne di celle pari e dispari
    che possono essere in accento (nessuna colonna vuota, almeno una in luce)."""
    out = {k: [] for k in ("ROT_WB0", "ROT_WB1", "ROT_WL0", "ROT_WL1", "ROT_WEL")}
    for arrive in (False, True):
        for a in range(WARP_LEVELS):
            st = warp_states(arrive, a)
            el = 0
            for par in range(2):
                cls = [(4 * par + 5 * j) & 7 for j in range(4)]
                black = sum(3 << (6 - 2 * j) for j, c in enumerate(cls) if st[c] != 2)
                lit = sum(3 << (6 - 2 * j) for j, c in enumerate(cls) if st[c] == 1)
                out[f"ROT_WB{par}"].append(black)
                out[f"ROT_WL{par}"].append(lit)
                if lit and all(st[c] != 0 for c in cls):
                    el |= 1 << par
            out["ROT_WEL"].append(el)
    return out


def byte_table(src: str, label: str, n: int) -> list[int]:
    """I primi n byte della tabella `label: .byte ...` (anche su più righe) di un sorgente."""
    text = src[src.index(label + ":") + len(label) + 1:]
    out = []
    for line in text.splitlines():
        m = re.match(r"\s*\.byte\s+([^;]*)", line)
        if not m:
            break
        out += [int(v.strip()[1:], 16) if v.strip().startswith("$") else int(v) for v in m.group(1).split(",")]
        if len(out) >= n:
            break
    return out[:n]


def rot_glyph(left: list[int], right: list[int]) -> list[int]:
    """Un motivo della rete di oggi (8 righe lungo la mezzeria: left x 152-159, right x 160-167) nel
    carattere della mezzeria girata (vedi rot_nets)."""
    out = []
    for j in range(8):
        x = 163 - j
        b = 0
        for i in range(8):
            row = (left if x < 160 else right)[i]
            if row & (0x80 >> (x - (152 if x < 160 else 160))):
                b |= 0x80 >> i
        out.append(b)
    return out


def rot_nets_anim() -> tuple[list[int], list[int]]:
    """Le reti animate: TWIST (tw_l/tw_r, 3 varianti di 4 righe: dritta, a destra, a sinistra) e
    HAMMER (ham_l/ham_r, 3 spostamenti, uguali in tutte le righe), girate come rot_glyph."""
    src = (ROOT / "c64" / "src" / "video.s").read_text(encoding="utf-8")
    tl, tr = byte_table(src, "tw_l", 12), byte_table(src, "tw_r", 12)
    hl, hr = byte_table(src, "ham_l", 3), byte_table(src, "ham_r", 3)
    tw, ham = [], []
    for v in range(3):
        tw += rot_glyph(tl[4 * v:4 * v + 4] + [0] * 4, tr[4 * v:4 * v + 4] + [0] * 4)
        ham += rot_glyph([hl[v]] * 8, [hr[v]] * 8)
    return tw, ham


def rot_nets() -> list[int]:
    """Le reti di video.s (net_l: x 152-159, net_r: x 160-167, 8 righe lungo la mezzeria per tipo)
    nel carattere della mezzeria girata: la riga j del carattere è la riga 96 + j dello schermo,
    cioè la x di oggi 163 - j (y = 99 - (x - 160)); la colonna i è la riga i di oggi. Fuori da
    x 156-163 si perde (solo qualche mattone del GUARDIAN)."""
    src = (ROOT / "c64" / "src" / "video.s").read_text(encoding="utf-8")
    left, right = byte_table(src, "net_l", 64), byte_table(src, "net_r", 64)
    out = []
    for k in range(8):
        for j in range(8):
            x = 163 - j
            b = 0
            for i in range(8):
                row = (left if x < 160 else right)[k * 8 + i]
                if row & (0x80 >> (x - (152 if x < 160 else 160))):
                    b |= 0x80 >> i
            out.append(b)
    return out


def shot_cells() -> list[set[int]]:
    """Righe accese dei 7 caratteri di un fascio verticale (7 pixel dalla riga f della cella in
    alto): f = 0 una cella; f = 2, 4, 6 la cella in alto (righe f-7) e quella sotto (0..f-2)."""
    out = [set(range(0, 7))]
    for f in (2, 4, 6):
        out += [set(range(f, 8)), set(range(0, f - 1))]
    return out


def blaster_muzzles() -> tuple[int, int]:
    """Le due bocche dei cannoni del BLASTER girato: le coppie di colonne con il colore del tipo
    nella riga più avanti della posa in basso, dalla prima colonna della racchetta."""
    hi, mc, nose, off, _ = ship("blaster")
    row = next(r for r in range(SPR_H) if any(v == 3 for v in mc[r]))
    xs = [x for x in range(SPR_W) if mc[row][x] == 3]
    pairs = sorted({x & ~1 for x in xs})
    assert len(pairs) == 2, f"BLASTER: bocche dei cannoni nella riga {row}: {xs}"
    return pairs[0] - off, pairs[1] - off


def rings(a_inc: Path) -> list[int]:
    """Gli aloni di SLOW (FX_SQUARES di gen/assets.inc, come li disegna fx_copy con spin_plot:
    quadrati di pixel in sprite hires 24x21; $FF chiude un'immagine): 2 immagini da 64 byte."""
    sq = define(a_inc, "FX_SQUARES")
    out, img, i = [], bytearray(64), 0
    while len(out) < 128:
        if sq[i] == 255:
            out += list(img)
            img, i = bytearray(64), i + 1
            continue
        x0, y0, n = sq[i:i + 3]
        for dy in range(n):
            for dx in range(n):
                x, y = x0 + dx, y0 + dy
                if x < 24 and y < 21:
                    img[y * 3 + x // 8] |= 0x80 >> (x % 8)
        i += 3
    return out


def guardian_courses() -> tuple[list[int], list[int], int]:
    """GUARDIAN: i 5 corsi dello scudo tra le giunture (colonne con il colore del tipo nella prima
    riga della posa in basso), dal più a destra (il settore 0, in alto nel core). Per corso le
    maschere dei 6 byte di una riga (hires sinistro, destro) e delle coppie del multicolore, e le
    righe dello scudo (dall'alto)."""
    hi, mc, nose, off, h = ship("guardian")
    cols = [x for x in range(SPR_W) if mc[0][x] == 3]
    seams = []                      # (prima, ultima colonna) di ogni giuntura, larga una coppia
    for x in cols:
        if seams and x == seams[-1][1] + 1:
            seams[-1] = (seams[-1][0], x)
        else:
            seams.append((x, x))
    drawn = [x for x in range(SPR_W) if hi[0][x] or mc[0][x]]
    edges = [(drawn[0] - 1, drawn[0] - 1)] + seams + [(drawn[-1] + 1, drawn[-1] + 1)]
    assert len(edges) == 6, f"GUARDIAN: giunture {seams}"
    rows = max(r for r in range(SPR_H) if any(hi[r][x] for x in range(SPR_W))) + 1
    hi_m, mc_m = [], []
    for c in range(5):
        lo, up = edges[4 - c][1] + 1, edges[5 - c][0] - 1     # dal corso più a destra
        cols = set(range(lo, up + 1))
        hb, mb = bytearray(6), bytearray(6)
        for x in cols:
            hb[(x // 24) * 3 + (x % 24) // 8] |= 0x80 >> (x % 8)
            k = (x % 24) // 2
            mb[(x // 24) * 3 + k // 4] |= 3 << (6 - 2 * (k % 4))
        hi_m += list(hb)
        mc_m += list(mb)
    return hi_m, mc_m, rows


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    a = consts(GEN / "assets.inc")
    params = OUT / "params.inc"
    kind_h = [v >> 16 for v in define(params, "T_KIND_H")]
    lines = ["; Generato da tools/gen_c64_rotated.py: non modificare a mano.", ""]

    # caratteri
    cs = bytearray((GEN / "charset.bin").read_bytes())

    def glyph(code: int, rows: tuple[int, ...]) -> None:
        cs[8 * code:8 * code + 8] = bytes(rows)

    today = bytes(cs[8 * a["CH_LINE_L"]:8 * a["CH_LINE_L"] + 24])
    assert a["CH_LINE_R"] == a["CH_LINE_L"] + 1 and a["CH_WALL"] == a["CH_LINE_L"] + 2
    field = bytes((0xC0,) * 8 + (0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF))  # muro destro, x 240-241; muro del singolo, righe 12-15
    lines += [
        "; caratteri 1-3: quelli di oggi (fuori dalla partita) e CH_LINE_R e CH_WALL del campo girato",
        ".define ROT_GL_TODAY " + ", ".join(f"${v:02X}" for v in today),
        ".define ROT_GL_FIELD " + ", ".join(f"${v:02X}" for v in field),
        "",
    ]
    # muro del GUARDIAN (x 5 del core): in basso righe 194-195 (riga 24), in alto 4-5 (riga 0)
    glyph(a["CH_BAR_R"], (0, 0, 0xFF, 0xFF, 0, 0, 0, 0))
    glyph(a["CH_BAR_L"], (0, 0, 0, 0, 0xFF, 0xFF, 0, 0))
    # segni di STEER: tratti di 6 pixel dal bordo sinistro (R) e destro (L) del campo, righe 1-2 (riga
    # di caratteri 6: le righe 49-50) e 5-6 (riga 18: 149-150)
    glyph(a["CH_STEER_TOP_R"], (0, 0xFC, 0xFC, 0, 0, 0, 0, 0))
    glyph(a["CH_STEER_TOP_L"], (0, 0x3F, 0x3F, 0, 0, 0, 0, 0))
    glyph(a["CH_STEER_BOTTOM_R"], (0, 0, 0, 0, 0, 0xFC, 0xFC, 0))
    glyph(a["CH_STEER_BOTTOM_L"], (0, 0, 0, 0, 0, 0x3F, 0x3F, 0))
    # fasci del BLASTER, verticali: tratto largo 2 pixel e alto 7 dalla riga f (0, 2, 4, 6) della
    # cella; nei caratteri del set (SHOT_OWN) la posizione 3 (pixel 6-7), le altre tre le fa
    # shot_glyphs spostando i bit. Per posizione 7 caratteri: alto con f = 0, poi alto e basso con
    # f = 2, 4, 6 (lo schema di SHOT_CHARS)
    for i, rows in enumerate(shot_cells()):
        glyph(a["SHOT_OWN"] + i, tuple(0x03 if r in rows else 0 for r in range(8)))
    (OUT / "charset.bin").write_bytes(bytes(cs))
    muzzles = blaster_muzzles()
    lines += [
        "; campo girato: mezzeria nella riga 12, muro destro nella colonna 30, muro del singolo nella riga 1",
        "ROT_LINE_ROW = 12",
        "ROT_WALL_COL = 30",
        "ROT_SINGLE_ROW = 1",
        "ROT_FIELD_COLS = 30",
        "ROT_HUD_COL = 31               ; fascia dell'HUD: prima colonna",
        "; reti degli avversari nel carattere della mezzeria (il motivo di net_l/net_r girato, x = 156-163)",
        ".define ROT_NET " + ", ".join(f"${b:02X}" for b in rot_nets()),
        "; reti animate: TWIST (dritta, a destra, a sinistra) e HAMMER (3 spostamenti), 8 byte l'una",
        ".define ROT_NET_TW " + ", ".join(f"${b:02X}" for b in rot_nets_anim()[0]),
        ".define ROT_NET_HAM " + ", ".join(f"${b:02X}" for b in rot_nets_anim()[1]),
        "; BLASTER: colonna delle bocche dei cannoni dalla prima colonna della racchetta (la prima,",
        "; pari) e distanza della seconda; metà lunghezza della racchetta",
        f"ROT_SHOT_A = {muzzles[0]}",
        f"ROT_SHOT_D = {muzzles[1] - muzzles[0]}",
        f"ROT_BL_HALF = {kind_h[K_BLASTER] // 2}",
        "; GUARDIAN: per corso dello scudo (0 il più a destra, il settore in alto nel core), per i 6 byte",
        "; di una riga: il bianco da tenere (HIK), le coppie da tenere (MCK) e le coppie %01 (LO); righe",
        "; dello scudo",
        ".define ROT_G_HIK " + ", ".join(f"${~b & 0xFF:02X}" for b in guardian_courses()[0]),
        ".define ROT_G_MCK " + ", ".join(f"${~b & 0xFF:02X}" for b in guardian_courses()[1]),
        ".define ROT_G_LO " + ", ".join(f"${b & 0x55:02X}" for b in guardian_courses()[1]),
        f"ROT_G_ROWS = {guardian_courses()[2]}",
        "; aloni di SLOW già disegnati (al posto di fx_copy con spin_plot): 2 sprite da 64 byte",
        ".define ROT_RINGS " + ", ".join(f"${b:02X}" for b in rings(GEN / "assets.inc")),
        "",
    ]

    # sprite: le bande EVO in orizzontale al posto di quelle verticali
    spr = bytearray((GEN / "sprites.bin").read_bytes())
    band1 = 6
    for i in range(a["SPRITE_BANDS"]):
        img = bytearray(64)
        w = i + 1
        for r in range(BAND_ROWS):
            for x in range(w):
                img[r * 3 + x // 8] |= 0x80 >> (x % 8)
        spr[64 * (band1 + i):64 * (band1 + i + 1)] = img
    # la barra bianca delle partite senza tipo nei due posti delle immagini dinamiche (SP_PAD0 i
    # primi 24 pixel, SP_PAD1 gli altri 16), righe 0-3
    hi, _, _, off, _ = bar()
    spr[64 * 2:64 * 4] = sprite_hi(hi, off) + sprite_hi([row[24:] + [0] * 24 for row in hi], off)
    (OUT / "sprites.bin").write_bytes(bytes(spr))

    # pose delle astronavi
    block = bytearray(8 * 2 * 0x400)
    nose, off_x = [], []
    blaster_levels = 4             # BLASTER_VIS di video.s: livelli 0-4, il 4 è la posa di sempre
    for k in range(8):
        hi, mc, n, off, length = ship(NAMES[k]) if k < 7 else bar()
        if k == K_TWIST:
            # le inclinazioni alzano le colonne fino a drop righe: tutte le pose drop righe più in
            # giù, e la faccia con loro (ROT_NOSE), così niente esce dallo sprite
            pairs = length // 2
            drop = -min(((c - pairs // 2) * t) >> 3 for c in range(pairs) for t in (-TWIST_T, TWIST_T))
            assert not any(any(r) for r in hi[SPR_H - drop:] + mc[SPR_H - drop:]), "TWIST: niente posto per l'inclinazione"
            hi = [[0] * SPR_W for _ in range(drop)] + hi[:SPR_H - drop]
            mc = [[0] * SPR_W for _ in range(drop)] + mc[:SPR_H - drop]
            n += drop
        # la racchetta del core lunga quanto l'astronave (T_KIND_H; senza tipo P_PAD_H)
        assert length == (kind_h[k] if k < 7 else consts(params)["P_PAD_H"] >> 16), (k, length)
        nose.append(n)
        off_x.append(off)
        for side in range(2):
            f = flip if side else (lambda g: g)
            base = (k * 2 + side) * 0x400
            block[base:base + 0x100] = pose(f(hi), f(mc))
            if k == K_TWIST:
                for i, t in enumerate((-TWIST_T, TWIST_T)):
                    block[base + 0x100 * (i + 1):base + 0x100 * (i + 2)] = pose(f(shear(hi, t, off, length)), f(shear(mc, t, off, length)))
            if k == K_GUARDIAN:
                block[base + 0x300:base + 0x400] = block[base:base + 0x100]
            if k == K_BLASTER:
                for lv in range(blaster_levels):
                    m = f(magazine(mc, lv, blaster_levels, off, length))
                    at = base + 0x100 + 0x80 * lv
                    block[at:at + 0x80] = sprite_mc(m, 0) + sprite_mc(m, 24)
    (OUT / "paddles.bin").write_bytes(bytes(block))
    # anteprime della scelta: di quante righe il disegno della posa in alto comincia più in giù
    # di quello della posa in basso (le due astronavi alla stessa altezza)
    def first_row(base: int) -> int:
        return min(r for r in range(SPR_H) if any(block[base + p * 64 + r * 3 + c] for p in range(4) for c in range(3)))
    pick_dy = [first_row((k * 2 + 1) * 0x400) - first_row(k * 2 * 0x400) for k in range(8)]
    lines += [
        "; pose delle astronavi (paddles.bin): per tipo e lato 4 pagine; nella posa lo sprite sinistro",
        "; comincia ROT_OFF pixel prima della prima colonna della racchetta. Faccia: riga ROT_NOSE",
        "; dell'immagine in basso, 20 - ROT_NOSE in quella in alto",
        ".define ROT_OFF " + ", ".join(map(str, off_x)),
        ".define ROT_NOSE " + ", ".join(map(str, nose)),
        f"ROT_TWIST_T = {TWIST_T}",
        "; scelta: la posa in basso ROT_PICK_DY righe più in giù, all'altezza di quella in alto",
        ".define ROT_PICK_DY " + ", ".join(map(str, pick_dy)),
        "; salto del TELEPORT a caratteri (warp_tables): per arrivo * 33 + avanzamento",
        *[f".define {k} " + ", ".join(f"${v:02X}" for v in vals) for k, vals in warp_tables().items()],
        f"ROT_BAND_ROWS = {BAND_ROWS}",
        "",
    ]
    (OUT / "rotated.inc").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"c64/gen/rotated: caratteri, sprite, {len(block) // 256} pagine di pose")


if __name__ == "__main__":
    main()
