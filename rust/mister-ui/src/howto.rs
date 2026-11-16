//! Schermata HOW TO PLAY delle mosse speciali (come il vecchio howto_render.v): scritte (righe intere
//! della ROM, scelte per riga con la tabella delle righe), figurine 32x32 e, sotto, cornici, racchetta,
//! palla e freccette. Animazione a ciclo continuo: i passi del gesto si accendono uno dopo l'altro, poi
//! il pulsante A si abbassa e la palla parte, poi una pausa.

use crate::Img;
use crate::assets::howto as ht;
use crate::assets::{
    IMG_HT_ARROW, IMG_HT_SPRITE_0, IMG_HT_SPRITE_1, IMG_HT_SPRITE_2, IMG_HT_SPRITE_3, IMG_HT_SPRITE_4, IMG_HT_SPRITE_5,
    IMG_HT_SPRITE_6, IMG_HT_SPRITE_7, IMG_HT_SPRITE_8, IMG_HT_SPRITE_9,
};
use crate::dl::{CLASS_A, Dl, Kind, Obj};
use crate::pal::{ACCENT, BLACK, HT_FRAME, HT_GRAY, HT_SPR, HT_SPR_LIT, HT_TEXT, HT_TRAIL, WHITE};
use crate::regs::{Regs, field};

const SPRITES: [Img; 10] = [
    IMG_HT_SPRITE_0,
    IMG_HT_SPRITE_1,
    IMG_HT_SPRITE_2,
    IMG_HT_SPRITE_3,
    IMG_HT_SPRITE_4,
    IMG_HT_SPRITE_5,
    IMG_HT_SPRITE_6,
    IMG_HT_SPRITE_7,
    IMG_HT_SPRITE_8,
    IMG_HT_SPRITE_9,
];
const STICK_D: usize = 0;
const STICK_DF: usize = 1;
const STICK_F: usize = 2;
const SPIN_D: usize = 3;
const SPIN_U: usize = 4;
const BTN_A: usize = 5;
const BTN_A_DOWN: usize = 6;

const STEP_F: i32 = 13;
const FLIGHT_F: i32 = 53;
const IDLE_F: i32 = 53;
const SHOT_X: i32 = 212;
const SHOT_END: i32 = 299;
const RISE_X: i32 = 256;

#[inline(never)]
fn rise_of(c: i32) -> i32 {
    if c <= RISE_X {
        0
    } else if c - RISE_X >= 14 {
        14
    } else {
        (c & 15) - (RISE_X & 15)
    }
}

#[inline(never)]
pub fn draw(r: &Regs, d: &mut Dl) {
    let control = field(r.w[7], 27, 2);
    let knob = control != 0;
    let press = if knob { 2 * STEP_F } else { 3 * STEP_F };
    let t = r.frame % (press + FLIGHT_F + IDLE_F);
    let s_now = if t < STEP_F {
        0
    } else if t < 2 * STEP_F {
        1
    } else if t < 3 * STEP_F {
        2
    } else if t < 4 * STEP_F {
        3
    } else {
        4
    };
    let flying = t < press + FLIGHT_F;
    let ts = (t - press) & 255;
    let ts11 = (((ts & 127) << 3) + (ts << 1) + ts) & 1023;
    let ball_now = (SHOT_X + 8 + (ts11 >> 2)) & 511;
    let step_lit = if flying && s_now <= if knob { 2 } else { 3 } {
        s_now
    } else {
        7
    };
    let done = if flying { s_now } else { 0 };
    let ball_on = flying && t >= press && ball_now < SHOT_END;
    let trail_on = ball_on && ball_now > SHOT_X + 10;

    d.class = CLASS_A;
    d.rect(0, 0, 320, 240, BLACK);
    // ---- strato in logica, nei due riquadri
    for (b, (by, cy)) in [(ht::BOX0_Y, ht::CY0), (ht::BOX1_Y, ht::CY1)].into_iter().enumerate() {
        // le righe di un riquadro (b = 1 il secondo, da y = 108 in giù)
        let band = if b == 0 {
            (by - 4, (by + 63).min(108))
        } else {
            ((by - 4).max(108), by + 63)
        };
        let old = d.clip;
        d.clip = [0, 320, band.0, band.1];
        d.rect(8, by - 4, 304, 1, HT_FRAME);
        d.rect(8, by + 62, 304, 1, HT_FRAME);
        d.rect(8, by - 4, 1, 67, HT_FRAME);
        d.rect(311, by - 4, 1, 67, HT_FRAME);
        // riquadro del tiro (righe dy da cy - 18) e racchetta
        let y0 = cy - 18;
        d.rect(204, y0, 99, 1, HT_FRAME);
        d.rect(204, y0 + 30, 99, 1, HT_FRAME);
        d.rect(204, y0, 1, 31, HT_FRAME);
        d.rect(302, y0, 1, 31, HT_FRAME);
        d.rect(208, y0 + 10, 3, 13, WHITE);
        if b == 0 {
            // STRAIGHT SHOT: tre righe di velocità dietro la palla
            if trail_on && ball_now - 4 >= SHOT_X {
                for dy in [14, 16, 18] {
                    d.rect(SHOT_X, y0 + dy, ball_now - 4 - SHOT_X + 1, 1, ACCENT);
                }
            }
            if ball_on {
                d.rect(ball_now, y0 + 15, 3, 3, ACCENT);
            }
        } else {
            // RISING STRIKE: tre punti di scia, poi la palla che s'impenna
            if ball_on {
                for i in 0..3 {
                    let c = ball_now - 4 * (i + 1);
                    if (c & 511) > SHOT_X {
                        d.rect((c + 1) & 511, y0 + 16 - rise_of(c & 511), 1, 1, HT_TRAIL);
                    }
                }
                let rise = rise_of(ball_now);
                d.rect(ball_now, y0 + 15 - rise, 3, 3, ACCENT);
            }
        }
        // freccette tra i passi, gialle quando il passo prima è fatto
        let ay = cy - 3;
        let o = d.img_obj(
            ht::JOY_S0 + ht::ARROW_DX,
            ay,
            &IMG_HT_ARROW,
            if done > 0 { ACCENT } else { HT_GRAY },
        );
        d.push(&o);
        if !knob {
            let o = d.img_obj(
                ht::JOY_S1 + ht::ARROW_DX,
                ay,
                &IMG_HT_ARROW,
                if done > 1 { ACCENT } else { HT_GRAY },
            );
            d.push(&o);
        }
        d.clip = old;
    }
    // ---- scritte: una riga della ROM per riga dello schermo; PRESS START TO SKIP lampeggia
    let rows = &ht::ROWS[(control as usize).min(2)];
    let mut lt = [0i32; 240];
    for (y, v) in lt.iter_mut().enumerate() {
        let skip = (y as i32) >= ht::SKIP_Y0 && (y as i32) < ht::SKIP_Y1 && r.blink >= 37;
        let row = if skip { ht::TEXT_ROWS } else { rows[y] as i32 };
        *v = 20 * row;
    }
    let base = d.lines(&lt);
    let mut o = Obj::new(Kind::Img, 0, 0, 320, 240);
    o.base = ht::TEXT_BASE;
    o.bpp = 1;
    o.lt = Some(base);
    o.ltrow = true;
    o.ca = HT_TEXT;
    o.class = d.class;
    d.push(&o);
    // ---- figurine: i passi del gesto nei due riquadri, il pulsante A, la legenda
    let slot = |d: &mut Dl, cx: i32, cy: i32, id: usize, lit: bool| {
        let mut o = d.img_obj(
            cx - ht::AX,
            cy - ht::AY,
            &SPRITES[id],
            if lit { HT_SPR_LIT } else { HT_SPR },
        );
        o.w = ht::SLOT_W;
        d.push(&o);
    };
    for c1 in [false, true] {
        let cy = if c1 { ht::CY1 } else { ht::CY0 };
        slot(
            d,
            ht::JOY_S0,
            cy,
            if knob {
                if c1 { SPIN_U } else { SPIN_D }
            } else if c1 {
                STICK_F
            } else {
                STICK_D
            },
            step_lit == 0,
        );
        slot(
            d,
            ht::JOY_S1,
            cy,
            if knob {
                if c1 { SPIN_D } else { SPIN_U }
            } else if c1 {
                STICK_D
            } else {
                STICK_DF
            },
            step_lit == 1,
        );
        if !knob {
            slot(d, ht::JOY_S2, cy, if c1 { STICK_DF } else { STICK_F }, step_lit == 2);
        }
        let a = if step_lit == if knob { 2 } else { 3 } {
            BTN_A_DOWN
        } else {
            BTN_A
        };
        slot(d, if knob { ht::KNOB_A } else { ht::JOY_A }, cy, a, false);
    }
    slot(d, ht::LEG_X0, ht::LEG_CY, 7, false);
    slot(d, ht::LEG_X1, ht::LEG_CY, 8, false);
    slot(d, ht::LEG_X2, ht::LEG_CY, 9, false);
}
