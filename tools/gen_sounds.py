"""Genera gli effetti sonori "classici" della versione Python: paddws/sounds/ping.wav, pong.wav,
boost.wav ed error.wav. Il gettone (coin.wav) lo genera tools/gen_coin_sound.py.

Uso:
    python tools/gen_sounds.py

Suoni originali nello stile degli arcade del 1972: onde quadre come quelle dei contatori TTL,
con le sole armoniche dispari fino alla nona (nessun aliasing a 48 kHz), un attacco e una fine
di pochi millisecondi per non fare click. Mono, 16 bit, 48 kHz. Le altre versioni suonano gli
effetti del SID (assets/sounds/sid).
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "paddws" / "sounds"
RATE = 48000
# volume medio (rms) dei campioni di prima, così il mixer non va ritoccato
TARGET_RMS = 0.245

# effetto: note (frequenza in Hz, durata in secondi), decadimento (costante di tempo in secondi,
# 0 = nessuno)
SOUNDS = {
    # bordo: quadra bassa e cortissima
    "ping": ([(246.0, 0.032)], 0.0),
    # colpo della racchetta: l'ottava sopra
    "pong": ([(491.0, 0.032)], 0.0),
    # boost: tre note in salita, veloci
    "boost": ([(491.0, 0.045), (659.3, 0.045), (982.0, 0.090)], 0.12),
    # punto: tono basso e lungo che si spegne
    "error": ([(246.0, 0.36)], 0.25),
}


def square(phase: float) -> float:
    """Quadra con le armoniche dispari fino alla nona."""
    return sum(math.sin(phase * k) / k for k in (1, 3, 5, 7, 9)) * 4 / math.pi


def render(notes: list[tuple[float, float]], tau: float) -> list[float]:
    out: list[float] = []
    phase = 0.0
    for freq, length in notes:
        n = int(length * RATE)
        for i in range(n):
            attack = min(1.0, i / (0.002 * RATE))
            release = min(1.0, (n - i) / (0.003 * RATE))
            env = attack * release * (math.exp(-i / RATE / tau) if tau else 1.0)
            phase += 2 * math.pi * freq / RATE
            out.append(square(phase) * env)
    return out


def write(name: str, samples: list[float]) -> None:
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    gain = min(TARGET_RMS / rms, 0.95 / max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", round(s * gain * 32767)) for s in samples)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def main() -> None:
    for name, (notes, tau) in SOUNDS.items():
        write(name, render(notes, tau))
        print(f"{name}.wav: {sum(d for _, d in notes):.3f} s")


if __name__ == "__main__":
    main()
