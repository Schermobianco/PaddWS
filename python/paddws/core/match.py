"""Simulazione di una partita di Pong.

Pura e deterministica (a parità di RNG): nessun codice di grafica, audio o input.
Le coordinate sono in pixel con origine in basso a sinistra e y verso l'alto.
Velocità e accelerazioni sono espresse per tick a 60 Hz: `step(dt)` scala tutto
di `dt / TICK`, così la sensazione di gioco non dipende dal frame rate.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from enum import Enum, IntEnum

from paddws.core.params import Params

TICK = 1 / 60


class Side(IntEnum):
    LEFT = 0
    RIGHT = 1

    @property
    def opponent(self) -> Side:
        return Side(1 - self)


class Event(Enum):
    WALL = "wall"       # la palla ha rimbalzato sul bordo alto/basso
    HIT = "hit"         # palla respinta da una racchetta
    BOOST = "boost"     # palla respinta con un boost
    SCORE = "score"     # è stato segnato un punto


@dataclass
class Ball:
    x: float
    y: float
    radius: float
    vx: float = 0.0
    vy: float = 0.0
    boost: float = 1.0  # moltiplicatore della velocità orizzontale

    @property
    def left(self) -> float:
        return self.x - self.radius

    @property
    def right(self) -> float:
        return self.x + self.radius

    @property
    def bottom(self) -> float:
        return self.y - self.radius

    @property
    def top(self) -> float:
        return self.y + self.radius


@dataclass
class Paddle:
    side: Side
    x: float
    y: float
    width: float
    height: float
    home_x: float
    fwd_x: float
    boost_ratio: float
    speed: float = 0.0
    direction: int = 0  # +1 su, -1 giù, 0 ferma
    fast: bool = False

    @property
    def left(self) -> float:
        return self.x - self.width / 2

    @property
    def right(self) -> float:
        return self.x + self.width / 2

    @property
    def bottom(self) -> float:
        return self.y - self.height / 2

    @property
    def top(self) -> float:
        return self.y + self.height / 2

    @property
    def at_home(self) -> bool:
        return self.x == self.home_x

    @property
    def boost_height(self) -> float:
        return self.height // self.boost_ratio

    def set_direction(self, direction: int, fast: bool = False) -> None:
        if direction * self.speed < 0:
            self.speed *= 0.3  # conserva un po' di slancio quando si inverte
        self.direction = direction
        self.fast = fast

    def update(self, k: float, p: Params) -> None:
        if self.direction:
            accel = p.pad_fast_acceleration if self.fast else p.pad_acceleration
            self.speed += accel * self.direction * k
            self.speed = max(-p.pad_max_speed, min(p.pad_max_speed, self.speed))
        elif abs(self.speed) > 0.1:
            decel = p.pad_deceleration * k
            self.speed = max(0.0, self.speed - decel) if self.speed > 0 else min(0.0, self.speed + decel)
        else:
            self.speed = 0.0

        half = self.height / 2
        y = self.y + self.speed * k
        if y < half or y > p.height - half:
            y = max(half, min(p.height - half, y))
            self.speed = 0.0
        self.y = y


class Match:
    def __init__(self, params: Params, players: int = 2, evo: bool = False,
                 rng: random.Random | None = None) -> None:
        if players not in (1, 2):
            raise ValueError("players must be 1 or 2")
        self.p = params
        self.players = players
        self.evo = evo and players == 2
        self.rng = rng or random.Random()

        w, h = params.width, params.height
        right_height = params.pad_height if players == 2 else h  # giocatore singolo: muro a tutta altezza
        self.paddles = (
            Paddle(Side.LEFT, params.pad_start_pos, h / 2, params.pad_width, params.pad_height,
                   home_x=params.pad_start_pos, fwd_x=params.pad_fwd_pos,
                   boost_ratio=params.boost_area_ratio),
            Paddle(Side.RIGHT, w - params.pad_start_pos, h / 2, params.pad_width, right_height,
                   home_x=w - params.pad_start_pos, fwd_x=w - params.pad_fwd_pos,
                   boost_ratio=params.boost_area_ratio),
        )
        self.ball = Ball(w / 2, h / 2, params.ball_radius)
        self.score = [0, 0]
        self.best = 0               # record del giocatore singolo
        self.serve_timer = 0.0
        self.serve(self.rng.choice((Side.LEFT, Side.RIGHT)))

    @property
    def max_ball_speed(self) -> float:
        return self.p.max_ball_speed_2p if self.players == 2 else self.p.max_ball_speed_1p

    # ----------------------------------------------------------------- comandi

    def serve(self, toward: Side) -> None:
        p, b = self.p, self.ball
        if self.players == 1:
            toward = Side.LEFT
        b.x, b.y = p.width / 2, p.height / 2
        b.boost, b.radius = 1.0, p.ball_radius
        vx = self.rng.randrange(2, 4) * p.scale
        vy = self.rng.randrange(1, 3) * p.scale
        b.vx = -vx if toward is Side.LEFT else vx
        b.vy = vy * self.rng.choice((-1, 1))
        self.serve_timer = p.serve_delay

    def set_paddle_top(self, side: Side, offset: float) -> None:
        """Posiziona una racchetta in base alla distanza dal bordo alto (input dell'encoder)."""
        pad = self.paddles[side]
        half = pad.height / 2
        pad.y = max(half, min(self.p.height - half, self.p.height - offset - half))
        pad.speed = 0.0

    def toggle_forward(self, side: Side) -> list[Event]:
        """Mossa EVO: la racchetta scatta in avanti (o torna indietro). Se intercetta la palla la potenzia."""
        if not self.evo:
            return []
        pad = self.paddles[side]
        if not pad.at_home:
            pad.x = pad.home_x
            return []
        old_x, pad.x = pad.x, pad.fwd_x
        if self._ball_in_forward_area(pad, old_x):
            return [self._forward_boost(side)]
        return []

    # ------------------------------------------------------------- simulazione

    def step(self, dt: float) -> list[Event]:
        k = dt / TICK
        events: list[Event] = []
        for pad in self.paddles:
            pad.update(k, self.p)

        if self.serve_timer > 0:
            self.serve_timer -= dt
            return events

        b, p = self.ball, self.p
        prev_x, prev_y = b.x, b.y
        b.x += b.vx * b.boost * k
        b.y += b.vy * k

        if b.top >= p.height - 1:
            b.y = p.height - 1 - b.radius
            b.vy = -abs(b.vy)
            events.append(Event.WALL)
        elif b.bottom <= 1:
            b.y = 1 + b.radius
            b.vy = abs(b.vy)
            events.append(Event.WALL)

        pad = self.paddles[Side.LEFT if b.vx < 0 else Side.RIGHT]
        contact_y = self._contact(pad, prev_x, prev_y)
        if contact_y is not None:
            b.y = contact_y
            events.append(self._bounce(pad))
        elif b.left <= 0:
            events.append(self._point(Side.RIGHT))
        elif b.right >= p.width:
            events.append(self._point(Side.LEFT))
        return events

    def _contact(self, pad: Paddle, prev_x: float, prev_y: float) -> float | None:
        """La y della palla nel momento in cui tocca `pad` nell'ultimo spostamento, o None.

        Fa scorrere il bordo anteriore della palla attraverso la faccia della
        racchetta, così le palle veloci non possono attraversarla; poi ripiega
        su un semplice test di sovrapposizione.
        """
        b = self.ball
        r = b.radius
        if pad.side is Side.LEFT:
            if prev_x < pad.x:
                return None  # già dietro la racchetta
            face, prev_edge, edge = pad.right, prev_x - r, b.x - r
            crossed = prev_edge >= face > edge
        else:
            if prev_x > pad.x:
                return None
            face, prev_edge, edge = pad.left, prev_x + r, b.x + r
            crossed = prev_edge <= face < edge

        if crossed:
            t = (prev_edge - face) / (prev_edge - edge)
            y = prev_y + (b.y - prev_y) * t
            if y - r <= pad.top and y + r >= pad.bottom:
                return y
        if b.left <= pad.right and b.right >= pad.left and b.bottom <= pad.top and b.top >= pad.bottom:
            return b.y
        return None

    def _reflection(self, pad: Paddle) -> float:
        """Velocità verticale aggiunta dalla racchetta: proporzionale alla distanza dal centro,
        fortemente smorzata dentro l'area boost EVO."""
        b = self.ball
        size = pad.height
        if self.evo:
            bh = pad.boost_height
            start = (size - bh) // 2
            rel = b.y - (pad.y - size // 2)
            if bh > 0 and start <= rel <= start + bh:
                center = start + bh // 2
                return abs(b.vx) * ((rel - center) / (bh / 2)) * 0.2
        return abs(b.vx) * ((b.y - pad.y) / (size / 2))

    def _bounce(self, pad: Paddle) -> Event:
        b, p = self.ball, self.p
        reflection = self._reflection(pad)
        b.vy += reflection
        if abs(b.vx) < abs(b.vy):  # mai più ripida di 45 gradi
            b.vy = math.copysign(abs(b.vx), b.vy)

        event = Event.HIT
        if self.evo and b.boost == 1 and abs(reflection) < abs(b.vx * pad.boost_height / pad.height / 2):
            b.boost, b.radius = p.boost_mul, p.ball_radius_boost
            self._shrink_boost_area(pad)
            event = Event.BOOST
        else:
            b.boost, b.radius = 1.0, p.ball_radius

        b.x = pad.right + b.radius if pad.side is Side.LEFT else pad.left - b.radius
        b.vx = -b.vx
        # in singolo il muro rimanda la palla senza accelerarla: accelerano solo i colpi del giocatore
        single_wall = self.players == 1 and pad.side is Side.RIGHT
        if not single_wall and abs(b.vx) < self.max_ball_speed:
            kspeed = p.kspeed_2p if self.players == 2 else p.kspeed_1p
            b.vx *= kspeed
            b.vy *= kspeed

        if self.players == 1 and pad.side is Side.RIGHT:
            self.score[Side.LEFT] += 1
        return event

    def _point(self, scorer: Side) -> Event:
        if self.players == 2:
            self.score[scorer] += 1
            for pad in self.paddles:
                pad.boost_ratio = self.p.boost_area_ratio
        else:
            self.best = max(self.best, self.score[Side.LEFT])
            self.score[Side.LEFT] = 0
        self.serve(scorer.opponent)
        return Event.SCORE

    def _shrink_boost_area(self, pad: Paddle) -> None:
        if self.p.boost_decay:
            pad.boost_ratio = min(pad.boost_ratio / self.p.boost_decay_rate, self.p.boost_min_area_ratio)

    def _ball_in_forward_area(self, pad: Paddle, old_x: float) -> bool:
        b = self.ball
        if not (b.bottom <= pad.top and b.top >= pad.bottom):
            return False
        half = pad.width // 2
        if pad.side is Side.LEFT:
            return old_x + half <= b.left <= pad.x + half and b.vx < 0
        return pad.x - half <= b.right <= old_x - half and b.vx > 0

    def _forward_boost(self, side: Side) -> Event:
        b, p = self.ball, self.p
        if b.boost == 1:
            b.boost, b.radius = p.boost_fwd_mul, p.ball_radius_boost_fwd
            event = Event.BOOST
        else:
            b.boost, b.radius = 1.0, p.ball_radius
            event = Event.HIT
        b.vx = abs(b.vx) * 1.2 if side is Side.LEFT else -abs(b.vx) * 1.2
        b.vy += self.rng.uniform(-1, 1) * p.scale
        return event
