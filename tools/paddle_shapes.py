"""Racchette dei personaggi di NEXT, pixel per pixel: il modello delle forme del MiSTer.

Le forme sono quelle di rust/game/src/paddle_ui.rs (`kind_ops`), in pixel arcade: x (`u`) dal
corpo, che va da -3 a 1, verso la faccia; y (`v`) dalla cima. Sul MiSTer il corpo è largo 4 (`pw`):
si toglie la colonna 0, quella subito dietro la faccia (i pezzi che la coprono si accorciano, quelli
davanti si spostano di 1), e il corpo va da -3 a 0; i giunti del GUARDIAN restano sfalsati. La racchetta destra è speculare. Un
pixel prende il ruolo dell'ultimo pezzo che lo copre; sopra vanno le luci e le ombre dei bordi (dei
pezzi alti e larghi almeno 2 pixel, l'ultimo vince), poi i pezzi "tardi" (il bordo scuro di HAMMER).
Dove non c'è niente, l'ombra portata: la stessa forma 1 pixel verso il retro e 1 in basso.

Serve a tools/gen_mister_ui.py (le anteprime della scelta e dello schermo VS) e a confrontare i
frame dell'RTL (`kind_px` di mister/rtl/next_render.v, che segue le stesse regole). TWIST si inclina
come sul MiSTer, spostando le righe (`twist_shift`), non ruotando.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

# ruoli dei pixel (gli stessi codici di KR_* in next_render.v)
NONE, BODY, SHADE, MARK, MARK_DARK, MARK_LIGHT, GRAY, GRAY_LIGHT, DARK, DARK_DEEP, BLACK, SIGNAL, \
    SHADOW, GHOST1, GHOST2, GHOST3 = range(16)

KINDS = ("arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian")
ARCADE, TITAN, HAMMER, TWIST, BLASTER, RUSH, GUARDIAN = range(7)
SECTORS = 5

# colori fissi (come paddle_ui.rs) e rampe del colore del personaggio
RGB = {
    SHADOW: (48, 48, 58), BODY: (255, 255, 255), SHADE: (212, 214, 224), GRAY: (180, 180, 180),
    GRAY_LIGHT: (226, 226, 230), DARK: (92, 92, 98), DARK_DEEP: (52, 52, 60), BLACK: (0, 0, 0),
    SIGNAL: (255, 210, 37),
}


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


@dataclass
class Anim:
    """Stato delle animazioni, come `paddle_ui::Anim` (le pose sono a 8 al secondo)."""
    t: float = 0.0
    vy: float = 0.0
    ammo: int = 4
    fire: float | None = None
    spark: tuple[float, float] | None = None
    wall: list[float | None] = field(default_factory=lambda: [None] * SECTORS)
    build: float | None = None
    recoil: float | None = None
    dashing: bool = False


class Ops:
    def __init__(self, pw: int = 5) -> None:
        self.ops: list[tuple[int, int, int, int, int]] = []
        self.late: list[tuple[int, int, int, int, int]] = []
        self.narrow = pw == 4

    def fit(self, x, w):
        """Colonne [x, x + w) del PC su un corpo largo `pw`: con 4 si toglie la colonna 0."""
        x, w = int(x), int(w)
        if not self.narrow:
            return x, w
        cols = [c if c < 0 else c - 1 for c in range(x, x + w) if c != 0]
        return (cols[0], len(cols)) if cols else (x, 0)

    def rect(self, x, y, w, h, role) -> None:
        x, w = self.fit(x, w)
        if w > 0:
            self.ops.append((x, int(y), w, int(h), role))

    def late_rect(self, x, y, w, h, role) -> None:
        x, w = self.fit(x, w)
        if w > 0:
            self.late.append((x, int(y), w, int(h), role))

    def shift(self, dx: int) -> None:
        self.ops = [(x + dx, y, w, h, r) for (x, y, w, h, r) in self.ops]
        self.late = [(x + dx, y, w, h, r) for (x, y, w, h, r) in self.late]


def pose(t: float) -> int:
    return math.floor(t * 8)


def smooth(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def coin_slot(r: Ops, h: int, t: float) -> None:
    s = pose(t) % 24
    top = h // 2 - 4
    lit = 10 <= s <= 13 and s % 2 == 0
    r.rect(-1, top, 1, 8, MARK if lit else DARK)
    if s <= 5:
        y = top - 7 + s
        r.rect(-2, y + 1, 3, 1, MARK)
        r.rect(-1, y, 1, 3, MARK)
    elif s <= 8:
        r.rect(-1, top, 1, (6, 4, 2)[s - 6], MARK)


def heavy_step(r: Ops, h: int, a: Anim, x0: int) -> None:
    t = pose(a.t) / 8
    m = 4 if abs(a.vy) > 0.5 else 2
    for yc, d in ((h - 3, 1), (2, -1)):
        for k in range(m):
            p = (t * 0.9 + k / m + (0 if d > 0 else 0.37)) % 1
            if p > 0.85:
                continue
            x = jround(x0 - p * 9)
            y = jround(yc + d * (p * 4 + (k % 2) * 2))
            if p < 0.45:
                r.rect(x - 1, y, 2, 2, GRAY)
            else:
                r.rect(x, y, 1, 1, DARK)


RING_SECONDS = 0.5
SPARK_SECONDS = 0.5
BREAK_SECONDS = 0.65


def ring(r: Ops, h: int, s: float) -> None:
    p = min(max(s / RING_SECONDS, 0.0), 1.0)
    rad = 3 + p * 7
    for cy, a0, a1 in ((2, 150.0, 300.0), (h - 2, 60.0, 210.0)):
        seen = set()
        deg = a0
        while deg <= a1:
            x = jround(-0.5 + rad * math.cos(math.radians(deg)) - 0.5)
            y = jround(cy + rad * math.sin(math.radians(deg)))
            if not (-3 <= x <= 1 and 0 <= y < h) and (x, y) not in seen:
                seen.add((x, y))
                r.rect(x, y, 1, 1, MARK if p < 0.5 else MARK_DARK)
            deg += 40 / rad


def tails(r: Ops, ax: int, ay: int, sw: int, n1: int, n2: int, a: Anim) -> None:
    t = pose(a.t) / 8
    bend = min(max(-a.vy * 0.6, -1.2), 1.2)
    calm = 1 - min(abs(bend), 1.0)
    for i, (n, spread, y0) in enumerate(((n1, -0.5, 0), (n2, 0.6, 2))):
        if a.dashing:
            n += 2
        for j in range(1, n + 1):
            wave = 0.0 if a.dashing else math.sin(t * 5 + j * 1.3 + i * 2) * (0.3 + 0.7 * calm) * j / n * 1.4
            lean = 0.25 if a.dashing else 1.0
            dy = jround(ay + y0 + lean * spread * j + bend * j + wave)
            r.rect(ax - sw * j, dy, sw, 1, MARK_DARK if i == 1 and j == n else MARK)


def build_offset(i: int, t: float) -> int | None:
    land = 0.4 + 0.3 * (SECTORS - 1 - i)
    if t < land - 0.25:
        return None
    if t < land:
        return -jround((1 - smooth((t - land + 0.25) / 0.25)) * 14)
    return -1 if t < land + 0.1 else 0


def wall(r: Ops, h: int, a: Anim) -> None:
    tq = pose(a.t)
    alive = sum(1 for w in a.wall if w is None)
    recoil = None if a.recoil is None else min(int(a.recoil * SECTORS), SECTORS - 1)
    for i in range(SECTORS):
        dy = 0
        if a.build is not None:
            dy = build_offset(i, a.build)
            if dy is None:
                continue
        dx = -1 if recoil == i else 0

        def rect(x, y, w, hh, role):
            r.rect(x + dx, y + dy, w, hh, role)
        y0 = jround(h * i / SECTORS)
        y1 = jround(h * (i + 1) / SECTORS)
        ys = y0 + 1 if i > 0 else y0
        hh = y1 - ys
        joints = ((-4, 0) if i % 2 else (-2,)) if not r.narrow else ((-5, -1) if i % 2 else (-3,))

        def crack():
            rect(-4, ys + 1, 1, 2, BLACK)
            rect(-3, ys + 3, 1, 1, BLACK)
            rect(-2, ys + 4, 1, 2, BLACK)
            rect(0, ys + 2, 1, 2, BLACK)
        rect(-6, y0, 8, y1 - y0, BODY)
        age = a.wall[i]
        if age is None:
            if alive == 1 and tq % 4 < 2:
                rect(-6, ys, 8, hh, MARK_LIGHT)
            for jx in joints:
                rect(jx, ys, 1, hh, MARK)
        elif age < 0.15:
            for jx in joints:
                rect(jx, ys, 1, hh, MARK)
            crack()
        else:
            rect(-6, ys, 8, hh, DARK)
            crack()
            if age < BREAK_SECONDS:
                p = (age - 0.15) / 0.5
                for j in range(4):
                    w, role = (1, GRAY) if j % 2 else (2, DARK)
                    rect(jround(-7 - p * (5 + 2 * j)), jround(ys + 1 + j * 1.5 + (j - 1.5) * p * 3), w, 1, role)
        if i > 0:
            rect(-6, y0, 8, 1, MARK)


def kind_ops(kind: int, h: int, a: Anim, pw: int = 5) -> Ops:
    r = Ops(pw)
    mid = h // 2
    if kind == ARCADE:
        r.rect(-3, 0, 5, h, BODY)
        coin_slot(r, h, a.t)
    elif kind == TITAN:
        yb = jround(h / 2) - 2
        r.rect(-6, 0, 8, h, BODY)
        r.rect(-6, yb, 7, 4, MARK)
        for x in (-4, -2, 0):
            r.rect(x, yb + 1, 1, 1, MARK_DARK)
        r.rect(-9, yb - 1, 3, 6, GRAY)
        r.rect(-8, yb, 1, 4, DARK)
        heavy_step(r, h, a, -8)
    elif kind == HAMMER:
        r.rect(-6, 0, 8, h, BODY)
        r.late_rect(-6, 0, 1, h, DARK)
        yc = jround(h / 2)
        r.rect(-4, yc - 4, 4, 8, DARK)
        r.rect(-3, yc - 3, 2, 6, MARK)
        r.rect(-3, yc - 1, 2, 1, MARK_DARK)
        if a.spark is not None and a.spark[0] < SPARK_SECONDS:
            s, at = a.spark
            p = (pose(s) + 1) / 4
            yh = jround(at * h)
            for j in range(6):
                an = math.radians(-70 + j * 28)
                d = 2 + p * 7
                for dd in (d, d - 1.5):
                    r.rect(jround(1 + math.cos(an) * dd), jround(yh + math.sin(an) * dd), 1, 1,
                           MARK if p < 0.6 else MARK_DARK)
    elif kind == TWIST:
        r.rect(-3, 0, 5, h, BODY)
        r.rect(-1, 2, 1, h - 4, MARK)
        r.rect(-2, mid - 2, 3, 4, MARK)
        if a.spark is not None and a.spark[0] < RING_SECONDS:
            ring(r, h, a.spark[0])
    elif kind == BLASTER:
        fr = None if a.fire is None else a.fire * 60
        recoil = fr is not None and fr < 3
        barrel = 1 if recoil else 2 if fr is not None and fr < 8 else 3
        # corpo con gli spigoli del davanti smussati (gli stessi pixel tagliati di prima sul MiSTer)
        r.rect(-3, 0, 3, h, BODY)
        r.rect(0, 2, 2, h - 4, BODY)
        r.rect(-0, 1, 1, 1, BODY)
        r.rect(-0, h - 2, 1, 1, BODY)
        r.rect(2, mid - 3, barrel, 2, GRAY)
        r.rect(2, mid + 1, barrel, 2, GRAY)
        if recoil:
            x = 2 + barrel
            r.rect(x, mid - 4, 1, 3, SIGNAL)
            r.rect(x, mid + 1, 1, 3, SIGNAL)
            r.rect(x + 1, mid - 2, 2, 4, SIGNAL)
            r.rect(x + 3, mid - 1, 1, 2, SIGNAL)
        tails(r, -3, 3, 2, 3, 2, a)
        y0 = mid - 9
        r.rect(-4, y0, 1, 21, DARK)
        ammo = min(a.ammo, 4)
        for i in range(4 - ammo, 4):
            r.rect(-6, y0 + 1 + i * 5, 2, 3, SIGNAL)
        if fr is not None and 2 <= fr < 26:
            p = (fr - 2) / 24
            slot = max(3 - ammo, 0)
            r.rect(jround(-7 - p * 10), jround(y0 + 1 + slot * 5 - 6 * math.sin(p * math.pi) + p * 4), 2, 1, SIGNAL)
        if recoil:
            r.shift(-1)
    elif kind == RUSH:
        r.rect(-3, 0, 5, h, BODY)
        r.rect(-3, 3, 4, 2, MARK)
        tails(r, -3, 3, 3, 3, 2, a)
    elif kind == GUARDIAN:
        wall(r, h, a)
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
    fill = NONE
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
        for u in range(-30, 20):
            c = role(u, v)
            if c == NONE and shadow and role(u + 1, v - 1) not in (NONE,):
                c = SHADOW
            if c != NONE:
                out[(u, v)] = c
    return out
