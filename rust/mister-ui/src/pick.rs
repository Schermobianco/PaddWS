//! Schermate di scelta di NEXT (come il vecchio next_render.v): prima la racchetta, poi i bonus.
//! Ogni colonna sta nella sua metà dello schermo (il renderer sceglieva il lato dal pixel): gli
//! oggetti di un lato sono ritagliati sulla sua metà.

use crate::Img;
use crate::assets::game::{BONUS_NAMES, CAP, KIND_H, KIND_NAMES, KIND_TAGS, PW};
use crate::assets::{IMG_CAP_FRAME, IMG_ICON, IMG_PICK_NET, pads};
use crate::dl::{CLASS_A, Dl, code, text_w};
use crate::pal::{ACCENT, BLACK, GRAY, PAD, PAD_OFF, WHITE};
use crate::regs::{Regs, field};

const W: i32 = 320;

/// Stato della scelta dai registri.
struct Pick {
    cur: [u32; 2],
    mask: [u32; 2],
    secs: u32,
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
            secs: field(w, 18, 4),
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

/// Titolo, secondi rimasti e mezzeria, comuni alle due schermate.
#[inline(never)]
fn common(d: &mut Dl, p: &Pick, title: &[u8]) {
    d.text((W - text_w(title)) / 2, 8, title, ACCENT, 0);
    let (a, b) = if p.secs >= 10 { (1, 0) } else { (0, p.secs as u8) };
    d.cells(152, 30, &[(a, WHITE), (b, WHITE)]);
    d.img(W / 2 - 1, 56, &IMG_PICK_NET, WHITE);
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    let p = Pick::new(r);
    d.class = CLASS_A;
    d.rect(0, 0, W, 240, BLACK);
    if p.paddle {
        common(d, &p, b"PICK YOUR PADDLE");
        for side in 0..2usize {
            let half = if side == 0 { (0, W / 2) } else { (W / 2, W) };
            let cxl = if side == 0 { W / 4 } else { 3 * W / 4 };
            let kcur = p.kcur[side];
            let chosen = p.chosen >> side & 1 != 0;
            let head: &[u8] = if side == 0 {
                b"P1"
            } else if p.cpu {
                b"CPU"
            } else {
                b"P2"
            };
            text_in(d, cxl - 50, 58, head, WHITE, half);
            if chosen {
                text_in(d, cxl + 26, 58, b"OK", ACCENT, half);
            }
            // anteprima a grandezza reale, verso la mezzeria (immagine rivolta a destra, specchiata a destra)
            let h = KIND_H[kcur as usize];
            let kcx = cxl - 60;
            pad_img(
                d,
                &pads::PREVIEW[kcur as usize],
                kcx - PW / 2,
                kcx - PW / 2 + PW - 1,
                side == 0,
                144 - (h >> 1),
                PAD,
                half,
                (0, 240),
            );
            // sette righe ogni 20 pixel: cursore, miniatura e nome
            for row in 0..7u32 {
                let y0 = 74 + 20 * row as i32;
                let band = (y0, y0 + 20);
                let sel = kcur == row;
                if sel && !chosen && !p.ready {
                    let base = d.tiles(b">", ACCENT);
                    let o = d
                        .text_obj(cxl - 42, y0 + 5, base, 1, 0)
                        .clip(half.0, half.1, band.0, band.1);
                    d.push(&o);
                }
                let mh = KIND_H[row as usize];
                pad_img(
                    d,
                    &pads::MINI[row as usize],
                    cxl - 25,
                    cxl - 24,
                    side == 0,
                    y0 + 9 - (mh >> 2),
                    if sel { PAD } else { PAD_OFF },
                    half,
                    band,
                );
                let name = KIND_NAMES[row as usize];
                let c = if sel { if chosen { ACCENT } else { WHITE } } else { GRAY };
                let base = d.tiles(name, c);
                let o = d
                    .text_obj(cxl - 14, y0 + 5, base, name.len(), 0)
                    .clip(half.0, half.1, band.0, band.1);
                d.push(&o);
            }
            let tag = KIND_TAGS[kcur as usize];
            text_in(d, cxl - text_w(tag) / 2, 218, tag, GRAY, half);
        }
    } else {
        common(d, &p, b"PICK 3 BONUSES");
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

/// Racchetta della scelta da un'immagine (t0, r0: la sua prima colonna e riga nelle coordinate del
/// tipo): verso destra x = xa + t, verso sinistra x = xb - t; y = y0 + r.
#[allow(clippy::too_many_arguments)]
#[inline(never)]
fn pad_img(
    d: &mut Dl,
    p: &(Img, i32, i32),
    xa: i32,
    xb: i32,
    right: bool,
    y0: i32,
    pal: u8,
    half: (i32, i32),
    band: (i32, i32),
) {
    let (img, t0, r0) = p;
    let x = if right { xa + t0 } else { xb - t0 - img.w as i32 + 1 };
    let mut o = d.img_obj(x, y0 + r0, img, pal);
    o.fx = !right;
    let o = o.clip(half.0, half.1, band.0, band.1);
    d.push(&o);
}
