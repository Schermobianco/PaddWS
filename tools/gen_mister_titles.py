"""Genera le ROM dei titoli disegnati per il core MiSTer, da assets/titles (tools/gen_title_assets.py).

Uscite in mister/rtl/gen/ (vanno nel repository, così la sintesi non richiede Python):
  title_challenge.hex  ROM di challenge_render: HERE COMES A NEW CHALLENGER! e i nomi dei sette
                       avversari delle presentazioni
  title_perfect.hex    ROM di pong_render: PERFECT della fine partita
  pong_titles.vh       misure, indirizzi di partenza e lettere (per le entrate animate)

Ogni voce delle ROM è un pixel, 4 bit: l'indice della palette dei PNG, cioè il ruolo del colore
(0 trasparente, 1 nero, 2 bianco, 3 giallo, 4 giallo scuro, 5 grigio, 6 grigio scuro, 7 rosso, 8 rosso
scuro); i colori veri li sceglie il renderer. Le righe di un titolo stanno a passo 2^SH (64, 128 o
256 voci) dal suo indirizzo di partenza, così l'indirizzo del pixel (u, v) è base + {v, u}: nessuna
moltiplicazione. Le colonne in più restano a zero. Una M10K tiene 2048 voci da 4 bit.

Uso:  .venv\\Scripts\\python tools\\gen_mister_titles.py   (richiede Pillow)
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "titles"
OUT = ROOT / "mister" / "rtl" / "gen"

# nomi nell'ordine di PaddleKind (0 ARCADE ... 6 GUARDIAN)
KINDS = ["arcade", "titan", "hammer", "twist", "blaster", "rush", "guardian"]

# BLASTER è in corsivo (tools/gen_title_assets.py, blaster()): la lettera j, senza l'inclinazione,
# parte dalla colonna BL_X0 + BL_STEP * j; la riga v è spostata a destra di int((h - 1 - v) * BL_K).
# Si controlla sul PNG che ogni pixel delle lettere cada nella sua cella.
BL_X0, BL_STEP, BL_K, BL_LETTERS = 22, 9, 0.34, 7


def load(name: str) -> list[list[int]]:
    im = Image.open(SRC / f"{name}.png")
    assert im.mode == "P", name
    w, h = im.size
    return [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]


def stride_sh(w: int) -> int:
    """Esponente del passo delle righe: la potenza di 2 che contiene la larghezza (almeno 64)."""
    return max(6, (w - 1).bit_length())


def guardian_starts(px: list[list[int]]) -> list[int]:
    """GUARDIAN: prima colonna di ogni lettera (gruppi di colonne accese separati da colonne vuote)."""
    w = len(px[0])
    lit = [any(row[x] for row in px) for x in range(w)]
    starts = [x for x in range(w) if lit[x] and (x == 0 or not lit[x - 1])]
    assert len(starts) == 8, starts
    return starts


def blaster_slant(h: int) -> list[int]:
    return [int((h - 1 - v) * BL_K) for v in range(h)]


def check_blaster(px: list[list[int]]) -> None:
    """Ogni pixel a destra delle scie sta nella cella di una delle sette lettere (8 colonne su 9)."""
    h, w = len(px), len(px[0])
    slant = blaster_slant(h)
    used = set()
    for v in range(h):
        for u in range(w):
            if not px[v][u]:
                continue
            d = u - slant[v] - BL_X0
            if d < 0:
                assert u < BL_X0 - 1, (u, v)        # scie di velocità, a sinistra della B
                continue
            assert d % BL_STEP < BL_STEP - 1 and d // BL_STEP < BL_LETTERS, (u, v)
            used.add(d // BL_STEP)
    assert used == set(range(BL_LETTERS)), used


def main() -> None:
    info = json.loads((SRC / "titles.json").read_text(encoding="utf-8"))
    sizes = {name: tuple(t["size"]) for name, t in info["titles"].items()}
    imgs = {name: load(name) for name in sizes}
    for name, (w, h) in sizes.items():
        assert (len(imgs[name][0]), len(imgs[name])) == (w, h), name
        assert max(max(row) for row in imgs[name]) < 16, name

    # ROM di challenge_render: prima il nuovo sfidante, poi i nomi; ogni titolo a un indirizzo
    # multiplo del suo passo
    ch_order = ["challenger"] + [f"name_{k}" for k in KINDS]
    ch_rom: list[int] = []
    base, sh = {}, {}
    for name in ch_order:
        w, h = sizes[name]
        sh[name] = stride_sh(w)
        step = 1 << sh[name]
        while len(ch_rom) % step:
            ch_rom.append(0)
        base[name] = len(ch_rom)
        for row in imgs[name]:
            ch_rom += row + [0] * (step - w)
    w, h = sizes["perfect"]
    sh["perfect"] = stride_sh(w)
    pf_rom = [c for row in imgs["perfect"] for c in row + [0] * ((1 << sh["perfect"]) - w)]
    ch_bits = (len(ch_rom) - 1).bit_length()
    pf_bits = (len(pf_rom) - 1).bit_length()

    g_starts = guardian_starts(imgs["name_guardian"])
    check_blaster(imgs["name_blaster"])
    bl_h = sizes["name_blaster"][1]
    slant = blaster_slant(bl_h)

    def kind_fn(ret: str, fname: str, values: list[int]) -> list[str]:
        out = [f"function {ret}{fname}(input [2:0] kind);", "    case (kind)"]
        out += [f"        3'd{i}: {fname} = {v};" for i, v in enumerate(values)]
        out += [f"        default: {fname} = 0;", "    endcase", "endfunction"]
        return out

    names = [f"name_{k}" for k in KINDS]
    p = [
        "// Generato da tools/gen_mister_titles.py: non modificare a mano.",
        "// Titoli disegnati (assets/titles): un pixel per voce, 4 bit = ruolo del colore (0 trasparente,",
        "// 1 nero, 2 bianco, 3 giallo, 4 giallo scuro, 5 grigio, 6 grigio scuro, 7 rosso, 8 rosso scuro).",
        "// Il pixel (u, v) di un titolo sta a base + (v << SH) + u.",
        "localparam [3:0] TL_CLEAR = 4'd0, TL_BLACK = 4'd1, TL_WHITE = 4'd2, TL_YELLOW = 4'd3, TL_DARK_YELLOW = 4'd4,",
        "                 TL_GRAY = 4'd5, TL_DARK_GRAY = 4'd6, TL_RED = 4'd7, TL_DARK_RED = 4'd8;",
        "// title_challenge.hex (challenge_render)",
        f"localparam integer TL_CH_DEPTH = {len(ch_rom)}, TL_CH_ABITS = {ch_bits};",
        f"localparam integer TL_NEWCH_BASE = {base['challenger']}, TL_NEWCH_W = {sizes['challenger'][0]}, "
        f"TL_NEWCH_H = {sizes['challenger'][1]}, TL_NEWCH_SH = {sh['challenger']};",
        "// nomi degli avversari (PaddleKind): indirizzo di partenza, larghezza, altezza, passo 128 (1) o 64 (0)",
    ]
    p += kind_fn(f"[{ch_bits - 1}:0] ", "tl_name_base", [base[n] for n in names])
    p += kind_fn("[6:0] ", "tl_name_w", [sizes[n][0] for n in names])
    p += kind_fn("[4:0] ", "tl_name_h", [sizes[n][1] for n in names])
    p += kind_fn("", "tl_name_sh7", [1 if sh[n] == 7 else 0 for n in names])
    assert all(sh[n] in (6, 7) for n in names) and all(sizes[n][1] <= 31 for n in names)
    p += [
        "// lettere per le entrate animate: GUARDIAN (prima colonna delle lettere 1-7) e BLASTER, in corsivo",
        "// (prima colonna delle lettere 1-6 senza l'inclinazione; la riga v è spostata di tl_blaster_slant(v));",
        "// centro della lettera 0 a metà altezza e passo, per i colpi che le accendono",
        "function [6:0] tl_letter_x(input [2:0] kind, input [2:0] j);",
        "    case ({kind, j})",
    ]
    p += [f"        {{3'd6, 3'd{j}}}: tl_letter_x = {g_starts[j]};" for j in range(1, 8)]
    p += [f"        {{3'd4, 3'd{j}}}: tl_letter_x = {BL_X0 + BL_STEP * j};" for j in range(1, BL_LETTERS)]
    p += ["        default: tl_letter_x = 7'd127;", "    endcase", "endfunction",
          "function [2:0] tl_blaster_slant(input [4:0] v);", "    case (v)"]
    p += [f"        5'd{v}: tl_blaster_slant = {s};" for v, s in enumerate(slant) if s]
    p += ["        default: tl_blaster_slant = 0;", "    endcase", "endfunction",
          f"localparam integer TL_BLASTER_CX0 = {BL_X0 + (BL_STEP - 2) // 2 + slant[bl_h // 2]}, "
          f"TL_BLASTER_STEP = {BL_STEP};",
          "// title_perfect.hex (pong_render)",
          f"localparam integer TL_PF_DEPTH = {len(pf_rom)}, TL_PF_ABITS = {pf_bits};",
          f"localparam integer TL_PF_W = {sizes['perfect'][0]}, TL_PF_H = {sizes['perfect'][1]}, "
          f"TL_PF_SH = {sh['perfect']};"]
    assert math.ceil(len(ch_rom) / 2048) <= 16

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "pong_titles.vh").write_text("\n".join(p) + "\n", encoding="utf-8", newline="\n")
    for fname, rom in (("title_challenge.hex", ch_rom), ("title_perfect.hex", pf_rom)):
        (OUT / fname).write_text("".join(f"{c:x}\n" for c in rom), encoding="ascii", newline="\n")
    print(f"title_challenge.hex: {len(ch_rom)} voci ({math.ceil(len(ch_rom) / 2048)} M10K), "
          f"title_perfect.hex: {len(pf_rom)} voci ({math.ceil(len(pf_rom) / 2048)} M10K)")


if __name__ == "__main__":
    main()
