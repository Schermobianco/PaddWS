//! Tipi di racchetta di NEXT a schermo: il disegno di ogni tipo, uguale in partita e
//! nella scelta, e la schermata di scelta della racchetta, dopo quella dei bonus.
//!
//! Ogni racchetta è il segno, visto dall'alto, del personaggio della sua illustrazione, nel colore
//! del personaggio (`Portraits::accent`): ARCADE la fessura della gettoniera con il gettone che ci
//! entra, TITAN la cintura con la fibbia e la polvere del passo pesante, HAMMER la testa della mazza
//! con la punta del manico e le scintille del colpo potente, TWIST inclinata con la velocità, la
//! cucitura e un'onda alle estremità a ogni colpo, BLASTER smussata con le canne, la bandana e la cartuccera,
//! RUSH la fascia con i lembi e le immagini dello scatto, GUARDIAN un muro di cinque corsi, uno per
//! settore, che si rompono. La faccia che colpisce resta un bordo dritto: davanti vanno solo le
//! canne di BLASTER e gli effetti brevi dopo un colpo. Cambia solo il disegno, la hitbox è quella
//! del core.
//!
//! Le forme sono in pixel arcade (schermo a 240 righe, corpo largo 5), con la x che cresce verso
//! la faccia (il corpo va da -3 a 2) e la y dalla cima; la racchetta destra è speculare. Il rilievo
//! usa solo colori pieni, come potrebbe fare il MiSTer: ombra portata verso il retro e in basso,
//! retro e fondo del corpo in bianco in ombra, bordi alti in luce e bassi in ombra sui segni.

use macroquad::prelude::*;
use paddws_core::fixed::to_f32;
use paddws_core::next::GUARDIAN_SECTORS;
use paddws_core::{Event, Paddle, PaddleKind, Side};

use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::{PICK_KEYS, PICK_SECONDS, Pick, READY_SECONDS, unit};
use crate::render::{ArtPart, Renderer};
use crate::scenes::{App, Menu, Scene};
use crate::touch;

/// Inclinazione massima di TWIST (circa 20 gradi).
pub(crate) const TWIST_MAX_TILT: f32 = 0.35;

/// HAMMER: durata delle scintille del colpo potente (4 pose a 8 al secondo).
pub(crate) const SPARK_SECONDS: f32 = 0.5;
/// TWIST: durata dell'onda del colpo.
pub(crate) const RING_SECONDS: f32 = 0.5;
/// BLASTER: durata dell'animazione dello sparo (bossolo compreso, 26 frame a 60 Hz).
pub(crate) const FIRE_SECONDS: f32 = 26.0 / 60.0;
/// GUARDIAN: rientro del corso colpito dalla palla.
pub(crate) const RECOIL_SECONDS: f32 = 0.1;
/// GUARDIAN: rottura di un corso (si crepa, poi diventa grigio e perde le schegge).
pub(crate) const BREAK_SECONDS: f32 = 0.65;

/// Frase sotto la colonna della scelta.
pub fn tagline(kind: PaddleKind) -> &'static str {
    match kind {
        PaddleKind::Arcade => "MORE BONUSES",
        PaddleKind::Titan => "TALL BUT SLOW",
        PaddleKind::Hammer => "POWER SHOTS",
        PaddleKind::Twist => "TILTS WITH SPEED",
        PaddleKind::Blaster => "SHOOTS CAPSULES",
        PaddleKind::Rush => "LONG DASH",
        PaddleKind::Guardian => "FIVE-PIECE WALL",
    }
}

/// Colori di una racchetta: corpo (bianco, o il colore dello stato: bonus armato, lampo, OMEGA),
/// colore del personaggio per i segni e giallo del gioco per i segnali (colpi della cartuccera,
/// lampo dello sparo).
#[derive(Clone, Copy)]
pub struct Look {
    pub body: Color,
    pub mark: Color,
    pub signal: Color,
}

/// I colori di una racchetta del tipo `kind` con il corpo `body`.
pub fn look(app: &App, kind: Option<PaddleKind>, body: Color) -> Look {
    let signal = App::color(app.cfg.colors.accent);
    Look {
        body,
        mark: kind.map_or(signal, |k| app.assets.portraits.accent(k)),
        signal,
    }
}

/// Stato delle animazioni di una racchetta. In partita lo tiene `NextFx`; nella scelta e nello
/// schermo VS c'è solo l'orologio (`Anim::still`).
#[derive(Clone, Copy)]
pub struct Anim {
    /// secondi dell'orologio dei cicli (gettone, onde, lembi, polvere, ultimo corso)
    pub t: f32,
    /// velocità verticale in pixel arcade per frame a 60 Hz, positiva verso il basso
    pub vy: f32,
    /// BLASTER: colpi nella cartuccera (al massimo 4) e secondi dall'ultimo sparo
    pub ammo: u8,
    pub fire: Option<f32>,
    /// HAMMER e TWIST: secondi dal colpo (per HAMMER quello potente) e altezza del colpo (0 in
    /// cima, 1 in fondo): scintille di HAMMER, onda di TWIST
    pub spark: Option<(f32, f32)>,
    /// GUARDIAN: per corso (settore) dall'alto, None se c'è, altrimenti i secondi dalla rottura;
    /// secondi dall'inizio della costruzione (None: muro già costruito); altezza del colpo che fa
    /// rientrare il corso (0 in cima, 1 in fondo)
    pub wall: [Option<f32>; GUARDIAN_SECTORS],
    pub build: Option<f32>,
    pub recoil: Option<f32>,
    /// RUSH: sta scattando in avanti (i lembi si allungano dritti)
    pub dashing: bool,
}

impl Anim {
    /// Racchetta ferma e intera, con l'orologio a `t` secondi.
    pub fn still(t: f32) -> Self {
        Self {
            t,
            vy: 0.0,
            ammo: 4,
            fire: None,
            spark: None,
            wall: [None; GUARDIAN_SECTORS],
            build: None,
            recoil: None,
            dashing: false,
        }
    }
}

/// Racchetta da disegnare: centro in coordinate del core (y verso l'alto), dimensioni,
/// verso della faccia (+1 a destra: giocatore sinistro) e inclinazione di TWIST (radianti,
/// positiva con la faccia verso l'alto).
pub struct Shape {
    pub kind: Option<PaddleKind>,
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub front: f32,
    pub tilt: f32,
    /// la racchetta sta scattando in avanti: x da cui è partita e intensità (1 all'inizio, poi
    /// sfuma); RUSH lascia immagini nel suo colore tra la partenza e dove si trova
    pub dash: Option<(f32, f32)>,
    /// anteprima della scelta: RUSH mostra sempre le immagini dello scatto
    pub preview: bool,
    pub anim: Anim,
}

/// Inclinazione di TWIST dalla velocità della racchetta: salendo la faccia si gira verso l'alto.
pub fn twist_tilt(pad: &Paddle) -> f32 {
    if pad.max_speed == 0 {
        return 0.0;
    }
    (to_f32(pad.motion) / to_f32(pad.max_speed)).clamp(-1.0, 1.0) * TWIST_MAX_TILT
}

/// Ruolo di colore di un pezzo della racchetta.
#[derive(Clone, Copy, PartialEq)]
enum Role {
    /// il corpo
    Body,
    /// colore del personaggio, scurito, schiarito
    Mark,
    MarkDark,
    MarkLight,
    /// grigio chiaro e grigio scuro
    Gray,
    Dark,
    Black,
    /// giallo del gioco
    Signal,
}

#[derive(Clone, Copy)]
enum Op {
    Rect { x: f32, y: f32, w: f32, h: f32, role: Role },
    Tri { p: [(f32, f32); 3], role: Role },
}

/// I pezzi di una racchetta, in ordine di disegno: quelli con il rilievo e quelli disegnati dopo
/// il rilievo, che non ne prendono e non ne sono coperti (hanno solo l'ombra portata).
#[derive(Default)]
struct Ops(Vec<Op>, Vec<Op>);

impl Ops {
    fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, role: Role) {
        self.0.push(Op::Rect { x, y, w, h, role });
    }

    fn late_rect(&mut self, x: f32, y: f32, w: f32, h: f32, role: Role) {
        self.1.push(Op::Rect { x, y, w, h, role });
    }

    fn tri(&mut self, p: [(f32, f32); 3], role: Role) {
        self.0.push(Op::Tri { p, role });
    }

    /// Sposta di `dx` i pezzi dal numero `from` in poi.
    fn shift(&mut self, from: usize, dx: f32) {
        for op in self.0[from..].iter_mut().chain(&mut self.1) {
            match op {
                Op::Rect { x, .. } => *x += dx,
                Op::Tri { p, .. } => {
                    for (x, _) in p {
                        *x += dx;
                    }
                }
            }
        }
    }
}

/// Arrotondamento come `Math.round` (le metà verso l'alto), per avere gli stessi pixel del mockup.
fn round(v: f32) -> f32 {
    (v + 0.5).floor()
}

/// Posa del ciclo a 8 al secondo.
fn pose(t: f32) -> f32 {
    (t * 8.0).floor()
}

fn smooth(u: f32) -> f32 {
    let u = u.clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

/// ARCADE: la fessura della gettoniera al centro del corpo e il gettone che ci entra. Ciclo di 3
/// secondi a 8 pose al secondo: il gettone, visto dall'alto come una piccola croce, scende verso la
/// fessura (pose 0-5), si mette di taglio e sparisce dentro (6-8), la fessura lampeggia gialla come
/// un credito accettato (10-13), poi pausa.
fn coin_slot(r: &mut Ops, h: f32, t: f32) {
    let s = (pose(t) as i64).rem_euclid(24);
    let top = (h / 2.0).floor() - 4.0;
    let lit = (10..=13).contains(&s) && s % 2 == 0;
    r.rect(-1.0, top, 1.0, 8.0, if lit { Role::Mark } else { Role::Dark });
    if s <= 5 {
        let y = top - 7.0 + s as f32;
        r.rect(-2.0, y + 1.0, 3.0, 1.0, Role::Mark);
        r.rect(-1.0, y, 1.0, 3.0, Role::Mark);
    } else if s <= 8 {
        let len = [6.0, 4.0, 2.0][s as usize - 6];
        r.rect(-1.0, top, 1.0, len, Role::Mark);
    }
}

/// TITAN, passo pesante: sbuffi di polvere e calcinacci che si staccano dietro le estremità (da
/// `x0` verso il retro) e si allontanano; da ferma 2 per estremità, in movimento 4. Prima grigio
/// chiaro 2x2, poi puntini scuri.
fn heavy_step(r: &mut Ops, h: f32, a: &Anim, x0: f32) {
    let t = pose(a.t) / 8.0;
    let m = if a.vy.abs() > 0.5 { 4 } else { 2 };
    for (yc, dir) in [(h - 3.0, 1.0), (2.0, -1.0)] {
        for k in 0..m {
            let p = (t * 0.9 + k as f32 / m as f32 + if dir > 0.0 { 0.0 } else { 0.37 }).fract();
            if p > 0.85 {
                continue;
            }
            let x = round(x0 - p * 9.0);
            let y = round(yc + dir * (p * 4.0 + (k % 2) as f32 * 2.0));
            if p < 0.45 {
                r.rect(x - 1.0, y, 2.0, 2.0, Role::Gray);
            } else {
                r.rect(x, y, 1.0, 1.0, Role::Dark);
            }
        }
    }
}

/// TWIST, colpo della palla: un'onda che si allarga intorno alle due estremità (raggio da 3 a 10
/// in `RING_SECONDS`), come se la racchetta vibrasse. Copre il retro e la punta, mai la faccia né
/// il corpo; piena da vicina, scurita quando si allontana. `s`: secondi dal colpo.
fn ring(r: &mut Ops, h: f32, s: f32) {
    let p = (s / RING_SECONDS).clamp(0.0, 1.0);
    let rad = 3.0 + p * 7.0;
    for (cy, a0, a1) in [(2.0, 150.0f32, 300.0), (h - 2.0, 60.0, 210.0)] {
        let mut seen: Vec<(f32, f32)> = Vec::new();
        let mut deg = a0;
        while deg <= a1 {
            let (sin, cos) = deg.to_radians().sin_cos();
            let x = round(-0.5 + rad * cos - 0.5);
            let y = round(cy + rad * sin);
            let on_body = (-3.0..=1.0).contains(&x) && y >= 0.0 && y < h;
            if !on_body && !seen.contains(&(x, y)) {
                seen.push((x, y));
                r.rect(x, y, 1.0, 1.0, if p < 0.5 { Role::Mark } else { Role::MarkDark });
            }
            deg += 40.0 / rad;
        }
    }
}

/// Lembi di fascia o bandana, dal nodo (`ax`, `ay`) verso il retro: due strisce di segmenti larghi
/// `sw` (`n1` e `n2` segmenti, l'ultimo dell'inferiore scurito). Pose a 8 al secondo: da ferma
/// sventolano piano; in movimento piegano nel verso opposto alla velocità verticale; nello scatto
/// di RUSH si allungano di 2 segmenti, dritti.
fn tails(r: &mut Ops, (ax, ay): (f32, f32), sw: f32, (n1, n2): (u32, u32), a: &Anim) {
    let t = pose(a.t) / 8.0;
    let bend = (-a.vy * 0.6).clamp(-1.2, 1.2);
    let calm = 1.0 - bend.abs().min(1.0);
    for (i, (n, spread, y0)) in [(n1, -0.5, 0.0), (n2, 0.6, 2.0)].into_iter().enumerate() {
        let n = if a.dashing { n + 2 } else { n };
        for j in 1..=n {
            let jf = j as f32;
            let wave = if a.dashing {
                0.0
            } else {
                (t * 5.0 + jf * 1.3 + i as f32 * 2.0).sin() * (0.3 + 0.7 * calm) * jf / n as f32 * 1.4
            };
            let lean = if a.dashing { 0.25 } else { 1.0 };
            let dy = round(ay + y0 + lean * spread * jf + bend * jf + wave);
            let role = if i == 1 && j == n { Role::MarkDark } else { Role::Mark };
            r.rect(ax - sw * jf, dy, sw, 1.0, role);
        }
    }
}

/// GUARDIAN: spostamento verticale del corso `i` durante la costruzione, a `t` secondi
/// dall'inizio: i corsi cadono da 14 pixel uno alla volta, dal basso, ogni 0,3 s, e rimbalzano di
/// 1 pixel; None finché il corso non è ancora entrato.
fn build_offset(i: usize, t: f32) -> Option<f32> {
    let land = 0.4 + 0.3 * (GUARDIAN_SECTORS - 1 - i) as f32;
    if t < land - 0.25 {
        None
    } else if t < land {
        Some(-round((1.0 - smooth((t - land + 0.25) / 0.25)) * 14.0))
    } else if t < land + 0.1 {
        Some(-1.0)
    } else {
        Some(0.0)
    }
}

/// GUARDIAN: tutta la racchetta è un muro spesso 8 pixel, 5 corsi di blocchi, uno per settore del
/// core dall'alto, con le fughe nel suo colore su tutta la larghezza (anche sulla faccia) e i giunti
/// sfalsati. Un settore perso è un corso che si crepa (0,15 s), poi diventa grigio con la crepa e
/// quattro schegge saltano via dietro; quando ne resta uno solo, lampeggia nel colore schiarito.
fn wall(r: &mut Ops, h: f32, a: &Anim) {
    let n = GUARDIAN_SECTORS;
    let tq = pose(a.t) as i64;
    let alive = a.wall.iter().filter(|w| w.is_none()).count();
    let recoil = a.recoil.map(|at| ((at * n as f32).floor() as usize).min(n - 1));
    for i in 0..n {
        let dy = match a.build {
            Some(t) => match build_offset(i, t) {
                Some(dy) => dy,
                None => continue,
            },
            None => 0.0,
        };
        let dx = if recoil == Some(i) { -1.0 } else { 0.0 };
        let mut rect = |x: f32, y: f32, w: f32, hh: f32, role: Role| r.rect(x + dx, y + dy, w, hh, role);
        let y0 = round(h * i as f32 / n as f32);
        let y1 = round(h * (i + 1) as f32 / n as f32);
        // righe del corso, sotto la fuga
        let ys = if i > 0 { y0 + 1.0 } else { y0 };
        let hh = y1 - ys;
        let joints: &[f32] = if i % 2 == 1 { &[-4.0, 0.0] } else { &[-2.0] };
        let crack = |rect: &mut dyn FnMut(f32, f32, f32, f32, Role)| {
            rect(-4.0, ys + 1.0, 1.0, 2.0, Role::Black);
            rect(-3.0, ys + 3.0, 1.0, 1.0, Role::Black);
            rect(-2.0, ys + 4.0, 1.0, 2.0, Role::Black);
            rect(0.0, ys + 2.0, 1.0, 2.0, Role::Black);
        };
        rect(-6.0, y0, 8.0, y1 - y0, Role::Body);
        match a.wall[i] {
            None => {
                if alive == 1 && tq % 4 < 2 {
                    rect(-6.0, ys, 8.0, hh, Role::MarkLight);
                }
                for &jx in joints {
                    rect(jx, ys, 1.0, hh, Role::Mark);
                }
            }
            Some(age) if age < 0.15 => {
                for &jx in joints {
                    rect(jx, ys, 1.0, hh, Role::Mark);
                }
                crack(&mut rect);
            }
            Some(age) => {
                rect(-6.0, ys, 8.0, hh, Role::Dark);
                crack(&mut rect);
                if age < BREAK_SECONDS {
                    let p = (age - 0.15) / 0.5;
                    for j in 0..4 {
                        let jf = j as f32;
                        let (w, role) = if j % 2 == 1 { (1.0, Role::Gray) } else { (2.0, Role::Dark) };
                        let x = round(-7.0 - p * (5.0 + 2.0 * jf));
                        let y = round(ys + 1.0 + jf * 1.5 + (jf - 1.5) * p * 3.0);
                        rect(x, y, w, 1.0, role);
                    }
                }
            }
        }
        if i > 0 {
            rect(-6.0, y0, 8.0, 1.0, Role::Mark);
        }
    }
}

/// I pezzi della racchetta `kind` alta `h` pixel arcade.
fn kind_ops(kind: PaddleKind, h: f32, a: &Anim) -> Ops {
    let mut r = Ops::default();
    let mid = (h / 2.0).floor();
    match kind {
        PaddleKind::Arcade => {
            r.rect(-3.0, 0.0, 5.0, h, Role::Body);
            coin_slot(&mut r, h, a.t);
        }
        PaddleKind::Titan => {
            // più spessa verso il retro (la faccia resta dove colpisce), cintura a metà altezza con
            // i fori (la colonna della faccia resta bianca), fibbia che sporge sul retro
            let yb = round(h / 2.0) - 2.0;
            r.rect(-6.0, 0.0, 8.0, h, Role::Body);
            r.rect(-6.0, yb, 7.0, 4.0, Role::Mark);
            for x in [-4.0, -2.0, 0.0] {
                r.rect(x, yb + 1.0, 1.0, 1.0, Role::MarkDark);
            }
            r.rect(-9.0, yb - 1.0, 3.0, 6.0, Role::Gray);
            r.rect(-8.0, yb, 1.0, 4.0, Role::Dark);
            heavy_step(&mut r, h, a, -8.0);
        }
        PaddleKind::Hammer => {
            // la testa della mazza vista dall'alto (il manico scende sotto e non si vede): piano
            // bianco spesso 8 pixel con un bordo scuro sul retro, al centro l'occhio con la punta
            // del manico e il cuneo di traverso
            r.rect(-6.0, 0.0, 8.0, h, Role::Body);
            r.late_rect(-6.0, 0.0, 1.0, h, Role::Dark);
            let yc = round(h / 2.0);
            r.rect(-4.0, yc - 4.0, 4.0, 8.0, Role::Dark);
            r.rect(-3.0, yc - 3.0, 2.0, 6.0, Role::Mark);
            r.rect(-3.0, yc - 1.0, 2.0, 1.0, Role::MarkDark);
            // colpo potente: scintille a raggiera dalla faccia (da -70 a +70 gradi), che si
            // allontanano e si scuriscono
            if let Some((s, at)) = a.spark
                && s < SPARK_SECONDS
            {
                let p = (pose(s) + 1.0) / 4.0;
                let yh = round(at * h);
                for j in 0..6 {
                    let (sin, cos) = (-70.0 + j as f32 * 28.0f32).to_radians().sin_cos();
                    let d = 2.0 + p * 7.0;
                    for dd in [d, d - 1.5] {
                        let role = if p < 0.6 { Role::Mark } else { Role::MarkDark };
                        r.rect(round(1.0 + cos * dd), round(yh + sin * dd), 1.0, 1.0, role);
                    }
                }
            }
        }
        PaddleKind::Twist => {
            // cucitura della maschera e stemma al centro
            r.rect(-3.0, 0.0, 5.0, h, Role::Body);
            r.rect(-1.0, 2.0, 1.0, h - 4.0, Role::Mark);
            r.rect(-2.0, mid - 2.0, 3.0, 4.0, Role::Mark);
            if let Some((s, _)) = a.spark
                && s < RING_SECONDS
            {
                ring(&mut r, h, s);
            }
        }
        PaddleKind::Blaster => {
            // sparo: tutta la racchetta arretra di 1 pixel per 3 frame, le canne rientrano a 1
            // pixel e tornano a 3 in 8 frame, lampo alla bocca per 3 frame, il bossolo vola dietro
            // con un arco in circa 24 frame
            let fr = a.fire.map(|s| s * 60.0);
            let recoil = fr.is_some_and(|f| f < 3.0);
            let barrel = match fr {
                Some(f) if f < 3.0 => 1.0,
                Some(f) if f < 8.0 => 2.0,
                _ => 3.0,
            };
            let cut = 2.0;
            r.rect(-3.0, 0.0, 3.0, h, Role::Body);
            r.rect(0.0, cut, 2.0, h - 2.0 * cut, Role::Body);
            r.tri([(0.0, 0.0), (0.0, cut), (2.0, cut)], Role::Body);
            r.tri([(0.0, h), (0.0, h - cut), (2.0, h - cut)], Role::Body);
            r.rect(2.0, mid - 3.0, barrel, 2.0, Role::Gray);
            r.rect(2.0, mid + 1.0, barrel, 2.0, Role::Gray);
            if recoil {
                let x = 2.0 + barrel;
                r.rect(x, mid - 4.0, 1.0, 3.0, Role::Signal);
                r.rect(x, mid + 1.0, 1.0, 3.0, Role::Signal);
                r.rect(x + 1.0, mid - 2.0, 2.0, 4.0, Role::Signal);
                r.rect(x + 3.0, mid - 1.0, 1.0, 2.0, Role::Signal);
            }
            // lembi della bandana, cinghia e cartuccera
            tails(&mut r, (-3.0, 3.0), 2.0, (3, 2), a);
            let y0 = mid - 9.0;
            r.rect(-4.0, y0, 1.0, 21.0, Role::Dark);
            let ammo = a.ammo.min(4);
            for i in (4 - ammo)..4 {
                r.rect(-6.0, y0 + 1.0 + i as f32 * 5.0, 2.0, 3.0, Role::Signal);
            }
            if let Some(f) = fr
                && (2.0..26.0).contains(&f)
            {
                let p = (f - 2.0) / 24.0;
                let slot = 3u8.saturating_sub(ammo) as f32;
                let x = round(-7.0 - p * 10.0);
                let y = round(y0 + 1.0 + slot * 5.0 - 6.0 * (p * std::f32::consts::PI).sin() + p * 4.0);
                r.rect(x, y, 2.0, 1.0, Role::Signal);
            }
            if recoil {
                r.shift(0, -1.0);
            }
        }
        PaddleKind::Rush => {
            // fascia in cima, con i lembi che escono dietro dal nodo
            r.rect(-3.0, 0.0, 5.0, h, Role::Body);
            r.rect(-3.0, 3.0, 4.0, 2.0, Role::Mark);
            tails(&mut r, (-3.0, 3.0), 3.0, (3, 2), a);
        }
        PaddleKind::Guardian => wall(&mut r, h, a),
    }
    r
}

/// Colore `c` moltiplicato per `k` (canale per canale).
fn scaled(c: Color, k: [f32; 3]) -> Color {
    Color::new(c.r * k[0], c.g * k[1], c.b * k[2], c.a)
}

/// Colore `c` portato verso il bianco di `k`.
fn lighter(c: Color, k: f32) -> Color {
    Color::new(c.r + (1.0 - c.r) * k, c.g + (1.0 - c.g) * k, c.b + (1.0 - c.b) * k, c.a)
}

fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color::from_rgba(r, g, b, 255)
}

/// Disegna la racchetta `s` con i colori `look`; `u` è il pixel "arcade" (schermo a 240 righe).
pub fn draw_paddle(r: &Renderer, s: &Shape, u: f32, look: Look) {
    let (cx, cy, f) = (s.x, r.screen_y(s.y), s.front);
    let Some(kind) = s.kind else {
        draw_rectangle(cx - s.w / 2.0, cy - s.h / 2.0, s.w, s.h, look.body);
        return;
    };
    // pixel arcade della racchetta: il corpo largo 5 e alto `h` occupa esattamente la hitbox
    let h = (s.h / u).round().max(1.0);
    let (kx, ky) = (s.w / 5.0, s.h / h);
    let top = cy - s.h / 2.0;

    // RUSH: immagini della racchetta lungo lo scatto in avanti, più chiare verso la partenza
    // (nella scelta sempre: è il suo segno)
    if kind == PaddleKind::Rush {
        let dash = s.dash.or(s.preview.then_some((cx - f * s.w * 8.0, 1.0)));
        if let Some((from, fade)) = dash {
            for k in 1..=3 {
                let gx = from + (cx - from) * k as f32 / 4.0;
                let color = Color {
                    a: look.mark.a * fade * 0.18 * k as f32,
                    ..look.mark
                };
                draw_rectangle(gx - s.w / 2.0, top, s.w, s.h, color);
            }
        }
    }

    let ops = kind_ops(kind, h, &s.anim);
    // da pixel arcade a coordinate di disegno, con l'inclinazione di TWIST attorno al centro
    let angle = -s.tilt * f;
    let (sin, cos) = angle.sin_cos();
    let point = |x: f32, y: f32| {
        let (dx, dy) = (f * (x + 0.5) * kx, top + y * ky - cy);
        vec2(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos)
    };
    let fill = |op: &Op, color: Color, ox: f32, oy: f32| match *op {
        Op::Rect { x, y, w, h, .. } => {
            let (ww, hh) = (w * kx, h * ky);
            if angle == 0.0 {
                let x0 = if f > 0.0 { cx + (x + ox + 0.5) * kx } else { cx - (x + ox + w + 0.5) * kx };
                draw_rectangle(x0, top + (y + oy) * ky, ww, hh, color);
            } else {
                let c = point(x + ox + w / 2.0, y + oy + h / 2.0);
                draw_rectangle_ex(c.x, c.y, ww, hh, DrawRectangleParams {
                    offset: vec2(0.5, 0.5),
                    rotation: angle,
                    color,
                });
            }
        }
        Op::Tri { p, .. } => {
            let [a, b, c] = p.map(|(x, y)| point(x + ox, y + oy));
            draw_triangle(a, b, c, color);
        }
    };
    let role_of = |op: &Op| match *op {
        Op::Rect { role, .. } | Op::Tri { role, .. } => role,
    };

    let mark_dark = scaled(look.mark, [0.6; 3]);
    let mark_light = lighter(look.mark, 0.45);
    let gray = rgb(180, 180, 180);
    let dark = rgb(92, 92, 98);
    let color = |role: Role| match role {
        Role::Body => look.body,
        Role::Mark => look.mark,
        Role::MarkDark => mark_dark,
        Role::MarkLight => mark_light,
        Role::Gray => gray,
        Role::Dark => dark,
        Role::Black => BLACK,
        Role::Signal => look.signal,
    };

    // ombra portata grigio scuro, 1 pixel verso il retro e 1 in basso, sotto tutto
    let shadow = rgb(48, 48, 58);
    for op in ops.0.iter().chain(&ops.1) {
        fill(op, shadow, -1.0, 1.0);
    }
    for op in &ops.0 {
        fill(op, color(role_of(op)), 0.0, 0.0);
    }
    // luce dall'alto e dalla faccia: retro e fondo del corpo in bianco in ombra (la faccia resta
    // piena), sui segni alti almeno 2 pixel il bordo alto in luce e il basso in ombra
    let body_shade = scaled(look.body, [212.0 / 255.0, 214.0 / 255.0, 224.0 / 255.0]);
    for op in &ops.0 {
        let Op::Rect { x, y, w, h, role } = *op else { continue };
        if w < 2.0 || h < 2.0 {
            continue;
        }
        let edge = |x: f32, y: f32, w: f32, c: Color| fill(&Op::Rect { x, y, w, h: 1.0, role }, c, 0.0, 0.0);
        if role == Role::Body {
            if x <= -3.0 {
                fill(&Op::Rect { x, y, w: 1.0, h, role }, body_shade, 0.0, 0.0);
            }
            edge(x + 1.0, y + h - 1.0, w - 2.0, body_shade);
        } else {
            let ramp = match role {
                Role::Mark => (mark_light, mark_dark),
                Role::Gray => (rgb(226, 226, 230), dark),
                Role::Dark => (gray, rgb(52, 52, 60)),
                _ => continue,
            };
            edge(x, y, w, ramp.0);
            edge(x, y + h - 1.0, w, ramp.1);
        }
    }
    for op in &ops.1 {
        fill(op, color(role_of(op)), 0.0, 0.0);
    }
}

/// Per le immagini del README: la racchetta `kind` al centro, ingrandita `zoom` volte, su nero,
/// rivolta a destra (come quella del giocatore sinistro), con i segni in azione.
pub fn draw_gallery(app: &App, kind: PaddleKind, zoom: f32) {
    let r = &app.renderer;
    let p = &app.params;
    let u = unit(app) * zoom;
    r.fill(BLACK);
    let shape = Shape {
        kind: Some(kind),
        x: r.world_w / 2.0,
        y: r.world_h / 2.0,
        w: to_f32(p.pad_width) * zoom,
        h: to_f32(p.kinds[kind as usize].height) * zoom,
        front: 1.0,
        tilt: if kind == PaddleKind::Twist { TWIST_MAX_TILT } else { 0.0 },
        dash: None,
        preview: true,
        anim: Anim::still(0.0),
    };
    let look = look(app, Some(kind), App::color(app.cfg.colors.white));
    draw_paddle(r, &shape, u, look);
}

// ------------------------------------------------------------------ scelta

/// Scelta della racchetta di ciascun giocatore, prima dei bonus (`Pick`).
pub struct PaddlePick {
    /// il giocatore di destra è il computer: sceglie a caso
    cpu: bool,
    /// lato che ha già la sua racchetta e non sceglie: la CPU, o il campione quando entra uno
    /// sfidante
    fixed: Option<usize>,
    /// CHALLENGE: sceglie lo sfidante di questo lato, poi si gioca la sfida
    duel: Option<Side>,
    cursor: [usize; 2],
    chosen: [bool; 2],
    left: f64,
    ready: Option<f64>,
    /// encoder già impostati per la scelta
    knobs_ready: bool,
}

impl PaddlePick {
    pub fn new(app: &App) -> Self {
        let mut pick = Self {
            cpu: app.vs_cpu(),
            fixed: app.vs_cpu().then_some(1),
            duel: None,
            cursor: [0; 2],
            chosen: [false; 2],
            left: PICK_SECONDS,
            ready: None,
            knobs_ready: false,
        };
        if let Some(run) = &app.run {
            // scalata: la CPU cambia racchetta a ogni livello, qui si vede quella del primo;
            // allenamento: quella dell'avversario scelto
            pick.cursor[1] = crate::challenge_ui::rung(run.level).kind as usize;
            pick.chosen[1] = true;
        } else if app.cpu {
            let mut rng = paddws_core::Rng::new(app.seed ^ 0x7A11_E5ED);
            pick.cursor[1] = rng.below(PaddleKind::COUNT as u32) as usize;
            pick.chosen[1] = true;
        }
        pick
    }

    /// CHALLENGE, nuovo sfidante sul lato `free`: sceglie solo lui, il campione tiene la sua.
    pub fn challenger(app: &App, free: Side) -> Self {
        let champion = free.opponent() as usize;
        let mut pick = Self::new(app);
        pick.cpu = false;
        pick.fixed = Some(champion);
        pick.duel = Some(free);
        pick.chosen = [false; 2];
        pick.chosen[champion] = true;
        pick.cursor[free as usize] = 0;
        pick.cursor[champion] = app.paddles[champion].map_or(0, |k| k as usize);
        pick
    }

    /// CHALLENGE che comincia con la sfida (due crediti e lo Start del giocatore 2 nell'attract):
    /// scelgono tutti e due, P1 fa da campione.
    pub fn opening_duel(app: &App) -> Self {
        let mut pick = Self::new(app);
        pick.cpu = false;
        pick.fixed = None;
        pick.duel = Some(Side::Right);
        pick.chosen = [false; 2];
        pick.cursor = [0; 2];
        pick
    }


    /// Gamepad come i tasti del lato (`input`): le quattro direzioni spostano il cursore nella
    /// griglia (`grid_step`), A sceglie la racchetta (o annulla la scelta), B torna al menu. Con un
    /// solo gamepad è di chi sceglie.
    pub fn pad_keys(&self, app: &App) -> PadKeys {
        let solo = self.fixed.map(|f| 1 - f);
        input::pad_keys(|slot, c| {
            let side = app.pads.side_of(slot, solo);
            let (up, down, toggle) = PICK_KEYS[side];
            let (left, right) = SIDE_KEYS[side];
            match c {
                Control::Up => Some(up),
                Control::Down => Some(down),
                Control::Left => Some(left),
                Control::Right => Some(right),
                Control::A => Some(toggle),
                Control::B => Some(KeyCode::Escape),
                _ => None,
            }
        })
    }

    /// Nome sopra la colonna del lato `side`.
    fn name(&self, side: usize) -> String {
        if self.cpu && self.fixed == Some(side) {
            "CPU".to_string()
        } else {
            format!("P{}", side + 1)
        }
    }

    /// Per la verifica automatica: P1 sul BLASTER, P2 ha già scelto il GUARDIAN.
    pub fn demo(&mut self) {
        self.cpu = false;
        self.fixed = None;
        self.cursor = [PaddleKind::Blaster as usize, PaddleKind::Guardian as usize];
        self.chosen = [false, true];
    }

    /// Lati che scelgono (non la CPU né il campione che tiene la sua racchetta).
    fn choosing(&self) -> impl Iterator<Item = usize> + '_ {
        (0..2).filter(|&side| self.fixed != Some(side))
    }

    /// Conferma o annulla la racchetta sotto il cursore di `side`; confermata, se ne sente il nome
    /// sopra la musica (come READY e GO), interrompendo quello di prima.
    fn toggle(&mut self, app: &App, side: usize) {
        self.chosen[side] = !self.chosen[side];
        app.play(if self.chosen[side] { Event::Hit } else { Event::Wall });
        if self.chosen[side] {
            app.announce_paddle(PaddleKind::ALL[self.cursor[side]]);
        }
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            return Some(Scene::Menu(Menu::new(app)));
        }
        if let Some(t) = &mut self.ready {
            *t -= dt;
            if *t <= 0.0 {
                // poi la scelta dei bonus (nella sfida solo lo sfidante)
                if let Some(free) = self.duel {
                    if self.fixed.is_none() {
                        app.paddles = self.cursor.map(|i| Some(PaddleKind::ALL[i]));
                        return Some(Scene::Pick(Pick::opening_duel(app)));
                    }
                    let i = free as usize;
                    app.paddles[i] = Some(PaddleKind::ALL[self.cursor[i]]);
                    return Some(Scene::Pick(Pick::challenger(app, free)));
                }
                app.paddles = self.cursor.map(|i| Some(PaddleKind::ALL[i]));
                return Some(Scene::Pick(Pick::new(app)));
            }
            return None;
        }
        self.left -= dt;
        let n = PaddleKind::COUNT;
        for (side, &(up, down, toggle)) in PICK_KEYS.iter().enumerate() {
            if self.fixed == Some(side) {
                continue;
            }
            if !self.chosen[side] {
                let (left, right) = SIDE_KEYS[side];
                let cur = &mut self.cursor[side];
                for (key, step) in [(up, GridStep::Row), (down, GridStep::Row), (left, GridStep::Prev), (right, GridStep::Next)] {
                    if input::pressed(key) {
                        *cur = grid_step(*cur, step);
                    }
                }
            }
            if input::pressed(toggle) {
                self.toggle(app, side);
            }
        }
        // encoder: la rotazione sposta il cursore, il click (o USA) conferma o annulla
        if let Some(enc) = &mut app.encoders
            && !std::mem::replace(&mut self.knobs_ready, true)
        {
            enc.configure(0, n as i32 - 1, 1, 0);
        }
        for e in app.knob_events.clone() {
            if self.fixed == Some(e.player) {
                continue;
            }
            match e.action {
                Action::Rotate(v) if !self.chosen[e.player] => self.cursor[e.player] = (v.max(0) as usize).min(n - 1),
                Action::Click | Action::Activate => self.toggle(app, e.player),
                _ => {}
            }
        }
        // touch: un tocco su una casella della griglia mostra quella racchetta (e annulla la
        // conferma) per chi sceglie (in due, per chi sta da quella parte dello schermo); un tocco
        // fuori dalla griglia, nella propria metà, conferma o lascia la scelta (come OK)
        let solo = {
            let mut sides = self.choosing();
            match (sides.next(), sides.next()) {
                (Some(side), None) => Some(side),
                _ => None,
            }
        };
        let half = |p: Vec2| usize::from(p.x >= app.renderer.world_w / 2.0);
        for p in touch::taps() {
            let cell = (0..CELLS).find(|&i| cell_rect(app, i).contains(p));
            let side = solo.unwrap_or_else(|| half(p));
            if self.fixed == Some(side) {
                continue;
            }
            match cell {
                Some(i) if i < n => {
                    self.cursor[side] = i;
                    self.chosen[side] = false;
                }
                Some(_) => {} // la casella di OMEGA non si sceglie
                None => self.toggle(app, side),
            }
        }
        // tempo scaduto: vale la racchetta sotto il cursore
        if self.chosen.iter().all(|&c| c) || self.left <= 0.0 {
            self.chosen = [true; 2];
            self.ready = Some(READY_SECONDS);
            app.play(Event::Boost);
        }
        None
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let w = r.world_w;
        let s = app.scale();
        let u = unit(app);
        let colors = &app.cfg.colors;
        let white = App::color(colors.white);
        let gray = App::color(colors.lgray);
        let accent = App::color(colors.accent);
        let frame = Color::from_rgba(0x46, 0x46, 0x46, 255);
        let font = &app.assets.font_text;
        let portraits = &app.assets.portraits;
        let p = &app.params;
        let t1 = r.text_1x();
        r.fill(BLACK);
        r.text_centered("PICK YOUR PADDLE", font, t1, w / 2.0, at(app, 0.0, line(0)).y, 0.0, accent);
        let secs = format!("{:02}", self.left.max(0.0).ceil() as u32);
        let blink = self.left < 3.0 && (get_time() * 4.0) as i64 % 2 == 1;
        r.text_centered(
            &secs,
            &app.assets.font_score,
            48.0 * s,
            w / 2.0,
            at(app, 0.0, TIMER_Y).y,
            0.0,
            if blink { gray } else { white },
        );

        // griglia: le caselle dei sette tipi e quella di OMEGA, il boss segreto (non si sceglie)
        for i in 0..CELLS {
            let cell = cell_rect(app, i);
            let texture = match PaddleKind::ALL.get(i) {
                Some(&kind) => portraits.small(kind),
                None => &portraits.omega_small,
            };
            draw_texture_ex(texture, cell.x, cell.y, WHITE, DrawTextureParams {
                dest_size: Some(cell.size()),
                ..Default::default()
            });
            draw_rectangle_lines(cell.x, cell.y, cell.w, cell.h, u, frame);
            if i >= PaddleKind::COUNT {
                let omega = App::color([0xE0, 0x40, 0xFF]);
                r.text_centered("?", font, t1, cell.center().x, cell.y + cell.h - 6.0 * u, 0.0, omega);
            }
        }

        // il campo sotto la griglia: rete tratteggiata e le due racchette a grandezza reale
        let mut y = COURT_Y + 2.0;
        while y < COURT_Y + COURT_H {
            let top = at(app, 160.0, y);
            draw_rectangle(top.x - u, top.y, 2.0 * u, 5.0 * u, white);
            y += 8.0;
        }

        for side in 0..2 {
            let kind = PaddleKind::ALL[self.cursor[side]];
            // ritratto grande, il personaggio intero; quello di destra guarda il centro
            let corner = at(app, PORTRAIT_X[side], PORTRAIT_Y);
            draw_texture_ex(portraits.big(kind), corner.x, corner.y, WHITE, DrawTextureParams {
                dest_size: Some(vec2(PORTRAIT_W, PORTRAIT_H) * u),
                flip_x: side == 1,
                ..Default::default()
            });
            let mid = PORTRAIT_X[side] + PORTRAIT_W / 2.0;
            r.text_centered(&self.name(side), font, t1, at(app, mid, 0.0).x, at(app, 0.0, line(4)).y, 0.0, white);
            // OK verso la griglia (sul touch, finché non si sceglie, il pulsante da toccare)
            let ok = at(app, mid + if side == 0 { 28.0 } else { -28.0 }, line(4));
            if self.chosen[side] {
                r.text_centered("OK", font, t1, ok.x, ok.y, 0.0, accent);
            } else if app.touch && self.fixed != Some(side) && self.ready.is_none() {
                draw_rectangle(ok.x - 16.0 * u, ok.y - 7.0 * u, 32.0 * u, 14.0 * u, accent);
                r.text_centered("OK", font, t1, ok.x, ok.y, 0.0, App::color(colors.black));
            }
            // il nome disegnato sotto il ritratto, dentro lo schermo
            let name = app.assets.titles.name(kind);
            let half = name.w / 2.0 + 2.0;
            let cx = mid.clamp(half, 320.0 - half);
            let paint = crate::titles::paint(colors);
            r.art_centered(name, 1.0, at(app, cx, 0.0).x, at(app, 0.0, NAME_Y).y, 0.0, ArtPart::Whole, &paint);
            let shape = Shape {
                kind: Some(kind),
                x: at(app, PADDLE_X[side], 0.0).x,
                y: r.world_h - at(app, 0.0, COURT_Y + COURT_H / 2.0).y,
                w: to_f32(p.pad_width),
                h: to_f32(p.kinds[kind as usize].height),
                front: if side == 0 { 1.0 } else { -1.0 },
                // TWIST si mostra inclinato, come quando sale
                tilt: if kind == PaddleKind::Twist { TWIST_MAX_TILT } else { 0.0 },
                dash: None,
                preview: true,
                anim: Anim::still(get_time() as f32),
            };
            draw_paddle(r, &shape, u, look(app, Some(kind), white));
            let half_x = at(app, HALF_X[side], 0.0).x;
            r.text_centered(tagline(kind), font, t1, half_x, at(app, 0.0, line(22)).y, 0.0, white);
        }

        // cursori sopra la griglia, gialli tutti e due con la sigla del giocatore; finché si sceglie
        // lampeggiano (sul C64 sono sprite)
        let on = (get_time() * 4.0) as i64 % 4 != 3;
        for side in 0..2 {
            if !self.chosen[side] && self.fixed != Some(side) && self.ready.is_none() && !on {
                continue;
            }
            let cell = cell_rect(app, self.cursor[side]);
            draw_rectangle_lines(cell.x, cell.y, cell.w, cell.h, 4.0 * u, accent);
            let tag = if self.cpu && self.fixed == Some(side) { "CPU".to_string() } else { format!("{}P", side + 1) };
            let tag_w = (tag.len() as f32 * 8.0 + 2.0) * u;
            let x = if side == 0 { cell.x + 2.0 * u } else { cell.x + cell.w - 2.0 * u - tag_w };
            // in basso; con i due cursori sulla stessa casella quella di destra va in alto, se no le
            // sigle si coprono
            let top = side == 1 && self.cursor[0] == self.cursor[1];
            let y = if top { cell.y + 1.0 * u } else { cell.y + cell.h - 10.0 * u };
            draw_rectangle(x, y, tag_w, 9.0 * u, BLACK);
            r.text_centered(&tag, font, t1, x + tag_w / 2.0, y + 4.5 * u, 0.0, accent);
        }

        let hint_y = at(app, 0.0, line(24)).y;
        if self.ready.is_some() && (get_time() * 6.0) as i64 % 2 == 0 {
            r.text_centered("READY!", font, t1, w / 2.0, hint_y, 0.0, accent);
        } else if self.ready.is_none() {
            for side in self.choosing() {
                if app.touch && self.chosen[side] {
                    continue;
                }
                let hint = match (app.touch, side) {
                    (true, _) => "TAP OK TO CHOOSE",
                    (false, 0) => "WASD + C",
                    (false, _) => "ARROWS + -",
                };
                r.text_centered(hint, font, t1, at(app, HALF_X[side], 0.0).x, hint_y, 0.0, gray);
            }
        }
    }
}

// La disposizione della scelta, in pixel del campo 320x240 e allineata ai caratteri da 8 pixel del
// C64 (40x25 a partire dalla riga `TOP`, come lì): riga 0 il titolo, 1-3 il tempo, 4 P1/P2 e OK,
// 5-17 i ritratti grandi (11x13 caratteri, colonne 0-10 e 29-39), 5-12 la griglia 4x2 di caselle
// 4x4 (colonne 12-27), 13-21 il campo con le due racchette, 18-21 i nomi, 22 le frasi, 24 i comandi.
pub(crate) const TOP: f32 = 20.0;
pub(crate) const PORTRAIT_W: f32 = 88.0;
pub(crate) const PORTRAIT_H: f32 = 104.0;
pub(crate) const PORTRAIT_X: [f32; 2] = [0.0, 320.0 - PORTRAIT_W];
const PORTRAIT_Y: f32 = TOP + 5.0 * 8.0;
const GRID_X: f32 = 12.0 * 8.0;
const GRID_Y: f32 = PORTRAIT_Y;
const CELL: f32 = 32.0;
/// caselle della griglia: i sette tipi e OMEGA
const CELLS: usize = PaddleKind::COUNT + 1;

/// Tasti di sinistra e destra nella griglia, per lato (su e giù sono quelli di `PICK_KEYS`).
const SIDE_KEYS: [(KeyCode, KeyCode); 2] = [(KeyCode::A, KeyCode::D), (KeyCode::Left, KeyCode::Right)];

/// Un passo del cursore nella griglia 4x2 (`cell_rect`).
#[derive(Clone, Copy)]
enum GridStep {
    /// destra e sinistra: la racchetta dopo o prima, da una riga all'altra e in giro
    Next,
    Prev,
    /// su e giù: l'altra riga, stessa colonna; sotto TWIST c'è OMEGA, che non si sceglie: fermo
    Row,
}

fn grid_step(i: usize, step: GridStep) -> usize {
    let n = PaddleKind::COUNT;
    match step {
        GridStep::Next => (i + 1) % n,
        GridStep::Prev => (i + n - 1) % n,
        GridStep::Row => Some((i + 4) % CELLS).filter(|&j| j < n).unwrap_or(i),
    }
}
const TIMER_Y: f32 = TOP + 8.0 + 12.0;
const COURT_Y: f32 = TOP + 13.0 * 8.0;
const COURT_H: f32 = 9.0 * 8.0;
pub(crate) const PADDLE_X: [f32; 2] = [14.0 * 8.0 + 4.0, 25.0 * 8.0 + 4.0];
const NAME_Y: f32 = TOP + 18.0 * 8.0 + 16.0;
/// centro di ciascuna metà, per le frasi e i comandi
pub(crate) const HALF_X: [f32; 2] = [80.0, 240.0];

/// Centro verticale della riga di caratteri `row`.
pub(crate) fn line(row: u32) -> f32 {
    TOP + row as f32 * 8.0 + 4.0
}

/// Punto (x, y) in pixel del campo 320x240, centrato orizzontalmente, in coordinate di disegno.
pub(crate) fn at(app: &App, x: f32, y: f32) -> Vec2 {
    let u = unit(app);
    vec2(app.renderer.world_w / 2.0 + (x - 160.0) * u, y * u)
}

/// Riquadro della casella `i` della griglia (prima riga ARCADE-TWIST, seconda BLASTER-OMEGA).
fn cell_rect(app: &App, i: usize) -> Rect {
    let u = unit(app);
    let corner = at(app, GRID_X + (i % 4) as f32 * CELL, GRID_Y + (i / 4) as f32 * CELL);
    Rect::new(corner.x, corner.y, CELL * u, CELL * u)
}
