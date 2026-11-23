//! Schermate di scelta di NEXT: prima la racchetta (con i ritratti dei personaggi, come
//! `PaddlePick` di paddle_ui.rs), poi i bonus (come il vecchio next_render.v: ogni colonna sta nella
//! sua metà dello schermo, gli oggetti di un lato sono ritagliati sulla sua metà).

use crate::assets::game::{BONUS_NAMES, CAP, KIND_TAGS};
use crate::assets::{IMG_CAP_FRAME, IMG_ICON, IMG_NAME, IMG_PICK_NET, portraits};
use crate::cast::{
    Cast, HALF_X, OMEGA, PADDLE_X, PORTRAIT_W, PORTRAIT_X, TOP, centered, frame, line, name_art, name_x, net,
    paddle, portrait,
};
use crate::dl::{CLASS_A, Dl, code, text_w};
use crate::pal::{ACCENT, BLACK, CELL_FRAME, GRAY, OMEGA_Q, TL, WHITE};
use crate::regs::{Regs, field};

const W: i32 = 320;

/// Stato della scelta dai registri.
struct Pick {
    cur: [u32; 2],
    mask: [u32; 2],
    ready: bool,
    cpu: bool,
    lock: u32,
    paddle: bool,
    kcur: [u32; 2],
    chosen: u32,
}

impl Pick {
    fn new(r: &Regs) -> Self {
        let w = r.w[7];
        let k = r.w[28];
        Self {
            cur: [field(w, 0, 3), field(w, 3, 3)],
            mask: [field(w, 6, 6), field(w, 12, 6)],
            ready: field(w, 22, 1) != 0,
            cpu: field(w, 23, 1) != 0,
            lock: field(w, 24, 2),
            paddle: field(w, 26, 1) != 0,
            kcur: [field(k, 0, 3), field(k, 3, 3)],
            chosen: field(k, 6, 2),
        }
    }
}

/// Testo con il ritaglio della metà dello schermo.
#[inline(never)]
fn text_in(d: &mut Dl, x: i32, y: i32, s: &[u8], c: u8, half: (i32, i32)) {
    let base = d.tiles(s, c);
    let o = d.text_obj(x, y, base, s.len(), 0).clip(half.0, half.1, 0, 240);
    d.push(&o);
}

/// Titolo e mezzeria della scelta dei bonus.
#[inline(never)]
fn common(d: &mut Dl, title: &[u8]) {
    d.text((W - text_w(title)) / 2, 8, title, ACCENT, 0);
    d.img(W / 2 - 1, 56, &IMG_PICK_NET, WHITE);
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    let p = Pick::new(r);
    d.class = CLASS_A;
    // lo sfondo è il cielo visto da un'astronave, con le stelle cadenti nel colore del personaggio di
    // destra (l'avversario o P2)
    crate::space::draw(d, r.frame, p.kcur[1] as usize);
    if p.paddle {
        paddles(r, d, &p);
        return;
    }
    {
        common(d, b"PICK 3 BONUSES");
        for side in 0..2usize {
            let half = if side == 0 { (0, W / 2) } else { (W / 2, W) };
            let cxl = if side == 0 { W / 4 } else { 3 * W / 4 };
            let mask = p.mask[side];
            let count = mask.count_ones();
            let head: &[u8] = if side == 0 {
                b"P1"
            } else if p.cpu {
                b"CPU"
            } else {
                b"P2"
            };
            text_in(d, cxl - 50, 58, head, WHITE, half);
            let cc = if count == 3 { WHITE } else { GRAY };
            let cnt = [(count as u8, cc), (code(b'/'), cc), (3, cc)];
            let base = d.codes(&cnt);
            let o = d.text_obj(cxl + 26, 58, base, 3, 0).clip(half.0, half.1, 0, 240);
            d.push(&o);
            for br in 0..6u32 {
                let by0 = 76 + 24 * br as i32;
                let rb = if br == 5 { 6 } else { br };
                let taken = mask >> br & 1 != 0;
                let cur = p.cur[side] == br;
                if cur && p.lock >> side & 1 == 0 && count != 3 && !p.ready {
                    text_in(d, cxl - 66, by0 + 5, b">", ACCENT, half);
                }
                let c = if taken || cur { WHITE } else { GRAY };
                let (sx, sy) = (cxl - 52, by0 + 2);
                let io = (CAP - 9) / 2;
                if taken {
                    // in negativo: riquadro pieno, l'icona resta nera
                    d.rect(sx, sy, CAP, CAP, c);
                    d.img(sx + io, sy + io, &IMG_ICON[rb as usize], BLACK);
                } else {
                    d.img(sx, sy, &IMG_CAP_FRAME, c);
                    d.img(sx + io, sy + io, &IMG_ICON[rb as usize], c);
                }
                text_in(d, cxl - 34, by0 + 5, BONUS_NAMES[rb as usize], c, half);
            }
        }
    }
    if p.ready && r.blink < 37 {
        let s = b"READY!";
        d.text((W - text_w(s)) / 2, 230, s, ACCENT, 0);
    }
}

// Scelta della racchetta (PaddlePick::draw di paddle_ui.rs), sulle righe di caratteri del C64: riga
// 0 il titolo, 1-3 il tempo, 4 P1/P2 e OK, 5-17 i ritratti grandi (colonne 0-10 e 29-39, quello di
// destra girato verso il centro), 5-12 la griglia 4x2 di caselle 4x4 (colonne 12-27, l'ultima è
// OMEGA, che non si sceglie), 13-21 il campo con le due racchette a grandezza reale, 18-21 i nomi
// disegnati, 22 le frasi, 24 i comandi o READY!.
const PORTRAIT_Y: i32 = TOP + 5 * 8;
const GRID_X: i32 = 12 * 8;
const GRID_Y: i32 = PORTRAIT_Y;
const CELL: i32 = 32;
const COURT_Y: i32 = TOP + 13 * 8;
const COURT_H: i32 = 9 * 8;
/// Centro verticale del nome disegnato: a metà fra il fondo comune dei ritratti (`ART_BASE`) e la
/// frase della riga 22 (le maiuscole cominciano 3 pixel e mezzo sopra il suo centro), come
/// `pick_name_y` di paddle_ui.rs.
fn name_y() -> i32 {
    TOP + (portraits::ART_BASE + 217) / 2
}

/// Angolo della casella `i` della griglia (prima riga ARCADE-TWIST, seconda BLASTER-OMEGA).
fn cell_xy(i: u32) -> (i32, i32) {
    (GRID_X + (i % 4) as i32 * CELL, GRID_Y + (i / 4) as i32 * CELL)
}

#[inline(never)]
fn paddles(r: &Regs, d: &mut Dl, p: &Pick) {
    let mut cast = Cast::new();
    let f = r.frame;
    centered(d, b"PICK YOUR PADDLE", 160, line(0), ACCENT);
    // griglia: le caselle dei sette tipi e quella di OMEGA in sagoma con il punto di domanda
    for i in 0..8u32 {
        let (x, y) = cell_xy(i);
        portrait(d, &portraits::SMALL[i as usize], i as usize, x, y);
        frame(d, x, y, CELL, CELL, 1, CELL_FRAME);
        if i as usize == OMEGA {
            centered(d, b"?", x + CELL / 2, y + CELL - 6, OMEGA_Q);
        }
    }
    net(d, COURT_Y, COURT_Y + COURT_H, WHITE);
    for side in 0..2usize {
        let kind = p.kcur[side];
        let chosen = p.chosen >> side & 1 != 0;
        let fixed = p.lock >> side & 1 != 0;
        // tutti i personaggi finiscono sulla stessa riga: scendono fino a ART_BASE
        let drop = portraits::ART_BASE - portraits::ART_BOTTOM[kind as usize];
        cast.big(d, kind as usize, PORTRAIT_X[side], PORTRAIT_Y + drop, side == 1);
        let mid = PORTRAIT_X[side] + PORTRAIT_W / 2;
        let head: &[u8] = match side {
            0 => b"P1",
            _ if p.cpu && fixed => b"CPU",
            _ => b"P2",
        };
        centered(d, head, mid, line(4), WHITE);
        if chosen {
            centered(d, b"OK", mid + if side == 0 { 28 } else { -28 }, line(4), ACCENT);
        }
        let img = &IMG_NAME[kind as usize];
        name_art(d, kind, name_x(mid, img.w as i32), name_y(), TL);
        paddle(d, kind, PADDLE_X[side], COURT_Y + COURT_H / 2, side == 0);
        centered(d, KIND_TAGS[kind as usize], HALF_X[side], line(22), WHITE);
    }
    // cursori sopra la griglia, gialli con la sigla del giocatore; lampeggiano finché si sceglie
    let on = (f / 15) % 4 != 3;
    for side in 0..2usize {
        let chosen = p.chosen >> side & 1 != 0;
        let fixed = p.lock >> side & 1 != 0;
        if !chosen && !fixed && !p.ready && !on {
            continue;
        }
        let (x, y) = cell_xy(p.kcur[side]);
        frame(d, x, y, CELL, CELL, 2, ACCENT);
        let tag: &[u8] = match side {
            0 => b"1P",
            _ if p.cpu && fixed => b"CPU",
            _ => b"2P",
        };
        let tw = tag.len() as i32 * 8 + 2;
        let tx = if side == 0 { x + 2 } else { x + CELL - 2 - tw };
        // sulla stessa casella la sigla di destra va in alto, 1P resta in basso
        let ty = if side == 1 && p.kcur[0] == p.kcur[1] { y + 1 } else { y + CELL - 10 };
        d.rect(tx, ty, tw, 9, BLACK);
        d.text(tx + 1, ty + 1, tag, ACCENT, 0);
    }
    if p.ready {
        if (f / 10) % 2 == 0 {
            centered(d, b"READY!", 160, line(24), ACCENT);
        }
    } else {
        // i comandi sotto la metà di chi sceglie (con il paddle o lo spinner si gira)
        let hint: &[u8] = if field(r.w[7], 27, 2) == 0 { b"STICK + A" } else { b"TURN + A" };
        for (side, x) in HALF_X.iter().enumerate() {
            if p.lock >> side & 1 == 0 {
                centered(d, hint, *x, line(24), GRAY);
            }
        }
    }
}
