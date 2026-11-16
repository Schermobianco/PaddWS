//! Finale della scalata (come il vecchio ending_render.v più la sfilata di next_render.v): le scritte
//! sono righe di bitmap scelte riga per riga dalla mappa (tabella delle righe), le cifre del
//! punteggio celle della striscia delle cifre, i timbri DEFEATED (inclinati, già ruotati nella ROM,
//! sfalsati in altezza) e le racchette della sfilata oggetti. I tempi (parti, conteggi, scorrimento
//! dei titoli) e i fuochi d'artificio
//! restano in hardware (ending_render): qui arrivano dai registri.

use crate::assets::ending as e;
use crate::assets::game::{BLASTER_SHOTS, KIND_H, KIND_NAMES, PW};
use crate::dl::{CLASS_A, Dl, Kind, Obj, text_w};
use crate::paddle::{Colors, Pad};
use crate::pal::{ACCENT, NDIM, RED, WHITE, YELLOW};
use crate::regs::{Omega, Regs, field};

const P_PARADE: u32 = 1;
const P_CREDITS: u32 = 4;
const P_THE_END: u32 = 5;
const COLS: [i32; 7] = [e::COL0, e::COL1, e::COL2, e::COL3, e::COL4, e::COL5, e::COL6];

/// Parola della mappa della riga y nella parte in corso (0 = riga vuota).
fn entry(part: u32, y: i32, scroll: i32) -> u32 {
    let (top, h, base) = match part {
        0 => (e::WIN0_TOP, e::WIN0_H, e::WIN0_BASE),
        1 => (e::WIN1_TOP, e::WIN1_H, e::WIN1_BASE),
        2 => (e::WIN2_TOP, e::WIN2_H, e::WIN2_BASE),
        3 => (e::WIN3_TOP, e::WIN3_H, e::WIN3_BASE),
        P_CREDITS => {
            let c = (y + scroll - e::CRED_C0) & 2047;
            return if c < e::CRED_LEN {
                e::MAP[(e::CRED_BASE + c) as usize]
            } else {
                0
            };
        }
        _ => (e::WIN5_TOP, e::WIN5_H, e::WIN5_BASE),
    };
    let d = (y - top) & 511;
    if d < h { e::MAP[(base + d) as usize] } else { 0 }
}

fn dec7(v: u32) -> [u8; 7] {
    let mut d = [0u8; 7];
    let mut n = v;
    for k in (0..7).rev() {
        d[k] = (n % 10) as u8;
        n /= 10;
    }
    d
}

pub fn draw(r: &Regs, om: &Omega, d: &mut Dl) {
    let w = r.w[41];
    let part = field(w, 11, 3);
    let beats = field(w, 14, 4) as i32;
    let stage = field(w, 18, 2);
    let fl = field(w, 20, 1) != 0;
    let disp = [
        r.w[42] & 0xFF_FFFF,
        r.w[43] & 0xFF_FFFF,
        (r.w[38].wrapping_add(r.w[39])) & 0xFF_FFFF,
    ];
    let scroll = (r.w[44] & 1023) as i32;
    d.class = CLASS_A;

    // ---- scritte e cifre: righe consecutive con la stessa voce (tranne la riga) diventano un oggetto
    let mut rows = [0i32; 240];
    let mut glyph = [0i32; 240];
    let mut y = 0;
    while y < 240 {
        let ent = entry(part, y, scroll);
        let scale = field(ent, 22, 2);
        let group = field(ent, 26, 2);
        if scale == 0 || group > stage {
            y += 1;
            continue;
        }
        let key = ent & !0x1FFF; // tutto tranne riga e riga del glifo
        let y0 = y;
        let mut n = 0;
        while y < 240 {
            let en = entry(part, y, scroll);
            if en & !0x1FFF != key {
                break;
            }
            rows[n] = 10 * field(en, 0, 9) as i32;
            glyph[n] = 10 * (e::STRIP_ROW0 + field(en, 9, 4) as i32);
            n += 1;
            y += 1;
        }
        let sh = if scale == 2 { 1 } else { 0 };
        let ex = field(ent, 13, 9) as i32;
        let color = match field(ent, 24, 2) {
            0 => WHITE,
            1 => YELLOW,
            2 => RED,
            _ => {
                if fl {
                    WHITE
                } else {
                    YELLOW
                }
            }
        };
        let num = field(ent, 28, 2);
        // la scritta (nelle righe del punteggio solo prima delle cifre)
        let lt = d.lines(&rows[..n]);
        let mut o = Obj::new(Kind::Img, ex, y0, 320 << sh, n as i32);
        o.base = e::TEXT_BASE;
        o.lt = Some(lt);
        o.ltrow = true;
        o.sx = sh;
        o.ca = color;
        o.class = d.class;
        let o = if num != 0 { o.clip(0, e::DIG_X0, 0, 240) } else { o };
        d.push(&o);
        if num != 0 {
            // sette celle di cifre (il premio con il "+" davanti)
            let digits = dec7(disp[num as usize - 1]);
            let lt = d.lines(&glyph[..n]);
            for (j, dv) in digits.iter().enumerate() {
                let dv = if num == 2 && j == 0 { 10 } else { *dv as i32 };
                let mut o = Obj::new(
                    Kind::Img,
                    e::DIG_X0 + ((j as i32 * e::CELL) << sh),
                    y0,
                    e::CELL << sh,
                    n as i32,
                );
                o.base = e::TEXT_BASE;
                o.lt = Some(lt);
                o.ltrow = true;
                o.sx = sh;
                o.u0 = dv * e::CELL;
                o.ca = color;
                o.class = d.class;
                d.push(&o);
            }
        }
    }

    // dopo OMEGA battuto: OMEGA DEFEATED in rosso sotto THE END (ending_ui.rs, 40 righe sotto a 480)
    if part == P_THE_END && om.won {
        let t = b"OMEGA DEFEATED";
        d.text((320 - text_w(t)) / 2, e::WIN5_TOP + 20, t, RED, 0);
    }
    if part != P_PARADE {
        return;
    }
    // ---- sfilata: le racchette (una per colonna, rivolte a destra) e i nomi sotto, su due righe
    let parade_n = (beats + 1) >> 1;
    let parade_ko = beats >> 1;
    let mid = |k: usize| (COLS[k] + COLS[k + 1]) / 2;
    for k in 0..7usize {
        if k as i32 >= parade_n {
            continue;
        }
        let x0 = if k == 0 { 0 } else { mid(k - 1) };
        let x1 = if k == 6 { 320 } else { mid(k) };
        let ko = (k as i32) < parade_ko;
        let (lit, acc) = if ko { (NDIM, NDIM) } else { (WHITE, ACCENT) };
        let h = KIND_H[k];
        let top = e::PARADE_Y - (h >> 1);
        let pad = Pad {
            kind: k as u32,
            xa: COLS[k] - PW / 2,
            xb: COLS[k] - PW / 2 + PW - 1,
            right: true,
            y: top,
            h,
            tilt: if k == 3 { 3 } else { 0 },
            preview: true,
            ghosts: true,
            half: false,
        };
        let colors = Colors {
            body: lit,
            mark: acc,
            detail: acc,
            ghost: [acc, acc, acc],
            pattern: true,
        };
        let old = d.clip;
        d.clip = [x0, x1, 0, 240];
        pad.draw(d, &colors);
        if k == 4 {
            // BLASTER: il caricatore pieno dietro la racchetta, dal basso
            for j in 0..BLASTER_SHOTS {
                d.rect(COLS[k] - PW / 2 - 4, top + h - 4 - 4 * j, 2, 3, acc);
            }
        }
        d.clip = old;
    }
    for k in 0..7usize {
        if k as i32 >= parade_n {
            continue;
        }
        let odd = k & 1 == 1;
        let name = KIND_NAMES[k];
        let ny = e::PARADE_NAME_Y - 4 + if odd { e::PARADE_NAME_DY } else { 0 };
        let row_y = e::PARADE_NAME_Y - 4 + e::PARADE_NAME_DY;
        // colonne dei nomi della stessa riga: i confini sono a metà fra due nomi della riga
        let (x0, x1) = if odd {
            match k {
                1 => (0, (COLS[1] + COLS[3]) / 2),
                3 => ((COLS[1] + COLS[3]) / 2, (COLS[3] + COLS[5]) / 2),
                _ => ((COLS[3] + COLS[5]) / 2, 320),
            }
        } else {
            match k {
                0 => (0, (COLS[0] + COLS[2]) / 2),
                2 => ((COLS[0] + COLS[2]) / 2, (COLS[2] + COLS[4]) / 2),
                4 => ((COLS[2] + COLS[4]) / 2, (COLS[4] + COLS[6]) / 2),
                _ => ((COLS[4] + COLS[6]) / 2, 320),
            }
        };
        let (y0, y1) = if odd { (row_y, 240) } else { (0, row_y) };
        let base = d.tiles(name, WHITE);
        let o = d
            .text_obj(COLS[k] - text_w(name) / 2, ny, base, name.len(), 0)
            .clip(x0, x1, y0, y1);
        d.push(&o);
    }
    // timbri DEFEATED sulle racchette battute: pari più su, dispari più giù (i vicini non si toccano)
    let mut lt = [0i32; 64];
    for (v, l) in lt.iter_mut().enumerate().take(e::STAMP_H as usize) {
        *l = 10 * (e::STAMP_ROW0 + v as i32);
    }
    let lt = d.lines(&lt[..e::STAMP_H as usize]);
    for (k, col) in COLS.iter().enumerate() {
        if (k as i32) < beats >> 1 {
            let dy = if k % 2 == 0 {
                -e::STAMP_STAGGER
            } else {
                e::STAMP_STAGGER
            };
            let mut o = Obj::new(
                Kind::Img,
                col - 1 - e::STAMP_W / 2,
                e::STAMP_Y0 + dy,
                e::STAMP_W,
                e::STAMP_H,
            );
            o.base = e::TEXT_BASE;
            o.lt = Some(lt);
            o.ltrow = true;
            o.ca = RED;
            o.class = d.class;
            d.push(&o);
        }
    }
}
