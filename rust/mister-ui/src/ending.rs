//! Finale della scalata (come il vecchio ending_render.v): le scritte sono righe di bitmap scelte riga
//! per riga dalla mappa (tabella delle righe), le cifre del punteggio celle della striscia delle cifre;
//! la sfilata ha i ritratti medi dei personaggi (normali e sconfitti) e i timbri DEFEATED (inclinati,
//! già ruotati nella ROM). I tempi (parti, conteggi, scorrimento
//! dei titoli) e i fuochi d'artificio
//! restano in hardware (ending_render): qui arrivano dai registri.

use crate::assets::ending as e;
use crate::assets::game::KIND_NAMES;
use crate::assets::portraits;
use crate::cast::{OMEGA, centered, portrait};
use crate::dl::{CLASS_A, Dl, Kind, Obj, text_w};
use crate::pal::{GRAY, OMEGA_Q, RED, WHITE, YELLOW};
use crate::regs::{Omega, Regs, field};

const P_PARADE: u32 = 1;
const P_CREDITS: u32 = 4;
const P_THE_END: u32 = 5;
/// tipi della scala nell'ordine dei livelli (PaddleKind)
const LADDER: [usize; 7] = [0, 3, 2, 1, 4, 5, 6];

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
    let beats = field(w, 14, 5) as i32;
    let stage = field(w, 19, 2);
    let fl = field(w, 21, 1) != 0;
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
    // ---- sfilata (draw_parade di ending_ui.rs): otto posti nell'ordine della scala, due file da
    // quattro ritratti medi; ognuno entra normale e al timbro passa all'immagine sconfitta, con il nome
    // grigio. L'ultimo è OMEGA: svelato se è stato battuto, se no la sua sagoma con il punto di
    // domanda, senza timbro
    let entered = (beats + 1) >> 1;
    let stamped = beats >> 1;
    let mut lt = [0i32; e::STAMP_H as usize];
    for (v, l) in lt.iter_mut().enumerate() {
        *l = 10 * (e::STAMP_ROW0 + v as i32);
    }
    let lt = d.lines(&lt);
    for i in 0..entered.min(8) {
        let k = if i < 7 { LADDER[i as usize] } else { OMEGA };
        let x = e::PARADE_X0 + e::PARADE_DX * (i % 4);
        let (y, ny) = if i < 4 {
            (e::PARADE_ROW0, e::PARADE_NAME0)
        } else {
            (e::PARADE_ROW1, e::PARADE_NAME1)
        };
        let cx = x + e::PARADE_W / 2;
        if k == OMEGA && !om.won {
            portrait(d, &portraits::MID_LOCKED, OMEGA, x, y);
            centered(d, b"?", cx, ny, OMEGA_Q);
            continue;
        }
        let ko = i < stamped;
        portrait(d, &portraits::MID[k][ko as usize], k, x, y);
        let name: &[u8] = if k == OMEGA { b"OMEGA" } else { KIND_NAMES[k] };
        centered(d, name, cx, ny, if ko { GRAY } else { WHITE });
        if ko {
            let cy = y + e::PARADE_H - e::PARADE_STAMP_UP;
            let mut o = Obj::new(Kind::Img, cx - e::STAMP_W / 2, cy - e::STAMP_H / 2, e::STAMP_W, e::STAMP_H);
            o.base = e::TEXT_BASE;
            o.lt = Some(lt);
            o.ltrow = true;
            o.ca = RED;
            o.class = d.class;
            d.push(&o);
        }
    }
}
