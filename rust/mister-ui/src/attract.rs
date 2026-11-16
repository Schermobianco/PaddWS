//! Sequenza attract: auto-test, strisce, logo, titolo (come il vecchio `attract_render.v`).
//!
//! Nel titolo il nero di strisce, logo e scritte è il nero "solido" ([`pal::SOLID`]): pong_top ci
//! fa rimbalzare la pallina, che invece è nera e basta. Nel riquadro di WS (giallo dentro la striscia)
//! la pallina si vede nera solo sui pixel della scritta: la scritta disegnata una seconda volta,
//! ritagliata sulla pallina.

use crate::assets::{IMG_LOGO, IMG_WS, at};
use crate::dl::{Dl, text_w};
use crate::pal::{BLACK, PHOSPHOR, SOLID, WHITE, YELLOW};
use crate::regs::{M_BOOT, M_LOGO, M_STRIPES, Regs};

const W: i32 = 320;
const H: i32 = 240;

/// Avanzamento della striscia i: parte STRIPE_START_STEP frame dopo la precedente.
#[inline(never)]
fn slide_step(f: i32, i: i32) -> usize {
    let local = if f > i * at::STRIPE_START_STEP {
        f - i * at::STRIPE_START_STEP
    } else {
        0
    };
    local.min(at::SLIDE_LAST) as usize
}

/// Le tre strisce, con i bordi della parte sinistra e destra.
#[inline(never)]
fn stripes(d: &mut Dl, left: [i32; 3], right: [i32; 3], c: u8) {
    for i in 0..3 {
        let y = at::STRIPE_ROWS[i];
        d.rect(0, y, left[i], at::STRIPE_H, c);
        d.rect(right[i], y, W - right[i], at::STRIPE_H, c);
    }
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    let f = r.frame;
    let still_left = [75; 3];
    let still_right = [241; 3];
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
        M_STRIPES => {
            d.rect(0, 0, W, H, YELLOW);
            let mut left = [0; 3];
            let mut right = [0; 3];
            for i in 0..3 {
                left[i] = at::STRIPE_LEFT_END[slide_step(f, 2 * i as i32)];
                right[i] = at::STRIPE_RIGHT_START[slide_step(f, 2 * i as i32 + 1)];
            }
            stripes(d, left, right, BLACK);
        }
        M_LOGO => {
            if (at::WIPE_FRAMES..at::WIPE_FRAMES + at::FLASH_FRAMES).contains(&f) {
                d.rect(0, 0, W, H, WHITE);
                return;
            }
            d.rect(0, 0, W, H, YELLOW);
            stripes(d, still_left, still_right, BLACK);
            d.img(at::WS_X, at::WS_Y, &IMG_WS, YELLOW);
            let rows = if f < at::WIPE_FRAMES {
                51 * f / at::WIPE_FRAMES
            } else {
                51
            };
            let logo = d
                .img_obj(at::LOGO_X, at::LOGO_Y, &IMG_LOGO, BLACK)
                .clip(0, W, 0, at::LOGO_Y + rows);
            d.push(&logo);
            if f < at::WIPE_FRAMES {
                d.rect(at::LOGO_X, at::LOGO_Y + rows + 1, IMG_LOGO.w as i32, 1, WHITE);
            }
        }
        _ => {
            d.rect(0, 0, W, H, YELLOW);
            // pallina (nera, non solida) sotto a tutto il nero solido
            d.rect(r.ball_x, r.ball_y, 4, 4, BLACK);
            stripes(d, still_left, still_right, SOLID);
            // spenta, la scritta resta nera ma non solida (come il `solid` di prima)
            let ws_off = at::WS_OFF.iter().any(|&(a, b)| f >= a && f < b);
            if ws_off {
                d.img(at::WS_X, at::WS_Y, &IMG_WS, BLACK);
            } else {
                d.img(at::WS_X, at::WS_Y, &IMG_WS, YELLOW);
                let ball =
                    d.img_obj(at::WS_X, at::WS_Y, &IMG_WS, BLACK)
                        .clip(r.ball_x, r.ball_x + 4, r.ball_y, r.ball_y + 4);
                d.push(&ball);
            }
            d.img(at::LOGO_X, at::LOGO_Y, &IMG_LOGO, SOLID);
            if f > at::LABEL_FROM && r.blink < at::BLINK_ON {
                let s: &[u8] = if !r.free_play && r.credits == 0 {
                    b"INSERT COIN"
                } else {
                    b"PRESS START"
                };
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
