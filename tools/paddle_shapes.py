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
    coin: float | None = None
    ammo: int = 6
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


def trail(r: "Ops", x_from: int, y: int, length: int) -> None:
    """Scia dello scatto: linea tratteggiata scura lunga `length` oltre la punta della fiamma."""
    for i in range(0, length, 2):
        r.late_rect(x_from - 1 - i, y, 1, 1, MARK_DARK)


def ignite(r: "Ops", x_end: int, y: int, rows: int) -> None:
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


def build_offset(i: int, t: float) -> int | None:
    land = 0.4 + 0.3 * (SECTORS - 1 - i)
    if t < land - 0.25:
        return None
    if t < land:
        return -jround((1 - smooth((t - land + 0.25) / 0.25)) * 14)
    return -1 if t < land + 0.1 else 0


def wall(r: Ops, h: int, a: Anim) -> None:
    tq = pose(a.t) % 120
    mid = h // 2
    # chiglia posteriore, stabilizzatori blu e due propulsori ionici a cono
    r.rect(-7, 5, 4, h - 10, GRAY)
    r.rect(-8, mid - 3, 3, 6, DARK)
    r.rect(-7, mid - 2, 2, 4, MARK)
    r.rect(-5, 2, 3, 3, MARK)
    r.rect(-5, h - 5, 3, 3, MARK)
    moving = abs(a.vy) > 0.5 or a.boost_stage > 0
    for idx, ey in enumerate((7, h - 9)):
        r.rect(-8, ey - 1, 1, 4, DARK_DEEP)
        p = (tq + idx * 2) % 4
        fl = (6, 7, 8, 7)[p] if moving else (4, 5, 6, 5)[p]
        jlen = fl - 1
        clen = max(2, fl // 2)
        r.late_rect(-9, ey - 1, 1, 4, MARK)
        r.late_rect(-8 - jlen, ey, jlen, 2, MARK_LIGHT)
        r.late_rect(-8 - clen, ey, clen, 2, BODY)
        r.late_rect(-9 - fl, ey + (p % 2), 2, 1, MARK)
        if moving:
            s = (tq + idx) % 2
            r.late_rect(-10 - fl - s, ey + s, 1, 1, MARK_LIGHT)
        trail(r, -9 - fl, ey, a.boost_extra)
        if a.boost_stage == 3:
            ignite(r, -9, ey, 2)

    alive = sum(1 for w in a.wall if w is None)
    scan = tq % SECTORS
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
        age = a.wall[i]
        if age is None:
            warn = alive == 1 and (tq % 4) < 2
            rect(-2, y0, 4, y1 - y0, MARK_LIGHT if warn else BODY)
            rect(-2, ys, 1, hh, MARK_LIGHT if (scan == i or warn) else MARK)
        elif age < 0.15:
            rect(-2, y0, 4, y1 - y0, MARK_LIGHT)
            rect(-1, ys + 1, 2, max(1, hh - 2), MARK)
        else:
            rect(-2, y0, 4, y1 - y0, DARK)
            rect(-1, ys + 1, 2, max(1, hh - 2), DARK_DEEP)
            if age < BREAK_SECONDS:
                p = (age - 0.15) / 0.5
                for j in range(4):
                    w, role = (1, GRAY) if j % 2 else (2, DARK)
                    rect(jround(-7 - p * (5 + 2 * j)), jround(ys + 1 + j * 1.5 + (j - 1.5) * p * 3), w, 1, role)
        if i > 0:
            gap = BLACK if (a.wall[i] is not None and a.wall[i - 1] is not None) else MARK
            rect(-2, y0, 4, 1, gap)
    r.late_rect(-3, 0, 1, h, BLACK)


def kind_ops(kind: int, h: int, a: Anim, pw: int = 5) -> Ops:
    r = Ops(pw)
    mid = h // 2
    tq = pose(a.t) % 120
    moving = abs(a.vy) > 0.5 or a.boost_stage > 0
    extra = a.boost_extra
    ignited = a.boost_stage == 3
    if kind == ARCADE:
        coin_f = int(math.floor(a.coin * 60)) if (a.coin is not None and a.coin < 0.5) else None
        coin_flash = coin_f is not None and coin_f >= 18
        r.rect(-3, 4, 5, h - 8, BODY)
        r.rect(-3, 1, 5, 3, GRAY)
        r.rect(-2, 0, 4, 1, GRAY)
        r.rect(-3, h - 4, 5, 3, GRAY)
        r.rect(-2, h - 1, 4, 1, GRAY)
        r.late_rect(-3, 4, 4, 1, DARK)
        r.late_rect(-3, h - 5, 4, 1, DARK)
        r.rect(-5, 6, 2, 5, GRAY)
        r.rect(-5, h - 11, 2, 5, GRAY)
        r.rect(-6, 7, 1, 3, DARK)
        r.rect(-6, h - 10, 1, 3, DARK)
        lit = (tq % 8) < 2
        r.rect(-4, mid - 4, 4, 8, DARK)
        cabin = BODY if (coin_f is not None and 18 <= coin_f < 22) else (MARK_LIGHT if (coin_flash or lit) else MARK)
        r.rect(-3, mid - 3, 3, 6, cabin)
        r.late_rect(-2, mid - 2, 1, 4, BLACK)
        f = tq % 4
        fl = 3 if moving else 2
        for ey in (8, h - 9):
            r.rect(-6 - fl - (f % 2), ey, fl, 1, MARK_LIGHT)
            r.rect(-8 - f * 2, ey + (1 if f % 2 else -1), 1, 1, MARK)
            trail(r, -7 - fl, ey, extra)
            if ignited:
                ignite(r, -6, ey, 1)
        if coin_f is not None:
            if coin_f < 12:
                cx = -17 + coin_f
                r.late_rect(cx, mid - 1, 4, 2, MARK)
                r.late_rect(cx + 1, mid - 2, 2, 4, MARK)
                r.late_rect(cx + 1, mid - 2, 2, 1, MARK_LIGHT)
                r.late_rect(cx + 1, mid + 1, 2, 1, MARK_DARK)
                if (coin_f // 3) % 2 == 0:
                    r.late_rect(cx + 1, mid - 1, 1, 2, BODY)
                else:
                    r.late_rect(cx + 2, mid - 1, 1, 2, MARK_LIGHT)
            elif coin_f < 14:
                r.late_rect(-5, mid - 2, 3, 4, MARK)
                r.late_rect(-5, mid - 2, 2, 1, MARK_LIGHT)
                r.late_rect(-4, mid - 1, 1, 2, BODY)
            elif coin_f < 16:
                r.late_rect(-4, mid - 2, 2, 4, MARK_LIGHT)
                r.late_rect(-3, mid - 1, 1, 2, BODY)
            elif coin_f < 18:
                r.late_rect(-3, mid - 2, 1, 4, BODY)
            else:
                d, srole = (0, BODY) if coin_f < 22 else ((1, MARK_LIGHT) if coin_f < 26 else (2, MARK))
                r.late_rect(-2 - d * 2, mid - 5 - d, 1, 1, srole)
                r.late_rect(-2 - d * 2, mid + 4 + d, 1, 1, srole)
                r.late_rect(-5 - d * 2, mid - 2 - d, 1, 1, srole)
                r.late_rect(-5 - d * 2, mid + 1 + d, 1, 1, srole)
    elif kind == TITAN:
        yb = jround(h / 2) - 3
        for idx, my in enumerate((2, h - 12)):
            r.rect(-11, my, 4, 10, GRAY)
            r.rect(-10, my + 2, 2, 6, DARK)
            r.rect(-12, my + 1, 1, 8, DARK_DEEP)
            p = (tq + idx * 2) % 4
            fl = (6, 8, 7, 8)[p] if moving else (4, 5, 6, 5)[p]
            mlen = (fl + 1) // 2
            jlen = fl - 1
            clen = max(2, fl // 2)
            r.late_rect(-13, my + 2, 1, 6, MARK)
            r.late_rect(-12 - mlen, my + 3, mlen, 4, MARK)
            r.late_rect(-13, my + 3, 1, 4, MARK_LIGHT)
            r.late_rect(-12 - jlen, my + 4, jlen, 2, MARK_LIGHT)
            r.late_rect(-12 - clen, my + 4, clen, 2, BODY)
            r.late_rect(-13 - fl, my + 4 + (p % 2), 2, 1, MARK)
            if moving:
                s = (tq + idx) % 3
                r.late_rect(-14 - fl - s, my + 3 + ((s + idx) % 3), 1, 1, MARK_LIGHT if s == 0 else MARK)
            trail(r, -13 - fl, my + 4, extra)
            if ignited:
                ignite(r, -13, my + 4, 2)
        r.rect(-8, 1, 2, h - 2, DARK_DEEP)
        r.rect(-7, 1, 1, h - 2, DARK)
        r.rect(-7, h, 9, 2, DARK_DEEP)
        r.rect(-6, h, 8, 1, DARK)
        r.rect(-6, 0, 8, h, BODY)
        r.rect(-6, 6, 1, h - 12, DARK)
        r.rect(-5, 6, 6, h - 12, GRAY_LIGHT)
        r.rect(-4, 7, 5, h - 14, BODY)
        r.late_rect(-6, 11, 6, 1, DARK)
        r.late_rect(-6, h - 12, 6, 1, DARK)
        r.late_rect(-7, yb + 1, 7, 7, DARK_DEEP)
        r.late_rect(-6, yb - 1, 7, 8, DARK)
        r.late_rect(-5, yb, 6, 6, MARK)
        r.late_rect(-5, yb, 6, 1, MARK_LIGHT)
        r.late_rect(-5, yb + 5, 6, 1, MARK_DARK)
        r.late_rect(-4, yb + 1, 4, 4, GRAY_LIGHT)
        r.late_rect(-3, yb + 2, 2, 2, DARK_DEEP)
        r.late_rect(-2, yb + 2, 1, 2, MARK_LIGHT)
    elif kind == HAMMER:
        yc = jround(h / 2)
        r.rect(-4, 0, 6, h, BODY)
        r.rect(-4, 0, 2, 5, GRAY)
        r.rect(-4, h - 5, 2, 5, GRAY)
        r.rect(-3, 5, 2, h - 10, MARK)
        r.late_rect(-4, 5, 1, h - 10, DARK)
        r.rect(-10, yc - 5, 6, 10, GRAY)
        r.rect(-8, yc - 4, 4, 8, DARK)
        r.rect(-7, yc - 3, 3, 6, MARK)
        r.rect(-11, yc - 6, 2, 12, DARK)
        r.late_rect(-10, yc - 4, 1, 8, GRAY_LIGHT)
        s = a.spark[0] if a.spark is not None else None
        surge = 3 if (s is not None and s < 0.14) else (2 if (s is not None and s < 0.25) else (1 if (s is not None and s < 0.35) else 0))
        piston_beat = (tq % 2) == 1
        fl = (11 if surge == 3 else (9 if surge == 2 else (7 if surge == 1 else (4, 5, 4, 3)[tq % 4])))
        tlen = 3 if fl >= 9 else (2 if fl >= 6 else 1)
        mlen = (fl * 2) // 3
        jlen = fl - 1
        clen = max(2, fl // 2)
        if surge == 3:
            r.late_rect(-12, yc - 4, 1, 8, MARK)
        r.late_rect(-11 - tlen, yc - 3, tlen, 6, MARK)
        r.late_rect(-11 - mlen, yc - 2, mlen, 4, MARK)
        if surge >= 1:
            r.late_rect(-11 - max(1, mlen // 2), yc - 2, max(1, mlen // 2), 4, MARK_LIGHT)
        r.late_rect(-11 - jlen, yc - 1, jlen, 2, MARK_LIGHT)
        r.late_rect(-11 - clen, yc - 1, clen, 2, BODY)
        r.late_rect(-12 - fl, yc - 1 + (tq % 2), 2, 1, MARK)
        if surge >= 2:
            r.late_rect(-11 - fl, yc - 1 + (tq % 2), 1, 1, MARK_LIGHT)
        trail(r, -12 - fl, yc - 1, extra)
        if ignited:
            ignite(r, -11, yc - 1, 2)
        if surge >= 2 or piston_beat:
            r.shift(-1)
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
        r.rect(-3, 3, 5, h - 6, BODY)
        r.rect(-2, 1, 4, 2, BODY)
        r.rect(-1, 0, 3, 1, GRAY)
        r.rect(-2, h - 3, 4, 2, BODY)
        r.rect(-1, h - 1, 3, 1, GRAY)
        r.rect(-6, 7, 3, 6, MARK)
        r.rect(-7, 9, 2, 3, GRAY)
        r.rect(-6, h - 13, 3, 6, MARK)
        r.rect(-7, h - 12, 2, 3, GRAY)
        r.rect(-5, mid - 5, 5, 10, MARK)
        r.late_rect(-4, mid - 4, 3, 8, MARK_DARK)
        r.late_rect(-3, mid - 3, 2, 6, MARK)
        r.late_rect(-2, mid - 2, 2, 1, BODY)
        r.late_rect(-2, mid + 1, 2, 1, BODY)
        ph = tq % 4
        dy = -1 if ph == 1 else (1 if ph == 3 else 0)
        fl = (2, 3, 2, 3)[ph] if moving else (0, 1, 0, 1)[ph]
        clen = 2 + fl // 2
        r.rect(-7, mid - 2, 2, 4, DARK)
        r.late_rect(-9, mid - 2, 2, 4, MARK)
        r.late_rect(-10 - fl, mid - 1 + dy, 3 + fl, 2, MARK_LIGHT)
        r.late_rect(-7 - clen, mid - 1 + dy, clen, 2, BODY)
        r.late_rect(-12 - fl, mid - 1 + dy + (ph % 2), 2, 1, MARK)
        trail(r, -12 - fl, mid - 1, extra)
        if ignited:
            ignite(r, -9, mid - 1, 2)
        p = tq % 2
        if a.vy < -0.5:
            r.late_rect(-13 - p, h - 8, 3, 3 + p, MARK)
            r.late_rect(-11, h - 3 + p, 2, 3, MARK)
            r.late_rect(-11, h - 10, 3, 4 + p, MARK_LIGHT)
            r.late_rect(-10, h - 6, 2, 4 + p, MARK_LIGHT)
            r.late_rect(-9, h - 11, 2, 3, BODY)
            r.late_rect(-9, h - 8, 1, 3, BODY)
            r.late_rect(-13 - p, h - 2 + p, 1, 1, BODY)
        elif a.vy > 0.5:
            r.late_rect(-13 - p, 5 - p, 3, 3 + p, MARK)
            r.late_rect(-11, -p, 2, 3, MARK)
            r.late_rect(-11, 6 - p, 3, 4 + p, MARK_LIGHT)
            r.late_rect(-10, 2 - p, 2, 4 + p, MARK_LIGHT)
            r.late_rect(-9, 8, 2, 3, BODY)
            r.late_rect(-9, 5, 1, 3, BODY)
            r.late_rect(-13 - p, 1 - p, 1, 1, BODY)
        if a.spark is not None and a.spark[0] < RING_SECONDS:
            ring(r, h, a.spark[0])
    elif kind == BLASTER:
        fr = None if a.fire is None else a.fire * 60
        recoil = fr is not None and fr < 3
        barrel = 1 if recoil else (2 if (fr is not None and fr < 8) else 3)
        r.rect(-3, 0, 3, h, BODY)
        r.rect(0, 2, 2, h - 4, BODY)
        r.rect(0, 1, 1, 1, BODY)
        r.rect(0, h - 2, 1, 1, BODY)
        r.rect(-6, 3, 3, 5, GRAY)
        r.rect(-6, h - 8, 3, 5, GRAY)
        for idx, ey in enumerate((5, h - 6)):
            r.rect(-7, ey - 1, 1, 3, DARK_DEEP)
            p = (tq + idx * 2) % 4
            fl = (6, 8, 7, 8)[p] if moving else (4, 5, 6, 5)[p]
            mlen = (fl + 1) // 2
            jlen = fl - 1
            clen = max(2, fl // 2)
            r.late_rect(-7 - mlen, ey - 1, mlen, 3, MARK)
            r.late_rect(-8, ey - 1, 1, 3, MARK_LIGHT)
            r.late_rect(-7 - jlen, ey, jlen, 1, MARK_LIGHT)
            r.late_rect(-7 - clen, ey, clen, 1, BODY)
            r.late_rect(-8 - fl, ey, 2, 1, MARK)
            if moving:
                s = (tq + idx) % 3
                r.late_rect(-9 - fl - s, ey - 1 + ((s + idx) % 3), 1, 1, MARK_LIGHT if s == 0 else MARK)
            trail(r, -8 - fl, ey, extra)
            if ignited:
                ignite(r, -8, ey, 1)
        r.late_rect(-3, mid - 4, 1, 2, MARK)
        r.late_rect(-1, mid - 4, 1, 2, MARK)
        r.late_rect(-2, mid - 2, 1, 1, MARK_DARK)
        r.late_rect(-2, mid - 1, 1, 2, MARK)
        r.late_rect(-2, mid + 1, 1, 1, MARK_DARK)
        r.late_rect(-3, mid + 2, 1, 2, MARK)
        r.late_rect(-1, mid + 2, 1, 2, MARK)
        r.rect(-1, 8, 1, 2, MARK)
        r.rect(2, 8, barrel, 2, GRAY)
        r.rect(-1, h - 10, 1, 2, MARK)
        r.rect(2, h - 10, barrel, 2, GRAY)
        if recoil:
            fx = 2 + barrel
            for fy in (7, h - 11):
                r.rect(fx, fy, 2, 4, MARK)
                r.rect(fx + 1, fy + 1, 3, 2, MARK_LIGHT)
                r.rect(fx + 1, fy + 1, 2, 2, BODY)
                r.rect(fx + 4, fy + 1, 2, 2, MARK_LIGHT)
        y0 = mid - 9
        r.rect(-6, y0, 3, 21, DARK)
        ammo = min(a.ammo, 6)
        fill = (0, 3, 6, 9, 13, 16, 19)[ammo]
        if fill > 0:
            top = y0 + 20 - fill
            r.rect(-6, top, 2, fill, MARK)
            r.rect(-6, top, 2, min(fill, 2), MARK_LIGHT)
        if recoil:
            r.shift(-1)
    elif kind == RUSH:
        r.rect(-3, 0, 5, h, BODY)
        r.rect(-6, 1, 3, 5, BODY)
        r.rect(-9, 0, 4, 3, MARK)
        r.rect(-11, 0, 2, 2, MARK_DARK)
        r.rect(-6, h - 6, 3, 5, BODY)
        r.rect(-9, h - 3, 4, 3, MARK)
        r.rect(-11, h - 2, 2, 2, MARK_DARK)
        r.rect(-3, mid - 4, 3, 8, DARK)
        r.rect(-2, mid - 3, 2, 6, MARK)
        r.late_rect(-1, mid - 2, 1, 4, MARK_LIGHT)
        r.rect(-5, mid - 2, 2, 4, GRAY)
        # postbruciatore: quattro pose irregolari, alone e punta che sfarfallano a 16 al secondo,
        # diamanti d'urto che scorrono e scintille
        p = tq % 4
        fz = flicker(a.t)
        fl = (11, 13, 12, 14)[p] if a.dashing else (5, 7, 6, 8)[p] + (2 if moving else 0)
        lean = 0 if a.dashing else (-1 if a.vy > 0.5 else (1 if a.vy < -0.5 else 0))
        olen = (fl + 1) // 2 + fz
        jlen = fl - 1
        clen = fl // 4 + 1
        r.late_rect(-5 - olen, mid - 2, olen, 4, MARK)
        r.late_rect(-5 - jlen, mid - 1 + lean, jlen, 2, MARK_LIGHT)
        r.late_rect(-5 - clen, mid - 1, clen, 2, BODY)
        for k in range(2):
            d = clen + 1 + tq % 3 + 3 * k
            if d < jlen - 1:
                r.late_rect(-6 - d, mid - 1 + lean, 1, 2, BODY)
        r.late_rect(-6 - fl, mid - 1 + lean + fz, 2, 1, MARK)
        if moving:
            sp = tq % 3
            r.late_rect(-7 - fl - sp, mid - 2 + (p + sp) % 4, 1, 1, MARK_LIGHT if sp == 0 else MARK)
        trail(r, -6 - fl, mid - 1, extra)
        if ignited:
            ignite(r, -5, mid - 1, 2)
        wlen = 4 if a.dashing else 2
        w1 = tq % 3
        w2 = (tq + 1) % 3
        wrole = MARK_LIGHT if a.dashing else MARK
        r.rect(-12 - w1 - wlen, 1, wlen, 1, wrole)
        r.rect(-12 - w2 - wlen, h - 2, wlen, 1, wrole)
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
        for u in range(-80, 20):
            c = role(u, v)
            if c == NONE and shadow and role(u + 1, v - 1) not in (NONE,):
                c = SHADOW
            if c != NONE:
                out[(u, v)] = c
    return out
