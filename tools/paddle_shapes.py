"""Racchette dei personaggi di NEXT, pixel per pixel: il modello delle forme del MiSTer.

Ogni racchetta è lo sprite dell'astronave (assets/ships/sprites, letto da `ship`) più le animazioni
a codice attaccate ai suoi agganci, come `kind_ops` di rust/game/src/paddle_ui.rs e `ships.rs`, in
pixel arcade: x (`u`) con la faccia a 1 (la hitbox va da -3 a 1), negativa verso il retro; y (`v`)
dalla cima. Sul MiSTer la hitbox è larga 4 (`pw`): si toglie la colonna 0, quella subito dietro la
faccia (i pezzi che la coprono si accorciano, quelli davanti si spostano di 1), e la hitbox va da
-3 a 0. La racchetta destra è speculare. Un pixel prende il ruolo dello sprite, poi dell'ultimo
pezzo degli effetti che lo copre; sopra vanno le luci e le ombre dei bordi dei pezzi alti e larghi
almeno 2 pixel (l'ultimo vince), poi i pezzi "tardi". Dove non c'è niente, l'ombra portata: la
stessa forma 1 pixel verso il retro e 1 in basso.

Sprite: PNG a palette, l'indice è il ruolo (0 trasparente, poi i ruoli qui sotto fino a SIGNAL);
16-18 sono agganci (ENGINE, WEAPON, SPECIAL), mai disegnati: un pixel nel vuoto dove comincia un
effetto, in colonna per lo spessore. Il blocco tEXt "paddedit" dice quante colonne sporgono davanti
alla faccia (`front`, le canne del BLASTER).

Serve a tools/gen_mister_paddles.py (gli sprite e le costanti di kind_px), a tools/gen_mister_ui.py
(le anteprime della scelta e dello schermo VS) e a confrontare i frame dell'RTL (`kind_px` di
mister/rtl/next_render.v, che segue le stesse regole). TWIST si inclina come sul MiSTer, spostando
le righe (`twist_shift`), non ruotando.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from PIL import Image

# ruoli dei pixel (gli stessi codici di KR_* in next_render.v)
NONE, BODY, SHADE, MARK, MARK_DARK, MARK_LIGHT, GRAY, GRAY_LIGHT, DARK, DARK_DEEP, BLACK, SIGNAL, \
    SHADOW, GHOST1, GHOST2, GHOST3 = range(16)
# agganci negli sprite
ENGINE, WEAPON, SPECIAL = 16, 17, 18

KINDS = ("arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian")
ARCADE, TITAN, HAMMER, TWIST, BLASTER, RUSH, GUARDIAN = range(7)
SECTORS = 5
# GUARDIAN: colonne delle piastre fino alla faccia (dietro c'è il binario)
PLATE = 4

SPRITES = Path(__file__).resolve().parent.parent / "assets" / "ships" / "sprites"

# colori fissi (come paddle_ui.rs) e rampe del colore del personaggio
RGB = {
    SHADOW: (48, 48, 58), BODY: (255, 255, 255), SHADE: (212, 214, 224), GRAY: (180, 180, 180),
    GRAY_LIGHT: (226, 226, 230), DARK: (92, 92, 98), DARK_DEEP: (52, 52, 60), BLACK: (0, 0, 0),
    SIGNAL: (255, 210, 37),
}
MARKS = (MARK, MARK_DARK, MARK_LIGHT)


def mark_ramp(c: tuple[int, int, int]) -> dict[int, tuple[int, int, int]]:
    """Colore del personaggio, scurito (x 0,6) e schiarito (45% verso il bianco)."""
    return {MARK: c, MARK_DARK: tuple(round(v * 0.6) for v in c),
            MARK_LIGHT: tuple(round(v + (255 - v) * 0.45) for v in c)}


def body_shade(c: tuple[int, int, int]) -> tuple[int, int, int]:
    """Il corpo in ombra: il colore del corpo per (212, 214, 224) / 255."""
    return (round(c[0] * 212 / 255), round(c[1] * 214 / 255), round(c[2] * 224 / 255))


def jround(v: float) -> int:
    """Arrotondamento come `Math.round` e paddle_ui.rs: le metà verso l'alto."""
    return math.floor(v + 0.5)


# ------------------------------------------------------------------ sprite

@dataclass
class Anchor:
    """Aggancio: colonna u (faccia a 1), prima riga v, righe."""
    u: int
    v: int
    rows: int


@dataclass
class Ship:
    """Sprite di un'astronave, come `ships::Ship`: dimensioni del PNG, colonna della faccia, ruoli
    (agganci tolti), agganci dall'alto in basso, settori del GUARDIAN, colonna più a sinistra e
    righe dei pixel nel colore del personaggio fino alla faccia."""
    w: int
    h: int
    face: int
    px: list[int]
    engines: list[Anchor]
    weapons: list[Anchor]
    specials: list[Anchor]
    sectors: list[tuple[int, int]] | None
    mark_u0: int
    mark_rows: tuple[int, int]

    def u_of(self, x: int) -> int:
        return x - self.face + 1

    def u_range(self) -> tuple[int, int]:
        return self.u_of(0), self.u_of(self.w - 1)

    def front(self) -> int:
        """Colonne davanti alla faccia (agganci compresi)."""
        return self.w - 1 - self.face

    def at(self, u: int, v: int) -> int:
        x = u + self.face - 1
        if x < 0 or v < 0 or x >= self.w or v >= self.h:
            return NONE
        return self.px[v * self.w + x]


def _front(im: Image.Image, idx: list[int], w: int, h: int) -> int:
    meta = im.info.get("paddedit")
    if meta:
        front = json.loads(meta).get("front")
        if front is not None:
            return int(front)
    for x in range(w - 1, -1, -1):
        if 2 * sum(1 for y in range(h) if 1 <= idx[y * w + x] <= SIGNAL) >= h:
            return w - 1 - x
    return 0


@lru_cache(maxsize=None)
def ship(kind: int) -> Ship:
    """Lo sprite dell'astronave `kind` (le stesse regole di `Ship::decode` in ships.rs)."""
    im = Image.open(SPRITES / f"{KINDS[kind]}.png")
    assert im.mode == "P", f"{KINDS[kind]}.png: serve un PNG a palette"
    w, h = im.size
    idx = list(im.getdata())
    face = w - 1 - _front(im, idx, w, h)
    px = [NONE if r >= ENGINE else r for r in idx]
    assert all(r <= SIGNAL for r in px), f"ruolo sconosciuto in {KINDS[kind]}.png"

    def groups(role: int) -> list[Anchor]:
        out = []
        for x in range(w):
            y = 0
            while y < h:
                if idx[y * w + x] == role:
                    y0 = y
                    while y < h and idx[y * w + x] == role:
                        y += 1
                    out.append(Anchor(x - face + 1, y0, y - y0))
                else:
                    y += 1
        return sorted(out, key=lambda a: (a.v, a.u))
    marks = [(x - face + 1, y) for y in range(h) for x in range(w) if px[y * w + x] in MARKS and x <= face]
    s = Ship(w, h, face, px, groups(ENGINE), groups(WEAPON), groups(SPECIAL), None,
             min((m[0] for m in marks), default=-3),
             (min(m[1] for m in marks), max(m[1] for m in marks)) if marks else (0, -1))
    if kind == GUARDIAN:
        s.sectors = _sectors(s)
    return s


def _sectors(s: Ship) -> list[tuple[int, int]]:
    """GUARDIAN: giunture (righe con le piastre tutte nel colore del personaggio o nere) e settori,
    i pezzi tra l'una e l'altra; se non sono cinque, le righe del core (round(h * i / 5))."""
    def seam(v: int) -> bool:
        return all(s.at(u, v) in (*MARKS, BLACK) for u in range(2 - PLATE, 2))
    bands, y0 = [], 0
    for v in range(s.h + 1):
        if v == s.h or seam(v):
            if v > y0:
                bands.append((y0, v))
            y0 = v + 1
    if len(bands) == SECTORS:
        return bands
    row = [jround(s.h * i / SECTORS) for i in range(SECTORS + 1)]
    return [(row[i] + (1 if i else 0), row[i + 1]) for i in range(SECTORS)]


def col(u: int, pw: int) -> int | None:
    """Colonna sul MiSTer (pw 4) della colonna u del PC: None per la colonna 0, tolta."""
    if pw == 5:
        return u
    if u == 0:
        return None
    return u if u < 0 else u - 1


# ------------------------------------------------------------------ animazioni

@dataclass
class Anim:
    """Stato delle animazioni, come `paddle_ui::Anim` (le pose sono a 8 al secondo)."""
    t: float = 0.0
    vy: float = 0.0
    coin: float | None = None
    ammo: int = 6
    reload: float | None = None
    fire: float | None = None
    spark: tuple[float, float] | None = None
    wall: list[float | None] = field(default_factory=lambda: [None] * SECTORS)
    build: float | None = None
    recoil: float | None = None
    dashing: bool = False
    # accensione dei booster allo scatto in avanti (`Boost` di paddle_ui.rs): fase 3 (lampo), 2, 1
    # o 0, e allungamento delle fiamme in pixel
    boost_stage: int = 0
    boost_extra: int = 0


class Ops:
    def __init__(self, pw: int = 5) -> None:
        self.px: dict[tuple[int, int], int] = {}
        self.ops: list[tuple[int, int, int, int, int]] = []
        self.late: list[tuple[int, int, int, int, int]] = []
        self.pw = pw

    def fit(self, x, w):
        """Colonne [x, x + w) del PC su una hitbox larga `pw`: con 4 si toglie la colonna 0."""
        x, w = int(x), int(w)
        if self.pw == 5:
            return x, w
        cols = [c if c < 0 else c - 1 for c in range(x, x + w) if c != 0]
        return (cols[0], len(cols)) if cols else (x, 0)

    def sprite_px(self, u: int, v: int, role: int, dx: int = 0, dy: int = 0) -> None:
        c = col(u, self.pw)
        if c is not None:
            self.px[(c + dx, v + dy)] = role

    def rect(self, x, y, w, h, role) -> None:
        x, w = self.fit(x, w)
        if w > 0:
            self.ops.append((x, int(y), w, int(h), role))

    def late_rect(self, x, y, w, h, role) -> None:
        x, w = self.fit(x, w)
        if w > 0:
            self.late.append((x, int(y), w, int(h), role))

    def shift(self, dx: int) -> None:
        self.px = {(u + dx, v): r for (u, v), r in self.px.items()}
        self.ops = [(x + dx, y, w, h, r) for (x, y, w, h, r) in self.ops]
        self.late = [(x + dx, y, w, h, r) for (x, y, w, h, r) in self.late]


def pose(t: float) -> int:
    return math.floor(t * 8)


def flicker(t: float) -> int:
    """Sfarfallio delle fiamme a 16 al secondo (0 o 1)."""
    return math.floor(t * 16) % 2


def boost_of(fade: float, dist: float) -> tuple[int, int]:
    """Fase e allungamento dei booster da `fade` (1 appena partito, poi 0) e dalla distanza da casa."""
    left = jround(fade * 15)
    dist = max(0, jround(dist))
    if left >= 13:
        return 3, dist
    if left >= 7:
        return 2, dist // 2
    if left >= 1:
        return 1, dist // 4
    return 0, 0


def trail(r: Ops, x_from: int, y: int, length: int) -> None:
    """Scia dello scatto: linea tratteggiata scura lunga `length` oltre la punta della fiamma."""
    for i in range(0, length, 2):
        r.late_rect(x_from - 1 - i, y, 1, 1, MARK_DARK)


def ignite(r: Ops, x_end: int, y: int, rows: int) -> None:
    """Lampo dell'accensione dietro un ugello che finisce alla colonna `x_end`."""
    r.late_rect(x_end - 3, y - 2, 3, rows + 4, MARK)
    r.late_rect(x_end - 3, y - 1, 3, rows + 2, MARK_LIGHT)
    r.late_rect(x_end - 2, y, 2, rows, BODY)


def smooth(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


RING_SECONDS = 0.5
SPARK_SECONDS = 0.5
BREAK_SECONDS = 0.65
COIN_SECONDS = 0.5


def nozzle(a: Anchor, h: int, s: Ship) -> tuple[int, int, int]:
    """Colonna dell'ugello (subito davanti all'aggancio), prima riga e righe del getto, con le righe
    dello sprite riportate all'altezza della racchetta."""
    k = h / s.h
    return a.u + 1, math.floor(a.v * k), max(1, jround(a.rows * k))


def trail_row(y: int, rows: int) -> int:
    return y + (rows - 1) // 2


def sprite(r: Ops, s: Ship, h: int, paint) -> None:
    """I pixel dello sprite sulla racchetta alta `h`: `paint(u, riga dello sprite, ruolo)` dà
    (ruolo, dx, dy) o None."""
    u0, u1 = s.u_range()
    for v in range(h):
        sv = v if h == s.h else v * s.h // h
        for u in range(u0, u1 + 1):
            p = s.at(u, sv)
            if p == NONE:
                continue
            out = paint(u, sv, p)
            if out is not None:
                r.sprite_px(u, v, out[0], out[1], out[2])


def plain(_u, _v, p):
    return p, 0, 0


def brighter(p: int) -> int:
    return {MARK: MARK_LIGHT, MARK_DARK: MARK}.get(p, p)


def dimmed(p: int) -> int:
    return {MARK: DARK, MARK_DARK: DARK_DEEP, MARK_LIGHT: GRAY}.get(p, p)


def broken(p: int) -> int:
    if p in (BODY, SHADE, GRAY, GRAY_LIGHT):
        return DARK
    return BLACK if p == BLACK else DARK_DEEP


def ring(r: Ops, s: Ship, h: int, t: float) -> None:
    p = min(max(t / RING_SECONDS, 0.0), 1.0)
    rad = 3 + p * 7
    for cy, a0, a1 in ((2, 150.0, 300.0), (h - 2, 60.0, 210.0)):
        seen = set()
        deg = a0
        while deg <= a1:
            x = jround(-0.5 + rad * math.cos(math.radians(deg)) - 0.5)
            y = jround(cy + rad * math.sin(math.radians(deg)))
            on_body = 0 <= y < h and s.at(x, y * s.h // h) != NONE
            if not on_body and (x, y) not in seen:
                seen.add((x, y))
                r.rect(x, y, 1, 1, MARK if p < 0.5 else MARK_DARK)
            deg += 40 / rad


def rcs(r: Ops, a: Anchor, h: int, s: Ship, down: bool, p: int) -> None:
    """TWIST: getto di manovra dal pod `a`, verso il basso o verso l'alto (ribaltato)."""
    nz, y, rows = nozzle(a, h, s)
    parts = [(-6 - p, 3, 3, 3 + p, MARK), (-4, 8 + p, 2, 3, MARK), (-4, -1, 3, 4 + p, MARK_LIGHT),
             (-3, 5, 2, 4 + p, MARK_LIGHT), (-2, 0, 2, rows, BODY), (-2, 3, 1, 3, BODY),
             (-6 - p, 9 + p, 1, 1, BODY)]
    for dx, dy, w, hh, role in parts:
        yy = y + dy if down else y + rows - dy - hh
        r.late_rect(nz + dx, yy, w, hh, role)


def build_offset(i: int, t: float) -> int | None:
    land = 0.4 + 0.3 * (SECTORS - 1 - i)
    if t < land - 0.25:
        return None
    if t < land:
        return -jround((1 - smooth((t - land + 0.25) / 0.25)) * 14)
    return -1 if t < land + 0.1 else 0


def wall(r: Ops, s: Ship, h: int, a: Anim) -> None:
    tq = pose(a.t) % 120
    k = h / s.h
    sectors = s.sectors
    alive = sum(1 for w in a.wall if w is None)
    warn = alive == 1 and (tq % 4) < 2
    scan = tq % SECTORS
    recoil = None if a.recoil is None else min(int(a.recoil * SECTORS), SECTORS - 1)

    def offset(i: int):
        dy = 0
        if a.build is not None:
            dy = build_offset(i, a.build)
            if dy is None:
                return None
        return (-1 if recoil == i else 0), dy
    back = 2 - PLATE

    def paint(u, v, p):
        if u < back:
            return p, 0, 0
        i = next((j for j, (_, y1) in enumerate(sectors) if v < y1), SECTORS - 1)
        o = offset(i)
        if o is None:
            return None
        if v < sectors[i][0]:
            role = BLACK if (a.wall[i] is not None and a.wall[i - 1] is not None) else p
        elif a.wall[i] is None:
            if warn and p in (BODY, SHADE):
                role = MARK_LIGHT
            elif scan == i and u == back and p in (BODY, SHADE):
                role = MARK_LIGHT
            else:
                role = p
        elif a.wall[i] < 0.15:
            role = MARK_LIGHT if p in (BODY, SHADE) else MARK
        else:
            role = broken(p)
        return role, o[0], o[1]
    sprite(r, s, h, paint)
    for i, (y0, _) in enumerate(sectors):
        age, o = a.wall[i], offset(i)
        if age is None or o is None or not (0.15 <= age < BREAK_SECONDS):
            continue
        p = (age - 0.15) / 0.5
        ys = math.floor(y0 * k)
        for j in range(4):
            w, role = (1, GRAY) if j % 2 else (2, DARK)
            r.rect(jround(-7 - p * (5 + 2 * j)) + o[0], jround(ys + 1 + j * 1.5 + (j - 1.5) * p * 3) + o[1], w, 1, role)
    moving = abs(a.vy) > 0.5 or a.boost_stage > 0
    for idx, e in enumerate(s.engines):
        nz, y, rows = nozzle(e, h, s)
        p = (tq + idx * 2) % 4
        fl = (6, 7, 8, 7)[p] if moving else (4, 5, 6, 5)[p]
        jlen = fl - 1
        clen = max(2, fl // 2)
        r.late_rect(nz - 1, y - 1, 1, rows + 2, MARK)
        r.late_rect(nz - jlen, y, jlen, rows, MARK_LIGHT)
        r.late_rect(nz - clen, y, clen, rows, BODY)
        r.late_rect(nz - 1 - fl, y + min(p % 2, rows - 1), 2, 1, MARK)
        if moving:
            sp = (tq + idx) % 2
            r.late_rect(nz - 2 - fl - sp, y + min(sp, rows - 1), 1, 1, MARK_LIGHT)
        trail(r, nz - 1 - fl, trail_row(y, rows), a.boost_extra)
        if a.boost_stage == 3:
            ignite(r, nz - 1, y, rows)


def kind_ops(kind: int, h: int, a: Anim, pw: int = 5) -> Ops:
    r = Ops(pw)
    s = ship(kind)
    mid = h // 2
    tq = pose(a.t) % 120
    moving = abs(a.vy) > 0.5 or a.boost_stage > 0
    extra = a.boost_extra
    ignited = a.boost_stage == 3
    if kind == ARCADE:
        coin_f = math.floor(a.coin * 60) if a.coin is not None and a.coin < COIN_SECONDS else None
        coin_flash = coin_f is not None and coin_f >= 18
        lit = (tq % 8) < 2

        def paint(_u, _v, p):
            if p not in MARKS:
                return p, 0, 0
            if coin_f is not None and 18 <= coin_f < 22:
                return BODY, 0, 0
            return (brighter(p) if coin_flash or lit else p), 0, 0
        sprite(r, s, h, paint)
        f = tq % 4
        fl = 3 if moving else 2
        for e in s.engines:
            nz, y, rows = nozzle(e, h, s)
            r.rect(nz - fl - f % 2, y, fl, rows, MARK_LIGHT)
            r.rect(nz - 2 - f * 2, y + rows if f % 2 else y - 1, 1, 1, MARK)
            trail(r, nz - 1 - fl, trail_row(y, rows), extra)
            if ignited:
                ignite(r, nz, y, rows)
        if coin_f is not None:
            c0 = s.mark_u0
            if coin_f < 12:
                cx = c0 - 14 + coin_f
                r.late_rect(cx, mid - 1, 4, 2, MARK)
                r.late_rect(cx + 1, mid - 2, 2, 4, MARK)
                r.late_rect(cx + 1, mid - 2, 2, 1, MARK_LIGHT)
                r.late_rect(cx + 1, mid + 1, 2, 1, MARK_DARK)
                if (coin_f // 3) % 2 == 0:
                    r.late_rect(cx + 1, mid - 1, 1, 2, BODY)
                else:
                    r.late_rect(cx + 2, mid - 1, 1, 2, MARK_LIGHT)
            elif coin_f < 14:
                r.late_rect(c0 - 2, mid - 2, 3, 4, MARK)
                r.late_rect(c0 - 2, mid - 2, 2, 1, MARK_LIGHT)
                r.late_rect(c0 - 1, mid - 1, 1, 2, BODY)
            elif coin_f < 16:
                r.late_rect(c0 - 1, mid - 2, 2, 4, MARK_LIGHT)
                r.late_rect(c0, mid - 1, 1, 2, BODY)
            elif coin_f < 18:
                r.late_rect(c0, mid - 2, 1, 4, BODY)
            else:
                d, sr = (0, BODY) if coin_f < 22 else (1, MARK_LIGHT) if coin_f < 26 else (2, MARK)
                r.late_rect(c0 + 1 - 2 * d, mid - 5 - d, 1, 1, sr)
                r.late_rect(c0 + 1 - 2 * d, mid + 4 + d, 1, 1, sr)
                r.late_rect(c0 - 2 - 2 * d, mid - 2 - d, 1, 1, sr)
                r.late_rect(c0 - 2 - 2 * d, mid + 1 + d, 1, 1, sr)
    elif kind == TITAN:
        sprite(r, s, h, plain)
        for idx, e in enumerate(s.engines):
            nz, y, rows = nozzle(e, h, s)
            p = (tq + idx * 2) % 4
            fl = (6, 8, 7, 8)[p] if moving else (4, 5, 6, 5)[p]
            mlen = (fl + 1) // 2
            jlen = fl - 1
            clen = max(2, fl // 2)
            r.late_rect(nz - 1, y - 2, 1, rows + 4, MARK)
            r.late_rect(nz - mlen, y - 1, mlen, rows + 2, MARK)
            r.late_rect(nz - 1, y - 1, 1, rows + 2, MARK_LIGHT)
            r.late_rect(nz - jlen, y, jlen, rows, MARK_LIGHT)
            r.late_rect(nz - clen, y, clen, rows, BODY)
            r.late_rect(nz - 1 - fl, y + min(p % 2, rows - 1), 2, 1, MARK)
            if moving:
                sp = (tq + idx) % 3
                r.late_rect(nz - 2 - fl - sp, y - 1 + (sp + idx) % 3, 1, 1, MARK_LIGHT if sp == 0 else MARK)
            trail(r, nz - 1 - fl, trail_row(y, rows), extra)
            if ignited:
                ignite(r, nz - 1, y, rows)
    elif kind == HAMMER:
        sprite(r, s, h, plain)
        sp = a.spark[0] if a.spark is not None else None
        surge = 3 if (sp is not None and sp < 0.14) else (2 if (sp is not None and sp < 0.25) else
                                                          (1 if (sp is not None and sp < 0.35) else 0))
        piston_beat = (tq % 2) == 1
        fl = (11 if surge == 3 else (9 if surge == 2 else (7 if surge == 1 else (4, 5, 4, 3)[tq % 4])))
        tlen = 3 if fl >= 9 else (2 if fl >= 6 else 1)
        mlen = (fl * 2) // 3
        jlen = fl - 1
        clen = max(2, fl // 2)
        for e in s.engines:
            nz, y, rows = nozzle(e, h, s)
            if surge == 3:
                r.late_rect(nz - 1, y - 3, 1, rows + 6, MARK)
            r.late_rect(nz - tlen, y - 2, tlen, rows + 4, MARK)
            r.late_rect(nz - mlen, y - 1, mlen, rows + 2, MARK)
            if surge >= 1:
                hlen = max(1, mlen // 2)
                r.late_rect(nz - hlen, y - 1, hlen, rows + 2, MARK_LIGHT)
            r.late_rect(nz - jlen, y, jlen, rows, MARK_LIGHT)
            r.late_rect(nz - clen, y, clen, rows, BODY)
            tip = y + min(tq % 2, rows - 1)
            r.late_rect(nz - 1 - fl, tip, 2, 1, MARK)
            if surge >= 2:
                r.late_rect(nz - fl, tip, 1, 1, MARK_LIGHT)
            trail(r, nz - 1 - fl, trail_row(y, rows), extra)
            if ignited:
                ignite(r, nz, y, rows)
        if surge >= 2 or piston_beat:
            r.shift(-1)
        if a.spark is not None and a.spark[0] < SPARK_SECONDS:
            p = (pose(a.spark[0]) + 1) / 4
            yh = jround(a.spark[1] * h)
            for j in range(6):
                an = math.radians(-70 + j * 28)
                d = 2 + p * 7
                for dd in (d, d - 1.5):
                    r.rect(jround(1 + math.cos(an) * dd), jround(yh + math.sin(an) * dd), 1, 1,
                           MARK if p < 0.6 else MARK_DARK)
    elif kind == TWIST:
        sprite(r, s, h, plain)
        ph = tq % 4
        dy = -1 if ph == 1 else (1 if ph == 3 else 0)
        fl = (2, 3, 2, 3)[ph] if moving else (0, 1, 0, 1)[ph]
        clen = 2 + fl // 2
        for e in s.engines:
            nz, y, rows = nozzle(e, h, s)
            r.late_rect(nz - 2, y - 1, 2, rows + 2, MARK)
            r.late_rect(nz - 3 - fl, y + dy, 3 + fl, rows, MARK_LIGHT)
            r.late_rect(nz - clen, y + dy, clen, rows, BODY)
            r.late_rect(nz - 5 - fl, y + dy + min(ph % 2, rows - 1), 2, 1, MARK)
            trail(r, nz - 5 - fl, trail_row(y, rows), extra)
            if ignited:
                ignite(r, nz - 2, y, rows)
        p = tq % 2
        if a.vy < -0.5 and s.specials:
            rcs(r, s.specials[-1], h, s, True, p)
        elif a.vy > 0.5 and s.specials:
            rcs(r, s.specials[0], h, s, False, p)
        if a.spark is not None and a.spark[0] < RING_SECONDS:
            ring(r, s, h, a.spark[0])
    elif kind == BLASTER:
        fr = None if a.fire is None else a.fire * 60
        recoil = fr is not None and fr < 3
        barrel = 1 if recoil else (2 if (fr is not None and fr < 8) else 3)
        length = s.front() - (1 if s.weapons else 0)
        back = max(0, min(3 - barrel, length - 1))
        ammo = min(a.ammo, 6)
        fill = ((0, 3, 6, 9, 13, 16, 19)[ammo] / 19 if ammo > 0
                else (min(max(a.reload, 0.0), 1.0) if a.reload is not None else 0.0))
        g0, g1 = s.mark_rows
        lit_from = g1 + 1 - jround(fill * (g1 - g0 + 1))

        def paint(u, v, p):
            if u > 1:
                return (p, -back, 0) if u - back > 1 else None
            return (dimmed(p) if p in MARKS and v < lit_from else p), 0, 0
        sprite(r, s, h, paint)
        for idx, e in enumerate(s.engines):
            nz, y, rows = nozzle(e, h, s)
            p = (tq + idx * 2) % 4
            fl = (6, 8, 7, 8)[p] if moving else (4, 5, 6, 5)[p]
            mlen = (fl + 1) // 2
            jlen = fl - 1
            clen = max(2, fl // 2)
            r.late_rect(nz - mlen, y - 1, mlen, rows + 2, MARK)
            r.late_rect(nz - 1, y - 1, 1, rows + 2, MARK_LIGHT)
            r.late_rect(nz - jlen, y, jlen, rows, MARK_LIGHT)
            r.late_rect(nz - clen, y, clen, rows, BODY)
            r.late_rect(nz - 1 - fl, y, 2, 1, MARK)
            if moving:
                sp = (tq + idx) % 3
                r.late_rect(nz - 2 - fl - sp, y - 1 + (sp + idx) % 3, 1, 1, MARK_LIGHT if sp == 0 else MARK)
            trail(r, nz - 1 - fl, trail_row(y, rows), extra)
            if ignited:
                ignite(r, nz - 1, y, rows)
        if recoil:
            k = h / s.h
            for w in s.weapons:
                fx, rows = w.u - back, max(1, jround(w.rows * k))
                fy = math.floor(w.v * k) - 1
                r.rect(fx, fy, 2, rows + 2, MARK)
                r.rect(fx + 1, fy + 1, 3, rows, MARK_LIGHT)
                r.rect(fx + 1, fy + 1, 2, rows, BODY)
                r.rect(fx + 4, fy + 1, 2, rows, MARK_LIGHT)
            r.shift(-1)
    elif kind == RUSH:
        sprite(r, s, h, plain)
        p = tq % 4
        fz = flicker(a.t)
        fl = (11, 13, 12, 14)[p] if a.dashing else (5, 7, 6, 8)[p] + (2 if moving else 0)
        lean = 0 if a.dashing else (-1 if a.vy > 0.5 else (1 if a.vy < -0.5 else 0))
        olen = (fl + 1) // 2 + fz
        jlen = fl - 1
        clen = fl // 4 + 1
        for e in s.engines:
            nz, y, rows = nozzle(e, h, s)
            r.late_rect(nz - olen, y - 1, olen, rows + 2, MARK)
            r.late_rect(nz - jlen, y + lean, jlen, rows, MARK_LIGHT)
            r.late_rect(nz - clen, y, clen, rows, BODY)
            for j in range(2):
                d = clen + 1 + tq % 3 + 3 * j
                if d < jlen - 1:
                    r.late_rect(nz - 1 - d, y + lean, 1, rows, BODY)
            r.late_rect(nz - 1 - fl, y + lean + min(fz, rows - 1), 2, 1, MARK)
            if moving:
                sp = tq % 3
                r.late_rect(nz - 2 - fl - sp, y - 1 + (p + sp) % 4, 1, 1, MARK_LIGHT if sp == 0 else MARK)
            trail(r, nz - 1 - fl, trail_row(y, rows), extra)
            if ignited:
                ignite(r, nz, y, rows)
        wlen = 4 if a.dashing else 2
        wrole = MARK_LIGHT if a.dashing else MARK
        for j, sa in enumerate(s.specials):
            w = (tq + j) % 3
            x, y, rows = nozzle(sa, h, s)
            r.rect(x - 1 - w - wlen, trail_row(y, rows), wlen, 1, wrole)
    elif kind == GUARDIAN:
        wall(r, s, h, a)
    return r


def twist_shift(v: int, h: int, tilt: int) -> int:
    """Righe di TWIST spostate verso la faccia (positivo) come kind_px del MiSTer: (v - h/2) * tilt / 8,
    con tilt da -3 a 3 (positivo: faccia verso l'alto)."""
    d = v - (h >> 1)
    m = abs(tilt)
    s = (d if m & 1 else 0) + ((d << 1) if m & 2 else 0)
    return -(s >> 3) if tilt < 0 else (s >> 3)


def pixel(ops: Ops, u: int, v: int) -> int:
    """Ruolo del pixel (u, v), senza l'ombra portata."""
    fill = ops.px.get((u, v), NONE)
    rel = NONE
    for (x, y, w, hh, role) in ops.ops:
        if x <= u < x + w and y <= v < y + hh:
            fill = role
        if w < 2 or hh < 2 or not (x <= u < x + w and y <= v < y + hh):
            continue
        if role == BODY:
            if (x <= -3 and u == x) or (v == y + hh - 1 and x + 1 <= u < x + w - 1):
                rel = SHADE
        elif role in (MARK, GRAY, DARK):
            light, dark = {MARK: (MARK_LIGHT, MARK_DARK), GRAY: (GRAY_LIGHT, DARK), DARK: (GRAY, DARK_DEEP)}[role]
            if v == y:
                rel = light
            elif v == y + hh - 1:
                rel = dark
    out = rel if rel != NONE else fill
    for (x, y, w, hh, role) in ops.late:
        if x <= u < x + w and y <= v < y + hh:
            out = role
    return out


def render(kind: int, h: int, a: Anim | None = None, tilt: int = 0, shadow: bool = True,
           pw: int = 5) -> dict[tuple[int, int], int]:
    """Pixel della racchetta rivolta a destra: {(u, v): ruolo}, ombra portata compresa. Con `tilt`
    TWIST sposta le righe come il MiSTer."""
    a = a or Anim()
    ops = kind_ops(kind, h, a, pw)

    def role(u: int, v: int) -> int:
        if kind == TWIST and tilt:
            u -= twist_shift(v, h, tilt)
        return pixel(ops, u, v)
    out = {}
    for v in range(-20, h + 20):
        for u in range(-80, 20):
            c = role(u, v)
            if c == NONE and shadow and role(u + 1, v - 1) not in (NONE,):
                c = SHADOW
            if c != NONE:
                out[(u, v)] = c
    return out
