"""Musiche ed effetti del SID: dati per il player in Verilog (mister/rtl/pong_sid.v) e per il
player in 6502 della versione C64 (c64/src/sid.s), che leggono gli stessi byte.

Uscite (vanno nel repository, così la sintesi e l'assemblaggio non richiedono Python; un file
uguale a quello che c'è già non si riscrive):
  mister/rtl/gen/sid_music.hex   ROM a 8 bit: tabella delle frequenze, strumenti, tracce
  mister/rtl/gen/sid_music.vh    indirizzi di tabelle, canzoni ed effetti
  c64/gen/sid_music.bin          la stessa ROM, con le frequenze per il clock del C64 PAL
  c64/gen/sid_freq_ntsc.bin      tabella delle frequenze per il clock NTSC
  c64/gen/sid_music.inc          indirizzi per l'assembler
  c64/gen/themeK_V.bin           tracce dei temi di CHALLENGE (tema K, voce V), per i file voce
  c64/gen/ending.bin             tracce del finale di CHALLENGE (ENDING), per il finale del C64

Le versioni PC, Raspberry e web leggono la stessa ROM (mister/rtl/gen/sid_music.hex) con il port
in Rust del player e un SID Rust (rust/sid), che suonano le musiche in tempo reale; gli effetti
sono WAV registrati dal SID simulato con Verilator (mister/sim/sid/render.ps1).

Formato di una traccia (un byte per comando, il player avanza a 50 Hz):
  0x00-0x5F nota (0 = C0), poi la durata in frame
  0x60      pausa, poi la durata in frame
  0x70+i    strumento i
  0x80      scivolata: il byte dopo (con segno) si somma alla frequenza a ogni frame
  0x90+m    arpeggio: 0 spento, 1 minore (0, 3, 7), 2 maggiore (0, 4, 7), 3 ottava (0, 12)
  0xA0+l    taglio del filtro: l i 3 bit bassi del taglio a 11 bit, il byte dopo gli 8 alti (cioè
            $D415 e $D416); si scrive subito
  0xB0      scivolata del taglio: i due byte dopo (basso, alto: 16 bit con segno, in 1/32 di passo
            del taglio) si sommano al taglio a ogni passo della canzone, prima dei canali; 0 la ferma
  0xFE      ricomincia la traccia
  0xFF      fine: la voce tace

Il taglio il player lo tiene a 16 bit, con 5 bit di frazione (taglio a 11 bit = valore >> 5): il
comando del taglio azzera la frazione, la scivolata si somma a 16 bit senza saturazione (il
generatore controlla che il taglio resti tra 0 e 2047, check_cutoff). Con la scivolata accesa, a
ogni passo della canzone servito (nel bullet time uno su due) il player scrive $D415 =
(valore >> 5) & 7 e $D416 = valore >> 8, anche se non sono cambiati.

Strumento, 8 byte: forma d'onda, attacco/decadimento, sostegno/rilascio, impulso basso e alto,
frame di rilascio, $D417, $D418. Uno strumento senza filtro ha 0 nel byte 6 e non tocca il filtro;
uno nel filtro ha il suo $D417 (risonanza nei bit 4-7, la voce che lo suona nel bit 0 o 1: la mette
il generatore, ogni strumento nel filtro sta in una sola voce) e il suo $D418 (modo nei bit 4-6:
$10 passa-basso, $20 passa-banda, $40 passa-alto; volume 15). Il filtro è uno per tutto il SID:
  - vale solo sulle voci 1 e 2 (tracce "bass" e "lead"): la voce 3 non passa mai dal filtro, così gli
    effetti (sempre sulla voce 3) e la terza traccia restano puliti. Comandi e strumenti del filtro
    stanno solo nelle tracce delle voci 1 e 2, mai negli effetti né nella presentazione (INTRO);
  - a ogni nota di uno strumento nel filtro, dopo il gate, se i suoi $D417 e $D418 sono diversi da
    quelli che il player sa nel SID (ne tiene una copia), il player scrive taglio ($D415, $D416),
    $D417 e $D418; altrimenti niente;
  - all'inizio di una canzone $D418 = $0F come sempre (modo spento) e $D417 = 0 (nessuna voce nel
    filtro); la scivolata si ferma, il taglio resta;
  - la voce digitalizzata (pong_sid.v; c64/src/voice.s) usa $D418 per i campioni con il nibble alto
    a 0 e le voci 2 e 3 (sul C64 tutte e tre) per il DC: all'inizio scrive $D417 = 0 (nessuna voce
    nel filtro) e alla fine $D418 = $0F come prima; intanto la copia di $D417 del player torna a 0,
    così la prima nota nel filtro dopo la voce (il tema della CHALLENGE parte mentre la voce si
    spegne, READY e GO cadono sul tema) riscrive tutto il filtro.

Notazione usata qui: "A4/24" nota e durata, "r/12" pausa, "i2" strumento, "s+20" scivolata,
"a1" arpeggio, "f400" taglio (0-2047), "w-64" scivolata del taglio (in 1/32 di passo per frame:
-64 = due passi), "loop" alla fine per ripetere. Tutte le musiche sono originali.

Uso:  python tools/gen_sid_music.py
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "mister" / "rtl" / "gen"
C64_OUT = ROOT / "c64" / "gen"

SID_CLOCK = 1_000_000          # il SID del core gira a 1 MHz (20 MHz / 20)
PAL_CLOCK = 985_248            # clock del C64 PAL e NTSC: stesse note, registri diversi
NTSC_CLOCK = 1_022_727
NOTES = 96                     # C0 .. B7
FRAME_HZ = 50

NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}

# Filtro dello strumento (byte 6 e 7): risonanza 0-15 nel $D417 (la voce la aggiunge build) e modo
# nel $D418, con il volume a 15
LP, BP, HP = 0x10, 0x20, 0x40


def filt(res: int, mode: int) -> tuple[int, int]:
    assert 0 <= res <= 15 and mode in (LP, BP, HP, LP | BP, LP | HP, BP | HP, LP | BP | HP), (res, mode)
    return res << 4, mode | 0x0F


# Strumenti: forma d'onda (registro di controllo senza gate), attacco/decadimento,
# sostegno/rilascio, larghezza dell'impulso (12 bit), frame di rilascio prima della fine della nota;
# per quelli nel filtro anche la risonanza e il $D418 (filt).
INSTRUMENTS = [
    # 0 basso: impulso stretto, pizzicato
    (0x40, 0x09, 0x00, 0x300, 1),
    # 1 accordo in arpeggio: impulso quadro, sostenuto
    (0x40, 0x00, 0xA4, 0x800, 1),
    # 2 melodia: dente di sega, attacco morbido
    (0x20, 0x26, 0x98, 0x000, 2),
    # 3 campanella: triangolo, decadimento lungo
    (0x10, 0x0A, 0x00, 0x000, 1),
    # 4 effetti: impulso, breve
    (0x40, 0x06, 0x00, 0x800, 0),
    # 5 rumore: per punto ed esplosioni
    (0x80, 0x09, 0x00, 0x000, 0),
    # 6 effetti: dente di sega
    (0x20, 0x08, 0x00, 0x000, 0),
    # 7 melodia morbida: triangolo sostenuto
    (0x10, 0x28, 0xA8, 0x000, 2),
    # 8 cassa: impulso quadro che decade in fretta, suonato a note da un frame che scendono. Il
    # gate resta aperto (rilascio 0), quindi è una scivolata di tono veloce; l'ultima nota passa a
    # uno strumento che chiude il gate (la coda, 12, o il basso), altrimenti la nota dopo
    # erediterebbe l'inviluppo già spento
    (0x40, 0x07, 0x00, 0x800, 0),
    # 9 basso profondo (HAMMER): impulso largo, sostenuto, per le ottave 1 e 2, nel passa-basso con
    # la risonanza; il taglio lo muovono i comandi della traccia
    (0x40, 0x04, 0xD6, 0x700, 1, *filt(12, LP)),
    # 10 charleston: rumore acuto, cortissimo
    (0x80, 0x02, 0x00, 0x000, 1),
    # 11 rullante: rumore, breve
    (0x80, 0x07, 0x00, 0x000, 1),
    # 12 coda della cassa: come la 8, ma chiude il gate prima della fine
    (0x40, 0x07, 0x00, 0x800, 1),
    # 13 melodia nel filtro: il dente di sega del 2 nel passa-basso, poca risonanza (aperture)
    (0x20, 0x26, 0x98, 0x000, 2, *filt(5, LP)),
    # 14 basso del finale (ENDING): come il 9 ma senza filtro, che lì è di HAMMER
    (0x40, 0x04, 0xD6, 0x700, 1),
    # 15 motivo del finale (ENDING): impulso breve nel passa-basso con risonanza, il taglio lo
    # aprono e lo chiudono i comandi della traccia
    (0x40, 0x06, 0x50, 0x600, 1, *filt(10, LP)),
]


def freq_reg(note: int, clock: int = SID_CLOCK) -> int:
    """Registro di frequenza del SID per la nota (0 = C0); A4 = 57 = 440 Hz."""
    hz = 440.0 * 2 ** ((note - 57) / 12)
    return min(0xFFFF, round(hz * (1 << 24) / clock))


def freq_table(clock: int) -> list[int]:
    """Tabella delle frequenze: byte basso e alto di ogni nota."""
    out: list[int] = []
    for n in range(NOTES):
        f = freq_reg(n, clock)
        out += [f & 0xFF, f >> 8]
    return out


def parse_note(tok: str) -> int:
    name, octave = (tok[:2], tok[2:]) if len(tok) > 2 and tok[1] == "#" else (tok[:1], tok[1:])
    return NAMES[name] + 12 * int(octave)


def assemble(track: str) -> tuple[list[int], int]:
    """Traccia in notazione -> byte e durata totale in frame."""
    out: list[int] = []
    frames = 0
    toks = track.split()
    for tok in toks:
        if tok == "loop":
            out.append(0xFE)
            continue
        if tok[0] == "i":
            assert int(tok[1:]) < len(INSTRUMENTS) <= 16, tok
            out.append(0x70 + int(tok[1:]))
        elif tok[0] == "s":
            out += [0x80, int(tok[1:]) & 0xFF]
        elif tok[0] == "a" and tok[1:].isdigit():
            out.append(0x90 + int(tok[1:]))
        elif tok[0] == "f":
            fc = int(tok[1:])
            assert 0 <= fc <= 0x7FF, tok
            out += [0xA0 | fc & 7, fc >> 3]
        elif tok[0] == "w":
            v = int(tok[1:])
            assert -0x8000 <= v <= 0x7FFF, tok
            out += [0xB0, v & 0xFF, v >> 8 & 0xFF]
        else:
            what, dur = tok.split("/")
            d = int(dur)
            assert 1 <= d <= 255, tok
            frames += d
            out += [0x60, d] if what == "r" else [parse_note(what), d]
    if not out or out[-1] != 0xFE:
        out.append(0xFF)
    return out, frames


def bars(*parts: str) -> str:
    return " ".join(parts)


FILTER_TOKENS = ("f", "w")


def uses_filter(track: str) -> bool:
    """La traccia usa il filtro: comandi del taglio o strumenti nel filtro."""
    for tok in track.split():
        if tok[0] in FILTER_TOKENS and tok[1:2] in "0123456789+-" and tok[1:]:
            return True
        if tok[0] == "i" and len(INSTRUMENTS[int(tok[1:])]) > 5:
            return True
    return False


# ----------------------------------------------------------------------------- musiche
# Battuta = 96 frame (4 tempi da 24 a 50 Hz, 125 BPM).

def bass_bar(root: str, low: int) -> str:
    """Basso a ottave, otto crome."""
    return " ".join(f"{root}{low + (i % 2)}/12" for i in range(8))


TITLE_CHORDS = [("A", 1), ("F", 2), ("C", 2), ("G", 2), ("A", 1), ("F", 2), ("G", 2), ("E", 2)]
TITLE_LEAD = [
    "E5/24 A5/24 G5/12 E5/12 C5/24",
    "F5/36 E5/12 C5/24 A4/24",
    "G4/24 C5/24 E5/24 G5/24",
    "D5/48 B4/24 G4/24",
    "A4/12 C5/12 E5/12 A5/12 G5/24 E5/24",
    "F5/24 A5/24 C6/24 A5/24",
    "B5/36 A5/12 G5/24 D5/24",
    "E5/48 G#5/24 B5/24",
]
TITLE = {
    "bass": "i0 " + bars(*(bass_bar(r, 2) for r, _ in TITLE_CHORDS)) + " loop",
    # la melodia nel filtro si apre nelle prime tre battute (da circa 360 Hz a 7 kHz sull'8580),
    # resta aperta, e nelle ultime due si richiude un po' prima di ricominciare
    "lead": "i13 f60 w+128 " + bars(*TITLE_LEAD[:3]) + " w0 " + bars(*TITLE_LEAD[3:6])
    + " w-96 " + bars(*TITLE_LEAD[6:]) + " loop",
    "arp": "i1 " + bars(*(f"a{m} {r}4/96" for r, m in TITLE_CHORDS)) + " loop",
}

# presentazione dell'avversario: squillo in minore
INTRO = {
    "bass": "i0 A2/12 A2/12 A3/48",
    "lead": "i2 E5/6 A5/6 C6/6 E6/54",
    "arp": "i1 a1 A4/72",
}

# livello superato: fanfara in maggiore
CLEAR = {
    "bass": "i0 C3/18 G3/18 C3/60",
    "lead": "i2 C5/6 E5/6 G5/6 C6/12 G5/6 C6/60",
    "arp": "i1 a2 C4/96",
}

# continue: due battute tese, in ripetizione
CONTINUE = {
    "bass": "i0 " + " ".join(["E2/12", "F2/12"] * 8) + " loop",
    "lead": "i7 B4/24 C5/24 B4/24 A#4/24 B4/24 C5/24 D5/24 C5/24 loop",
    "arp": "i3 E6/6 r/42 E6/6 r/42 E6/6 r/42 E6/6 r/42 loop",
}

# game over: discesa in minore
GAME_OVER = {
    "bass": "i0 A2/96 E2/48 A1/36",
    "lead": "i7 A4/18 G4/18 F4/18 E4/18 D4/18 C4/18 B3/12 A3/60",
    "arp": "r/180",
}

CHAMPION_CHORDS = [("C", 2), ("A", 1), ("F", 2), ("G", 2)]
CHAMPION = {
    "bass": "i0 " + bars(*(bass_bar(r, 2) for r, _ in CHAMPION_CHORDS)) + " loop",
    "lead": "i2 " + bars(
        "G5/24 E5/12 G5/12 C6/48",
        "A5/24 G5/12 E5/12 C5/48",
        "F5/24 A5/12 C6/12 F5/24 A5/24",
        "G5/36 F5/12 E5/24 D5/24",
    ) + " loop",
    "arp": "i1 " + bars(*(f"a{m} {r}4/96" for r, m in CHAMPION_CHORDS)) + " loop",
}

# (nome Verilog, canzone); il numero è la posizione + 1 (0 = silenzio)
SONGS = [
    ("TITLE", TITLE),
    ("INTRO", INTRO),
    ("CLEAR", CLEAR),
    ("CONTINUE", CONTINUE),
    ("GAME_OVER", GAME_OVER),
    ("CHAMPION", CHAMPION),
]

# ----------------------------------------------------------------------------- temi di CHALLENGE
# Uno per avversario, in partita contro la CPU, nell'ordine di PaddleKind. Solo le voci 1 e 2
# (basso e melodia): la voce 3 resta agli effetti, che altrimenti la interromperebbero di continuo.
# Nel C64 ogni tema viaggia nel file voce del suo avversario (src/voice.s), che lo copia a
# C64_THEME_BASE: una traccia per pagina, al massimo 255 byte (la copia conta all'indietro da 255);
# la terza, vuota, la scrive il file stesso (solo il $FF della fine).


def bass_line(chords: list[tuple[str, int]], dur: int) -> str:
    """Basso a ottave per ogni accordo (nota, ottava), otto note da `dur` frame per battuta."""
    return " ".join(" ".join(f"{r}{o + (i % 2)}/{dur}" for i in range(8)) for r, o in chords)


# ARCADE: allegro e semplice, in do maggiore (battuta da 96 frame)
ARCADE_CHORDS = [("C", 2), ("G", 1), ("A", 1), ("F", 1), ("C", 2), ("G", 1), ("F", 1), ("G", 1)]
THEME_ARCADE = {
    "bass": "i0 " + bass_line(ARCADE_CHORDS, 12) + " loop",
    "lead": "i1 " + bars(
        "E5/12 G5/12 C6/24 G5/12 E5/12 G5/24",
        "D5/12 G5/12 B5/24 A5/12 G5/12 D5/24",
        "C5/12 E5/12 A5/24 G5/12 E5/12 C5/24",
        "F5/24 A5/24 G5/12 F5/12 E5/12 D5/12",
        "E5/12 G5/12 C6/24 D6/12 C6/12 G5/24",
        "B5/12 D6/12 G6/24 F6/12 D6/12 B5/24",
        "A5/12 C6/12 F6/24 E6/12 C6/12 A5/24",
        "G5/36 A5/12 B5/24 D6/24",
    ) + " loop",
}

# TWIST: in re minore, con lo swing (crome lunga e corta) e le note che scivolano
THEME_TWIST = {
    "bass": "i0 " + bars(*(2 * [
        "D2/16 F2/8 A2/16 C3/8 D3/16 C3/8 A2/16 F2/8",
        "G1/16 B1/8 D2/16 F2/8 G2/16 F2/8 D2/16 B1/8",
        "C2/16 E2/8 G2/16 A#2/8 C3/16 A#2/8 G2/16 E2/8",
        "A1/16 C#2/8 E2/16 G2/8 A2/16 G2/8 F2/16 C#2/8",
    ])) + " loop",
    "lead": "i2 " + bars(
        "A4/16 D5/8 F5/16 A5/8 G5/16 F5/8 E5/24",
        "s+8 D5/24 s0 B4/16 D5/8 G5/48",
        "E5/16 G5/8 C6/16 A#5/8 A5/16 G5/8 E5/24",
        "C#5/16 E5/8 G5/16 A#5/8 s-12 A5/48 s0",
        "D6/16 C6/8 A5/16 F5/8 G5/16 A5/8 D5/24",
        "B4/16 D5/8 G5/16 B5/8 s+10 A5/24 s0 G5/24",
        "G5/16 E5/8 C5/16 E5/8 G5/16 A#5/8 C6/24",
        "s-10 E6/24 s0 C#6/16 A5/8 E5/16 C#5/8 A4/24",
    ) + " loop",
}

# HAMMER: drum and bass in mi minore a circa 180 BPM. A 50 frame al secondo un tempo dura 16,7
# frame: la battuta alterna tempi da 17 e da 16 (17 17 16 17 = 67 frame, 179 BPM), i sedicesimi
# sono da 4 frame con un 5 alla fine dei tempi da 17. Come nella drum and bass contano batteria e
# basso: la prima voce è tutta della batteria (cassa e rullante del "two-step" e charleston), la
# seconda di un basso profondo nelle ottave 1 e 2; niente melodia.
HAMMER_SIXTEENTHS = [4, 4, 4, 5, 4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 5]
HAMMER_EIGHTHS = [8, 9, 8, 9, 8, 8, 8, 9]


def hammer_drums(pattern: str) -> str:
    """Batteria di una battuta, sedicesimo per sedicesimo: "K" cassa, "S" rullante, "H" charleston,
    "-" niente (una nota, es. "E5", suonerebbe con la campanella); ogni colpo dura fino al
    successivo. La cassa scende di tono a note da un frame e chiude con la coda (12)."""
    hits = pattern.split()
    assert len(hits) == 16, hits
    out, ins = [], None

    def use(i: int) -> None:
        nonlocal ins
        if ins != i:
            out.append(f"i{i}")
            ins = i

    for i, h in enumerate(hits):
        if h == "-":
            continue
        n = next((j for j in range(i + 1, 16) if hits[j] != "-"), 16)
        d = sum(HAMMER_SIXTEENTHS[i:n])
        if h == "K":
            assert d >= 6, hits
            use(8)
            out.append("C4/1 F3/1 C3/1 G2/1 D2/1")
            use(12)
            out.append(f"A1/{d - 5}")
        elif h == "S":
            use(11)
            out.append(f"D6/{d}")
        elif h == "H":
            use(10)
            out.append(f"A7/{d}")
        else:
            use(3)
            out.append(f"{h}/{d}")
    assert hits[0] != "-", hits
    return " ".join(out)


def hammer_bass(lo: str, hi: str) -> str:
    """Basso di una battuta in ottavi: nota bassa lunga, ottava sopra, pausa, di nuovo giù."""
    e = HAMMER_EIGHTHS
    return f"{lo}/{sum(e[0:3])} {hi}/{e[3]} r/{e[4]} {lo}/{e[5] + e[6]} {hi}/{e[7]}"


HAMMER_ROOTS = {"E": ("E1", "E2"), "C": ("C2", "C3"), "D": ("D2", "D3"), "B": ("B1", "B2")}
HAMMER_DRUMS = bars(
    # batteria su due battute, che girano quattro volte sopra il basso di otto
    hammer_drums("K - H - S - H K - - K - S - H H"),
    hammer_drums("K - H - S - H - K - K - S - H S"),
) + " loop"


def hammer_bars(chords: str, cutoff: str = "") -> str:
    """Basso delle battute; con `cutoff` (es. "f768") il taglio riparte a ogni nota."""
    notes = " ".join(hammer_bass(*HAMMER_ROOTS[c]) for c in chords).split()
    return " ".join(f"{cutoff} {t}" if cutoff and not t.startswith("r/") else t for t in notes)


# Con il filtro (stessa batteria, stesso ritmo del basso): il basso nel passa-basso con la
# risonanza. Nelle prime quattro battute il taglio sale piano (da 60 a 328, circa da 360 Hz a
# 2 kHz sull'8580), nelle due dopo torna giù dov'era, un "reese" leggero; nelle ultime due il
# "wobble": a ogni nota il taglio riparte da 768 (4,7 kHz) e si chiude di 28 per frame
THEME_HAMMER = {
    "bass": HAMMER_DRUMS,
    "lead": "i9 f60 w+32 " + hammer_bars("ECEB") + " w-64 " + hammer_bars("EC") + " w-896 "
    + hammer_bars("DB", "f768") + " loop",
}

# TITAN: lento e pesante ma eroico, in do maggiore con il si bemolle (battuta da 120 frame)
TITAN_LEAD = [
    "G4/30 C5/30 E5/30 G5/30",
    "F5/60 D5/30 A#4/30",
    "A4/30 C5/30 F5/30 A5/30",
    "G5/90 D5/30",
    "E5/30 G5/30 C6/60",
    "A#5/30 A5/30 F5/60",
    "A5/30 G5/30 F5/30 E5/30",
    "D5/60 G5/30 B5/30",
]
THEME_TITAN = {
    "bass": "i0 " + bars(*(2 * [
        "C2/45 C2/15 G1/30 C2/30",
        "A#1/45 A#1/15 F1/30 A#1/30",
        "F1/45 F1/15 C2/30 F2/30",
        "G1/45 G1/15 D2/30 G2/30",
    ])) + " loop",
    # la melodia nel filtro cresce nella prima metà (taglio da 120 a 1080) e si scurisce un poco
    # nella seconda, come un respiro di otto battute
    "lead": "i13 f120 w+64 " + bars(*TITAN_LEAD[:4]) + " w-32 " + bars(*TITAN_LEAD[4:]) + " loop",
}

# BLASTER: veloce e aggressivo, in fa diesis minore, accordi in arpeggio e laser (battuta da 72).
# Nella voce del basso anche la batteria, a mezzo tempo come nella drum and bass: la cassa (note da
# un frame che scendono e poi scivolano nella nota del basso) sul primo ottavo, il rullante sul
# quinto al posto della nota
def blaster_bar(root: str, octave: int) -> str:
    notes = [f"{root}{octave + (i % 2)}" for i in range(8)]
    kick = f"i8 G3/1 D3/1 i0 {notes[0]}/7"
    return " ".join([kick, *(f"{n}/9" for n in notes[1:4]), "i11 D6/9 i0", *(f"{n}/9" for n in notes[5:])])


THEME_BLASTER = {
    "bass": bars(*(blaster_bar(r, o) for r, o in
                   [("F#", 2), ("D", 2), ("E", 2), ("F#", 2), ("F#", 2), ("D", 2), ("B", 1), ("C#", 2)])) + " loop",
    "lead": "i1 " + bars(
        "a1 F#4/18 a0 r/9 C#5/9 F#5/9 r/9 E5/9 C#5/9",
        "s-120 F#6/18 s0 D5/9 F#5/9 A5/18 F#5/9 D5/9",
        "a2 E4/18 a0 r/9 B4/9 E5/9 r/9 G#5/9 B5/9",
        "A5/18 G#5/9 F#5/9 s-120 C#6/27 s0 r/9",
        "a1 F#4/18 a0 r/9 C#5/9 F#5/9 r/9 A5/9 G#5/9",
        "F#5/18 A5/9 D6/9 s-120 F#6/18 s0 E6/9 D6/9",
        "a1 B4/18 a0 D5/9 F#5/9 B5/18 A5/9 F#5/9",
        "a2 C#5/36 a0 s-100 G#6/36 s0",
    ) + " loop",
}

# RUSH: di corsa, in la minore, basso al galoppo e scale veloci (battuta da 72, tempi da 18:
# galoppo 9 4 5). Nella voce del basso anche la batteria: cassa sui tempi 1 e 3 (scivola nella
# prima nota del galoppo), rullante su 2 e 4 al posto della prima nota. Il basso ripete 4 battute
# (la, fa, sol, mi): con la batteria otto non starebbero nei 255 byte di una traccia
def rush_bar(r: str) -> str:
    kick = f"i8 C4/1 G3/1 D3/1 i0 {r}/6 {r}/4 {r}/5"
    snare = f"i11 D6/9 i0 {r}/4 {r}/5"
    return " ".join([kick, snare, kick, snare])


THEME_RUSH = {
    "bass": bars(*(rush_bar(r) for r in ("A2", "F2", "G2", "E2"))) + " loop",
    "lead": "i2 " + bars(
        "A4/9 C5/9 E5/9 A5/9 G5/18 E5/18",
        "F5/9 A5/9 C6/18 A5/9 F5/9 C5/18",
        "G5/9 B5/9 D6/18 B5/9 G5/9 D5/18",
        "E5/9 A5/9 C6/9 E6/9 A6/36",
        "A5/4 G5/5 E5/4 C5/5 A4/18 C5/9 E5/9 A5/18",
        "C6/4 A5/5 F5/4 C5/5 F5/18 A5/9 C6/9 F6/18",
        "D6/4 B5/5 G5/4 D5/5 G5/18 B5/9 D6/9 G6/18",
        "G#5/18 B5/18 E6/18 G#6/18",
    ) + " loop",
}

# GUARDIAN, l'ultimo: lamento in re minore sul basso che scende di semitono
GUARDIAN_BASS = [("D2", "A2", "D3"), ("C#2", "A2", "E3"), ("C2", "A2", "F3"), ("B1", "G2", "D3"),
                 ("A#1", "F2", "D3"), ("A#1", "G2", "D3"), ("A1", "E2", "C#3"), ("A1", "E2", "A2")]
THEME_GUARDIAN = {
    "bass": "i0 " + bars(*(" ".join(f"{n}/12" for n in 2 * (lo, mid, hi, mid)) for lo, mid, hi in GUARDIAN_BASS))
    + " loop",
    "lead": "i2 " + bars(
        "A5/48 D6/24 F6/24",
        "E6/48 C#6/24 A5/24",
        "C6/36 A5/12 F5/24 A5/24",
        "B5/36 G5/12 D5/48",
        "D6/36 C6/12 A#5/24 A5/24",
        "G5/24 A#5/24 D6/24 G6/24",
        "a2 A5/48 a0 G5/12 F5/12 E5/24",
        "C#6/24 E6/24 A6/48",
    ) + " loop",
}

# nell'ordine di PaddleKind; la terza traccia è vuota (la voce 3 è degli effetti)
THEMES = [
    ("ARCADE", THEME_ARCADE),
    ("TITAN", THEME_TITAN),
    ("HAMMER", THEME_HAMMER),
    ("TWIST", THEME_TWIST),
    ("BLASTER", THEME_BLASTER),
    ("RUSH", THEME_RUSH),
    ("GUARDIAN", THEME_GUARDIAN),
]
for _, theme in THEMES:
    theme["arp"] = ""

# fine del gioco (dopo l'ultimo avversario di CHALLENGE): techno melodica in fa diesis minore a
# 125 BPM (battuta da 96 frame, tempi da 24, sedicesimi da 6), 32 battute. Un motivo ipnotico a
# sedicesimi gira su un ciclo di tre note contro i quattro tempi; il filtro (uno solo nel chip) lo
# apre piano, nella pausa sale, poi oscilla (wobble) sul basso profondo e nel drop resta spalancato,
# infine si richiude. Le aperture le comanda la traccia del basso, l'unica lunga. Nel finale non ci
# sono effetti, quindi le voci sono tre:
# - prima voce: basso profondo sul controtempo (strumento 14), 32 battute, con i comandi del
#   filtro (la terza voce non può comandarlo);
# - seconda voce: giro di 16 battute, 12 col motivo nel filtro (strumento 15), 2 a mezzo tempo e
#   2 di wobble sul basso profondo di HAMMER (il 9, nel filtro e di questa voce);
# - terza voce: batteria, giro di 16 battute: 12 di groove (cassa su ogni tempo, charleston sul
#   controtempo, clap sul 2 e sul 4, rullo ogni 4 battute) e la pausa con il rullo del drop. Nelle
#   32 battute la seconda pausa chiude il pezzo.
ENDING_CHORDS = [("F#", 1, ("F#4", "C#5", "A4")), ("D", 2, ("D4", "A4", "F#4")),
                 ("A", 1, ("A4", "E5", "C#5")), ("E", 2, ("E4", "B4", "G#4"))]


def ending_beat(clap: bool) -> str:
    """Un tempo: cassa (12 frame) e, sul controtempo, il clap o il charleston (12 frame)."""
    off = "i11 D6/12" if clap else "i10 A7/12"
    return f"i8 C4/1 G3/1 D3/1 i12 A1/9 {off}"


ENDING_DRUMS = " ".join(ending_beat(b in (1, 3)) for b in range(4))
ENDING_FILL = (" ".join(ending_beat(b == 1) for b in range(3)) +
               " i8 C4/1 G3/1 D3/1 i12 A1/9 i10 A7/6 A7/6")
# pausa prima del drop: la batteria tace, poi un rullo che accelera e un tempo di silenzio
ENDING_BREAK = ["r/96", "r/96", "r/96", "i11 " + " ".join(["D6/12"] * 4 + ["D6/6"] * 4) + " r/24"]


def ending_motif(notes: tuple[str, str, str]) -> str:
    """Sedici sedicesimi su un ciclo di tre note: l'accento scivola di tempo in tempo."""
    return " ".join(f"{notes[i % 3]}/6" for i in range(16))


def ending_half(notes: tuple[str, str, str]) -> str:
    """Il motivo a mezzo tempo, a crome: la pausa respira."""
    return " ".join(f"{notes[i % 3]}/12" for i in range(8))


def ending_wobble(n: int, half: int, depth: int) -> str:
    """Il filtro oscilla n volte, salendo e scendendo di depth in half frame per metà."""
    v = depth * 32 // half
    return " ".join(f"w+{v} r/{half} w-{v} r/{half}" for _ in range(n))


ENDING_BASS = [" ".join(f"r/12 {r}{o}/12" for _ in range(4)) for r, o, _ in ENDING_CHORDS]
ENDING_SILENCE = ["r/96"] * 4

ENDING = {
    "bass": "i14 " + bars(
        "f30 w+10", *ENDING_BASS * 3,                # 12 battute: il filtro si apre piano
        "w+84", *ENDING_SILENCE[:2],                 # pausa: il motivo da solo, il filtro sale
        "f250", ending_wobble(4, 12, 700),           # wobble a semiminime
        ending_wobble(5, 6, 700), "w0 r/36",         # poi a crome, e il silenzio prima del drop
        "f1500 w0", *ENDING_BASS * 2,                # il drop: 8 battute a filtro spalancato
        "w-48", *ENDING_BASS,                        # 4 battute: si richiude
        "w-72", *ENDING_SILENCE,                     # chiusura: il motivo da solo si spegne
    ) + " loop",
    "lead": "i15 " + bars(*[ending_motif(n) for _, _, n in ENDING_CHORDS] * 3,
                          *(ending_half(n) for _, _, n in ENDING_CHORDS[:2]),
                          "i9 F#1/96 F#1/72 r/24") + " loop",
    "arp": bars(*[ENDING_DRUMS, ENDING_DRUMS, ENDING_DRUMS, ENDING_FILL] * 3, *ENDING_BREAK) + " loop",
}

# Canzoni dopo i temi, come le mosse speciali: fuori dalla ROM del C64 (sid_music.bin), così i
# numeri dei temi non cambiano; si cercano per nome (SID_SONG_ENDING).
LATE_SONGS = [
    ("ENDING", ENDING),
]

C64_THEME_BASE = 0xF800        # nel C64: le tracce del tema, una per pagina (src/voice.s)
C64_SONG_THEME = len(SONGS) + 1

# ----------------------------------------------------------------------------- effetti
# Solo sulla voce 3: interrompono per un attimo la parte della canzone su quella voce.
EFFECTS = [
    ("WALL", "i4 A4/5"),
    ("HIT", "i4 A5/5"),
    ("BOOST", "i6 s+60 C5/10"),
    ("SCORE", "i3 s-12 A4/24"),
    ("COIN", "i4 B5/3 E6/14"),
]

# Mosse speciali di NEXT (non sul C64: in fondo alla ROM, dopo i temi, fuori da sid_music.bin).
# MOVE all'attivazione: una carica che sale (quadra in arpeggio d'ottava, scivolata verso l'alto);
# SPECIAL al colpo: schiocco di rumore e discesa veloce a dente di sega, l'impatto del tiro.
MOVE_EFFECTS = [
    ("MOVE", "i1 a3 s+40 G3/8 s+60 D4/10"),
    ("SPECIAL", "i5 C7/3 i6 C7/2 G6/2 E6/2 C6/2 G5/2 E5/2 C5/3 G4/3 C4/8"),
]


def write_if_changed(path: Path, data: bytes) -> None:
    """Scrive il file solo se cambia."""
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def check_filter_use(songs: list[tuple[str, dict[str, str]]], effects: list[tuple[str, str]]) -> dict[int, int]:
    """Il filtro solo sulle voci 1 e 2 delle canzoni, mai nella presentazione né negli effetti; ogni
    strumento nel filtro in una sola voce. Restituisce il bit della voce di ogni strumento nel
    filtro (per il suo $D417)."""
    voice_bit: dict[int, int] = {}
    for name, song in songs:
        assert not uses_filter(song["arp"]), (name, "voce 3 nel filtro")
        if name == "INTRO":
            assert not uses_filter(song["bass"]) and not uses_filter(song["lead"]), (name, "filtro")
        for v, part in enumerate(("bass", "lead")):
            for tok in song[part].split():
                if tok[0] == "i" and len(INSTRUMENTS[int(tok[1:])]) > 5:
                    assert voice_bit.setdefault(int(tok[1:]), 1 << v) == 1 << v, (name, tok, "due voci")
            check_cutoff(name, song[part])
    for name, track in effects:
        assert not uses_filter(track), (name, "effetto nel filtro")
    return voice_bit


def check_cutoff(name: str, track: str) -> None:
    """Il taglio a 16 bit della traccia resta tra 0 e $FFFF (il player non satura): due giri della
    traccia, nota per nota, con un passo di margine."""
    fc, sweep = None, 0
    for tok in 2 * track.split():
        if tok[0] == "f":
            fc = int(tok[1:]) << 5
        elif tok[0] == "w":
            sweep = int(tok[1:])
        elif "/" in tok and tok[0] != "s":
            if sweep:
                assert fc is not None, (name, "scivolata senza taglio")
                fc += sweep * (int(tok.split("/")[1]) + 1)
                assert 0 <= fc <= 0xFFFF, (name, "taglio fuori dai limiti", fc)


def build() -> dict:
    """ROM e indirizzi."""
    rom: list[int] = []
    # tabella delle frequenze: byte basso e alto di ogni nota
    freq_base = len(rom)
    rom += freq_table(SID_CLOCK)
    instr_base = len(rom)
    songs, themes = SONGS, THEMES
    voice_bit = check_filter_use(songs + [("THEME_" + n, s) for n, s in themes] + LATE_SONGS,
                                 EFFECTS + MOVE_EFFECTS)
    for i, ins in enumerate(INSTRUMENTS):
        ctrl, ad, sr, pw, release = ins[:5]
        # $D417 (risonanza e la voce) e $D418 dello strumento nel filtro; 0 senza filtro
        d417, d418 = (ins[5] | voice_bit[i], ins[6]) if len(ins) > 5 else (0, 0)
        rom += [ctrl, ad, sr, pw & 0xFF, pw >> 8, release, d417, d418]
    lines = [
        "// Generato da tools/gen_sid_music.py: non modificare a mano.",
        f"localparam SID_FREQ_BASE = {freq_base};",
        f"localparam SID_INSTR_BASE = {instr_base};",
        f"localparam SID_SONGS = {len(songs) + len(themes) + len(LATE_SONGS)};",
        f"localparam SID_EFFECTS = {len(EFFECTS) + len(MOVE_EFFECTS)};",
    ]
    starts: list[tuple[int, int, int]] = []
    theme_tracks: list[list[list[int]]] = []

    def add_song(name: str, song: dict[str, str]) -> list[list[int]]:
        addrs = []
        lengths = []
        tracks = []
        for part in ("bass", "lead", "arp"):
            data, frames = assemble(song[part])
            addrs.append(len(rom))
            if song[part]:
                lengths.append(frames)
            tracks.append(data)
            rom.extend(data)
        # le voci di una canzone in ripetizione restano a tempo: ognuna ricomincia per conto suo,
        # quindi la più lunga deve essere un multiplo delle altre (la batteria di HAMMER gira su
        # due battute, il basso su otto)
        if any("loop" in song[p] for p in song):
            assert all(max(lengths) % n == 0 for n in lengths), (name, lengths)
        starts.append((addrs[0], addrs[1], addrs[2]))
        lines.append(f"localparam SID_SONG_{name} = {len(starts)};   // {max(lengths) / FRAME_HZ:.1f} s")
        return tracks

    for name, song in songs:
        add_song(name, song)
    fx_starts = []
    for name, track in EFFECTS:
        data, _ = assemble(track)
        fx_starts.append(len(rom))
        rom += data
        lines.append(f"localparam SID_FX_{name} = {len(fx_starts)};")
    # i temi in fondo: la ROM del C64 (sid_music.bin) si ferma prima
    base_size = len(rom)
    lines.append(f"localparam SID_SONG_THEME0 = {len(songs) + 1};   // temi di CHALLENGE, nell'ordine di PaddleKind")
    for name, song in themes:
        tracks = add_song("THEME_" + name, song)
        assert all(len(t) <= 255 for t in tracks) and tracks[2] == [0xFF], (name, [len(t) for t in tracks])
        theme_tracks.append(tracks)
    for name, song in LATE_SONGS:
        add_song(name, song)
    for name, track in MOVE_EFFECTS:
        data, _ = assemble(track)
        fx_starts.append(len(rom))
        rom += data
        lines.append(f"localparam SID_FX_{name} = {len(fx_starts)};")
    assert len(fx_starts) <= 7, "effetti oltre i 3 bit di pong_sid"
    assert len(starts) <= 15, "canzoni oltre i 4 bit di pong_sid"
    assert len(rom) <= 4096, len(rom)
    lines.append(f"localparam SID_ROM_SIZE = {len(rom)};")
    lines.append(f"localparam SID_ROM_BASE_SIZE = {base_size};   // senza i temi (C64)")
    # indirizzi d'inizio delle tracce, come funzioni (canzone 1.., voce 0-2; effetto 1..)
    lines.append("function [11:0] sid_song_start(input [3:0] song, input [1:0] voice);")
    lines.append("    case ({song, voice})")
    for i, addrs in enumerate(starts, start=1):
        for v, a in enumerate(addrs):
            lines.append(f"        {{4'd{i}, 2'd{v}}}: sid_song_start = 12'd{a};")
    lines.append("        default: sid_song_start = 12'd0;")
    lines.append("    endcase")
    lines.append("endfunction")
    lines.append("function [11:0] sid_fx_start(input [2:0] fx);")
    lines.append("    case (fx)")
    for i, a in enumerate(fx_starts, start=1):
        lines.append(f"        3'd{i}: sid_fx_start = 12'd{a};")
    lines.append("        default: sid_fx_start = 12'd0;")
    lines.append("    endcase")
    lines.append("endfunction")
    return dict(rom=rom, lines=lines, starts=starts, fx_starts=fx_starts, base_size=base_size,
                theme_tracks=theme_tracks, songs=songs, themes=themes, freq_base=freq_base,
                instr_base=instr_base)


def main() -> None:
    c64 = build()
    write_if_changed(OUT / "sid_music.hex", ("\n".join(f"{x:02x}" for x in c64["rom"]) + "\n").encode())
    write_if_changed(OUT / "sid_music.vh", ("\n".join(c64["lines"]) + "\n").encode())
    # C64: la stessa ROM, con le frequenze per il clock della macchina (stesse note)
    rom, base_size, starts = c64["rom"], c64["base_size"], c64["starts"]
    pal = freq_table(PAL_CLOCK)
    write_if_changed(C64_OUT / "sid_music.bin", bytes(pal + rom[len(pal):base_size]))
    write_if_changed(C64_OUT / "sid_freq_ntsc.bin", bytes(freq_table(NTSC_CLOCK)))
    # tracce dei temi per i file voce: tema k, voce v
    for k, tracks in enumerate(c64["theme_tracks"]):
        for v, data in enumerate(tracks):
            write_if_changed(C64_OUT / f"theme{k}_{v}.bin", bytes(data))
    inc = [
        "; Generato da tools/gen_sid_music.py: non modificare a mano.",
        f"SID_FREQ_BASE = {c64['freq_base']}",
        f"SID_INSTR_BASE = {c64['instr_base']}",
        f"SID_SONGS = {len(SONGS)}",
        f"SID_EFFECTS = {len(EFFECTS)}",
        f"SID_ROM_SIZE = {base_size}",
    ]
    inc += [f"SID_SONG_{name} = {i}" for i, (name, _) in enumerate(SONGS, start=1)]
    inc += [f"SID_FX_{name} = {i}" for i, (name, _) in enumerate(EFFECTS, start=1)]
    inc.append("; tema dell'avversario di CHALLENGE (dal file voce): una traccia per pagina da THEME_BASE")
    inc.append(f"SID_SONG_THEME = {C64_SONG_THEME}")
    inc.append(f"THEME_BASE = ${C64_THEME_BASE:04X}")
    inc.append("; inizio delle tracce nella ROM: per canzone (da 1) le voci 0-2, poi gli effetti (da 1)")
    inc.append(".define SID_SONG_STARTS " + ", ".join(str(a) for addrs in starts[: len(SONGS)] for a in addrs))
    inc.append(".define SID_FX_STARTS " + ", ".join(str(a) for a in c64["fx_starts"][: len(EFFECTS)]))
    # finale di CHALLENGE (c64/src/ending.s): le tre tracce di ENDING in fila in ending.bin, che il
    # finale copia dalla cartuccia; nel player è la canzone dopo il tema
    ending = c64["starts"][len(SONGS) + len(THEMES)]
    assert LATE_SONGS[0][0] == "ENDING"
    bounds = sorted(a for addrs in c64["starts"] for a in addrs) + [c64["fx_starts"][len(EFFECTS)], len(rom)]
    tracks = [rom[a:min(b for b in bounds if b > a)] for a in ending]
    assert all(t[-1] in (0xFE, 0xFF) for t in tracks), "tracce di ENDING non contigue"
    write_if_changed(C64_OUT / "ending.bin", bytes(sum(tracks, [])))
    inc.append("; finale di CHALLENGE (ending.bin, le tre tracce di fila): offset delle tracce")
    inc.append(f"SID_SONG_ENDING = {C64_SONG_THEME + 1}")
    inc.append(f"SID_ENDING_LEAD = {len(tracks[0])}")
    inc.append(f"SID_ENDING_ARP = {len(tracks[0]) + len(tracks[1])}")
    inc.append(f"SID_ENDING_SIZE = {sum(len(t) for t in tracks)}")
    write_if_changed(C64_OUT / "sid_music.inc", ("\n".join(inc) + "\n").encode())
    sizes = ", ".join(f"{n.lower()} {sum(len(t) for t in tr)}" for (n, _), tr in zip(THEMES, c64["theme_tracks"]))
    print(f"{len(c64['rom'])} byte ({base_size} nel C64), {len(SONGS)} canzoni, {len(THEMES)} temi ({sizes}), "
          f"{len(EFFECTS) + len(MOVE_EFFECTS)} effetti")


if __name__ == "__main__":
    main()
