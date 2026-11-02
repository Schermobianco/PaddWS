"""Logica di gioco indipendente dal motore (nessuna dipendenza da grafica, audio o hardware)."""

from paddws.core.match import TICK, Ball, Event, Match, Paddle, Side
from paddws.core.params import Params

__all__ = ["TICK", "Ball", "Event", "Match", "Paddle", "Params", "Side"]
