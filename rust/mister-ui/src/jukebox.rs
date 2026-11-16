//! JUKEBOX (voce Jukebox dell'OSD, sbloccata battendo OMEGA o con le iniziali BAS), come
//! rust/game/src/jukebox.rs: il brano e la sua posizione, tre oscilloscopi affiancati (uno per voce
//! del SID) e lo stato. Brani, comandi e sezioni di OMEGA sono di pong_top (jb_*): qui il disegno.
//!
//! Gli oscilloscopi sono una linea continua sottile nell'immagine scrivibile del motore (map::GRAM,
//! un'immagine a 1 bit per voce), riscritta a ogni frame dagli oscilloscopi di sid_scope: una finestra
//! di 120 ms agganciata al primo passaggio per lo zero in salita (omega::trigger).

use crate::assets::game::KIND_NAMES;
use crate::dl::{CLASS_A, Dl, Kind, Obj, text_w};
use crate::map;
use crate::omega::{self, SEARCH, WINDOW};
use crate::pal::{ACCENT, BLACK, DIM, GRAY, WHITE};
use crate::regs::{Omega, Regs};

const W: i32 = 320;
/// Brani: i temi nell'ordine della scala (tipi di PaddleKind), il finale, OMEGA.
const TRACKS: u32 = 9;
const LADDER: [usize; 7] = [0, 3, 2, 1, 4, 5, 6];
/// Riquadri degli oscilloscopi: larghezza, altezza, distanza, prima riga.
const BOX_W: i32 = 92;
const BOX_H: i32 = 36;
const GAP: i32 = 10;
const BOX_Y: i32 = 95;
/// Immagine di ogni oscilloscopio dentro il riquadro: SCOPE_W x SCOPE_H a 1 bit, 4 parole per riga.
const SCOPE_W: i32 = BOX_W - 4;
const SCOPE_H: i32 = BOX_H - 4;
const ROW_WORDS: usize = 4;
const IMG_WORDS: usize = ROW_WORDS * SCOPE_H as usize;
/// Scala piena (16 bit della via diretta, musica al 100%): SCOPE_FULL di scope.rs rispetto a NET_PEAK.
const SCOPE_FULL: i32 = omega::NET_PEAK * 35 / 24;

fn track_name(t: u32, section: u32) -> ([u8; 12], usize) {
    let mut s = [b' '; 12];
    let mut n = 0;
    let mut put = |b: &[u8]| {
        for &c in b {
            if n < s.len() {
                s[n] = c;
                n += 1;
            }
        }
    };
    put(b"< ");
    match t {
        0..=6 => put(KIND_NAMES[LADDER[t as usize]]),
        7 => put(b"ENDING"),
        _ => {
            put(b"OMEGA ");
            put(&[b'1' + section as u8]);
        }
    }
    put(b" >");
    (s, n)
}

#[inline(never)]
pub fn draw(r: &Regs, o: &Omega, d: &mut Dl) {
    d.class = CLASS_A;
    d.rect(0, 0, W, 240, BLACK);
    let center = |d: &mut Dl, t: &[u8], y: i32, c: u8| d.text((W - text_w(t)) / 2, y, t, c, 0);
    center(d, b"JUKEBOX", 32, ACCENT);
    let (name, n) = track_name(o.track, o.section);
    center(d, &name[..n], 60, WHITE);
    let pos = [b'1' + o.track.min(TRACKS - 1) as u8, b'/', b'0' + TRACKS as u8];
    center(d, &pos, 75, GRAY);
    // tre oscilloscopi, uno per voce
    let gain = if o.music_off { 0 } else { omega::music_gain(o.music_vol) };
    let full = SCOPE_FULL * gain / 64;
    let mut bits = [0u32; IMG_WORDS];
    for v in 0..3 {
        let x0 = W / 2 + (v - 1) * (BOX_W + GAP) - BOX_W / 2;
        // cornice e linea dello zero
        for (x, y, w, h) in [
            (x0, BOX_Y, BOX_W, 1),
            (x0, BOX_Y + BOX_H - 1, BOX_W, 1),
            (x0, BOX_Y, 1, BOX_H),
            (x0 + BOX_W - 1, BOX_Y, 1, BOX_H),
            (x0 + 1, BOX_Y + BOX_H / 2, BOX_W - 2, 1),
        ] {
            d.rect(x, y, w, h, DIM);
        }
        for b in bits.iter_mut() {
            *b = 0;
        }
        if o.playing && full > 0 {
            let mut x = [0i32; SEARCH + WINDOW];
            omega::read_voice(d, o.scope_wptr, v as u32, true, &mut x);
            let i0 = omega::trigger(&x);
            let half = SCOPE_H / 2 - 2;
            let mut prev = -1;
            for c in 0..SCOPE_W {
                let i = (i0 + c as usize * (WINDOW - 1) / (SCOPE_W as usize - 1)).min(x.len() - 1);
                let y = (SCOPE_H / 2 - (x[i] * half / full).clamp(-half, half)).clamp(0, SCOPE_H - 1);
                // linea continua: nella colonna, dal punto di prima a questo
                let p = if prev < 0 { y } else { prev };
                for yy in p.min(y)..=p.max(y) {
                    bits[yy as usize * ROW_WORDS + (c / 32) as usize] |= 1 << (31 - (c & 31));
                }
                prev = y;
            }
        } else {
            // fermo: la linea dello zero
            for c in 0..SCOPE_W {
                bits[(SCOPE_H / 2) as usize * ROW_WORDS + (c / 32) as usize] |= 1 << (31 - (c & 31));
            }
        }
        let at = v as u32 * IMG_WORDS as u32;
        d.port().write_block(map::GRAM + at, &bits);
        let mut ob = Obj::new(Kind::Img, x0 + 2, BOX_Y + 2, SCOPE_W, SCOPE_H);
        ob.base = map::GRAM_BASE as u32 + at;
        ob.ssh = 2;
        ob.bpp = 0;
        ob.ca = ACCENT;
        ob.class = d.class;
        d.push(&ob);
        let label = [b'V', b'O', b'I', b'C', b'E', b' ', b'1' + v as u8];
        d.text(x0 + (BOX_W - text_w(&label)) / 2, BOX_Y + BOX_H + 6, &label, GRAY, 0);
    }
    let (state, c): (&[u8], u8) = if !o.playing {
        (b"STOPPED", GRAY)
    } else if o.music_off {
        (b"MUSIC VOLUME 0%", WHITE)
    } else {
        (b"PLAYING", WHITE)
    };
    center(d, state, 168, c);
    center(d, b"UP/DOWN: TRACK   A: STOP/PLAY", 200, GRAY);
    let _ = r;
}
