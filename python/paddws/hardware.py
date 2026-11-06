"""Utility di piattaforma e controller opzionali a encoder rotativo (Raspberry Pi + pigpio)."""

from __future__ import annotations

import logging
import queue
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from paddws.config import EncoderConfig

log = logging.getLogger(__name__)


def is_raspberry_pi() -> bool:
    try:
        return "Raspberry Pi" in Path("/proc/device-tree/model").read_text(errors="ignore")
    except OSError:
        return False


def enable_dpi_awareness() -> None:
    """Impedisce a Windows di scalare la finestra come bitmap sugli schermi ad alto DPI."""
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.user32.SetProcessDPIAware()
        except (AttributeError, OSError):
            pass


def shutdown_system() -> None:
    subprocess.run(["sudo", "shutdown", "-h", "now"], check=False)


class EncoderAction(Enum):
    ROTATE = "rotate"
    CLICK = "click"
    LONG_CLICK = "long_click"


@dataclass(frozen=True)
class EncoderEvent:
    player: int          # 0 = sinistra, 1 = destra
    action: EncoderAction
    value: int = 0


class Encoders:
    """Due encoder rotativi con pulsante.

    pigpio chiama le callback dal proprio thread: gli eventi vengono accodati
    e consumati dal loop di gioco tramite `poll()`.
    """

    def __init__(self, cfg: EncoderConfig) -> None:
        from paddws.vendor.pigpio_encoder import Rotary  # richiede il demone pigpio

        self._events: queue.SimpleQueue[EncoderEvent] = queue.SimpleQueue()
        pins = ((cfg.e1_clock_pin, cfg.e1_data_pin, cfg.e1_switch_pin),
                (cfg.e2_clock_pin, cfg.e2_data_pin, cfg.e2_switch_pin))
        self._rotaries = [Rotary(clk_gpio=clk, dt_gpio=dt, sw_gpio=sw) for clk, dt, sw in pins]
        for player, rotary in enumerate(self._rotaries):
            rotary.setup_switch(
                long_press=True,
                sw_gpio_short_callback=lambda p=player: self._push(p, EncoderAction.CLICK),
                sw_gpio_long_callback=lambda p=player: self._push(p, EncoderAction.LONG_CLICK),
            )

    @classmethod
    def create(cls, cfg: EncoderConfig) -> Encoders | None:
        if not cfg.enabled:
            return None
        try:
            return cls(cfg)
        except Exception as exc:  # modulo/demone pigpio assente, pin errati...
            log.error("Rotary encoders disabled: %s", exc)
            return None

    def _push(self, player: int, action: EncoderAction, value: int = 0) -> None:
        self._events.put(EncoderEvent(player, action, value))

    def configure(self, minimum: int, maximum: int, scale: int, start: int) -> None:
        """Imposta l'intervallo del contatore di entrambi gli encoder e li porta a `start`."""
        for player, rotary in enumerate(self._rotaries):
            rotary.setup_rotary(
                min=minimum, max=maximum, scale=scale, debounce=500,
                rotary_callback=lambda value, p=player: self._push(p, EncoderAction.ROTATE, value),
            )
            rotary.counter = start

    def poll(self) -> list[EncoderEvent]:
        events = []
        while not self._events.empty():
            events.append(self._events.get_nowait())
        return events
