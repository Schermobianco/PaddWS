//! Racchette disegnate fuori dalla partita (anteprime della scelta, presentazione, sfilata del
//! finale), come `kind_px` del vecchio next_render.v: pochi rettangoli per tipo.
//!
//! Coordinate del tipo: t è la colonna contata dal retro (0) verso la faccia (PW - 1; oltre: davanti,
//! sotto 0: dietro), r la riga dall'alto. Con `half` si prende un pixel ogni due in t e in r
//! (miniature a metà grandezza: il pixel (t, r) della miniatura è quello (2t, 2r) della racchetta).

use crate::Img;
use crate::assets::game::PW;
use crate::assets::{IMG_PAT_A, IMG_PAT_B};
use crate::dl::{Dl, Kind, Obj};
use crate::pal::BLACK;

/// Colori dei pezzi (0 = non si disegna).
#[derive(Clone, Copy)]
pub struct Colors {
    pub body: u8,
    pub mark: u8,
    pub detail: u8,
    pub ghost: [u8; 3],
    /// immagini del RUSH a scacchi (sfilata del finale): la prima a puntini, la seconda a scacchi,
    /// colore `ghost` sul nero
    pub pattern: bool,
}

/// Una racchetta: dove sta la colonna t = 0 (verso destra: x = xa + t; verso sinistra:
/// x = xb - t) e la riga r = 0.
#[derive(Clone, Copy)]
pub struct Pad {
    pub kind: u32,
    pub xa: i32,
    pub xb: i32,
    pub right: bool,
    pub y: i32,
    pub h: i32,
    pub tilt: i32,
    /// pezzo di muro del GUARDIAN dietro (scelta)
    pub preview: bool,
    /// immagini del RUSH attaccate dietro (scelta)
    pub ghosts: bool,
    pub half: bool,
}

fn ceil2(a: i32) -> i32 {
    (a + 1).div_euclid(2)
}

impl Pad {
    /// Rettangolo [t0, t1) x [r0, r1) nelle coordinate del tipo, a tinta unita o con una trama.
    fn rect(&self, d: &mut Dl, t0: i32, t1: i32, r0: i32, r1: i32, c: u8) {
        self.rect_pat(d, t0, t1, r0, r1, c, None);
    }

    #[allow(clippy::too_many_arguments)]
    fn rect_pat(&self, d: &mut Dl, t0: i32, t1: i32, r0: i32, r1: i32, c: u8, pat: Option<&Img>) {
        if c == 0 {
            return;
        }
        let (t0, t1, r0, r1) = if self.half {
            (ceil2(t0), ceil2(t1), ceil2(r0), ceil2(r1))
        } else {
            (t0, t1, r0, r1)
        };
        if t0 >= t1 || r0 >= r1 {
            return;
        }
        let x = if self.right { self.xa + t0 } else { self.xb - t1 + 1 };
        let y = self.y + r0;
        match pat {
            None => d.rect(x, y, t1 - t0, r1 - r0, c),
            Some(img) => {
                // trama legata alla parità dei pixel dello schermo
                let mut o = d.img_obj(x, y, img, c);
                o.w = t1 - t0;
                o.h = r1 - r0;
                o.u0 = x & 1;
                o.v0 = y & 1;
                o.opaque = true;
                o.cb = BLACK;
                d.push(&o);
            }
        }
    }

    /// Scorrimento orizzontale della riga r di TWIST: (r - h/2) * tilt / 8, come kind_px.
    fn twist(&self, r: i32) -> i32 {
        let dd = r - (self.h >> 1);
        let m = self.tilt.abs();
        let s = if m & 1 != 0 { dd } else { 0 } + if m & 2 != 0 { dd << 1 } else { 0 };
        if self.tilt < 0 { -(s >> 3) } else { s >> 3 }
    }

    pub fn draw(&self, d: &mut Dl, c: &Colors) {
        let h = self.h;
        match self.kind {
            3 => {
                // TWIST: righe spostate (tabella delle righe)
                let rows = if self.half { ceil2(h) } else { h };
                let mut dx = [0i32; 64];
                for (k, v) in dx.iter_mut().enumerate().take(rows as usize) {
                    let r = if self.half { 2 * k as i32 } else { k as i32 };
                    let s = self.twist(r);
                    let s = if self.half { ceil2(s) } else { s };
                    *v = if self.right { s } else { -s };
                }
                let lt = d.lines(&dx[..rows as usize]);
                let w = if self.half { ceil2(PW) } else { PW };
                let x = if self.right { self.xa } else { self.xb - w + 1 };
                let mut o = Obj::new(Kind::Rect, x, self.y, w, rows);
                o.ca = c.body;
                o.lt = Some(lt);
                o.class = d.class;
                if c.body != 0 {
                    d.push(&o);
                }
            }
            2 => {
                // HAMMER: più spessa verso il retro, bande grigie del peso
                self.rect(d, -(PW / 2), PW, 0, h, c.body);
                for r in [(h >> 1) - 10, (h >> 1) + 8] {
                    self.rect(d, -(PW / 2), PW, r, r + 2, c.detail);
                }
            }
            4 => {
                // BLASTER: spigoli del davanti smussati, due canne davanti
                self.rect(d, 0, PW - 2, 0, 1, c.body);
                self.rect(d, 0, PW - 1, 1, 2, c.body);
                self.rect(d, 0, PW, 2, h - 2, c.body);
                self.rect(d, 0, PW - 1, h - 2, h - 1, c.body);
                self.rect(d, 0, PW - 2, h - 1, h, c.body);
                for r in [(h >> 1) - 4, (h >> 1) + 2] {
                    self.rect(d, PW, PW + 2, r, r + 2, c.detail);
                }
            }
            1 => {
                // TITAN: segni sul retro in cima e in fondo
                self.rect(d, 0, PW, 0, h, c.body);
                self.rect(d, 0, 1, 0, h >> 3, c.mark);
                self.rect(d, 0, 1, h - (h >> 3), h, c.mark);
            }
            5 => {
                self.rect(d, 0, PW, 0, h, c.body);
                if self.ghosts {
                    // tre immagini dietro, più scure verso il retro, con una colonna vuota fra l'una e l'altra
                    let (pa, pb) = if c.pattern {
                        (Some(&IMG_PAT_A), Some(&IMG_PAT_B))
                    } else {
                        (None, None)
                    };
                    self.rect_pat(d, -3 * PW, -2 * PW - 1, 0, h, c.ghost[0], pa);
                    self.rect_pat(d, -2 * PW, -PW - 1, 0, h, c.ghost[1], pb);
                    self.rect(d, -PW, -1, 0, h, c.ghost[2]);
                }
            }
            6 => {
                self.rect(d, 0, PW, 0, h, c.body);
                if self.preview {
                    // pezzo di muro dietro: tratti di 5 righe ogni 8
                    let q = h >> 2;
                    let mut k = 0;
                    while 8 * k - q < h + q {
                        let r0 = (8 * k - q).max(-q);
                        let r1 = (8 * k + 5 - q).min(h + q);
                        self.rect(d, -8, -6, r0, r1, c.mark);
                        k += 1;
                    }
                }
            }
            _ => self.rect(d, 0, PW, 0, h, c.body),
        }
    }
}
