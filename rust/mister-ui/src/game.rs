//! Scritte sopra il campo (come la parte "top" e i punteggi del vecchio pong_render.v): punteggi, TOP,
//! BALLS, crediti e scritta della demo, conto alla rovescia, fine partita animata (GAME OVER scritto,
//! chi ha vinto, timbro e riflesso di PERFECT, palla di YOU WIN, chiusura del televisore); poi i punti
//! arcade della scalata e "n WINS" (challenge.rs).
//!
//! Classi: i punteggi e i crediti della demo stanno dentro il campo (C: sotto palla e racchette), il
//! resto sopra le aggiunte di NEXT (B). Con `upright` basso le scritte guardano i giocatori seduti ai
//! lati (ruotate di 90 gradi).

use crate::Img;
use crate::assets::{IMG_PERFECT, IMG_SCORE};
use crate::dl::{CLASS_B, CLASS_C, Dl, Kind, Obj, code, letters, text_w};
use crate::pal::{ACCENT, BLACK, GRAY, TL, TL_GLINT, WHITE};
use crate::regs::{self, Regs, field};

const W: i32 = 320;
const H: i32 = 240;
const GAME_OVER_Y: i32 = 112;
const WINNER_Y: i32 = 132;
const DEMO_LABEL_Y: i32 = 112;
const ROT_CX_L: i32 = (80 + W / 2) / 2 + 8;
const ROT_CX_R: i32 = W - ROT_CX_L;
const ROT_SHIFT: i32 = 27;
const GO_WB: i32 = 71 << 1;
const BH: i32 = 7 << 1;
const GO_BOX_X: i32 = (W - GO_WB - 12) / 2;
const PF_W: i32 = 114;
const PF_H: i32 = 25;
const PFG_X0: i32 = (W - PF_W) / 2;
const PFG_Y0: i32 = GAME_OVER_Y + BH - PF_H;
const PFS_X0: i32 = W / 2 - PF_W;
const PFS_Y0: i32 = PFG_Y0 - (PF_H + 1) / 2;
const PF_BOX_X0: i32 = PFG_X0 - 6;
const PF_BOX_X1: i32 = PFG_X0 + PF_W + 6;
const PF_BOX_Y0: i32 = PFG_Y0 - 4;
const PFR_XL: i32 = ROT_CX_L - 8;
const PFR_XR: i32 = ROT_CX_R + 8 - PF_H;
const PFR_YL: i32 = (H - PF_W) / 2 - ROT_SHIFT;
const PFR_YR: i32 = (H - PF_W) / 2 + ROT_SHIFT;
const DIM_WIN: u8 = crate::pal::WIN_DIM;

/// Stato della partita dai registri.
pub struct Game {
    pub mode: u32,
    pub two: bool,
    pub nxt: bool,
    pub demo_kind: u32,
    pub winner: u32,
    pub solo: bool,
    pub perfect: bool,
    pub you_right: bool,
    pub countdown: u32,
    pub lives: u32,
    pub gray: bool,
    pub score: [u32; 2],
    pub best: u32,
    pub pad_x: [i32; 2],
    pub pad_y: [i32; 2],
    pub pad_h: [i32; 2],
}

impl Game {
    pub fn new(r: &Regs) -> Self {
        let k = r.w[28];
        Self {
            mode: r.mode,
            two: field(k, 10, 1) != 0,
            nxt: field(k, 11, 1) != 0,
            demo_kind: field(k, 8, 2),
            winner: field(k, 12, 3),
            solo: field(k, 15, 1) != 0,
            perfect: field(k, 16, 1) != 0,
            you_right: field(k, 17, 1) != 0,
            countdown: field(k, 18, 2),
            lives: field(k, 20, 2),
            gray: field(k, 22, 1) != 0,
            score: [r.w[29] & 0xFFFF, r.w[29] >> 16],
            best: r.w[30] & 0xFFFF,
            pad_x: [r.w[31] as i32, r.w[33] as i32],
            pad_y: [r.w[32] as i32, r.w[34] as i32],
            pad_h: [r.w[35] as i32, r.w[36] as i32],
        }
    }
}

/// Decine e unità (fino a 99), come tens/ones di pong_render.
#[inline(never)]
fn tens_ones(v: u32) -> (u8, u8) {
    let c = v.min(99);
    let t = (c * 205) >> 11;
    (t as u8, (c - t * 10) as u8)
}

/// Testo dritto (caratteri da `base`) a scala 1 << sh.
#[inline(never)]
fn up_text(d: &Dl, x: i32, y: i32, base: u32, len: usize, sh: u32) -> Obj {
    d.text_obj(x, y, base, len, sh)
}

/// Scritta ruotata verso il giocatore sinistro (orario, si legge dall'alto) o destro (antiorario),
/// lunga `len` pixel (già scalati), centrata sulla colonna cx: come rot_coord di pong_render.
#[inline(never)]
fn rot_text(d: &Dl, right: bool, cx: i32, len: i32, sh: u32, base: u32, n: usize) -> Obj {
    let mut o = Obj::new(
        Kind::Text,
        cx - (4 << sh),
        ((H - len) >> 1) + if right { ROT_SHIFT } else { -ROT_SHIFT },
        8 << sh,
        len,
    );
    o.base = base;
    o.swap = true;
    o.fx = !right;
    o.fy = right;
    o.sx = sh;
    o.sy = sh;
    o.class = d.class;
    let _ = n;
    o
}

/// Riquadro nero attorno a una scritta ruotata (il lato viene dalla colonna).
#[inline(never)]
fn rot_box(cx: i32, len: i32, sh: u32) -> [i32; 4] {
    let y0 = ((H - len) >> 1) + if cx > W / 2 { ROT_SHIFT } else { -ROT_SHIFT };
    let hw = 4 << sh;
    [cx - hw - 5, cx + hw + 5, y0 - 6, y0 + len + 6]
}

#[inline(never)]
fn fill(d: &mut Dl, b: [i32; 4], c: u8) {
    d.rect(b[0], b[2], b[1] - b[0], b[3] - b[2], c);
}

/// Cifra del font dei punteggi: dritta, o ruotata (orario `cw`) come i punteggi verso i giocatori.
#[inline(never)]
fn digit(d: &Dl, x: i32, y: i32, v: u8, rot: i32, sh: u32, c: u8) -> Obj {
    let img: &Img = &IMG_SCORE[v as usize % 10];
    let mut o = d.img_obj(x, y, img, c);
    o.w = 22 << sh;
    o.h = 22 << sh;
    o.sx = sh;
    o.sy = sh;
    match rot {
        1 => {
            o.swap = true;
            o.fx = true;
        }
        -1 => {
            o.swap = true;
            o.fy = true;
        }
        _ => {}
    }
    o
}

/// Valori della scritta di chi ha vinto: testo, numero di lettere, scala.
#[inline(never)]
fn winner_text(w: u32) -> &'static [u8] {
    match w {
        1 => b"P1 WINS",
        2 => b"P2 WINS",
        3 => b"YOU WIN",
        4 => b"CPU WINS",
        _ => b"PERFECT",
    }
}

/// Lettere scritte dopo `a` frame, una ogni 5 o ogni 3, al massimo `n`.
#[inline(never)]
fn typed5(a: i32, n: i32) -> i32 {
    ((((a & 255) * 13) >> 6) + 1).min(n)
}
#[inline(never)]
fn typed3(a: i32, n: i32) -> i32 {
    ((((a & 255) * 11) >> 5) + 1).min(n)
}

const STAMP_DX: [i32; 8] = [3, -3, 3, -2, 2, -1, 1, 0];
const STAMP_DY: [i32; 8] = [0, 2, -2, 1, -1, 0, 0, 0];

/// Colonna (Q16.16 -> pixel) come col_of / row_first / row_last di pong_render.
#[inline(never)]
fn col_of(v: i32) -> i32 {
    (v.wrapping_sub(32768).wrapping_add(65535)) >> 16
}
#[inline(never)]
fn row_first(top: i32) -> i32 {
    ((15_728_640i32.wrapping_sub(32768).wrapping_sub(top)) >> 16) + 1
}
#[inline(never)]
fn row_last(bottom: i32) -> i32 {
    15_728_640i32.wrapping_sub(32768).wrapping_sub(bottom) >> 16
}

/// Stato che il renderer di prima teneva da un frame all'altro: la fase del riflesso di PERFECT.
#[derive(Default)]
pub struct GameState {
    pub glint_ph: i32,
}

#[inline(never)]
pub fn draw(r: &Regs, st: &mut GameState, d: &mut Dl) {
    let g = Game::new(r);
    let age = r.frame.min(255);
    // il riflesso conta a ogni frame (come la fotografia di pong_render), in tutti i modi
    st.glint_ph = if age < 48 || st.glint_ph == 59 {
        0
    } else {
        st.glint_ph + 1
    };
    if !matches!(g.mode, regs::M_DEMO | regs::M_GAME | regs::M_GAME_OVER) {
        return;
    }
    let upright = r.upright;
    let txt_c = if g.gray { GRAY } else { WHITE };
    // hit-stop del SUPER: il campo (e le sue scritte) trema di 2 pixel (shake di pong_top)
    let freeze = r.w[40] >> 16;
    let shake = if g.nxt && freeze != 0 {
        if freeze & 8 != 0 { -2 } else { 2 }
    } else {
        0
    };
    d.dx = -shake;

    // ---- classe C: punteggi, TOP NN, BALLS n, crediti della demo
    d.class = CLASS_C;
    let (lt, lo) = tens_ones(g.score[0]);
    let (rt, ro) = tens_ones(g.score[1]);
    let (bt, bo) = tens_ones(g.best);
    let show_lives = !g.two && (g.mode == regs::M_GAME || g.mode == regs::M_GAME_OVER);
    let top_s = [code(b'T'), code(b'O'), code(b'P'), code(b' '), bt, bo];
    let balls_s = [
        code(b'B'),
        code(b'A'),
        code(b'L'),
        code(b'L'),
        code(b'S'),
        code(b' '),
        g.lives as u8,
    ];
    if upright {
        // in alto ai lati della mezzeria: W/2 -+ 2 OX - SCORE_W
        for (x, t, o, show) in [(90, lt, lo, true), (186, rt, ro, g.two)] {
            if show {
                let a = digit(d, x, 8, t, 0, 0, txt_c);
                d.push(&a);
                let b = digit(d, x + 22, 8, o, 0, 0, txt_c);
                d.push(&b);
            }
        }
        if !g.two {
            let base = d.codes(&top_s.map(|c| (c, txt_c)));
            let o = up_text(d, 184, 10, base, 6, 0);
            d.push(&o);
        }
        if show_lives {
            let base = d.codes(&balls_s.map(|c| (c, txt_c)));
            let o = up_text(d, 180, 22, base, 7, 0);
            d.push(&o);
        }
    } else {
        // sinistro orario (la cima delle cifre guarda a destra), destro antiorario
        let a = digit(d, 125, 188, lt, 1, 0, txt_c);
        d.push(&a);
        let b = digit(d, 125, 210, lo, 1, 0, txt_c);
        d.push(&b);
        if g.two {
            let a = digit(d, 173, 30, rt, -1, 0, txt_c);
            d.push(&a);
            let b = digit(d, 173, 8, ro, -1, 0, txt_c);
            d.push(&b);
        }
        if !g.two {
            let base = d.codes(&top_s.map(|c| (c, txt_c)));
            let mut o = Obj::new(Kind::Text, 107, 186, 8, 48);
            o.base = base;
            o.swap = true;
            o.fx = true;
            o.class = d.class;
            d.push(&o);
        }
        if show_lives {
            let base = d.codes(&balls_s.map(|c| (c, txt_c)));
            let mut o = Obj::new(Kind::Text, 94, 182, 8, 56);
            o.base = base;
            o.swap = true;
            o.fx = true;
            o.class = d.class;
            d.push(&o);
        }
    }
    if g.mode == regs::M_DEMO {
        let cy = if g.demo_kind & 2 != 0 { H - 6 - 8 } else { 6 };
        if r.free_play {
            d.text(8, cy, b"FREE PLAY", WHITE, 0);
        } else {
            d.text(
                8,
                cy,
                &[b'C', b'R', b'E', b'D', b'I', b'T', b' ', b'0' + r.credits as u8],
                WHITE,
                0,
            );
        }
    }

    // ---- classe B: scritta della demo, fine partita, conto alla rovescia, chiusura
    d.class = CLASS_B;
    if g.mode == regs::M_DEMO {
        let s: &[u8] = if r.blink >= 37 {
            match g.demo_kind {
                0 => b"CLASSIC",
                1 => b"EVO",
                _ => b"NEXT",
            }
        } else if !r.free_play && r.credits == 0 {
            b"INSERT COIN"
        } else {
            b"PRESS START"
        };
        let lw = text_w(s);
        if upright {
            d.rect((W - lw - 12) / 2, DEMO_LABEL_Y - 5, lw + 12, 17, BLACK);
            d.text((W - lw) / 2, DEMO_LABEL_Y, s, WHITE, 0);
        } else {
            for (right, cx) in [(false, ROT_CX_L), (true, ROT_CX_R)] {
                fill(d, rot_box(cx, lw, 0), BLACK);
                let base = d.tiles(s, WHITE);
                let o = rot_text(d, right, cx, lw, 0, base, s.len());
                d.push(&o);
            }
        }
    }
    if g.mode == regs::M_GAME_OVER {
        game_over(r, &g, st, age, d);
    }
    if g.countdown != 0 {
        let v = g.countdown as u8;
        if upright {
            d.rect(W / 2 - 28, H / 2 - 28, 56, 56, BLACK);
            let o = digit(d, W / 2 - 11, H / 2 - 22, v, 0, 1, WHITE);
            d.push(&o);
        } else {
            let cx = if g.two { W / 2 - 22 - 6 } else { W / 2 };
            let bl = [cx - 28, cx + 28, H / 2 - 28, H / 2 + 28];
            fill(d, bl, BLACK);
            if g.two {
                fill(d, [W / 2 + 28 - 28, W / 2 + 28 + 28, bl[2], bl[3]], BLACK);
            }
            let o = digit(d, cx - 22, H / 2 - 11, v, 1, 1, WHITE).clip(bl[0], bl[1], bl[2], bl[3]);
            d.push(&o);
            if g.two {
                let cr = W / 2 + 28;
                let o = digit(d, cr - 22, H / 2 + 11 - 44, v, -1, 1, WHITE).clip(cr - 28, cr + 28, bl[2], bl[3]);
                d.push(&o);
            }
        }
    }
    if g.mode == regs::M_GAME_OVER && !g.solo && !g.perfect && age >= 158 {
        // chiusura del televisore sopra tutto: il nero stringe una fascia bordata di bianco, poi una
        // riga che si stringe, poi un puntino
        // (le parti a tutta larghezza non si spostano con la scossa)
        let dx = d.dx;
        d.dx = 0;
        if age >= 180 {
            d.rect(0, 0, W, H, BLACK);
        } else if age >= 174 {
            d.rect(0, 0, W, H, BLACK);
            d.dx = dx;
            d.rect(W / 2 - 1, H / 2 - 1, 2, 2, WHITE);
        } else if age >= 166 {
            let hw = if age >= 173 {
                1
            } else {
                (160 - 20 * ((age - 158 - 7) & 255)) & 511
            };
            d.rect(0, 0, W, H, BLACK);
            d.dx = dx;
            d.rect(W / 2 - hw, H / 2 - 1, 2 * hw, 2, WHITE);
        } else {
            let hh = if age >= 166 { 1 } else { (120 - 15 * (age - 158)) & 255 };
            d.rect(0, 0, W, H / 2 - hh, BLACK);
            d.rect(0, H / 2 + hh, W, H, BLACK);
            d.rect(0, H / 2 - hh, W, 1, WHITE);
            d.rect(0, H / 2 + hh - 1, W, 1, WHITE);
        }
        d.dx = dx;
    }
}

/// Fine partita animata (OV_* di pong_render).
#[inline(never)]
fn game_over(r: &Regs, g: &Game, st: &GameState, age: i32, d: &mut Dl) {
    const OFF: u32 = 1;
    const TYPE: u32 = 2;
    const STAMP: u32 = 3;
    const HOP: u32 = 4;
    let upright = r.upright;
    let show_rs = g.two;
    let w = g.winner;
    let ov = if g.solo && w == 3 {
        HOP
    } else if g.perfect || w == 5 {
        STAMP
    } else if g.solo {
        TYPE
    } else {
        OFF
    };
    let ws = winner_text(w);
    let mut wl1 = [0i32; 16];
    let mut wl0 = [0i32; 16];
    let wn = letters(ws, Some(&mut wl0), Some(&mut wl1)) as i32;
    let mut gl1 = [0i32; 16];
    let gn = letters(b"GAME OVER", None, Some(&mut gl1)) as i32;
    let wsh: u32 = if w == 3 || w == 5 { 1 } else { 0 };
    let ww = text_w(ws);
    let win_wb = ww << wsh;
    let win_x0 = (W - win_wb) >> 1;
    let a1 = age - if g.solo { 12 } else { 56 };
    let n1 = typed5(a1, if g.solo { wn } else { gn });
    let type_show = age >= if g.solo { 12 } else { 56 };
    let type_cols = if g.solo {
        wl1[(n1 - 1) as usize & 15]
    } else {
        gl1[(n1 - 1) as usize & 15]
    };
    let n2 = typed3(age - 106, wn);
    let win_show = !g.solo && w != 0 && age >= 106;
    let win_cols = wl1[(n2 - 1) as usize & 15];
    let (cur_x, cur_y, cur_sh, cur_on);
    if !g.solo && w != 0 && age >= 106 {
        cur_x = (W - win_wb) / 2 + (wl1[(n2 - 1) as usize & 15] << wsh) + 2;
        cur_y = WINNER_Y;
        cur_sh = wsh;
        cur_on = n2 < wn || age & 16 != 0;
    } else {
        cur_x = if g.solo {
            (W - win_wb) / 2 + (wl1[(n1 - 1) as usize & 15] << wsh)
        } else {
            (W - GO_WB) / 2 + (gl1[(n1 - 1) as usize & 15] << 1)
        } + 2;
        cur_y = GAME_OVER_Y;
        cur_sh = if g.solo { wsh } else { 1 };
        cur_on = type_show && (n1 < if g.solo { wn } else { gn } || (w != 0 && !g.solo) || age & 16 != 0);
    }
    let stamping = ov == STAMP && age < 11 && upright;
    let (shk_x, shk_y) = if (11..19).contains(&age) {
        let k = ((age & 7) - 3) & 7;
        (STAMP_DX[k as usize], STAMP_DY[k as usize])
    } else {
        (0, 0)
    };
    let pf_edge = (11..16).contains(&age);
    let pf_win = age >= 28;
    let glint_on = age >= 48;
    let pf_right = if w == 5 { g.you_right } else { w == 2 };
    // colore di chi ha vinto: giallo in NEXT; YOU WIN spento prima della palla, bianco nel lampeggio
    let ht = (age - 70) & 255;
    let hop_white = age > 70 && age < 118 && ht & 8 == 0;
    let win_c = if g.nxt { ACCENT } else { WHITE };
    let win_c_hop = if hop_white {
        if g.nxt { WHITE } else { DIM_WIN }
    } else {
        win_c
    };

    // riquadri, scritte (dritte: spostate dalla scossa del timbro) e grafica di PERFECT
    let go_base = d.tiles(b"GAME OVER", WHITE);
    let win_base = d.tiles(ws, win_c);
    let mut boxes: [Option<[i32; 4]>; 4] = [None; 4];
    let mut nb = 0;
    let mut add_box = |b: [i32; 4]| {
        boxes[nb] = Some(b);
        nb += 1;
    };
    // GAME OVER (dritto o ruotato) e chi ha vinto (dritto o ruotato), con le loro colonne visibili
    let mut go_up = true;
    let mut go_rot = [true, show_rs];
    let mut win_up = false;
    let mut win_rot = [false, false];
    let mut go_up_cols = 1000;
    let mut go_rot_cols = 1000;
    let mut win_up_cols = 1000;
    let mut win_rot_cols = 1000;
    let mut win_up_y = WINNER_Y;
    let mut win_rot_cx = [ROT_CX_L - 20, ROT_CX_R + 20];
    let mut pf = false;
    let mut pf_rbox = false;
    let mut edge: Option<[i32; 4]> = None;
    let mut rot_boxes: [Option<[i32; 4]>; 3] = [None; 3];
    // caso di partenza: GAME OVER
    let mut ub = [GO_BOX_X, GO_BOX_X + GO_WB + 12, GAME_OVER_Y - 5, GAME_OVER_Y + BH + 5];
    rot_boxes[0] = Some(rot_box(ROT_CX_L, GO_WB, 1));
    if show_rs {
        rot_boxes[1] = Some(rot_box(ROT_CX_R, GO_WB, 1));
    }
    let win_right;
    if g.solo && w != 0 {
        ub = [
            (W - win_wb - 12) / 2,
            (W + win_wb + 12) / 2,
            GAME_OVER_Y - 5,
            GAME_OVER_Y + (7 << wsh) + 5,
        ];
        go_up = false;
        go_rot = [false, false];
        win_up = true;
        win_up_y = GAME_OVER_Y;
        win_rot_cx = [ROT_CX_L, ROT_CX_R];
        win_right = if w == 4 { !g.you_right } else { g.you_right };
        rot_boxes = [None; 3];
        if win_right {
            if show_rs {
                rot_boxes[0] = Some(rot_box(ROT_CX_R, win_wb, wsh));
            }
        } else {
            rot_boxes[0] = Some(rot_box(ROT_CX_L, win_wb, wsh));
        }
        win_rot = [!win_right, win_right && show_rs];
        if w == 5 {
            ub = [PF_BOX_X0, PF_BOX_X1, PF_BOX_Y0, GAME_OVER_Y + BH + 5];
            rot_boxes = [None; 3];
            pf_rbox = true;
            win_up = false;
            win_rot = [false, false];
        }
    } else if w != 0 {
        win_right = false;
        ub = [
            GO_BOX_X,
            GO_BOX_X + GO_WB + 12,
            if g.perfect { PF_BOX_Y0 } else { GAME_OVER_Y - 5 },
            WINNER_Y + (7 << wsh) + 5,
        ];
        if g.perfect {
            go_up = false;
            go_rot = if w == 1 { [false, show_rs] } else { [true, false] };
            pf_rbox = true;
        }
        win_up = true;
        win_rot = [true, show_rs];
        let b = rot_box(ROT_CX_L - 20, GO_WB, wsh);
        rot_boxes[2] = Some(b);
        if show_rs {
            // il box destro di chi ha vinto si aggiunge come quarto
            add_box(rot_box(ROT_CX_R + 20, GO_WB, wsh));
        }
    } else {
        win_right = false;
    }
    let _ = win_right;
    // animazioni
    let mut cursor = false;
    let mut up_visible = true;
    let mut rot_visible = true;
    let mut win_rot_any = false;
    match ov {
        OFF | TYPE => {
            if !type_show {
                up_visible = false;
                rot_visible = false;
            }
            go_up_cols = type_cols;
            go_rot_cols = type_cols;
            if g.solo {
                go_rot = [false, false];
                win_up_cols = type_cols;
                win_rot_cols = type_cols;
                win_rot = [true, show_rs];
                win_rot_any = true;
            } else {
                win_up = win_up && win_show;
                win_up_cols = win_cols;
                win_rot = if win_show { [true, show_rs] } else { [false, false] };
                win_rot_cols = win_cols;
            }
            cursor = cur_on && upright;
        }
        STAMP => {
            pf = true;
            if stamping {
                up_visible = false;
                rot_visible = false;
            } else {
                if upright && pf_edge {
                    let w5 = w == 5;
                    edge = Some([
                        if w5 { PF_BOX_X0 } else { GO_BOX_X },
                        if w5 { PF_BOX_X1 - 1 } else { GO_BOX_X + GO_WB + 11 },
                        PF_BOX_Y0,
                        if w5 {
                            GAME_OVER_Y + BH + 4
                        } else {
                            WINNER_Y + 4 + (7 << wsh)
                        },
                    ]);
                }
                if w != 5 && !pf_win {
                    win_up = false;
                    win_rot = [false, false];
                }
            }
        }
        _ => {}
    }
    let _ = win_rot_any;
    let up_box = ub;
    let (ox, oy) = (shk_x, shk_y);
    if upright {
        if up_visible {
            let b = [up_box[0] + ox, up_box[1] + ox, up_box[2] + oy, up_box[3] + oy];
            // (YOU WIN senza riquadro: le lettere direttamente sopra la partita, come sul PC)
            if ov != HOP {
                d.rect(b[0], b[2], b[1] - b[0], b[3] - b[2], BLACK);
            }
            // chi ha vinto (colori della palla di YOU WIN lettera per lettera)
            if win_up && ov == HOP {
                hop_letters(d, g, age, win_base, ws, &wl1, b, ox, oy, win_c_hop);
            } else if win_up {
                let o = up_text(d, win_x0 + ox, win_up_y + oy, win_base, ws.len(), wsh)
                    .clip(b[0], b[1], b[2], b[3])
                    .clip(0, win_x0 + ox + (win_up_cols << wsh), 0, H);
                d.push(&o);
            }
            if go_up {
                let x0 = (W - GO_WB) / 2 + ox;
                let o = up_text(d, x0, GAME_OVER_Y + oy, go_base, 9, 1)
                    .clip(b[0], b[1], b[2], b[3])
                    .clip(0, x0 + (go_up_cols << 1), 0, H);
                d.push(&o);
            }
            if pf {
                let o = d
                    .img_obj(PFG_X0 + ox, PFG_Y0 + oy, &IMG_PERFECT, TL)
                    .clip(b[0], b[1], b[2], b[3]);
                d.push(&o);
                if glint_on {
                    // riflesso: fascia in diagonale sui pixel della grafica (u + v in [s, s + 12))
                    let s = 4 * st.glint_ph - 20;
                    for v in 0..PF_H {
                        let o = d
                            .img_obj(PFG_X0, PFG_Y0, &IMG_PERFECT, TL_GLINT)
                            .clip(b[0], b[1], b[2], b[3])
                            .clip(PFG_X0 + s - v, PFG_X0 + s - v + 12, PFG_Y0 + v, PFG_Y0 + v + 1);
                        d.push(&o);
                    }
                }
            }
            if let Some(e) = edge {
                let (x0, x1, y0, y1) = (e[0] + ox, e[1] + ox, e[2] + oy, e[3] + oy);
                let clipb = |o: Obj| o.clip(b[0], b[1], b[2], b[3]);
                for o in [
                    Obj::new(Kind::Rect, x0, b[2], 1, b[3] - b[2]),
                    Obj::new(Kind::Rect, x1, b[2], 1, b[3] - b[2]),
                    Obj::new(Kind::Rect, b[0], y0, b[1] - b[0], 1),
                    Obj::new(Kind::Rect, b[0], y1, b[1] - b[0], 1),
                ] {
                    let mut o = clipb(o);
                    o.ca = ACCENT;
                    o.class = d.class;
                    d.push(&o);
                }
            }
        }
    } else if rot_visible {
        // da tavolo: riquadri ruotati, scritte verso i giocatori
        let mut all: [Option<[i32; 4]>; 6] = [None; 6];
        let mut k = 0;
        for b in rot_boxes.iter().flatten().chain(boxes.iter().flatten()) {
            all[k] = Some(*b);
            k += 1;
        }
        if pf_rbox {
            all[k] = Some(if pf_right {
                [PFR_XR - 5, PFR_XR + PF_H + 5, PFR_YR - 6, PFR_YR + PF_W + 6]
            } else {
                [PFR_XL - 5, PFR_XL + PF_H + 5, PFR_YL - 6, PFR_YL + PF_W + 6]
            });
        }
        if ov != HOP {
            for b in all.iter().flatten() {
                fill(d, *b, BLACK);
            }
        }
        // scritte visibili solo dentro i riquadri
        let in_boxes = |d: &mut Dl, o: Obj| {
            for b in all.iter().flatten() {
                d.push(&o.clip(b[0], b[1], b[2], b[3]));
            }
        };
        for (side, on) in win_rot.iter().enumerate() {
            if !*on {
                continue;
            }
            let right = side == 1;
            if ov == HOP {
                // le lettere della scritta verso il giocatore spente finché la palla non ci salta sopra
                if right != g.you_right {
                    continue;
                }
                for li in 0..wn {
                    let lit = age >= 16 + 8 * if g.you_right { 5 - li } else { li };
                    let c = if !lit { DIM_WIN } else { win_c_hop };
                    let base = d.tiles(ws, c);
                    let lo = if li == 0 { -1000 } else { wl1[li as usize - 1] };
                    let hi = if li == wn - 1 { 1000 } else { wl1[li as usize] };
                    let o = rot_text(d, right, win_rot_cx[side], win_wb, wsh, base, ws.len());
                    let o = clip_along(o, right, lo << wsh, hi << wsh);
                    in_boxes(d, o);
                }
            } else {
                let o = rot_text(d, right, win_rot_cx[side], win_wb, wsh, win_base, ws.len());
                let o = clip_along(o, right, -1000, win_rot_cols << wsh);
                in_boxes(d, o);
            }
        }
        for (side, on) in go_rot.iter().enumerate() {
            if !*on {
                continue;
            }
            let right = side == 1;
            let cx = if right { ROT_CX_R } else { ROT_CX_L };
            let o = rot_text(d, right, cx, GO_WB, 1, go_base, 9);
            let o = clip_along(o, right, -1000, go_rot_cols << 1);
            in_boxes(d, o);
        }
        if pf && pf_rbox {
            let mut o = if pf_right {
                let mut o = d.img_obj(PFR_XR, PFR_YR, &IMG_PERFECT, TL);
                o.fy = true;
                o
            } else {
                let mut o = d.img_obj(PFR_XL, PFR_YL, &IMG_PERFECT, TL);
                o.fx = true;
                o
            };
            o.swap = true;
            o.w = PF_H;
            o.h = PF_W;
            in_boxes(d, o);
        }
    }
    // aggiunte fuori dal riquadro: cursore (dritto), palla di YOU WIN, timbro di PERFECT
    if cursor {
        d.rect(cur_x, cur_y, 4 << cur_sh, 7 << cur_sh, WHITE);
    }
    if ov == HOP {
        hop_ball(r, g, age, d);
    }
    if stamping {
        let mut o = d.img_obj(PFS_X0, PFS_Y0, &IMG_PERFECT, TL);
        o.w = 2 * PF_W;
        o.h = 2 * PF_H;
        o.sx = 1;
        o.sy = 1;
        d.push(&o);
    }
}

/// Ritaglio lungo la scritta ruotata: colonne [lo, hi) del testo (già scalate).
#[inline(never)]
fn clip_along(o: Obj, right: bool, lo: i32, hi: i32) -> Obj {
    // sinistra: la colonna u del testo è la riga y0 + u; destra: la riga y0 + len - 1 - u
    if right {
        o.clip(0, W, o.y + o.h - hi, o.y + o.h - lo)
    } else {
        o.clip(0, W, o.y + lo, o.y + hi)
    }
}

/// YOU WIN dritto: lettere spente finché la palla non ci salta sopra, poi accese (abbassate di 2
/// pixel per 3 frame); finiti i salti lampeggiano.
#[allow(clippy::too_many_arguments)]
#[inline(never)]
fn hop_letters(
    d: &mut Dl,
    g: &Game,
    age: i32,
    _base: u32,
    ws: &[u8],
    wl1: &[i32; 16],
    b: [i32; 4],
    ox: i32,
    oy: i32,
    c_lit: u8,
) {
    const YW_X0: i32 = (W - (55 << 1)) / 2;
    let n = 6;
    for li in 0..n {
        let hp = if g.you_right { 5 - li } else { li };
        let lit = age >= 16 + 8 * hp;
        let press = age >= 16 + 8 * hp && age < 19 + 8 * hp;
        let c = if !lit { DIM_WIN } else { c_lit };
        let base = d.tiles(ws, c);
        let lo = if li == 0 { -1000 } else { wl1[li as usize - 1] };
        let hi = if li == n - 1 { 1000 } else { wl1[li as usize] };
        let x0 = YW_X0 + ox;
        let o = d
            .text_obj(x0, GAME_OVER_Y + oy + if press { 2 } else { 0 }, base, ws.len(), 1)
            .clip(b[0], b[1], b[2], b[3])
            .clip(x0 + (lo << 1), x0 + (hi << 1), 0, H);
        d.push(&o);
    }
}

/// Palla di YOU WIN: dalla racchetta del giocatore alla prima lettera, salti di lettera in
/// lettera, poi via in una parabola (hop_* di pong_render).
#[inline(never)]
fn hop_ball(r: &Regs, g: &Game, age: i32, d: &mut Dl) {
    const YW_X0: i32 = (W - (55 << 1)) / 2;
    const HOP_TOP: i32 = GAME_OVER_Y - 4;
    let mut l0 = [0i32; 16];
    let mut l1 = [0i32; 16];
    letters(b"YOU WIN", Some(&mut l0), Some(&mut l1));
    let hop_cx = |i: i32| YW_X0 + l0[i as usize] + l1[i as usize] - 2;
    let yr = g.you_right as usize;
    let hw = 131_072; // P_PAD_WIDTH / 2
    let c0 = col_of(g.pad_x[yr] - hw);
    let c1 = col_of(g.pad_x[yr] + hw);
    let hh = g.pad_h[yr] >> 1;
    let r0 = row_first(g.pad_y[yr] + hh);
    let r1 = row_last(g.pad_y[yr] - hh);
    let hsx = ((c0 + c1) >> 1) - 2;
    let hsy = ((r0 + r1) >> 1) - 2;
    let n = 6;
    let hf = age;
    let mut on = true;
    let (hx, hy, hs);
    if hf < 16 {
        hs = hf & 15;
        let ha = hop_cx(if g.you_right { n - 1 } else { 0 }) - hsx;
        let hb = HOP_TOP - hsy;
        hx = hsx + ((ha * hs) >> 4);
        hy = hsy + ((hb * hs) >> 4) - ((hs * (16 - hs) * 5) >> 4);
    } else if hf < 56 {
        let hj = (hf - 16) >> 3;
        hs = hf & 7;
        let ha = hop_cx(if g.you_right { n - 1 - hj } else { hj });
        let hb = hop_cx(if g.you_right { n - 2 - hj } else { hj + 1 });
        hx = ha + (((hb - ha) * hs) >> 3);
        hy = HOP_TOP - ((hs * (8 - hs) * 9) >> 3);
    } else {
        hs = (hf - 56).min(63);
        hx = hop_cx(if g.you_right { 0 } else { n - 1 }) + if g.you_right { -(hs << 2) } else { hs << 2 };
        hy = HOP_TOP - hs * 6 + ((hs * hs * 5) >> 3);
        on = hs < 48;
    }
    if !on {
        return;
    }
    let s12 = |v: i32| (v << 20) >> 20;
    if r.upright {
        d.rect(s12(hx), s12(hy), 4, 4, WHITE);
    } else {
        const BHS: i32 = 14;
        let yw_wb = 55 << 1;
        let rot_cx_l = ROT_CX_L;
        let rot_cx_r = ROT_CX_R;
        let y0l = (H - yw_wb) / 2 - ROT_SHIFT;
        let y0r = (H - yw_wb) / 2 + ROT_SHIFT;
        let hpu = if hf < 16 {
            hop_cx(if g.you_right { n - 1 } else { 0 }) - YW_X0
        } else {
            hx - YW_X0
        };
        let hpv = if hf < 16 {
            HOP_TOP - GAME_OVER_Y
        } else {
            hy - GAME_OVER_Y
        };
        let ha = if g.you_right {
            rot_cx_r - (BHS + 1) / 2 + hpv
        } else {
            rot_cx_l + (BHS + 1) / 2 - 4 - hpv
        };
        let hb = if g.you_right { y0r + yw_wb - 4 - hpu } else { y0l + hpu };
        let (x, y) = if hf < 16 {
            (
                hsx + (((ha - hsx) * hs) >> 4),
                hsy + (((hb - hsy) * hs) >> 4) - ((hs * (16 - hs) * 5) >> 4),
            )
        } else {
            (ha, hb)
        };
        d.rect(s12(x), s12(y), 4, 4, WHITE);
    }
}
