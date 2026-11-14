"""Crea la cartuccia EasyFlash della versione C64 (.crt, tipo hardware 32), senza dipendenze.

Uso:
    python tools/make_crt.py OUT.crt BOOT.bin PROGRAMMA.prg PICK.bin FINALE.bin VOCE0.prg [... VOCE6.prg]

Banchi e indirizzi in c64/src/ef.inc:
- BOOT.bin: gli 8 KB della ROMH del banco 0 (c64/src/crt.s), a $E000 nel modo Ultimax
  dell'accensione: copia il programma in RAM e lo avvia;
- PROGRAMMA.prg: il programma, da $0801 a $CFFF, poi a $D000-$D0FF l'immagine delle routine della
  RAM della cartuccia (c64/src/ef.s), da $D100 quelle dell'avvio (c64/src/unpack.s), da $D500 il
  codice delle mosse speciali di NEXT (c64/src/supers.s), da $D900 quello della classifica
  (c64/src/challenge.s), da $DF00 i caratteri di PERFECT e da $E000 il codice del GAME OVER
  (c64/src/play.s); da PRG_BANK (16 KB per banco, ROML e poi ROMH) da $0800, con uno zero
  davanti, così il caricatore copia pagine intere;
- PICK.bin: il set di caratteri della scelta dei bonus, la pagina $FF00 e il titolo dell'attract
  (c64/gen/pick_bank.bin), nella ROML del banco PICK_BANK;
- VOCEn.prg: i file voce di CHALLENGE (c64/src/voice.s), senza l'indirizzo di caricamento, nella
  ROML dei banchi da VOICE_BANK0. Solo il file del primo livello arriva oltre VOICE_RES (player e
  READY, che restano per tutta la scala): quella parte va anche negli altri banchi, allo stesso
  posto, perché la copia prende sempre VOICE_PAGES pagine.
- c64/gen/howto.bin (letto da qui, non è un argomento): la HOW TO PLAY delle mosse speciali, nella
  ROML dei banchi HOWTO_BANK (la bitmap) e HOWTO_BANK + 1 (i colori e quelli dell'easter egg);
- FINALE.bin: il finale di CHALLENGE (c64/src/ending.s, l'uscita PROGRAMMA.prg.end di ld65), nella
  ROML dei banchi da END_BANK, 8 KB per banco;
- banco della vittoria WIN_BANK (ROML): "YOU WIN!" (c64/gen/you_win.bin) con il player delle voci,
  16 pagine da copiare a WIN_RUN ($EB00-$FAFF): da VOICE_RES il player e READY come nel file voce
  del primo livello, i campioni a WIN_SAMPLES con il loro descrittore a WIN_DESC (inizio, fine),
  $FF a $FA00 (la fine della terza traccia del tema) e da VOICE_GO la prima pagina di quello che il
  file del primo livello copia lì (gli NMI del player). In CHALLENGE il player e i suoi NMI sono già
  in memoria e restano uguali. Nelle 16 pagine dopo ($9000) la stessa immagine con "PERFECT!"
  (c64/gen/perfect.bin) al posto di YOU WIN, per il GAME OVER vinto con l'avversario a 0 punti.

La ROML del banco HI_BANK resta cancellata: è il settore della classifica, che il programma scrive.
Nella ROMH dello stesso banco ci sono solo i vettori, che puntano a un RTI: mentre il programma
scrive la flash (modo Ultimax, banco HI_BANK) un NMI (RESTORE) torna subito.

Formato CRT: intestazione "C64 CARTRIDGE" di 64 byte (versione 1.0, tipo 32, EXROM inattiva e GAME
attiva come all'accensione dell'EasyFlash), poi un pacchetto CHIP per ogni metà di banco usata
(flash, banco, indirizzo $8000 per la ROML e $A000 per la ROMH, 8 KB). Le parti non scritte della
flash restano a $FF.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

HW_EASYFLASH = 32
CHIP_FLASH = 2
HALF = 0x2000
PRG_START = 0x0800
PRG_END = 0xD100   # poi le routine dell'avvio (fino a $D7FF), le mosse speciali (fino a $DBFF),
BOOT_END = 0x10000 # la classifica, i caratteri di PERFECT e il GAME OVER (nel banco 4, anche nella
                   # ROMH), che restano nella flash
SRC = Path(__file__).resolve().parent.parent / "c64" / "src"


def const(name: str, inc: str) -> int:
    """Costante di c64/src/INC (`NOME = $XXXX` o decimale)."""
    path = SRC / inc
    m = re.search(rf"^{name}\s*=\s*(\$[0-9A-Fa-f]+|\d+)", path.read_text(encoding="utf-8"), re.M)
    if not m:
        sys.exit(f"{path}: manca {name}")
    v = m.group(1)
    return int(v[1:], 16) if v.startswith("$") else int(v)


PRG_BANK = const("PRG_BANK", "ef.inc")
VOICE_BANK0 = const("VOICE_BANK0", "ef.inc")
PICK_BANK = const("PICK_BANK", "ef.inc")
HI_BANK = const("HI_BANK", "ef.inc")
VOICE_BASE = const("VOICE_BASE", "voice.inc")
VOICE_PAGES = const("VOICE_PAGES", "voice.inc")
VOICE_RES = const("VOICE_RES", "voice.inc")
VOICE_GO = const("VOICE_GO", "voice.inc")
VOICE_GO_SRC = const("VOICE_GO_SRC", "voice.inc")
WIN_BANK = const("WIN_BANK", "ef.inc")
END_BANK = const("END_BANK", "ef.inc")
HOWTO_BANK = const("HOWTO_BANK", "ef.inc")
HOWTO = SRC.parent / "gen" / "howto.bin"
WIN_RUN = const("WIN_RUN", "voice.inc")
WIN_SAMPLES = const("WIN_SAMPLES", "voice.inc")
WIN_DESC = const("WIN_DESC", "voice.inc")
YOU_WIN = SRC.parent / "gen" / "you_win.bin"
PERFECT = SRC.parent / "gen" / "perfect.bin"
WIN_PAGES = const("WIN_PAGES", "voice.inc")


def chip(bank: int, addr: int, data: bytes) -> bytes:
    assert len(data) <= HALF, (bank, hex(addr), len(data))
    data = data + b"\xff" * (HALF - len(data))
    return b"CHIP" + struct.pack(">IHHHH", 0x10 + HALF, CHIP_FLASH, bank, addr, HALF) + data


def prg(path: Path, start: int) -> bytes:
    data = path.read_bytes()
    addr = data[0] | data[1] << 8
    if addr != start:
        sys.exit(f"{path}: si carica a ${addr:04X} invece di ${start:04X}")
    return data[2:]


def win_image(first: bytes, voice: Path) -> bytes:
    """Un'immagine del banco della vittoria con la voce `voice`: le WIN_PAGES pagine da WIN_RUN a
    VOICE_GO + $FF (vedi sopra)."""
    image = bytearray(WIN_PAGES * 256)
    res, go = VOICE_RES - WIN_RUN, VOICE_GO - WIN_RUN
    tail = first[VOICE_RES - VOICE_BASE:]
    if len(tail) > WIN_SAMPLES - VOICE_RES:
        sys.exit("player e READY oltre WIN_SAMPLES")
    image[res:res + len(tail)] = tail
    samples = voice.read_bytes()
    at = WIN_SAMPLES - WIN_RUN
    if not samples or WIN_SAMPLES + len(samples) > WIN_DESC:
        sys.exit(f"{voice}: {len(samples)} byte, oltre WIN_DESC")
    image[at:at + len(samples)] = samples
    end = WIN_SAMPLES + len(samples)
    image[WIN_DESC - WIN_RUN:WIN_DESC - WIN_RUN + 4] = bytes([WIN_SAMPLES & 0xFF, WIN_SAMPLES >> 8, end & 0xFF, end >> 8])
    image[go - 1] = 0xFF
    src = VOICE_GO_SRC - VOICE_BASE
    page = first[src:src + 255]
    if len(page) != 255 or go + 255 != len(image):
        sys.exit("pagina degli NMI del player fuori posto")
    image[go:] = page
    return bytes(image)


def win_bank(first: bytes) -> bytes:
    """Banco della vittoria: l'immagine di YOU WIN, poi quella di PERFECT (la ROML intera)."""
    bank = win_image(first, YOU_WIN) + win_image(first, PERFECT)
    if len(bank) != HALF:
        sys.exit(f"banco della vittoria: {len(bank)} byte invece di {HALF}")
    return bank


def main() -> None:
    if len(sys.argv) < 7:
        sys.exit(__doc__)
    out, boot, program = Path(sys.argv[1]), Path(sys.argv[2]).read_bytes(), Path(sys.argv[3])
    pick = Path(sys.argv[4]).read_bytes()
    ending = Path(sys.argv[5]).read_bytes()
    voices = [Path(v) for v in sys.argv[6:]]
    if len(boot) != HALF:
        sys.exit(f"{sys.argv[2]}: {len(boot)} byte invece di {HALF}")
    image = b"\x00" + prg(program, PRG_START + 1)
    if not PRG_END - PRG_START <= len(image) <= BOOT_END - PRG_START:
        sys.exit(f"{program}: non finisce tra ${PRG_END - 1:04X} e ${BOOT_END - 1:04X}")
    name = b"PADD WS"
    header = (b"C64 CARTRIDGE   " + struct.pack(">IHHBB", 0x40, 0x0100, HW_EASYFLASH, 1, 0)
              + bytes(6) + name + bytes(32 - len(name)))
    chips = [chip(0, 0xA000, boot)]
    for i in range(0, len(image), HALF):
        bank, half = PRG_BANK + i // (2 * HALF), i // HALF % 2
        chips.append(chip(bank, 0x8000 + half * HALF, image[i:i + HALF]))
    files = [prg(path, VOICE_BASE) for path in voices]
    res = VOICE_RES - VOICE_BASE
    first = [d for d in files if len(d) > res]
    if len(first) != 1:
        sys.exit(f"{len(first)} file voce oltre VOICE_RES invece di uno (quello del primo livello)")
    tail = first[0][res:]
    chips.append(chip(WIN_BANK, 0x8000, win_bank(first[0])))
    for i in range(0, len(ending), HALF):
        chips.append(chip(END_BANK + i // HALF, 0x8000, ending[i:i + HALF]))
    if not ending or END_BANK + (len(ending) - 1) // HALF >= HI_BANK:
        sys.exit(f"{sys.argv[5]}: finale vuoto o oltre il banco della classifica")
    for kind, (path, data) in enumerate(zip(voices, files)):
        if len(data) <= res:
            data = data + bytes(res - len(data)) + tail
        if len(data) > VOICE_PAGES * 256:
            sys.exit(f"{path}: più lungo di {VOICE_PAGES} pagine")
        chips.append(chip(VOICE_BANK0 + kind, 0x8000, data))
    if len(pick) != 0x1100:
        sys.exit(f"{sys.argv[4]}: {len(pick)} byte invece di 4352")
    chips.append(chip(PICK_BANK, 0x8000, pick))
    howto = HOWTO.read_bytes()
    if len(howto) != HALF + 0x800:
        sys.exit(f"{HOWTO}: {len(howto)} byte invece di {HALF + 0x800}")
    chips.append(chip(HOWTO_BANK, 0x8000, howto[:HALF]))
    chips.append(chip(HOWTO_BANK + 1, 0x8000, howto[HALF:]))
    # ROMH del banco della classifica: RTI a $FFF0 e i vettori (NMI, reset, IRQ) lì
    vectors = bytearray(b"\xff" * HALF)
    vectors[0x1FF0] = 0x40
    vectors[0x1FFA:0x2000] = bytes([0xF0, 0xFF] * 3)
    chips.append(chip(HI_BANK, 0xA000, bytes(vectors)))
    assert VOICE_BANK0 + len(voices) <= PICK_BANK < WIN_BANK < END_BANK < HI_BANK < HI_BANK + 8 <= HOWTO_BANK
    out.write_bytes(header + b"".join(chips))
    print(f"{out}: {len(chips)} pezzi da 8 KB")


if __name__ == "__main__":
    main()
