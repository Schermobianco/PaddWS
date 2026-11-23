//! Lista degli oggetti di un frame (formato in testa a `mister/rtl/ui_render.v`), scritta
//! direttamente nel banco nascosto del motore.

use crate::assets::{FONT_COLS, FONT_MAP};
use crate::win::Win;
use crate::{Img, Port, map};

/// Sorgente di un oggetto.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    /// rettangolo pieno del colore A
    Rect = 0,
    /// caratteri 8x8 dalla RAM dei caratteri (base, `ssh` = caratteri per riga in scorrimento)
    Text = 1,
    /// immagine della ROM grafica (base, `ssh` = parole per riga, `bpp` in scorrimento)
    Img = 2,
}

/// Classe di priorità rispetto al campo (pong_top): A sopra tutto tranne il lampo, B sopra le
/// aggiunte di NEXT, C dentro il campo (sotto palla e racchette). Nelle schermate a tutto schermo
/// non conta.
pub const CLASS_A: u32 = 0;
pub const CLASS_B: u32 = 1;
pub const CLASS_C: u32 = 2;

/// Un oggetto: rettangolo di destinazione (x, y, w, h) e come si legge la sorgente.
#[derive(Clone, Copy, Debug)]
pub struct Obj {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    pub fx: bool,
    pub fy: bool,
    pub swap: bool,
    pub sx: u32,
    pub sy: u32,
    /// prima voce della tabella delle righe (scostamento in x della riga j)
    pub lt: Option<u32>,
    /// la tabella delle righe dà la riga della sorgente (parola dalla base) invece dello scostamento
    pub ltrow: bool,
    pub opaque: bool,
    pub kind: Kind,
    pub class: u32,
    /// ritaglio [x0, x1) e [y0, y1)
    pub clip: [i32; 4],
    pub base: u32,
    pub ssh: u32,
    pub bpp: u32,
    pub u0: i32,
    pub v0: i32,
    pub ca: u8,
    pub cb: u8,
}

impl Obj {
    #[inline(always)]
    pub const fn new(kind: Kind, x: i32, y: i32, w: i32, h: i32) -> Self {
        Self {
            x,
            y,
            w,
            h,
            fx: false,
            fy: false,
            swap: false,
            sx: 0,
            sy: 0,
            lt: None,
            ltrow: false,
            opaque: false,
            kind,
            class: CLASS_A,
            clip: [0, 320, 0, 240],
            base: 0,
            ssh: 0,
            bpp: 0,
            u0: 0,
            v0: 0,
            ca: 0,
            cb: 0,
        }
    }

    /// Ritaglio aggiuntivo (intersezione con quello che c'è).
    #[inline(always)]
    pub fn clip(mut self, x0: i32, x1: i32, y0: i32, y1: i32) -> Self {
        self.clip = [
            self.clip[0].max(x0),
            self.clip[1].min(x1),
            self.clip[2].max(y0),
            self.clip[3].min(y1),
        ];
        self
    }
}

/// Larghezza in pixel di una scritta del font 8x8 a scala 1: l'ultima colonna vuota non conta, tranne
/// dopo uno spazio finale (come `text_mask` di tools/gen_attract_assets.py).
pub fn text_w(s: &[u8]) -> i32 {
    let n = s.len() as i32;
    if s.last() == Some(&b' ') { 8 * n } else { 8 * n - 1 }
}

/// Lettere di una scritta del font 8x8: gruppi di colonne accese separati da colonne vuote (come
/// `verilog_letters` di tools/gen_attract_assets.py). Scrive la prima colonna (`l0`) e quella dopo
/// l'ultima (`l1`) di ogni lettera e restituisce quante sono.
pub fn letters(s: &[u8], mut l0: Option<&mut [i32]>, mut l1: Option<&mut [i32]>) -> usize {
    let w = text_w(s);
    let mut n = 0;
    let mut start = -1;
    for x in 0..=w {
        let lit = x < w && FONT_COLS[code(s[(x / 8) as usize]) as usize] & (0x80 >> (x % 8)) != 0;
        if lit && start < 0 {
            start = x;
        } else if !lit && start >= 0 {
            if let Some(a) = l0.as_deref_mut() {
                a[n] = start;
            }
            if let Some(b) = l1.as_deref_mut() {
                b[n] = x;
            }
            n += 1;
            start = -1;
        }
    }
    n
}

/// Codice del font di un carattere ASCII.
pub fn code(c: u8) -> u8 {
    FONT_MAP[(c & 0x7F) as usize]
}

pub struct Dl<'a> {
    p: &'a mut dyn Port,
    /// finestra della DDR3 (immagini copiate per il frame)
    win: &'a mut Win,
    n: u32,
    tiles: u32,
    lt: u32,
    /// classe degli oggetti che seguono
    pub class: u32,
    /// ritaglio aggiunto a tutti gli oggetti che seguono
    pub clip: [i32; 4],
    /// spostamento in x degli oggetti che seguono (con il loro ritaglio)
    pub dx: i32,
    /// griglia in prospettiva dietro agli oggetti (schermate prima della partita): la disegna
    /// rtl/ui_render.v dove nessun oggetto copre il pixel; il valore è il colore RGB dell'impulso
    pub grid: Option<u32>,
}

impl<'a> Dl<'a> {
    pub fn new(p: &'a mut dyn Port, win: &'a mut Win) -> Self {
        Self {
            p,
            win,
            n: 0,
            tiles: 0,
            lt: 0,
            class: CLASS_A,
            clip: [0, 320, 0, 240],
            dx: 0,
            grid: None,
        }
    }

    /// L'immagine `img` della DDR3 (`words` parole) copiata in uno dei `count` posti a passo `stride`
    /// della finestra ([`Win::place`]); None se la grafica della DDR3 non è caricata.
    pub fn ddr(&mut self, img: &Img, words: u16, stride: u16, count: u16) -> Option<Img> {
        self.win.place(self.p, img, words, stride, count)
    }

    /// Aggiunge un oggetto (se ha righe visibili e c'è posto).
    #[inline(never)]
    pub fn push(&mut self, o: &Obj) {
        // ritaglio e spostamento della lista, senza copiare l'oggetto
        let c = self.clip;
        let dx = self.dx;
        let x = o.x + dx;
        let ya = o.y.max(o.clip[2]).max(c[2]).max(0);
        let yb = (o.y + o.h).min(o.clip[3]).min(c[3]).min(240);
        let cx0 = (o.clip[0].max(c[0]) + dx).max(0);
        let cx1 = (o.clip[1].min(c[1]) + dx).min(320);
        if ya >= yb || cx0 >= cx1 || o.w <= 0 || self.n >= map::MAX_OBJ {
            return;
        }
        let words = [
            ya as u32 | (yb as u32) << 9,
            (x as u32 & 0x7FF) | (o.y as u32 & 0x7FF) << 11 | (o.w as u32 & 0x3FF) << 22,
            (o.h as u32 & 0x3FF)
                | (o.fx as u32) << 10
                | (o.fy as u32) << 11
                | (o.swap as u32) << 12
                | (o.sx & 3) << 13
                | (o.sy & 3) << 15
                | (o.lt.is_some() as u32) << 17
                | (o.opaque as u32) << 18
                | (o.kind as u32) << 19
                | (o.class & 3) << 21
                | (o.ltrow as u32) << 23,
            cx0 as u32 | (cx1 as u32) << 9,
            (o.base & 0xFFFF) | (o.ssh & 15) << 16 | (o.bpp & 3) << 20,
            (o.u0 as u32 & 0x3FF) | (o.v0 as u32 & 0x3FF) << 10,
            o.ca as u32 | (o.cb as u32) << 8,
            o.lt.unwrap_or(0) & 0x1FF,
        ];
        self.p.write_block(map::OBJ + 8 * self.n, &words);
        self.n += 1;
    }

    /// Scrive dei caratteri nella RAM dei caratteri (colore per carattere) e restituisce il primo indice.
    #[inline(never)]
    pub fn tiles(&mut self, s: &[u8], color: u8) -> u32 {
        let base = self.tiles;
        let n = s.len().min((map::MAX_TILE - base.min(map::MAX_TILE)) as usize);
        let mut at = map::TILE + base;
        for chunk in s[..n].chunks(8) {
            let mut buf = [0u32; 8];
            for (k, c) in chunk.iter().enumerate() {
                buf[k] = code(*c) as u32 | (color as u32) << 8;
            }
            self.p.write_block(at, &buf[..chunk.len()]);
            at += chunk.len() as u32;
        }
        self.tiles += s.len() as u32;
        base
    }

    /// Scrive dei caratteri già in codici del font, ciascuno con il suo colore; restituisce il primo indice.
    #[inline(never)]
    pub fn codes(&mut self, cells: &[(u8, u8)]) -> u32 {
        let base = self.tiles;
        let n = cells.len().min((map::MAX_TILE - base.min(map::MAX_TILE)) as usize);
        let mut at = map::TILE + base;
        for chunk in cells[..n].chunks(8) {
            let mut buf = [0u32; 8];
            for (k, (c, color)) in chunk.iter().enumerate() {
                buf[k] = *c as u32 | (*color as u32) << 8;
            }
            self.p.write_block(at, &buf[..chunk.len()]);
            at += chunk.len() as u32;
        }
        self.tiles += cells.len() as u32;
        base
    }

    /// Celle del font (codici e colori) in fila dall'angolo (x, y), a scala 1.
    #[inline(never)]
    pub fn cells(&mut self, x: i32, y: i32, cells: &[(u8, u8)]) {
        let base = self.codes(cells);
        let o = self.text_obj(x, y, base, cells.len(), 0);
        self.push(&o);
    }

    /// Scrive voci della tabella delle righe (scostamenti con segno o righe della sorgente) e
    /// restituisce la prima.
    #[inline(never)]
    pub fn lines(&mut self, dx: &[i32]) -> u32 {
        let base = self.lt;
        let room = (map::MAX_LT - base.min(map::MAX_LT)) as usize;
        let mut at = base;
        for chunk in dx[..dx.len().min(room)].chunks(8) {
            let mut buf = [0u32; 8];
            for (k, v) in chunk.iter().enumerate() {
                buf[k] = *v as u32 & 0xFFFF;
            }
            self.p.write_block(map::LT + at, &buf[..chunk.len()]);
            at += chunk.len() as u32;
        }
        self.lt += dx.len() as u32;
        base
    }

    /// Rettangolo pieno.
    #[inline(never)]
    pub fn rect(&mut self, x: i32, y: i32, w: i32, h: i32, color: u8) {
        let mut o = Obj::new(Kind::Rect, x, y, w, h);
        o.ca = color;
        o.class = self.class;
        self.push(&o);
    }

    /// Oggetto di una scritta (caratteri già scritti da `base`), in una riga, a scala 1 << sh.
    #[inline(always)]
    pub fn text_obj(&self, x: i32, y: i32, base: u32, len: usize, sh: u32) -> Obj {
        let mut o = Obj::new(Kind::Text, x, y, (8 * len as i32) << sh, 8 << sh);
        o.base = base;
        o.sx = sh;
        o.sy = sh;
        o.class = self.class;
        o
    }

    /// Scritta dritta a scala 1 << sh con l'angolo in (x, y).
    #[inline(never)]
    pub fn text(&mut self, x: i32, y: i32, s: &[u8], color: u8, sh: u32) {
        let base = self.tiles(s, color);
        let o = self.text_obj(x, y, base, s.len(), sh);
        self.push(&o);
    }

    /// Oggetto di un'immagine della ROM grafica (1 bit: colore `c`; più bit: base della tavolozza).
    #[inline(always)]
    pub fn img_obj(&self, x: i32, y: i32, img: &Img, c: u8) -> Obj {
        let mut o = Obj::new(Kind::Img, x, y, img.w as i32, img.h as i32);
        o.base = img.base as u32;
        o.ssh = img.stride_sh as u32;
        o.bpp = img.bpp_sh as u32;
        o.ca = c;
        o.class = self.class;
        o
    }

    #[inline(never)]
    pub fn img(&mut self, x: i32, y: i32, img: &Img, c: u8) {
        let o = self.img_obj(x, y, img, c);
        self.push(&o);
    }

    /// I registri, per quello che non è un oggetto (oscilloscopi, rete di OMEGA, immagine scrivibile).
    pub fn port(&mut self) -> &mut dyn Port {
        &mut *self.p
    }

    /// Fine del frame: numero di oggetti, richiesta di scambio e griglia (con il colore dell'impulso).
    pub fn finish(self) {
        if let Some(rgb) = self.grid {
            self.p.write(map::GRID_RGB, rgb);
        }
        self.p.write(map::CTRL, self.n | 1 << 8 | u32::from(self.grid.is_some()) << 9);
    }
}
