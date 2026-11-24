"""Grafica della versione C64: set di caratteri, sprite e tabelle per c64/src.

Le scritte usano il font della ROM dei caratteri della macchina (set maiuscolo, $D000): i suoi
glifi non stanno in nessun file generato. Nel set di caratteri al loro posto ci sono dei
segnaposto vuoti, e assets.inc dice al programma dove vanno: all'avvio (video_init) il programma
li legge dalla ROM e li copia nel suo set, 1x (un carattere per lettera, FONT_ROM) e 2x (quattro
caratteri per lettera, ogni pixel 2x2: BIG2_SRC, fatti dai glifi 1x già nel set).

Uscite in c64/gen/ (vanno nel repository, così l'assemblaggio non richiede Python):
  charset.bin   256 caratteri 8x8 (2 KB): vuoto, mezzeria, muro del singolo, cifre del punteggio
                (celle di 3x3 caratteri), segnaposto del font 1x e delle lettere 2x
  pick_bank.bin il banco PICK_BANK della cartuccia (tools/make_crt.py): 2 KB vuoti (lì c'era il
                set della scelta dei bonus, che ora il programma si fa da solo), poi la pagina
                $FF00, che l'avvio copia sotto il KERNAL: a $FF40 i caratteri della capsula del
                BULLET e quelli che sostituisce (bullet_chars), a $FFC0 l'RTS di VOICE_COUNT, a
                $FFC3 gli originali (vuoti) dei caratteri della barra delle mosse speciali; poi
                title.bin (8 pagine), che l'avvio copia sotto l'I/O
  sprites.bin   sprite (64 byte ciascuno): palla normale (4x4) e con il boost (6x6), posti delle
                racchette, linee del raster dell'attract, bande grigie EVO di 1-10 righe
  title.bin     del titolo dell'attract in bitmap hires solo le righe di caratteri che l'attract
                copia (logo con WS, il simbolo del copyright): due blocchi di righe intere, 320
                byte ciascuna; le scritte le disegna il programma con i glifi del set
  (in assets.inc anche gli effetti della palla di NEXT come elenco di quadrati: il programma li
  disegna a inizio partita a $E000; e per le mosse speciali i caratteri della barra, le icone
  della mossa armata e le tracce degli effetti MOVE e SPECIAL dalla ROM della musica del MiSTer)
  assets.inc    codici dei caratteri, tabelle dei glifi della ROM, posizioni e tempi dell'attract,
                scritte della HOW TO PLAY per l'assembler
  voiceN.bin    campioni del nome dell'avversario di CHALLENGE per il tipo di racchetta N (ordine
                di `PaddleKind`), dai .raw4 di assets/sounds/voice (tools/gen_voices.py): src/voice.s
                li mette con il player nei file voce della cartuccia; voice7.bin è il nome di
                OMEGA (omega.raw4, senza parte della coda quasi muta: OMEGA_VOICE_MAX)
  ready.bin, go.bin  "READY?" e "GO!" del conto alla rovescia di CHALLENGE, dagli stessi .raw4: nel
                file voce dell'avversario del primo livello
  you_win.bin   "YOU WIN!": il banco della vittoria della cartuccia (tools/make_crt.py), per il
                GAME OVER contro la CPU e il finale di CHALLENGE
  perfect.bin   "PERFECT!": nello stesso banco, per il GAME OVER vinto da un giocatore con
                l'avversario a 0 punti
  ending_chars.bin, ending.inc  set di caratteri del finale di CHALLENGE (src/ending.s): i
                segnaposto del font ai suoi codici e delle lettere 2x, il timbro DEFEATED e i
                punti multicolore dei fuochi d'artificio
  howto.bin     la schermata HOW TO PLAY delle mosse speciali in bitmap hires (banchi HOWTO_BANK
                della cartuccia, tools/make_crt.py): 31 pagine di bitmap ($E000-$FEFF) e una
                vuota, poi i colori (1.000 byte, 4 pagine) e gli stessi con giallo e rosso
                scambiati per l'easter egg; disegnata con le figure di tools/gen_howto_assets.py,
                con le celle delle scritte vuote (le scrive il programma, HT_TEXTS: i loro
                testi stanno nella riga 1 della bitmap, vuota e nera)
  titles.bin    i titoli disegnati (assets/titles) in caratteri: una pagina per nome degli avversari,
                una per PERFECT, due per la targa di HERE COMES A NEW CHALLENGER! (con lo sprite
                del rosso); nel file del finale della cartuccia, mappe e colori in assets.inc

Le cifre del punteggio vengono da assets/fonts/pong-score.ttf a 22 px come sul MiSTer. Delle
bitmap dell'attract (assets/attract) servono solo la grafica (logo e WS) e i tempi.

Uso:  .venv\\Scripts\\python tools\\gen_c64_assets.py   (richiede Pillow)
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import gen_howto_assets as howto
from gen_next_assets import ICONS
from gen_voices import NAMES as VOICE_NAMES

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "c64" / "gen"
FONTS = ROOT / "assets" / "fonts"
ATTRACT = ROOT / "assets" / "attract"
VOICES = ROOT / "assets" / "sounds" / "voice"

# caratteri del font monospazio (codici ASCII 32-95, come la tabella in assets.inc)
FONT_CHARS = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
FONT_DRAWN = "!+-./0123456789:=>?ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# scelta dei bonus: caratteri sostituiti dalle metà delle lettere (pagine intere). Sono le stesse
# pagine delle lettere 2x, che nella scelta non si vedono
PICK_FIRST = 64
PICK_PAGES = 3

# scritte a 2x del programma (fuori dal finale, che ha il suo set): solo le grandi del GAME OVER
# (PERFECT è una grafica: title_perfect). Le loro lettere hanno quattro caratteri ciascuna da
# PICK_FIRST; tutto il resto è a 1x
BIG2_TEXTS = ["GAME OVER", "YOU WIN"]
# le scritte del GAME OVER come elenchi di codici su due righe (nome per assets.inc: testo, 2x);
# quelle a 1x hanno la riga sotto vuota
BIG2_LISTS = {"GAME_OVER": ("GAME OVER", True), "P1_WINS": ("P1 WINS", False), "P2_WINS": ("P2 WINS", False),
              "YOU_WIN": ("YOU WIN", True), "CPU_WINS": ("CPU WINS", False)}
BLANK: tuple[int, ...] = (0,) * 8   # segnaposto di un glifo della ROM

Tile = tuple[int, ...]   # 8 byte, bit 7 = pixel a sinistra


def rom_code(ch: str) -> int:
    """Codice del carattere ASCII `ch` (32-95) nel set maiuscolo della ROM dei caratteri: le
    lettere da 1 (A), la punteggiatura e le cifre al loro codice ASCII."""
    o = ord(ch)
    assert 32 <= o < 96, ch
    return o - 64 if o >= 64 else o


class Charset:
    def __init__(self) -> None:
        self.tiles: list[Tile] = []
        self.index: dict[Tile, int] = {}
        self.given: list[int] = []      # codici dati da add, in ordine (chi usa quale carattere)

    def add(self, tile: Tile, unique: bool = False) -> int:
        """Codice del carattere (riusa quelli uguali, salvo `unique`)."""
        if not unique and tile in self.index:
            self.given.append(self.index[tile])
            return self.index[tile]
        code = len(self.tiles)
        assert code < 256, "set di caratteri pieno"
        self.tiles.append(tile)
        self.index.setdefault(tile, code)
        self.given.append(code)
        return code


def tiles_of(pixels: list[list[bool]], w_chars: int, h_chars: int) -> list[list[Tile]]:
    """Immagine (righe di pixel) -> righe di caratteri 8x8."""
    rows = []
    for cy in range(h_chars):
        row = []
        for cx in range(w_chars):
            tile = []
            for y in range(8):
                byte = 0
                for x in range(8):
                    py, px = cy * 8 + y, cx * 8 + x
                    if py < len(pixels) and px < len(pixels[py]) and pixels[py][px]:
                        byte |= 0x80 >> x
                tile.append(byte)
            row.append(tuple(tile))
        rows.append(row)
    return rows


def render(font: ImageFont.FreeTypeFont, text: str, size: tuple[int, int], offset: tuple[int, int]) -> list[list[bool]]:
    im = Image.new("L", size, 0)
    ImageDraw.Draw(im).text(offset, text, font=font, fill=255)
    return [[im.getpixel((x, y)) > 127 for x in range(size[0])] for y in range(size[1])]


def ink_rows(font: ImageFont.FreeTypeFont, chars: str, height: int) -> tuple[int, int]:
    """Prima e ultima riga con l'inchiostro di tutti i caratteri disegnati a (0, 0)."""
    rows: set[int] = set()
    for c in chars:
        px = render(font, c, (32, height), (0, 0))
        rows |= {y for y in range(height) if any(px[y])}
    return min(rows), max(rows)


def score_digits(cs: Charset) -> list[list[int]]:
    """Cifre del punteggio a 22 px in celle di 24x24 (3x3 caratteri), come sul MiSTer."""
    font = ImageFont.truetype(str(FONTS / "pong-score.ttf"), 22)
    top, bottom = ink_rows(font, "0123456789", 40)
    assert bottom - top + 1 <= 24
    out = []
    for d in "0123456789":
        px = render(font, d, (24, 40), (1, 1 - top))
        rows = tiles_of(px[:24], 3, 3)
        out.append([cs.add(t) for row in rows for t in row])
    return out


def text_font(cs: Charset) -> list[int]:
    """Font 1x della ROM dei caratteri: un carattere per lettera di FONT_DRAWN, contigui, con un
    segnaposto vuoto (il glifo lo copia il programma dalla ROM, FONT_ROM). Codici per ASCII 32-95
    (0 = vuoto)."""
    codes = {c: cs.add(BLANK, unique=True) for c in FONT_DRAWN}
    return [codes.get(c, 0) for c in FONT_CHARS]


def big2_letters() -> str:
    """Lettere delle scritte a 2x (BIG2_TEXTS), in ordine alfabetico."""
    letters = "".join(sorted(set("".join(BIG2_TEXTS)) - {" "}))
    assert all(c in FONT_DRAWN for c in letters), letters
    return letters


def big2_codes(first: int, letters: str, text: str) -> list[int]:
    """Codici di `text` a 2x (lettere di quattro caratteri da `first`, nell'ordine di `letters`):
    la riga alta (alto sinistra, alto destra per lettera), poi la bassa; lo spazio è vuoto."""
    top, bottom = [], []
    for ch in text:
        if ch == " ":
            top += [0, 0]
            bottom += [0, 0]
            continue
        c = first + 4 * letters.index(ch)
        top += [c, c + 1]
        bottom += [c + 2, c + 3]
    return top + bottom


SPRITE_BANDS = 10  # altezze della banda grigia EVO (la più alta: area di 8 pixel, 9 righe)
CAP = 12           # lato della capsula disegnata, come sul MiSTer (la capsula del C64 è di 10 pixel)
BONUSES = len(ICONS)
B_SUPER = 5
B_BULLET = 7       # solo dalle capsule, mai armato: niente icona del bonus armato
assert BONUSES == B_BULLET + 1


def icon_lit(b: int, dx: int, dy: int) -> bool:
    return 0 <= dx < 9 and 0 <= dy < 9 and ICONS[b][dy][dx] == "#"


def capsule(b: int, inv: bool) -> list[list[bool]]:
    """Capsula CAP x CAP come cap_px del MiSTer: bordo e icona, oppure piena con l'icona vuota."""
    o = (CAP - 9) // 2
    rows = []
    for dy in range(CAP):
        row = []
        for dx in range(CAP):
            border = dx in (0, CAP - 1) or dy in (0, CAP - 1)
            ic = icon_lit(b, dx - o, dy - o)
            row.append(not ic if inv else border or ic)
        rows.append(row)
    return rows


def sprite_of(pixels: list[list[bool]]) -> bytes:
    """Sprite hires con l'immagine in alto a sinistra."""
    data = bytearray(64)
    for y, row in enumerate(pixels):
        for x, on in enumerate(row):
            if on:
                data[3 * y + x // 8] |= 0x80 >> (x % 8)
    return bytes(data)


def cap_tiles(b: int) -> list[Tile]:
    """Capsula b della riserva in 2x2 caratteri, normale e in negativo (8 caratteri)."""
    out = []
    for inv in (False, True):
        px = [[False] * 16 for _ in range(16)]
        for y, row in enumerate(capsule(b, inv)):
            for x, on in enumerate(row):
                px[2 + y][2 + x] = on
        out += [t for row in tiles_of(px, 2, 2) for t in row]
    return out


def next_chars(cs: Charset, lines: list[str], spare: list[int]) -> bytes:
    """NEXT: capsule della riserva e della scelta in 2x2 caratteri (la capsula a 2 pixel dal bordo,
    passo di 16 pixel come sul MiSTer), normali e in negativo, posto vuoto a puntini e freccetta del
    selezionato sotto la capsula.

    Il set di caratteri è pieno: le 8 della capsula del BULLET (che c'è solo in partita, nella
    riserva) prendono in NEXT il posto dei caratteri `spare`, che in NEXT non servono; il programma
    li scambia a inizio partita (bullet_chars in video.s, con i caratteri originali per le altre).
    Restituisce i 128 byte da $FF40: i caratteri della capsula, poi quelli originali."""
    codes = []
    for b in range(BONUSES):
        if b != B_BULLET:
            codes += [cs.add(t) for t in cap_tiles(b)]
    bullet = cap_tiles(B_BULLET)
    assert len(spare) == len(bullet) and len(set(bullet)) == len(bullet)
    assert not any(t in cs.index for t in bullet), "capsula del BULLET già nel set"
    codes += spare
    lines.append("; NEXT: capsule 2x2 (alto sinistra, alto destra, basso sinistra, basso destra), per bonus")
    lines.append("; normale e in negativo: indice = bonus * 8 + negativo * 4")
    lines.append(".define CAP_CHARS " + ", ".join(str(c) for c in codes))
    lines.append("; BULLET: le sue capsule della riserva al posto dei caratteri BULLET_C0-7 (bullet_chars),")
    lines.append("; con quelli originali per le partite che non sono NEXT")
    for i, c in enumerate(spare):
        lines.append(f"BULLET_C{i} = {c}")
    bullet_bytes = bytes(v for t in bullet for v in t) + bytes(v for c in spare for v in cs.tiles[c])
    # posto vuoto: bordo a puntini (pixel accesi a scacchiera, come x[0] == y[0] sul MiSTer)
    px = [[False] * 16 for _ in range(16)]
    for dy in range(CAP):
        for dx in range(CAP):
            if (dx in (0, CAP - 1) or dy in (0, CAP - 1)) and (dx + dy) % 2 == 0:
                px[2 + dy][2 + dx] = True
    empty = [cs.add(t) for row in tiles_of(px, 2, 2) for t in row]
    lines.append(".define CAP_EMPTY " + ", ".join(str(c) for c in empty))
    # freccetta: 2 pixel sotto la capsula, larga 5, 3 e 1 pixel attorno al centro della capsula
    px = [[False] * 16 for _ in range(8)]
    center = 2 + CAP // 2
    for r, half in enumerate((2, 1, 0)):
        for x in range(center - half, center + half + 1):
            px[r][x] = True
    arrow = [cs.add(t) for t in tiles_of(px, 2, 1)[0]]
    lines.append(f"CH_ARROW_L = {arrow[0]}")
    lines.append(f"CH_ARROW_R = {arrow[1]}")
    # muro del GUARDIAN: due pixel a cavallo di due colonne (x 7-8 e 311-312), tratti di 5 righe
    # ogni 8 come sul MiSTer, ma tutti dentro il carattere (righe 1-5): il colore e la presenza
    # vanno per riga di caratteri (settori del muro), così nessun tratto resta a metà
    dash = [1 if 1 <= y <= 5 else 0 for y in range(8)]
    lines.append(f"CH_BAR_R = {cs.add(tuple(0x01 * d for d in dash), unique=True)}    ; pixel 7 della colonna")
    lines.append(f"CH_BAR_L = {cs.add(tuple(0x80 * d for d in dash), unique=True)}    ; pixel 0 della colonna")
    # fascio laser del BLASTER (uno per cannone alare): tratto di 7x2 pixel dal pixel p (0, 2, 4, 6)
    # del primo carattere, il resto nel secondo. Questi sette hanno il tratto all'altezza SHOT_H0
    # (righe 6-7); le altre tre altezze sono caratteri presi in prestito in NEXT (shot_assets)
    shot = []
    for p in (0, 2, 4, 6):
        bits = sum(0x80 >> x for x in range(p, p + 7) if x < 8), sum(0x80 >> (x - 8) for x in range(p, p + 7) if x >= 8)
        for half in bits:
            shot.append(cs.add(tuple(half if y >> 1 == SHOT_H0 else 0 for y in range(8)), unique=True) if half else 0)
    # STEER: segni dove finisce la guida, 2 pixel a cavallo di due colonne, alti 6 righe in cima e
    # in fondo allo schermo
    top = [1 if y < 6 else 0 for y in range(8)]
    bottom = [1 if y >= 2 else 0 for y in range(8)]
    for name, rows in (("TOP", top), ("BOTTOM", bottom)):
        lines.append(f"CH_STEER_{name}_R = {cs.add(tuple(0x01 * r for r in rows), unique=True)}")
        lines.append(f"CH_STEER_{name}_L = {cs.add(tuple(0x80 * r for r in rows), unique=True)}")
    lines.append("")
    return bullet_bytes, shot


# fasci laser del BLASTER (pick.s, next_shots): il tratto alto 2 pixel sta a una di quattro altezze
# nella cella (righe 0-1, 2-3, 4-5, 6-7), così ogni fascio esce dalla bocca del suo cannone entro un
# pixel. Sette caratteri per altezza: quelli del set (SHOT_H0) e SHOT_BN presi in prestito in NEXT.
# Dove sotto il fascio c'è qualcosa (righe 0-3: riserve, barre, punteggi) il programma mette un
# carattere fuso, quello di sotto con il tratto sopra, in uno dei SHOT_PN caratteri della riserva:
# uno per cella di fascio (8 colpi, due fasci, due celle), presi in prestito anche loro
SHOT_H0 = 3
SHOT_BN = 3 * 7
SHOT_PN = 32


def shot_rows(params: str) -> tuple[int, int]:
    """Righe di schermo delle bocche dei cannoni del BLASTER (la prima delle due righe di pixel di
    ciascuna), meno ceil(y) della racchetta: le righe dell'immagine (assets/ships/sprites/c64) con
    il colore del tipo nella colonna più avanti, nello sprite espanso in verticale che pad_sprite
    mette dalla riga floor(P_HEIGHT - 1/2 - y - h/2) + 1 (h altezza del BLASTER)."""
    im = Image.open(ROOT / "assets" / "ships" / "sprites" / "c64" / "blaster.png")
    w, h = im.size
    px = [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]
    front = max(x for x in range(w) if any(px[y][x] for y in range(h)))
    muzzles = [y for y in range(h) if px[y][front] == 2]
    assert len(muzzles) == 2, f"BLASTER: bocche dei cannoni nella colonna {front}: {muzzles}"
    kind_h = [int(v, 16) for v in re.search(r"\.define T_KIND_H (.*)", params).group(1).replace("$", "").split(", ")]
    height = int(re.search(r"^P_HEIGHT\s*=\s*\$([0-9A-F]+)", params, re.M).group(1), 16)
    # u - h/2 = P_HEIGHT - 1/2 - h/2 - y in Q16.16: con la parte intera k e senza frazione,
    # floor(k - y) + 1 = k + 1 - ceil(y)
    edge = height - 0x8000 - kind_h[PAD_KINDS.index("blaster")] // 2
    assert edge & 0xFFFF == 0, "BLASTER: bordo della racchetta non intero (altezza dispari)"
    r0 = (edge >> 16) + 1
    return r0 + 2 * muzzles[0], r0 + 2 * muzzles[1]


def shot_assets(cs: Charset, lines: list[str], own: list[int], letters: str, pick_range: range) -> None:
    """Caratteri dei fasci laser: quelli del set (`own`, altezza SHOT_H0) e i SHOT_BN presi in
    prestito in NEXT, gli ultimi prima della pagina dei nomi (TN_FIRST): le ultime lettere 2x e
    il resto vuoto delle loro pagine. Il programma ci scrive i glifi nel conto alla rovescia
    (shot_glyphs) e li rimette vuoti al primo frame fuori dalla partita (next_shots). I SHOT_PN
    caratteri della riserva dei fusi (bd_fuse) sono le prime lettere 2x, da SHOT_P0. Le lettere
    2x toccate si rifanno al primo frame del GAME OVER (next_shots): si vedono solo lì (e nelle
    schermate che si rifanno le pagine: scelta, targa, VS, finale). In partita la pagina dei nomi
    serve a OMEGA, e da lì in su c'è solo il set di sempre."""
    b0 = TN_FIRST - SHOT_BN
    p0 = PICK_FIRST
    taken = [*range(p0, p0 + SHOT_PN), *range(b0, TN_FIRST)]
    big_end = PICK_FIRST + 4 * len(letters)
    assert b0 >= p0 + SHOT_PN and TN_FIRST <= pick_range.stop, "colpi: caratteri fuori dalle pagine della scelta"
    assert p0 % 32 == 0 and SHOT_PN == 32, "bd_fuse: la riserva è una pagina di 256 byte del set"
    # dalle lettere 2x solo lettere intere (rifatte da big2_build), il resto oltre
    first_letter = (p0 - PICK_FIRST) // 4
    assert big_end <= TN_FIRST and first_letter < len(letters)
    # i caratteri presi non sono di nessun altro: solo segnaposto delle pagine della scelta (le
    # lettere 2x hanno codici da formula, non da cs.add)
    for c in taken:
        assert cs.given.count(c) == 1 and cs.tiles[c] == BLANK, c
    # e non compaiono nelle scritte del GAME OVER oltre le due lettere che si rifanno
    big = [int(v) for line in lines if line.startswith(".define BIG_") for v in line.split(" ", 2)[2].split(", ")]
    assert not any(big_end <= c < TN_FIRST for c in big), "scritte del GAME OVER sui caratteri dei colpi"
    # la scelta dei bonus ricopre tutte le pagine con le metà delle lettere fino a oltre i colpi
    assert PICK_FIRST + 2 * len(FONT_DRAWN) >= TN_FIRST, "colpi: la scelta non ricopre i caratteri presi"
    chars = []
    for hgt in range(4):
        if hgt == SHOT_H0:
            chars += own
        else:
            base = b0 + 7 * (hgt - (hgt > SHOT_H0))
            chars += [base, 0] + [base + i for i in range(1, 7)]
    assert own == [own[0], 0] + [own[0] + i for i in range(1, 7)], f"colpi: caratteri del set non in fila: {own}"
    top, bottom = shot_rows((OUT / "params.inc").read_text(encoding="utf-8"))
    assert bottom - top == 16, "colpi: i due fasci a 16 righe (stessa altezza, due righe di celle)"
    assert SHOT_H0 == 3, "shot_glyphs: le altezze prese sono 0, 1 e 2 (riga del tratto 2 * altezza)"
    lines.append("; BLASTER: caratteri dei fasci per altezza del tratto (righe 2h e 2h + 1) e fase: primo e")
    lines.append("; secondo carattere (0: nessuno); quelli dell'altezza SHOT_H0 nel set, gli altri SHOT_BN da")
    lines.append("; SHOT_B0 presi in prestito in NEXT (shot_glyphs), dove stanno le lettere 2x da SHOT_LETTER0")
    lines.append("; (SHOT_LETTERS, rifatte al GAME OVER) e il vuoto dopo. Riserva dei caratteri fusi (bd_fuse):")
    lines.append("; SHOT_PN da SHOT_P0, uno per cella di fascio. Righe di schermo delle bocche dei cannoni:")
    lines.append("; SHOT_TOP - ceil(y) e SHOT_BOT - ceil(y)")
    lines.append(".define SHOT_CHARS " + ", ".join(str(c) for c in chars))
    lines.append(f"SHOT_H0 = {SHOT_H0}")
    lines.append(f"SHOT_OWN = {own[0]}")
    lines.append(f"SHOT_B0 = {b0}")
    lines.append(f"SHOT_BN = {SHOT_BN}")
    lines.append(f"SHOT_P0 = {p0}")
    lines.append(f"SHOT_PN = {SHOT_PN}")
    lines.append(f"SHOT_LETTER0 = {first_letter}")
    lines.append(f"SHOT_LETTERS = {len(letters) - first_letter}")
    lines.append(f"SHOT_TOP = {top}")
    lines.append(f"SHOT_BOT = {bottom}")
    lines.append("")


# NEXT: effetti della palla, sprite disegnati a inizio partita nella bitmap dell'attract ($E000, che
# in partita non serve): gli aloni di SLOW, sprite normali con la palla nel pixel (9, 7). La coda
# grigia e la cometa del SUPER invece il programma le disegna in partita dalle posizioni vere della
# palla (video.s, trail_end): qui solo il retino per età e i quadrati ritagliati della coda.
FX_RING_BALL = (9, 7)  # pixel della palla nell'alone
TRAIL_N = 5            # coda: posizioni passate della palla (0,1 s a 50 Hz), più quelle a metà tra due
# retino ordinato 4x4 (Bayer): la coda grigia sfuma diradandosi verso la fine
BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


TRAIL_ROWS = 24        # righe per età nel retino della coda (21 dello sprite, arrotondate)
TRAIL_SPAN = 48        # coordinate dei quadrati della coda nello sprite + 16: da 0 a 47


def trail_dither() -> list[int]:
    """Retino della coda: per ogni età (0 = a metà tra la palla e la posizione di un frame fa,
    1 = un frame fa, ... 2 * TRAIL_N - 1 = la più vecchia) e riga dello sprite, il byte dello sprite
    multicolore con %01 nei quattro pixel doppi accesi. Densità da quasi piena a quasi vuota."""
    out = []
    for age in range(2 * TRAIL_N):
        density = 1 - (age + 1) / (2 * TRAIL_N + 1)
        for row in range(TRAIL_ROWS):
            out.append(sum(0x40 >> (2 * p) for p in range(4) if BAYER4[row % 4][p] < density * 16))
    return out


def trail_tables() -> list[str]:
    """Quadrati della coda già ritagliati allo sprite (12 pixel doppi x 21 righe), per lato 4 e 6:
    indice = coordinata del bordo sinistro (o alto) nello sprite + 16, più 48 per il lato 6.
    Per la x: primo byte della riga, maschera dei pixel doppi in quel byte e nel successivo (0 se
    il quadrato sta in un byte solo; nel primo 0 se è fuori); per la y: prima riga * 3 e righe."""
    b0, lm, rm, base, rows, r0s = [], [], [], [], [], []
    pair_bits = [0xC0, 0x30, 0x0C, 0x03]
    for size in (4, 6):
        for c in range(TRAIL_SPAN):
            x0, x1 = max(c - 16, 0), min(c - 16 + size - 1, 23)
            first = left = right = 0
            if x0 <= x1:
                i0, i1 = x0 // 2, x1 // 2
                first = i0 // 4
                for i in range(i0, i1 + 1):
                    if i // 4 == first:
                        left |= pair_bits[i % 4]
                    else:
                        right |= pair_bits[i % 4]
            b0.append(first)
            lm.append(left)
            rm.append(right)
            y0, y1 = max(c - 16, 0), min(c - 16 + size - 1, 20)
            n = max(y1 - y0 + 1, 0)
            rows.append(n)
            base.append(3 * y0 if n else 0)
            r0s.append(y0 if n else 0)
    ages = [TRAIL_ROWS * a for a in range(2 * TRAIL_N)]
    hexes = lambda v: ", ".join(f"${b:02X}" for b in v)
    return [
        f"TRAIL_SPAN = {TRAIL_SPAN}    ; coda: coordinate dei quadrati nello sprite + 16, da 0 a 47",
        ".define TRAIL_X_B0 " + hexes(b0),
        ".define TRAIL_X_LM " + hexes(lm),
        ".define TRAIL_X_RM " + hexes(rm),
        ".define TRAIL_Y_BASE " + hexes(base),
        ".define TRAIL_Y_ROWS " + hexes(rows),
        ".define TRAIL_Y_R0 " + hexes(r0s),
        ".define TRAIL_AGE " + hexes(ages),
    ]


def fx_image(cells: set[tuple[int, int]]) -> bytes:
    """Sprite hires dai pixel (x, y) accesi, griglia 24x21."""
    data = bytearray(64)
    for x, y in cells:
        if 0 <= x < 24 and 0 <= y < 21:
            data[3 * y + x // 8] |= 0x80 >> (x % 8)
    return bytes(data)


def next_fx_sprites() -> tuple[bytes, list[str]]:
    """Alone di SLOW (palla 4 e 6 pixel, quadrato di lato triplo, a puntini perché sul MiSTer è
    grigio)."""
    images = []
    rx, ry = FX_RING_BALL
    for size in (4, 6):
        cx, cy = rx + size / 2, ry + size / 2
        side = 3 * size
        x0, y0 = round(cx - side / 2), round(cy - side / 2)
        cells = {(rx + i, ry + j) for i in range(size) for j in range(size)}
        for t in range(side):
            for x, y in ((x0 + t, y0), (x0 + t, y0 + side - 1), (x0, y0 + t), (x0 + side - 1, y0 + t)):
                if (x + y) % 2 == 0:
                    cells.add((x, y))
        images.append(fx_image(cells))
    lines = [
        f"FX_SPRITES = {len(images)}    ; effetti della palla: 2 aloni",
        f"FX_RING_X = {FX_RING_BALL[0]}",
        f"FX_RING_Y = {FX_RING_BALL[1]}",
        f"TRAIL_N = {TRAIL_N}    ; coda: posizioni passate della palla",
        "; coda: retino per età (2 * TRAIL_N, TRAIL_ROWS righe ciascuna), %01 nei pixel doppi accesi",
        ".define TRAIL_DITHER " + ", ".join(f"${b:02X}" for b in trail_dither()),
        *trail_tables(),
    ]
    return b"".join(images), lines


def fx_squares() -> list[str]:
    """Aloni di next_fx_sprites come quadrati (x, y, lato) per immagine, chiusi da $FF: il programma
    li disegna a inizio partita."""
    out = []
    rx, ry = FX_RING_BALL
    for size in (4, 6):
        cx, cy = rx + size / 2, ry + size / 2
        side = 3 * size
        x0, y0 = round(cx - side / 2), round(cy - side / 2)
        sq = [(rx, ry, size)]
        cells = set()
        for t in range(side):
            for x, y in ((x0 + t, y0), (x0 + t, y0 + side - 1), (x0, y0 + t), (x0 + side - 1, y0 + t)):
                if (x + y) % 2 == 0:
                    cells.add((x, y))
        sq += [(x, y, 1) for x, y in sorted(cells)]
        out.append(sq)
    # controllo: gli stessi pixel delle immagini di next_fx_sprites (dentro la griglia)
    data, _ = next_fx_sprites()
    for k, sq in enumerate(out):
        cells = set()
        for x, y, size in sq:
            cells |= {(x + i, y + j) for i in range(size) for j in range(size)}
        assert fx_image(cells) == data[64 * k:64 * k + 64], k
    flat = []
    for sq in out:
        for x, y, size in sq:
            flat += [x & 0xFF, y & 0xFF, size]
        flat.append(0xFF)
    return ["; aloni: quadrati (x, y, lato) per immagine, $FF alla fine di ognuna",
            ".define FX_SQUARES " + ", ".join(map(str, flat))]


def next_sprites() -> tuple[bytes, list[str]]:
    """NEXT: capsule in campo (CAP x CAP, il SUPER anche in negativo per il lampeggio) e icone 9x9
    del bonus armato (non del BULLET, che non resta armato)."""
    data = b"".join(sprite_of(capsule(b, False)) for b in range(BONUSES))
    data += sprite_of(capsule(B_SUPER, True))
    icons = [b for b in range(BONUSES) if b != B_BULLET]
    assert icons == list(range(len(icons))), "icone per codice del bonus"
    data += b"".join(sprite_of([[icon_lit(b, x, y) for x in range(9)] for y in range(9)]) for b in icons)
    return data, [f"SPRITE_CAPS = {BONUSES}", f"SPRITE_ICONS = {len(icons)}", f"CAP_DRAW = {CAP}"]


# ------------------------------------------------------------------------- mosse speciali
#
# NEXT con le mosse speciali (c64/src/supers.s): barra di ciascun giocatore accanto alle riserve,
# icona della mossa armata accanto alla racchetta, effetti del SID dell'attivazione e del colpo.

BAR_CHARS = 5           # barra: un carattere per 0, 2, 4, 6 e 8 pixel pieni
BAR_ORIG = 0xC3         # originali dei caratteri della barra nella pagina $FF00 (dopo VOICE_COUNT)
# icone 8x8 (bit 7 = pixel a sinistra), per il giocatore sinistro: STRAIGHT SHOT (freccia verso
# l'avversario) e RISING STRIKE (dritta, poi in alto); il destro le ha specchiate
SUPER_ICONS = {
    "STRAIGHT": (0x00, 0x00, 0x04, 0x06, 0xFF, 0x06, 0x04, 0x00),
    "RISE": (0x00, 0x07, 0x03, 0x05, 0x08, 0xF0, 0x00, 0x00),
}
# la ROM della musica (la stessa del MiSTer e del player 6502)
SID_GEN = ROOT / "mister" / "rtl" / "gen"
SID_VH = SID_GEN / "sid_music.vh"
SID_HEX = SID_GEN / "sid_music.hex"


def mirror8(b: int) -> int:
    return int(f"{b:08b}"[::-1], 2)


def bar_glyph(px: int) -> bytes:
    """Cella della barra: bordo sopra e sotto (righe 0 e 4), pieno per `px` pixel da sinistra."""
    fill = (0xFF << (8 - px)) & 0xFF
    return bytes((0xFF, fill, fill, fill, 0xFF, 0, 0, 0))


def supers_assets(lines: list[str], bar: list[int]) -> None:
    """Barra, icone e tracce degli effetti delle mosse speciali (definizioni in assets.inc).

    Il set di caratteri è pieno: la barra ha BAR_CHARS caratteri suoi (`bar`, contigui, vuoti nel
    set, che si vedono solo in NEXT); supers.s li scrive a inizio partita e restano. Le tracce MOVE
    e SPECIAL sono quelle della ROM della musica (tools/gen_sid_music.py le mette in fondo, dopo i
    temi, fuori da sid_music.bin): qui si prendono da sid_music.hex, con gli indirizzi di
    sid_music.vh (SID_GEN)."""
    assert bar == list(range(bar[0], bar[0] + BAR_CHARS)), f"caratteri della barra non contigui: {bar}"
    lines.append("; NEXT, mosse speciali: caratteri della barra (supers.s, bullet_chars)")
    lines.append(f"BAR_C0 = {bar[0]}")
    lines.append(f"BAR_CHARS = {BAR_CHARS}")
    glyphs = b"".join(bar_glyph(2 * i) for i in range(BAR_CHARS))
    lines.append(".define BAR_GLYPHS " + ", ".join(f"${b:02X}" for b in glyphs))
    icons = []
    for name in ("STRAIGHT", "RISE"):
        icons += [SUPER_ICONS[name], tuple(mirror8(b) for b in SUPER_ICONS[name])]
    lines.append("; icone della mossa armata: STRAIGHT SHOT sinistro e destro, RISING STRIKE sinistro e destro")
    lines.append(".define SUPER_ICONS " + ", ".join(f"${b:02X}" for icon in icons for b in icon))
    vh = SID_VH.read_text(encoding="utf-8")
    rom = [int(v, 16) for v in SID_HEX.read_text(encoding="utf-8").split()]

    def param(name: str) -> int:
        for line in vh.splitlines():
            if line.startswith(f"localparam {name} ="):
                return int(line.split("=")[1].split(";")[0])
        raise SystemExit(f"{SID_VH}: manca {name}")

    # indirizzi della ROM: "sid_song_start = 13'd320;" (la larghezza segue la ROM)
    def addr(line: str) -> int | None:
        m = re.search(r"sid_(?:song|fx)_start = \d+'d(\d+);", line)
        return int(m.group(1)) if m else None

    starts = sorted(a for a in map(addr, vh.splitlines()) if a is not None)
    assert param("SID_ROM_SIZE") == len(rom), "sid_music.hex e sid_music.vh non vanno insieme"
    fx = {}
    for line in vh.splitlines():
        if "sid_fx_start =" in line and line.strip().startswith("4'd"):
            fx[int(line.split("4'd")[1].split(":")[0])] = addr(line)
    # tracce degli effetti fuori da sid_music.bin, nel codice che li usa: mosse speciali (supers.s),
    # sparo del BLASTER (LASER) e rimbalzo della pallina del continue (BOUNCE, challenge.s)
    for name in ("MOVE", "SPECIAL", "LASER", "BOUNCE"):
        start = fx[param(f"SID_FX_{name}")]
        end = min([s for s in starts if s > start] + [len(rom)])
        track = rom[start:end]
        assert track and start >= param("SID_ROM_BASE_SIZE"), name
        lines.append(f"SID_FX_{name} = {param(f'SID_FX_{name}')}")
        lines.append(f".define SID_TRACK_{name} " + ", ".join(f"${b:02X}" for b in track))


def sprite(w: int, h: int) -> bytes:
    """Sprite hires con un quadrato pieno w x h in alto a sinistra."""
    data = bytearray(64)
    for y in range(h):
        bits = ((1 << w) - 1) << (24 - w)
        data[3 * y : 3 * y + 3] = bits.to_bytes(3, "big")
    return bytes(data)


# ----------------------------------------------------------------------------------- attract
#
# L'attract delle altre versioni è definito su 320x240 a 60 Hz (assets/attract/attract.json): sul
# C64 lo schermo è 320x200 e i frame sono a 50 Hz. Le parti centrali salgono di 20 righe, le
# scritte in basso si avvicinano; i tempi si convertono in frame a 50 Hz.

SPEC = json.loads((ATTRACT / "attract.json").read_text(encoding="utf-8"))
W64, H64 = 320, 200
Y_SHIFT = 20
# scritte del titolo nella bitmap, nelle celle (il programma ci copia i glifi del set): INSERT COIN
# / PRESS START (riga 19), CREDIT n / FREE PLAY (riga 22), il
# copyright (riga 24: il simbolo è nel titolo, il resto lo scrive il programma)
LABEL_ROW = 19
LABEL_LEN = 11         # INSERT COIN e PRESS START
CREDIT_ROW = 22
COPYRIGHT_ROW = 24
COPYRIGHT_TEXT = "2026 SCHERMOBIANCO"
# simbolo del copyright, disegnato qui (non è nel set maiuscolo della ROM)
COPYRIGHT_SIGN = (0x3C, 0x42, 0x99, 0xA1, 0xA1, 0x99, 0x42, 0x3C)


def f50(frames60: float) -> int:
    """Frame a 60 Hz -> frame a 50 Hz."""
    return round(frames60 * 50 / 60)


def png_pixels(name: str) -> list[list[bool]]:
    im = Image.open(ATTRACT / f"{name}.png").convert("RGBA")
    w, h = im.size
    return [[im.getpixel((x, y))[3] > 127 for x in range(w)] for y in range(h)]


class Bitmap:
    """Bitmap hires 320x200 a 1 bit (1 = nero sul titolo giallo)."""

    def __init__(self) -> None:
        self.px = [[False] * W64 for _ in range(H64)]

    def put(self, pixels: list[list[bool]], x0: int, y0: int, value: bool = True, scale: int = 1) -> None:
        for y, row in enumerate(pixels):
            for x, lit in enumerate(row):
                if lit:
                    for dy in range(scale):
                        for dx in range(scale):
                            self.px[y0 + scale * y + dy][x0 + scale * x + dx] = value

    def rect(self, x0: int, y0: int, w: int, h: int) -> None:
        for y in range(y0, y0 + h):
            for x in range(max(0, x0), min(W64, x0 + w)):
                self.px[y][x] = True

    def cells(self, c0: int, c1: int, r0: int, r1: int) -> bytes:
        """Byte delle celle (colonne c0..c1, righe di celle r0..r1), nell'ordine della memoria del VIC."""
        out = bytearray()
        for cy in range(r0, r1 + 1):
            for cx in range(c0, c1 + 1):
                for row in range(8):
                    b = 0
                    for x in range(8):
                        if self.px[cy * 8 + row][cx * 8 + x]:
                            b |= 0x80 >> x
                    out.append(b)
        return bytes(out)

    def c64(self) -> bytes:
        return self.cells(0, 39, 0, 24)


def centered(width: int) -> int:
    return round((W64 - width) / 2)


def next_consts() -> list[str]:
    """NEXT sotto il logo (assets/attract/attract.json, "next") nella bitmap a 320x200 (le righe come
    il titolo, meno Y_SHIFT). Le quattro lettere sono già spostate di quanto serve per cadere ai loro
    pixel (non sono allineate alle celle): per ogni riga due byte, la parte nella cella della lettera e
    quella nella cella dopo. Sul C64 NEXT non si anima: c'è, intero, o non c'è."""
    import gen_attract_assets as attract
    nx = SPEC["next"]
    letters = []                       # per lettera: 10 righe x (byte nella cella, byte nella cella dopo)
    cols = []
    for i, name in enumerate("NEXT"):
        x = nx["x"] + i * nx["pitch"]
        shift = x & 7
        cols.append(x >> 3)
        for row in attract.next_letter_rows(name):
            b = sum(v << (7 - k) for k, v in enumerate(row))
            letters += [b >> shift, (b << (8 - shift)) & 0xFF]
    consts = {
        "NX_Y": nx["y"] - Y_SHIFT, "NX_LINE_Y": nx["line"]["y"] - Y_SHIFT, "NX_LINE_X": nx["line"]["x"],
        "NX_LINE_HALF": nx["line"]["half"][-1], "NX_ROWS": 10,
    }
    lines = ["", "; NEXT sotto il logo (solo in NEXT): posizione, lettere"]
    lines += [f"{k} = {v}" for k, v in consts.items()]
    lines.append(".define NX_COLS " + ", ".join(map(str, cols)))
    lines.append(".define NX_GLYPHS " + ", ".join(map(str, letters)))
    return lines


def attract_assets(lines: list[str]) -> dict[str, bytes]:
    st, logo, ws, t = SPEC["stripes"], SPEC["logo"], SPEC["ws"], SPEC["title"]
    rows = [int(r) - Y_SHIFT for r in st["rows"]]
    height, left_end, right_start = int(st["height"]), int(st["left_end"]), int(st["right_start"])
    logo_px, ws_px = png_pixels("logo"), png_pixels("ws")
    lx, ly = int(logo["x"]), int(logo["y"]) - Y_SHIFT
    wx, wy = int(ws["x"]), int(ws["y"]) - Y_SHIFT
    # titolo completo: strisce, WS (giallo dentro la striscia), logo, copyright
    title = Bitmap()
    for r in rows:
        title.rect(0, r, left_end, height)
        title.rect(right_start, r, W64 - right_start, height)
    title.put(ws_px, wx, wy, value=False)
    title.put(logo_px, lx, ly)
    # copyright: il simbolo, poi uno spazio e il testo (riga COPYRIGHT_ROW, centrati)
    cp_col = (40 - 2 - len(COPYRIGHT_TEXT)) // 2
    title.put([[bool(r & 0x80 >> x) for x in range(8)] for r in COPYRIGHT_SIGN], 8 * cp_col, 8 * COPYRIGHT_ROW)
    # 1x: il 2x è solo per i titoli grandi (attract.json ha label_scale per le altre versioni)
    scale = 1
    fr = SPEC["frames"]
    b = SPEC["boot"]
    consts = {
        "AT_BOOT_FRAMES": f50(fr["boot"]),
        "AT_TITLE_FRAMES": f50(fr["title"]),
        "AT_GAME_OVER_FRAMES": f50(fr["game_over"]),
        "AT_GAME_OVER_BLACK": f50(SPEC["game_over"]["black_frames"]),
        "AT_BOOT_LINE_FRAMES": f50(b["line_frames"]),
        "AT_BOOT_GRID_FROM": f50(b["grid_from"]),
        "AT_CURSOR_HALF": f50(b["cursor_period"] / 2),
        "AT_STRIPE_H": height,
        "AT_STRIPE_LEFT": left_end,
        "AT_STRIPE_RIGHT": right_start,
        "AT_LOGO_Y": ly,
        "AT_LOGO_H": len(logo_px),
        "AT_LOGO_X": lx,
        "AT_LOGO_W": len(logo_px[0]),
        "AT_LOGO_C0": lx // 8,
        "AT_LOGO_C1": (lx + len(logo_px[0]) - 1) // 8,
        "AT_WS_Y": wy,
        "AT_WS_H": len(ws_px),
        "AT_WS_C0": wx // 8,
        "AT_WS_C1": (wx + len(ws_px[0]) - 1) // 8,
        "AT_BLINK_PERIOD": f50(t["blink_period"]),
        "AT_BLINK_ON": f50(t["blink_on"]),
        "AT_LABEL_FROM": f50(t["label_from"]),
        "AT_LABEL_C0": (40 - scale * LABEL_LEN) // 2,
        "AT_LABEL_W": scale * LABEL_LEN,
        "AT_LABEL_R0": LABEL_ROW,
        "AT_LABEL_2X": scale - 1,
        "AT_FREE_C0": (40 - len("FREE PLAY")) // 2,     # FREE PLAY
        "AT_CREDIT_C0": (40 - len("CREDIT 0")) // 2,    # CREDIT n
        "AT_CREDIT_W": len("FREE PLAY") + 1,            # celle da pulire dalla prima delle due
        "AT_CREDIT_R0": CREDIT_ROW,
        # pallina del titolo: posizione e velocità in pixel * 64, a 50 Hz
        "AT_BALL_X": int(t["ball"]["x"]) * 64,
        "AT_BALL_Y": (int(t["ball"]["y"]) - Y_SHIFT) * 64,
        "AT_BALL_VX": round(t["ball"]["vx"] * 60 / 50 * 64),
        "AT_BALL_VY": round(t["ball"]["vy"] * 60 / 50 * 64),
        "AT_BALL_SIZE": int(t["ball"]["size"]),
        "AT_COPYRIGHT_Y": 8 * COPYRIGHT_ROW,
        "AT_COPYRIGHT_H": 8,
        "AT_COPYRIGHT_C0": cp_col + 2,                  # il testo, dopo il simbolo e uno spazio
    }
    lines.append("")
    lines.append("; attract (attract.json riportato a 320x200 e 50 Hz)")
    lines += [f"{k} = {v}" for k, v in consts.items()]
    for i, r in enumerate(rows):
        lines.append(f"AT_STRIPE_Y{i} = {r}")
    lines += next_consts()
    # del titolo servono solo le righe di caratteri con il logo e WS (blocco A) e con il copyright
    # (blocco B): l'attract li copia nella bitmap a schermo
    # del blocco A solo le colonne del logo e di WS
    full = title.c64()
    a0, a1 = min(ly, wy) // 8, (max(ly + len(logo_px), wy + len(ws_px)) - 1) // 8 + 1
    b0, b1 = COPYRIGHT_ROW, COPYRIGHT_ROW + 1
    c0, c1 = lx // 8, (wx + len(ws_px[0]) - 1) // 8 + 1
    assert a1 <= b0 and c0 <= wx // 8
    lines.append(f"TITLE_A_ROW = {a0}    ; righe di caratteri del blocco A in title.bin, poi il B")
    lines.append(f"TITLE_A_END = {a1}")
    lines.append(f"TITLE_A_C0 = {c0}    ; colonne del blocco A (il B è largo tutto lo schermo)")
    lines.append(f"TITLE_A_W = {c1 - c0}")
    lines.append(f"TITLE_B_ROW = {b0}")
    lines.append(f"TITLE_B_END = {b1}")
    slim = b"".join(full[r * 320 + c0 * 8:r * 320 + c1 * 8] for r in range(a0, a1))
    slim += full[b0 * 320:b1 * 320]
    # nella cartuccia (pick_bank.bin): l'avvio lo copia sotto l'I/O
    lines.append(f"TITLE_SIZE = {len(slim)}    ; byte di title.bin")
    lines.append(f'.define AT_COPYRIGHT_TEXT "{COPYRIGHT_TEXT}"')
    return {"title.bin": slim}


# Finale di CHALLENGE (src/ending.s): un set di caratteri suo, che il finale copia sopra quello del
# programma (e alla fine rimette): il font resta ai suoi codici (le routine del programma scrivono
# con FONT_MAP), il resto è del finale. I glifi del font e delle lettere 2x sono segnaposto, come
# nel set del programma: il finale li prende dalla ROM (font_from_rom, big_build)
END_FW_BASE = 192      # fuochi d'artificio, multicolore: codice = base + colore * 16 + quadranti
END_FW_COLORS = 3      # %01 bianco ($D022), %10 giallo ($D023), %11 rosso (colore del carattere)
END_BIG_BASE = 64      # lettere 2x (2x2 caratteri per lettera, quattro codici di fila)
# scritte a 2x del finale (big_print di src/ending.s): solo YOU WIN!, come nel GAME OVER; il resto,
# titoli di coda compresi, è a 1x
END_BIG_TEXTS = ["YOU WIN!"]
END_STAMP_W, END_STAMP_H = 5, 3                     # timbro DEFEATED: caratteri
# lettere 3x5 del timbro
STAMP_FONT = {
    "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
    "E": ["XXX", "X..", "XX.", "X..", "XXX"],
    "F": ["XXX", "X..", "XX.", "X..", "X.."],
    "A": ["XXX", "X.X", "XXX", "X.X", "X.X"],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
}


def stamp_pixels() -> list[list[bool]]:
    """Timbro DEFEATED inclinato di 18 gradi (in salita verso destra) in 40x24 pixel: le lettere 3x5
    a scaletta lungo la base inclinata, il riquadro con le linee inclinate."""
    import math
    w, h = 8 * END_STAMP_W, 8 * END_STAMP_H
    px = [[False] * w for _ in range(h)]

    def put(x: int, y: int) -> None:
        if 0 <= x < w and 0 <= y < h:
            px[y][x] = True

    ang = math.radians(18)
    cx, cy = w / 2, h / 2
    text = "DEFEATED"
    tw = len(text) * 4 - 1
    for i, ch in enumerate(text):
        lx = -tw / 2 + i * 4 + 1.5
        x0 = round(cx + lx * math.cos(ang) - 1.5)
        y0 = round(cy - lx * math.sin(ang) - 2.5)
        for r, row in enumerate(STAMP_FONT[ch]):
            for c, v in enumerate(row):
                if v == "X":
                    put(x0 + c, y0 + r)
    hw, hh = tw / 2 + 2, 6.0
    corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
    pts = [(cx + x * math.cos(ang) + y * math.sin(ang), cy - x * math.sin(ang) + y * math.cos(ang)) for x, y in corners]
    for i in range(4):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for k in range(n + 1):
            t = k / n
            put(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t))
    return px


def fw_glyph(color: int, mask: int) -> Tile:
    """Carattere multicolore dei fuochi: un punto di 2x2 pixel al centro di ogni quadrante acceso
    (bit 0 alto a sinistra, 1 alto a destra, 2 basso a sinistra, 3 basso a destra), sulla griglia
    di 4 pixel; colore 0 bianco (%01), 1 giallo (%10), 2 rosso (%11)."""
    pair = color + 1
    rows = [0] * 8
    for q in range(4):
        if mask >> q & 1:
            col = 2 * (q & 1) + 1                   # pixel multicolore 1 o 3 (pixel 2-3 o 6-7)
            for r in (4 * (q >> 1) + 1, 4 * (q >> 1) + 2):
                rows[r] |= pair << (6 - 2 * col)
    return tuple(rows)


# Titoli di coda, come CREDITS di rust/game/src/ending_ui.rs: titolo grande (a 1x e giallo come i
# titoli di sezione, ma con le sue due righe: la seconda vuota), titolo di sezione, voce; ogni GAP
# lascia due righe in più. Il titolo finale va su due righe "grandi". Il C64
# non usa font di terzi per le scritte: niente riga del font, e al suo posto (una voce: due righe)
# un GAP in più prima di THANK YOU, così l'ultima riga arriva al centro nello stesso frame di prima
# (la durata va con la musica).
END_CREDITS = [
    ("big", "PADD WS"),
    ("head", "GAME DESIGN AND PROGRAMMING"),
    ("text", "SCHERMOBIANCO"),
    ("head", "PLATFORMS"),
    ("text", "PC  WEB  RASPBERRY PI"),
    ("text", "MISTER FPGA"),
    ("text", "COMMODORE 64"),
    ("head", "MUSIC AND SOUND"),
    ("text", "ORIGINAL SID MUSIC"),
    ("text", "SID SOUND EFFECTS"),
    ("text", "ANNOUNCER VOICES"),
    ("head", "THE CHALLENGERS"),
    ("text", "ARCADE   TITAN   HAMMER"),
    ("text", "TWIST   BLASTER   RUSH"),
    ("text", "AND GUARDIAN"),
    ("head", "THIRD-PARTY WORKS"),
    ("text", "PONG SCORE FONT  PWNZOR.AK"),
    ("text", "MISTER FRAMEWORK  SORGELIG"),
    ("text", "SID EMULATION  DAG LEM  A. MELNIKOV"),
    ("text", "VEXRISCV  SPINALHDL"),
    ("text", "MACROQUAD  FEDOR LOGACHEV"),
    ("text", "GILRS  SDL GAMECONTROLLERDB"),
    ("text", "PYTHON ARCADE  PIGPIO"),
    ("head", "SPECIAL THANKS"),
    ("text", "THE MISTER FPGA COMMUNITY"),
    ("text", "THE COMMODORE 64 SCENE"),
    ("gap", ""),
    ("gap", ""),
    ("big", "THANK YOU"),
    ("big", "FOR PLAYING"),
]
CRED_STYLE = {"text": 0, "head": 1, "big": 1}
CRED_BLANK = {"text": 1, "head": 2, "big": 2}       # righe vuote prima della riga


def credits_tables() -> list[str]:
    """Titoli di coda in righe virtuali (da 0, la prima riga): per riga il numero della riga di testo
    (da 1; con il bit 7 la seconda riga di un titolo grande), per riga di testo colonna, stile,
    lunghezza e testo."""
    rows: list[int] = []
    cols, styles, lens, offs, texts = [], [], [], [], []
    extra = 0
    off = 0
    for kind, text in END_CREDITS:
        if kind == "gap":
            extra += 2
            continue
        assert all(c in FONT_DRAWN + " " for c in text), text
        big = kind == "big"
        width = len(text)
        assert width <= 40, text
        if rows:
            rows += [0] * (CRED_BLANK[kind] + extra)
        extra = 0
        n = len(cols) + 1
        rows.append(n)
        if big:
            rows.append(0)          # la seconda riga del titolo grande (tempi come prima)
        cols.append((40 - width) // 2)
        styles.append(CRED_STYLE[kind])
        lens.append(len(text))
        offs.append(off)
        texts.append(text)
        off += len(text)
    last = max(i for i, r in enumerate(rows) if r and not r & 0x80)
    return [
        "; titoli di coda (righe virtuali da 0): per riga 0 o la riga di testo (da 1, bit 7: seconda",
        "; riga di un titolo grande); per riga di testo colonna, stile (0 voce bianca, 1 titolo giallo,",
        "; 2 grande giallo), lunghezza, inizio nel testo",
        f"END_CRED_LINES = {len(cols)}",
        f"END_CRED_ROWS = {len(rows)}",
        f"END_CRED_LAST = {last}    ; prima riga dell'ultima riga di testo",
        ".define END_CRED_ROW " + ", ".join(str(r) for r in rows),
        ".define END_CRED_COL " + ", ".join(str(c) for c in cols),
        ".define END_CRED_STYLE " + ", ".join(str(s) for s in styles),
        ".define END_CRED_LEN " + ", ".join(str(n) for n in lens),
        ".define END_CRED_OFF " + ", ".join(str(o) for o in offs),
        ".define END_CRED_TEXT " + ", ".join(f'"{t}"' for t in texts),
    ]


# Fuochi d'artificio (fireworks.py e ending_ui.rs): un passo ogni FW_FRAMES frame (16,7 al secondo,
# FW_T del passo del PC a 15), posizioni sulla griglia di 4 pixel (80x50, la parte alta dello
# schermo) in 8.8, velocità con segno in 1/256 di griglia per passo, gravità in 1/256 per passo al
# quadrato, attrito v -= v >> 5. Il razzo è uno sprite che sale in FW_RISE frame.
FW_FRAMES = 3
FW_T = FW_FRAMES / 50 * 15
FW_UNIT = 200 / 480 / 4                 # griglia per unità dello schermo alto 480
FW_RISE = 45                            # frame del razzo (14 passi del PC)
FW_GRAV = 3
FW_SLOTS, FW_MAX = 4, 24                # fuochi accesi insieme, scintille per fuoco
FW_CHAMPION = 350                       # frame di YOU ARE THE PADD WS CHAMPION


def fireworks_tables() -> list[str]:
    import math
    import random

    def v(speed: float, ang: float) -> tuple[int, int]:
        s = speed * FW_UNIT * FW_T * 256
        vx, vy = round(s * math.cos(ang)), round(s * math.sin(ang))
        assert -128 <= vx <= 127 and -128 <= vy <= 127, (speed, vx, vy)
        return vx & 0xFF, vy & 0xFF

    def ring(n: int, speed: float, color: int, phase: float = 0.0) -> list[tuple[int, int, int]]:
        return [(*v(speed, phase + a * math.tau / n), color) for a in range(n)]

    W, Y, R = 0xC0, 0xD0, 0xE0              # codice dei caratteri per colore (END_FW_BASE)
    life = lambda t: math.ceil(t / FW_T)    # noqa: E731 (passi del PC -> passi del C64)
    rng = random.Random(0xF1AE2026)
    crackle = []
    for i in range(20):
        ang = rng.uniform(0, math.tau)
        crackle.append((*v(0.5 + rng.uniform(0, 3.5), ang), (W, Y, R)[i % 3]))
    split = life(12)
    cross = [(*v(4.5, a * math.pi / 2 + math.pi / 4), W) for a in range(4) for _ in range(4)]
    cross_split = [(*v(2.5, a * math.pi / 2 + math.pi / 4 + (b - 1.5) * 0.5), R if (a + b) % 2 == 0 else Y)
                   for a in range(4) for b in range(4)]
    # anello bicolore (tema %11 + giallo %10 alternati) così ogni scoppio sfoggia il proprio colore
    ring_bi = [(*v(4.0, a * math.tau / 18), R if a % 2 == 0 else Y) for a in range(18)]
    willow_bi = [(*v(2.6, 0.13 + a * math.tau / 12), R if a % 2 == 0 else Y) for a in range(12)]
    # tipo: scintille, vita, gravità, attrito (shift, 0 = niente), scia, blocco, divisione, crepitio
    kinds = [
        ("RING", ring_bi, life(26), FW_GRAV, 5, 0, 0, 0, 0),
        ("WILLOW", willow_bi, life(50), FW_GRAV, 5, 2, 0, 0, 0),
        ("PALM", ring(7, 4.5, R, 0.3), life(34), FW_GRAV, 5, 2, 0, 0, 0),
        ("CHRYSANTHEMUM", ring(8, 2.2, W, 0.2) + ring(14, 4.2, R), life(30), FW_GRAV, 5, 0, 0, 0, 0),
        ("CRACKLE", crackle, life(40), 2, 0, 0, life(18), 0, 1),
        ("CROSSETTE", cross, life(34), FW_GRAV, 0, 0, 0, split, 0),
    ]
    vx, vy, vc = [], [], []
    rows = {k: [] for k in ("N", "LIFE", "GRAV", "DRAG", "TRAIL", "FREEZE", "SPLIT", "FLICK", "OFF")}
    for name, parts, lf, grav, drag, trail, freeze, spl, flick in kinds:
        assert len(parts) <= FW_MAX and lf < 128
        for key, val in zip(rows, (len(parts), lf, grav, drag, trail, freeze, spl, flick, len(vx))):
            rows[key].append(val)
        for x, y, c in parts:
            vx.append(x)
            vy.append(y)
            vc.append(c)
    split_off = len(vx)
    for x, y, c in cross_split:
        vx.append(x)
        vy.append(y)
        vc.append(c)
    assert len(vx) < 256
    # colori VIC-II multicolore in Color RAM ($D800: bit 3 acceso + colore 0..7):
    # ciano (3), rosso (2), viola (4), verde (5), blu (6), giallo (7)
    sky_cols = [8 + 3, 8 + 2, 8 + 4, 8 + 5, 8 + 3, 8 + 6, 8 + 4, 8 + 2, 8 + 5, 8 + 7]
    # lo spettacolo: i tipi a turno, uno ogni 6-12 passi fino a poco prima della fine
    show = []
    last = FW_CHAMPION // FW_FRAMES - life(30)
    start = 0
    rng = random.Random(0x2026F1AE)
    while start < last:
        gx = round((54 + rng.uniform(0, 212)) / 4)
        gy = round((70 + rng.uniform(0, 160)) * 200 / 480 / 4)
        cy = gy * 4 + 2
        v0 = round((200 - cy) * 256 / (FW_RISE / 2 + 0.5))
        acc = round(v0 / FW_RISE)
        assert v0 < 0x10000 and acc < 256
        col = sky_cols[len(show) % len(sky_cols)]
        show.append((start, len(show) % len(kinds), gx, gy, v0, acc, col))
        start += round((5 + rng.randrange(7)) / FW_T)
    lines = [
        "; fuochi d'artificio: tipi (anello, salice, palma, crisantemo, crepitio, croce che si divide)",
        f"FW_FRAMES = {FW_FRAMES}    ; frame per passo",
        f"FW_RISE = {FW_RISE}    ; frame del razzo",
        f"FW_SLOTS = {FW_SLOTS}",
        f"FW_MAX = {FW_MAX}",
        f"FW_KINDS = {len(kinds)}",
        f"FW_SPLIT_OFF = {split_off}    ; velocità dopo la divisione (CROSSETTE)",
        f"FW_SHOW = {len(show)}",
    ]
    for key, vals in rows.items():
        lines.append(f".define FW_K_{key} " + ", ".join(str(x) for x in vals))
    lines.append(".define FW_VX " + ", ".join(str(x) for x in vx))
    lines.append(".define FW_VY " + ", ".join(str(x) for x in vy))
    lines.append(".define FW_VC " + ", ".join(str(x) for x in vc))
    for i, key in enumerate(("STEP", "KIND", "GX", "GY")):
        lines.append(f".define FW_S_{key} " + ", ".join(str(s[i]) for s in show) + ", 255" * (key == "STEP"))
    lines.append(".define FW_S_V0 " + ", ".join(str(s[4]) for s in show))
    lines.append(".define FW_S_ACC " + ", ".join(str(s[5]) for s in show))
    lines.append(".define FW_S_COL " + ", ".join(str(s[6]) for s in show))
    return lines


def ending_assets(charset: bytes, font: list[int]) -> tuple[bytes, list[str]]:
    """Set di caratteri del finale (2 KB) e le sue costanti (ending.inc)."""
    keep = {0} | {c for c in font if c}
    tiles: dict[int, Tile] = {c: tuple(charset[8 * c : 8 * c + 8]) for c in keep}
    fw_codes = range(END_FW_BASE, END_FW_BASE + 16 * END_FW_COLORS)
    for color in range(END_FW_COLORS):
        for mask in range(16):
            tiles[END_FW_BASE + 16 * color + mask] = fw_glyph(color, mask) if mask else (0,) * 8
    free = [c for c in range(1, 256) if c not in keep and c not in fw_codes]
    index: dict[Tile, int] = {}

    def add(tile: Tile) -> int:
        if not any(tile):
            return 0
        if tile in index:
            return index[tile]
        code = free.pop(0)
        tiles[code] = tile
        index[tile] = code
        return code

    lines = ["; Generato da tools/gen_c64_assets.py: non modificare a mano.", "",
             "; finale di CHALLENGE (src/ending.s): set di caratteri ending_chars.bin", ""]
    # lettere 2x: quattro segnaposto di fila per lettera (alto sinistra, alto destra, basso
    # sinistra, basso destra) da END_BIG_BASE
    end_big = "".join(sorted(set("".join(END_BIG_TEXTS)) - {" "}))
    assert all(c in FONT_DRAWN for c in end_big), end_big
    big = []
    for k in range(len(end_big)):
        quarter = [END_BIG_BASE + 4 * k + q for q in range(4)]
        assert all(c in free for c in quarter), "finale: lettere 2x sopra altri caratteri"
        for c in quarter:
            free.remove(c)
            tiles[c] = BLANK
        big.append(quarter)
    # indice della lettera grande per ASCII 32-95 (0 = spazio)
    idx = [end_big.index(ch) + 1 if ch in end_big else 0 for ch in FONT_CHARS]
    font_map = {ch: font[i] for i, ch in enumerate(FONT_CHARS)}
    lines.append(f"END_BIG_BASE = {END_BIG_BASE}    ; lettere 2x: quattro caratteri per lettera da qui")
    lines.append(f"END_BIG_N = {len(end_big)}")
    lines.append("; lettere 2x: il carattere del font da cui si fanno (big_build)")
    lines.append(".define END_BIG_SRC " + ", ".join(str(font_map[ch]) for ch in end_big))
    lines.append("; scala 2: indice (da 1) per ASCII 32-95, poi i caratteri in alto a sinistra, in alto")
    lines.append("; a destra, in basso a sinistra, in basso a destra (indice 0 = spazio)")
    lines.append(".define END_BIG_IDX " + ", ".join(str(i) for i in idx))
    for q, name in enumerate(("TL", "TR", "BL", "BR")):
        lines.append(f".define END_BIG_{name} 0, " + ", ".join(str(b[q]) for b in big))
    stamp = stamp_pixels()
    codes = [add(t) for row in tiles_of(stamp, END_STAMP_W, END_STAMP_H) for t in row]
    lines.append(f"END_STAMP_W = {END_STAMP_W}")
    lines.append(f"END_STAMP_H = {END_STAMP_H}")
    lines.append(".define END_STAMP " + ", ".join(str(c) for c in codes))
    lines.append(f"END_FW_BASE = {END_FW_BASE}    ; fuochi: base + colore * 16 + quadranti (multicolore)")
    lines.append(f"END_CHARS_USED = {256 - len(free)}")
    lines += credits_tables() + fireworks_tables()
    out = bytearray(2048)
    for c, t in tiles.items():
        out[8 * c : 8 * c + 8] = bytes(t)
    return bytes(out), lines


OMEGA_VOICE_MAX = 2760   # campioni del nome di OMEGA nel suo file voce (fino a VOL_TAB: src/voice.s)


def voice_files() -> dict[str, bytes]:
    """Campioni delle voci di CHALLENGE, uno per tipo di racchetta: i .raw4 come sono (16 livelli in
    due nibble, 8 = silenzio), controllati perché il player li suona fino all'ultimo byte."""
    files = {}
    # coda quasi muta: campioni a 7-9, cioè al più un passo dal silenzio
    quiet = lambda b: 7 <= b >> 4 <= 9 and 7 <= b & 15 <= 9

    def trimmed(raw: bytes) -> bytes:
        end = len(raw)
        while end > 1 and quiet(raw[end - 1]):
            end -= 1
        return raw[:end]

    # i nomi senza la coda quasi muta: con il player che scala i campioni al VOLUME del menu
    # (VOL_TAB di src/voice.s) il file del primo livello non ci sta più nelle sue 16 pagine
    for kind, name in enumerate(VOICE_NAMES):
        raw = (VOICES / f"{name.lower()}.raw4").read_bytes()
        assert raw, name    # (che con il player stia in VOICE_PAGES pagine lo controlla voice.s)
        files[f"voice{kind}.bin"] = trimmed(raw)
    # OMEGA (il file voce in più, VOICE_KIND = 7 di src/voice.s): il suo nome è lungo (1,13 s) e
    # fra VOICE_BASE e la tabella del volume (VOL_TAB) ci sta solo senza la coda quasi muta,
    # tolta fino a OMEGA_VOICE_MAX byte
    raw = (VOICES / "omega.raw4").read_bytes()
    end = len(raw)
    while end > OMEGA_VOICE_MAX and quiet(raw[end - 1]):
        end -= 1
    assert end <= OMEGA_VOICE_MAX, f"omega.raw4: {end} byte oltre la coda muta, più di {OMEGA_VOICE_MAX}"
    files[f"voice{len(VOICE_NAMES)}.bin"] = raw[:end]
    # READY e GO del conto alla rovescia, uguali per tutti: solo nel file del primo livello; YOU
    # WIN e PERFECT nel banco della vittoria (tools/make_crt.py), per il GAME OVER e il finale.
    # READY e GO senza la coda quasi muta, come i nomi
    for name in ("ready", "go", "you_win", "perfect"):
        raw = (VOICES / f"{name}.raw4").read_bytes()
        assert raw, name
        files[f"{name}.bin"] = trimmed(raw) if name in ("ready", "go") else raw
    return files


# ------------------------------------------------------------------ HOW TO PLAY

# palette del C64 (Pepto) per scegliere i due colori di ogni cella
C64_RGB = [(0, 0, 0), (255, 255, 255), (104, 55, 43), (112, 164, 178), (111, 61, 134), (88, 141, 67),
           (53, 40, 121), (184, 199, 111), (111, 79, 37), (67, 57, 0), (154, 103, 89), (68, 68, 68),
           (108, 108, 108), (154, 210, 132), (108, 94, 181), (149, 149, 149)]
C_BLACK, C_WHITE, C_RED, C_YELLOW, C_BROWN, C_LRED, C_DGRAY, C_GRAY, C_LGRAY = 0, 1, 2, 7, 9, 10, 11, 12, 15
# disposizione a 320x200 (quella del MiSTer è a 240 righe): riquadri delle mosse da y0 - 4 a
# y0 + 58, comando sulla riga y0 + 42. Le scritte stanno nelle celle (riga, colonna), con il font
# della ROM: le scrive il programma (HT_TEXTS), qui le loro celle restano vuote, con i colori
HT_BOX_Y0 = [32, 96]
HT_BARS_Y = 161
HT_SHOT_X = 234                  # riquadro del tiro, fino a x = HT_SHOT_X1 (il bordo e la racchetta in celle diverse)
HT_SHOT_X1 = 306
HT_PLUS_X = 124                  # centro del "+" fra i joystick e il pulsante (disegnato)
HT_LABEL_COL = 20                # FIRE accanto al pulsante
# scritte: (colonna, riga, 2x, colore del C64, testo); un gruppo per frame del programma (al più
# una trentina di lettere, spazi compresi: circa 400 cicli l'una, e fuori dalla partita la musica
# nello stesso frame; sull'NTSC il frame ha 15.500 cicli)
HT_TEXTS = [
    [(14, 0, False, C_YELLOW, "HOW TO PLAY")],
    [(9, 2, False, C_GRAY, "SUPER MOVES - JOYSTICK")],
    [(2, 4, False, C_YELLOW, "STRAIGHT SHOT")],
    [(2, 6, False, C_WHITE, "NEXT SHOT FLAT AND FAST")],
    [(HT_LABEL_COL, 9, False, C_GRAY, "FIRE"),
     (2, 12, False, C_YELLOW, "RISING STRIKE"),
     (HT_LABEL_COL, 17, False, C_GRAY, "FIRE")],
    [(2, 14, False, C_WHITE, "FLAT SHOT WITH A LATE BREAK")],
    [(2, 20, False, C_WHITE, "HALF"),
     (13, 20, False, C_WHITE, "= MOVE"),
     (20, 20, False, C_WHITE, "FULL"),
     (30, 20, False, C_YELLOW, "= MAX")],
    [(1, 22, False, C_GRAY, "FIRE: USE THE BONUS     ")],
    [(25, 22, False, C_GRAY, "FORWARD: DASH")],
    [(11, 24, False, C_GRAY, "PRESS FIRE TO SKIP")],
]


def c64_stick(img: Image.Image, cx: int, cy: int, way: str) -> None:
    """Joystick come howto.stick, ma sulla griglia delle celle 8x8 della bitmap hires (due colori
    per cella): pallina nelle due righe di celle sopra quella di cy, base nella riga sotto, asta
    dalla base alla pallina (howto_image la colora come la cella in cui passa). Niente riflesso
    bianco sulla pallina: sarebbe il terzo colore della cella."""
    d = ImageDraw.Draw(img)
    row = cy // 8 * 8                  # prima riga di pixel della cella di cy
    base_top = row + 8
    d.rounded_rectangle((cx - 11, base_top, cx + 11, base_top + 6), 2, fill=howto.S_DARK)
    d.ellipse((cx - 5, base_top, cx + 5, base_top + 3), fill=howto.S_HOLE)
    dx, dy = howto.DIRS[way]
    bx, by = cx + dx * 7, row + 2 - (1 - dy) * 5
    d.line((cx, base_top + 1, bx, by), fill=howto.S_SHAFT, width=2)
    d.ellipse((bx - 5, by - 5, bx + 5, by + 5), fill=howto.S_BALL)


def c64_button(img: Image.Image, cx: int, cy: int) -> None:
    """Pulsante sulla griglia delle celle, come i joystick (c64_stick): un rettangolo rosso nelle
    righe di celle fino a quella di cy, la base grigia nella riga sotto."""
    d = ImageDraw.Draw(img)
    row = cy // 8 * 8
    base_top = row + 8
    d.rounded_rectangle((cx - 11, base_top, cx + 11, base_top + 4), 2, fill=howto.S_DARK)
    d.rectangle((cx - 8, row + 2, cx + 8, row + 7), fill=howto.S_RED)


def howto_text_cells() -> dict[tuple[int, int], int]:
    """Celle (riga, colonna) delle scritte di HT_TEXTS e il loro colore."""
    cells = {}
    for group in HT_TEXTS:
        for col, row, big, color, text in group:
            k = 2 if big else 1
            assert all(c == " " or c in FONT_DRAWN for c in text) and col + k * len(text) <= 40, text
            for i in range(k * len(text)):
                for r in range(k):
                    assert (row + r, col + i) not in cells, f"HOW TO PLAY: scritte sovrapposte ({text})"
                    cells[(row + r, col + i)] = color
    return cells


def howto_image() -> list[list[int]]:
    """La schermata a 320x200 in colori del C64 (un indice per pixel), prima della conversione,
    senza le scritte (le loro celle sono vuote: howto_text_cells)."""
    w, h = 320, 200
    figs = Image.new("L", (w, h), 0)      # codici howto.S_*
    lines = Image.new("L", (w, h), 0)     # colori del C64 + 1 (0 = niente)
    dl = ImageDraw.Draw(lines)
    steps, _, fire_x, _ = howto.command_x(True)
    for i, y0 in enumerate(HT_BOX_Y0):
        cy = y0 + 42
        dl.rectangle((8, y0 - 4, 311, y0 + 58), outline=C_GRAY + 1)
        for k, (x, way) in enumerate(zip(steps, howto.JOY_STEPS[i])):
            c64_stick(figs, x, cy, way)
            if k < len(steps) - 1:
                # freccia nella prima cella dopo la pallina più a destra (x + 12), nella riga di
                # celle di cy: mai nella stessa cella di una pallina o di una base
                ax = ((x + 12) // 8 + 1) * 8
                ay = cy // 8 * 8 + 4
                dl.polygon([(ax, ay - 3), (ax + 4, ay), (ax, ay + 3)], fill=C_YELLOW + 1)
        # il "+" (7x7) nella cella di HT_PLUS_X, nella riga di celle di cy
        py = cy // 8 * 8 + 4
        dl.line((HT_PLUS_X - 3, py, HT_PLUS_X + 3, py), fill=C_WHITE + 1)
        dl.line((HT_PLUS_X, py - 3, HT_PLUS_X, py + 3), fill=C_WHITE + 1)
        c64_button(figs, fire_x, cy)
        # il tiro: racchetta, palla gialla e la sua strada (dritta e veloce, o che poi s'impenna)
        x0, x1 = HT_SHOT_X, HT_SHOT_X1
        dl.rectangle((x0, y0 + 6, x1, y0 + 54), outline=C_GRAY + 1)
        py = y0 + 30
        dl.rectangle((x0 + 6, py - 8, x0 + 7, py + 8), fill=C_WHITE + 1)
        if i == 0:
            for dy in (-2, 0, 2):
                dl.line((x0 + 14, py + dy, x0 + 50, py + dy), fill=C_YELLOW + 1)
            dl.rectangle((x0 + 56, py - 2, x0 + 59, py + 1), fill=C_YELLOW + 1)
        else:
            for x in range(x0 + 14, x0 + 50, 4):
                dl.point((x, py), fill=C_YELLOW + 1)
            for k in range(1, 4):
                dl.point((x0 + 50 + 4 * k, py - 4 * k), fill=C_YELLOW + 1)
            dl.rectangle((x0 + 64, py - 15, x0 + 67, py - 12), fill=C_YELLOW + 1)
    # costo: mezza barra = mossa, barra piena = MAX (le scritte accanto in HT_TEXTS)
    y = HT_BARS_Y
    for x, fill in ((58, 18), (196, 36)):
        dl.rectangle((x, y, x + 37, y + 5), outline=C_YELLOW + 1)
        dl.rectangle((x + 1, y + 1, x + fill, y + 4), fill=C_YELLOW + 1)
        dl.line((x + 19, y - 1, x + 19, y + 6), fill=C_YELLOW + 1)
    # joystick: base e asta in un grigio solo (con il nero, due colori per cella); l'asta rossa
    # nelle celle della pallina
    scol = {howto.S_DARK: C_GRAY, howto.S_HOLE: C_BLACK, howto.S_SHAFT: C_GRAY, howto.S_BALL: C_RED,
            howto.S_BASE_EDGE: C_GRAY, howto.S_WHITE: C_WHITE, howto.S_RED: C_RED, howto.S_RED_DARK: C_BROWN,
            howto.S_RED_LIGHT: C_LRED}
    out = [[0] * w for _ in range(h)]
    for yy in range(h):
        for xx in range(w):
            if v := figs.getpixel((xx, yy)):
                out[yy][xx] = scol[v]
            elif v := lines.getpixel((xx, yy)):
                out[yy][xx] = v - 1
    for cy in range(h // 8):
        for cx in range(w // 8):
            cell = [(cx * 8 + x, cy * 8 + y) for y in range(8) for x in range(8)]
            if any(figs.getpixel(p) == howto.S_BALL for p in cell):
                for x, y in cell:
                    if figs.getpixel((x, y)) == howto.S_SHAFT:
                        out[y][x] = C_RED
    # le celle delle scritte devono essere vuote: le riempie il programma
    for (row, col) in howto_text_cells():
        assert not any(out[row * 8 + y][col * 8 + x] for y in range(8) for x in range(8)), \
            f"HOW TO PLAY: disegno nella cella di una scritta ({row}, {col})"
    return out


# riga di celle della bitmap, vuota e nera, che porta le scritte (howto_text_bytes): il programma le
# legge da lì (HT_TEXTS_AT) e le scrive nelle loro celle, così non stanno nella sua memoria
HT_DATA_ROW = 1


def howto_text_bytes() -> bytes:
    """Le scritte di HT_TEXTS come le legge il programma: per scritta colonna (bit 7: 2x), riga,
    testo in ASCII, 0; $FE alla fine di ogni gruppo (un frame), $FF alla fine."""
    out = bytearray()
    for group in HT_TEXTS:
        for col, row, big, _, text in group:
            out += bytes([col | (0x80 if big else 0), row]) + text.encode("ascii") + bytes(1)
        out.append(0xFE)
    out[-1] = 0xFF
    assert len(out) <= 320, "HOW TO PLAY: scritte oltre una riga di celle"
    return bytes(out)


def howto_texts() -> list[str]:
    """Per assets.inc: quanti gruppi di scritte e dove sono, nella bitmap copiata a $E000."""
    return ["; HOW TO PLAY: scritte nella riga HT_DATA_ROW della bitmap, vuota e nera (colonna, con il",
            "; bit 7 a 2x; riga; testo; 0), $FE alla fine di ogni frame di disegno, $FF alla fine (i",
            "; colori sono già in howto.bin)",
            f"HT_GROUPS = {len(HT_TEXTS)}",
            f"HT_TEXTS_AT = ${0xE000 + HT_DATA_ROW * 320:04X}"]


def howto_bitmap() -> tuple[bytes, bytes, list[list[int]]]:
    """Bitmap hires (8.000 byte) e colori (1.000): per ogni cella 8x8 i due colori che rendono
    meglio i suoi pixel (il nero compreso), ogni pixel al più vicino. Anche l'immagine risultante."""
    img = howto_image()
    text_cells = howto_text_cells()

    def dist(a: int, b: int) -> int:
        return sum((p - q) ** 2 for p, q in zip(C64_RGB[a], C64_RGB[b]))

    bitmap, colors = bytearray(8000), bytearray(1000)
    shown = [[0] * 320 for _ in range(200)]
    for cy in range(25):
        for cx in range(40):
            px = [img[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]
            if (cy, cx) in text_cells:
                # scritta: il suo colore sul nero, i pixel li mette il programma
                colors[cy * 40 + cx] = text_cells[(cy, cx)] << 4 | C_BLACK
                continue
            used = sorted(set(px) | {C_BLACK})
            best = None
            for i, a in enumerate(used):
                for b in used[i:]:
                    err = sum(min(dist(p, a), dist(p, b)) for p in px)
                    if best is None or err < best[0]:
                        best = (err, a, b)
            _, a, b = best
            fg, bg = (a, b) if a != C_BLACK else (b, a)
            colors[cy * 40 + cx] = fg << 4 | bg
            for y in range(8):
                byte = 0
                for x in range(8):
                    p = px[y * 8 + x]
                    on = dist(p, fg) < dist(p, bg)
                    byte |= on << (7 - x)
                    shown[cy * 8 + y][cx * 8 + x] = fg if on else bg
                bitmap[(cy * 40 + cx) * 8 + y] = byte
    # ogni cella al più con due colori (il nero compreso): sul C64 si vede il disegno esatto
    bad = [(cy, cx) for cy in range(25) for cx in range(40)
           if any(shown[cy * 8 + y][cx * 8 + x] != img[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8))]
    assert not bad, f"HOW TO PLAY: celle (riga, colonna) con più di due colori {bad}"
    return bytes(bitmap), bytes(colors), shown


def howto_file() -> bytes:
    """howto.bin: 31 pagine di bitmap ($E000-$FEFF) e una vuota, i colori e quelli dell'easter egg
    (giallo e rosso scambiati), 4 pagine ciascuno. Le ultime 8 celle (da $FF00, sotto le variabili
    a $FF40) non si copiano: devono essere vuote, con i colori a 0. Nella riga HT_DATA_ROW, vuota e
    con i colori a 0 (nero su nero: non si vede), le scritte (howto_text_bytes)."""
    bitmap, colors, _ = howto_bitmap()
    assert not any(bitmap[0x1F00:]), "HOW TO PLAY: ultime celle non vuote"
    at = HT_DATA_ROW * 320
    row_colors = colors[HT_DATA_ROW * 40:HT_DATA_ROW * 40 + 40]
    assert not any(bitmap[at:at + 320]) and not any(row_colors), "HOW TO PLAY: la riga delle scritte non è vuota e nera"
    assert all(row != HT_DATA_ROW for row, _ in howto_text_cells()), "HOW TO PLAY: una scritta nella riga dei dati"
    texts = howto_text_bytes()
    bitmap = bitmap[:at] + texts + bitmap[at + len(texts):]
    colors = bytearray(colors)
    colors[992:] = bytes(8)
    swap = {C_YELLOW: C_RED, C_RED: C_YELLOW}
    egg = bytes(swap.get(c >> 4, c >> 4) << 4 | swap.get(c & 15, c & 15) for c in colors)
    pad = bytes(24)
    return bitmap[:0x1F00] + bytes(256) + bytes(colors) + pad + egg + pad


# ------------------------------------------------------------------ titoli disegnati
#
# Le scritte disegnate a pixel delle altre versioni (assets/titles, tools/gen_title_assets.py): i
# nomi dei sette avversari nelle presentazioni di CHALLENGE, la targa di HERE COMES A NEW
# CHALLENGER! e PERFECT del GAME OVER. Qui diventano caratteri hires, un colore per cella 8x8 sul
# nero: ombre, scie e contorni si tolgono, le parti di colore diverso vanno in celle diverse (le
# fasce di PERFECT e di A NEW CHALLENGER! allineate alle righe di celle, le lettere di TWIST una per
# colonna, le travi di TITAN nelle loro righe), il rosso della targa è fatto da quattro sprite
# dietro i caratteri. Il set è pieno: i caratteri li copia dalla cartuccia (titles.bin, nel file del
# finale: challenge.s) solo chi li mostra, su uno schermo appena pulito, al posto di caratteri che
# lì non si vedono:
#   - un nome o PERFECT: una pagina, i caratteri da TN_FIRST (128-159), che fuori dalla scelta dei
#     bonus restano vuoti (il nome lo copia in_draw di intro.s, PERFECT il GAME OVER in play.s);
#   - la targa: due pagine da TC_FIRST (64-127), sopra le lettere 2x, che le scelte dello sfidante
#     (subito dopo) rifanno; negli ultimi otto caratteri l'immagine dello sprite (TC_SPRITE).
TITLES = ROOT / "assets" / "titles"
TITLE_SPEC = json.loads((TITLES / "titles.json").read_text(encoding="utf-8"))
ROLE = {name: i for i, name in enumerate(TITLE_SPEC["palette"])}
R_WHITE, R_YELLOW, R_DYELLOW = ROLE["white"], ROLE["yellow"], ROLE["dark_yellow"]
R_GRAY, R_DGRAY, R_RED, R_DRED = ROLE["gray"], ROLE["dark_gray"], ROLE["red"], ROLE["dark_red"]
C_ORANGE = 8
TN_FIRST = 128           # nomi e PERFECT: caratteri 128-159, una pagina
TN_CHARS = 32
TC_FIRST = 64            # targa: caratteri 64-127, due pagine
TC_SPRITE = 120          # i suoi ultimi 8: l'immagine dello sprite (64 byte)
TC_W, TC_H = 24, 5       # targa in celle
TC_RED_X0, TC_RED_X1 = 3, 188    # il rosso dentro il bordo: pixel della targa (gli sprite)
TC_RED_Y0, TC_RED_Y1 = 6, 33

Point = tuple[int, int, int]     # x, y (pixel nelle celle della grafica), colore del C64


def title_roles(name: str) -> list[list[int]]:
    """Ruoli (indici della palette di titles.json) dei pixel della grafica `name`."""
    info = TITLE_SPEC["titles"][name]
    im = Image.open(TITLES / info["file"])
    assert im.mode == "P" and list(im.size) == info["size"], name
    w, h = im.size
    return [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]


def title_points(px: list[list[int]], colors: dict[int, int], ox: int = 0, oy: int = 0, rows=None, cols=None) -> list[Point]:
    """I pixel di `px` dei ruoli in `colors` (ruolo -> colore del C64; gli altri ruoli si tolgono),
    spostati di (ox, oy); rows e cols danno le righe e la colonna d'arrivo di ogni riga e colonna
    (per togliere o raddoppiare righe, spostare lettere)."""
    out = []
    for y, row in enumerate(px):
        for yy in (rows(y) if rows else [y]):
            for x, r in enumerate(row):
                if r in colors:
                    out.append(((cols(x) if cols else x) + ox, yy + oy, colors[r]))
    return out


def title_cells(points: list[Point], w: int, h: int, prio: list[int]) -> dict[tuple[int, int], tuple[Tile, int]]:
    """Celle (colonna, riga) -> (carattere, colore) dei punti in w x h celle. In una cella con più
    colori resta il primo di `prio` (gli altri pixel si perdono: le scie di BLASTER e RUSH); senza
    nessuno di `prio` la cella non va."""
    by: dict[tuple[int, int], list[Point]] = {}
    for x, y, c in points:
        assert 0 <= x < 8 * w and 0 <= y < 8 * h, (x, y, w, h)
        by.setdefault((x // 8, y // 8), []).append((x % 8, y % 8, c))
    cells = {}
    for cell, pts in by.items():
        used = {c for _, _, c in pts}
        keep = used.pop() if len(used) == 1 else next((c for c in prio if c in used), None)
        assert keep is not None, f"cella {cell} con i colori {used}"
        tile = [0] * 8
        for x, y, c in pts:
            if c == keep:
                tile[y] |= 0x80 >> x
        cells[cell] = (tuple(tile), keep)
    return cells


def title_name(kind: str) -> tuple[list[Point], int, int, int, list[int]]:
    """Il nome di un avversario: punti, celle (larghezza, altezza), prima riga dello schermo,
    priorità dei colori. Le grafiche stanno fra le righe 10 e 14, con la parte bassa 6-10 pixel
    sopra il motto (riga 15 di intro.s); le righe dipendono dalla forma."""
    px = title_roles(f"name_{kind.lower()}")
    wy = {R_WHITE: C_WHITE, R_YELLOW: C_YELLOW}
    if kind == "ARCADE":
        # bianco in alto e giallo in basso, la metà proprio a una riga di celle; senza l'ombra
        return title_points(px, wy, ox=3), 8, 2, 12, [C_WHITE]
    if kind == "TITAN":
        # le lettere fra le travi gialle, ognuna nella sua riga di celle (le travi di due righe)
        def rows(y: int) -> list[int]:
            return [y + 5] if y < 2 else [] if y == 2 else [y + 6] if y < 24 else [y + 8]
        return title_points(px, wy | {R_DYELLOW: C_YELLOW}, ox=2, rows=rows), 6, 5, 10, [C_WHITE]
    if kind == "HAMMER":
        # senza l'ombra; i colpi gialli ai lati in colonne di celle loro
        return title_points(px, wy, ox=4), 11, 2, 12, [C_WHITE]
    if kind == "TWIST":
        # le lettere (bianche e gialle a turno) una per colonna di celle, più strette
        spans = [(0, 5, 1), (9, 15, 8), (20, 25, 17), (29, 35, 24), (40, 45, 33)]

        def cols(x: int) -> int:
            return next(d + x - a for a, b, d in spans if a <= x <= b)
        return title_points(px, wy, oy=4, cols=cols), 5, 3, 11, [C_WHITE]
    if kind == "BLASTER":
        # il bianco delle prime quattro righe in una riga di celle sua; le scie che finiscono in
        # celle gialle diventano gialle
        return title_points(px, wy | {R_GRAY: C_GRAY}, ox=4, oy=4), 12, 3, 12, [C_YELLOW, C_WHITE, C_GRAY]
    if kind == "RUSH":
        # le scie grigie solo dove non ci sono lettere
        return title_points(px, wy | {R_GRAY: C_GRAY, R_DGRAY: C_DGRAY}, ox=2), 7, 2, 12, [C_WHITE, C_GRAY, C_DGRAY]
    if kind == "OMEGA":
        # senza le ombre (rosso scuro): il sigillo giallo con le gambe rosse e le due barre rosse
        # nelle prime due righe di celle, OMEGA bianco nelle due sotto (le righe vuote tolte)
        def rows(y: int) -> list[int]:
            return [y] if y < 14 else [] if y < 18 else [y - 2] if y < 32 else []
        pts = title_points(px, {R_WHITE: C_WHITE, R_YELLOW: C_YELLOW, R_RED: C_RED}, rows=rows)
        return pts, 10, 4, 11, [C_WHITE, C_YELLOW, C_RED]
    assert kind == "GUARDIAN", kind
    # la malta nera nelle righe dei corsi di mattoni, piena (gialla) nei giunti: le lettere si
    # leggono meglio
    mortar = {y for y, row in enumerate(px) if row.count(R_DYELLOW) > row.count(R_YELLOW)}
    pts = [p for p in title_points(px, {R_YELLOW: C_YELLOW, R_DYELLOW: C_YELLOW}, ox=2)
           if p[1] not in mortar or px[p[1]][p[0] - 2] == R_YELLOW]
    return pts, 10, 2, 12, [C_YELLOW]


def title_perfect() -> tuple[list[Point], int, int]:
    """PERFECT: senza il contorno, le tre fasce (bianca, gialla, giallo scuro arancio) una per riga
    di celle (la gialla con una riga ripetuta, la scura con due), la riga gialla sotto nella quarta."""
    px = title_roles("perfect")

    def rows(y: int) -> list[int]:
        if 1 <= y <= 14:
            return [y - 1]
        if y == 15:
            return [14, 15]
        if y in (16, 17):
            return [2 * y - 16, 2 * y - 15]
        if 18 <= y <= 21:
            return [y + 2]
        return [25] if y == 24 else []
    # (la riga sotto è gialla come la fascia di mezzo)
    pts = title_points(px, {R_WHITE: C_WHITE, R_YELLOW: C_YELLOW, R_DYELLOW: C_ORANGE}, ox=2, rows=rows)
    return pts, 15, 4


def title_plate() -> list[Point]:
    """La targa in 24 x 5 celle: il bordo (giallo, la riga scura in mezzo tolta), HERE COMES bianca
    e A NEW CHALLENGER! bianca sopra e gialla sotto, la metà a una riga di celle; ombre e sfumature
    tolte (dove erano c'è il rosso degli sprite). Il bordo alto e HERE COMES in righe di celle
    diverse: le distanze fra le righe un po' più strette."""
    px = title_roles("challenger")
    w = len(px[0])
    ring = (R_YELLOW, R_DYELLOW)
    pts = []
    for y0, dy in ((0, 3), (34, -1)):       # angoli e bordo in alto e in basso
        for y in range(y0, y0 + 4):
            pts += [(x, y + dy, C_YELLOW) for x in range(w) if px[y][x] in ring]
    for y in range(7, 33):                  # i lati, come nella riga 10 della grafica
        pts += [(x, y, C_YELLOW) for x in list(range(3)) + list(range(w - 3, w)) if px[10][x] in ring]
    pts += [(x, y + 3, C_WHITE) for y in range(5, 12) for x in range(w) if px[y][x] == R_WHITE]
    pts += [(x, y + 1, C_WHITE if px[y][x] == R_WHITE else C_YELLOW)
            for y in range(17, 31) for x in range(3, w - 3) if px[y][x] in (R_WHITE, R_YELLOW)]
    assert {y + 1 for y in range(17, 31) for x in range(3, w - 3) if px[y][x] == R_YELLOW} == set(range(24, 32)), \
        "targa: la parte gialla di A NEW CHALLENGER! non è una riga di celle"
    return pts


def title_warning() -> list[Point]:
    """WARNING! (l'allarme prima di OMEGA) in 24 x 5 celle come la targa del nuovo sfidante, con il
    suo bordo: le lettere grandi bianche nelle righe di celle 1 e 2 e gialle nella 3 (sul PC la metà
    è più in alto: qui sta su una riga di celle), le ombre tolte."""
    px = title_roles("warning")
    w = len(px[0])
    ring = (R_YELLOW, R_DYELLOW)
    pts = []
    for y0, dy in ((0, 3), (34, -1)):       # angoli e bordo in alto e in basso, come la targa
        for y in range(y0, y0 + 4):
            pts += [(x, y + dy, C_YELLOW) for x in range(w) if px[y][x] in ring]
    for y in range(7, 33):
        pts += [(x, y, C_YELLOW) for x in list(range(3)) + list(range(w - 3, w)) if px[10][x] in ring]
    pts += [(x, y + 1, C_WHITE if y + 1 < 24 else C_YELLOW)
            for y in range(7, 31) for x in range(3, w - 3) if px[y][x] in (R_WHITE, R_YELLOW)]
    return pts


def title_codes(cells: dict[tuple[int, int], tuple[Tile, int]], w: int, h: int, first: int,
                order=None) -> tuple[list[Tile], list[int], list[int]]:
    """Caratteri (diversi, nell'ordine `order` dei colori se c'è), codici da `first` e colori delle
    celle riga per riga (vuote: 0 e 0)."""
    keys = sorted(cells, key=lambda k: (k[1], k[0]))
    if order:
        keys.sort(key=lambda k: order.index(cells[k][1]))
    tiles: list[Tile] = []
    for k in keys:
        tile = cells[k][0]
        if any(tile) and tile not in tiles:
            tiles.append(tile)
    codes, colors = [], []
    for cy in range(h):
        for cx in range(w):
            tile, color = cells.get((cx, cy), ((0,) * 8, 0))
            codes.append(first + tiles.index(tile) if any(tile) else 0)
            colors.append(color if any(tile) else 0)
    return tiles, codes, colors


def title_assets(lines: list[str]) -> tuple[bytes, list[tuple[str, list[list[int]]]]]:
    """titles.bin (una pagina per nome nell'ordine di PaddleKind, una per PERFECT, due per la targa)
    e le costanti in assets.inc. Anche le immagini risultanti (colori del C64 per pixel), per
    vederle."""
    pages = bytearray()
    shown = []

    def image(cells: dict, w: int, h: int, back: set[tuple[int, int]] = frozenset()) -> list[list[int]]:
        img = [[C_RED if (x, y) in back else C_BLACK for x in range(8 * w)] for y in range(8 * h)]
        for (cx, cy), (tile, color) in cells.items():
            for y in range(8):
                for x in range(8):
                    if tile[y] & 0x80 >> x:
                        img[8 * cy + y][8 * cx + x] = color
        return img

    lines.append("")
    lines.append("; titoli disegnati (assets/titles): caratteri hires, un colore per cella. Nomi e PERFECT")
    lines.append("; da TN_FIRST (una pagina di titles.bin ciascuno), la targa da TC_FIRST (due pagine)")
    lines.append(f"TN_FIRST = {TN_FIRST}")
    lines.append(f"TC_FIRST = {TC_FIRST}")
    lines.append("; nomi: celle (larghezza, altezza), prima riga e colonna, y del centro (pixel), codici e")
    lines.append("; colori riga per riga (0: cella vuota)")
    for k, kind in enumerate(VOICE_NAMES):
        pts, w, h, row, prio = title_name(kind)
        cells = title_cells(pts, w, h, prio)
        tiles, codes, colors = title_codes(cells, w, h, TN_FIRST)
        assert len(tiles) <= TN_CHARS, f"{kind}: {len(tiles)} caratteri"
        assert 10 <= row and row + h <= 15, kind
        ys = [y for _, y, _ in pts]
        cy = 8 * row + (min(ys) + max(ys) + 1) // 2
        lines += [f"TN_{k}_W = {w}    ; {kind}, {len(tiles)} caratteri", f"TN_{k}_H = {h}", f"TN_{k}_ROW = {row}",
                  f"TN_{k}_COL = {(40 - w) // 2}", f"TN_{k}_CY = {cy}",
                  f".define TN_{k}_MAP " + ", ".join(map(str, codes)),
                  f".define TN_{k}_CLR " + ", ".join(map(str, colors))]
        pages += bytes(v for t in tiles for v in t).ljust(256, b"\0")
        shown.append((f"name_{kind.lower()}", image(cells, w, h)))
    # PERFECT: un colore per riga di celle (il riflesso del GAME OVER li cambia per riga)
    pts, w, h = title_perfect()
    cells = title_cells(pts, w, h, [C_WHITE])
    tiles, codes, colors = title_codes(cells, w, h, TN_FIRST)
    assert len(tiles) <= TN_CHARS, f"PERFECT: {len(tiles)} caratteri"
    row_colors = []
    for cy in range(h):
        used = {colors[cy * w + cx] for cx in range(w)} - {0}
        assert len(used) == 1, f"PERFECT: riga di celle {cy} con i colori {used}"
        row_colors.append(used.pop())
    lines += ["; PERFECT: celle, codici riga per riga, colore di ogni riga",
              f"TP_W = {w}    ; {len(tiles)} caratteri", f"TP_H = {h}",
              ".define TP_MAP " + ", ".join(map(str, codes)),
              ".define TP_ROWC " + ", ".join(map(str, row_colors))]
    pages += bytes(v for t in tiles for v in t).ljust(256, b"\0")
    shown.append(("perfect", image(cells, w, h)))
    # la targa: prima i caratteri bianchi, poi i gialli (il colore viene dal codice)
    cells = title_cells(title_plate(), TC_W, TC_H, [C_WHITE])
    tiles, codes, colors = title_codes(cells, TC_W, TC_H, TC_FIRST, order=[C_WHITE, C_YELLOW])
    assert TC_FIRST + len(tiles) <= TC_SPRITE, f"targa: {len(tiles)} caratteri"
    yellow0 = min(c for c, col in zip(codes, colors) if col == C_YELLOW)
    assert all((c >= yellow0) == (col == C_YELLOW) for c, col in zip(codes, colors) if c)
    # il rosso: quattro sprite hires espansi (48 x 2 pixel per pixel dell'immagine), il quarto
    # sovrapposto al terzo, dietro i caratteri; dove il rettangolo non è rosso c'è un carattere
    rows = (TC_RED_Y1 - TC_RED_Y0 + 1) // 2
    assert (TC_RED_Y1 - TC_RED_Y0 + 1) % 2 == 0 and rows <= 21
    sprite = bytes([0xFF] * 3 * rows).ljust(64, b"\0")
    width = TC_RED_X1 - TC_RED_X0 + 1
    sx = [TC_RED_X0 + 48 * i for i in range(3)] + [TC_RED_X1 + 1 - 48]
    assert 4 * 48 >= width and sx[3] > sx[2]
    red = {(x, y) for x in range(TC_RED_X0, TC_RED_X1 + 1) for y in range(TC_RED_Y0, TC_RED_Y1 + 1)}
    plate = image(cells, TC_W, TC_H, red)
    for y in (TC_RED_Y0, TC_RED_Y1):
        for x in (TC_RED_X0, TC_RED_X1):
            assert plate[y][x] == C_YELLOW, f"targa: angolo ({x}, {y}) del rosso fuori dal bordo"
    lines += ["; targa di HERE COMES A NEW CHALLENGER!: celle, codici riga per riga (da TC_YEL0 gialli,",
              "; prima bianchi), sprite del rosso (immagine a TC_SPRITE, righe espanse, x dal bordo",
              "; sinistro della targa, y dal bordo alto)",
              f"TC_W = {TC_W}    ; {len(tiles)} caratteri", f"TC_H = {TC_H}", f"TC_YEL0 = {yellow0}",
              f"TC_SPRITE = {TC_SPRITE}", f"TC_SPR_Y = {TC_RED_Y0}",
              *[f"TC_SPR_X{i} = {x}" for i, x in enumerate(sx)],
              ".define TC_MAP " + ", ".join(map(str, codes))]
    chars = bytearray(bytes(v for t in tiles for v in t).ljust(8 * (TC_SPRITE - TC_FIRST), b"\0")) + sprite
    assert len(chars) == 512
    pages += chars
    shown.append(("challenger", plate))
    # OMEGA: il nome (come quelli degli avversari) e WARNING! (come la targa, con lo stesso rosso)
    pts, w, h, row, prio = title_name("OMEGA")
    cells = title_cells(pts, w, h, prio)
    tiles, codes, colors = title_codes(cells, w, h, TN_FIRST)
    assert len(tiles) <= TN_CHARS, f"OMEGA: {len(tiles)} caratteri"
    ys = [y for _, y, _ in pts]
    lines += [f"TN_7_W = {w}    ; OMEGA, {len(tiles)} caratteri", f"TN_7_H = {h}", f"TN_7_ROW = {row}",
              f"TN_7_COL = {(40 - w) // 2}", f"TN_7_CY = {8 * row + (min(ys) + max(ys) + 1) // 2}",
              ".define TN_7_MAP " + ", ".join(map(str, codes)),
              ".define TN_7_CLR " + ", ".join(map(str, colors))]
    ttl_omega = len(pages) // 256
    pages += bytes(v for t in tiles for v in t).ljust(256, b"\0")
    shown.append(("name_omega", image(cells, w, h)))
    cells = title_cells(title_warning(), TC_W, TC_H, [C_WHITE])
    tiles, codes, colors = title_codes(cells, TC_W, TC_H, TC_FIRST, order=[C_WHITE, C_YELLOW])
    assert TC_FIRST + len(tiles) <= TC_SPRITE, f"WARNING: {len(tiles)} caratteri"
    yellow0 = min(c for c, col in zip(codes, colors) if col == C_YELLOW)
    assert all((c >= yellow0) == (col == C_YELLOW) for c, col in zip(codes, colors) if c)
    plate = image(cells, TC_W, TC_H, red)
    lines += ["; WARNING! prima di OMEGA: come la targa (stessi sprite del rosso), da TW_YEL0 gialli",
              f"TW_YEL0 = {yellow0}    ; {len(tiles)} caratteri", ".define TW_MAP " + ", ".join(map(str, codes))]
    ttl_warn = len(pages) // 256
    pages += bytes(bytes(v for t in tiles for v in t).ljust(8 * (TC_SPRITE - TC_FIRST), b"\0")) + sprite
    shown.append(("warning", plate))
    lines += ["; titles.bin: pagina del nome k (TTL_NAMES + k), di PERFECT, della targa (due), del nome di",
              "; OMEGA, di WARNING! (due)",
              "TTL_NAMES = 0", f"TTL_PERFECT = {len(VOICE_NAMES)}", f"TTL_PLATE = {len(VOICE_NAMES) + 1}",
              f"TTL_OMEGA = {ttl_omega}", f"TTL_WARN = {ttl_warn}",
              f"TTL_PAGES = {len(pages) // 256}"]
    return bytes(pages), shown


PAD_KINDS = ("arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian")
PAD_W = 12            # colonne doppie dello sprite multicolore
PAD_TILT = 3          # colonne di spostamento massimo dell'inclinazione della TWIST (pad_image)
PAD_ENGINE = 16       # aggancio motore nei PNG (editor delle racchette): non si disegna
PAD_ENGINES = (2, 2, 1, 1, 2, 1, 2)   # agganci motore per tipo, come sul PC
PAD_SLOTS = 8         # immagini per lato e tipo nel banco PAD_BANK (2 pagine)
PAD_ROWS = 21


def pad_anchors(name: str, px: list[list[int]], want: int) -> list[list[int]]:
    """Lo sprite senza gli agganci motore (indice 16: dove partirebbe la fiamma, colonna e righe del
    getto, nello spazio vuoto dietro lo scafo), dopo averli controllati: `want` gruppi in colonna,
    con il vuoto a sinistra e lo scafo a destra entro due colonne."""
    clean = [[0 if c == PAD_ENGINE else c for c in row] for row in px]
    groups = []
    for x in range(len(px[0])):
        for y in range(len(px)):
            if px[y][x] == PAD_ENGINE and (y == 0 or px[y - 1][x] != PAD_ENGINE):
                groups.append((x, y))
            if px[y][x] == PAD_ENGINE:
                assert not any(clean[y][: x + 1]), f"{name}.png: l'aggancio ({x}, {y}) non ha vuoto a sinistra"
                hull = next((i for i in range(x + 1, len(px[0])) if clean[y][i]), None)
                assert hull is not None and hull - x <= 2, f"{name}.png: l'aggancio ({x}, {y}) è lontano dallo scafo"
    assert len(groups) == want, f"{name}.png: {len(groups)} agganci motore, ne servono {want}"
    return clean


def pad_block(kind: int, data: list[int], n: int, thr: list[int]) -> tuple[bytes, bytes]:
    """Le immagini in partita NEXT del tipo `kind` per la racchetta sinistra e la destra (PAD_SLOTS da
    64 byte l'una), byte per byte come pad_image di video.s: per TWIST le 7 inclinazioni (posto =
    inclinazione + 3, righe spostate di (acc >> 3) colonne doppie), per BLASTER i 5 livelli del
    caricatore (%10 -> %01 nelle righe sopra la soglia), per gli altri l'immagine sola."""
    def image(rows: list[int]) -> bytes:
        return bytes(rows).ljust(3 * PAD_ROWS, b"\0").ljust(64, b"\0")

    def mirror(rows: list[int]) -> list[int]:
        out = []
        for y in range(0, len(rows), 3):
            v = rows[y] << 16 | rows[y + 1] << 8 | rows[y + 2]
            m = 0
            for c in range(12):
                m |= (v >> (2 * c) & 3) << (22 - 2 * c)
            out += [m >> 16, m >> 8 & 255, m & 255]
        return out

    variants: list[list[int]] = []
    if kind == 3:
        half = n >> 1
        for var in range(7):
            sign = var - 3
            tabs = abs(sign)
            acc = (tabs * -half) & 255
            rows = []
            for k in range(n):
                v = data[3 * k] << 16 | data[3 * k + 1] << 8 | data[3 * k + 2]
                sh = (acc - 256 if acc >= 128 else acc) >> 3
                if sign < 0:
                    sh = -sh
                acc = (acc + tabs) & 255
                v = (v >> 2 * sh if sh >= 0 else v << -2 * sh) & 0xFFFFFF
                rows += [v >> 16, v >> 8 & 255, v & 255]
            variants.append(rows)
    elif kind == 4:
        for level in range(len(thr)):
            rows = list(data)
            for k in range(min(n, thr[level])):
                for b in range(3):
                    x = rows[3 * k + b]
                    t = ((~(x << 1)) & x) & 0xAA
                    rows[3 * k + b] = x ^ (t | t >> 1)
            variants.append(rows)
    else:
        variants.append(list(data))
    assert len(variants) <= PAD_SLOTS
    left = b"".join(image(r) for r in variants).ljust(PAD_SLOTS * 64, b"\0")
    right = b"".join(image(mirror(r)) for r in variants).ljust(PAD_SLOTS * 64, b"\0")
    return left, right


def paddle_sprites() -> list[str]:
    """Le astronavi delle racchette di NEXT (assets/ships/sprites/c64/<tipo>.png, editor
    tools/paddle_editor.html): righe dello sprite multicolore viste dalla racchetta sinistra, 3
    byte per riga (indice della tavolozza = coppia di bit: %01 grigio, %10 colore del tipo, %11
    bianco). Nell'immagine la faccia sta alla colonna doppia fi (la hitbox sono fi - 1 e fi): il
    disegno si sposta tutto a sinistra, con almeno 4 colonne dietro la hitbox come la racchetta
    senza tipo, e la TWIST con PAD_TILT colonne libere per parte. La racchetta destra è lo
    specchio intero (colonna c -> 11 - c): lo sprite va PAD_DX_L / PAD_DX_R pixel prima della
    colonna della racchetta."""
    src = ROOT / "assets" / "ships" / "sprites" / "c64"
    params = (OUT / "params.inc").read_text(encoding="utf-8")
    kind_h = [int(v, 16) >> 16 for v in re.search(r"\.define T_KIND_H (.*)", params).group(1).replace("$", "").split(", ")]
    dx_l, dx_r, rows_n, out = [], [], [], []
    datas: list[list[int]] = []
    thr: list[int] = []
    for k, name in enumerate(PAD_KINDS):
        im = Image.open(src / f"{name}.png")
        assert im.mode == "P", f"{name}.png: serve un PNG a palette (editor delle racchette)"
        w, h = im.size
        want = ((kind_h[k] - 1) >> 1) + 1
        assert w == PAD_W and h == want, f"{name}.png: {w}x{h}, la racchetta del C64 è {PAD_W}x{want}"
        px = [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]
        # gli agganci motore (indice 16) non si disegnano
        px = pad_anchors(name, px, PAD_ENGINES[k])
        assert all(c < 4 for row in px for c in row), f"{name}.png: indici oltre 3 (servono le coppie di bit)"
        front = json.loads(im.info.get("paddedit", "{}")).get("front", 0)
        face = PAD_W - 1 - front
        used = [x for x in range(w) if any(px[y][x] for y in range(h))]
        margin = PAD_TILT if name == "twist" else 0
        fi = face - min(used) + margin
        if name != "twist":
            fi = max(fi, 5)
        shift = face - fi
        assert all(0 <= x - shift - margin and x - shift + margin < PAD_W for x in used), \
            f"{name}.png: il disegno non sta nelle {PAD_W} colonne dell'immagine"
        if name == "guardian":
            assert fi == 5, "GUARDIAN: lo scudo deve stare nelle colonne 4 e 5 (guard_gray)"
            seams = [y for y in range(h) if px[y][face - 1] == px[y][face] == 2]
            assert len(seams) == 4 and all(px[y][face - 1] == px[y][face] == 3 for y in range(h) if y not in seams), \
                "GUARDIAN: lo scudo vuole 4 giunture nel colore del tipo e il resto bianco"
        if name == "blaster":
            # caricatore: le righe con il colore del tipo si spengono dall'alto; al livello L restano
            # accese le ceil(L * g / 4) più in basso (soglia: la prima riga accesa)
            green = sorted((y for y in range(h) if 2 in px[y]), reverse=True)
            for lv in range(5):
                lit = -(-lv * len(green) // 4)
                thr.append(h if lit == 0 else 0 if lit == len(green) else green[lit - 1])
        dx_l.append(2 * (fi - 1))
        dx_r.append(2 * (PAD_W - 1 - fi))
        rows_n.append(h)
        data = []
        for row in px:
            img = [0] * PAD_W
            for x, c in enumerate(row):
                if c:
                    img[x - shift] = c
            for b in range(3):
                data.append((img[4 * b] << 6) | (img[4 * b + 1] << 4) | (img[4 * b + 2] << 2) | img[4 * b + 3])
        datas.append(data)
        out.append(f".define PAD_IMG_{name.upper()} " + ", ".join(f"${v:02X}" for v in data))
    # la racchetta senza tipo (Classic, EVO, allenamento): corpo bianco nelle colonne 4 e 5
    dx_l.append(8)
    dx_r.append(2 * (PAD_W - 1 - 5))
    # le immagini della partita NEXT, nella cartuccia (banco PAD_BANK): per tipo la sinistra e la
    # destra, 2 pagine l'una, copiate da pad_prep invece di farle con pad_image
    pads = bytearray()
    for k, data in enumerate(datas):
        left, right = pad_block(k, data, rows_n[k], thr)
        pads += left + right
    assert len(pads) == len(PAD_KINDS) * 4 * 256 <= 0x2000
    (OUT / "paddles.bin").write_bytes(bytes(pads))
    return [
        "; astronavi delle racchette di NEXT (assets/ships/sprites/c64): righe viste dalla racchetta",
        "; sinistra, 3 byte per riga; x dello sprite: colonna della racchetta - PAD_DX_L / PAD_DX_R",
        "; (per tipo, poi la racchetta senza tipo); PAD_BL_THR: prima riga accesa del BLASTER per",
        "; livello del caricatore (0-4)",
        ".define PAD_DX_L " + ", ".join(map(str, dx_l)),
        ".define PAD_DX_R " + ", ".join(map(str, dx_r)),
        ".define PAD_IMG_N " + ", ".join(map(str, rows_n)),
        ".define PAD_BL_THR " + ", ".join(map(str, thr)),
        *out,
    ]


def main() -> None:
    cs = Charset()
    lines: list[str] = ["; Generato da tools/gen_c64_assets.py: non modificare a mano.", ""]
    blank = cs.add((0,) * 8)
    # mezzeria: due pixel a cavallo tra le colonne 19 e 20 (x = 159 e 160), 4 righe accese e 4 spente
    line_l = cs.add((1, 1, 1, 1, 0, 0, 0, 0), unique=True)
    line_r = cs.add((0x80, 0x80, 0x80, 0x80, 0, 0, 0, 0), unique=True)
    # muro del singolo: x 298-301, colonna 37, pixel 2-5
    wall = cs.add((0x3C,) * 8, unique=True)
    lines += [
        f"CH_BLANK  = {blank}",
        f"CH_LINE_L = {line_l}    ; mezzeria, colonna 19",
        f"CH_LINE_R = {line_r}    ; mezzeria, colonna 20",
        f"CH_WALL   = {wall}    ; muro del singolo, colonna 37",
        "",
    ]
    digits = score_digits(cs)
    lines.append("; cifre del punteggio: 9 caratteri per cifra (3 righe di 3)")
    lines.append(".define SCORE_TILES " + ", ".join(str(c) for d in digits for c in d))
    # font 1x: segnaposto, poi i glifi della ROM (FONT_ROM: codice della ROM per carattere del
    # font, da FONT_FIRST)
    font = text_font(cs)
    lines.append("; font monospazio: codice del carattere per ASCII 32-95")
    lines.append(".define FONT_MAP " + ", ".join(str(c) for c in font))
    font_first, font_last = min(c for c in font if c), max(font)
    assert font_last - font_first + 1 == len(set(font) - {0}) == len(FONT_DRAWN), "font non contiguo"
    lines.append(f"FONT_FIRST = {font_first}")
    lines.append(f"FONT_CHARS = {font_last - font_first + 1}")
    lines.append("; font: codice nella ROM dei caratteri (set maiuscolo) dei caratteri da FONT_FIRST")
    by_code = {c: FONT_CHARS[i] for i, c in enumerate(font) if c}
    lines.append(".define FONT_ROM " + ", ".join(str(rom_code(by_code[c])) for c in range(font_first, font_last + 1)))
    # lettere 2x: quattro caratteri per lettera da PICK_FIRST (le pagine della scelta dei bonus:
    # lì le lettere 2x non si vedono), segnaposto riempiti da big_build con i glifi 1x già nel set
    assert len(cs.tiles) == PICK_FIRST, (len(cs.tiles), PICK_FIRST)
    letters = big2_letters()
    pick_range = range(PICK_FIRST, PICK_FIRST + PICK_PAGES * 32)
    assert 4 * len(letters) <= len(pick_range), f"lettere 2x: {len(letters)}, ne stanno {len(pick_range) // 4}"
    for _ in pick_range:
        cs.add(BLANK, unique=True)
    font_of = {ch: font[i] for i, ch in enumerate(FONT_CHARS)}
    lines.append("; lettere 2x (GAME OVER, YOU WIN): quattro caratteri per lettera da BIG2_FIRST (alto")
    lines.append("; sinistra, alto destra, basso sinistra, basso destra), ogni pixel 2x2 del carattere del")
    lines.append("; font BIG2_SRC; il resto delle pagine della scelta resta vuoto")
    lines.append(f"BIG2_FIRST = {PICK_FIRST}")
    lines.append(f"BIG2_N = {len(letters)}    ; {letters}")
    lines.append(".define BIG2_SRC " + ", ".join(str(font_of[ch]) for ch in letters))
    lines.append("; scritte del GAME OVER: larghezza (celle), celle per lettera (BIG_*_K), codici delle due righe")
    for name, (text, big) in BIG2_LISTS.items():
        if big:
            codes = big2_codes(PICK_FIRST, letters, text)
        else:
            codes = [font_of[ch] for ch in text] + [0] * len(text)
        lines.append(f"BIG_{name}_W = {len(codes) // 2}")
        lines.append(f"BIG_{name}_K = {2 if big else 1}")
        lines.append(f".define BIG_{name} " + ", ".join(str(c) for c in codes))
    # nella scelta dei bonus le metà delle lettere del font (codice + PICK_TOP la alta, abbassata di 4
    # pixel; + PICK_BOTTOM la bassa, in cima al carattere: pick_chars) nelle stesse pagine
    assert PICK_FIRST + 2 * len(FONT_DRAWN) <= pick_range.stop
    # auto-test: cursore a blocco e reticolo (righe ogni 16 pixel, l'ultima in fondo allo schermo)
    cursor = cs.add((0xF8,) * 8, unique=True)
    lines.append(f"CH_CURSOR = {cursor}")
    top, left_line = 0xFF, 0x80
    grid = {
        "GRID_TL": (top,) + (left_line,) * 7,
        "GRID_T": (top,) + (0,) * 7,
        "GRID_L": (left_line,) * 8,
        "GRID_TLB": (top,) + (left_line,) * 6 + (top,),
        "GRID_TB": (top,) + (0,) * 6 + (top,),
    }
    spare = [cursor]
    for name, tile in grid.items():
        code = cs.add(tile)
        if name == "GRID_T":
            grid_t = code
        else:
            spare.append(code)
        lines.append(f"CH_{name} = {code}")
    # caratteri per la capsula del BULLET in NEXT: cursore e reticolo (solo l'auto-test
    # dell'accensione) e tre caratteri suoi, vuoti fuori da NEXT. Non CH_GRID_T e il muro del
    # singolo: le scritte animate (riga del televisore, trattini, pavimento) e le entrate della
    # CHALLENGE li usano anche in partita NEXT e dopo
    self_test = list(spare)
    spare += [cs.add(BLANK, unique=True) for _ in range(3)]
    bullet_bytes, shot_own = next_chars(cs, lines, spare)
    # CHALLENGE: bande della schermata del nuovo sfidante (HERE COMES A NEW CHALLENGER!)
    lines.append(f"CH_SOLID = {cs.add((0xFF,) * 8, unique=True)}")
    # NEXT, mosse speciali: la barra, caratteri suoi (vuoti fuori da NEXT)
    bar = [cs.add(BLANK, unique=True) for _ in range(BAR_CHARS)]
    supers_assets(lines, bar)
    files = attract_assets(lines)
    # i caratteri presi dal BULLET e dalla barra non servono ad altro: quelli dell'auto-test dati una
    # volta sola, gli altri mai
    for c in self_test:
        assert cs.given.count(c) == 1, c
    for c in spare[len(self_test):] + bar:
        assert cs.given.count(c) == 1 and c not in pick_range, c
    assert grid_t not in spare and wall not in spare
    shot_assets(cs, lines, shot_own, letters, pick_range)
    lines.append(f"CHARSET_USED = {len(cs.tiles)}")
    OUT.mkdir(parents=True, exist_ok=True)
    charset = bytearray(2048)
    for i, t in enumerate(cs.tiles):
        charset[8 * i : 8 * i + 8] = bytes(t)
    (OUT / "charset.bin").write_bytes(bytes(charset))
    end_chars, end_lines = ending_assets(bytes(charset), font)
    (OUT / "ending_chars.bin").write_bytes(end_chars)
    (OUT / "ending.inc").write_text("\n".join(end_lines) + "\n", encoding="utf-8", newline="\n")
    # pagina $FF00: bitmap (vuota), caratteri del BULLET a $FF40, RTS a $FFC0 (VOICE_COUNT), poi
    # gli originali dei caratteri della barra delle mosse speciali (vuoti)
    page = bytearray(256)
    page[0x40:0xC0] = bullet_bytes
    page[0xC0] = 0x60
    page[BAR_ORIG : BAR_ORIG + 8 * BAR_CHARS] = bytes(charset[8 * bar[0] : 8 * (bar[0] + BAR_CHARS)])
    title = files["title.bin"]
    assert len(title) <= 0x800
    # nessun glifo della ROM nei file: i segnaposto sono vuoti
    assert not any(charset[8 * PICK_FIRST : 8 * pick_range.stop]) and not any(charset[8 * font_first : 8 * (font_last + 1)])
    (OUT / "pick_bank.bin").write_bytes(bytes(0x800) + bytes(page) + title + bytes(0x800 - len(title)))
    lines.append(f"PICK_FIRST = {PICK_FIRST}    ; scelta dei bonus: caratteri sostituiti (pagine intere)")
    lines.append(f"PICK_PAGES = {PICK_PAGES}")
    # sprite: palla 4x4, palla 6x6, due posti per le racchette (rifatte a ogni frame), linea di
    # 24 pixel e di 8 (il raster che scende sul logo), banda grigia EVO larga 4 pixel e alta 1-10
    # righe (non espansa, sopra la racchetta: la banda cade sulla riga esatta)
    line24, line8 = bytearray(64), bytearray(64)
    line24[0:3] = b"\xff\xff\xff"
    line8[0] = 0xFF
    bands = b"".join(sprite(4, h) for h in range(1, SPRITE_BANDS + 1))
    lines.append(f"SPRITE_BANDS = {SPRITE_BANDS}")
    # NEXT: capsule (8 più il SUPER in negativo) e icone del bonus armato (7, non il BULLET)
    nxt, nxt_lines = next_sprites()
    lines += nxt_lines
    sprites = sprite(4, 4) + sprite(6, 6) + bytes(128) + bytes(line24) + bytes(line8) + bands + nxt
    lines.append(f"SPRITES_N = {len(sprites) // 64}")
    (OUT / "sprites.bin").write_bytes(sprites)
    _, fx_lines = next_fx_sprites()
    lines += fx_lines
    lines += fx_squares()
    lines += howto_texts()
    lines += paddle_sprites()
    files |= voice_files()
    files["howto.bin"] = howto_file()
    files["titles.bin"], _ = title_assets(lines)
    for name, data in files.items():
        (OUT / name).write_bytes(data)
    # file che non si usano più
    for name in ("labels.bin", "credits.bin", "perfect_chars.bin"):
        (OUT / name).unlink(missing_ok=True)
    (OUT / "assets.inc").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"c64/gen: {len(cs.tiles)} caratteri su 256, {len(sprites) // 64} sprite, attract")


if __name__ == "__main__":
    main()
