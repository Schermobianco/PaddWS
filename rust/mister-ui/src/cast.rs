//! Personaggi e disposizione comuni alla scelta della racchetta (pick.rs), allo schermo VS
//! (intro.rs) e alla sfilata del finale (ending.rs), come `paddle_ui.rs` del gioco Rust: le
//! posizioni sono pixel del campo 320x240 sulle righe di caratteri del C64 (40x25 da `TOP`).
//!
//! I ritratti (assets::portraits) hanno 4 bit per pixel, il ruolo del colore + 1, e la tavolozza del
//! personaggio da `pal::PORTRAIT`. I grandi hanno le righe una dopo l'altra (11 parole, non 16): si
//! leggono con la tabella delle righe, scritta una volta per frame ([`Cast::big`]).

use crate::Img;
use crate::assets::game::{KIND_H, PW};
use crate::assets::{IMG_NAME, pads, portraits};
use crate::dl::{Dl, text_w};
use crate::pal::{PADS, PADS_OMEGA, PORTRAIT};

/// prima riga della griglia di caratteri del C64 nello schermo 320x240
pub const TOP: i32 = 20;
pub const PORTRAIT_W: i32 = 88;
pub const PORTRAIT_H: i32 = 104;
/// colonna dei ritratti grandi di ciascun lato
pub const PORTRAIT_X: [i32; 2] = [0, 320 - PORTRAIT_W];
/// centro delle racchette nel campo di ciascun lato
pub const PADDLE_X: [i32; 2] = [14 * 8 + 4, 25 * 8 + 4];
/// centro di ciascuna metà, per le frasi e i comandi
pub const HALF_X: [i32; 2] = [80, 240];
/// OMEGA nelle tabelle dei ritratti (dopo i sette tipi)
pub const OMEGA: usize = 7;

/// Centro verticale della riga di caratteri `row`.
pub const fn line(row: i32) -> i32 {
    TOP + row * 8 + 4
}

/// Base della tavolozza del personaggio `k` (i sette tipi, poi OMEGA).
pub const fn pal_of(k: usize) -> u8 {
    PORTRAIT + 8 * k as u8
}

/// Scritta del font 8x8 centrata nel punto (cx, cy).
#[inline(never)]
pub fn centered(d: &mut Dl, s: &[u8], cx: i32, cy: i32, c: u8) {
    d.text(cx - text_w(s) / 2, cy - 4, s, c, 0);
}

/// Il nome disegnato del tipo `kind` (assets/titles) centrato in (cx, cy), nei colori `pal`.
#[inline(never)]
pub fn name_art(d: &mut Dl, kind: u32, cx: i32, cy: i32, pal: u8) {
    let img = &IMG_NAME[kind as usize];
    d.img(cx - img.w as i32 / 2, cy - img.h as i32 / 2, img, pal);
}

/// Centro x di un nome disegnato largo `w` sotto il ritratto di centro `mid`, dentro lo schermo.
pub fn name_x(mid: i32, w: i32) -> i32 {
    let half = w / 2 + 2;
    mid.clamp(half, 320 - half)
}

/// Ritratti dei personaggi nel frame in disegno.
pub struct Cast {
    /// tabella delle righe dei ritratti grandi (scritta al primo che serve)
    rows: Option<u32>,
}

impl Cast {
    pub const fn new() -> Self {
        Self { rows: None }
    }

    /// Ritratto grande del personaggio `k` con l'angolo in (x, y); `mirror` lo gira verso sinistra.
    #[inline(never)]
    pub fn big(&mut self, d: &mut Dl, k: usize, x: i32, y: i32, mirror: bool) {
        let lt = match self.rows {
            Some(lt) => lt,
            None => {
                let mut rows = [0i32; PORTRAIT_H as usize];
                for (v, row) in rows.iter_mut().enumerate() {
                    *row = v as i32 * portraits::BIG_ROW_WORDS;
                }
                let lt = d.lines(&rows);
                self.rows = Some(lt);
                lt
            }
        };
        let mut o = d.img_obj(x, y, &portraits::BIG[k], pal_of(k));
        o.lt = Some(lt);
        o.ltrow = true;
        o.fx = mirror;
        d.push(&o);
    }
}

/// Immagine di un ritratto (casella o medio) del personaggio `k`.
#[inline(never)]
pub fn portrait(d: &mut Dl, img: &Img, k: usize, x: i32, y: i32) {
    d.img(x, y, img, pal_of(k));
}

/// Riquadro vuoto spesso `t` pixel verso l'interno del rettangolo (x, y, w, h).
#[inline(never)]
pub fn frame(d: &mut Dl, x: i32, y: i32, w: i32, h: i32, t: i32, c: u8) {
    d.rect(x, y, w, t, c);
    d.rect(x, y + h - t, w, t, c);
    d.rect(x, y + t, t, h - 2 * t, c);
    d.rect(x + w - t, y + t, t, h - 2 * t, c);
}

/// Mezzeria tratteggiata del campo sotto la griglia (o del VS): trattini di 5 righe ogni 8, larghi 2,
/// da y0 + 2 finché iniziano prima di `y1`.
#[inline(never)]
pub fn net(d: &mut Dl, y0: i32, y1: i32, c: u8) {
    let mut y = y0 + 2;
    while y < y1 {
        d.rect(159, y, 2, 5, c);
        y += 8;
    }
}

/// Racchetta del tipo `kind` a grandezza reale (anteprima: TWIST inclinata, le immagini dello scatto
/// del RUSH) centrata in (cx, cy), con il davanti verso destra o verso sinistra.
#[inline(never)]
pub fn paddle(d: &mut Dl, kind: u32, cx: i32, cy: i32, right: bool) {
    pad_image(d, &pads::PREVIEW, kind, cx, cy, right, PADS);
}

/// Racchetta del tipo `kind` dritta, senza le immagini del RUSH: le forme di OMEGA, rosse (`omega`) o
/// bianche nel lampo.
#[inline(never)]
pub fn plain_paddle(d: &mut Dl, kind: u32, cx: i32, cy: i32, right: bool, omega: bool) {
    pad_image(d, &pads::PLAIN, kind, cx, cy, right, if omega { PADS_OMEGA } else { PADS });
}

/// Immagine della racchetta `kind` di `set` (colonna t = 0 al retro del corpo, specchiata se è
/// rivolta a sinistra) centrata in (cx, cy), con la tavolozza da `base`.
fn pad_image(d: &mut Dl, set: &[(Img, i32, i32); 7], kind: u32, cx: i32, cy: i32, right: bool, base: u8) {
    let (img, t0, r0) = &set[kind as usize];
    let xa = cx - PW / 2;
    let xb = xa + PW - 1;
    let x = if right { xa + t0 } else { xb - t0 - img.w as i32 + 1 };
    let mut o = d.img_obj(x, cy - (KIND_H[kind as usize] >> 1) + r0, img, base);
    o.fx = !right;
    d.push(&o);
}
