"""Genera gli schemi di collegamento di encoder e pulsanti del cabinato Raspberry Pi:

- deploy/raspberry/wiring.svg: encoder meccanici KY-040 (con pulsante, 20 scatti per giro);
- deploy/raspberry/wiring_optical.svg: encoder ottici 360 o 600 P/R (NPN open collector, 5 V),
  con lo scatto in avanti su un pulsante a parte.

Uso:
    python tools/gen_wiring.py

I pin sono i default della sezione `encoder` di padd_config.json (rust/game/src/config.rs): se
cambiano, vanno cambiati anche qui. Un colore per segnale, uguale per i due giocatori.
"""

from pathlib import Path

DIR = Path(__file__).resolve().parent.parent / "deploy" / "raspberry"

# connettore a 40 pin: (numero, nome)
ODD = {1: "3V3", 3: "GPIO2", 5: "GPIO3", 7: "GPIO4", 9: "GND", 11: "GPIO17", 13: "GPIO27", 15: "GPIO22",
       17: "3V3", 19: "GPIO10", 21: "GPIO9", 23: "GPIO11", 25: "GND", 27: "GPIO0", 29: "GPIO5", 31: "GPIO6",
       33: "GPIO13", 35: "GPIO19", 37: "GPIO26", 39: "GND"}
EVEN = {2: "5V", 4: "5V", 6: "GND", 8: "GPIO14", 10: "GPIO15", 12: "GPIO18", 14: "GND", 16: "GPIO23",
        18: "GPIO24", 20: "GND", 22: "GPIO25", 24: "GPIO8", 26: "GPIO7", 28: "GPIO1", 30: "GND", 32: "GPIO12",
        34: "GND", 36: "GPIO16", 38: "GPIO20", 40: "GPIO21"}

W = 1000
CX, TOP, ROW = 500, 90, 30
# un colore per segnale, uguale per i due giocatori (come i cavetti di un cablaggio)
CLK, DT, SW, SEL, USE = "#2e7d32", "#1565c0", "#7b1fa2", "#ef6c00", "#00838f"
GND, PWR, BOX = "#424242", "#c62828", "#37474f"


def pin_xy(n):
    row = (n - 1) // 2
    return (CX - 14 if n % 2 else CX + 14), TOP + row * ROW


def draw(optical):
    H = 900 if optical else 860
    used = {}  # pin -> colore
    out = []
    add = out.append
    add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
        'font-family="Helvetica, Arial, sans-serif" font-size="13">')
    add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')
    title = "encoder ottici 360 / 600 P/R" if optical else "cabinato Raspberry Pi 4 / 5"
    add(f'<text x="{W / 2}" y="34" text-anchor="middle" font-size="20" font-weight="bold">PADD WS - {title}</text>')
    add(f'<text x="{W / 2}" y="56" text-anchor="middle" fill="#555">connettore GPIO a 40 pin visto dall\'alto, pin 1 in alto a sinistra (numeri GPIO = BCM)</text>')

    def wire(points, color, pin):
        used[pin] = color
        d = " ".join(f"{x},{y}" for x, y in points)
        add(f'<polyline points="{d}" fill="none" stroke="{color}" stroke-width="2.5" stroke-linejoin="round"/>')

    def box(x, y, w, h, title, sub, color):
        add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="#fafafa" stroke="{color}" stroke-width="2"/>')
        add(f'<text x="{x + w / 2}" y="{y + 22}" text-anchor="middle" font-weight="bold" fill="{color}">{title}</text>')
        add(f'<text x="{x + w / 2}" y="{y + 40}" text-anchor="middle" fill="#555" font-size="12">{sub}</text>')

    def terminal(x, y, label, anchor):
        add(f'<circle cx="{x}" cy="{y}" r="4" fill="#fff" stroke="#000"/>')
        dx = -8 if anchor == "end" else 8
        add(f'<text x="{x + dx}" y="{y + 4}" text-anchor="{anchor}">{label}</text>')

    # corpo del connettore, sotto i fili
    add(f'<rect x="{CX - 32}" y="{TOP - 16}" width="64" height="{19 * ROW + 32}" rx="4" fill="#263238"/>')

    if not optical:
        # --- encoder e pulsanti del giocatore 1 (a sinistra, verso i pin dispari)
        ex, ey = 70, 380
        box(ex, ey, 170, 190, "ENCODER P1", "modulo KY-040", BOX)
        p1 = [("CLK", 29, CLK), ("DT", 31, DT), ("SW", 33, SW), ("+", 17, PWR), ("GND", 39, GND)]
        for i, (label, pin, color) in enumerate(p1):
            ty = ey + 65 + i * 26
            terminal(ex + 170, ty, label, "end")
            px, py = pin_xy(pin)
            lane = 270 + i * 20
            wire([(ex + 170, ty), (lane, ty), (lane, py), (px - 6, py)], color, pin)

        bx, by = 70, 610
        box(bx, by, 170, 120, "PULSANTI P1", "NEXT: verso massa", BOX)
        for i, (label, pin, color) in enumerate([("SELEZIONA", 35, SEL), ("USA", 37, USE)]):
            ty = by + 62 + i * 30
            terminal(bx + 170, ty, label, "end")
            px, py = pin_xy(pin)
            lane = 366 + i * 14
            wire([(bx + 170, ty), (lane, ty), (lane, py), (px - 6, py)], color, pin)
        # l'altro capo dei due pulsanti va a massa (pin 39)
        gx, gy = pin_xy(39)
        wire([(bx + 120, by + 120), (bx + 120, by + 140), (394, by + 140), (394, gy), (gx - 6, gy)], GND, 39)
        add(f'<text x="{bx + 128}" y="{by + 136}" fill="{GND}" font-size="11">altro capo -> GND</text>')

        # --- encoder e pulsanti del giocatore 2 (a destra, verso i pin pari)
        ex2, ey2 = 760, 380
        box(ex2, ey2, 170, 190, "ENCODER P2", "modulo KY-040", BOX)
        p2 = [("CLK", 36, CLK), ("DT", 38, DT), ("SW", 40, SW), ("GND", 34, GND)]
        for i, (label, pin, color) in enumerate(p2):
            ty = ey2 + 65 + i * 26
            terminal(ex2, ty, label, "start")
            px, py = pin_xy(pin)
            lane = 730 - i * 20
            wire([(ex2, ty), (lane, ty), (lane, py), (px + 6, py)], color, pin)
        # + del secondo encoder al 3V3 del pin 1 (lato dispari): il filo gira sopra il connettore ed entra dall'alto
        ty = ey2 + 65 + 4 * 26
        terminal(ex2, ty, "+", "start")
        px, py = pin_xy(1)
        wire([(ex2, ty), (750, ty), (750, TOP - 26), (px, TOP - 26), (px, py - 6)], PWR, 1)

        bx2, by2 = 760, 610
        box(bx2, by2, 170, 120, "PULSANTI P2", "NEXT: verso massa", BOX)
        for i, (label, pin, color) in enumerate([("SELEZIONA", 32, SEL), ("USA", 22, USE)]):
            ty = by2 + 62 + i * 30
            terminal(bx2, ty, label, "start")
            px, py = pin_xy(pin)
            lane = 650 - i * 14
            wire([(bx2, ty), (lane, ty), (lane, py), (px + 6, py)], color, pin)
        gx, gy = pin_xy(30)
        wire([(bx2 + 50, by2 + 120), (bx2 + 50, by2 + 140), (622, by2 + 140), (622, gy), (gx + 6, gy)], GND, 30)
        add(f'<text x="{bx2 + 58}" y="{by2 + 136}" fill="{GND}" font-size="11">altro capo -> GND</text>')
    else:
        # --- encoder ottici: 4 fili (colori tipici dei cavi LPD3806), alimentati dal 5 V. Ordine dei
        # morsetti e corsie scelti perché i fili dello stesso encoder non si incrocino: VCC in alto
        # sulla corsia più interna (sale sopra il connettore), poi i fili che scendono, con le
        # corsie verso l'esterno man mano che il pin è più in basso
        sub = "ottico 360 / 600 P/R"
        ex, ey = 50, 360
        box(ex, ey, 190, 170, "ENCODER P1", sub, BOX)
        ty = ey + 65
        terminal(ex + 190, ty, "VCC (rosso)", "end")
        px, py = pin_xy(2)
        wire([(ex + 190, ty), (330, ty), (330, TOP - 26), (px, TOP - 26), (px, py - 6)], PWR, 2)
        # il GND dell'encoder sul pin 25: il 39 resta ai pulsanti, così le due masse non si sovrappongono
        p1 = [("GND (nero)", 25, GND, 310), ("A (verde)", 29, CLK, 296), ("B (bianco)", 31, DT, 280)]
        for i, (label, pin, color, lane) in enumerate(p1):
            ty = ey + 65 + (i + 1) * 26
            terminal(ex + 190, ty, label, "end")
            px, py = pin_xy(pin)
            wire([(ex + 190, ty), (lane, ty), (lane, py), (px - 6, py)], color, pin)

        # mezza riga più in basso dei pin: nessun filo dei pulsanti corre sulla riga di un altro pin
        bx, by = 50, 584
        box(bx, by, 190, 150, "PULSANTI P1", "verso massa", BOX)
        buttons1 = [("SCATTO", 33, SW), ("SELEZIONA", 35, SEL), ("USA", 37, USE)]
        for i, (label, pin, color) in enumerate(buttons1):
            ty = by + 62 + i * 28
            terminal(bx + 190, ty, label, "end")
            px, py = pin_xy(pin)
            lane = 352 + i * 14
            wire([(bx + 190, ty), (lane, ty), (lane, py), (px - 6, py)], color, pin)
        gx, gy = pin_xy(39)
        wire([(bx + 140, by + 150), (bx + 140, by + 170), (394, by + 170), (394, gy), (gx - 6, gy)], GND, 39)
        add(f'<text x="{bx + 148}" y="{by + 166}" fill="{GND}" font-size="11">altro capo -> GND</text>')

        ex2, ey2 = 760, 360
        box(ex2, ey2, 190, 170, "ENCODER P2", sub, BOX)
        p2 = [("VCC (rosso)", 4, PWR, 670), ("GND (nero)", 34, GND, 690), ("A (verde)", 36, CLK, 710),
              ("B (bianco)", 38, DT, 730)]
        for i, (label, pin, color, lane) in enumerate(p2):
            ty = ey2 + 65 + i * 26
            terminal(ex2, ty, label, "start")
            px, py = pin_xy(pin)
            wire([(ex2, ty), (lane, ty), (lane, py), (px + 6, py)], color, pin)

        bx2, by2 = 760, 584
        box(bx2, by2, 190, 150, "PULSANTI P2", "verso massa", BOX)
        # salgono tutti: dall'alto in basso i pin più alti, sulle corsie più esterne
        buttons2 = [("USA", 22, USE), ("SELEZIONA", 32, SEL), ("SCATTO", 40, SW)]
        for i, (label, pin, color) in enumerate(buttons2):
            ty = by2 + 62 + i * 28
            terminal(bx2, ty, label, "start")
            px, py = pin_xy(pin)
            lane = 650 - i * 14
            wire([(bx2, ty), (lane, ty), (lane, py), (px + 6, py)], color, pin)
        gx, gy = pin_xy(30)
        wire([(bx2 + 50, by2 + 150), (bx2 + 50, by2 + 170), (608, by2 + 170), (608, gy), (gx + 6, gy)], GND, 30)
        add(f'<text x="{bx2 + 58}" y="{by2 + 166}" fill="{GND}" font-size="11">altro capo -> GND</text>')

    # --- connettore: i pin e i loro nomi sopra i fili
    for n, name in list(ODD.items()) + list(EVEN.items()):
        x, y = pin_xy(n)
        color = used.get(n)
        fill = color or ("#c62828" if name in ("3V3", "5V") else "#9e9e9e" if name == "GND" else "#cfd8dc")
        add(f'<circle cx="{x}" cy="{y}" r="7" fill="{fill}" stroke="#000" stroke-width="{2 if color else 0.5}"/>')
        add(f'<text x="{x}" y="{y + 3}" text-anchor="middle" font-size="8" fill="#fff">{n}</text>')
        style = f' font-weight="bold" fill="{color}"' if color else ' fill="#9e9e9e"'
        ty = y - 5 if color else y + 4
        if n % 2:
            add(f'<text x="{CX - 42}" y="{ty}" text-anchor="end"{style} font-size="12">{name}</text>')
        else:
            add(f'<text x="{CX + 42}" y="{ty}" text-anchor="start"{style} font-size="12">{name}</text>')

    # legenda dei colori
    if optical:
        legend = [("A", CLK), ("B", DT), ("SCATTO", SW), ("SELEZIONA", SEL), ("USA", USE), ("GND", GND), ("VCC 5V", PWR)]
    else:
        legend = [("CLK", CLK), ("DT", DT), ("SW (click)", SW), ("SELEZIONA", SEL), ("USA", USE), ("GND", GND), ("+ 3V3", PWR)]
    # larghezza di ogni voce: trattino, spazio e nome (circa 9 pixel per lettera in grassetto)
    widths = [32 + 9 * len(name) + 24 for name, _ in legend]
    x = W / 2 - sum(widths) / 2
    ly = H - 82 - (16 if optical else 0)
    for (name, color), width in zip(legend, widths):
        add(f'<line x1="{x}" y1="{ly}" x2="{x + 26}" y2="{ly}" stroke="{color}" stroke-width="4"/>')
        add(f'<text x="{x + 32}" y="{ly + 4}" font-weight="bold" fill="{color}">{name}</text>')
        x += width

    # note
    if optical:
        notes = [
            "Solo encoder con uscite NPN open collector (es. LPD3806-360BM-G5-24C, -600BM-G5-24C), alimentati a 5 V:",
            "A e B portano il GPIO a massa e il pull-up interno lo riporta a 3,3 V. Mai uscite push-pull a 5 V su un GPIO.",
            "Cavi lunghi o giri molto veloci: pull-up esterni da 2,2 kOhm da A e B verso 3V3 (pin 1 o 17); la calza a GND.",
            "padd_config.json, sezione encoder: pulses_per_revolution 360 o 600, debounce_us 0, turns_per_travel a piacere.",
        ]
    else:
        notes = [
            "Encoder: modulo KY-040 o encoder nudo (CLK e DT ai due capi, il comune a GND); pull-up interni attivati dal gioco.",
            "Il + del KY-040 va al 3V3, mai al 5V: i GPIO del Raspberry reggono solo 3,3 V.",
            "Pulsanti: un capo sul GPIO, l'altro a GND. Pin configurabili nella sezione encoder di padd_config.json.",
        ]
    for i, text in enumerate(notes):
        add(f'<text x="{W / 2}" y="{H - 44 - (16 if optical else 0) + i * 16}" text-anchor="middle" fill="#333" font-size="12">{text}</text>')
    add("</svg>")
    return "\n".join(out) + "\n", len(used)


for name, optical in (("wiring.svg", False), ("wiring_optical.svg", True)):
    svg, pins = draw(optical)
    (DIR / name).write_text(svg, encoding="utf-8", newline="\n")
    print(f"{name}: {pins} pin usati")
