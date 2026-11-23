//! Griglia in prospettiva dietro le schermate prima della partita (scelta della racchetta, scelta dei
//! bonus, schermo VS): un angolo a 90 gradi, muro e pavimento, di righe sottili disegnate al volo, a
//! pixel arcade (lo schermo 320x240 del core MiSTer; sul PC largo le righe continuano ai lati). Un
//! impulso di luce parte dallo spigolo e corre sul pavimento verso chi guarda e sul muro verso
//! l'alto, ogni `CYCLE` frame: più chiaro in testa, sfuma in `PULSE_TAIL` righe di coda.
//!
//! Il grigio di ogni pixel lo dice [`shade`], solo con interi: è la stessa regola della logica che
//! disegna la griglia nel core MiSTer (`grid_gray` di rtl/ui_render.v), quindi le due versioni
//! sono identiche pixel per pixel.

use macroquad::prelude::*;

use crate::App;

/// Riga dello spigolo muro-pavimento e del punto di fuga (sopra, a metà muro) e
/// passo dei quadrati del muro (la colonna centrale è dx = 0).
const JUNCTION: i32 = 128;
const VANISH: i32 = 96;
const CELL: i32 = 16;
/// Righe in orizzontale del pavimento, oltre quella dello spigolo (le profondità 1/8, 2/8... in
/// prospettiva: `VANISH + 256 / (8 - k)`).
const FLOOR_ROWS: [i32; 6] = [133, 139, 147, 160, 181, 224];
/// Frame di un impulso e quelli in cui si vede (poi una pausa).
pub const CYCLE: i32 = 240;
const PULSE_LEN: i32 = 170;
/// Righe di coda dell'impulso, a gradini di 4 righe in 8 livelli di luce.
const PULSE_TAIL: i32 = 32;
/// Grigi: righe del muro e del pavimento a riposo, e al massimo dell'impulso (la distanza è un
/// multiplo di 8, uno per livello: muro 20, pavimento 14).
pub const NONE: u8 = 0;
pub const WALL: u8 = 32;
pub const FLOOR: u8 = 80;
pub const PEAK: u8 = 192;

/// 2 / d in 16.16: `131072 / d` arrotondato, per le righe che vanno al punto di fuga (d = y - VANISH).
fn radial_step(d: i32) -> i64 {
    (131_072 + i64::from(d) / 2) / i64::from(d)
}

/// Livello di luce dell'impulso nella riga `y` al frame `t`, da 0 (niente) a 8 (la testa): la testa
/// parte dallo spigolo e va in giù sul pavimento e in su sul muro, la coda sfuma dietro di lei.
fn pulse(y: i32, t: i32) -> i32 {
    if t >= PULSE_LEN {
        return 0;
    }
    let behind = if y < JUNCTION { y - (JUNCTION - t) } else { JUNCTION + t - y };
    if (0..PULSE_TAIL).contains(&behind) { 8 - behind / 4 } else { 0 }
}

/// Grigio del pixel (`dx` dal centro della griglia, `y` dall'alto, in pixel arcade) al frame `t` del
/// ciclo (0..CYCLE); 0 se non è su una riga.
pub fn shade(dx: i32, y: i32, t: i32) -> u8 {
    let on = if y < JUNCTION {
        // muro: quadrati visti di fronte
        y % CELL == 0 || dx.rem_euclid(CELL) == 0
    } else {
        y == JUNCTION
            || FLOOR_ROWS.contains(&y)
            || {
                // righe verso il punto di fuga: un pixel per ogni passaggio di un multiplo di 65.536
                let step = radial_step(y - VANISH);
                (i64::from(dx.abs()) * step) & 0xFFFF < step
            }
    };
    if !on {
        return NONE;
    }
    let base = if y < JUNCTION { WALL } else { FLOOR };
    base + ((PEAK - base) / 8) * pulse(y, t) as u8
}

/// Disegna la griglia sul campo (da chiamare subito dopo lo sfondo nero della scena).
pub fn draw(app: &App) {
    let r = &app.renderer;
    let u = r.world_h / 240.0;
    let half = (r.world_w / u / 2.0).ceil() as i32;
    let t = ((get_time() * 60.0) as i64 % i64::from(CYCLE)) as i32;
    for y in 0..240 {
        // pixel vicini dello stesso grigio in un rettangolo solo
        let mut dx = -half;
        while dx < half {
            let g = shade(dx, y, t);
            if g == NONE {
                dx += 1;
                continue;
            }
            let start = dx;
            while dx < half && shade(dx, y, t) == g {
                dx += 1;
            }
            let x = r.world_w / 2.0 + start as f32 * u;
            draw_rectangle(x, y as f32 * u, (dx - start) as f32 * u, u, Color::from_rgba(g, g, g, 255));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Centro e simmetria: la riga al centro c'è sempre, e la griglia è speculare a destra e a sinistra.
    #[test]
    fn the_grid_is_symmetric_and_has_a_center_line() {
        for y in [0, 50, 127, 140, 200, 239] {
            assert_ne!(shade(0, y, 200), NONE, "riga centrale in y = {y}");
            for dx in 1..170 {
                assert_eq!(shade(dx, y, 200), shade(-dx, y, 200), "dx = {dx}, y = {y}");
            }
        }
    }

    /// Pavimento: le righe verso il punto di fuga si allargano e non si toccano mai (almeno un
    /// pixel di vuoto fra l'una e l'altra), e l'impulso c'è solo nei primi PULSE_LEN frame.
    #[test]
    fn floor_rays_do_not_touch_and_the_pulse_ends() {
        for y in JUNCTION + 1..240 {
            if FLOOR_ROWS.contains(&y) {
                continue;
            }
            let lit: Vec<i32> = (0..213).filter(|&dx| shade(dx, y, 200) != NONE).collect();
            assert!(lit.windows(2).all(|w| w[1] - w[0] >= 2), "y = {y}: {lit:?}");
        }
        assert!((0..240).any(|y| shade(0, y, 10) > FLOOR));
        assert!((0..240).all(|y| shade(0, y, PULSE_LEN) <= FLOOR));
    }

    /// L'impulso sfuma: dalla testa alla coda il grigio di una riga scende a gradini, mai sopra
    /// PEAK, e torna al riposo oltre la coda; sul pavimento e sul muro.
    #[test]
    fn the_pulse_fades_along_its_tail() {
        let floor: Vec<u8> = (0..PULSE_TAIL).map(|k| shade(0, JUNCTION + 100 - k, 100)).collect();
        assert_eq!(floor[0], PEAK, "{floor:?}");
        assert!(floor.windows(2).all(|w| w[1] <= w[0]), "{floor:?}");
        assert!(floor[PULSE_TAIL as usize - 1] > FLOOR);
        assert_eq!(shade(0, JUNCTION + 100 - PULSE_TAIL, 100), FLOOR);
        let wall: Vec<u8> = (0..PULSE_TAIL).map(|k| shade(0, JUNCTION - 100 + k, 100)).collect();
        assert!(wall[0] > WALL && wall.windows(2).all(|w| w[1] <= w[0]), "{wall:?}");
        assert_eq!(shade(0, JUNCTION - 100 + PULSE_TAIL, 100), WALL);
    }
}
