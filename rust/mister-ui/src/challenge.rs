//! Schermate della scalata di NEXT (come il vecchio `challenge_render.v`): livello superato,
//! continue, iniziali, classifica, nuovo sfidante, e in partita i punti arcade e "n WINS".
//!
//! Nel renderer di prima le celle del font (`put`, `digits7`) si decidevano per ultime e stavano sopra
//! a tutto il resto della schermata: qui si disegnano dopo le altre cose.

use crate::assets::{IMG_CHALLENGER, IMG_SCORE};
use crate::dl::{CLASS_A, Dl, code, letters, text_w};
use crate::pal::{ACCENT, BAND, BLACK, DIM, GRAY, TL, TL_HI, TRAIL1, TRAIL2, TRAIL3, WHITE};
use crate::regs::{self, Regs, field};

const W: i32 = 320;
const C: i32 = 8;
const GAME_OVER_Y: i32 = 112;

/// Stato della scalata dai registri.
pub struct Ch {
    pub level: u32,
    pub kind: u32,
    pub loadout: u32,
    pub side: bool,
    pub active: bool,
    pub duel: bool,
    pub train: bool,
    pub perfect: bool,
    pub cont_over: bool,
    pub cont_digit: u32,
    pub cont_sub: i32,
    pub score: u32,
    pub mult: u32,
    pub best: u32,
    pub highlight: u32,
    pub name: u32,
    pub pos: u32,
    pub letter: u32,
    pub points: u32,
    pub wins: u32,
    pub wins_intro: bool,
    pub wins_over: bool,
    pub duel_w: bool,
    pub roll: u32,
}

impl Ch {
    pub fn new(r: &Regs) -> Self {
        let w = &r.w;
        Self {
            level: field(w[2], 0, 3),
            kind: field(w[2], 3, 3),
            loadout: field(w[2], 6, 9),
            side: field(w[2], 15, 1) != 0,
            active: field(w[2], 16, 1) != 0,
            duel: field(w[2], 17, 1) != 0,
            train: field(w[2], 18, 1) != 0,
            perfect: field(w[2], 19, 1) != 0,
            cont_over: field(w[2], 20, 1) != 0,
            cont_digit: field(w[2], 21, 4),
            cont_sub: field(w[2], 25, 6) as i32,
            score: field(w[3], 0, 24),
            mult: field(w[3], 24, 4),
            best: field(w[4], 0, 24),
            highlight: field(w[4], 24, 4),
            name: field(w[5], 0, 18),
            pos: field(w[5], 18, 2),
            letter: field(w[5], 20, 6),
            points: field(w[5], 26, 5),
            wins: field(w[6], 0, 8),
            wins_intro: field(w[6], 8, 1) != 0,
            wins_over: field(w[6], 9, 1) != 0,
            duel_w: field(w[6], 10, 1) != 0,
            roll: field(w[6], 12, 4),
        }
    }
}

/// Cifre (codici del font) di un numero a 7 cifre in BCD, dalla più a sinistra.
#[inline(never)]
fn bcd7(v: u32) -> [u8; 7] {
    core::array::from_fn(|i| ((v >> (4 * (6 - i))) & 15) as u8)
}

/// Lo stesso numero da binario (come bin_to_bcd di prima: 7 cifre).
#[inline(never)]
fn dec7(v: u32) -> [u8; 7] {
    let mut d = [0u8; 7];
    let mut n = v;
    for k in (0..7).rev() {
        d[k] = (n % 10) as u8;
        n /= 10;
    }
    d
}

#[inline(never)]
fn centered(d: &mut Dl, s: &[u8], y: i32, c: u8) {
    d.text((W - text_w(s)) / 2, y, s, c, 0);
}

/// Sette cifre (codici) in un colore.
#[inline(never)]
fn digits(d: &mut Dl, x: i32, y: i32, v: [u8; 7], c: u8) {
    let cells: [(u8, u8); 7] = core::array::from_fn(|i| (v[i], c));
    d.cells(x, y, &cells);
}

/// Rettangolo pieno nelle coordinate di in_box (anche fuori schermo).
#[inline(never)]
fn bx(d: &mut Dl, x: i32, y: i32, w: i32, h: i32, c: u8) {
    d.rect(x, y, w, h, c);
}

#[inline(never)]
pub fn intro_age(r: &Regs) -> i32 {
    r.frame.min(255)
}

/// Schermate a tutto schermo della scalata (tranne la presentazione).
#[inline(never)]
pub fn screen(r: &Regs, d: &mut Dl) {
    let ch = Ch::new(r);
    let age = intro_age(r);
    let coin = !r.free_play && r.credits == 0;
    d.class = CLASS_A;
    d.rect(0, 0, W, 240, BLACK);
    match r.mode {
        regs::M_CLEAR => {
            let lv = ch.level as u8;
            if ch.level == 7 {
                omega_clear(d, &ch);
                return;
            }
            if ch.level == 6 {
                centered(d, b"CHAMPION!", 44, ACCENT);
                centered(d, b"YOU BEAT EVERY PADDLE", 72, WHITE);
            } else {
                let s = [
                    b'L',
                    b'E',
                    b'V',
                    b'E',
                    b'L',
                    b' ',
                    b'1' + lv,
                    b' ',
                    b'C',
                    b'L',
                    b'E',
                    b'A',
                    b'R',
                ];
                centered(d, &s, 44, ACCENT);
            }
            d.text(80, 100, b"WIN BONUS", WHITE, 0);
            if ch.perfect {
                d.text(80, 120, b"PERFECT", ACCENT, 0);
            }
            d.text(80, 150, b"SCORE", WHITE, 0);
            centered(d, b"PRESS START", 200, GRAY);
            // celle: +n000, +[1]n000, punti
            d.cells(
                176,
                100,
                &[(code(b'+'), WHITE), (lv + 1, WHITE), (0, WHITE), (0, WHITE), (0, WHITE)],
            );
            if ch.perfect {
                let p = 2 * lv + 2;
                if ch.level >= 4 {
                    d.cells(
                        176,
                        120,
                        &[
                            (code(b'+'), ACCENT),
                            (1, ACCENT),
                            (p - 10, ACCENT),
                            (0, ACCENT),
                            (0, ACCENT),
                            (0, ACCENT),
                        ],
                    );
                } else {
                    d.cells(
                        176,
                        120,
                        &[(code(b'+'), ACCENT), (p, ACCENT), (0, ACCENT), (0, ACCENT), (0, ACCENT)],
                    );
                }
            }
            digits(d, 184, 150, dec7(ch.score), WHITE);
        }
        regs::M_CONT => {
            if ch.cont_over {
                game_over_close(d, age);
            } else {
                centered(d, b"CONTINUE?", 40, ACCENT);
                // la cifra con il font dei punteggi a scala 2
                let mut o = d.img_obj(149, 84, &IMG_SCORE[ch.cont_digit as usize % 10], WHITE);
                o.w = 44;
                o.h = 44;
                o.sx = 1;
                o.sy = 1;
                d.push(&o);
                // pallina che rimbalza: tocca terra a ogni secondo; gialla negli ultimi tre
                let m = ch.cont_sub * (60 - ch.cont_sub);
                let by = 84 + 44 - 6 - ((m * 17) >> 9);
                bx(
                    d,
                    160 + 11 + 12,
                    by,
                    6,
                    6,
                    if ch.cont_digit <= 2 { ACCENT } else { WHITE },
                );
                bx(d, 160 + 11 + 9, 128, 12, 1, GRAY);
                if r.blink < 30 {
                    centered(d, if coin { b"INSERT COIN" } else { b"PRESS START" }, 160, WHITE);
                }
                centered(d, b"SCORE RESETS TO 0", 190, GRAY);
                // crediti rimasti, come nel titolo (non in Free Play)
                if !r.free_play {
                    let s = [b'C', b'R', b'E', b'D', b'I', b'T', b' ', b'0' + r.credits as u8];
                    centered(d, &s, 214, WHITE);
                }
            }
        }
        regs::M_INITIALS => {
            centered(d, b"NEW RECORD!", 28, ACCENT);
            d.text((W - 13 * C) / 2, 66, b"SCORE", WHITE, 0);
            centered(d, b"ENTER YOUR INITIALS", 92, GRAY);
            centered(d, b"UP DOWN TO CHOOSE, A TO CONFIRM", 210, GRAY);
            digits(d, (W - 13 * C) / 2 + 6 * C, 66, dec7(ch.best), WHITE);
            for i in 0..3u32 {
                let x = 160 - C / 2 + 16 * (i as i32 - 1);
                if i < ch.pos {
                    d.cells(x, 120, &[(field(ch.name, 6 * i, 6) as u8, WHITE)]);
                } else if i == ch.pos {
                    if r.blink < 40 {
                        d.cells(x, 120, &[(ch.letter as u8, ACCENT)]);
                    }
                } else {
                    d.cells(x, 120, &[(code(b'.'), WHITE)]);
                }
            }
        }
        regs::M_SCORES => scores(r, &ch, age, coin, d),
        regs::M_CHALLENGER => {
            d.rect(0, 96, W, 48, BAND);
            d.rect(0, 96, W, 1, ACCENT);
            d.rect(0, 143, W, 1, ACCENT);
            let hi = r.blink & 8 == 0;
            let x = (W - IMG_CHALLENGER.w as i32) / 2;
            let y = 96 + (48 - IMG_CHALLENGER.h as i32) / 2;
            d.img(x, y, &IMG_CHALLENGER, if hi { TL_HI } else { TL });
        }
        _ => {}
    }
    wins(&ch, d);
}

/// GAME OVER del continue scaduto: si scrive con il cursore, poi lo schermo si chiude come un
/// televisore (intro_age conta i frame del GAME OVER).
#[inline(never)]
fn game_over_close(d: &mut Dl, age: i32) {
    let s = b"GAME OVER";
    let mut l1 = [0i32; 16];
    let n = letters(s, None, Some(&mut l1)) as i32;
    let x0 = (W - (text_w(s) << 1)) / 2;
    let go_n = if age < 12 {
        0
    } else if age - 12 >= 40 {
        n
    } else {
        (((age - 12) * 13) >> 6) + 1
    };
    let cols = if go_n == 0 { 0 } else { l1[go_n as usize - 1] };
    let mut o = d.text_obj(x0, GAME_OVER_Y, 0, 0, 1);
    o.base = d.tiles(s, WHITE);
    o.w = (8 * s.len() as i32) << 1;
    let o = o.clip(0, x0 + (cols << 1), 0, 240);
    d.push(&o);
    if age >= 12 && (go_n < n || age & 16 != 0) {
        d.rect(x0 + (cols << 1) + 2, GAME_OVER_Y, 8, 14, WHITE);
    }
    if age >= 158 {
        let a7 = age & 127;
        if age >= 180 {
            d.rect(0, 0, W, 240, BLACK);
        } else if age >= 174 {
            d.rect(0, 0, W, 240, BLACK);
            d.rect(159, 119, 2, 2, WHITE);
        } else if age >= 166 {
            let w = if age >= 173 { 1 } else { (127 - 16 * (a7 - 38)) & 127 };
            d.rect(0, 0, W, 240, BLACK);
            d.rect(160 - w, 119, 2 * w, 2, WHITE);
        } else {
            let h = if age >= 165 { 1 } else { (120 - 15 * (a7 - 30)) & 127 };
            d.rect(0, 0, W, 120 - h, BLACK);
            d.rect(0, 120 + h, W, 240, BLACK);
            d.rect(0, 120 - h, W, 1, WHITE);
            d.rect(0, 119 + h, W, 1, WHITE);
        }
    }
}

/// Classifica animata: la palla scende rimbalzando e accende le righe, le cifre girano e si fermano
/// da sinistra; poi le racchette ai lati del posto nuovo e il riflesso sulle sue lettere.
#[inline(never)]
fn scores(r: &Regs, ch: &Ch, age: i32, coin: bool, d: &mut Dl) {
    const TB_X: i32 = (W - 183) / 2;
    const TB_Y0: i32 = 40;
    const TB_STEP: i32 = 20;
    const SC_MARK: i32 = 190;
    const SC_DONE: i32 = 8 + 7 * 6;
    let ball_y = |f: i32| 30 + f + (f >> 2);
    let ball_x = |f: i32| {
        let p = (f & 127) << 2;
        32 + if p & 256 != 0 { !p & 255 } else { p & 255 }
    };
    let hl = ch.highlight;
    let hl_row = if hl >= 8 { 7 } else { hl as i32 };
    centered(d, b"HIGH SCORES", 14, ACCENT);
    if ball_y(age) < 206 {
        for sk in (0..4).rev() {
            let k = if age >= 2 * sk { age - 2 * sk } else { 0 };
            let c = [WHITE, TRAIL1, TRAIL2, TRAIL3][sk as usize];
            d.rect(ball_x(k), ball_y(k), 4, 4, c);
        }
    }
    if hl < 10 && age >= SC_MARK {
        let k = age - SC_MARK;
        let pl = (3 * k - 4).min(TB_X - 14);
        let pr = (320 - 3 * k).max(TB_X + 183 + 10);
        let y = TB_Y0 - 4 + TB_STEP * hl_row;
        d.rect(pl, y, 4, 15, ACCENT);
        d.rect(pr, y, 4, 15, ACCENT);
    }
    if ball_y(age) >= 206 && r.blink < 30 {
        centered(d, if coin { b"INSERT COIN" } else { b"PRESS START" }, 226, GRAY);
    }
    for row in 0..8 {
        let ri = if row == 7 && (hl == 8 || hl == 9) {
            hl as usize
        } else {
            row as usize
        };
        let row_y = TB_Y0 + TB_STEP * row;
        let lit = ball_y(age) - row_y - 3;
        let rc = if lit < 0 {
            DIM
        } else if lit < SC_DONE {
            GRAY
        } else if hl as usize == ri {
            ACCENT
        } else {
            WHITE
        };
        let lc = if lit < 0 {
            DIM
        } else if lit < SC_DONE {
            GRAY
        } else if hl as usize == ri {
            ACCENT
        } else {
            GRAY
        };
        let name = field(r.w[8 + 2 * ri], 0, 18);
        let level = field(r.w[8 + 2 * ri], 18, 4);
        let bcd = bcd7(r.w[9 + 2 * ri] & 0x0FFF_FFFF);
        let sp = code(b' ');
        // una riga di 24 celle da TB_X: posto (2), iniziali (da 4), punti (da 10), livello (da 20: ALL
        // per la scala finita, ALL+ con OMEGA battuto)
        let mut cells = [(sp, rc); 24];
        if ri == 9 {
            cells[0] = (1, rc);
            cells[1] = (0, rc);
        } else {
            cells[1] = (ri as u8 + 1, rc);
        }
        for j in 0..3 {
            cells[4 + j] = (field(name, 6 * j as u32, 6) as u8, rc);
        }
        for j in 0..7 {
            let mut t = ch.roll as i32 + 3 * j as i32;
            t = if t >= 20 {
                t - 20
            } else if t >= 10 {
                t - 10
            } else {
                t
            };
            let v = if lit < 0 {
                0
            } else if lit >= 8 + 6 * j as i32 {
                bcd[j]
            } else {
                t as u8
            };
            cells[10 + j] = (v, rc);
        }
        if level > 7 {
            cells[20] = (10, lc);
            cells[21] = (21, lc);
            cells[22] = (21, lc);
            if level > 8 {
                cells[23] = (code(b'+'), lc);
            }
        } else {
            cells[20] = (21, lc);
            cells[21] = (code(b'V'), lc);
            cells[22] = (level as u8, lc);
        }
        let base = d.codes(&cells);
        let o = d.text_obj(TB_X, row_y, base, 24, 0);
        d.push(&o);
        // riflesso: banda in diagonale larga 12 (x - riga in [s, s + 12)) sulle lettere del posto nuovo
        if hl as usize == ri && age >= SC_MARK + 20 && r.blink < 30 {
            let wb: [(u8, u8); 24] = core::array::from_fn(|k| (cells[k].0, WHITE));
            let base = d.codes(&wb);
            let s = TB_X - 20 + (r.blink << 3);
            for dy in 0..8 {
                let o = d
                    .text_obj(TB_X, row_y, base, 24, 0)
                    .clip(s + dy, s + dy + 12, row_y + dy, row_y + dy + 1);
                d.push(&o);
            }
        }
    }
}

/// Punti arcade in partita: in basso dalla parte dell'avversario.
#[inline(never)]
pub fn hud(r: &Regs, d: &mut Dl) {
    let ch = Ch::new(r);
    d.class = CLASS_A;
    if ch.active && !ch.duel && !ch.train && (r.mode == regs::M_GAME || r.mode == regs::M_GAME_OVER) {
        let x = if ch.side { W - 200 - (13 * C - 1) } else { 200 };
        let sp = code(b' ');
        let s = dec7(ch.score);
        let mut cells = [(sp, GRAY); 13];
        cells[0] = (21, GRAY);
        cells[1] = (ch.level as u8 + 1, GRAY);
        for j in 0..7 {
            cells[3 + j] = (s[j], GRAY);
        }
        if ch.mult > 1 {
            cells[11] = (39, ACCENT);
            cells[12] = (ch.mult as u8, ACCENT);
        }
        d.cells(x, 228, &cells);
    }
    wins(&ch, d);
}

/// "n WINS" in giallo: piccolo in alto nella presentazione, in basso alla fine del duello.
#[inline(never)]
pub fn wins(ch: &Ch, d: &mut Dl) {
    if !(ch.wins_intro || ch.wins_over) {
        return;
    }
    let big = ch.wins_over;
    let right = if ch.wins_over { ch.duel_w } else { ch.side };
    let tens = (ch.wins >> 4) as u8;
    let x = (if big {
        if right { 256 } else { 64 }
    } else if right {
        240
    } else {
        80
    }) - if tens != 0 { 28 } else { 32 };
    let y = if big { 226 } else { 2 };
    let sp = code(b' ');
    let cells = [
        (if tens != 0 { tens } else { sp }, ACCENT),
        ((ch.wins & 15) as u8, ACCENT),
        (sp, ACCENT),
        (32, ACCENT),
        (18, ACCENT),
        (23, ACCENT),
        (28, ACCENT),
    ];
    d.cells(x, y, &cells);
}

/// OMEGA battuto (Clear di challenge_ui.rs): OMEGA CLEAR!, i premi di Score::omega_bonus (50.000 e,
/// senza punti di OMEGA, 16.000 della partita perfetta come un ottavo livello) e il punteggio.
#[inline(never)]
fn omega_clear(d: &mut Dl, ch: &Ch) {
    centered(d, b"OMEGA CLEAR!", 44, ACCENT);
    centered(d, b"YOU BEAT THEM ALL", 72, WHITE);
    d.text(80, 100, b"WIN BONUS", WHITE, 0);
    d.cells(
        168,
        100,
        &[
            (code(b'+'), WHITE),
            (5, WHITE),
            (0, WHITE),
            (0, WHITE),
            (0, WHITE),
            (0, WHITE),
        ],
    );
    if ch.perfect {
        d.text(80, 120, b"PERFECT", ACCENT, 0);
        d.cells(
            168,
            120,
            &[
                (code(b'+'), ACCENT),
                (1, ACCENT),
                (6, ACCENT),
                (0, ACCENT),
                (0, ACCENT),
                (0, ACCENT),
            ],
        );
    }
    d.text(80, 150, b"SCORE", WHITE, 0);
    digits(d, 184, 150, dec7(ch.score), WHITE);
    centered(d, b"PRESS START", 200, GRAY);
}
