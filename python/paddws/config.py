"""Configurazione: default tipizzati, caricamento JSON tollerante, salvataggio preferenze.

I valori nel file JSON sono espressi per la risoluzione di riferimento 800x480;
`Params.from_config` li scala alla dimensione del mondo configurata.
"""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, dataclass, field, fields, is_dataclass
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

Color = tuple[int, int, int]


@dataclass
class ResolutionConfig:
    width: int = 0      # 0 = automatica: proporzioni del monitor (4:3, 16:9, ...) con l'altezza data
    height: int = 480


def auto_width(height: int, screen_width: int, screen_height: int) -> int:
    """Larghezza del campo con le stesse proporzioni dello schermo: niente bande nere."""
    return max(1, round(height * screen_width / screen_height))


@dataclass
class GameConfig:
    title_bar: bool = True
    fps: int = 60                   # limite di frame, usato solo con vsync disattivato
    vsync: bool = True
    game_name: str = "PADD WS"
    fullscreen: bool = False
    keep_aspect: bool = True        # a schermo intero: bande nere invece di deformare
    serve_delay: float = 0.5        # secondi di attesa della palla al centro dopo un punto
    splash_time: float = 3.0        # non più usato (sostituito dall'attract): resta per i vecchi file
    free_play: bool = True          # senza monete; con False servono crediti: tasto 5, poi Start
    points_to_win: int = 11         # in due vince chi arriva per primo a questi punti
    lives: int = 3                  # palle a disposizione in singolo
    self_test: bool = True          # auto-test all'accensione nella sequenza attract
    difficulty: int = 1             # 0 facile, 1 normale, 2 difficile, 3 esperto (velocità della palla)
    attract_sound: bool = True      # suoni dell'attract (gettone e Start si sentono sempre)


@dataclass
class BallConfig:
    radius: float = 5
    radius_boost: float = 8
    radius_boost_fwd: float = 6


@dataclass
class PaddleConfig:
    width: float = 10
    height: float = 80
    start_pos: float = 50
    forward_pos: float = 200
    base_speed: float = 2
    max_speed: float = 15
    acceleration: float = 0.3
    fast_acceleration: float = 1
    deceleration: float = 2
    double_click_time: int = 300    # ms


@dataclass
class BoostConfig:
    multiplier: float = 2
    area_ratio: float = 4
    forward_multiplier: float = 1.5
    enable_area_decay: bool = True
    decay_rate: float = 0.8
    min_area_ratio: float = 20


@dataclass
class EncoderConfig:
    enabled: bool = False
    e1_clock_pin: int = 5
    e1_data_pin: int = 6
    e1_switch_pin: int = 13
    e2_clock_pin: int = 16
    e2_data_pin: int = 20
    e2_switch_pin: int = 21


@dataclass
class ColorsConfig:
    white: Color = (255, 255, 255)
    red: Color = (255, 0, 0)
    green: Color = (0, 255, 0)
    black: Color = (0, 0, 0)
    gray: Color = (50, 50, 50)
    lgray: Color = (180, 180, 180)


@dataclass
class CrtConfig:
    enabled: bool = False
    resolution_scale: float = 6.0
    hard_scan: float = -8.0
    hard_pix: float = -3.0
    warp_x: float = 0.03125
    warp_y: float = 0.04167
    mask_dark: float = 0.5
    mask_light: float = 1.5


@dataclass
class Config:
    resolution: ResolutionConfig = field(default_factory=ResolutionConfig)
    game: GameConfig = field(default_factory=GameConfig)
    ball: BallConfig = field(default_factory=BallConfig)
    paddle: PaddleConfig = field(default_factory=PaddleConfig)
    boost: BoostConfig = field(default_factory=BoostConfig)
    encoder: EncoderConfig = field(default_factory=EncoderConfig)
    colors: ColorsConfig = field(default_factory=ColorsConfig)
    crt_effects: CrtConfig = field(default_factory=CrtConfig)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _fill(instance: Any, data: dict[str, Any], path: str) -> None:
    """Copia le chiavi note di `data` in un'istanza dataclass, segnalando le altre."""
    known = {f.name: f for f in fields(instance)}
    for key, value in data.items():
        if key not in known:
            log.warning("Unknown config key '%s%s' ignored", path, key)
            continue
        current = getattr(instance, key)
        if is_dataclass(current):
            if isinstance(value, dict):
                _fill(current, value, f"{path}{key}.")
            else:
                log.warning("Config section '%s%s' must be an object", path, key)
        elif isinstance(current, tuple):
            setattr(instance, key, tuple(int(c) for c in value))
        elif isinstance(current, bool):
            setattr(instance, key, bool(value))
        else:
            setattr(instance, key, type(current)(value))


def config_from_dict(data: dict[str, Any]) -> Config:
    cfg = Config()
    _fill(cfg, data, "")
    return cfg


def load_config(path: Path) -> Config:
    """Carica `path`; se manca lo crea con i default, non sovrascrive mai un file rovinato."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        log.info("Config %s not found, writing defaults", path)
        cfg = Config()
        _write_json(path, cfg.to_dict())
        return cfg
    except json.JSONDecodeError as exc:
        log.error("Config %s is not valid JSON (%s); using defaults without overwriting", path, exc)
        return Config()
    return config_from_dict(data)


def save_preferences(path: Path, cfg: Config) -> None:
    """Salva solo le impostazioni modificabili durante il gioco, lasciando intatto il resto del file."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        data = cfg.to_dict()
    data.setdefault("game", {})["fullscreen"] = cfg.game.fullscreen
    data["game"]["difficulty"] = cfg.game.difficulty
    data["game"]["attract_sound"] = cfg.game.attract_sound
    data.setdefault("crt_effects", {})["enabled"] = cfg.crt_effects.enabled
    _write_json(path, data)


def _write_json(path: Path, data: dict[str, Any]) -> None:
    try:
        path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
    except OSError as exc:
        log.error("Cannot write config %s: %s", path, exc)
