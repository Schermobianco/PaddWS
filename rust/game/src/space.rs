//! Sfondo spaziale dietro le schermate prima della partita (scelta della racchetta, scelta dei bonus,
//! schermo VS), visto da una navicella: un cielo di stelle bianche che scorrono piano dal centro verso
//! i bordi, sempre più grandi e luminose quando si avvicinano, con un leggero scintillio; la navicella
//! rolla piano a destra e a sinistra (tutto il cielo ruota di qualche grado); ogni tanto una stella
//! cadente attraversa lo schermo, con la coda nel colore dello sfidante.
//!
//! Tutto dipende solo dal tempo, senza stato: le stelle sono fisse (da un generatore con seme) e si
//! muovono con la fase `t` del ciclo (0..1), quindi l'animazione ricomincia senza scatti.

use macroquad::prelude::*;

use crate::App;

/// Secondi che una stella ci mette ad attraversare lo schermo, e che dura un giro di rollio.
const CYCLE: f64 = 14.0;
/// Stelle e ampiezza massima del rollio (gradi).
const STARS: usize = 170;
const ROLL_DEGREES: f32 = 7.0;
/// Raggio massimo del cielo, in pixel arcade dal centro (oltre il bordo anche nel 21:9).
const RADIUS: f32 = 300.0;
/// Riga del centro del cielo, in pixel arcade dall'alto.
const CENTER_Y: f32 = 120.0;
/// Colore dell'accento quando non c'è uno sfidante da seguire.
pub const NEUTRAL: [u8; 3] = [192, 192, 192];

/// Un punto da disegnare: posizione in pixel arcade dal centro del cielo, lato (1..3) e colore.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Dot {
    pub x: f32,
    pub y: f32,
    pub size: i32,
    pub rgb: [u8; 3],
}

/// Generatore dei semi delle stelle: lo stesso di sempre, così il cielo è sempre quello.
fn lcg(seed: u64) -> impl FnMut() -> f32 {
    let mut s = seed;
    move || {
        s = (s * 1_103_515_245 + 12_345) & 0x7FFF_FFFF;
        s as f32 / 0x7FFF_FFFF as f32
    }
}

fn gray(k: f32) -> [u8; 3] {
    let v = (k.clamp(0.0, 1.0) * 255.0).round() as u8;
    [v, v, v]
}

/// Le stelle al tempo `now` (secondi), già ruotate dal rollio.
pub fn stars(now: f64) -> Vec<Dot> {
    let t = (now % CYCLE / CYCLE) as f32;
    let roll = ROLL_DEGREES.to_radians() * (std::f32::consts::TAU * t).sin();
    let (sin, cos) = roll.sin_cos();
    let mut next = lcg(5);
    (0..STARS)
        .map(|i| {
            // direzione a spirale d'oro, fase di avvicinamento e di scintillio da generatore
            let angle = std::f32::consts::TAU * ((i as f32 * 0.618_034) % 1.0);
            let (phase, twinkle) = (next(), next());
            let u = (phase + t) % 1.0;
            let r = RADIUS * u.powf(1.5);
            let (x, y) = (r * angle.cos(), r * angle.sin());
            let tw = 0.8 + 0.2 * (std::f32::consts::TAU * (now as f32 * 0.5 + twinkle)).sin();
            let k = (0.25 + 0.75 * u.powf(0.8)) * tw;
            let size = if u > 0.94 { 3 } else if u > 0.82 { 2 } else { 1 };
            Dot { x: x * cos - y * sin, y: x * sin + y * cos, size, rgb: gray(k) }
        })
        .collect()
}

/// Stelle cadenti del ciclo: (istante di partenza nel ciclo, partenza dal centro, angolo in gradi,
/// lunghezza del percorso). Partono da posizioni diverse, soprattutto dove non ci sono ritratti.
const SHOOTING: [(f32, (f32, f32), f32, f32); 5] = [
    (0.04, (-63.0, -116.0), 32.0, 210.0),
    (0.24, (77.0, -116.0), 148.0, 210.0),
    (0.43, (-193.0, -78.0), 18.0, 240.0),
    (0.62, (192.0, -106.0), 162.0, 240.0),
    (0.82, (-43.0, 85.0), -28.0, 210.0),
];
/// Durata del percorso di una stella cadente, in giri del ciclo, e lunghezza della coda in pixel.
const SHOOT_TIME: f32 = 0.045;
const TAIL: f32 = 70.0;

/// Le stelle cadenti al tempo `now`, con la coda del colore `accent`: la testa bianca, la coda che
/// sfuma dal colore (più chiaro vicino alla testa) a niente.
pub fn shooting_stars(now: f64, accent: [u8; 3]) -> Vec<Dot> {
    let t = (now % CYCLE / CYCLE) as f32;
    let lighter = accent.map(|c| ((u16::from(c) + 255 * 2) / 3) as u8);
    let mut dots = Vec::new();
    for &(start, (x0, y0), angle, length) in &SHOOTING {
        let p = (t - start) / SHOOT_TIME;
        if !(0.0..=1.25).contains(&p) {
            continue;
        }
        let (dy, dx) = angle.to_radians().sin_cos();
        let head = p.min(1.0) * length;
        let (hx, hy) = (x0 + dx * head, y0 + dy * head);
        // a fine percorso la stella si spegne in un quarto del tempo
        let fade = if p <= 1.0 { 1.0 } else { (1.0 - (p - 1.0) / 0.25).max(0.0) };
        for j in 0..=TAIL as i32 {
            let f = j as f32 / TAIL * fade;
            let back = TAIL - j as f32;
            let (x, y) = (hx - dx * back, hy - dy * back);
            let color = if back < TAIL / 2.0 { lighter } else { accent };
            let scale = |c: u8, k: f32| (f32::from(c) * k) as u8;
            dots.push(Dot { x, y, size: 1, rgb: color.map(|c| scale(c, f)) });
            // alone di mezzo tono ai lati della coda
            let (px, py) = (-dy, dx);
            for side in [-1.0, 1.0] {
                dots.push(Dot { x: x + px * side, y: y + py * side, size: 1, rgb: accent.map(|c| scale(c, f * 0.45)) });
            }
        }
        dots.push(Dot { x: hx, y: hy, size: 2, rgb: gray(fade) });
    }
    dots
}

/// Disegna il cielo e le stelle cadenti (da chiamare subito dopo lo sfondo nero della scena), con le
/// code nel colore `accent`.
pub fn draw(app: &App, accent: [u8; 3]) {
    let r = &app.renderer;
    let u = r.world_h / 240.0;
    let (cx, cy) = (r.world_w / 2.0, CENTER_Y * u);
    let now = get_time();
    for d in stars(now).into_iter().chain(shooting_stars(now, accent)) {
        // il quadrato di lato `size` centrato sul punto, sul reticolo dei pixel arcade
        let side = d.size as f32;
        let (x, y) = ((d.x - (side - 1.0) / 2.0).round(), (d.y - (side - 1.0) / 2.0).round());
        draw_rectangle(cx + x * u, cy + y * u, side * u, side * u, Color::from_rgba(d.rgb[0], d.rgb[1], d.rgb[2], 255));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Le stelle sono sempre le stesse e il ciclo si chiude: al tempo 0 e dopo un giro uguali, e il
    /// rollio (che è a zero al tempo 0 e a metà ciclo) resta dentro i suoi gradi.
    #[test]
    fn the_sky_is_always_the_same_and_loops() {
        let a = stars(0.0);
        assert_eq!(a.len(), STARS);
        assert_eq!(a, stars(0.0));
        for (x, y) in a.iter().zip(stars(CYCLE)) {
            assert!((x.x - y.x).abs() < 0.01 && (x.y - y.y).abs() < 0.01 && x.size == y.size);
        }
        // nessuna stella oltre il raggio del cielo, e le più grandi sono poche
        assert!(stars(3.3).iter().all(|d| d.x.hypot(d.y) <= RADIUS + 1.0));
        assert!(stars(3.3).iter().filter(|d| d.size == 3).count() <= STARS / 10);
    }

    /// Le stelle si allargano: in un secondo la stessa stella è più lontana dal centro.
    #[test]
    fn stars_drift_outward() {
        let (a, b) = (stars(5.0), stars(5.5));
        let moved = a.iter().zip(&b).filter(|(p, q)| q.x.hypot(q.y) > p.x.hypot(p.y)).count();
        assert!(moved > STARS * 8 / 10, "{moved}");
    }

    /// Una stella cadente: niente prima di partire, testa bianca durante il percorso, niente dopo.
    #[test]
    fn a_shooting_star_has_a_white_head_and_goes_out() {
        let accent = [230, 120, 40];
        let (start, ..) = SHOOTING[0];
        assert!(shooting_stars(f64::from(start - 0.01) * CYCLE, accent).is_empty());
        let mid = shooting_stars(f64::from(start + SHOOT_TIME / 2.0) * CYCLE, accent);
        assert!(mid.iter().any(|d| d.size == 2 && d.rgb == [255, 255, 255]));
        assert!(mid.iter().any(|d| d.rgb[0] > d.rgb[2] && d.rgb[0] > 0), "coda nel colore dell'accento");
        assert!(shooting_stars(f64::from(start + SHOOT_TIME * 1.3) * CYCLE, accent).is_empty());
    }
}
