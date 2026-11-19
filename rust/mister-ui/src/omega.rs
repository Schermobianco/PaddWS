//! OMEGA, il boss segreto dopo la scala (rust/game/src/challenge_ui.rs, next_ui.rs, scope.rs): l'allarme
//! prima della presentazione, la rete che segue la voce 2 del SID, il nome della forma nuova a ogni
//! trasformazione, la racchetta che si spezza prima del finale speciale.
//!
//! La racchetta rossa in partita, il suo lampo e la rete stessa sono di next_render e pong_render:
//! qui si calcolano solo gli spostamenti dei trattini (scritti in pong_top, `map::NET`).

use crate::assets::{IMG_NAME, IMG_WARNING};
use crate::dl::{CLASS_A, CLASS_C, Dl, Kind, Obj};
use crate::map;
use crate::cast::plain_paddle;
use crate::pal::{BLACK, RED, TL, WHITE};
use crate::regs::{Omega, Regs};

const W: i32 = 320;

/// Allarme (Warning di challenge_ui.rs): la targa accesa 30 frame e spenta 15, tre volte, poi ferma.
pub const WARNING_PERIOD: i32 = 45;
const WARNING_ON: i32 = 30;

/// La targa WARNING! al frame `age` dell'allarme è accesa.
pub fn warning_lit(age: i32) -> bool {
    age >= 3 * WARNING_PERIOD || age % WARNING_PERIOD < WARNING_ON
}

/// Schermo nero e la targa WARNING! al centro.
#[inline(never)]
pub fn warning(r: &Regs, d: &mut Dl) {
    d.class = CLASS_A;
    d.rect(0, 0, W, 240, BLACK);
    if warning_lit(r.frame.min(255)) {
        let img = &IMG_WARNING;
        d.img((W - img.w as i32) / 2, (240 - img.h as i32) / 2, img, TL);
    }
}


// ------------------------------------------------------------------ rete e oscilloscopi

/// Oscilloscopi (sid_scope): un campione ogni 1,024 ms, media di 1024 campioni a 1 MHz.
pub const SCOPE_LEN: usize = 256;
/// Finestra mostrata (120 ms) e ricerca dell'aggancio prima (50 ms), in campioni.
pub const WINDOW: usize = 117;
pub const SEARCH: usize = 49;
const HYSTERESIS_NUM: i32 = 1; // 0,1 del picco
const HYSTERESIS_DEN: i32 = 10;
/// Rete: 30 trattini, uno ogni 8 righe, al più 3 pixel di lato.
pub const NET_DASHES: usize = 30;
const NET_REACH: i32 = 3;
/// Ampiezza della voce 2 (16 bit della via diretta del SID, medie di 1 ms, musica al 100%) che porta
/// un trattino a NET_REACH: come NET_PEAK di scope.rs, il basso di OMEGA (un'onda quasi quadra di
/// circa ±2.900 nel simulatore dei frame, scenario "jukebox", OMEGA 1).
pub const NET_PEAK: i32 = 3000;

/// Guadagno della musica per il passo del volume dell'OSD (vol_gain di pong_sid.v), su 64.
pub fn music_gain(step: u32) -> i32 {
    [64, 52, 41, 31, 23, 16, 10, 6, 3, 1, 0]
        .get(step as usize)
        .copied()
        .unwrap_or(0)
}

/// Gli ultimi SEARCH + WINDOW campioni della voce `v` (0-2), dal più vecchio, meno la loro media: le
/// medie di 1 ms (la rete), o con `raw` un campione per posto senza media (gli oscilloscopi).
#[inline(never)]
pub fn read_voice(d: &mut Dl, wptr: u32, v: u32, raw: bool, out: &mut [i32; SEARCH + WINDOW]) {
    let n = SEARCH + WINDOW;
    let p = d.port();
    let mut sum = 0i32;
    for (k, o) in out.iter_mut().enumerate() {
        let at = (wptr + SCOPE_LEN as u32 - n as u32 + k as u32) & (SCOPE_LEN as u32 - 1);
        *o = p.read(map::SCOPE + ((raw as u32) << 10) + (v << 8) + at) as i32;
        sum += *o;
    }
    let mean = sum / n as i32;
    for o in out.iter_mut() {
        *o -= mean;
    }
}

/// Primo passaggio per lo zero in salita nei primi SEARCH campioni, con l'isteresi (0 se non c'è).
pub fn trigger(x: &[i32]) -> usize {
    let peak = x.iter().fold(0, |m, v| m.max(v.abs()));
    let th = peak * HYSTERESIS_NUM / HYSTERESIS_DEN;
    let mut armed = false;
    for (i, &v) in x.iter().enumerate().take(SEARCH) {
        if v < -th {
            armed = true;
        } else if armed && v >= 0 {
            return i;
        }
    }
    0
}

/// Spostamento di ciascun trattino dai campioni della voce 2 (net_offsets di scope.rs).
pub fn net_offsets(x: &[i32; SEARCH + WINDOW], peak: i32) -> [i32; NET_DASHES] {
    let mut out = [0; NET_DASHES];
    if peak <= 0 {
        return out;
    }
    let i0 = trigger(x);
    for (k, o) in out.iter_mut().enumerate() {
        // il centro del trattino, alla sua riga della finestra
        let i = i0 + (k * 8 + 2) * WINDOW / 240;
        let v = x[i.min(x.len() - 1)];
        let q = (v * NET_REACH * 2 + if v >= 0 { peak } else { -peak }) / (2 * peak);
        *o = q.clamp(-NET_REACH, NET_REACH);
    }
    out
}

/// Rete di OMEGA: legge la voce 2 e scrive gli spostamenti dei trattini (zero fuori da OMEGA, così la
/// rete torna quella di sempre). La musica spenta o a 0% lascia la rete ferma.
#[inline(never)]
pub fn net(r: &Regs, o: &Omega, d: &mut Dl) {
    let mut offs = [0i32; NET_DASHES];
    let gain = if o.music_off { 0 } else { music_gain(o.music_vol) };
    if o.level && gain > 0 && matches!(r.mode, crate::regs::M_GAME | crate::regs::M_GAME_OVER) {
        let mut x = [0i32; SEARCH + WINDOW];
        read_voice(d, o.scope_wptr, 1, false, &mut x);
        offs = net_offsets(&x, NET_PEAK * gain / 64);
    }
    let mut w = [0u32; 3];
    for (k, v) in offs.iter().enumerate() {
        w[k / 10] |= (*v as u32 & 7) << (3 * (k % 10));
    }
    d.port().write_block(map::NET, &w);
}

// ------------------------------------------------------------------ trasformazioni

/// Frame del nome della forma nuova (60) e del lampeggio finale (gli ultimi 10).
const NAME_FRAMES: i32 = 60;
const NAME_BLINK: i32 = 10;

/// A ogni trasformazione, per un secondo, il nome disegnato della forma nuova nella metà del campo di
/// OMEGA, al 30% dell'altezza (draw_morph_name di next_ui.rs): ruotato di 90 gradi nella modalità da
/// tavolo (il giocatore sta dall'altra parte: OMEGA a destra in senso orario, a sinistra antiorario),
/// dritto con le scritte dritte. Gli ultimi frame lampeggia.
#[inline(never)]
pub fn morph_name(r: &Regs, o: &Omega, d: &mut Dl, cpu_left: bool) {
    let age = o.morph_age;
    if !o.level || age >= NAME_FRAMES || (age >= NAME_FRAMES - NAME_BLINK && (age >> 1) & 1 == 0) {
        return;
    }
    let img = &IMG_NAME[o.kind.min(6) as usize];
    let (w, h) = (img.w as i32, img.h as i32);
    let (cx, cy) = (if cpu_left { W / 4 } else { 3 * W / 4 }, 72);
    d.class = CLASS_C;
    let mut ob = d.img_obj(cx - w / 2, cy - h / 2, img, TL);
    if !r.upright {
        // senso orario: scambio e specchio in x; antiorario: scambio e specchio in y
        ob.swap = true;
        ob.w = h;
        ob.h = w;
        ob.x = cx - h / 2;
        ob.y = cy - w / 2;
        if cpu_left {
            ob.fy = true;
        } else {
            ob.fx = true;
        }
    }
    d.push(&ob);
}

// ------------------------------------------------------------------ finale speciale

/// La racchetta di OMEGA che si spezza (Part::Shatter di ending_ui.rs, 240 frame): trema con lampi
/// sempre più fitti, a SHATTER_AT diventa bianca per 8 frame, poi le sette racchette della scala si
/// allontanano dal centro in tutte le direzioni, con qualche scheggia.
const SHATTER_AT: i32 = 72;
const SHATTER_FLASH: i32 = 8;
pub const SHATTER: i32 = 240;
/// Direzioni delle sette racchette (seno e coseno su 256, da -90 gradi, un settimo di giro l'una).
const DIRS: [(i32, i32); 7] = [
    (0, -256),
    (200, -160),
    (250, 57),
    (111, 231),
    (-111, 231),
    (-250, 57),
    (-200, -160),
];
/// Tipi della scala, nell'ordine dei livelli (PaddleKind).
const LADDER: [u32; 7] = [0, 3, 2, 1, 4, 5, 6];

#[inline(never)]
pub fn shatter(o: &Omega, d: &mut Dl) {
    let at = o.shatter;
    d.class = CLASS_A;
    d.rect(0, 0, W, 240, BLACK);
    let (cx, cy) = (W / 2, 120);
    // le racchette guardano a sinistra; OMEGA rossa (o viola), bianca nei lampi
    let pad = |d: &mut Dl, kind: u32, x: i32, y: i32, omega: bool| plain_paddle(d, kind, x, y, false, omega);
    if at < SHATTER_AT + SHATTER_FLASH {
        // trema avanti e indietro, di più verso la fine, con lampi sempre più fitti
        let k = at.min(SHATTER_AT);
        let dx = if at % 4 < 2 { 1 } else { -1 } * ((3 * k + SHATTER_AT / 2) / SHATTER_AT);
        let every = (16 - 12 * k / SHATTER_AT).max(2);
        let lit = at >= SHATTER_AT || (at > 24 && at % every == 0);
        pad(d, 0, cx + dx, cy, !lit);
        return;
    }
    // escono in fretta e rallentano: d = 1 - (1 - k)^2, k da 0 a 1 (su 256)
    let k = ((at - SHATTER_AT - SHATTER_FLASH) * 256 / (SHATTER - SHATTER_AT - SHATTER_FLASH)).min(256);
    let dd = 256 - (((256 - k) * (256 - k)) >> 8);
    let reach = 240;
    for (i, &(sx, sy)) in DIRS.iter().enumerate() {
        let x = cx + sx * reach / 256 * dd / 256;
        let y = cy + sy * reach / 256 * dd / 256 * 4 / 5;
        pad(d, LADDER[i], x, y, false);
    }
    // schegge: quadratini più veloci, che si diradano (rossi e bianchi)
    let mut seed = 0x0E6A_0001u32;
    for i in 0..24 {
        seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12345);
        let a = (seed >> 16) as i32 & 0xFF;
        seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12345);
        let speed = 154 + ((seed >> 16) as i32 & 0xFF) * 204 / 256;
        // direzione: un punto del giro su 256 passi, seno e coseno a tratti dalla tabella delle sette
        let (sx, sy) = DIRS[(a * 7 / 256) as usize];
        let dist = reach * 13 / 10 * speed / 256 * dd / 256;
        let alive = (256 - k) * 24 / 256 > i || (at & 1 == 0 && i < 4);
        if alive {
            let c = if i % 3 == 0 { WHITE } else { RED };
            let x = cx + sx * dist / 256 + (a & 15) - 8;
            let y = cy + sy * dist / 256 + ((a >> 4) & 15) - 8;
            let mut ob = Obj::new(Kind::Rect, x - 1, y - 1, 3, 3);
            ob.ca = c;
            ob.class = d.class;
            d.push(&ob);
        }
    }
}
