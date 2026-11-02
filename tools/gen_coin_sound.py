"""Genera paddws/sounds/coin.wav: il "gettone" dei cabinati della versione Python, due note
in salita.

Uso:
    python tools/gen_coin_sound.py

Onda quadra ammorbidita (si 5 breve, poi mi 6 che si spegne), mono 16 bit a 48 kHz,
come gli altri effetti della versione Python (tools/gen_sounds.py).
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "paddws" / "sounds" / "coin.wav"
RATE = 48000

# (frequenza in Hz, durata in secondi, decadimento: costante di tempo in secondi)
NOTES = [(987.77, 0.07, 1.0), (1318.51, 0.30, 0.11)]
VOLUME = 0.45


def square(phase: float) -> float:
    """Quadra con le prime armoniche dispari: meno aspra di quella ideale."""
    return sum(math.sin(phase * k) / k for k in (1, 3, 5, 7)) * 4 / math.pi


def main() -> None:
    samples: list[int] = []
    for freq, length, tau in NOTES:
        n = int(length * RATE)
        for i in range(n):
            t = i / RATE
            attack = min(1.0, i / (0.002 * RATE))            # niente click all'attacco
            release = min(1.0, (n - i) / (0.004 * RATE))     # né alla fine della nota
            env = attack * release * math.exp(-t / tau)
            v = square(2 * math.pi * freq * t) * env * VOLUME
            samples.append(max(-32767, min(32767, int(v * 32767))))
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    print(f"{OUT} ({len(samples) / RATE:.2f} s)")


if __name__ == "__main__":
    main()
