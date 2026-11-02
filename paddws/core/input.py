"""Utility di input condivise da tutti i front-end."""

from __future__ import annotations

from collections.abc import Hashable


class DoubleTap:
    """Rileva un tasto premuto due volte entro `window_ms` (modalità veloce della racchetta)."""

    def __init__(self, window_ms: float) -> None:
        self.window_ms = window_ms
        self._last: dict[Hashable, float] = {}

    def press(self, key: Hashable, now_ms: float) -> bool:
        last = self._last.get(key)
        self._last[key] = now_ms
        return last is not None and now_ms - last <= self.window_ms
