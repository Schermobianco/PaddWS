//! Sequenza attract: auto-test e titolo (come `attract.rs` del gioco per PC).
//!
//! Nel titolo il nero di strisce, logo e scritte è il nero "solido" ([`pal::SOLID`]): pong_top ci
//! fa rimbalzare la pallina, che invece è nera e basta. Nel riquadro di WS (giallo dentro la striscia)
//! la pallina si vede nera solo sui pixel della scritta: la scritta disegnata una seconda volta,
//! ritagliata sulla pallina.

use crate::assets::{IMG_LOGO, IMG_NEXT, IMG_WS, at};
use crate::dl::{Dl, text_w};
use crate::pal::{BLACK, PHOSPHOR, SOLID, WHITE, YELLOW};
use crate::regs::{M_BOOT, Regs};

const W: i32 = 320;
const H: i32 = 240;
/// Bordi delle strisce ferme e misure delle lettere di NEXT.
const STRIPE_LEFT: i32 = 75;
const STRIPE_RIGHT: i32 = 241;
const NEXT_H: i32 = 10;
const NEXT_LETTER_W: i32 = 8;

/// Le tre strisce, ferme: la parte sinistra arriva a x = 75, quella destra parte da x = 241.
#[inline(never)]
fn stripes(d: &mut Dl, c: u8) {
    for i in 0..3 {
        let y = at::STRIPE_ROWS[i];
        d.rect(0, y, STRIPE_LEFT, at::STRIPE_H, c);
        d.rect(STRIPE_RIGHT, y, W - STRIPE_RIGHT, at::STRIPE_H, c);
    }
}

/// NEXT sotto il logo, come `Attract::draw_next` del gioco per PC: le lettere partono una dopo
/// l'altra a righe sfalsate che si assestano (le stesse tabelle, in interi), poi la riga larga come il
/// logo si allarga dal centro. Una riga di una lettera è la bitmap di tutto NEXT ritagliata su quella
/// riga e sulle colonne della lettera, spostata di `dx`. Il nero è "solido", come il resto del titolo.
#[inline(never)]
fn next(f: i32, d: &mut Dl) {
    for i in 0..4 {
        let k = f - (at::NEXT_START + at::NEXT_STEP * i);
        if k < 0 {
            continue;
        }
        let x0 = at::NEXT_X + i * at::NEXT_PITCH;
        if k >= at::NEXT_LETTER_FRAMES {
            let o = d.img_obj(at::NEXT_X, at::NEXT_Y, &IMG_NEXT, SOLID).clip(x0, x0 + NEXT_LETTER_W, 0, H);
            d.push(&o);
            continue;
        }
        let s = (k >> 1) as usize;
        for row in 0..NEXT_H {
            let idx = ((row * 7 + s as i32 * 29 + i * 61) & 255) as usize;
            if at::NEXT_NOISE[idx] as u16 >= at::NEXT_PRESENT[s] {
                continue;
            }
            let amp = at::NEXT_AMP[s] as i32;
            let dx = at::NEXT_NOISE[(idx + 131) & 255] as i32 % (2 * amp + 1) - amp;
            let y = at::NEXT_Y + row;
            let o = d
                .img_obj(at::NEXT_X + dx, at::NEXT_Y, &IMG_NEXT, SOLID)
                .clip(x0 + dx, x0 + dx + NEXT_LETTER_W, y, y + 1);
            d.push(&o);
        }
    }
    let k = f - at::NEXT_LINE_START;
    if k >= 0 {
        let half = at::NEXT_LINE_HALF[k.min(at::NEXT_LINE_FRAMES - 1) as usize] as i32;
        d.rect(at::NEXT_LINE_X - half, at::NEXT_LINE_Y, 2 * half, at::NEXT_LINE_H, SOLID);
    }
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    let f = r.frame;
    match r.mode {
        M_BOOT => {
            d.rect(0, 0, W, H, BLACK);
            if f < at::BOOT_GRID_FROM {
                // una riga ogni 30 frame (moltiplicazione per il reciproco, come l'RTL)
                let q = (f * at::BOOT_LINE_RECIP) >> 16;
                let shown = q.min(5);
                for (k, line) in at::BOOT_LINES.iter().enumerate() {
                    let k = k as i32;
                    if !line.is_empty() && (k == 0 || shown >= k) {
                        d.text(at::BOOT_X, at::BOOT_Y + k * at::BOOT_STEP, line, PHOSPHOR, 0);
                    }
                }
                let cursor_on = ((f * 6554) >> 16) & 1 == 0;
                if cursor_on {
                    let line = at::BOOT_LINES[shown as usize];
                    let cx = at::BOOT_X + if line.is_empty() { 0 } else { text_w(line) } + 2;
                    d.rect(cx, at::BOOT_Y + shown * at::BOOT_STEP, 5, 8, PHOSPHOR);
                }
            } else {
                // reticolo di test dei vecchi cabinati
                for x in (0..W).step_by(16) {
                    d.rect(x, 0, 1, H, WHITE);
                }
                for y in (0..H).step_by(16) {
                    d.rect(0, y, W, 1, WHITE);
                }
                d.rect(0, H - 1, W, 1, WHITE);
            }
        }
        _ => {
            d.rect(0, 0, W, H, YELLOW);
            // pallina (nera, non solida) sotto a tutto il nero solido
            d.rect(r.ball_x, r.ball_y, 4, 4, BLACK);
            stripes(d, SOLID);
            d.img(at::WS_X, at::WS_Y, &IMG_WS, YELLOW);
            let ball = d
                .img_obj(at::WS_X, at::WS_Y, &IMG_WS, BLACK)
                .clip(r.ball_x, r.ball_x + 4, r.ball_y, r.ball_y + 4);
            d.push(&ball);
            d.img(at::LOGO_X, at::LOGO_Y, &IMG_LOGO, SOLID);
            if r.next {
                next(f, d);
            }
            // l'unico invito del titolo: INSERT COIN senza crediti (e senza NEXT, che sta al suo posto)
            if f > at::LABEL_FROM && r.blink < at::BLINK_ON && !r.free_play && r.credits == 0 && !r.next {
                let s = b"INSERT COIN";
                d.text((W - text_w(s)) / 2, at::LABEL_Y, s, SOLID, 0);
            }
            if r.free_play {
                let s = b"FREE PLAY";
                d.text((W - text_w(s)) / 2, at::CREDIT_Y, s, SOLID, 0);
            } else {
                let s = [b'C', b'R', b'E', b'D', b'I', b'T', b' ', b'0' + r.credits as u8];
                d.text((W - 56 - 8) / 2, at::CREDIT_Y, &s, SOLID, 0);
            }
            let copy = b"\x7F 2026 SCHERMOBIANCO";
            d.text((W - text_w(copy)) / 2, at::COPYRIGHT_Y, copy, SOLID, 0);
        }
    }
}
