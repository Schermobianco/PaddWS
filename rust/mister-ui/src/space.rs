//! Sfondo spaziale dietro la scelta della racchetta, la scelta dei bonus e lo schermo VS (come
//! `rust/game/src/space.rs`, ma con meno stelle: gli oggetti sono 128 in tutto): il cielo visto da una
//! navicella. Le stelle bianche scorrono piano dal centro verso i bordi, più grandi e luminose quando si
//! avvicinano; tutto il cielo rolla di qualche grado a destra e a sinistra; ogni tanto una stella cadente
//! attraversa lo schermo con la coda nel colore dello sfidante (un'immagine per angolo, specchiata se serve).
//!
//! Dipende solo dal frame (il ciclo è di 1024 frame, che divide il conteggio a 11 bit dei registri: niente
//! salti quando ricomincia). Le tabelle sono generate da `tools/gen_mister_ui.py`.

use crate::assets::{IMG_STREAK, space};
use crate::dl::Dl;
use crate::pal::{PORTRAIT, TRAIL1, TRAIL2, TRAIL3, WHITE};

/// Centro del cielo nello schermo.
const CX: i32 = 160;
const CY: i32 = 120;

/// Disegna il cielo e la stella cadente in corso, da chiamare per primo (sono sotto a tutto). `frame` è
/// il frame del modo, `who` il personaggio di cui la coda ha il colore (0-7).
#[inline(never)]
pub fn draw(d: &mut Dl, frame: i32, who: usize) {
    let t = frame & 1023;
    // rollio: sin(angolo) x 256, al più 31 (circa 7 gradi); coseno 1
    let roll = i32::from(space::ROLL[(t >> 4) as usize]);
    for i in 0..space::STARS {
        // fase della stella nel suo avvicinamento (0..255) e raggio dalla tabella di 300 * u^1.5
        let u = ((i32::from(space::PHASE[i]) + (t >> 2)) & 255) as usize;
        let r = i32::from(space::POW15[u]);
        let x = (r * i32::from(space::COS[i])) >> 7;
        let y = (r * i32::from(space::SIN[i])) >> 7;
        let (x, y) = (x - ((y * roll) >> 8), y + ((x * roll) >> 8));
        let size = if u > 240 {
            3
        } else if u > 210 {
            2
        } else {
            1
        };
        let (px, py) = (CX + x, CY + y);
        if px < 0 || py < 0 || px + size > 320 || py + size > 240 {
            continue;
        }
        let color = if u > 174 {
            WHITE
        } else if u > 81 {
            TRAIL1
        } else if u > 26 {
            TRAIL2
        } else {
            TRAIL3
        };
        d.rect(px, py, size, size, color);
    }
    shooting(d, t, who);
}

/// La stella cadente del ciclo che sta passando: l'immagine della sua scia con la testa nel punto in cui è.
#[inline(never)]
fn shooting(d: &mut Dl, t: i32, who: usize) {
    for s in &space::SHOOTING {
        let age = t - s.start;
        if !(0..space::SHOOT_FRAMES).contains(&age) {
            continue;
        }
        // la testa: una frazione del percorso lungo la sua direzione
        let step = s.length * age / space::SHOOT_FRAMES;
        let (hx, hy) = (CX + s.x0 + ((s.dx * step) >> 8), CY + s.y0 + ((s.dy * step) >> 8));
        let img = &IMG_STREAK[s.streak];
        let (w, h) = (i32::from(img.w), i32::from(img.h));
        // la testa è 2x2 nell'angolo in basso a destra dell'immagine; specchiata, nell'angolo opposto
        let ox = if s.flip_x { hx } else { hx - (w - 2) };
        let oy = if s.flip_y { hy } else { hy - (h - 2) };
        let mut o = d.img_obj(ox, oy, img, PORTRAIT + 8 * who as u8);
        o.fx = s.flip_x;
        o.fy = s.flip_y;
        d.push(&o);
    }
}
