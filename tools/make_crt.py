"""Crea la cartuccia EasyFlash della versione C64 (.crt, tipo hardware 32), senza dipendenze.

Uso:
    python tools/make_crt.py [--pads FILE] [--name NOME] OUT.crt BOOT.bin PROGRAMMA.prg PICK.bin FINALE.bin OMEGA.bin VOCE0.prg [... VOCE7.prg]
    (--pads: le pose delle racchette del campo girato, c64/gen/rotated/paddles.bin, nel banco
    PAD_BANK; senza, le astronavi a righe dello schermo di c64/gen/padpairs.bin dal banco PAD2_BANK;
    --name: il nome nell'intestazione del .crt, al posto di "PADD WS": lo mostrano VICE e il
    C64 Ultimate, e distingue le quattro cartucce)

Banchi e indirizzi in c64/src/ef.inc:
- BOOT.bin: gli 8 KB della ROMH del banco 0 (c64/src/crt.s), a $E000 nel modo Ultimax
  dell'accensione: copia il programma in RAM e lo avvia;
- PROGRAMMA.prg: il programma, da $0801 a $CFFF, poi a $D000-$D0FF l'immagine delle routine della
  RAM della cartuccia (c64/src/ef.s), da $D100 quelle dell'avvio (c64/src/unpack.s), da $D500 il
  codice delle mosse speciali di NEXT (c64/src/supers.s), da $D900 quello della classifica
  (c64/src/challenge.s), da $DF00 una pagina vuota e da $E000 il codice del GAME OVER
  (c64/src/play.s); da PRG_BANK (16 KB per banco, ROML e poi ROMH) da $0800, con uno zero
  davanti, così il caricatore copia pagine intere;
- PICK.bin: il set di caratteri della scelta dei bonus, la pagina $FF00 e il titolo dell'attract
  (c64/gen/pick_bank.bin), nella ROML del banco PICK_BANK;
- VOCEn.prg: i file voce di CHALLENGE (c64/src/voice.s), senza l'indirizzo di caricamento, nella
  ROML dei banchi da VOICE_BANK0. Solo il file del primo livello arriva oltre VOICE_RES (player e
  READY, che restano per tutta la scala): quella parte va anche negli altri banchi, allo stesso
  posto, perché la copia prende sempre VOICE_PAGES pagine. L'ottavo file (VOCE7) è quello di OMEGA:
  va all'inizio del banco OM_BANK;
- OMEGA.bin: il resto del banco di OMEGA (l'uscita PROGRAMMA.prg.omega di ld65: sezioni della sua
  canzone, temi per il jukebox, jukebox, entrata nella presentazione), dopo il suo file voce;
- c64/gen/howto.bin (letto da qui, non è un argomento): la HOW TO PLAY delle mosse speciali, nella
  ROML dei banchi HOWTO_BANK (la bitmap) e HOWTO_BANK + 1 (i colori e quelli dell'easter egg);
- PROGRAMMA.prg.kpick (accanto al programma, non è un argomento) e c64/gen/kpick.bin: la scelta
  della racchetta con i ritratti, il codice (c64/src/kpick.s, 4 pagine) e poi i dati
  (tools/gen_c64_portraits.py), dal banco KP_BANK, ROML e ROMH; il resto del codice
  (PROGRAMMA.prg.kpick2 e .kpick3) va nelle righe 1-3 della bitmap dello sfondo, vuote;
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
BOOT_END = 0x10000 # la classifica, una pagina vuota e il GAME OVER (nel banco 4, anche nella
                   # ROMH), che restano nella flash
SRC = Path(__file__).resolve().parent.parent / "c64" / "src"


def const(name: str, inc: str, base: int = 0) -> int:
    """Costante di c64/src/INC (`NOME = $XXXX` o decimale, o `NOME = $80 + n` con base $80)."""
    path = SRC / inc
    m = re.search(rf"^{name}\s*=\s*(\$[0-9A-Fa-f]+|\d+)(?:\s*\+\s*(\d+))?", path.read_text(encoding="utf-8"), re.M)
    if not m:
        sys.exit(f"{path}: manca {name}")
    v = m.group(1)
    value = int(v[1:], 16) if v.startswith("$") else int(v)
    return value + int(m.group(2) or 0)


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
OM_BANK = const("OM_BANK", "ef.inc")
KP_BANK = const("KP_BANK", "ef.inc")
PAD_BANK = const("PAD_BANK", "ef.inc")
PAD2_BANK = const("PAD2_BANK", "ef.inc")
PAIRS = SRC.parent / "gen" / "padpairs.bin"
PADS = None           # (--pads: le pose del campo girato)
KPICK = SRC.parent / "gen" / "kpick.bin"
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
    if len(samples) <= 256 or WIN_SAMPLES + len(samples) > WIN_DESC:
        # (il player guarda la fine solo dalla seconda pagina: src/voice.s, nmi_lo)
        sys.exit(f"{voice}: {len(samples)} byte, non più di una pagina o oltre WIN_DESC")
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
    global PADS
    # --pads FILE: le immagini delle racchette di un'altra versione (il campo girato:
    # c64/gen/rotated/paddles.bin, 16 KB nella ROML e nella ROMH del banco PAD_BANK)
    # --name NOME: il nome nell'intestazione del .crt (al più 31 caratteri ASCII)
    name = b"PADD WS"
    while len(sys.argv) > 2 and sys.argv[1] in ("--pads", "--name"):
        if sys.argv[1] == "--pads":
            PADS = Path(sys.argv[2])
        else:
            name = sys.argv[2].encode("ascii")
        del sys.argv[1:3]
    if not 0 < len(name) < 32:
        sys.exit(f"--name: {len(name)} caratteri, ne servono da 1 a 31")
    if len(sys.argv) < 7:
        sys.exit(__doc__)
    out, boot, program = Path(sys.argv[1]), Path(sys.argv[2]).read_bytes(), Path(sys.argv[3])
    pick = Path(sys.argv[4]).read_bytes()
    ending = Path(sys.argv[5]).read_bytes()
    omega = Path(sys.argv[6]).read_bytes()
    voices = [Path(v) for v in sys.argv[7:]]
    if len(boot) != HALF:
        sys.exit(f"{sys.argv[2]}: {len(boot)} byte invece di {HALF}")
    image = b"\x00" + prg(program, PRG_START + 1)
    if not PRG_END - PRG_START <= len(image) <= BOOT_END - PRG_START:
        sys.exit(f"{program}: non finisce tra ${PRG_END - 1:04X} e ${BOOT_END - 1:04X}")
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
    if len(voices) != 8:
        sys.exit(f"{len(voices)} file voce invece di 8 (i sette tipi e OMEGA)")
    for kind, (path, data) in enumerate(zip(voices, files)):
        if len(data) <= res:
            data = data + bytes(res - len(data)) + tail
        if len(data) > VOICE_PAGES * 256:
            sys.exit(f"{path}: più lungo di {VOICE_PAGES} pagine")
        if kind < 7:
            chips.append(chip(VOICE_BANK0 + kind, 0x8000, data))
            continue
        # OMEGA: il file voce, poi il resto del banco (ROML e ROMH)
        bank = data.ljust(VOICE_PAGES * 256, b"\0") + omega
        if len(bank) > 2 * HALF:
            sys.exit(f"banco di OMEGA: {len(bank)} byte, oltre 16 KB")
        chips.append(chip(OM_BANK, 0x8000, bank[:HALF]))
        if len(bank) > HALF:
            chips.append(chip(OM_BANK, 0xA000, bank[HALF:]))
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
    # scelta della racchetta: il codice, poi i dati, 8 KB per metà di banco
    kcode = Path(str(program) + ".kpick").read_bytes()
    if len(kcode) != 0x400:
        sys.exit(f"{program}.kpick: {len(kcode)} byte invece di 1024")
    # i cursori (PROGRAMMA.prg.kpick2) nella riga 1 della bitmap dello sfondo e nella riga 2 fino
    # alla colonna 16, vuote: da $E140
    kcode2 = Path(str(program) + ".kpick2").read_bytes()
    bg = bytearray(KPICK.read_bytes())
    if len(kcode2) != 0x1C8 or any(bg[0x140:0x308]):
        sys.exit(f"{program}.kpick2: {len(kcode2)} byte invece di 456, o righe 1-2 dello sfondo non vuote")
    bg[0x140:0x308] = kcode2
    # lo split del raster e il tempo (PROGRAMMA.prg.kpick3) nella riga 2 dalla colonna 23 e nella
    # riga 3 fino alla 16, vuote: da $E338
    kcode3 = Path(str(program) + ".kpick3").read_bytes()
    if len(kcode3) != 0x110 or any(bg[0x338:0x448]):
        sys.exit(f"{program}.kpick3: {len(kcode3)} byte invece di 272, o righe 2-3 dello sfondo non vuote")
    bg[0x338:0x448] = kcode3
    # lo schermo VS (PROGRAMMA.prg.kvs, .kvs2, .kvs3, .kvs4): il codice all'inizio del suo banco,
    # nelle 4 pagine lasciate vuote da tools/gen_c64_portraits.py, poi quello della riga 24 della
    # bitmap a KV_ROW24P, quello dei caratteri 64-159 a KV_CHARSP e quello delle celle della riga 14
    # e della riga 15 nelle tre pagine da KV_CODE4P (copiate a $F100: dentro, da KV_CODE4 e da
    # KV_CODE5)
    vs_bank = const("KV_BANK_REL", "../gen/kpick.inc")
    vs_row24 = const("KV_ROW24P", "../gen/kpick.inc", 0x80)
    vs_chars = const("KV_CHARSP", "../gen/kpick.inc", 0x80)
    vs_code4p = const("KV_CODE4P", "../gen/kpick.inc", 0x80)
    vs_code4 = const("KV_CODE4", "../gen/kpick.inc") - 0xF100
    vs_code5 = const("KV_CODE5", "../gen/kpick.inc") - 0xF100
    at = vs_bank * 2 * HALF - 0x400
    for ext, page, size in ((".kvs", 0x80, 0x400), (".kvs2", vs_row24, 0x100), (".kvs3", vs_chars, 0x300),
                            (".kvs4", vs_code4p, 0x90), (".kvs5", vs_code4p, 0x90)):
        code = Path(str(program) + ext).read_bytes()
        here = at + (page - 0x80) * 256 + {".kvs4": vs_code4, ".kvs5": vs_code5}.get(ext, 0)
        if len(code) > size or any(bg[here:here + size]):
            sys.exit(f"{program}{ext}: oltre {size} byte, o il suo posto nei dati non vuoto")
        bg[here:here + len(code)] = code
    # la sfilata del finale (PROGRAMMA.prg.parade): all'inizio del suo banco, come il VS; il codice
    # della riga 0 della bitmap (.parade2) nella pagina PR_CODE2P
    pr_bank = const("PR_BANK_REL", "../gen/kpick.inc")
    pcode = Path(str(program) + ".parade").read_bytes()
    here = pr_bank * 2 * HALF - 0x400
    if len(pcode) != 0x400 or any(bg[here:here + 0x400]):
        sys.exit(f"{program}.parade: {len(pcode)} byte invece di 1024, o il suo posto nei dati non vuoto")
    bg[here:here + 0x400] = pcode
    pcode2 = Path(str(program) + ".parade2").read_bytes()
    here += 0x400 + (const("PR_CODE2P", "../gen/kpick.inc", 0x80) - 0x80 - 4) * 256
    if len(pcode2) != 0x100 or any(bg[here:here + 0x100]):
        sys.exit(f"{program}.parade2: {len(pcode2)} byte invece di 256, o il suo posto nei dati non vuoto")
    bg[here:here + 0x100] = pcode2
    kpick = kcode + bytes(bg)
    for i in range(0, len(kpick), HALF):
        chips.append(chip(KP_BANK + i // (2 * HALF), 0x8000 + i // HALF % 2 * HALF, kpick[i:i + HALF]))
    assert VOICE_BANK0 + 7 <= PICK_BANK < WIN_BANK < END_BANK < HI_BANK < HI_BANK + 8 <= HOWTO_BANK < HOWTO_BANK + 2 <= OM_BANK < KP_BANK
    assert KP_BANK + (len(kpick) - 1) // (2 * HALF) < PAD_BANK < 64
    if PADS is not None:
        # campo girato: le sue pose, 16 KB nel banco PAD_BANK
        pads = PADS.read_bytes()
        if len(pads) != 16 * 1024:
            sys.exit(f"{PADS}: {len(pads)} byte invece di 16384")
        chips.append(chip(PAD_BANK, 0x8000, pads[:HALF]))
        chips.append(chip(PAD_BANK, 0xA000, pads[HALF:]))
    else:
        # campo orizzontale: le astronavi a righe dello schermo (racchette in due metà), dal banco
        # PAD2_BANK: 8 pagine per coppia di tipi, poi le pose ferme, ROML e poi ROMH
        pairs = PAIRS.read_bytes()
        assert PAD_BANK < PAD2_BANK and PAD2_BANK + (len(pairs) - 1) // (2 * HALF) < 64
        for i in range(0, len(pairs), HALF):
            chips.append(chip(PAD2_BANK + i // (2 * HALF), 0x8000 + i // HALF % 2 * HALF, pairs[i:i + HALF]))
    out.write_bytes(header + b"".join(chips))
    print(f"{out}: {len(chips)} pezzi da 8 KB")


if __name__ == "__main__":
    main()
