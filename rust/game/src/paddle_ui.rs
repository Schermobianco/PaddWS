//! Tipi di racchetta di NEXT a schermo: il disegno di ogni tipo, uguale in partita e
//! nella scelta, e la schermata di scelta della racchetta, dopo quella dei bonus.
//!
//! Ogni racchetta è l'astronave vista dall'alto pilotata dal suo personaggio, nel colore del
//! personaggio (`Portraits::accent`): ARCADE la capsula coin-op con calotte metalliche, cabina
//! gettoniera dorata e scia di scintille, TITAN la corazzata pesante con cintura/ponte e due
//! blocchi motori posteriori, HAMMER la nave-ariete a "T" con striscia rossa e grande reattore
//! centrale d'urto, TWIST il caccia acrobatico inclinato con visiera da luchador e getti di
//! manovra RCS sulle virate, BLASTER la cannoniera con livrea a "X", doppi cannoni alari laser
//! verdi alternati e cartuccera posteriore, RUSH l'intercettore supersonico ad ali a freccia con
//! postbruciatore nitro e scie alari, GUARDIAN il portascudo orbitale con chiglia posteriore e
//! cinque piastre scudo anteriori indipendenti. La faccia che colpisce resta un bordo dritto:
//! davanti vanno solo le canne di BLASTER e gli effetti brevi dopo un colpo. Cambia solo il
//! disegno, la hitbox è quella del core.
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

/// ARCADE: durata dell'animazione del gettone che si infila nella fessura (doppio clic USE).
pub(crate) const COIN_SECONDS: f32 = 0.5;
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
/// Scatto in avanti: durata dell'accensione dei booster (15 frame a 60 Hz, come le immagini del RUSH).
pub(crate) const BOOST_SECONDS: f32 = 0.25;

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
}

/// I colori di una racchetta del tipo `kind` con il corpo `body`.
pub fn look(app: &App, kind: Option<PaddleKind>, body: Color) -> Look {
    let fallback = App::color(app.cfg.colors.accent);
    Look {
        body,
        mark: kind.map_or(fallback, |k| app.assets.portraits.accent(k)),
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
    /// ARCADE: secondi dall'inserimento del gettone (doppio clic USE a riserva vuota)
    pub coin: Option<f32>,
    /// BLASTER: colpi nella carica (al massimo 6), progresso di ricarica (0..1 se in corso)
    /// e secondi dall'ultimo sparo
    pub ammo: u8,
    pub reload: Option<f32>,
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
            coin: None,
            ammo: 6,
            reload: None,
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
    /// sfuma in `BOOST_SECONDS`); tutte accendono i booster, RUSH lascia anche immagini nel suo
    /// colore tra la partenza e dove si trova
    pub dash: Option<(f32, f32)>,
    /// anteprima della scelta: RUSH mostra sempre le immagini dello scatto
    pub preview: bool,
    /// ritaglio verticale in coordinate di schermo (y0..y1), usato dal salto del TELEPORT
    pub clip_y: Option<(f32, f32)>,
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
    /// grigi (chiaro, luce, scuro, profondo)
    Gray,
    GrayLight,
    Dark,
    DarkDeep,
    Black,
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

/// Accensione dei booster allo scatto in avanti, per tutte le racchette: fase (3 nei primi 3
/// frame, con il lampo agli ugelli, 2 fino al nono, 1 fino al quindicesimo, 0 spenti) e
/// allungamento delle fiamme in pixel arcade, che parte dalla distanza da casa e si dimezza a ogni
/// fase (il getto lasciato lungo lo scatto).
#[derive(Clone, Copy, Default)]
struct Boost {
    stage: u8,
    extra: f32,
}

impl Boost {
    /// Dallo scatto in corso: `fade` va da 1 (appena partito) a 0, `dist` è la distanza da casa in
    /// pixel arcade.
    fn new(fade: f32, dist: f32) -> Self {
        let left = (fade * 15.0).round();
        let dist = dist.round().max(0.0);
        if left >= 13.0 {
            Self { stage: 3, extra: dist }
        } else if left >= 7.0 {
            Self { stage: 2, extra: (dist / 2.0).floor() }
        } else if left >= 1.0 {
            Self { stage: 1, extra: (dist / 4.0).floor() }
        } else {
            Self::default()
        }
    }
}

/// Lampo dell'accensione dietro un ugello che finisce alla colonna `x_end`: alone largo 3 nel colore
/// del personaggio, più chiaro sulle righe del getto e bianco al centro (`y` e `rows`: righe del
/// nucleo del getto).
fn ignite(r: &mut Ops, x_end: f32, y: f32, rows: f32) {
    r.late_rect(x_end - 3.0, y - 2.0, 3.0, rows + 4.0, Role::Mark);
    r.late_rect(x_end - 3.0, y - 1.0, 3.0, rows + 2.0, Role::MarkLight);
    r.late_rect(x_end - 2.0, y, 2.0, rows, Role::Body);
}

/// Sfarfallio delle fiamme a 16 al secondo (0 o 1), il doppio delle pose.
fn flicker(t: f32) -> usize {
    ((t * 16.0).floor() as i64).rem_euclid(2) as usize
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

/// GUARDIAN: spostamento verticale della piastra scudo `i` durante la costruzione, a `t` secondi
/// dall'inizio: le piastre cadono da 14 pixel una alla volta, dal basso, ogni 0,3 s, e rimbalzano
/// di 1 pixel; None finché la piastra non è ancora entrata.
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

/// GUARDIAN (BASTION-5): portascudo orbitale modulare. Chiglia posteriore compatta con ponte blu,
/// stabilizzatori e due micro-propulsori azzurri; davanti 5 piastre scudo indipendenti (una per
/// settore del core dall'alto) con impulso di scansione blu. Un settore perso lampeggia (0,15 s),
/// poi la piastra si spegne in grigio scuro e perde quattro frammenti; all'ultimo rimasto lampeggia
/// in allarme.
fn wall(r: &mut Ops, h: f32, a: &Anim, boost: Boost) {
    let n = GUARDIAN_SECTORS;
    let tq = (pose(a.t) as i64).rem_euclid(120) as usize;
    let mid = (h / 2.0).floor();
    // chiglia posteriore, stabilizzatori e due propulsori ionici a cono (sempre dietro lo scudo)
    r.rect(-7.0, 5.0, 4.0, h - 10.0, Role::Gray);
    r.rect(-8.0, mid - 3.0, 3.0, 6.0, Role::Dark);
    r.rect(-7.0, mid - 2.0, 2.0, 4.0, Role::Mark);
    r.rect(-5.0, 2.0, 3.0, 3.0, Role::Mark);
    r.rect(-5.0, h - 5.0, 3.0, 3.0, Role::Mark);
    let moving = a.vy.abs() > 0.5 || boost.stage > 0;
    for (idx, ey) in [7.0, h - 9.0].into_iter().enumerate() {
        r.rect(-8.0, ey - 1.0, 1.0, 4.0, Role::DarkDeep);
        let p = (tq + idx * 2) % 4;
        let fl = if moving { [6, 7, 8, 7][p] } else { [4, 5, 6, 5][p] } + boost.extra as usize;
        let jlen = fl - 1;
        let clen = (fl / 2).max(2);
        r.late_rect(-9.0, ey - 1.0, 1.0, 4.0, Role::Mark);
        r.late_rect(-8.0 - jlen as f32, ey, jlen as f32, 2.0, Role::MarkLight);
        r.late_rect(-8.0 - clen as f32, ey, clen as f32, 2.0, Role::Body);
        r.late_rect(-9.0 - fl as f32, ey + (p % 2) as f32, 2.0, 1.0, Role::Mark);
        if moving {
            let s = (tq + idx) % 2;
            r.late_rect(-10.0 - fl as f32 - s as f32, ey + s as f32, 1.0, 1.0, Role::MarkLight);
        }
        if boost.stage == 3 {
            ignite(r, -9.0, ey, 2.0);
        }
    }

    let alive = a.wall.iter().filter(|w| w.is_none()).count();
    let scan = tq % n;
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
        let ys = if i > 0 { y0 + 1.0 } else { y0 };
        let hh = y1 - ys;
        match a.wall[i] {
            None => {
                let warn = alive == 1 && (tq % 4) < 2;
                rect(-2.0, y0, 4.0, y1 - y0, if warn { Role::MarkLight } else { Role::Body });
                rect(-2.0, ys, 1.0, hh, if scan == i || warn { Role::MarkLight } else { Role::Mark });
            }
            Some(age) if age < 0.15 => {
                rect(-2.0, y0, 4.0, y1 - y0, Role::MarkLight);
                rect(-1.0, ys + 1.0, 2.0, (hh - 2.0).max(1.0), Role::Mark);
            }
            Some(age) => {
                rect(-2.0, y0, 4.0, y1 - y0, Role::Dark);
                rect(-1.0, ys + 1.0, 2.0, (hh - 2.0).max(1.0), Role::DarkDeep);
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
            let gap = if a.wall[i].is_some() && a.wall[i - 1].is_some() {
                Role::Black
            } else {
                Role::Mark
            };
            rect(-2.0, y0, 4.0, 1.0, gap);
        }
    }
    r.late_rect(-3.0, 0.0, 1.0, h, Role::Black);
}

/// I pezzi dell'astronave `kind` alta `h` pixel arcade. `par` (-1 in cima, +1 in fondo) regola la
/// prospettiva 2.5D della corazzata TITAN.
fn kind_ops(kind: PaddleKind, h: f32, a: &Anim, par: f32, boost: Boost) -> Ops {
    let mut r = Ops::default();
    let mid = (h / 2.0).floor();
    let tq = (pose(a.t) as i64).rem_euclid(120) as usize;
    // con i booster accesi le fiamme si muovono come in movimento
    let moving = a.vy.abs() > 0.5 || boost.stage > 0;
    let extra = boost.extra;
    let ignited = boost.stage == 3;
    match kind {
        PaddleKind::Arcade => {
            // VAUS-84: capsula coin-op con calotte metalliche arrotondate, cabina gettoniera
            // dorata al centro, due alette posteriori e scia di scintille/monetine dai due ugelli
            let coin_f = a.coin.and_then(|s| (s < COIN_SECONDS).then(|| (s * 60.0).floor() as usize));
            let coin_flash = coin_f.is_some_and(|f| f >= 18);
            r.rect(-3.0, 4.0, 5.0, h - 8.0, Role::Body);
            r.rect(-3.0, 1.0, 5.0, 3.0, Role::Gray);
            r.rect(-2.0, 0.0, 4.0, 1.0, Role::Gray);
            r.rect(-3.0, h - 4.0, 5.0, 3.0, Role::Gray);
            r.rect(-2.0, h - 1.0, 4.0, 1.0, Role::Gray);
            r.late_rect(-3.0, 4.0, 4.0, 1.0, Role::Dark);
            r.late_rect(-3.0, h - 5.0, 4.0, 1.0, Role::Dark);
            r.rect(-5.0, 6.0, 2.0, 5.0, Role::Gray);
            r.rect(-5.0, h - 11.0, 2.0, 5.0, Role::Gray);
            r.rect(-6.0, 7.0, 1.0, 3.0, Role::Dark);
            r.rect(-6.0, h - 10.0, 1.0, 3.0, Role::Dark);
            let lit = (tq % 8) < 2;
            r.rect(-4.0, mid - 4.0, 4.0, 8.0, Role::Dark);
            let cabin_role = if coin_f.is_some_and(|f| (18..22).contains(&f)) {
                Role::Body
            } else if coin_flash || lit {
                Role::MarkLight
            } else {
                Role::Mark
            };
            r.rect(-3.0, mid - 3.0, 3.0, 6.0, cabin_role);
            r.late_rect(-2.0, mid - 2.0, 1.0, 4.0, Role::Black);
            let f = tq % 4;
            let fl = if moving { 3.0 } else { 2.0 } + extra;
            for ey in [8.0, h - 9.0] {
                r.rect(-6.0 - fl - (f % 2) as f32, ey, fl, 1.0, Role::MarkLight);
                r.rect(-8.0 - (f * 2) as f32 - extra, ey + if f % 2 == 1 { 1.0 } else { -1.0 }, 1.0, 1.0, Role::Mark);
                if ignited {
                    ignite(&mut r, -6.0, ey, 1.0);
                }
            }
            // animazione del gettone che entra nella fessura della gettoniera (doppio clic USE)
            if let Some(cf) = coin_f {
                if cf < 12 {
                    let cx = -17.0 + cf as f32;
                    r.late_rect(cx, mid - 1.0, 4.0, 2.0, Role::Mark);
                    r.late_rect(cx + 1.0, mid - 2.0, 2.0, 4.0, Role::Mark);
                    r.late_rect(cx + 1.0, mid - 2.0, 2.0, 1.0, Role::MarkLight);
                    r.late_rect(cx + 1.0, mid + 1.0, 2.0, 1.0, Role::MarkDark);
                    if (cf / 3).is_multiple_of(2) {
                        r.late_rect(cx + 1.0, mid - 1.0, 1.0, 2.0, Role::Body);
                    } else {
                        r.late_rect(cx + 2.0, mid - 1.0, 1.0, 2.0, Role::MarkLight);
                    }
                } else if cf < 14 {
                    r.late_rect(-5.0, mid - 2.0, 3.0, 4.0, Role::Mark);
                    r.late_rect(-5.0, mid - 2.0, 2.0, 1.0, Role::MarkLight);
                    r.late_rect(-4.0, mid - 1.0, 1.0, 2.0, Role::Body);
                } else if cf < 16 {
                    r.late_rect(-4.0, mid - 2.0, 2.0, 4.0, Role::MarkLight);
                    r.late_rect(-3.0, mid - 1.0, 1.0, 2.0, Role::Body);
                } else if cf < 18 {
                    r.late_rect(-3.0, mid - 2.0, 1.0, 4.0, Role::Body);
                } else {
                    let (d, srole) = if cf < 22 {
                        (0.0, Role::Body)
                    } else if cf < 26 {
                        (1.0, Role::MarkLight)
                    } else {
                        (2.0, Role::Mark)
                    };
                    r.late_rect(-2.0 - d * 2.0, mid - 5.0 - d, 1.0, 1.0, srole);
                    r.late_rect(-2.0 - d * 2.0, mid + 4.0 + d, 1.0, 1.0, srole);
                    r.late_rect(-5.0 - d * 2.0, mid - 2.0 - d, 1.0, 1.0, srole);
                    r.late_rect(-5.0 - d * 2.0, mid + 1.0 + d, 1.0, 1.0, srole);
                }
            }
        }
        PaddleKind::Titan => {
            // COLOSSUS: corazzata pesante in prospettiva 2.5D — fiancata 3D estrusa, ponte superiore
            // rialzato e torre di comando con ombra propria e parallasse verticale (`par`) così
            // appare molto più alta e imponente delle altre racchette (hitbox invariata)
            let yb = round(h / 2.0) - 3.0;
            let wall_bot = (2.0 - par * 2.0).clamp(0.0, 3.5);
            let wall_top = (par * 2.5 - 0.5).clamp(0.0, 2.0);
            let dy_p = round(par * 2.0);
            // due enormi pod motori posteriori (al livello inferiore dello scafo, sotto la fiancata)
            // con fiamme booster coniche affusolate e nucleo incandescente (niente bordi squadrati)
            for (idx, my) in [2.0, h - 12.0].into_iter().enumerate() {
                r.rect(-11.0, my, 4.0, 10.0, Role::Gray);
                r.rect(-10.0, my + 2.0, 2.0, 6.0, Role::Dark);
                r.rect(-12.0, my + 1.0, 1.0, 8.0, Role::DarkDeep);
                let p = (tq + idx * 2) % 4;
                let fl = if moving { [6, 8, 7, 8][p] } else { [4, 5, 6, 5][p] } + extra as usize;
                let mlen = fl.div_ceil(2);
                let jlen = fl - 1;
                let clen = (fl / 2).max(2);
                r.late_rect(-13.0, my + 2.0, 1.0, 6.0, Role::Mark);
                r.late_rect(-12.0 - mlen as f32, my + 3.0, mlen as f32, 4.0, Role::Mark);
                r.late_rect(-13.0, my + 3.0, 1.0, 4.0, Role::MarkLight);
                r.late_rect(-12.0 - jlen as f32, my + 4.0, jlen as f32, 2.0, Role::MarkLight);
                r.late_rect(-12.0 - clen as f32, my + 4.0, clen as f32, 2.0, Role::Body);
                r.late_rect(-13.0 - fl as f32, my + 4.0 + (p % 2) as f32, 2.0, 1.0, Role::Mark);
                if moving {
                    let s = (tq + idx) % 3;
                    let srole = if s == 0 { Role::MarkLight } else { Role::Mark };
                    r.late_rect(-14.0 - fl as f32 - s as f32, my + 3.0 + ((s + idx) % 3) as f32, 1.0, 1.0, srole);
                }
                if ignited {
                    ignite(&mut r, -13.0, my + 4.0, 2.0);
                }
            }
            // fiancate 3D verticali dello scafo (danno spessore e altezza in prospettiva)
            r.rect(-8.0, 1.0, 2.0, h - 2.0, Role::DarkDeep);
            r.rect(-7.0, 1.0, 1.0, h - 2.0, Role::Dark);
            if wall_bot > 0.25 {
                r.rect(-7.0, h, 9.0, wall_bot, Role::DarkDeep);
                r.rect(-6.0, h, 8.0, (wall_bot - 1.0).max(0.5), Role::Dark);
            }
            if wall_top > 0.25 {
                r.rect(-7.0, -wall_top, 9.0, wall_top, Role::Dark);
                r.rect(-6.0, -wall_top, 8.0, 1.0, Role::Gray);
            }
            // scafo principale corazzato (faccia anteriore dritta sulla hitbox, x = -6..+2)
            r.rect(-6.0, 0.0, 8.0, h, Role::Body);
            // ponte superiore rialzato (gradino centrale con ombra sul ponte inferiore)
            r.rect(-6.0, 6.0, 1.0, h - 12.0, Role::Dark);
            r.rect(-5.0, 6.0, 6.0, h - 12.0, Role::GrayLight);
            r.rect(-4.0, 7.0, 5.0, h - 14.0, Role::Body);
            r.late_rect(-6.0, 11.0, 6.0, 1.0, Role::Dark);
            r.late_rect(-6.0, h - 12.0, 6.0, 1.0, Role::Dark);
            // basamento e ombra della torre di comando sullo scafo sottostante
            r.late_rect(-7.0, yb + 1.0, 7.0, 7.0, Role::DarkDeep);
            r.late_rect(-6.0, yb - 1.0, 7.0, 8.0, Role::Dark);
            // tetto della torre di comando sopraelevato (si sposta in parallasse 2.5D con `dy_p`)
            let ty = yb + dy_p;
            r.late_rect(-5.0, ty, 6.0, 6.0, Role::Mark);
            r.late_rect(-5.0, ty, 6.0, 1.0, Role::MarkLight);
            r.late_rect(-5.0, ty + 5.0, 6.0, 1.0, Role::MarkDark);
            r.late_rect(-4.0, ty + 1.0, 4.0, 4.0, Role::GrayLight);
            r.late_rect(-3.0, ty + 2.0, 2.0, 2.0, Role::DarkDeep);
            r.late_rect(-2.0, ty + 2.0, 1.0, 2.0, Role::MarkLight);
        }
        PaddleKind::Hammer => {
            // ANVIL-MK1: nave-martello / ariete a "T" con fronte corazzato, striscia rossa da
            // battaglia e grande booster centrale d'urto che si allunga al colpo
            let yc = round(h / 2.0);
            r.rect(-4.0, 0.0, 6.0, h, Role::Body);
            r.rect(-4.0, 0.0, 2.0, 5.0, Role::Gray);
            r.rect(-4.0, h - 5.0, 2.0, 5.0, Role::Gray);
            r.rect(-3.0, 5.0, 2.0, h - 10.0, Role::Mark);
            r.late_rect(-4.0, 5.0, 1.0, h - 10.0, Role::Dark);
            r.rect(-10.0, yc - 5.0, 6.0, 10.0, Role::Gray);
            r.rect(-8.0, yc - 4.0, 4.0, 8.0, Role::Dark);
            r.rect(-7.0, yc - 3.0, 3.0, 6.0, Role::Mark);
            r.rect(-11.0, yc - 6.0, 2.0, 12.0, Role::Dark);
            r.late_rect(-10.0, yc - 4.0, 1.0, 8.0, Role::GrayLight);
            // booster conico: compatto a riposo, esplode allungandosi fino a 11 px al colpo
            let surge = match a.spark {
                Some((s, _)) if s < 0.14 => 3,
                Some((s, _)) if s < 0.25 => 2,
                Some((s, _)) if s < 0.35 => 1,
                _ => 0,
            };
            let piston_beat = tq % 2 == 1;
            let fl: usize = match surge {
                3 => 11,
                2 => 9,
                1 => 7,
                _ => [4, 5, 4, 3][tq % 4],
            };
            let tlen = if fl >= 9 { 3 } else if fl >= 6 { 2 } else { 1 };
            let mlen = (fl * 2) / 3;
            // i booster allungano il getto e la punta, non il cono (che segue il colpo)
            let fl = fl + extra as usize;
            let jlen = fl - 1;
            let clen = (fl / 2).max(2);
            if surge == 3 {
                r.late_rect(-12.0, yc - 4.0, 1.0, 8.0, Role::Mark);
            }
            r.late_rect(-11.0 - tlen as f32, yc - 3.0, tlen as f32, 6.0, Role::Mark);
            r.late_rect(-11.0 - mlen as f32, yc - 2.0, mlen as f32, 4.0, Role::Mark);
            if surge >= 1 {
                let hlen = (mlen / 2).max(1);
                r.late_rect(-11.0 - hlen as f32, yc - 2.0, hlen as f32, 4.0, Role::MarkLight);
            }
            r.late_rect(-11.0 - jlen as f32, yc - 1.0, jlen as f32, 2.0, Role::MarkLight);
            r.late_rect(-11.0 - clen as f32, yc - 1.0, clen as f32, 2.0, Role::Body);
            r.late_rect(-12.0 - fl as f32, yc - 1.0 + (tq % 2) as f32, 2.0, 1.0, Role::Mark);
            if surge >= 2 {
                r.late_rect(-11.0 - fl as f32, yc - 1.0 + (tq % 2) as f32, 1.0, 1.0, Role::MarkLight);
            }
            if ignited {
                ignite(&mut r, -11.0, yc - 1.0, 2.0);
            }
            // micro-vibrazione meccanica della racchetta a ogni battito del pistone (e al colpo)
            if surge >= 2 || piston_beat {
                r.shift(0, -1.0);
            }
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
            // VORTEX: caccia acrobatico affusolato con cabina-visiera da luchador viola, alette
            // giroscopiche, ugello rotante e getti di manovra RCS sulle virate
            r.rect(-3.0, 3.0, 5.0, h - 6.0, Role::Body);
            r.rect(-2.0, 1.0, 4.0, 2.0, Role::Body);
            r.rect(-1.0, 0.0, 3.0, 1.0, Role::Gray);
            r.rect(-2.0, h - 3.0, 4.0, 2.0, Role::Body);
            r.rect(-1.0, h - 1.0, 3.0, 1.0, Role::Gray);
            r.rect(-6.0, 7.0, 3.0, 6.0, Role::Mark);
            r.rect(-7.0, 9.0, 2.0, 3.0, Role::Gray);
            r.rect(-6.0, h - 13.0, 3.0, 6.0, Role::Mark);
            r.rect(-7.0, h - 12.0, 2.0, 3.0, Role::Gray);
            r.rect(-5.0, mid - 5.0, 5.0, 10.0, Role::Mark);
            r.late_rect(-4.0, mid - 4.0, 3.0, 8.0, Role::MarkDark);
            r.late_rect(-3.0, mid - 3.0, 2.0, 6.0, Role::Mark);
            r.late_rect(-2.0, mid - 2.0, 2.0, 1.0, Role::Body);
            r.late_rect(-2.0, mid + 1.0, 2.0, 1.0, Role::Body);
            let ph = tq % 4;
            let dy = match ph {
                1 => -1.0,
                3 => 1.0,
                _ => 0.0,
            };
            let fl = if moving { [2, 3, 2, 3][ph] } else { [0, 1, 0, 1][ph] } as f32 + extra;
            let clen = 2.0 + (fl / 2.0).floor();
            r.rect(-7.0, mid - 2.0, 2.0, 4.0, Role::Dark);
            r.late_rect(-9.0, mid - 2.0, 2.0, 4.0, Role::Mark);
            r.late_rect(-10.0 - fl, mid - 1.0 + dy, 3.0 + fl, 2.0, Role::MarkLight);
            r.late_rect(-7.0 - clen, mid - 1.0 + dy, clen, 2.0, Role::Body);
            r.late_rect(-12.0 - fl, mid - 1.0 + dy + (ph % 2) as f32, 2.0, 1.0, Role::Mark);
            if ignited {
                ignite(&mut r, -9.0, mid - 1.0, 2.0);
            }
            let p = (tq % 2) as f32;
            if a.vy < -0.5 {
                // sale: getto RCS brillante dal pod inferiore (nucleo bianco + scia diagonale/verticale)
                r.late_rect(-13.0 - p, h - 8.0, 3.0, 3.0 + p, Role::Mark);
                r.late_rect(-11.0, h - 3.0 + p, 2.0, 3.0, Role::Mark);
                r.late_rect(-11.0, h - 10.0, 3.0, 4.0 + p, Role::MarkLight);
                r.late_rect(-10.0, h - 6.0, 2.0, 4.0 + p, Role::MarkLight);
                r.late_rect(-9.0, h - 11.0, 2.0, 3.0, Role::Body);
                r.late_rect(-9.0, h - 8.0, 1.0, 3.0, Role::Body);
                r.late_rect(-13.0 - p, h - 2.0 + p, 1.0, 1.0, Role::Body);
            } else if a.vy > 0.5 {
                // scende: getto RCS brillante dal pod superiore (speculare)
                r.late_rect(-13.0 - p, 5.0 - p, 3.0, 3.0 + p, Role::Mark);
                r.late_rect(-11.0, -p, 2.0, 3.0, Role::Mark);
                r.late_rect(-11.0, 6.0 - p, 3.0, 4.0 + p, Role::MarkLight);
                r.late_rect(-10.0, 2.0 - p, 2.0, 4.0 + p, Role::MarkLight);
                r.late_rect(-9.0, 8.0, 2.0, 3.0, Role::Body);
                r.late_rect(-9.0, 5.0, 1.0, 3.0, Role::Body);
                r.late_rect(-13.0 - p, 1.0 - p, 1.0, 1.0, Role::Body);
            }
            if let Some((s, _)) = a.spark
                && s < RING_SECONDS
            {
                ring(&mut r, h, s);
            }
        }
        PaddleKind::Blaster => {
            // VIPER-X: cannoniera d'assalto con livrea verde a "X", ali corte con motorini verdi,
            // due cannoni alari laser con rinculo e lampo verde simultanei e barra di carica laser
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
            // ali corte posteriori + ugelli e booster al plasma verde
            r.rect(-6.0, 3.0, 3.0, 5.0, Role::Gray);
            r.rect(-6.0, h - 8.0, 3.0, 5.0, Role::Gray);
            for (idx, ey) in [5.0, h - 6.0].into_iter().enumerate() {
                r.rect(-7.0, ey - 1.0, 1.0, 3.0, Role::DarkDeep);
                let p = (tq + idx * 2) % 4;
                let fl = if moving { [6, 8, 7, 8][p] } else { [4, 5, 6, 5][p] } as f32 + extra;
                let mlen = ((fl as i32 + 1) / 2) as f32;
                let jlen = fl - 1.0;
                let clen = (fl as i32 / 2).max(2) as f32;
                r.late_rect(-7.0 - mlen, ey - 1.0, mlen, 3.0, Role::Mark);
                r.late_rect(-8.0, ey - 1.0, 1.0, 3.0, Role::MarkLight);
                r.late_rect(-7.0 - jlen, ey, jlen, 1.0, Role::MarkLight);
                r.late_rect(-7.0 - clen, ey, clen, 1.0, Role::Body);
                r.late_rect(-8.0 - fl, ey, 2.0, 1.0, Role::Mark);
                if moving {
                    let s = (tq + idx) % 3;
                    let spark_col = if s == 0 { Role::MarkLight } else { Role::Mark };
                    r.late_rect(-9.0 - fl - s as f32, ey - 1.0 + ((s + idx) % 3) as f32, 1.0, 1.0, spark_col);
                }
                if ignited {
                    ignite(&mut r, -8.0, ey, 1.0);
                }
            }
            // livrea a "X" verde sul dorso (colonne -3..-1, identica su PC e MiSTer)
            r.late_rect(-3.0, mid - 4.0, 1.0, 2.0, Role::Mark);
            r.late_rect(-1.0, mid - 4.0, 1.0, 2.0, Role::Mark);
            r.late_rect(-2.0, mid - 2.0, 1.0, 1.0, Role::MarkDark);
            r.late_rect(-2.0, mid - 1.0, 1.0, 2.0, Role::Mark);
            r.late_rect(-2.0, mid + 1.0, 1.0, 1.0, Role::MarkDark);
            r.late_rect(-3.0, mid + 2.0, 1.0, 2.0, Role::Mark);
            r.late_rect(-1.0, mid + 2.0, 1.0, 2.0, Role::Mark);
            // bobine verdi e due cannoni laser alari davanti
            r.rect(-1.0, 8.0, 1.0, 2.0, Role::Mark);
            r.rect(2.0, 8.0, barrel, 2.0, Role::Gray);
            r.rect(-1.0, h - 10.0, 1.0, 2.0, Role::Mark);
            r.rect(2.0, h - 10.0, barrel, 2.0, Role::Gray);
            if recoil {
                let fx = 2.0 + barrel;
                for fy in [7.0, h - 11.0] {
                    r.rect(fx, fy, 2.0, 4.0, Role::Mark);
                    r.rect(fx + 1.0, fy + 1.0, 3.0, 2.0, Role::MarkLight);
                    r.rect(fx + 1.0, fy + 1.0, 2.0, 2.0, Role::Body);
                    r.rect(fx + 4.0, fy + 1.0, 2.0, 2.0, Role::MarkLight);
                }
            }
            // barra verticale di ricarica del condensatore laser (verde, da 0 a 19 px dal basso)
            let y0 = mid - 9.0;
            r.rect(-6.0, y0, 3.0, 21.0, Role::Dark);
            let ammo = a.ammo.min(6);
            let fill = if ammo > 0 {
                [0.0, 3.0, 6.0, 9.0, 13.0, 16.0, 19.0][ammo as usize]
            } else if let Some(p) = a.reload {
                round(p.clamp(0.0, 1.0) * 19.0)
            } else {
                0.0
            };
            if fill > 0.0 {
                let top = y0 + 20.0 - fill;
                r.rect(-6.0, top, 2.0, fill, Role::Mark);
                r.rect(-6.0, top, 2.0, fill.min(2.0), Role::MarkLight);
            }
            if recoil {
                r.shift(0, -1.0);
            }
        }
        PaddleKind::Rush => {
            // MACH-ZERO: intercettore supersonico ad ali a freccia ciano, cockpit filante,
            // ugello postbruciatore nitro (che piega contro `vy`) e scie d'aria dalle punte alari
            r.rect(-3.0, 0.0, 5.0, h, Role::Body);
            // ali a freccia spazzate indietro
            r.rect(-6.0, 1.0, 3.0, 5.0, Role::Body);
            r.rect(-9.0, 0.0, 4.0, 3.0, Role::Mark);
            r.rect(-11.0, 0.0, 2.0, 2.0, Role::MarkDark);
            r.rect(-6.0, h - 6.0, 3.0, 5.0, Role::Body);
            r.rect(-9.0, h - 3.0, 4.0, 3.0, Role::Mark);
            r.rect(-11.0, h - 2.0, 2.0, 2.0, Role::MarkDark);
            // cockpit centrale e ugello
            r.rect(-3.0, mid - 4.0, 3.0, 8.0, Role::Dark);
            r.rect(-2.0, mid - 3.0, 2.0, 6.0, Role::Mark);
            r.late_rect(-1.0, mid - 2.0, 1.0, 4.0, Role::MarkLight);
            r.rect(-5.0, mid - 2.0, 2.0, 4.0, Role::Gray);
            // postbruciatore nitro: lunghezza irregolare a quattro pose, alone che pulsa e punta che
            // sfarfalla a 16 al secondo, diamanti d'urto bianchi che scorrono lungo il getto e
            // scintille che si staccano; il getto piega contro `vy` (dritto nello scatto)
            let p = tq % 4;
            let fz = flicker(a.t);
            let fl = if a.dashing {
                [11, 13, 12, 14][p]
            } else {
                [5, 7, 6, 8][p] + if moving { 2 } else { 0 }
            } + extra as usize;
            let lean = if a.dashing {
                0.0
            } else if a.vy > 0.5 {
                -1.0
            } else if a.vy < -0.5 {
                1.0
            } else {
                0.0
            };
            let olen = (fl.div_ceil(2) + fz) as f32;
            let jlen = (fl - 1) as f32;
            let clen = (fl / 4 + 1) as f32;
            r.late_rect(-5.0 - olen, mid - 2.0, olen, 4.0, Role::Mark);
            r.late_rect(-5.0 - jlen, mid - 1.0 + lean, jlen, 2.0, Role::MarkLight);
            r.late_rect(-5.0 - clen, mid - 1.0, clen, 2.0, Role::Body);
            for k in 0..2 {
                let d = clen + 1.0 + (tq % 3) as f32 + 3.0 * k as f32;
                if d < jlen - 1.0 {
                    r.late_rect(-6.0 - d, mid - 1.0 + lean, 1.0, 2.0, Role::Body);
                }
            }
            r.late_rect(-6.0 - fl as f32, mid - 1.0 + lean + fz as f32, 2.0, 1.0, Role::Mark);
            if moving {
                let s = tq % 3;
                let srole = if s == 0 { Role::MarkLight } else { Role::Mark };
                r.late_rect(-7.0 - fl as f32 - s as f32, mid - 2.0 + ((p + s) % 4) as f32, 1.0, 1.0, srole);
            }
            if ignited {
                ignite(&mut r, -5.0, mid - 1.0, 2.0);
            }
            // scie d'aria dalle punte alari
            let wlen = if a.dashing { 4.0 } else { 2.0 };
            let w1 = (tq % 3) as f32;
            let w2 = ((tq + 1) % 3) as f32;
            let wrole = if a.dashing { Role::MarkLight } else { Role::Mark };
            r.rect(-12.0 - w1 - wlen, 1.0, wlen, 1.0, wrole);
            r.rect(-12.0 - w2 - wlen, h - 2.0, wlen, 1.0, wrole);
        }
        PaddleKind::Guardian => wall(&mut r, h, a, boost),
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
    draw_paddle_stretched(r, s, u, 1.0, look);
}

/// Come [`draw_paddle`], ma allunga orizzontalmente i pixel arcade del fattore `stretch_x` (usata
/// nello scatto iperspaziale del finale).
pub fn draw_paddle_stretched(r: &Renderer, s: &Shape, u: f32, stretch_x: f32, look: Look) {
    let (cx, cy, f) = (s.x, r.screen_y(s.y), s.front);
    let Some(kind) = s.kind else {
        if s.tilt != 0.0 {
            draw_rectangle_ex(cx, cy, s.w * stretch_x, s.h, DrawRectangleParams {
                offset: vec2(0.5, 0.5),
                rotation: -s.tilt * f,
                color: look.body,
            });
        } else {
            let mut y0 = cy - s.h / 2.0;
            let mut y1 = y0 + s.h;
            if let Some((cy0, cy1)) = s.clip_y {
                y0 = y0.max(cy0);
                y1 = y1.min(cy1);
                if y1 <= y0 {
                    return;
                }
            }
            let w = s.w * stretch_x;
            draw_rectangle(cx - w / 2.0, y0, w, y1 - y0, look.body);
        }
        return;
    };
    // pixel arcade della racchetta: il corpo largo 5 e alto `h` occupa esattamente la hitbox
    let h = (s.h / u).round().max(1.0);
    let (kx, ky) = ((s.w / 5.0) * stretch_x, s.h / h);
    let top = cy - s.h / 2.0;

    // RUSH: immagini dell'intercettore lungo lo scatto in avanti, più chiare verso la partenza
    // (nella scelta sempre: è il suo segno), comprese le ali a freccia
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
                let wx = if f > 0.0 { gx - s.w / 2.0 - 6.0 * kx } else { gx + s.w / 2.0 };
                draw_rectangle(wx, top, 6.0 * kx, 3.0 * ky, color);
                draw_rectangle(wx, top + s.h - 3.0 * ky, 6.0 * kx, 3.0 * ky, color);
            }
        }
    }

    // parallasse verticale (-1 in cima, +1 in fondo; 0 nell'anteprima): usata dalla prospettiva 2.5D di TITAN
    let par = if s.preview {
        0.0
    } else {
        ((cy / r.world_h - 0.5) * 2.0).clamp(-1.0, 1.0)
    };
    // booster accesi dallo scatto in avanti, con la distanza da casa in pixel arcade
    let boost = s.dash.map_or(Boost::default(), |(from, fade)| Boost::new(fade, (cx - from).abs() / kx));
    let ops = kind_ops(kind, h, &s.anim, par, boost);
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
                let mut ry0 = top + (y + oy) * ky;
                let mut ry1 = ry0 + hh;
                if let Some((cy0, cy1)) = s.clip_y {
                    ry0 = ry0.max(cy0);
                    ry1 = ry1.min(cy1);
                    if ry1 <= ry0 {
                        return;
                    }
                }
                draw_rectangle(x0, ry0, ww, ry1 - ry0, color);
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
            let mut pts = p.map(|(x, y)| point(x + ox, y + oy));
            if let Some((cy0, cy1)) = s.clip_y {
                let lo = pts[0].y.min(pts[1].y).min(pts[2].y);
                let hi = pts[0].y.max(pts[1].y).max(pts[2].y);
                if hi <= cy0 || lo >= cy1 {
                    return;
                }
                for pt in &mut pts {
                    pt.y = pt.y.clamp(cy0, cy1);
                }
            }
            draw_triangle(pts[0], pts[1], pts[2], color);
        }
    };
    let role_of = |op: &Op| match *op {
        Op::Rect { role, .. } | Op::Tri { role, .. } => role,
    };

    let mark_dark = scaled(look.mark, [0.6; 3]);
    let mark_light = lighter(look.mark, 0.45);
    let gray = rgb(180, 180, 180);
    let gray_light = rgb(226, 226, 230);
    let dark = rgb(92, 92, 98);
    let dark_deep = rgb(52, 52, 60);
    let color = |role: Role| match role {
        Role::Body => look.body,
        Role::Mark => look.mark,
        Role::MarkDark => mark_dark,
        Role::MarkLight => mark_light,
        Role::Gray => gray,
        Role::GrayLight => gray_light,
        Role::Dark => dark,
        Role::DarkDeep => dark_deep,
        Role::Black => BLACK,
    };

    // ombra portata sotto tutto: per TITAN è molto più staccata e profonda (effetto altezza 2.5D),
    // tranne quando ruota con il SUPER (evita l'ombra lontana che gira attorno allo scafo)
    if kind == PaddleKind::Titan && angle == 0.0 {
        let far_shadow = Color::from_rgba(26, 26, 38, 175);
        let mid_shadow = Color::from_rgba(40, 40, 52, 115);
        let sy_far = 3.5 - par * 1.5;
        let sy_mid = 2.0 - par * 0.8;
        for op in ops.0.iter().chain(&ops.1) {
            fill(op, far_shadow, -4.5, sy_far);
        }
        for op in ops.0.iter().chain(&ops.1) {
            fill(op, mid_shadow, -2.5, sy_mid);
        }
    } else {
        let shadow = rgb(48, 48, 58);
        for op in ops.0.iter().chain(&ops.1) {
            fill(op, shadow, -1.0, 1.0);
        }
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
        clip_y: None,
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
                clip_y: None,
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
