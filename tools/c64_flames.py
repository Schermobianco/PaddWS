"""Fiamme dei motori delle astronavi del C64 (racchette di NEXT).

Lo sprite di ogni astronave (assets/ships/sprites/c64/<tipo>.png) porta gli agganci motore (indice
16, come sul PC): pixel nello spazio vuoto dietro l'ugello, non disegnati in gioco. La colonna di un
aggancio è la prima colonna della fiamma (la più vicina all'ugello), le sue righe sono quelle del
getto; la fiamma si allunga verso sinistra (verso il retro della racchetta sinistra).

Qui si disegnano le pose della fiamma sull'immagine dello sprite (liste di righe di indici 0-3:
%01 grigio, %10 colore del tipo, %11 bianco), le stesse per il generatore delle immagini
(tools/gen_c64_assets.py) e per le bozze. Pose:

  0 fermo A    1 fermo B    2 in movimento A    3 in movimento B    4 lampo (scatto in corso)

Più semplici del PC (rust/game/src/paddle_ui.rs): niente scia tratteggiata dello scatto, niente
scintille staccate, niente scie alari del RUSH né getti RCS della TWIST.
"""

ENGINE = 16
GRAY, MARK, WHITE = 1, 2, 3
POSES = ("fermo A", "fermo B", "moto A", "moto B", "lampo")
STATIC_POSE = 1                 # TWIST e BLASTER non hanno posti per le pose: fiamma fissa
# motori attesi per tipo (ARCADE, TITAN, HAMMER, TWIST, BLASTER, RUSH, GUARDIAN): gruppi di aggancio
ENGINES = (2, 2, 1, 1, 2, 1, 2)
# lunghezza massima della fiamma in colonne doppie (lo scatto la raggiunge, se c'è posto)
MAX_LEN = 6
# lunghezza della fiamma per posa (colonne dall'aggancio, ugello compreso)
LENGTH = (2, 3, 3, 4, MAX_LEN)


def anchors(px: list[list[int]]) -> tuple[list[list[int]], list[tuple[int, int, int]]]:
    """(sprite senza agganci, gruppi (colonna, prima riga, righe) in colonna)."""
    h = len(px)
    w = len(px[0]) if h else 0
    clean = [[0 if c == ENGINE else c for c in row] for row in px]
    groups = []
    for x in range(w):
        y = 0
        while y < h:
            if px[y][x] == ENGINE:
                y0 = y
                while y < h and px[y][x] == ENGINE:
                    y += 1
                groups.append((x, y0, y - y0))
            else:
                y += 1
    return clean, groups


def check(name: str, clean: list[list[int]], groups: list[tuple[int, int, int]], want: int) -> None:
    """Un aggancio sta su un pixel trasparente, con vuoto da lì a sinistra nelle sue righe e lo
    scafo (o uno spazio, di una sola colonna al più) subito a destra."""
    assert len(groups) == want, f"{name}.png: {len(groups)} agganci motore, ne servono {want}"
    for x, y0, rows in groups:
        for y in range(y0, y0 + rows):
            assert not any(clean[y][: x + 1]), f"{name}.png: l'aggancio ({x}, {y}) non ha vuoto a sinistra"
            hull = next((i for i in range(x + 1, len(clean[y])) if clean[y][i]), None)
            assert hull is not None and hull - x <= 2, f"{name}.png: l'aggancio ({x}, {y}) è lontano dallo scafo"


def pose_rows(clean: list[list[int]], groups: list[tuple[int, int, int]], pose: int) -> list[list[int]]:
    """Lo sprite con la fiamma della posa `pose` (0-4)."""
    out = [row[:] for row in clean]
    w = len(clean[0])

    def put(x: int, y: int, c: int) -> None:
        if 0 <= x < w and 0 <= y < len(out) and not clean[y][x] and not any(clean[y][:x]):
            out[y][x] = c

    for x, y0, rows in groups:
        length = min(LENGTH[pose], x + 1)
        core = range(y0, y0 + rows)
        # tra l'aggancio e lo scafo, se c'è uno spazio
        for y in core:
            hull = next(i for i in range(x + 1, w) if clean[y][i])
            for gx in range(x + 1, hull):
                put(gx, y, WHITE)
        tip_row = y0 + (rows - 1 if pose % 2 else 0)
        for j in range(length):
            cx = x - j
            for y in core:
                if pose == 4:
                    c = WHITE
                else:
                    c = WHITE if j < (length + 1) // 2 else MARK
                if j == length - 1 and length >= 3 and y == tip_row:
                    c = GRAY
                put(cx, y, c)
        # contorno sopra e sotto: ugello e una colonna in più, in luce nel lampo
        halo = 3 if pose == 4 else (2 if length >= 3 else 1)
        for j in range(min(halo, length)):
            c = WHITE if pose == 4 and j < 2 else MARK
            put(x - j, y0 - 1, c)
            put(x - j, y0 + rows, c)
    return out


# ------------------------------------------------------------------------- immagini della partita
# Le immagini delle racchette in partita NEXT (le "pose") vengono dalla cartuccia, due pagine per
# lato (8 posti da 64 byte), non da pad_image: lo scafo come disegnato (la TWIST spostata a sinistra
# di TILT_MAX colonne, per l'inclinazione), la fiamma nello spazio vuoto dietro. Posto k del blocco:
# i tipi a immagine sola hanno la posa k (0-4), TWIST l'inclinazione k - 3, BLASTER il livello del
# caricatore k (le due hanno la fiamma fissa, STATIC_POSE).
PAD_W = 12
PAD_ROWS = 21
K_TWIST, K_BLASTER = 3, 4
TILT_MAX = 2                    # colonne di spostamento massimo dell'inclinazione della TWIST
BLOCK_SLOTS = 8


def tilt_shift(row: int, n: int, t: int) -> int:
    """Colonne di cui l'inclinazione t (-3..3) sposta la riga `row` di un'immagine alta n righe,
    verso il davanti se positive: come pad_image (TWIST) ma al più TILT_MAX, simmetrico."""
    d = row - (n >> 1)
    s = int(2 * abs(d) * abs(t) / 24 + 0.5)
    return s if (d >= 0) == (t >= 0) else -s


def pack(rows: list[list[int]]) -> bytes:
    """Un'immagine di 64 byte: 3 byte per riga (PAD_ROWS righe, le altre vuote), la coppia di bit più
    a sinistra nei bit alti."""
    out = bytearray()
    for y in range(PAD_ROWS):
        row = rows[y] if y < len(rows) else [0] * PAD_W
        for b in range(3):
            out.append((row[4 * b] << 6) | (row[4 * b + 1] << 4) | (row[4 * b + 2] << 2) | row[4 * b + 3])
    return bytes(out).ljust(64, b"\0")


def kind_block(kind: int, clean: list[list[int]], groups: list[tuple[int, int, int]], front: int,
               thr: list[int]) -> tuple[bytes, bytes, int]:
    """(blocco della racchetta sinistra, blocco della destra, colonna della faccia nell'immagine)
    per il tipo `kind`: BLOCK_SLOTS immagini da 64 byte ciascuno."""
    n = len(clean)
    base = TILT_MAX if kind == K_TWIST else 0
    hull = [row[base:] + [0] * base for row in clean]
    grp = [(x - base, y0, r) for x, y0, r in groups]
    face = PAD_W - 1 - front - base
    images: list[list[list[int]]] = []
    for slot in range(BLOCK_SLOTS):
        if kind == K_TWIST:
            if slot >= 7:
                break
            rows = pose_rows(hull, grp, STATIC_POSE)
            t = slot - 3
            moved = []
            for y, row in enumerate(rows):
                s = tilt_shift(y, n, t)
                new = [0] * PAD_W
                for x, c in enumerate(row):
                    if c:
                        assert 0 <= x + s < PAD_W, f"TWIST: riga {y} fuori dall'immagine con l'inclinazione {t}"
                        new[x + s] = c
                moved.append(new)
            images.append(moved)
        elif kind == K_BLASTER:
            if slot >= len(thr):
                break
            low = [[1 if (c == MARK and y < thr[slot]) else c for c in row] for y, row in enumerate(hull)]
            images.append(pose_rows(low, grp, STATIC_POSE))
        else:
            if slot >= len(POSES):
                break
            images.append(pose_rows(hull, grp, slot))
    left = b"".join(pack(img) for img in images).ljust(BLOCK_SLOTS * 64, b"\0")
    right = b"".join(pack([row[::-1] for row in img]) for img in images).ljust(BLOCK_SLOTS * 64, b"\0")
    return left, right, face
