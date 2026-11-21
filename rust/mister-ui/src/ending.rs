//! Finale della scalata (come il vecchio ending_render.v): le scritte sono righe di bitmap scelte riga
//! per riga dalla mappa (tabella delle righe), le cifre del punteggio celle della striscia delle cifre;
//! la sfilata ha i ritratti medi dei personaggi (normali e sconfitti) e i timbri DEFEATED (inclinati,
//! già ruotati nella ROM). I tempi (parti, conteggi, scorrimento
//! dei titoli) e i fuochi d'artificio
//! restano in hardware (ending_render): qui arrivano dai registri.

use crate::assets::ending as e;
use crate::assets::game::{KIND_H, KIND_NAMES, SIN_Q8};
use crate::assets::{portraits, ships};
use crate::cast::{OMEGA, centered, paddle_warp, portrait};
use crate::dl::{CLASS_A, Dl, Kind, Obj, text_w};
use crate::pal::{CYAN, GRAY, OMEGA_Q, PADS, RED, SHIP, WHITE, YELLOW};
use crate::regs::{Omega, Regs, field};

const P_PARADE: u32 = 1;
const P_CHAMPION: u32 = 3;
const P_CREDITS: u32 = 4;
const P_THE_END: u32 = 5;
/// tipi della scala nell'ordine dei livelli (PaddleKind)
const LADDER: [usize; 7] = [0, 3, 2, 1, 4, 5, 6];

/// Colore del personaggio `kind` nella tavolozza delle racchette (`pal::PADS + 13 + 3 * kind`).
const fn kind_mark(kind: usize) -> u8 {
    PADS + 13 + 3 * kind as u8
}

/// Lampo iperspaziale centrato in `(cx, cy)` con progresso `num / den` in `(0, 1)`.
#[inline(never)]
fn warp_flash(d: &mut Dl, cx: i32, cy: i32, num: i32, den: i32, mark: u8) {
    if num <= 0 || num >= den {
        return;
    }
    // inviluppo triangolare morbido (0 -> 256 -> 0)
    let env = if num * 2 <= den {
        num * 512 / den
    } else {
        (den - num) * 512 / den
    };
    let w = 14 + (env * 124) / 256;
    let h = ((env * 5) / 256).max(1);
    d.rect(cx - w / 2, cy - h / 2 - 1, w, h + 2, CYAN);
    let iw = (w * 4) / 5;
    d.rect(cx - iw / 2, cy - h / 2, iw, h, WHITE);
    let vh = (env * 28) / 256;
    if vh > 0 {
        d.rect(cx - 1, cy - vh / 2, 3, vh, mark);
        let ivh = (vh * 4) / 5;
        d.rect(cx, cy - ivh / 2, 1, ivh.max(1), WHITE);
    }
}

/// Salto Warp dell'astronave vincitrice durante `P_CHAMPION` (`pf = 0..419` a 60 Hz):
/// linee velocità durante carica e scatto, entrata da lampo a sinistra, crociera e carica al
/// centro, scatto iperspaziale con allungamento hardware (`sx = 1, 2`) e lampo verso destra.
#[inline(never)]
fn draw_champion_warp(d: &mut Dl, pf: i32, winner: usize) {
    let mark = kind_mark(winner);
    // linee velocità orizzontali: carica (132..207) e scatto (207..288)
    let inten = if (132..207).contains(&pf) {
        (pf - 132) * 166 / 75
    } else if (207..288).contains(&pf) {
        (288 - pf) * 256 / 81
    } else {
        0
    };
    if inten > 4 {
        let count = (18 * inten / 256).max(1);
        for i in 0..count {
            let s = (i as u32).wrapping_mul(2_654_435_761);
            let y = if i % 3 == 0 {
                (92 + ((s >> 8) % 64) as i32 - 32).clamp(4, 166)
            } else {
                4 + (s % 162) as i32
            };
            let spd = 5 + ((s >> 12) % 6) as i32;
            let len = ((12 + ((s >> 16) % 40) as i32) * inten / 256).max(4);
            let phase = ((s >> 4) % 420) as i32;
            let x = 360 - (phase + pf * spd) % 420;
            let col = match i & 3 {
                0 => WHITE,
                1 => CYAN,
                2 => mark,
                _ => YELLOW,
            };
            d.rect(x, y, len, if i % 7 == 0 { 2 } else { 1 }, col);
        }
    }

    // lampo di ingresso a sinistra (0.35..0.85 s -> frame 21..51)
    if (21..51).contains(&pf) {
        warp_flash(d, 32, 92, pf - 21, 30, mark);
    }

    // astronave (0.45..4.25 s -> frame 27..255)
    if (27..255).contains(&pf) {
        let (x, y, sx, strength) = if pf < 108 {
            // decelerazione dall'iperspazio (27..108)
            let k = (pf - 27) * 256 / 81;
            let inv = 256 - k;
            let ease = 256 - ((((inv * inv) >> 8) * inv) >> 8);
            let sx = if ease < 160 { 1u32 } else { 0u32 };
            let wave = (SIN_Q8[((k >> 3) & 63) as usize] * 6) >> 8;
            (-24 + (ease * 158) / 256, 92 + wave, sx, 76 + ((256 - ease) * 180) / 256)
        } else if pf < 207 {
            // crociera trionfale + carica iperspazio (108..207)
            let k = (pf - 108) * 256 / 99;
            let jitter = if k > 140 {
                (if (pf >> 1) & 1 != 0 { 1 } else { -1 }) * ((k - 140) * 3 / 116)
            } else {
                0
            };
            let wave = (SIN_Q8[((pf * 5 / 6) & 63) as usize] * 5) >> 8;
            (134 + (k * 44) / 256 + jitter, 92 + wave, 0u32, 90 + (k * 166) / 256)
        } else {
            // SCATTO IPERSPAZIALE! (207..255)
            let k = (pf - 207) * 256 / 48;
            let k3 = (((k * k) >> 8) * k) >> 8;
            let sx = if k < 96 { 1u32 } else { 2u32 };
            (178 + (k3 * 290) / 256, 92, sx, 340)
        };

        // scia di plasma orizzontale dai motori
        let h_px = KIND_H[winner];
        let n_streaks = (6 + (8 * strength) / 256).min(14);
        let tick_seed = (pf >> 1) as u32;
        for i in 0..n_streaks {
            let s = ((i + 1) as u32)
                .wrapping_mul(1_103_515_245)
                .wrapping_add(tick_seed.wrapping_mul(12_345));
            let dy = ((((s >> 8) % 100) as i32 - 50) * h_px) / 140;
            let max_back = (22 + (64 * strength) / 256).max(8) as u32;
            let max_len = (10 + (32 * strength) / 256).max(4) as u32;
            let back = 6 + ((s >> 16) % max_back) as i32;
            let len = 4 + ((s >> 20) % max_len) as i32;
            let py = y + dy;
            if (2..168).contains(&py) {
                let col = match i % 3 {
                    0 => WHITE,
                    1 => CYAN,
                    _ => mark,
                };
                d.rect(x - back - len, py, len, if i % 5 == 0 { 2 } else { 1 }, col);
            }
        }

        // nave reale allungata in hardware + lampo bianco iniziale allo scatto
        paddle_warp(d, winner as u32, x, y, true, sx);
        if (206..=212).contains(&pf) {
            d.rect(x - 10, y - h_px / 2, 20, h_px, WHITE);
        }
    }

    // lampo di uscita verso destra (3.42..4.05 s -> frame 205..243)
    if (205..243).contains(&pf) {
        let dt = pf - 205;
        warp_flash(d, 184 + dt * 3, 92, dt, 38, mark);
    }
}

/// Illustrazione isometrica 160x90 della nave vincitrice sospesa sopra `THE END`, con stelle che
/// scorrono piano dietro.
#[inline(never)]
fn draw_the_end_ship(d: &mut Dl, pf: i32, winner: usize) {
    let mark = kind_mark(winner);
    for i in 0..16u32 {
        let s = i.wrapping_mul(2_654_435_761);
        let x0 = (s % 320) as i32;
        let y0 = ((s >> 9) % 156) as i32;
        let spd = 1 + ((s >> 17) % 3) as i32;
        let x = (x0 + (pf * spd) / 3) % 320;
        let y = (y0 - (pf * spd) / 6).rem_euclid(156);
        let col = match i % 4 {
            0 => WHITE,
            1 => CYAN,
            2 => mark,
            _ => YELLOW,
        };
        let sz = if i % 5 == 0 { 2 } else { 1 };
        d.rect(x, y + 4, sz, sz, col);
    }
    let img = &ships::ART[winner];
    let mut rows = [0i32; 90];
    for (v, row) in rows.iter_mut().enumerate() {
        *row = v as i32 * ships::ROW_WORDS;
    }
    let lt = d.lines(&rows);
    let hover = (SIN_Q8[((pf >> 1) & 63) as usize] * 2) >> 8;
    let mut o = d.img_obj((320 - img.w as i32) / 2, 36 + hover, img, SHIP);
    o.lt = Some(lt);
    o.ltrow = true;
    d.push(&o);
}

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
    let pf = field(w, 0, 11) as i32;
    let part = field(w, 11, 3);
    let beats = field(w, 14, 5) as i32;
    let stage = field(w, 19, 2);
    let fl = field(w, 21, 1) != 0;
    let winner = field(r.w[47], 9, 3).min(6) as usize;
    let disp = [
        r.w[42] & 0xFF_FFFF,
        r.w[43] & 0xFF_FFFF,
        (r.w[38].wrapping_add(r.w[39])) & 0xFF_FFFF,
    ];
    let scroll = (r.w[44] & 1023) as i32;
    d.class = CLASS_A;

    if part == P_CHAMPION {
        draw_champion_warp(d, pf, winner);
    } else if part == P_THE_END {
        draw_the_end_ship(d, pf, winner);
    }

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

    // dopo OMEGA battuto: OMEGA DEFEATED in rosso sotto THE END
    if part == P_THE_END && om.won {
        let t = b"OMEGA DEFEATED";
        d.text((320 - text_w(t)) / 2, e::WIN5_TOP + 22, t, RED, 0);
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
