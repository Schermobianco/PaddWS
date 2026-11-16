//! Presentazione dell'avversario della scalata (come il vecchio challenge_render.v, schermata 1, più
//! la racchetta dell'avversario di next_render.v e la scossa di pong_top.v): in cima il livello e la
//! scala dei sette livelli, poi ogni avversario entra a modo suo e porta nome, motto, bonus e FIRST TO.
//! Le x "verso l'avversario" (ax) vanno verso la sua metà campo, da dove entra.
//!
//! OMEGA (livello 7, dopo l'allarme di omega.rs): SECRET LEVEL, la racchetta rossa che passa per le
//! sette forme della scala con un lampo bianco a ogni cambio e torna ARCADE, il sigillo che arriva
//! bianco e lampeggia, il motto, i bonus di ARCADE e FIRST TO 7 (omega() di challenge_ui.rs).
//!
//! Per ogni frame si calcolano i valori dell'animazione con gli stessi conti di prima (`i_*` e
//! `ip_*`), poi gli oggetti nell'ordine in cui il renderer sceglieva i colori.

use crate::assets::game::{self, BLASTER_SLANT, GUARDIAN_X, KIND_H, PW, SIN_Q8};
use crate::assets::{IMG_ICON, IMG_NAME, IMG_NAME_OMEGA};
use crate::challenge::{Ch, intro_age};
use crate::dl::{CLASS_A, Dl, Obj, code, text_w};
use crate::paddle::{Colors, Pad};
use crate::pal::{
    ACCENT, BLACK, DETAIL, DIM, GRAY, PGHOST1, PGHOST2, PGHOST3, TL, TL_GHOST, TL_HI, TL_WHITE, TRAIL1, TRAIL2, TRAIL3,
    WHITE,
};
use crate::regs::{Omega, Regs};

const W: i32 = 320;
const C: i32 = 8;
const IP_Y: i32 = 82;
const NAME_BASE: i32 = 131;
const TITAN_TOP: i32 = 108;
const NAME_GROUND: i32 = TITAN_TOP + 26;
const WALL_TOP: i32 = IP_Y - 36;
const INTRO_CAP: i32 = 13;
const INTRO_CAP_Y: i32 = 154;
const INTRO_FIRST_Y: i32 = 190;
const K_ARCADE: u32 = 0;
const K_TITAN: u32 = 1;
const K_HAMMER: u32 = 2;
const K_TWIST: u32 = 3;
const K_BLASTER: u32 = 4;
const K_RUSH: u32 = 5;
const K_GUARDIAN: u32 = 6;
/// OMEGA: livello, motto, forme della scala (PaddleKind nell'ordine dei livelli), tempi
const OMEGA_LEVEL: u32 = 7;
const OMEGA_TAG: &[u8] = b"IT BECOMES THEM ALL";
const LADDER: [u32; 7] = [K_ARCADE, K_TWIST, K_HAMMER, K_TITAN, K_BLASTER, K_RUSH, K_GUARDIAN];
const OMEGA_FORMS_AT: i32 = 6;
const OMEGA_FORM_FRAMES: i32 = 24;
const OMEGA_FLASH: i32 = 8;
const OMEGA_NAME_AT: i32 = 180;
const OMEGA_NAME_TOP: i32 = 108;

#[inline(never)]
fn arcade_dy(k: i32) -> i32 {
    [-14, 10, -4, 16, -18, 2, 12, -10, 6, -2][k.clamp(0, 9) as usize]
}

#[inline(never)]
fn twist_shear(t: i32) -> i32 {
    match t {
        0 | 1 => 2,
        5 | 6 => -2,
        2 | 9 | 10 | 11 | 18 => 1,
        4 | 7 | 13 | 14 | 15 => -1,
        _ => 0,
    }
}

#[inline(never)]
fn twist_dx(s: i32, r: i32) -> i32 {
    match s {
        1 => r >> 1,
        2 => r,
        -1 => -(r >> 1),
        -2 => -r,
        _ => 0,
    }
}

#[inline(never)]
fn fall_q(t: i32) -> i32 {
    [10, 41, 92, 164, 256, 256, 256, 256][(t & 7) as usize]
}

/// Valori dell'animazione di un frame (i_* di challenge_render).
struct Anim {
    title: bool,
    lad: i32,
    name: bool,
    ndx: i32,
    ndy: i32,
    nacc: bool,
    lmin: i32,
    lmax: i32,
    shear: i32,
    ground: bool,
    gline: bool,
    ghost: bool,
    gdx: i32,
    lshow: [bool; 8],
    ldy: [i32; 8],
    tag: bool,
    tcols: i32,
    tdx: i32,
    cap: [bool; 3],
    cinv: [bool; 3],
    cname: [bool; 3],
    cdx: [i32; 3],
    cdy: [i32; 3],
    first: bool,
    net: bool,
    netx: i32,
    son: [bool; 4],
    sx: [i32; 4],
    sy: [i32; 4],
    ball: bool,
    bx: i32,
    by: i32,
    trail: [bool; 3],
    tx: [i32; 3],
    shot: [bool; 3],
    shx: [i32; 3],
    shy: [i32; 3],
    dust: bool,
    ux: [i32; 4],
    uy: [i32; 4],
    wall: [bool; 5],
    wx: i32,
    wy: [i32; 5],
    wflash: bool,
}

/// Il motto si scrive da t0, una lettera (8 pixel) per frame.
#[inline(never)]
fn tag_from(a: &mut Anim, age: i32, t0: i32) {
    a.tag = age >= t0;
    let tt = (age - t0) & 255;
    a.tcols = if tt >= 16 { 127 } else { (tt & 15) << 3 };
}

impl Anim {
    fn new(age: i32, kind: u32, level: u32, side: bool) -> Self {
        let ax = |d: i32| W / 2 + if side { -d } else { d };
        let mut a = Anim {
            title: age >= 14 && (level < 6 || age & 8 == 0),
            lad: if age >= 12 { 7 } else { ((age >> 1) & 7) + 1 },
            name: true,
            ndx: 0,
            ndy: 0,
            nacc: false,
            lmin: 0,
            lmax: 8,
            shear: 0,
            ground: false,
            gline: false,
            ghost: false,
            gdx: 0,
            lshow: [true; 8],
            ldy: [0; 8],
            tag: true,
            tcols: 127,
            tdx: 0,
            cap: [true; 3],
            cinv: [false; 3],
            cname: [true; 3],
            cdx: [0; 3],
            cdy: [0; 3],
            first: true,
            net: false,
            netx: 0,
            son: [false; 4],
            sx: [0; 4],
            sy: [0; 4],
            ball: false,
            bx: 0,
            by: 0,
            trail: [false; 3],
            tx: [0; 3],
            shot: [false; 3],
            shx: [0; 3],
            shy: [0; 3],
            dust: false,
            ux: [0; 4],
            uy: [0; 4],
            wall: [false; 5],
            wx: 0,
            wy: [0; 5],
            wflash: false,
        };
        // capsule che arrivano dalla metà campo dell'avversario, una ogni gap frame da t0, sp pixel per frame
        let caps_slide = |a: &mut Anim, t0: i32, gap: i32, sp: i32| {
            for c in 0..3 {
                let ts = (t0 + gap * c as i32) & 255;
                let tv = if side { 100 + 80 * c as i32 } else { 260 - 80 * c as i32 };
                let tm = ((age - ts) & 255) * sp;
                if age < ts {
                    a.cap[c] = false;
                    a.cname[c] = false;
                } else if tm < tv {
                    a.cdx[c] = if side { -(tv - tm) } else { tv - tm };
                    a.cname[c] = false;
                } else {
                    a.cinv[c] = tm < tv + (sp << 2);
                }
            }
        };
        if level == OMEGA_LEVEL {
            // il sigillo bianco, poi un lampeggio, poi i suoi colori (nacc: tutto bianco); il motto da
            // 196, i bonus di ARCADE uno ogni 10 frame da 226, FIRST TO da 264 (presentazione di 315
            // frame, CH_OMEGA_INTRO_FRAMES di pong_top)
            let t = age - OMEGA_NAME_AT;
            a.name = age >= OMEGA_NAME_AT;
            a.nacc = a.name && (t < 4 || (t < 20 && (t >> 2) & 1 == 1));
            // il motto è più lungo degli altri (19 lettere): una lettera per frame fino alla fine
            let tt = age - 196;
            a.tag = tt >= 0;
            a.tcols = if tt >= OMEGA_TAG.len() as i32 { 1000 } else { tt << 3 };
            for c in 0..3 {
                let ts = 226 + 10 * c as i32;
                a.cap[c] = age >= ts;
                a.cname[c] = age >= ts;
                a.cinv[c] = age >= ts && age < ts + 4;
            }
            a.first = age >= 264;
            return a;
        }
        match kind {
            K_ARCADE => {
                a.net = (6..84).contains(&age);
                a.netx = ax(-120);
                for q in 0..10 {
                    let ts = 10 + 6 * q;
                    if age >= ts && age < ts + 20 {
                        let k = (q % 4) as usize;
                        a.son[k] = true;
                        let tv = (age - ts) * 6;
                        a.sx[k] = ax(-120 + tv) - 4;
                        a.sy[k] = IP_Y + arcade_dy(q) - 4;
                    }
                }
                let tt = (age - 84) & 255;
                a.name = age >= 84 && (age >= 108 || tt & 4 == 0);
                tag_from(&mut a, age, 100);
                for c in 0..3 {
                    let ts = 120 + 8 * c as i32;
                    let tt = if age < ts {
                        0
                    } else if age - ts >= 8 {
                        8
                    } else {
                        age - ts
                    };
                    a.cap[c] = age >= ts;
                    a.cdx[c] = ((80 - 80 * c as i32) * (8 - tt)) >> 3;
                    a.cdy[c] = ((IP_Y - 6 - INTRO_CAP_Y) * (8 - tt)) >> 3;
                    a.cinv[c] = age >= ts + 8 && age < ts + 12;
                    a.cname[c] = age >= ts + 8;
                }
                a.first = age >= 160;
            }
            K_TWIST => {
                if (14..30).contains(&age) {
                    a.ball = true;
                    a.bx = ax(-160 + (age - 14) * 10) - 2;
                    a.by = IP_Y + 9;
                } else if (30..55).contains(&age) {
                    let tt = age - 30;
                    a.ball = true;
                    a.bx = ax(-8 - tt * 7) - 2;
                    a.by = IP_Y + 9 - tt * 4;
                }
                a.name = age >= 66;
                let tt = (age - 66) & 255;
                a.shear = if age >= 66 && tt < 24 { twist_shear(tt & 31) } else { 0 };
                tag_from(&mut a, age, 92);
                caps_slide(&mut a, 112, 12, 30);
                a.first = age >= 160;
            }
            K_HAMMER => {
                if (12..49).contains(&age) {
                    a.ball = true;
                    a.bx = ax(-10 - (49 - age) * 4) - 2;
                    a.by = IP_Y - 2;
                } else if (49..59).contains(&age) {
                    let tv = -10 - (age - 49) * 20;
                    a.ball = true;
                    a.bx = ax(tv) - 2;
                    a.by = IP_Y - 2;
                    a.trail = [true; 3];
                    for q in 0..3 {
                        a.tx[q] = ax(tv + 8 * (q as i32 + 1)) - 2;
                    }
                }
                a.name = age >= 62;
                let tt = (72 - age) & 255;
                let tm = tt * tt;
                a.ndy = if age < 72 { -(tm + ((tm * 5) >> 4)) } else { 0 };
                if (72..82).contains(&age) {
                    let tv = age - 72;
                    let tm = (tv * tv * 13) >> 5;
                    let tw = IMG_NAME[K_HAMMER as usize].w as i32;
                    a.dust = true;
                    a.ux = [
                        W / 2 - (tw >> 1) - 5 - tv * 3,
                        W / 2 + (tw >> 1) + 3 + tv * 3,
                        W / 2 - (tw >> 1) - 5 - tv * 5,
                        W / 2 + (tw >> 1) + 3 + tv * 5,
                    ];
                    let y5 = NAME_BASE - 1 - ((tv * 5) >> 1) + tm;
                    let y3 = NAME_BASE - 1 - ((tv * 3) >> 1) + tm;
                    a.uy = [y5, y5, y3, y3];
                }
                tag_from(&mut a, age, 88);
                for c in 0..3 {
                    let ts = 106 + 10 * c as i32;
                    let tt = (age - ts) & 255;
                    let tv = 8 - tt;
                    a.cap[c] = age >= ts;
                    a.cdy[c] = if age >= ts && tt < 8 { -(tv * tv * 3) } else { 0 };
                    a.cinv[c] = age >= ts && (8..11).contains(&tt);
                    a.cname[c] = age >= ts && tt >= 8;
                }
                a.first = age >= 150;
            }
            K_TITAN => {
                a.name = age >= 84;
                let tt = (age - 84) & 255;
                a.ndy = if age < 84 || tt >= 26 { 0 } else { 26 - tt };
                a.ground = true;
                a.gline = (84..112).contains(&age);
                a.tag = age >= 114;
                let tm = (((age - 114) & 255) * 85) >> 5;
                a.tcols = if ((age - 114) & 255) >= 48 { 127 } else { tm & 127 };
                caps_slide(&mut a, 156, 12, 8);
                a.first = age >= 214;
            }
            K_BLASTER => {
                let mut tn = 0;
                let tx0 = (W - IMG_NAME[K_BLASTER as usize].w as i32) / 2;
                for q in 0..7 {
                    let tv = if side { q } else { 6 - q };
                    let mut td = tx0 + game::BLASTER_CX0 + game::BLASTER_STEP * tv;
                    td = ax(112) - td;
                    td = td.abs();
                    let ts = 12 + 5 * q;
                    let tm = ((age - ts) & 255) * 20;
                    if age >= ts && tm >= td {
                        tn += 1;
                    }
                    if age >= ts && tm < td {
                        let k = (q % 3) as usize;
                        a.shot[k] = true;
                        a.shx[k] = ax(112 - tm) - 3;
                        a.shy[k] = NAME_BASE - 7;
                    }
                }
                a.lmin = if side { 0 } else { 7 - tn };
                a.lmax = if side { tn } else { 8 };
                tag_from(&mut a, age, 56);
                for c in 0..3 {
                    let ts = 96 + 14 * c as i32;
                    if age < ts {
                        let tv = (ts - age) * 10;
                        a.cdx[c] = if side { tv } else { -tv };
                        a.cap[c] = tv < 200;
                        a.cname[c] = false;
                        let tm = 10 + (ts - age) * 20;
                        let tw = if side {
                            112 + 80 * (c as i32 - 1)
                        } else {
                            112 - 80 * (c as i32 - 1)
                        };
                        if age >= 76 && tm <= tw {
                            a.shot[c] = true;
                            a.shx[c] = W / 2 - 80 + 80 * c as i32 + if side { -tm } else { tm } - 3;
                            a.shy[c] = INTRO_CAP_Y + 6;
                        }
                    } else {
                        a.cinv[c] = age < ts + 4;
                    }
                }
                a.first = age >= 150;
            }
            K_RUSH => {
                let tt = (age - 30) & 255;
                let tv = match tt {
                    0 => 127,
                    1 => 85,
                    2 => 42,
                    _ => 0,
                };
                a.name = age >= 30;
                a.ndx = if side { -tv } else { tv };
                a.ghost = age >= 30 && tt < 12;
                a.gdx = if side { -((170 + tv) >> 1) } else { (170 + tv) >> 1 };
                a.nacc = (34..36).contains(&age);
                let tt = (age - 44) & 255;
                let tv = match tt {
                    0 => 113,
                    1 => 57,
                    _ => 0,
                };
                a.tag = age >= 44;
                a.tdx = if side { -tv } else { tv };
                for c in 0..3 {
                    let ts = 58 + 6 * c as i32;
                    let tt = (age - ts) & 255;
                    let tm = if side { 100 + 80 * c as i32 } else { 260 - 80 * c as i32 };
                    let tv = match tt {
                        0 => (tm * 21) >> 5,
                        1 => (tm * 11) >> 5,
                        _ => 0,
                    };
                    a.cap[c] = age >= ts;
                    a.cdx[c] = if side { -tv } else { tv };
                    a.cinv[c] = age >= ts && (3..5).contains(&tt);
                    a.cname[c] = age >= ts && tt >= 3;
                }
                a.first = age >= 90;
            }
            K_GUARDIAN => {
                a.wx = ax(18);
                for q in 0..5 {
                    let ts = 10 + 8 * q as i32;
                    let tt = (age - ts) & 255;
                    let tv = WALL_TOP + 14 * (4 - q as i32);
                    a.wall[4 - q] = age >= ts;
                    a.wy[4 - q] = if age >= ts && tt < 5 {
                        -15 + (((tv + 15) * fall_q(tt)) >> 8)
                    } else {
                        tv
                    };
                }
                a.wflash = (82..90).contains(&age) && age & 2 == 0;
                if (52..82).contains(&age) {
                    a.ball = true;
                    a.bx = ax(-162 + (age - 52) * 6) - 2;
                    a.by = WALL_TOP + 4;
                } else if (82..112).contains(&age) {
                    a.ball = true;
                    a.bx = ax(16 - (age - 82) * 6) - 2;
                    a.by = WALL_TOP + 4;
                }
                for q in 0..8 {
                    let ts = 96 + 3 * q as i32;
                    let tt = (age - ts) & 255;
                    a.lshow[q] = age >= ts;
                    a.ldy[q] = if age >= ts && tt < 5 {
                        -((79 * (256 - fall_q(tt))) >> 7)
                    } else {
                        0
                    };
                }
                tag_from(&mut a, age, 130);
                for c in 0..3 {
                    let ts = 152 + 10 * c as i32;
                    a.cap[c] = age >= ts;
                    a.cname[c] = age >= ts;
                    a.cinv[c] = age >= ts && age < ts + 4;
                }
                a.first = age >= 190;
            }
            _ => {}
        }
        a
    }
}

/// Racchetta dell'avversario (ip_* di next_render): spostamento, altezza, inclinazione, lampo,
/// immagini dello scatto del RUSH.
struct Paddle {
    dx: i32,
    dy: i32,
    h: i32,
    tilt: i32,
    flash: bool,
    show: bool,
    fade: i32,
    gx: [i32; 4],
}

impl Paddle {
    fn new(age: i32, kind: u32) -> Self {
        let mut p = Paddle {
            dx: 0,
            dy: 0,
            h: KIND_H[kind as usize],
            tilt: 0,
            flash: false,
            show: true,
            fade: 0,
            gx: [0; 4],
        };
        match kind {
            K_ARCADE => {
                let m = ((age - 30) & 255) * 43;
                let k = if age < 30 {
                    0
                } else if age >= 84 {
                    10
                } else {
                    ((m >> 8) & 15) + 1
                };
                if age < 10 {
                    p.dy = 0;
                } else if k < 10 {
                    let y0 = if k == 0 { 0 } else { arcade_dy(k - 1) };
                    let y1 = arcade_dy(k);
                    let t = if k == 0 {
                        (age - 10) & 255
                    } else {
                        (age - (24 + (k << 2) + (k << 1))) & 255
                    };
                    p.dy = if t >= 4 { y1 } else { y0 + (((y1 - y0) * t) >> 2) };
                } else {
                    let t = (age - 84) & 255;
                    p.dy = if t >= 8 { 0 } else { (arcade_dy(9) * (8 - t)) >> 3 };
                }
                let mm = 6 * ((m >> 8) & 15);
                p.flash = (30..86).contains(&age) && (((age - 30) - mm) & 255) < 2;
            }
            K_TWIST => {
                if (6..66).contains(&age) {
                    let t = age - 6;
                    let amp = 22 - ((t * 3) >> 3);
                    let i = ((t * 57) >> 4) & 63;
                    p.dy = (amp * SIN_Q8[i as usize]) >> 8;
                    let y0 = -((amp * SIN_Q8[((i + 16) & 63) as usize]) >> 10);
                    p.tilt = y0.clamp(-3, 3);
                }
            }
            K_HAMMER => {
                if (40..48).contains(&age) {
                    p.dx = age - 39;
                } else if (49..55).contains(&age) {
                    p.dx = if age <= 50 { -8 } else { -8 + ((age - 50) << 1) };
                }
            }
            K_TITAN => {
                p.show = age >= 6;
                let t = if age < 6 { 0 } else { (((age - 6) * 11) >> 5) + 1 };
                if t < 24 {
                    p.h = t << 1;
                    p.dy = 24 - t;
                }
                p.flash = (78..82).contains(&age);
            }
            K_BLASTER => {
                p.show = age >= 4;
                p.dx = 120;
                p.dy = if age < 64 {
                    41
                } else if age >= 73 {
                    78
                } else {
                    41 + ((age - 64) << 2)
                };
            }
            K_RUSH => {
                if age < 16 {
                    let t = (age * 11) >> 5;
                    p.show = age >= 4 && t & 1 == 0;
                    p.dx = 140;
                } else {
                    let t = age - 16;
                    p.dx = if t >= 3 { 0 } else { 105 - t * 35 };
                    let y1 = p.dx;
                    p.gx = [
                        0,
                        140 - ((140 - y1) >> 2),
                        140 - ((140 - y1) >> 1),
                        140 - (((140 - y1) * 3) >> 2),
                    ];
                    p.fade = if t < 4 {
                        3
                    } else if t < 10 {
                        2
                    } else if t < 16 {
                        1
                    } else {
                        0
                    };
                }
            }
            K_GUARDIAN => {
                p.show = age >= 4;
                p.dx = -10;
            }
            _ => {}
        }
        p
    }
}

/// Scossa dello schermo (intro_sx, intro_sy di pong_top).
#[inline(never)]
fn shake(kind: u32, age: i32) -> (i32, i32) {
    match kind {
        K_HAMMER => match age {
            49 => (3, 0),
            50 => (-3, 2),
            51 => (3, -2),
            52 => (-2, 1),
            53 => (2, -1),
            54 => (-1, 0),
            55 => (1, 0),
            72 => (0, 3),
            73 => (0, -2),
            74 => (0, 2),
            75 => (0, -1),
            76 => (0, 1),
            _ => (0, 0),
        },
        K_TITAN if matches!(age, 6 | 18 | 30 | 42 | 54 | 66) => (0, 1),
        K_GUARDIAN => (
            if age == 82 { 2 } else { 0 },
            if matches!(age, 14 | 22 | 30 | 38 | 46) { 1 } else { 0 },
        ),
        _ => (0, 0),
    }
}

/// Oggetto spostato della scossa (anche il ritaglio: quello che esce dallo schermo resta nero).
#[inline(never)]
fn sh(o: Obj, s: (i32, i32)) -> Obj {
    let mut o = o;
    o.x += s.0;
    o.y += s.1;
    o.clip = [o.clip[0] + s.0, o.clip[1] + s.0, o.clip[2] + s.1, o.clip[3] + s.1];
    o
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    if Omega::new(r).warn {
        crate::omega::warning(r, d);
        return;
    }
    let ch = Ch::new(r);
    let omega = ch.level == OMEGA_LEVEL;
    // la presentazione di OMEGA dura 315 frame: il frame del modo senza il limite a 255
    let age = if omega { r.frame.min(511) } else { intro_age(r) };
    let kind = ch.kind;
    let side = ch.side;
    let a = Anim::new(age, kind, ch.level, side);
    let s = shake(kind, age);
    let coin = !r.free_play && r.credits == 0;
    d.class = CLASS_A;
    d.rect(0, 0, W, 240, BLACK);
    // tutto passa da qui: gli oggetti si spostano con la scossa
    let rect = |d: &mut Dl, x: i32, y: i32, w: i32, h: i32, c: u8| {
        let mut o = Obj::new(crate::dl::Kind::Rect, x, y, w, h);
        o.ca = c;
        o.class = d.class;
        d.push(&sh(o, s));
    };
    let text = |d: &mut Dl, x: i32, y: i32, t: &[u8], c: u8| {
        let base = d.tiles(t, c);
        let o = d.text_obj(x, y, base, t.len(), 0);
        d.push(&sh(o, s));
    };
    let cells = |d: &mut Dl, x: i32, y: i32, cs: &[(u8, u8)]| {
        let base = d.codes(cs);
        let o = d.text_obj(x, y, base, cs.len(), 0);
        d.push(&sh(o, s));
    };

    // titolo: LEVEL n OF 7 (FINAL LEVEL), nell'allenamento TRAINING
    if a.title {
        let lv = [
            b'L',
            b'E',
            b'V',
            b'E',
            b'L',
            b' ',
            b'1' + ch.level as u8,
            b' ',
            b'O',
            b'F',
            b' ',
            b'7',
        ];
        let t: &[u8] = if ch.train {
            b"TRAINING"
        } else if omega {
            b"SECRET LEVEL"
        } else if ch.level == 6 {
            b"FINAL LEVEL"
        } else {
            &lv
        };
        text(d, (W - text_w(t)) / 2, 20, t, ACCENT);
    }
    // la scala dei livelli
    for j in 0..7 {
        if j < a.lad {
            let c = if (j as u32) < ch.level && !ch.train {
                WHITE
            } else if j as u32 == ch.level && age & 8 == 0 {
                ACCENT
            } else {
                DIM
            };
            rect(d, 76 + 24 * j, 34, 16, 4, c);
        }
    }
    // nome: immagine gialla dietro (RUSH), poi il nome spostato, inclinato, a lettere
    let img = if omega {
        &IMG_NAME_OMEGA
    } else {
        &IMG_NAME[kind as usize]
    };
    let (nw, nh) = (img.w as i32, img.h as i32);
    // il sigillo di OMEGA (33 righe) sta più in basso, sotto la racchetta
    let top = if omega {
        OMEGA_NAME_TOP
    } else if kind == K_TITAN {
        TITAN_TOP
    } else {
        NAME_BASE - nh
    };
    let nx = (W - nw) / 2 + a.ndx;
    let ny = top + a.ndy;
    if a.ghost {
        let o = d.img_obj((W - nw) / 2 + a.gdx, top, img, TL_GHOST);
        d.push(&sh(o, s));
    }
    if a.name {
        let pal = if omega {
            if a.nacc { TL_WHITE } else { TL }
        } else if a.nacc {
            TL_HI
        } else {
            TL
        };
        let ground = if a.ground { NAME_GROUND } else { 240 };
        if kind == K_GUARDIAN && !omega {
            for q in 0..8 {
                if !a.lshow[q] {
                    continue;
                }
                let u0 = GUARDIAN_X[q];
                let u1 = if q == 7 { nw } else { GUARDIAN_X[q + 1] };
                let mut o = d.img_obj(nx + u0, ny + a.ldy[q], img, pal);
                o.u0 = u0;
                o.w = u1 - u0;
                d.push(&sh(o.clip(0, 320, 0, ground), s));
            }
        } else if kind == K_BLASTER && !omega && (a.lmin > 0 || a.lmax < 8) {
            // lettere accese da lmin a lmax: il confine segue il corsivo, una riga alla volta
            let lx = |j: i32| {
                if j <= 0 {
                    -1000
                } else if j >= 7 {
                    1000
                } else {
                    game::BLASTER_X0 + game::BLASTER_STEP * j
                }
            };
            for v in 0..nh {
                let sl = BLASTER_SLANT[v as usize];
                let o =
                    d.img_obj(nx, ny, img, pal)
                        .clip(nx + lx(a.lmin) + sl, nx + lx(a.lmax) + sl, ny + v, ny + v + 1);
                d.push(&sh(o.clip(0, 320, 0, ground), s));
            }
        } else {
            let mut o = d.img_obj(nx, ny, img, pal);
            if a.shear != 0 {
                let mut dx = [0i32; 32];
                for (j, v) in dx.iter_mut().enumerate().take(nh as usize) {
                    *v = twist_dx(a.shear, j as i32 - 10);
                }
                o.lt = Some(d.lines(&dx[..nh as usize]));
            }
            d.push(&sh(o.clip(0, 320, 0, ground), s));
        }
    }
    if a.gline {
        rect(d, W / 2 - nw / 2 - 8, NAME_GROUND, nw + 16, 1, DIM);
    }
    // motto, scritto a colonne o spostato (RUSH)
    if a.tag {
        let t = if omega {
            OMEGA_TAG
        } else {
            game::KIND_TAGS[kind as usize]
        };
        let x = (W - text_w(t)) / 2 + a.tdx;
        let ty = if omega {
            OMEGA_NAME_TOP + nh + 3
        } else {
            (if kind == K_TITAN { NAME_GROUND } else { NAME_BASE }) + 4
        };
        let base = d.tiles(t, GRAY);
        let o = d.text_obj(x, ty, base, t.len(), 0).clip(0, x + a.tcols, 0, 240);
        d.push(&sh(o, s));
    }
    // i bonus dell'avversario: capsule (lato 13, icona 9x9) e nomi sotto, su tre colonne
    for j in 0..3 {
        if !a.cap[j] {
            continue;
        }
        let x = W / 2 - 86 + 80 * j as i32 + a.cdx[j];
        let y = INTRO_CAP_Y + a.cdy[j];
        let b = (ch.loadout >> (3 * j)) & 7;
        if a.cinv[j] {
            rect(d, x, y, INTRO_CAP, INTRO_CAP, ACCENT);
            let o = d.img_obj(x + 2, y + 2, &IMG_ICON[b as usize], BLACK);
            d.push(&sh(o, s));
        } else {
            rect(d, x, y, INTRO_CAP, 1, ACCENT);
            rect(d, x, y + INTRO_CAP - 1, INTRO_CAP, 1, ACCENT);
            rect(d, x, y, 1, INTRO_CAP, ACCENT);
            rect(d, x + INTRO_CAP - 1, y, 1, INTRO_CAP, ACCENT);
            let o = d.img_obj(x + 2, y + 2, &IMG_ICON[b as usize], ACCENT);
            d.push(&sh(o, s));
        }
    }
    for j in 0..3 {
        if !a.cname[j] {
            continue;
        }
        let b = ((ch.loadout >> (3 * j)) & 7) as usize;
        let t = game::BONUS_NAMES[b];
        let cx = 80 + 80 * j as i32;
        let (x0, x1) = [(0, 120), (120, 200), (200, 320)][j];
        let base = d.tiles(t, ACCENT);
        let o = d
            .text_obj(cx - text_w(t) / 2, INTRO_CAP_Y + INTRO_CAP + 3, base, t.len(), 0)
            .clip(x0, x1, 0, 240);
        d.push(&sh(o, s));
    }
    // FIRST TO n
    let pts = ch.points as i32;
    let tens = if pts >= 30 {
        3
    } else if pts >= 20 {
        2
    } else if pts >= 10 {
        1
    } else {
        0
    };
    let units = pts - 10 * tens;
    let first_x = if tens != 0 {
        (W - (63 + 1 + 3 * C)) / 2
    } else {
        (W - (63 + 1 + 2 * C)) / 2
    };
    if a.first {
        text(d, first_x, INTRO_FIRST_Y, b"FIRST TO", GRAY);
    }
    // mezzeria e raffica (ARCADE), scia e palla, colpi (BLASTER), polvere (HAMMER), muro (GUARDIAN)
    if a.net {
        // trattini: righe con (y - (IP_Y - 28)) * 43 / 256 pari
        let mut y = IP_Y - 28;
        while y < IP_Y + 32 {
            let on = |y: i32| ((y - (IP_Y - 28)) * 43) & 256 == 0;
            if on(y) {
                let y0 = y;
                while y < IP_Y + 32 && on(y) {
                    y += 1;
                }
                rect(d, a.netx, y0, 2, y - y0, WHITE);
            } else {
                y += 1;
            }
        }
    }
    for j in 0..4 {
        if a.son[j] {
            rect(d, a.sx[j], a.sy[j], 8, 1, ACCENT);
            rect(d, a.sx[j], a.sy[j] + 7, 8, 1, ACCENT);
            rect(d, a.sx[j], a.sy[j] + 1, 1, 6, ACCENT);
            rect(d, a.sx[j] + 7, a.sy[j] + 1, 1, 6, ACCENT);
        }
    }
    for j in 0..3 {
        if a.trail[j] {
            rect(d, a.tx[j], a.by, 4, 4, [TRAIL1, TRAIL2, TRAIL3][j]);
        }
    }
    if a.ball {
        rect(d, a.bx, a.by, 4, 4, WHITE);
    }
    for j in 0..3 {
        if a.shot[j] {
            rect(d, a.shx[j], a.shy[j] - 4, 6, 1, ACCENT);
            rect(d, a.shx[j], a.shy[j] + 3, 6, 1, ACCENT);
        }
    }
    if a.dust {
        for j in 0..4 {
            rect(d, a.ux[j], a.uy[j], 2, 2, GRAY);
        }
    }
    for j in 0..5 {
        if a.wall[j] {
            let c = if j == 0 && a.wflash { WHITE } else { ACCENT };
            for (r0, r1) in [(0, 3), (4, 7), (8, 11)] {
                rect(d, a.wx, a.wy[j] + r0, 2, r1 - r0, c);
            }
        }
    }
    if !ch.train {
        text(d, 24, 216, b"SCORE", WHITE);
        text(d, 192, 216, b"HI", WHITE);
    }
    // contro OMEGA non entrano sfidanti
    let join = ch.active && !ch.duel && !ch.train && !omega && r.blink < 30;
    if join && coin {
        text(d, if side { 80 - 43 } else { 240 - 43 }, 2, b"INSERT COIN", WHITE);
    }
    let join_x = if side { 80 - 55 } else { 240 - 55 };
    if join && !coin {
        text(d, join_x + 3 * C, 2, b"PRESS START", WHITE);
    }
    // celle del font (sopra il resto della schermata)
    if a.first {
        if tens != 0 {
            cells(
                d,
                first_x + 64 + C,
                INTRO_FIRST_Y,
                &[(tens as u8, GRAY), (units as u8, GRAY)],
            );
        } else {
            cells(d, first_x + 64 + C, INTRO_FIRST_Y, &[(units as u8, GRAY)]);
        }
    }
    if !ch.train {
        let sd = dec7(ch.score);
        let hi = bcd7(r.w[9] & 0x0FFF_FFFF);
        let sc: [(u8, u8); 7] = core::array::from_fn(|k| (sd[k], WHITE));
        let hc: [(u8, u8); 7] = core::array::from_fn(|k| (hi[k], WHITE));
        cells(d, 24 + 39 + 1 + C, 216, &sc);
        cells(d, 192 + 15 + 1 + C, 216, &hc);
    }
    if join && !coin {
        cells(d, join_x, 2, &[(code(b'P'), WHITE), (if side { 1 } else { 2 }, WHITE)]);
    }
    crate::challenge::wins(&ch, d);

    // la racchetta dell'avversario, sopra a tutto (rivolta verso il giocatore)
    if omega {
        omega_paddle(r, d, age, side);
        return;
    }
    let p = Paddle::new(age, kind);
    let kcx = W / 2 + if side { -p.dx } else { p.dx };
    let top = IP_Y + p.dy - (p.h >> 1);
    // RUSH: le tre immagini dello scatto, più scure verso la partenza (sotto la racchetta)
    if p.fade != 0 {
        for k in 1..4 {
            if p.fade + k >= 4 {
                let c = if p.fade + k >= 6 {
                    PGHOST3
                } else if p.fade + k == 5 {
                    PGHOST2
                } else {
                    PGHOST1
                };
                let gx = W / 2 + if side { -p.gx[k as usize] } else { p.gx[k as usize] } - PW / 2;
                rect(d, gx, top, PW, p.h, c);
            }
        }
    }
    if p.show {
        let colors = Colors {
            body: if p.flash { ACCENT } else { WHITE },
            mark: ACCENT,
            detail: DETAIL,
            ghost: [PGHOST1, PGHOST2, PGHOST3],
            pattern: false,
        };
        let pad = Pad {
            kind,
            xa: kcx - PW / 2 + s.0,
            xb: kcx - PW / 2 + PW - 1 + s.0,
            right: side,
            y: top + s.1,
            h: p.h,
            tilt: p.tilt,
            preview: false,
            ghosts: false,
            half: false,
        };
        pad.draw(d, &colors);
    }
    // BLASTER: il caricatore pieno dietro la racchetta, dal basso (2 colonne a 3-4 pixel dal retro)
    if kind == K_BLASTER {
        let kh = KIND_H[kind as usize];
        for j in 0..game::BLASTER_SHOTS {
            let r0 = kh - 4 - 4 * j;
            let x = if side {
                kcx - PW / 2 - 4
            } else {
                kcx - PW / 2 + PW - 1 + 3
            };
            rect(d, x, top + r0, 2, 3, ACCENT);
        }
    }
}

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
fn bcd7(v: u32) -> [u8; 7] {
    core::array::from_fn(|i| ((v >> (4 * (6 - i))) & 15) as u8)
}

/// OMEGA: la racchetta rossa (viola con l'easter egg) che da OMEGA_FORMS_AT passa per le sette forme
/// della scala, una ogni OMEGA_FORM_FRAMES con un lampo bianco a ogni cambio (metà per le forme, intero
/// all'ultimo), poi resta ARCADE.
#[inline(never)]
fn omega_paddle(r: &Regs, d: &mut Dl, age: i32, side: bool) {
    let since = age - OMEGA_FORMS_AT;
    if since < 0 {
        return;
    }
    let step = since / OMEGA_FORM_FRAMES;
    let kind = if step < 7 { LADDER[step as usize] } else { K_ARCADE };
    let changed = since - step.min(7) * OMEGA_FORM_FRAMES;
    let flash = if step < 7 { OMEGA_FLASH / 2 } else { OMEGA_FLASH };
    let h = KIND_H[kind as usize];
    let colors = Colors {
        body: if changed < flash {
            WHITE
        } else {
            crate::omega::body(r.egg)
        },
        mark: ACCENT,
        detail: DETAIL,
        ghost: [PGHOST1, PGHOST2, PGHOST3],
        pattern: false,
    };
    let pad = Pad {
        kind,
        xa: W / 2 - PW / 2,
        xb: W / 2 - PW / 2 + PW - 1,
        right: side,
        y: IP_Y - (h >> 1),
        h,
        tilt: 0,
        preview: false,
        ghosts: false,
        half: false,
    };
    pad.draw(d, &colors);
}
