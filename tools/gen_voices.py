"""Genera le voci della CHALLENGE: il nome dell'avversario detto come dal SID con il trucco del
registro del volume ($D418), comune a PC, MiSTer e C64.

Uso:
    python tools/gen_voices.py            (voci da espeak-ng, poi la ROM del MiSTer)
    python tools/gen_voices.py --mister   (solo la ROM del MiSTer dai .raw4 già nel repository)
    python tools/gen_voices.py --moves    (solo le urla delle mosse speciali)

Richiede espeak-ng portable in C:\\DEV\\@Compiler\\espeak-ng (cartella cambiabile con la
variabile PADDWS_COMPILERS, come gli altri strumenti); i file generati sono nel repository, quindi
serve solo per rifarli. Per ogni tipo di racchetta (in ordine di `PaddleKind`):
- `assets/sounds/voice/<nome>.raw4`: campioni a 4 bit (0-15, 8 = silenzio) a `RATE` Hz, due per
  byte, prima il nibble alto; è quello che suonano il C64 e il MiSTer;
- `assets/sounds/voice/<nome>.wav`: gli stessi campioni a 22.050 Hz, tenuti come li tiene il
  registro del SID, per il gioco su PC e web.

Per il core MiSTer `mister/rtl/gen/sid_voices.hex` (i .raw4 uno dopo l'altro, un byte per riga) e
`sid_voices.vh` (inizio e lunghezza in byte di ogni voce, frequenza dei campioni, numeri delle voci
di partita): li legge `rtl/pong_sid.v`. Voci 0-6 i nomi degli avversari (`PaddleKind`), suonati
scrivendo il volume del SID; 7-8 le urla delle mosse (`Special`), 9 READY, 10 GO e 11 YOU WIN,
sommati come campioni all'uscita audio senza toccare il SID (indirizzi a 15 bit: la ROM supera i
16 KB).

Voce "urlata" scelta dall'utente (al posto di quella grave e lenta di prima): espeak-ng
`en-us+m3` acuta e veloce, con l'enfasi forte dell'SSML, il soffio dell'urlo (rumore che segue
l'inviluppo, ripetibile) e una compressione forte perché a 4 bit resti piena.

Mosse speciali di NEXT: con la stessa voce chi le esegue grida il nome della mossa, come nei
picchiaduro (parole nostre): `assets/sounds/voice/move_straight.*` e `move_rise.*`, nell'ordine
di `Special`. CHALLENGE: "READY?" all'inizio della partita e "GO!", ancora più urlato (più acuto,
più saturo, più fiato), al lancio della palla: `ready.*` e `go.*`.
"""

from __future__ import annotations

import array
import math
import os
import random
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sounds" / "voice"
MISTER = ROOT / "mister" / "rtl" / "gen"
COMPILERS = Path(os.environ.get("PADDWS_COMPILERS", r"C:\DEV\@Compiler"))
ESPEAK = COMPILERS / "espeak-ng" / "eSpeak NG"

RATE = 5000     # campioni al secondo (il C64 li suona con un interrupt del timer)
PLAY = 22050    # frequenza dei WAV per il PC

# nomi nell'ordine di `PaddleKind` (rust/core/src/next.rs)
NAMES = ["ARCADE", "TITAN", "HAMMER", "TWIST", "BLASTER", "RUSH", "GUARDIAN"]

VOICE = "en-us+m3"
SPEED = 175     # parole al minuto
PITCH = 80
RANGE = 99      # ampiezza delle variazioni di tono
DRIVE = 4.0     # compressione (tanh)
SHOUT_BREATH = 0.18   # fiato: rumore che segue l'inviluppo della voce
SHOUT_SEED = 7        # rumore ripetibile

# urla delle mosse speciali, nell'ordine di `Special` (rust/core/src/next.rs)
MOVES = [("move_straight", "STRAIGHT SHOT"), ("move_rise", "RISING STRIKE")]
# CHALLENGE: inizio della partita; il GO con i parametri della voce cambiati (scelto dall'utente)
CALLS = [("ready", "READY?", {}),
         ("go", "GO", {"PITCH": 99, "DRIVE": 6.0, "SHOUT_BREATH": 0.28, "SPEED": 160}),
         # vittoria, da annunciatore di sala: grave, "YOU" breve, pausa, "WIN" allungato che sale
         ("you_win",
          '<prosody rate="medium" pitch="-10%">YOU</prosody><break time="120ms"/>'
          '<prosody rate="slow" pitch="+15%">WIN</prosody>',
          {"PITCH": 35, "SPEED": 150, "RANGE": 90, "DRIVE": 3.0, "SHOUT_BREATH": 0.12})]


def speak(text: str, path: Path) -> None:
    ssml = (
        '<speak><prosody volume="x-loud">'
        f'<emphasis level="strong">{text}!</emphasis>'
        "</prosody></speak>"
    )
    subprocess.run(
        [str(ESPEAK / "espeak-ng.exe"), f"--path={ESPEAK}", "-m", "-v", VOICE, "-s", str(SPEED),
         "-p", str(PITCH), "-P", str(RANGE), "-w", str(path), ssml],
        check=True,
    )


def read(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path)) as w:
        rate = w.getframerate()
        data = array.array("h", w.readframes(w.getnframes()))
    return [s / 32768.0 for s in data], rate


def trim(x: list[float], level: float = 0.02) -> list[float]:
    """Toglie il silenzio prima e dopo (con un attimo di margine)."""
    idx = [i for i, s in enumerate(x) if abs(s) > level]
    return x[max(0, idx[0] - 40): idx[-1] + 200] if idx else x


def resample(x: list[float], src: int, dst: int) -> list[float]:
    """Media mobile come passa basso grezzo, poi interpolazione lineare."""
    k = max(1, round(src / dst))
    smooth = [sum(x[max(0, i - k + 1): i + 1]) / k for i in range(len(x))]
    out = []
    for i in range(int(len(x) * dst / src)):
        p = i * src / dst
        j = int(p)
        a = smooth[min(j, len(x) - 1)]
        b = smooth[min(j + 1, len(x) - 1)]
        out.append(a + (b - a) * (p - j))
    return out


def quantize(x: list[float]) -> list[int]:
    """Normalizza, comprime e porta ai 16 livelli del registro del volume (8 = silenzio)."""
    peak = max(abs(s) for s in x) or 1.0
    return [max(0, min(15, round(7.5 + 7.5 * math.tanh(DRIVE * s / peak) / math.tanh(DRIVE))))
            for s in x]


def breath(x: list[float], rng: random.Random) -> list[float]:
    """Normalizza e aggiunge il fiato dell'urlo: rumore che segue l'inviluppo della voce."""
    peak = max(abs(s) for s in x) or 1.0
    env = 0.0
    out = []
    for s in x:
        env = max(abs(s) / peak, env * 0.999)
        out.append(s / peak + SHOUT_BREATH * env * (rng.random() * 2 - 1))
    return out


def shout(text: str, base: Path, rng: random.Random) -> None:
    """`text` urlato: campioni a 4 bit (.raw4) e WAV per il PC."""
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "voce.wav"
        speak(text, src)
        x, rate = read(src)
    q = quantize(resample(trim(breath(x, rng)), rate, RATE))
    base.with_suffix(".raw4").write_bytes(pack(q))
    write_wav(q, base.with_suffix(".wav"))
    print(f"{text:13s} {len(q) / RATE:.2f} s, {len(pack(q))} byte")


def write_moves() -> None:
    """Urla delle mosse speciali e READY / GO della CHALLENGE, con il rumore ripetibile."""
    rng = random.Random(SHOUT_SEED)
    for name, text in MOVES:
        shout(text, OUT / name, rng)
    g = globals()
    for name, text, changes in CALLS:
        saved = {k: g[k] for k in changes}
        g.update(changes)
        shout(text, OUT / name, random.Random(SHOUT_SEED))
        g.update(saved)


def pack(q: list[int]) -> bytes:
    if len(q) % 2:
        q = q + [8]
    return bytes((q[i] << 4) | q[i + 1] for i in range(0, len(q), 2))


def write_wav(q: list[int], path: Path) -> None:
    out = array.array("h")
    for i in range(int(len(q) * PLAY / RATE)):
        v = q[min(len(q) - 1, int(i * RATE / PLAY))]
        out.append(int((v - 7.5) / 7.5 * 30000))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(PLAY)
        w.writeframes(out.tobytes())


def write_mister() -> None:
    """ROM delle voci del core MiSTer dai file .raw4: i nomi nell'ordine di `PaddleKind`, poi le urla
    delle mosse nell'ordine di `Special`, READY, GO e YOU WIN (indice a 4 bit, indirizzi a 15 bit)."""
    voices = ([(name.lower(), name) for name in NAMES] + [(name, text) for name, text in MOVES] +
              [(name, text) for name, text, _ in CALLS])
    rom = bytearray()
    starts, lens = [], []
    for name, _ in voices:
        raw = (OUT / f"{name}.raw4").read_bytes()
        starts.append(len(rom))
        lens.append(len(raw))
        rom += raw
    if len(voices) > 16 or len(rom) > 1 << 15 or max(lens) >= 1 << 12:
        raise SystemExit("voci troppe o troppo lunghe per l'indice a 4 bit, gli indirizzi a 15 bit "
                         "e le lunghezze a 12 bit")
    first_move = len(NAMES)
    lines = [
        "// Generato da tools/gen_voices.py: non modificare a mano.",
        "// Voci \"da SID\", campioni a 4 bit (8 = silenzio), due per byte, prima il nibble alto: 0-6 i nomi",
        "// degli avversari della CHALLENGE (`PaddleKind`), 7-8 le urla delle mosse speciali (`Special`),",
        "// 9 READY e 10 GO della CHALLENGE, 11 YOU WIN (vittoria contro la CPU e finale della CHALLENGE).",
        f"localparam VOICE_RATE = {RATE};",
        f"localparam VOICE_ROM_SIZE = {len(rom)};",
        f"localparam [3:0] VOICE_STRAIGHT = 4'd{first_move};",
        f"localparam [3:0] VOICE_RISE = 4'd{first_move + 1};",
        f"localparam [3:0] VOICE_READY = 4'd{first_move + len(MOVES)};",
        f"localparam [3:0] VOICE_GO = 4'd{first_move + len(MOVES) + 1};",
        f"localparam [3:0] VOICE_YOU_WIN = 4'd{first_move + len(MOVES) + 2};",
        "function [14:0] voice_start(input [3:0] id);",
        "    case (id)",
        *[f"        4'd{i}: voice_start = 15'd{s};   // {voices[i][1].split('<')[0] or 'YOU WIN'}"
          for i, s in enumerate(starts)],
        "        default: voice_start = 15'd0;",
        "    endcase",
        "endfunction",
        "function [11:0] voice_len(input [3:0] id);",
        "    case (id)",
        *[f"        4'd{i}: voice_len = 12'd{n};   // {n / RATE * 2:.2f} s" for i, n in enumerate(lens)],
        "        default: voice_len = 12'd0;",
        "    endcase",
        "endfunction",
    ]
    (MISTER / "sid_voices.hex").write_text("\n".join(f"{b:02x}" for b in rom) + "\n", newline="\n")
    (MISTER / "sid_voices.vh").write_text("\n".join(lines) + "\n", newline="\n")
    print(f"{MISTER / 'sid_voices.hex'}: {len(rom)} byte ({len(rom) * 8} bit)")


def main() -> None:
    if "--mister" in sys.argv[1:]:
        write_mister()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    if "--moves" in sys.argv[1:]:
        write_moves()
        return
    rng = random.Random(SHOUT_SEED)
    for name in NAMES:
        shout(name, OUT / name.lower(), rng)
    write_moves()
    write_mister()


if __name__ == "__main__":
    main()
