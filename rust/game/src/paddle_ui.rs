//! Tipi di racchetta di NEXT a schermo: il disegno di ogni tipo, uguale in partita e
//! nella scelta, e la schermata di scelta della racchetta, dopo quella dei bonus.
//!
//! Ogni racchetta è l'astronave vista dall'alto pilotata dal suo personaggio: lo sprite disegnato a
//! mano (`ships.rs`, `assets/ships/sprites`) con il corpo nel colore dello stato e i segni nel colore
//! del personaggio (`Portraits::accent`), più le animazioni a codice, attaccate agli agganci dello
//! sprite: fiamme, accensione e scia dei motori per tutti; ARCADE la cabina gettoniera che si accende
//! e il gettone, HAMMER il booster d'urto, il pistone e le scintille, TWIST i getti di manovra RCS
//! e l'onda del colpo, BLASTER le canne che rinculano, il lampo e il verde che fa da indicatore dei
//! colpi, RUSH il postbruciatore, le scie alari e le immagini dello scatto, GUARDIAN le cinque
//! piastre scudo (i settori del muro) che si montano, lampeggiano e si rompono. La faccia che
//! colpisce resta un bordo dritto: davanti vanno solo le canne di BLASTER e gli effetti brevi dopo
//! un colpo. Cambia solo il disegno, la hitbox è quella del core.
//!
//! Le forme sono in pixel arcade (schermo a 240 righe, hitbox larga 5), con la x che cresce verso
//! la faccia (la hitbox va da -3 a 1) e la y dalla cima; la racchetta destra è speculare. Sotto
//! tutto l'ombra portata, verso il retro e in basso.

use macroquad::prelude::*;
use paddws_core::fixed::to_f32;
use paddws_core::next::GUARDIAN_SECTORS;
use paddws_core::{Event, Paddle, PaddleKind, Side};

use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::{PICK_KEYS, Pick, READY_SECONDS, unit};
use crate::render::{ArtPart, Renderer};
use crate::scenes::{App, Menu, Scene};
use crate::ships::{self, Anchor, Ship};
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
    /// salto del TELEPORT: la racchetta si scompone o si ricompone a righe
    pub scan: Option<Scan>,
    pub anim: Anim,
}

/// Salto del TELEPORT: avanzamento da 0 a 32 (alla partenza quanto è scomposta, all'arrivo quanto è
/// ricomposta), se è la racchetta d'arrivo e la fase del tremolio delle righe in luce.
#[derive(Clone, Copy)]
pub struct Scan {
    pub level: i32,
    pub arriving: bool,
    pub jitter: bool,
}

/// TELEPORT: stato della riga `v` della racchetta (0 nascosta, 1 in luce, 2 piena). Ogni riga ha una
/// soglia fissa in ordine sparso (da 0 a 19); alla partenza la riga resta piena finché l'avanzamento
/// non arriva alla soglia, poi è in luce per 8 passi e sparisce; all'arrivo il contrario, con le
/// soglie rovesciate. Lo stesso calcolo fa `warp_row` di next_render.v sul MiSTer.
pub fn scan_row(v: i32, level: i32, arriving: bool) -> u8 {
    let th = (((v * 5) & 7) * 11) >> 2;
    let th = if arriving { 22 - th } else { th };
    match (arriving, level) {
        (false, l) if l < th => 2,
        (false, l) if l < th + 8 => 1,
        (false, _) => 0,
        (true, l) if l >= th + 8 => 2,
        (true, l) if l >= th => 1,
        (true, _) => 0,
    }
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
    /// il corpo, e in ombra
    Body,
    Shade,
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
    /// giallo dei segnali
    Signal,
}

#[derive(Clone, Copy)]
enum Op {
    Rect { x: f32, y: f32, w: f32, h: f32, role: Role },
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

    /// Sposta di `dx` i pezzi dal numero `from` in poi.
    fn shift(&mut self, from: usize, dx: f32) {
        for op in self.0[from..].iter_mut().chain(&mut self.1) {
            let Op::Rect { x, .. } = op;
            *x += dx;
        }
    }
}

/// Accensione dei booster allo scatto in avanti, per tutte le racchette: fase (3 nei primi 3
/// frame, con il lampo agli ugelli, 2 fino al nono, 1 fino al quindicesimo, 0 spenti) e lunghezza
/// in pixel arcade della scia tratteggiata dietro le fiamme (`trail`), che parte dalla distanza da
/// casa e si dimezza a ogni fase.
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

/// Scia dello scatto in avanti: una linea tratteggiata (un pixel sì e uno no) nel colore del
/// personaggio scurito, lunga `len` pixel oltre la punta della fiamma, che finisce alla colonna
/// `x_from`. Leggera di proposito: le fiamme restano della loro lunghezza.
fn trail(r: &mut Ops, x_from: f32, y: f32, len: f32) {
    let mut i = 0.0;
    while i < len {
        r.late_rect(x_from - 1.0 - i, y, 1.0, 1.0, Role::MarkDark);
        i += 2.0;
    }
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
/// in `RING_SECONDS`), come se la racchetta vibrasse. Copre il retro e la punta, mai l'astronave;
/// piena da vicina, scurita quando si allontana. `s`: secondi dal colpo.
fn ring(r: &mut Ops, ship: &Ship, h: f32, s: f32) {
    let p = (s / RING_SECONDS).clamp(0.0, 1.0);
    let rad = 3.0 + p * 7.0;
    for (cy, a0, a1) in [(2.0, 150.0f32, 300.0), (h - 2.0, 60.0, 210.0)] {
        let mut seen: Vec<(f32, f32)> = Vec::new();
        let mut deg = a0;
        while deg <= a1 {
            let (sin, cos) = deg.to_radians().sin_cos();
            let x = round(-0.5 + rad * cos - 0.5);
            let y = round(cy + rad * sin);
            let sv = (y * ship.h as f32 / h).floor() as i32;
            let on_body = y >= 0.0 && y < h && ship.at(x as i32, sv) != ships::NONE;
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

/// Ruolo di un pixel dello sprite.
fn sprite_role(px: u8) -> Role {
    match px {
        ships::BODY => Role::Body,
        ships::SHADE => Role::Shade,
        ships::MARK => Role::Mark,
        ships::MARK_DARK => Role::MarkDark,
        ships::MARK_LIGHT => Role::MarkLight,
        ships::GRAY => Role::Gray,
        ships::GRAY_LIGHT => Role::GrayLight,
        ships::DARK => Role::Dark,
        ships::DARK_DEEP => Role::DarkDeep,
        ships::SIGNAL => Role::Signal,
        _ => Role::Black,
    }
}

/// I pixel dello sprite `ship` sulla racchetta alta `h` (righe dello sprite ripetute o saltate se
/// l'altezza non è quella del tipo): `paint` riceve colonna, riga dello sprite e ruolo e dà il
/// ruolo da disegnare e lo spostamento, o None per non disegnarlo. I pixel vicini uguali di una riga
/// diventano un pezzo solo, alto 1: senza rilievo, perché lo sprite ha già le sue luci.
fn sprite(r: &mut Ops, ship: &Ship, h: f32, mut paint: impl FnMut(i32, i32, u8) -> Option<(Role, f32, f32)>) {
    let rows = h as i32;
    let (u0, u1) = ship.u_range();
    for v in 0..rows {
        let sv = if rows == ship.h as i32 { v } else { v * ship.h as i32 / rows };
        // pezzo in corso: prima colonna, colonne, ruolo e spostamento
        let mut run: Option<(i32, i32, Role, f32, f32)> = None;
        for u in u0..=u1 + 1 {
            let px = if u > u1 {
                None
            } else {
                match ship.at(u, sv) {
                    ships::NONE => None,
                    p => paint(u, sv, p),
                }
            };
            if let (Some((s, n, role, dx, dy)), Some((r2, dx2, dy2))) = (run, px)
                && role == r2
                && dx == dx2
                && dy == dy2
                && s + n == u
            {
                run = Some((s, n + 1, role, dx, dy));
                continue;
            }
            if let Some((s, n, role, dx, dy)) = run {
                r.rect(s as f32 + dx, v as f32 + dy, n as f32, 1.0, role);
            }
            run = px.map(|(role, dx, dy)| (u, 1, role, dx, dy));
        }
    }
}

/// Un tono più chiaro nel colore del personaggio (cabina accesa di ARCADE).
fn brighter(px: u8) -> u8 {
    match px {
        ships::MARK => ships::MARK_LIGHT,
        ships::MARK_DARK => ships::MARK,
        p => p,
    }
}

/// Spento: il colore del personaggio in grigio scuro (colpi esauriti del BLASTER).
fn dimmed(px: u8) -> u8 {
    match px {
        ships::MARK => ships::DARK,
        ships::MARK_DARK => ships::DARK_DEEP,
        ships::MARK_LIGHT => ships::GRAY,
        p => p,
    }
}

/// GUARDIAN: piastra rotta, tutto in grigio scuro.
fn broken(px: u8) -> u8 {
    match px {
        ships::BODY | ships::SHADE | ships::GRAY | ships::GRAY_LIGHT => ships::DARK,
        ships::BLACK => ships::BLACK,
        _ => ships::DARK_DEEP,
    }
}

/// GUARDIAN (BASTION-5): portascudo orbitale modulare. Davanti 5 piastre scudo indipendenti (una
/// per settore del core dall'alto, i pezzi dello sprite tra le giunture) con impulso di scansione
/// sul retro della piastra. Un settore perso lampeggia (0,15 s), poi la piastra si spegne in grigio
/// scuro e perde quattro frammenti; all'ultimo rimasto lampeggia in allarme. Il resto dello sprite
/// (chiglia, binario, stabilizzatori) resta fermo; due propulsori ionici agli agganci dei motori.
fn wall(r: &mut Ops, ship: &Ship, h: f32, a: &Anim, boost: Boost) {
    let n = GUARDIAN_SECTORS;
    let tq = (pose(a.t) as i64).rem_euclid(120) as usize;
    let k = h / ship.h as f32;
    let sectors = ship.sectors.expect("settori del GUARDIAN");
    let alive = a.wall.iter().filter(|w| w.is_none()).count();
    let warn = alive == 1 && (tq % 4) < 2;
    let scan = tq % n;
    let recoil = a.recoil.map(|at| ((at * n as f32).floor() as usize).min(n - 1));
    // spostamento di una piastra (None: non ancora entrata nella costruzione)
    let offset = |i: usize| -> Option<(f32, f32)> {
        let dy = match a.build {
            Some(t) => build_offset(i, t)?,
            None => 0.0,
        };
        Some((if recoil == Some(i) { -1.0 } else { 0.0 }, dy))
    };
    let back = 2 - ships::PLATE;
    sprite(r, ship, h, |u, v, px| {
        if u < back {
            return Some((sprite_role(px), 0.0, 0.0));
        }
        // la piastra della riga (le giunture vanno con la piastra sotto)
        let i = sectors.iter().position(|&(_, y1)| v < y1).unwrap_or(n - 1);
        let (dx, dy) = offset(i)?;
        let role = if v < sectors[i].0 {
            // giuntura: nera fra due piastre rotte
            if a.wall[i].is_some() && a.wall[i - 1].is_some() { ships::BLACK } else { px }
        } else {
            match a.wall[i] {
                None if warn && matches!(px, ships::BODY | ships::SHADE) => ships::MARK_LIGHT,
                None if scan == i && u == back && matches!(px, ships::BODY | ships::SHADE) => ships::MARK_LIGHT,
                None => px,
                Some(age) if age < 0.15 => {
                    if matches!(px, ships::BODY | ships::SHADE) { ships::MARK_LIGHT } else { ships::MARK }
                }
                Some(_) => broken(px),
            }
        };
        Some((sprite_role(role), dx, dy))
    });
    // frammenti delle piastre appena rotte
    for (i, &(y0, _)) in sectors.iter().enumerate() {
        let (Some(age), Some((dx, dy))) = (a.wall[i], offset(i)) else { continue };
        if !(0.15..BREAK_SECONDS).contains(&age) {
            continue;
        }
        let p = (age - 0.15) / 0.5;
        let ys = (y0 as f32 * k).floor();
        for j in 0..4 {
            let jf = j as f32;
            let (w, role) = if j % 2 == 1 { (1.0, Role::Gray) } else { (2.0, Role::Dark) };
            let x = round(-7.0 - p * (5.0 + 2.0 * jf));
            let y = round(ys + 1.0 + jf * 1.5 + (jf - 1.5) * p * 3.0);
            r.rect(x + dx, y + dy, w, 1.0, role);
        }
    }
    // propulsori ionici a cono
    let moving = a.vy.abs() > 0.5 || boost.stage > 0;
    for (idx, e) in ship.engines.iter().enumerate() {
        let (nz, y, rows) = nozzle(e, k);
        let p = (tq + idx * 2) % 4;
        let fl = if moving { [6, 7, 8, 7][p] } else { [4, 5, 6, 5][p] } as f32;
        let jlen = fl - 1.0;
        let clen = (fl / 2.0).floor().max(2.0);
        r.late_rect(nz - 1.0, y - 1.0, 1.0, rows + 2.0, Role::Mark);
        r.late_rect(nz - jlen, y, jlen, rows, Role::MarkLight);
        r.late_rect(nz - clen, y, clen, rows, Role::Body);
        r.late_rect(nz - 1.0 - fl, y + ((p % 2) as f32).min(rows - 1.0), 2.0, 1.0, Role::Mark);
        if moving {
            let s = ((tq + idx) % 2) as f32;
            r.late_rect(nz - 2.0 - fl - s, y + s.min(rows - 1.0), 1.0, 1.0, Role::MarkLight);
        }
        trail(r, nz - 1.0 - fl, y + ((rows - 1.0) / 2.0).floor(), boost.extra);
        if boost.stage == 3 {
            ignite(r, nz - 1.0, y, rows);
        }
    }
}

/// Un aggancio sulla racchetta: colonna dell'ugello (quella subito davanti all'aggancio), prima riga
/// e righe del getto, con le righe dello sprite riportate all'altezza della racchetta (`k`).
fn nozzle(a: &Anchor, k: f32) -> (f32, f32, f32) {
    (a.u as f32 + 1.0, (a.v as f32 * k).floor(), (a.rows as f32 * k).round().max(1.0))
}

/// TWIST: getto di manovra da un pod (aggancio speciale `a`), verso il basso (`down`) o verso
/// l'alto: piccolo, un nucleo bianco all'ugello con un filo di luce dietro e una coda corta che
/// piega verso l'estremità della nave.
fn rcs(r: &mut Ops, a: &Anchor, k: f32, down: bool, p: f32) {
    let (nz, y, rows) = nozzle(a, k);
    // pezzi del getto verso il basso: colonna e riga dall'ugello e dalla prima riga dell'aggancio
    let parts = [
        (-2.0, 0.0, 2.0, rows, Role::Body),
        (-3.0, 0.0, 1.0, rows, Role::MarkLight),
        (-3.0, rows, 2.0, 2.0 + p, Role::MarkLight),
        (-3.0, rows + 2.0 + p, 1.0, 1.0, Role::Mark),
    ];
    for (dx, dy, w, hh, role) in parts {
        // verso l'alto: lo stesso getto ribaltato sulle righe dell'aggancio
        let yy = if down { y + dy } else { y + rows - dy - hh };
        r.late_rect(nz + dx, yy, w, hh, role);
    }
}

/// I pezzi dell'astronave `kind` alta `h` pixel arcade: lo sprite (`ships.rs`) e le animazioni, le
/// fiamme e gli effetti agli agganci.
fn kind_ops(kind: PaddleKind, h: f32, a: &Anim, boost: Boost) -> Ops {
    let ship = ships::ship(kind);
    let mut r = Ops::default();
    let mid = (h / 2.0).floor();
    let k = h / ship.h as f32;
    let tq = (pose(a.t) as i64).rem_euclid(120) as usize;
    // con i booster accesi le fiamme si muovono come in movimento
    let moving = a.vy.abs() > 0.5 || boost.stage > 0;
    let extra = boost.extra;
    let ignited = boost.stage == 3;
    let plain = |_: i32, _: i32, px: u8| Some((sprite_role(px), 0.0, 0.0));
    // riga della scia (al centro del getto)
    let trail_row = |y: f32, rows: f32| y + ((rows - 1.0) / 2.0).floor();
    match kind {
        PaddleKind::Arcade => {
            // VAUS-84: capsula coin-op con la cabina gettoniera nel colore del personaggio, che si
            // accende a scatti, scintille dai due ugelli e gettone che entra nella fessura
            let coin_f = a.coin.and_then(|s| (s < COIN_SECONDS).then(|| (s * 60.0).floor() as usize));
            let coin_flash = coin_f.is_some_and(|f| f >= 18);
            let lit = (tq % 8) < 2;
            sprite(&mut r, ship, h, |_, _, px| {
                let role = if !ships::is_mark(px) {
                    px
                } else if coin_f.is_some_and(|f| (18..22).contains(&f)) {
                    ships::BODY
                } else if coin_flash || lit {
                    brighter(px)
                } else {
                    px
                };
                Some((sprite_role(role), 0.0, 0.0))
            });
            let f = tq % 4;
            let fl = if moving { 3.0 } else { 2.0 };
            for e in &ship.engines {
                let (nz, y, rows) = nozzle(e, k);
                r.rect(nz - fl - (f % 2) as f32, y, fl, rows, Role::MarkLight);
                r.rect(nz - 2.0 - (f * 2) as f32, if f % 2 == 1 { y + rows } else { y - 1.0 }, 1.0, 1.0, Role::Mark);
                trail(&mut r, nz - 1.0 - fl, trail_row(y, rows), extra);
                if ignited {
                    ignite(&mut r, nz, y, rows);
                }
            }
            // gettone che arriva da dietro ed entra nella cabina (doppio clic USE)
            if let Some(cf) = coin_f {
                let c0 = ship.mark_u0 as f32;
                if cf < 12 {
                    let cx = c0 - 14.0 + cf as f32;
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
                    r.late_rect(c0 - 2.0, mid - 2.0, 3.0, 4.0, Role::Mark);
                    r.late_rect(c0 - 2.0, mid - 2.0, 2.0, 1.0, Role::MarkLight);
                    r.late_rect(c0 - 1.0, mid - 1.0, 1.0, 2.0, Role::Body);
                } else if cf < 16 {
                    r.late_rect(c0 - 1.0, mid - 2.0, 2.0, 4.0, Role::MarkLight);
                    r.late_rect(c0, mid - 1.0, 1.0, 2.0, Role::Body);
                } else if cf < 18 {
                    r.late_rect(c0, mid - 2.0, 1.0, 4.0, Role::Body);
                } else {
                    let (d, srole) = if cf < 22 {
                        (0.0, Role::Body)
                    } else if cf < 26 {
                        (1.0, Role::MarkLight)
                    } else {
                        (2.0, Role::Mark)
                    };
                    r.late_rect(c0 + 1.0 - d * 2.0, mid - 5.0 - d, 1.0, 1.0, srole);
                    r.late_rect(c0 + 1.0 - d * 2.0, mid + 4.0 + d, 1.0, 1.0, srole);
                    r.late_rect(c0 - 2.0 - d * 2.0, mid - 2.0 - d, 1.0, 1.0, srole);
                    r.late_rect(c0 - 2.0 - d * 2.0, mid + 1.0 + d, 1.0, 1.0, srole);
                }
            }
        }
        PaddleKind::Titan => {
            // COLOSSUS: corazzata pesante con due grandi pod motori posteriori, fiamme booster coniche
            // affusolate e nucleo incandescente (l'ombra staccata la mette draw_paddle)
            sprite(&mut r, ship, h, plain);
            for (idx, e) in ship.engines.iter().enumerate() {
                let (nz, y, rows) = nozzle(e, k);
                let p = (tq + idx * 2) % 4;
                let fl: usize = if moving { [6, 8, 7, 8][p] } else { [4, 5, 6, 5][p] };
                let mlen = fl.div_ceil(2) as f32;
                let jlen = (fl - 1) as f32;
                let clen = (fl / 2).max(2) as f32;
                let fl = fl as f32;
                r.late_rect(nz - 1.0, y - 2.0, 1.0, rows + 4.0, Role::Mark);
                r.late_rect(nz - mlen, y - 1.0, mlen, rows + 2.0, Role::Mark);
                r.late_rect(nz - 1.0, y - 1.0, 1.0, rows + 2.0, Role::MarkLight);
                r.late_rect(nz - jlen, y, jlen, rows, Role::MarkLight);
                r.late_rect(nz - clen, y, clen, rows, Role::Body);
                r.late_rect(nz - 1.0 - fl, y + ((p % 2) as f32).min(rows - 1.0), 2.0, 1.0, Role::Mark);
                if moving {
                    let s = (tq + idx) % 3;
                    let srole = if s == 0 { Role::MarkLight } else { Role::Mark };
                    r.late_rect(nz - 2.0 - fl - s as f32, y - 1.0 + ((s + idx) % 3) as f32, 1.0, 1.0, srole);
                }
                trail(&mut r, nz - 1.0 - fl, trail_row(y, rows), extra);
                if ignited {
                    ignite(&mut r, nz - 1.0, y, rows);
                }
            }
        }
        PaddleKind::Hammer => {
            // ANVIL-MK1: nave-martello / ariete a "T" con grande booster centrale d'urto che si
            // allunga al colpo, pistone che fa vibrare la racchetta e scintille sulla faccia
            sprite(&mut r, ship, h, plain);
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
            let tlen = if fl >= 9 { 3.0 } else if fl >= 6 { 2.0 } else { 1.0 };
            let mlen = ((fl * 2) / 3) as f32;
            let jlen = (fl - 1) as f32;
            let clen = (fl / 2).max(2) as f32;
            let fl = fl as f32;
            for e in &ship.engines {
                let (nz, y, rows) = nozzle(e, k);
                if surge == 3 {
                    r.late_rect(nz - 1.0, y - 3.0, 1.0, rows + 6.0, Role::Mark);
                }
                r.late_rect(nz - tlen, y - 2.0, tlen, rows + 4.0, Role::Mark);
                r.late_rect(nz - mlen, y - 1.0, mlen, rows + 2.0, Role::Mark);
                if surge >= 1 {
                    let hlen = (mlen / 2.0).floor().max(1.0);
                    r.late_rect(nz - hlen, y - 1.0, hlen, rows + 2.0, Role::MarkLight);
                }
                r.late_rect(nz - jlen, y, jlen, rows, Role::MarkLight);
                r.late_rect(nz - clen, y, clen, rows, Role::Body);
                let tip = y + ((tq % 2) as f32).min(rows - 1.0);
                r.late_rect(nz - 1.0 - fl, tip, 2.0, 1.0, Role::Mark);
                if surge >= 2 {
                    r.late_rect(nz - fl, tip, 1.0, 1.0, Role::MarkLight);
                }
                trail(&mut r, nz - 1.0 - fl, trail_row(y, rows), extra);
                if ignited {
                    ignite(&mut r, nz, y, rows);
                }
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
            // VORTEX: caccia acrobatico con ugello rotante e getti di manovra RCS dai due pod sulle
            // virate (sale: spara il pod in basso; scende: quello in alto)
            sprite(&mut r, ship, h, plain);
            let ph = tq % 4;
            let dy = match ph {
                1 => -1.0,
                3 => 1.0,
                _ => 0.0,
            };
            let fl = if moving { [2, 3, 2, 3][ph] } else { [0, 1, 0, 1][ph] } as f32;
            let clen = 2.0 + (fl / 2.0).floor();
            for e in &ship.engines {
                let (nz, y, rows) = nozzle(e, k);
                r.late_rect(nz - 2.0, y - 1.0, 2.0, rows + 2.0, Role::Mark);
                r.late_rect(nz - 3.0 - fl, y + dy, 3.0 + fl, rows, Role::MarkLight);
                r.late_rect(nz - clen, y + dy, clen, rows, Role::Body);
                r.late_rect(nz - 5.0 - fl, y + dy + ((ph % 2) as f32).min(rows - 1.0), 2.0, 1.0, Role::Mark);
                trail(&mut r, nz - 5.0 - fl, trail_row(y, rows), extra);
                if ignited {
                    ignite(&mut r, nz - 2.0, y, rows);
                }
            }
            let p = (tq % 2) as f32;
            let (top, bottom) = (ship.specials.first(), ship.specials.last());
            if a.vy < -0.5
                && let Some(pod) = bottom
            {
                rcs(&mut r, pod, k, true, p);
            } else if a.vy > 0.5
                && let Some(pod) = top
            {
                rcs(&mut r, pod, k, false, p);
            }
            if let Some((s, _)) = a.spark
                && s < RING_SECONDS
            {
                ring(&mut r, ship, h, s);
            }
        }
        PaddleKind::Blaster => {
            // VIPER-X: cannoniera d'assalto con livrea verde, due cannoni che sporgono davanti con
            // rinculo e lampo verde simultanei; il verde dello scafo fa da indicatore dei colpi
            // (si spegne dall'alto man mano che spara e si riaccende dal basso con la ricarica)
            let fr = a.fire.map(|s| s * 60.0);
            let recoil = fr.is_some_and(|f| f < 3.0);
            let barrel: i32 = match fr {
                Some(f) if f < 3.0 => 1,
                Some(f) if f < 8.0 => 2,
                _ => 3,
            };
            let length = ship.front() - i32::from(!ship.weapons.is_empty());
            let back = (3 - barrel).min(length - 1).max(0);
            let ammo = a.ammo.min(6);
            let fill = if ammo > 0 {
                [0.0, 3.0, 6.0, 9.0, 13.0, 16.0, 19.0][ammo as usize] / 19.0
            } else {
                a.reload.map_or(0.0, |p| p.clamp(0.0, 1.0))
            };
            let (g0, g1) = ship.mark_rows;
            let lit_from = g1 + 1 - (fill * (g1 - g0 + 1) as f32).round() as i32;
            sprite(&mut r, ship, h, |u, v, px| {
                if u > 1 {
                    // le canne rientrano nel rinculo, sotto la faccia
                    return (u - back > 1).then_some((sprite_role(px), -back as f32, 0.0));
                }
                let role = if ships::is_mark(px) && v < lit_from { dimmed(px) } else { px };
                Some((sprite_role(role), 0.0, 0.0))
            });
            for (idx, e) in ship.engines.iter().enumerate() {
                let (nz, y, rows) = nozzle(e, k);
                let p = (tq + idx * 2) % 4;
                let fl = if moving { [6, 8, 7, 8][p] } else { [4, 5, 6, 5][p] } as f32;
                let mlen = ((fl as i32 + 1) / 2) as f32;
                let jlen = fl - 1.0;
                let clen = (fl as i32 / 2).max(2) as f32;
                r.late_rect(nz - mlen, y - 1.0, mlen, rows + 2.0, Role::Mark);
                r.late_rect(nz - 1.0, y - 1.0, 1.0, rows + 2.0, Role::MarkLight);
                r.late_rect(nz - jlen, y, jlen, rows, Role::MarkLight);
                r.late_rect(nz - clen, y, clen, rows, Role::Body);
                r.late_rect(nz - 1.0 - fl, y, 2.0, 1.0, Role::Mark);
                if moving {
                    let s = (tq + idx) % 3;
                    let spark_col = if s == 0 { Role::MarkLight } else { Role::Mark };
                    r.late_rect(nz - 2.0 - fl - s as f32, y - 1.0 + ((s + idx) % 3) as f32, 1.0, 1.0, spark_col);
                }
                trail(&mut r, nz - 1.0 - fl, trail_row(y, rows), extra);
                if ignited {
                    ignite(&mut r, nz - 1.0, y, rows);
                }
            }
            // lampo alle bocche dei cannoni (gli agganci delle armi, con il rinculo)
            if recoil {
                for w in &ship.weapons {
                    let (fx, wy, rows) = (w.u as f32 - back as f32, (w.v as f32 * k).floor(), (w.rows as f32 * k).round().max(1.0));
                    let fy = wy - 1.0;
                    r.rect(fx, fy, 2.0, rows + 2.0, Role::Mark);
                    r.rect(fx + 1.0, fy + 1.0, 3.0, rows, Role::MarkLight);
                    r.rect(fx + 1.0, fy + 1.0, 2.0, rows, Role::Body);
                    r.rect(fx + 4.0, fy + 1.0, 2.0, rows, Role::MarkLight);
                }
                r.shift(0, -1.0);
            }
        }
        PaddleKind::Rush => {
            // MACH-ZERO: intercettore supersonico ad ali a freccia, ugello postbruciatore nitro (che
            // piega contro `vy`) e scie d'aria dalle punte alari (gli agganci speciali)
            sprite(&mut r, ship, h, plain);
            let p = tq % 4;
            let fz = flicker(a.t);
            let fl: usize = if a.dashing {
                [11, 13, 12, 14][p]
            } else {
                [5, 7, 6, 8][p] + if moving { 2 } else { 0 }
            };
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
            let fl = fl as f32;
            for e in &ship.engines {
                let (nz, y, rows) = nozzle(e, k);
                r.late_rect(nz - olen, y - 1.0, olen, rows + 2.0, Role::Mark);
                r.late_rect(nz - jlen, y + lean, jlen, rows, Role::MarkLight);
                r.late_rect(nz - clen, y, clen, rows, Role::Body);
                for j in 0..2 {
                    let d = clen + 1.0 + (tq % 3) as f32 + 3.0 * j as f32;
                    if d < jlen - 1.0 {
                        r.late_rect(nz - 1.0 - d, y + lean, 1.0, rows, Role::Body);
                    }
                }
                r.late_rect(nz - 1.0 - fl, y + lean + (fz as f32).min(rows - 1.0), 2.0, 1.0, Role::Mark);
                if moving {
                    let s = tq % 3;
                    let srole = if s == 0 { Role::MarkLight } else { Role::Mark };
                    r.late_rect(nz - 2.0 - fl - s as f32, y - 1.0 + ((p + s) % 4) as f32, 1.0, 1.0, srole);
                }
                trail(&mut r, nz - 1.0 - fl, trail_row(y, rows), extra);
                if ignited {
                    ignite(&mut r, nz, y, rows);
                }
            }
            // scie d'aria dalle punte alari
            let wlen = if a.dashing { 4.0 } else { 2.0 };
            let wrole = if a.dashing { Role::MarkLight } else { Role::Mark };
            for (j, s) in ship.specials.iter().enumerate() {
                let w = ((tq + j) % 3) as f32;
                let (x, y, rows) = nozzle(s, k);
                r.rect(x - 1.0 - w - wlen, trail_row(y, rows), wlen, 1.0, wrole);
            }
        }
        PaddleKind::Guardian => wall(&mut r, ship, h, a, boost),
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
            let w = s.w * stretch_x;
            let top = cy - s.h / 2.0;
            match s.scan {
                None => draw_rectangle(cx - w / 2.0, top, w, s.h, look.body),
                Some(sc) => {
                    let rows = (s.h / u).round().max(1.0) as i32;
                    let ky = s.h / rows as f32;
                    for v in 0..rows {
                        let (dx, color) = match scan_row(v, sc.level, sc.arriving) {
                            0 => continue,
                            1 => (if (v & 1 == 0) == sc.jitter { u } else { -u }, lighter(look.mark, 0.45)),
                            _ => (0.0, look.body),
                        };
                        draw_rectangle(cx - w / 2.0 + dx, top + v as f32 * ky, w, ky, color);
                    }
                }
            }
        }
        return;
    };
    // pixel arcade della racchetta: il corpo largo 5 e alto `h` occupa esattamente la hitbox
    let h = (s.h / u).round().max(1.0);
    let (kx, ky) = ((s.w / 5.0) * stretch_x, s.h / h);
    let top = cy - s.h / 2.0;

    // RUSH: immagini dell'intercettore (la sagoma dello sprite) lungo lo scatto in avanti, più chiare
    // verso la partenza (nella scelta sempre: è il suo segno)
    if kind == PaddleKind::Rush {
        let dash = s.dash.or(s.preview.then_some((cx - f * s.w * 8.0, 1.0)));
        if let Some((from, fade)) = dash {
            for k in 1..=3 {
                let gx = from + (cx - from) * k as f32 / 4.0;
                let color = Color {
                    a: look.mark.a * fade * 0.18 * k as f32,
                    ..look.mark
                };
                // la sagoma dello sprite, una riga alla volta a pezzi pieni
                let ship = ships::ship(kind);
                let (u0, u1) = ship.u_range();
                for v in 0..h as i32 {
                    let sv = v * ship.h as i32 / h as i32;
                    let mut u = u0;
                    while u <= u1 {
                        if ship.at(u, sv) == ships::NONE {
                            u += 1;
                            continue;
                        }
                        let start = u;
                        while u <= u1 && ship.at(u, sv) != ships::NONE {
                            u += 1;
                        }
                        let n = (u - start) as f32;
                        let x0 = if f > 0.0 { gx + (start as f32 + 0.5) * kx } else { gx - (u as f32 + 0.5) * kx };
                        draw_rectangle(x0, top + v as f32 * ky, n * kx, ky, color);
                    }
                }
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
    let ops = kind_ops(kind, h, &s.anim, boost);
    // da pixel arcade a coordinate di disegno, con l'inclinazione di TWIST attorno al centro
    let angle = -s.tilt * f;
    let (sin, cos) = angle.sin_cos();
    let point = |x: f32, y: f32| {
        let (dx, dy) = (f * (x + 0.5) * kx, top + y * ky - cy);
        vec2(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos)
    };
    let mark_dark = scaled(look.mark, [0.6; 3]);
    let mark_light = lighter(look.mark, 0.45);
    // `main`: il disegno della racchetta (non l'ombra), dove le righe in luce del TELEPORT si accendono
    let fill = |op: &Op, color: Color, ox: f32, oy: f32, main: bool| match *op {
        Op::Rect { x, y, w, h, .. } => {
            let (ww, hh) = (w * kx, h * ky);
            if angle == 0.0 {
                let x0 = if f > 0.0 { cx + (x + ox + 0.5) * kx } else { cx - (x + ox + w + 0.5) * kx };
                let Some(sc) = s.scan else {
                    draw_rectangle(x0, top + (y + oy) * ky, ww, hh, color);
                    return;
                };
                // TELEPORT: una riga alla volta, nascosta, in luce che trema o piena
                for i in 0..h as i32 {
                    let v = y as i32 + i;
                    let (dx, c) = match scan_row(v, sc.level, sc.arriving) {
                        0 => continue,
                        1 => (if (v & 1 == 0) == sc.jitter { kx } else { -kx }, if main { mark_light } else { color }),
                        _ => (0.0, color),
                    };
                    draw_rectangle(x0 + dx, top + (v as f32 + oy) * ky, ww, ky, c);
                }
            } else {
                let c = point(x + ox + w / 2.0, y + oy + h / 2.0);
                draw_rectangle_ex(c.x, c.y, ww, hh, DrawRectangleParams {
                    offset: vec2(0.5, 0.5),
                    rotation: angle,
                    color,
                });
            }
        }
    };
    let role_of = |op: &Op| match *op {
        Op::Rect { role, .. } => role,
    };

    let gray = rgb(180, 180, 180);
    let gray_light = rgb(226, 226, 230);
    let dark = rgb(92, 92, 98);
    let dark_deep = rgb(52, 52, 60);
    let body_shade = scaled(look.body, [212.0 / 255.0, 214.0 / 255.0, 224.0 / 255.0]);
    let color = |role: Role| match role {
        Role::Body => look.body,
        Role::Shade => body_shade,
        Role::Signal => rgb(255, 210, 37),
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
            fill(op, far_shadow, -4.5, sy_far, false);
        }
        for op in ops.0.iter().chain(&ops.1) {
            fill(op, mid_shadow, -2.5, sy_mid, false);
        }
    } else {
        let shadow = rgb(48, 48, 58);
        for op in ops.0.iter().chain(&ops.1) {
            fill(op, shadow, -1.0, 1.0, false);
        }
    }
    for op in &ops.0 {
        fill(op, color(role_of(op)), 0.0, 0.0, true);
    }
    // luce dall'alto e dalla faccia sui pezzi alti e larghi almeno 2 pixel (gli effetti: lo sprite
    // ha già le sue luci): retro e fondo del corpo in bianco in ombra, sui segni il bordo alto in
    // luce e il basso in ombra
    for op in &ops.0 {
        let Op::Rect { x, y, w, h, role } = *op;
        if w < 2.0 || h < 2.0 {
            continue;
        }
        let edge = |x: f32, y: f32, w: f32, c: Color| fill(&Op::Rect { x, y, w, h: 1.0, role }, c, 0.0, 0.0, true);
        if role == Role::Body {
            if x <= -3.0 {
                fill(&Op::Rect { x, y, w: 1.0, h, role }, body_shade, 0.0, 0.0, true);
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
        fill(op, color(role_of(op)), 0.0, 0.0, true);
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
        scan: None,
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
        // tutti hanno scelto
        if self.chosen.iter().all(|&c| c) {
            self.chosen = [true; 2];
            self.ready = Some(READY_SECONDS);
            app.play(Event::Boost);
        }
        None
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let w = r.world_w;
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
                scan: None,
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
