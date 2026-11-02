"""Parametri di gioco scalati alla dimensione del mondo."""

from __future__ import annotations

from dataclasses import dataclass

from paddws.config import Config

BASE_WIDTH = 800
BASE_HEIGHT = 480

# Livelli di difficoltà (0 facile, 1 normale, 2 difficile, 3 esperto): accelerazione della
# palla a ogni colpo e velocità massima (px per frame a 800x480), per il singolo e per la
# partita in due. In due il livello normale è il gioco originale. Come nel core Rust.
DIFFICULTY_NAMES = ("EASY", "NORMAL", "HARD", "EXPERT")
SPEEDS_1P = ((1.05, 8), (1.10, 10), (1.15, 12), (1.25, 15))
SPEEDS_2P = ((1.15, 6), (1.25, 8), (1.25, 10), (1.30, 12))


@dataclass(frozen=True)
class Params:
    width: int
    height: int
    scale: float                # media dei fattori di scala x/y

    ball_radius: int
    ball_radius_boost: int
    ball_radius_boost_fwd: int
    max_ball_speed_1p: int
    max_ball_speed_2p: int
    kspeed_1p: float
    kspeed_2p: float

    pad_width: int
    pad_height: int
    pad_start_pos: int
    pad_fwd_pos: int
    pad_max_speed: int
    pad_acceleration: float
    pad_fast_acceleration: float
    pad_deceleration: float

    boost_mul: float
    boost_area_ratio: float
    boost_fwd_mul: float
    boost_decay: bool
    boost_decay_rate: float
    boost_min_area_ratio: float

    serve_delay: float

    @classmethod
    def from_config(cls, cfg: Config) -> Params:
        w, h = cfg.resolution.width, cfg.resolution.height
        if w <= 0 or h <= 0:
            raise ValueError(f"world size not resolved: {w}x{h}")
        sx, sy = w / BASE_WIDTH, h / BASE_HEIGHT
        s = (sx + sy) / 2
        b, p, bo = cfg.ball, cfg.paddle, cfg.boost
        level = max(0, min(len(SPEEDS_1P) - 1, cfg.game.difficulty))
        (k1, max1), (k2, max2) = SPEEDS_1P[level], SPEEDS_2P[level]
        return cls(
            width=w,
            height=h,
            scale=s,
            ball_radius=int(b.radius * s),
            ball_radius_boost=int(b.radius_boost * s),
            ball_radius_boost_fwd=int(b.radius_boost_fwd * s),
            max_ball_speed_1p=int(max1 * s),
            max_ball_speed_2p=int(max2 * s),
            kspeed_1p=k1,
            kspeed_2p=k2,
            pad_width=int(p.width * sx),
            pad_height=int(p.height * sy),
            pad_start_pos=int(p.start_pos * sx),
            pad_fwd_pos=int(p.forward_pos * sx),
            pad_max_speed=int(p.max_speed * s),
            pad_acceleration=p.acceleration * s,
            pad_fast_acceleration=p.fast_acceleration * s,
            pad_deceleration=p.deceleration * s,
            boost_mul=bo.multiplier,
            boost_area_ratio=bo.area_ratio,
            boost_fwd_mul=bo.forward_multiplier,
            boost_decay=bo.enable_area_decay,
            boost_decay_rate=bo.decay_rate,
            boost_min_area_ratio=bo.min_area_ratio,
            serve_delay=cfg.game.serve_delay,
        )
