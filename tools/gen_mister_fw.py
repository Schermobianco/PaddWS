"""Compila il firmware RISC-V del core MiSTer (rust/mister-fw) e scrive l'immagine della BRAM.

Uscite in mister/rtl/gen/ (vanno nel repository, così la sintesi non richiede Rust):
  pong_fw_b0.hex .. pong_fw_b3.hex  un file per byte della parola (b0 = bit 0-7), un byte per
                                    riga, dall'indirizzo 0: le quattro BRAM da 8 bit di
                                    rtl/pong_logic_rv.v, caricate con $readmemh
  pong_fw.vh                        dimensioni (RAM, immagine, .bss) e impronta dei sorgenti

L'impronta è uno SHA-256 dei sorgenti che entrano nel firmware (rust/core, rust/mister-fw tranne il
banco di prova, il profilo del workspace senza la versione), con i fine riga normalizzati: non
dipende dal sistema né dalla versione del gioco, mentre i byte compilati potrebbero cambiare con il
percorso o con la versione (simboli). `--check` controlla solo l'impronta: dice se i file generati
sono rimasti indietro rispetto ai sorgenti. Che l'immagine sia giusta lo dice paddws-fw-sim, che la
esegue contro le tracce (mister/sim/run.ps1 e run.sh).

Uso:
    python tools/gen_mister_fw.py           compila (cargo, target riscv32im-unknown-none-elf) e scrive
    python tools/gen_mister_fw.py --check   esce con 1 se i file generati non corrispondono ai sorgenti

Richiede la toolchain Rust con il target riscv32im-unknown-none-elf (portable: tools/rust-env.ps1).
"""

from __future__ import annotations

import hashlib
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUST = ROOT / "rust"
FW = RUST / "mister-fw"
OUT = ROOT / "mister" / "rtl" / "gen"
TARGET = "riscv32im-unknown-none-elf"
ELF = RUST / "target" / TARGET / "fw" / "paddws-mister-fw"

RAM_BYTES = 64 * 1024
# spazio minimo per lo stack sopra .bss: il picco misurato da paddws-fw-sim (6,8 KB) con un margine
STACK_MIN = 8 * 1024


def source_files() -> list[Path]:
    files = [RUST / "Cargo.toml"]
    files += sorted((RUST / "core").rglob("*.rs")) + [RUST / "core" / "Cargo.toml"]
    files += [FW / "Cargo.toml", FW / "build.rs", FW / "link.x"]
    files += sorted(p for p in (FW / "src").rglob("*.rs") if "bin" not in p.relative_to(FW / "src").parts)
    return files


def fingerprint() -> str:
    h = hashlib.sha256()
    for p in source_files():
        text = p.read_bytes().replace(b"\r\n", b"\n")
        if p == RUST / "Cargo.toml":
            # la versione del workspace cambia a ogni release ma non il firmware
            text = re.sub(rb'(?m)^version = "[^"]*"\n', b"", text)
        h.update(p.relative_to(ROOT).as_posix().encode() + b"\0" + text + b"\0")
    return h.hexdigest()[:16]


def check_ram_size() -> None:
    """La RAM deve avere la stessa dimensione nello script del linker e nella mappa dei registri."""
    link = (FW / "link.x").read_text(encoding="utf-8")
    m = re.search(r"LENGTH\s*=\s*(\d+)K", link)
    if not m or int(m.group(1)) * 1024 != RAM_BYTES:
        sys.exit(f"link.x: la RAM deve essere di {RAM_BYTES // 1024}K")
    mp = (FW / "src" / "map.rs").read_text(encoding="utf-8")
    m = re.search(r"RAM_SIZE: u32 = (\d+) \* 1024", mp)
    if not m or int(m.group(1)) * 1024 != RAM_BYTES:
        sys.exit(f"map.rs: RAM_SIZE deve essere {RAM_BYTES // 1024} * 1024")


def build() -> None:
    subprocess.run(
        ["cargo", "build", "-q", "--profile", "fw", "-p", "paddws-mister-fw", "--bin", "paddws-mister-fw",
         "--target", TARGET],
        cwd=RUST, check=True,
    )


def read_elf(path: Path) -> tuple[bytes, int]:
    """Immagine dei segmenti caricabili (da 0) e fine di .bss (simbolo __bss_end)."""
    b = path.read_bytes()
    if b[:4] != b"\x7fELF" or b[4] != 1 or struct.unpack_from("<H", b, 0x12)[0] != 0xF3:
        sys.exit(f"{path}: non è un ELF32 RISC-V")
    phoff, shoff = struct.unpack_from("<II", b, 0x1C)
    phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from("<HHHHH", b, 0x2A)
    image = bytearray()
    for i in range(phnum):
        p_type, off, vaddr, _, filesz, memsz, _, _ = struct.unpack_from("<8I", b, phoff + i * phentsize)
        if p_type != 1 or filesz == 0:
            continue
        end = vaddr + filesz
        if len(image) < end:
            image.extend(bytes(end - len(image)))
        image[vaddr:end] = b[off:off + filesz]
    # tabella dei simboli: __bss_end
    sections = [struct.unpack_from("<10I", b, shoff + i * shentsize) for i in range(shnum)]
    bss_end = None
    for sh in sections:
        if sh[1] != 2:  # SHT_SYMTAB
            continue
        strtab = sections[sh[6]]
        for k in range(sh[5] // 16):
            name_off, value = struct.unpack_from("<II", b, sh[4] + k * 16)
            start = strtab[4] + name_off
            name = b[start:b.index(b"\0", start)]
            if name == b"__bss_end":
                bss_end = value
    if bss_end is None:
        sys.exit(f"{path}: manca il simbolo __bss_end")
    while len(image) % 4:
        image.append(0)
    return bytes(image), bss_end


def outputs(image: bytes, bss_end: int, fp: str) -> dict[str, str]:
    files = {}
    words = len(image) // 4
    for lane in range(4):
        files[f"pong_fw_b{lane}.hex"] = "".join(f"{image[4 * w + lane]:02x}\n" for w in range(words))
    files["pong_fw.vh"] = (
        "// Generato da tools/gen_mister_fw.py: non modificare a mano.\n"
        f"// Firmware RISC-V (rust/mister-fw), impronta dei sorgenti {fp}\n"
        f"localparam integer FW_RAM_BYTES = {RAM_BYTES};   // BRAM: codice, costanti, .bss e stack\n"
        f"localparam integer FW_IMAGE_WORDS = {words};   // parole nei file pong_fw_b*.hex\n"
        f"localparam integer FW_BSS_END = {bss_end};   // fine di .bss: sopra c'è lo stack\n"
    )
    return files


def main() -> None:
    check = "--check" in sys.argv[1:]
    check_ram_size()
    fp = fingerprint()
    if check:
        vh = OUT / "pong_fw.vh"
        have = vh.read_text(encoding="utf-8") if vh.exists() else ""
        if f"impronta dei sorgenti {fp}" not in have:
            print("mister/rtl/gen/pong_fw*.hex non aggiornati: python tools/gen_mister_fw.py")
            sys.exit(1)
        print(f"firmware aggiornato (impronta {fp})")
        return
    build()
    image, bss_end = read_elf(ELF)
    if RAM_BYTES - bss_end < STACK_MIN:
        sys.exit(f"firmware troppo grande: {bss_end} byte, restano {RAM_BYTES - bss_end} byte per lo stack "
                 f"(ne servono {STACK_MIN})")
    for name, text in outputs(image, bss_end, fp).items():
        (OUT / name).write_text(text, encoding="utf-8", newline="\n")
    print(f"firmware: {len(image)} byte di codice e costanti, .bss fino a {bss_end}, "
          f"stack {RAM_BYTES - bss_end} byte; impronta {fp}")


if __name__ == "__main__":
    main()
