//! Modalità NEXT a schermo: scelta dei bonus, capsule, riserve, barra delle mosse speciali ed
//! effetti.
//!
//! La logica è tutta nel core (`paddws_core::next`); qui ci sono solo il disegno
//! e lo stato puramente grafico (scie, scritte, trattini spazzati dalla COMETA).

use std::collections::VecDeque;

use macroquad::prelude::*;
use paddws_core::fixed::{ONE, to_f32};
use paddws_core::{
    Bonus, Event, Events, GUARDIAN_SECTORS, MAX_SPECIAL_LEVEL, Match, PaddleKind, Side, Special, SuperAnim,
    guardian_sector,
};

use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::paddle_ui::{self, Look, PaddlePick, Shape};
use crate::render::Renderer;
use crate::scenes::{App, Menu, Scene};
use crate::touch;

/// Icone 9x9 a 1 bit, come le bitmap del core MiSTer, nell'ordine di `Bonus`.
const ICONS: [[&str; 9]; Bonus::COUNT] = [
    [
        "#.......#",
        "#.......#",
        "#....#..#",
        "#.....#.#",
        "#.#######",
        "#.....#.#",
        "#....#..#",
        "#.......#",
        "#.......#",
    ],
    [
        "......##.",
        ".....##..",
        "....##...",
        "...##....",
        "..######.",
        "....##...",
        "...##....",
        "..##.....",
        ".##......",
    ],
    [
        "#########",
        ".#.....#.",
        "..#...#..",
        "...#.#...",
        "....#....",
        "...#.#...",
        "..#.#.#..",
        ".#.###.#.",
        "#########",
    ],
    [
        "......###",
        ".....####",
        "....#.###",
        "...#.....",
        "..#......",
        "..#......",
        "..#......",
        "...#.....",
        "....####.",
    ],
    [
        "..#.#.#..",
        ".........",
        "#.......#",
        ".........",
        "#...#...#",
        ".........",
        "#.......#",
        ".........",
        "..#.#.#..",
    ],
    [
        "#...#...#",
        ".#..#..#.",
        "..#.#.#..",
        "...###...",
        "#########",
        "...###...",
        "..#.#.#..",
        ".#..#..#.",
        "#...#...#",
    ],
    [
        "..#####..",
        ".#.....#.",
        "#.......#",
        "#.......#",
        "#########",
        "#...#...#",
        "#...#...#",
        ".#..#..#.",
        "..#####..",
    ],
    // BULLET: il proiettile con le due onde d'urto dietro
    [
        "..#......",
        ".#..#....",
        "#..#.....",
        "#.#.####.",
        "#.#.#####",
        "#.#.####.",
        "#..#.....",
        ".#..#....",
        "..#......",
    ],
];

/// Icone 9x9 delle mosse speciali, rivolte a destra (giocatore sinistro), nell'ordine di
/// `Special::ALL`: la freccia orizzontale con la scia di STRAIGHT SHOT e quella che sale di
/// RISING STRIKE.
pub const SPECIAL_ICONS: [[&str; 9]; 2] = [
    [
        "....#....",
        ".....#...",
        "......#..",
        ".......#.",
        "#.#######",
        ".......#.",
        "......#..",
        ".....#...",
        "....#....",
    ],
    [
        "...######",
        ".......##",
        "......#.#",
        ".....#..#",
        "....#...#",
        "...#.....",
        "..#......",
        ".#.......",
        "#........",
    ],
];

/// Scelte predefinite quando scade il tempo.
const DEFAULT_PICK: [Bonus; 3] = [Bonus::Smash, Bonus::Teleport, Bonus::Slow];
/// Secondi per scegliere e pausa prima del servizio.
pub const PICK_SECONDS: f64 = 10.0;
pub const READY_SECONDS: f64 = 1.2;
/// Riga dei nomi e dei conteggi sopra le colonne della scelta (unità a 480 righe).
const HEAD_Y: f32 = 132.0;
/// Righe di velocità del RUSH quando scatta in avanti (l'avanzamento a schermo dura meno).
const RUSH_GHOST_SECONDS: f64 = 0.25;
/// Nome di una mossa speciale di livello `level`: al livello massimo con "MAX" davanti.
pub fn special_title(special: Special, level: u8) -> String {
    if level >= MAX_SPECIAL_LEVEL {
        format!("MAX {}", special.name())
    } else {
        special.name().to_string()
    }
}

/// Lampo del settore del muro del GUARDIAN che rimanda la palla, prima di sparire.
const BARRIER_FLASH_SECONDS: f64 = 0.3;
/// Durata della scritta "P1 SMASH!" e di quella delle mosse speciali.
const LABEL_SECONDS: f64 = 1.2;
/// Mosse speciali: ingresso della scritta (parte più grande e si stringe), scie del salto di
/// RISING STRIKE e quadrato che si allarga sul colpo speciale.
const SPECIAL_ZOOM_SECONDS: f64 = 0.15;
const BURST_SECONDS: f64 = 0.3;
/// Coda della palla con boost, curva, STEER e SLOW: posizioni dei tick precedenti (240 al secondo,
/// quindi 0,1 s), larghe quanto la palla, che sfumano dal grigio al nero.
const TRAIL_TICKS: usize = 24;
/// Salto del TELEPORT, seguendo la palla in arrivo (frazioni della larghezza del campo, contate
/// dal bordo del giocatore): la racchetta affonda nel primo portale mentre la palla va da metà
/// campo a 0,4, poi esce dal secondo, sul punto d'arrivo, mentre va da `WARP_RISE` a 0,2: quando
/// la palla arriva la racchetta è già tutta fuori. Passi di 32 pixel a 320x240, come nel core
/// MiSTer.
const WARP_RISE: f32 = 0.3;
const WARP_STEP: f32 = 0.1;
/// metà larghezza della linea del portale (px a 240 righe)
const WARP_LINE_HALF: f32 = 9.0;
/// Bullet time, solo con i colori della palette (come sul MiSTer e sul C64): quello che è bianco
/// diventa grigio, tranne la racchetta di chi l'ha attivato, che ha un bordo di accento; la coda
/// della palla è lunga il doppio e lascia immagini grigie ogni `BULLET_GHOST_STEP` posizioni, fino
/// a `BULLET_GHOST_TICKS` (meno immagini, e bordo che lampeggia, durante le rampe).
const BULLET_GHOST_STEP: usize = 12;
const BULLET_GHOST_TICKS: usize = 96;

/// BULLET a schermo, per chi l'ha attivato.
#[derive(Clone, Copy)]
pub struct BulletLook {
    /// lato di chi l'ha attivato
    pub side: usize,
    /// scattato (bullet time in corso); false = armato, in attesa della palla
    pub on: bool,
    /// intensità da 0 a 1: sale con la rampa d'entrata del core, torna a 0 subito alla fine
    pub k: f32,
}

/// Il BULLET a schermo; None se nessuno l'ha attivato.
pub fn bullet_look(game: &Match) -> Option<BulletLook> {
    let n = game.next.as_ref()?;
    let side = n.bullet? as usize;
    let k = if n.bullet_on {
        // `bullet_timer` scende da `bullet_ramp_ticks` a 0 dallo scatto
        let ramp = game.params.bullet_ramp_ticks.max(1) as f32;
        ((ramp - n.bullet_timer as f32 + 1.0) / ramp).clamp(0.0, 1.0)
    } else {
        0.0
    };
    Some(BulletLook {
        side,
        on: n.bullet_on,
        k,
    })
}

/// Bullet time in corso (il BULLET è scattato): intensità e lato di chi l'ha attivato.
pub fn bullet_time(game: &Match) -> Option<BulletLook> {
    bullet_look(game).filter(|b| b.on)
}

/// Colore di un oggetto rallentato dal bullet time: con `on` il bianco diventa grigio, gli altri
/// colori (grigio, accento, nero) restano.
pub fn slowed_color(c: Color, on: bool, white: Color, gray: Color) -> Color {
    if on && c == white { gray } else { c }
}

/// Tasti della scelta per giocatore: (su, giù, prendi/lascia).
pub const PICK_KEYS: [(KeyCode, KeyCode, KeyCode); 2] = [
    (KeyCode::W, KeyCode::S, KeyCode::C),
    (KeyCode::Up, KeyCode::Down, KeyCode::Minus),
];

/// Tasti NEXT in partita per giocatore: (seleziona, attiva).
pub const BONUS_KEYS: [(KeyCode, KeyCode); 2] = [(KeyCode::F, KeyCode::C), (KeyCode::Period, KeyCode::Minus)];

/// Lato di un pixel "arcade" (lo schermo a 320x240 del core MiSTer).
pub fn unit(app: &App) -> f32 {
    app.renderer.world_h / 240.0
}

/// Centro del posto `i` della riserva del giocatore `side`, in coordinate di disegno.
fn reserve_slot(w: f32, u: f32, size: f32, side: usize, i: usize) -> (f32, f32) {
    let step = size + 4.0 * u;
    let cx = if side == 0 {
        6.0 * u + size / 2.0 + i as f32 * step
    } else {
        w - 6.0 * u - size / 2.0 - i as f32 * step
    };
    (cx, 4.0 * u + size / 2.0)
}

/// Bonus della riserva di `side` sotto il punto `p` (coordinate di disegno), con un margine per
/// il dito: l'area di ogni posto è larga quanto il passo tra le capsule e alta il doppio.
pub fn reserve_slot_at(app: &App, game: &Match, side: usize, p: Vec2) -> Option<usize> {
    let n = game.next.as_ref()?;
    let (u, size) = (unit(app), to_f32(game.params.capsule_half) * 2.0);
    (0..n.players[side].count()).find(|&i| {
        let (cx, cy) = reserve_slot(app.renderer.world_w, u, size, side, i);
        (p.x - cx).abs() <= size / 2.0 + 2.0 * u && (p.y - cy).abs() <= size
    })
}

/// Icona 9x9 con l'angolo in alto a sinistra in (x, y), coordinate di disegno.
pub fn draw_icon(bonus: Bonus, x: f32, y: f32, u: f32, color: Color) {
    draw_bits(&ICONS[bonus as usize], x, y, u, false, color);
}

/// Bitmap 9x9 con l'angolo in alto a sinistra in (x, y), coordinate di disegno; `mirror` la
/// specchia in orizzontale.
pub fn draw_bits(rows: &[&str; 9], x: f32, y: f32, u: f32, mirror: bool, color: Color) {
    for (r, row) in rows.iter().enumerate() {
        for (c, ch) in row.bytes().enumerate() {
            if ch == b'#' {
                let c = if mirror { 8 - c } else { c };
                draw_rectangle(x + c as f32 * u, y + r as f32 * u, u, u, color);
            }
        }
    }
}

/// Icona della mossa speciale, rivolta verso l'avversario di `side` (0 = sinistro).
pub fn draw_special_icon(special: Special, x: f32, y: f32, u: f32, side: usize, color: Color) {
    draw_bits(&SPECIAL_ICONS[special as usize - 1], x, y, u, side == 1, color);
}

/// Barra delle mosse speciali: rettangolo (x, y, w, h) in coordinate di disegno, riempito per
/// `value / max` a partire dal lato destro (`from_right`) o sinistro, con le tacche del costo di
/// una mossa. Sotto il costo il riempimento è grigio, sopra bianco; `ready` (una mossa
/// disponibile) lo colora con l'accento e `flash` lo fa lampeggiare.
#[allow(clippy::too_many_arguments)]
pub fn draw_meter(
    (x, y, w, h): (f32, f32, f32, f32),
    u: f32,
    value: f32,
    max: f32,
    cost: f32,
    from_right: bool,
    (ready, flash): (bool, bool),
    (white, gray, accent): (Color, Color, Color),
) {
    let max = max.max(1.0);
    let inner = w - 2.0 * u;
    let fill = (value / max).clamp(0.0, 1.0) * inner;
    let color = if ready {
        if flash { white } else { accent }
    } else if value >= cost {
        white
    } else {
        gray
    };
    draw_rectangle_lines(x, y, w, h, u, if ready { accent } else { Color { a: 0.6, ..gray } });
    let fx = if from_right { x + w - u - fill } else { x + u };
    draw_rectangle(fx, y + u, fill, h - 2.0 * u, color);
    // tacche del costo: a metà con i valori di default (due mosse a barra piena)
    let mut k = cost.max(1.0);
    while k < max - 0.5 {
        let off = k / max * inner;
        let tx = if from_right { x + w - u - off } else { x + u + off };
        draw_rectangle(tx - u / 2.0, y - u, u, h + 2.0 * u, if ready { accent } else { gray });
        k += cost.max(1.0);
    }
}

/// Capsula di lato `size` centrata in (cx, cy): bordo e icona, oppure in negativo.
pub fn draw_capsule(bonus: Bonus, cx: f32, cy: f32, size: f32, u: f32, inverted: bool, color: Color) {
    let (x, y) = (cx - size / 2.0, cy - size / 2.0);
    let icon = 9.0 * u;
    let (ix, iy) = (cx - icon / 2.0, cy - icon / 2.0);
    if inverted {
        draw_rectangle(x, y, size, size, color);
        draw_icon(bonus, ix, iy, u, BLACK);
    } else {
        draw_rectangle_lines(x, y, size, size, u * 2.0, color);
        draw_icon(bonus, ix, iy, u, color);
    }
}

/// Posizione della palla come frazione della larghezza del campo, dal bordo del giocatore `side`.
fn field_share(game: &Match, side: usize) -> f32 {
    let share = to_f32(game.ball.x) / to_f32(game.params.width);
    if side == 0 { share } else { 1.0 - share }
}

/// Avanzamento del salto del TELEPORT con la palla a `share` (vedi `field_share`): parte
/// affondata nel primo portale e parte uscita dal secondo, da 0 a 1.
fn warp_progress(share: f32) -> (f32, f32) {
    let sunk = ((0.5 - share) / WARP_STEP).clamp(0.0, 1.0);
    let out = ((WARP_RISE - share) / WARP_STEP).clamp(0.0, 1.0);
    (sunk, out)
}

/// Salto del TELEPORT (coordinate del core, y verso l'alto): la racchetta affonda per `sunk` in
/// una linea orizzontale sul lato verso cui salta ed esce per `out` da una seconda linea sul lato
/// opposto della posizione d'arrivo. Disegna solo la parte oltre ciascuna linea; le linee hanno il
/// colore di accento. Il secondo portale si apre a metà dell'affondo.
#[allow(clippy::too_many_arguments)]
fn draw_warp(
    r: &Renderer,
    x: f32,
    from: f32,
    to: f32,
    (sunk, out): (f32, f32),
    pw: f32,
    ph: f32,
    u: f32,
    color: Color,
    line_color: Color,
) {
    let dir = if to > from { 1.0 } else { -1.0 };
    // tratto di racchetta tra lo e hi, se non è vuoto
    let span = |lo: f32, hi: f32| {
        if hi > lo {
            r.rect_centered(x, (lo + hi) / 2.0, pw, hi - lo, color);
        }
    };
    let line = |y: f32| r.rect_centered(x, y, 2.0 * WARP_LINE_HALF * u, 2.0 * u, line_color);
    if sunk < 1.0 {
        let edge = from + dir * ph / 2.0;
        let c = from + dir * ph * sunk;
        if dir > 0.0 {
            span(c - ph / 2.0, (c + ph / 2.0).min(edge));
        } else {
            span((c - ph / 2.0).max(edge), c + ph / 2.0);
        }
        line(edge);
    }
    if sunk >= 0.5 {
        let edge = to - dir * ph / 2.0;
        let c = to - dir * ph * (1.0 - out);
        if dir > 0.0 {
            span((c - ph / 2.0).max(edge), c + ph / 2.0);
        } else {
            span(c - ph / 2.0, (c + ph / 2.0).min(edge));
        }
        line(edge);
    }
}

// ------------------------------------------------------------------ scelta

/// Scelta dei 3 bonus di ciascun giocatore prima della partita.
pub struct Pick {
    /// il giocatore di destra è il computer: sceglie da solo
    cpu: bool,
    /// lato che ha già i suoi bonus e non sceglie: la CPU, o il campione quando entra uno sfidante
    fixed: Option<usize>,
    /// CHALLENGE: sceglie lo sfidante di questo lato, poi si gioca la sfida
    duel: Option<Side>,
    cursor: [usize; 2],
    chosen: [Vec<Bonus>; 2],
    /// scelta chiusa: con tasti ed encoder al terzo bonus, con il touch toccando OK
    confirmed: [bool; 2],
    left: f64,
    ready: Option<f64>,
    /// encoder già impostati per la scelta
    knobs_ready: bool,
}

impl Pick {
    pub fn new(app: &App) -> Self {
        let mut chosen = [Vec::new(), Vec::new()];
        if app.run.is_some() {
            chosen[1] = paddws_core::challenge::RUNGS[0].loadout.to_vec();
        } else if app.cpu {
            // tre bonus diversi a caso, dal seme della partita
            let mut rng = paddws_core::Rng::new(app.seed ^ 0x9E37_79B9);
            while chosen[1].len() < 3 {
                let b = Bonus::PICKABLE[rng.below(Bonus::PICKABLE.len() as u32) as usize];
                if !chosen[1].contains(&b) {
                    chosen[1].push(b);
                }
            }
        }
        Self {
            cpu: app.cpu,
            fixed: app.cpu.then_some(1),
            duel: None,
            cursor: [0; 2],
            chosen,
            confirmed: [false; 2],
            left: PICK_SECONDS,
            ready: None,
            knobs_ready: false,
        }
    }

    /// CHALLENGE, nuovo sfidante sul lato `free`: sceglie solo lui, il campione tiene i suoi bonus.
    pub fn challenger(app: &App, free: Side) -> Self {
        let champion = free.opponent() as usize;
        let mut pick = Self::new(app);
        pick.cpu = false;
        pick.fixed = Some(champion);
        pick.duel = Some(free);
        pick.chosen = [Vec::new(), Vec::new()];
        pick.chosen[champion] = app.loadout[champion].to_vec();
        pick
    }


    /// Gamepad come i tasti del lato (`input`): su e giù spostano il cursore, A prende o lascia il bonus, B torna al
    /// menu. Con un solo gamepad è di chi sceglie.
    pub fn pad_keys(&self, app: &App) -> PadKeys {
        let solo = self.fixed.map(|f| 1 - f);
        input::pad_keys(|slot, c| {
            let (up, down, toggle) = PICK_KEYS[app.pads.side_of(slot, solo)];
            match c {
                Control::Up => Some(up),
                Control::Down => Some(down),
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

    /// y del centro della riga `i` e altezza delle righe (coordinate di disegno).
    fn row(app: &App, i: usize) -> (f32, f32) {
        let s = app.scale();
        let rows = Bonus::PICKABLE.len() as f32;
        let row_h = ((app.renderer.world_h - 170.0 * s) / rows).min(60.0 * s);
        (175.0 * s + i as f32 * row_h, row_h)
    }

    /// Prende o lascia il bonus sotto il cursore del giocatore `side`.
    fn toggle(&mut self, app: &App, side: usize) {
        let b = Bonus::PICKABLE[self.cursor[side]];
        let chosen = &mut self.chosen[side];
        if let Some(i) = chosen.iter().position(|&c| c == b) {
            chosen.remove(i);
            app.play(Event::Wall);
        } else if chosen.len() < 3 {
            chosen.push(b);
            app.play(Event::Hit);
        }
    }

    fn loadouts(&self) -> [[Bonus; 3]; 2] {
        std::array::from_fn(|i| std::array::from_fn(|k| self.chosen[i][k]))
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            return Some(Scene::Menu(Menu::new(app)));
        }
        if let Some(t) = &mut self.ready {
            *t -= dt;
            if *t <= 0.0 {
                app.loadout = self.loadouts();
                return Some(Scene::Paddles(match self.duel {
                    Some(free) => PaddlePick::challenger(app, free),
                    None => PaddlePick::new(app),
                }));
            }
            return None;
        }
        self.left -= dt;
        let n = Bonus::PICKABLE.len();
        for (side, &(up, down, toggle)) in PICK_KEYS.iter().enumerate() {
            if self.fixed == Some(side) {
                continue;
            }
            let chosen = &mut self.chosen[side];
            if chosen.len() == 3 && !input::pressed(toggle) {
                continue;
            }
            let cur = &mut self.cursor[side];
            if input::pressed(up) {
                *cur = (*cur + n - 1) % n;
            }
            if input::pressed(down) {
                *cur = (*cur + 1) % n;
            }
            if input::pressed(toggle) {
                self.toggle(app, side);
                self.confirmed[side] = self.chosen[side].len() == 3;
            }
        }
        // encoder: la rotazione sposta il cursore, il click (o USA) prende o lascia il bonus
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
                Action::Rotate(v) => self.cursor[e.player] = (v.max(0) as usize).min(n - 1),
                Action::Click | Action::Activate => {
                    self.toggle(app, e.player);
                    self.confirmed[e.player] = self.chosen[e.player].len() == 3;
                }
                _ => {}
            }
        }
        // touch: un tocco su una riga della propria colonna prende o lascia quel bonus; con tre
        // bonus si conferma toccando OK in cima alla colonna (vale tutto lo spazio sopra le righe)
        let (first, row_h) = Self::row(app, 0);
        for p in touch::taps() {
            let side = usize::from(p.x >= app.renderer.world_w / 2.0);
            if self.fixed == Some(side) {
                continue;
            }
            if p.y < first - row_h / 2.0 {
                if self.chosen[side].len() == 3 && !self.confirmed[side] {
                    self.confirmed[side] = true;
                    app.play(Event::Hit);
                }
            } else if let Some(i) = (0..n).find(|&i| {
                let (cy, row_h) = Self::row(app, i);
                (p.y - cy).abs() < row_h / 2.0
            }) {
                self.cursor[side] = i;
                self.toggle(app, side);
                self.confirmed[side] = false;
            }
        }
        let done = (0..2).all(|i| self.fixed == Some(i) || self.confirmed[i]);
        if done || self.left <= 0.0 {
            // tempo scaduto: si completa con le scelte predefinite
            for chosen in &mut self.chosen {
                for b in DEFAULT_PICK.iter().chain(Bonus::PICKABLE.iter()) {
                    if chosen.len() < 3 && !chosen.contains(b) {
                        chosen.push(*b);
                    }
                }
            }
            self.ready = Some(READY_SECONDS);
            app.play(Event::Boost);
        }
        None
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let s = app.scale();
        let u = unit(app);
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        let font = &app.assets.font_text;
        r.fill(BLACK);
        r.text_centered("PICK 3 BONUSES", font, 34.0 * s, w / 2.0, 34.0 * s, 0.0, accent);
        let secs = format!("{:02}", self.left.max(0.0).ceil() as u32);
        let blink = self.left < 3.0 && (get_time() * 4.0) as i64 % 2 == 1;
        r.text_centered(
            &secs,
            &app.assets.font_score,
            48.0 * s,
            w / 2.0,
            84.0 * s,
            0.0,
            if blink { gray } else { white },
        );

        let dash = 10.0 * s;
        let mut y = 120.0 * s;
        while y < h - 20.0 * s {
            draw_rectangle(w / 2.0 - u, y, 2.0 * u, dash, white);
            y += dash * 2.0;
        }

        let size = 13.0 * u;
        for side in 0..2 {
            let col = if side == 0 { w / 4.0 } else { 3.0 * w / 4.0 };
            let chosen = &self.chosen[side];
            let head = HEAD_Y * s;
            r.text_centered(&self.name(side), font, 30.0 * s, col - 70.0 * s, head, 0.0, white);
            if app.touch && chosen.len() == 3 && !self.confirmed[side] && self.fixed != Some(side) && self.ready.is_none() {
                // touch: il pulsante con cui si chiude la scelta
                draw_rectangle(col + 35.0 * s, head - 18.0 * s, 70.0 * s, 36.0 * s, accent);
                let black = App::color(app.cfg.colors.black);
                r.text_centered("OK", font, 30.0 * s, col + 70.0 * s, head, 0.0, black);
            } else {
                r.text_centered(
                    &format!("{}/3", chosen.len()),
                    font,
                    30.0 * s,
                    col + 70.0 * s,
                    head,
                    0.0,
                    if chosen.len() == 3 { white } else { gray },
                );
            }
            for (i, &b) in Bonus::PICKABLE.iter().enumerate() {
                let (cy, _) = Self::row(app, i);
                let on = chosen.contains(&b);
                let here = self.cursor[side] == i && chosen.len() < 3 && self.ready.is_none();
                let color = if on || here { white } else { gray };
                if here {
                    r.text_centered(">", font, 30.0 * s, col - 105.0 * s, cy, 0.0, accent);
                }
                draw_capsule(b, col - 70.0 * s, cy, size, u, on, color);
                r.text_centered(b.name(), font, 30.0 * s, col + 15.0 * s, cy, 0.0, color);
            }
        }
        if self.ready.is_some() && (get_time() * 6.0) as i64 % 2 == 0 {
            r.text_centered("READY!", font, 40.0 * s, w / 2.0, h - 26.0 * s, 0.0, accent);
        } else if self.ready.is_none() && !app.touch {
            // tasti di ciascun giocatore, centrati sotto la sua colonna (chi non sceglie non ne ha)
            if self.fixed != Some(0) {
                r.text_centered("W S + C", font, 20.0 * s, w / 4.0, h - 16.0 * s, 0.0, gray);
            }
            if self.fixed != Some(1) {
                r.text_centered("UP DOWN + -", font, 20.0 * s, 3.0 * w / 4.0, h - 16.0 * s, 0.0, gray);
            }
        }
    }
}

// --------------------------------------------------------------- partita

/// Stato grafico di NEXT durante la partita.
pub struct NextFx {
    /// posizioni recenti della palla (coordinate del core) per le scie
    trail: VecDeque<(f32, f32)>,
    /// salto del TELEPORT in corso: y di partenza (l'avanzamento segue la palla)
    warp: [Option<f32>; 2],
    label: Option<(String, f64)>,
    /// spostamento dei trattini della mezzeria spazzati dalla COMETA, per trattino
    dash_kick: Vec<f32>,
    counts: [usize; 2],
    /// chi aveva il BULLET prima del tick (per riconoscere quello appena attivato)
    bullet_before: Option<Side>,
    pad_last: [f32; 2],
    /// secondi del lampo e settore del muro del GUARDIAN appena colpito
    barrier_flash: [(f64, usize); 2],
    /// RUSH: secondi delle righe di velocità, dall'inizio dello scatto in avanti
    rush_ghost: [f64; 2],
    pad_home: [bool; 2],
    /// mosse speciali: barra prima del tick (per capire chi ha speso), scritta della mossa per
    /// giocatore (mossa, livello, colpo invece di attivazione, secondi rimasti), RISING STRIKE
    /// ancora da impennare prima del tick e quadrato del colpo o dell'impennata (x, y, secondi)
    meters: [u8; 2],
    special_label: [Option<(Special, u8, bool, f64)>; 2],
    rise_pending: bool,
    burst: Option<(f32, f32, f64)>,
}

impl NextFx {
    pub fn new() -> Self {
        Self {
            trail: VecDeque::new(),
            warp: [None; 2],
            label: None,
            dash_kick: Vec::new(),
            counts: [0; 2],
            bullet_before: None,
            pad_last: [0.0; 2],
            barrier_flash: [(0.0, 0); 2],
            rush_ghost: [0.0; 2],
            pad_home: [true; 2],
            meters: [0; 2],
            special_label: [None; 2],
            rise_pending: false,
            burst: None,
        }
    }

    /// Scritta di un bonus al centro in basso (come "P1 SMASH!").
    pub fn show_label(&mut self, text: &str) {
        self.label = Some((text.to_string(), LABEL_SECONDS));
    }

    /// Scritta di una mossa speciale di livello `level` per il giocatore `side`: all'attivazione
    /// o, con `hit`, al colpo.
    pub fn show_special(&mut self, side: usize, special: Special, level: u8, hit: bool) {
        self.special_label[side] = Some((special, level, hit, LABEL_SECONDS));
    }

    /// Da chiamare prima di ogni tick: serve a capire chi ha attivato un bonus.
    pub fn before_tick(&mut self, game: &Match) {
        if let Some(n) = &game.next {
            self.counts = [n.players[0].count(), n.players[1].count()];
            self.meters = [n.players[0].meter, n.players[1].meter];
            self.rise_pending = n.rise_break.is_some();
            self.bullet_before = n.bullet;
        }
    }

    pub fn after_tick(&mut self, game: &Match, events: Events, scale: f32) {
        let Some(n) = &game.next else { return };
        if events.has(Event::Activate) {
            for side in 0..2 {
                let pl = &n.players[side];
                if pl.count() < self.counts[side] {
                    // SLOW e BULLET non restano armati: il BULLET si riconosce da chi lo ha da questo tick
                    let bullet = n.bullet == Some(if side == 0 { Side::Left } else { Side::Right })
                        && self.bullet_before != n.bullet;
                    let name = if bullet {
                        Bonus::Bullet.name()
                    } else {
                        pl.armed.map_or("SLOW", Bonus::name)
                    };
                    self.label = Some((format!("P{} {name}!", side + 1), LABEL_SECONDS));
                }
            }
        }
        let b = &game.ball;
        // mosse speciali: chi ha speso la barra ha attivato la mossa (il costo supera qualunque
        // guadagno di un tick); con due attivazioni nello stesso tick conta lo STRAIGHT SHOT armato
        let (straight, rise) = (events.has(Event::Straight), events.has(Event::Rise));
        if straight || rise {
            for side in 0..2 {
                let pl = &n.players[side];
                if pl.meter >= self.meters[side] {
                    continue;
                }
                let (special, level) = if straight && (!rise || pl.straight > 0) {
                    (Special::Straight, pl.straight)
                } else {
                    (Special::Rise, pl.rise)
                };
                self.show_special(side, special, level, false);
            }
        }
        if events.has(Event::SpecialHit)
            && let Some(special) = n.special_flight
        {
            let side = if b.vx > 0 { 0 } else { 1 };
            self.show_special(side, special, n.special_level, true);
            self.burst = Some((to_f32(b.x), to_f32(b.y), BURST_SECONDS));
        }
        // RISING STRIKE: un altro quadrato dove la palla s'impenna
        if self.rise_pending && n.rise_break.is_none() && n.special_flight == Some(Special::Rise) {
            self.burst = Some((to_f32(b.x), to_f32(b.y), BURST_SECONDS));
        }
        // il colpo di HAMMER (un piccolo boost a ogni tiro) non lascia la scia: resta per i bonus
        let boosted = b.boost != ONE && b.boost != game.params.hammer_mul;
        let effect = boosted
            || n.curve != 0
            || n.steer.is_some()
            || n.super_flight.is_some()
            || n.special_flight.is_some()
            || n.slow_timer > 0
            || n.bullet_on;
        if effect {
            self.trail.push_back((to_f32(b.x), to_f32(b.y)));
            if self.trail.len() > BULLET_GHOST_TICKS {
                self.trail.pop_front();
            }
        } else {
            // finito l'effetto la coda si svuota come prima del bullet time (al massimo 40 posizioni)
            self.trail.pop_front();
            while self.trail.len() > 40 {
                self.trail.pop_front();
            }
        }
        // GUARDIAN: la palla rimbalzata va ora verso l'avversario di chi aveva il muro, alla
        // stessa altezza del settore colpito
        if events.has(Event::Barrier) {
            self.barrier_flash[if b.vx > 0 { 0 } else { 1 }] =
                (BARRIER_FLASH_SECONDS, guardian_sector(&game.params, b.y));
        }
        // TELEPORT: salta la racchetta verso cui va la palla, dalla y del tick precedente; il
        // salto finisce quando la racchetta è uscita, al colpo o al punto
        let toward = if b.vx < 0 { 0 } else { 1 };
        if events.has(Event::Teleport) && self.warp[toward].is_none() {
            self.warp[toward] = Some(self.pad_last[toward]);
        }
        for (side, warp) in self.warp.iter_mut().enumerate() {
            let out = warp_progress(field_share(game, side)).1 >= 1.0;
            if side != toward || n.players[side].armed != Some(Bonus::Teleport) || out {
                *warp = None;
            }
        }
        for (side, pad) in game.paddles.iter().enumerate() {
            self.pad_last[side] = to_f32(pad.y);
            if self.pad_home[side] && !pad.at_home() {
                self.rush_ghost[side] = RUSH_GHOST_SECONDS;
            }
            self.pad_home[side] = pad.at_home();
        }
        // la COMETA spazza i trattini della mezzeria vicini alla palla
        if n.super_flight == Some(SuperAnim::Comet) {
            let w = to_f32(game.params.width);
            let h = to_f32(game.params.height);
            let dash = 10.0 * scale;
            let count = (h / (dash * 2.0)).ceil() as usize;
            self.dash_kick.resize(count, 0.0);
            if (to_f32(b.x) - w / 2.0).abs() < 12.0 * scale {
                let sy = h - to_f32(b.y);
                let dir = if b.vx > 0 { 1.0 } else { -1.0 };
                for (i, k) in self.dash_kick.iter_mut().enumerate() {
                    let dy = i as f32 * dash * 2.0 + dash / 2.0 - sy;
                    if dy.abs() < 36.0 * scale && *k == 0.0 {
                        *k = dir * (30.0 - dy.abs() * 0.5) * scale;
                    }
                }
            }
        }
    }

    pub fn update(&mut self, dt: f64) {
        for t in self.barrier_flash.iter_mut().map(|(t, _)| t).chain(&mut self.rush_ghost) {
            *t = (*t - dt).max(0.0);
        }
        if let Some((_, t)) = &mut self.label {
            *t -= dt;
            if *t <= 0.0 {
                self.label = None;
            }
        }
        for label in &mut self.special_label {
            if let Some((_, _, _, t)) = label {
                *t -= dt;
                if *t <= 0.0 {
                    *label = None;
                }
            }
        }
        if let Some((_, _, t)) = &mut self.burst {
            *t -= dt;
            if *t <= 0.0 {
                self.burst = None;
            }
        }
        let decay = (0.04f32).powf(dt as f32); // i trattini tornano al loro posto in circa un secondo
        for k in &mut self.dash_kick {
            *k *= decay;
            if k.abs() < 0.3 {
                *k = 0.0;
            }
        }
    }

    /// Spostamento orizzontale del trattino `i` della mezzeria.
    pub fn dash_offset(&self, i: usize) -> f32 {
        self.dash_kick.get(i).copied().unwrap_or(0.0)
    }

    /// Hit-stop del SUPER: (schermo invertito, scossa orizzontale).
    pub fn hit_stop(game: &Match, u: f32) -> (bool, f32) {
        match &game.next {
            Some(n) if n.freeze > 0 => {
                let invert = n.freeze * 3 > game.params.hitstop_ticks * 2;
                let shake = if (n.freeze / 8) % 2 == 0 { 2.0 * u } else { -2.0 * u };
                (invert, shake)
            }
            _ => (false, 0.0),
        }
    }

    /// Racchette, palla ed effetti di NEXT (al posto del disegno normale); la racchetta `skip`
    /// no (nel bullet time quella di chi l'ha attivato si disegna a parte, nitida: `draw_pad`).
    pub fn draw_field(&self, app: &App, game: &Match, pos: &[(f32, f32); 3], shake: f32, skip: Option<usize>) {
        let Some(n) = &game.next else { return };
        let r = &app.renderer;
        let u = unit(app);
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        let blink = (game.tick / 16).is_multiple_of(2);
        // bullet time: il bianco diventa grigio tranne per la racchetta (e i colpi) di chi l'ha attivato
        let time = bullet_time(game);
        let owner = time.map(|b| b.side);
        let cold = |c: Color| slowed_color(c, owner.is_some(), white, gray);
        let tint = |side: usize, c: Color| if owner == Some(side) { c } else { cold(c) };

        // GUARDIAN: muro tratteggiato a settori dietro la racchetta, sotto la banda delle
        // riserve; il settore che rimanda la palla lampeggia e sparisce
        for (side, pl) in n.players.iter().enumerate() {
            if pl.kind != Some(PaddleKind::Guardian) {
                continue;
            }
            let p = &game.params;
            let bx = to_f32(p.guardian_barrier_x);
            let lx = if side == 0 { bx } else { to_f32(p.width) - bx } + shake;
            let (flash, hit) = self.barrier_flash[side];
            let mut edges = [to_f32(p.guardian_top); GUARDIAN_SECTORS + 1];
            for (e, &b) in edges[1..].iter_mut().zip(&p.guardian_bounds) {
                *e = to_f32(b);
            }
            edges[GUARDIAN_SECTORS] = 0.0;
            // dall'alto dello schermo: la y del core cresce verso l'alto
            let edges = edges.map(|e| r.screen_y(e));
            for (i, e) in edges.windows(2).enumerate() {
                let color = if flash > 0.0 && i == hit {
                    if (get_time() * 30.0) as i64 % 2 == 0 {
                        accent
                    } else {
                        Color { a: 0.3, ..accent }
                    }
                } else if pl.barrier & (1 << i) != 0 {
                    Color { a: 0.9, ..accent }
                } else {
                    continue;
                };
                let color = tint(side, color);
                let mut dy = e[0] + 2.0 * u;
                while dy < e[1] - 2.0 * u {
                    draw_rectangle(lx - u, dy, 2.0 * u, (5.0 * u).min(e[1] - 2.0 * u - dy), color);
                    dy += 8.0 * u;
                }
            }
        }

        // BLASTER: i colpi in volo, due tratti paralleli ciascuno
        for (side, pl) in n.players.iter().enumerate() {
            for shot in pl.shots.iter().flatten() {
                let (sx, sy) = (to_f32(shot.x) + shake, to_f32(shot.y));
                for dy in [-2.0 * u, 2.0 * u] {
                    r.rect_centered(sx, sy + dy, 7.0 * u, u, tint(side, accent));
                }
            }
        }

        for (side, &at) in pos.iter().take(2).enumerate() {
            if skip != Some(side) {
                self.draw_pad(app, game, at, shake, side);
            }
        }

        // STEER: segni sui bordi alto e basso dove finisce la guida (3/4 del campo)
        if let Some(side) = n.steer {
            let w = to_f32(game.params.width);
            let lx = if side == Side::Left { w - w / 4.0 } else { w / 4.0 };
            draw_rectangle(lx - u, 0.0, 2.0 * u, 6.0 * u, accent);
            draw_rectangle(lx - u, r.world_h - 6.0 * u, 2.0 * u, 6.0 * u, accent);
        }

        // scie della palla: lunga e piena per la COMETA; per gli altri effetti una coda larga quanto
        // la palla che sfuma dal grigio al nero (dalla più vecchia, così le nuove la coprono)
        let ball = &game.ball;
        let d = to_f32(ball.radius) * 2.0;
        let comet = n.super_flight == Some(SuperAnim::Comet);
        // la palla del SUPER e delle mosse speciali in volo (e la testa della cometa) ha il colore
        // di accento, e la coda delle mosse sfuma dall'accento invece che dal grigio
        let special = n.special_flight;
        let ball_color = if n.super_flight.is_some() || special.is_some() {
            accent
        } else {
            white
        };
        let tail = if special.is_some() { accent } else { gray };
        let black = App::color(app.cfg.colors.black);
        // con GHOST la coda non si disegna: tradirebbe la palla quando è nascosta
        let len = if n.ghost.is_some() { 0 } else { self.trail.len() };
        // nel bullet time la coda è lunga il doppio, con le immagini della palla lungo la scia
        let trail_ticks = if owner.is_some() { TRAIL_TICKS * 2 } else { TRAIL_TICKS };
        let ghosts = if time.is_some_and(|b| b.k >= 1.0) {
            BULLET_GHOST_TICKS
        } else {
            BULLET_GHOST_TICKS / 2
        };
        for (i, &(tx, ty)) in self.trail.iter().take(len).enumerate() {
            let age = len - i;
            if owner.is_some() && age <= ghosts && age.is_multiple_of(BULLET_GHOST_STEP) {
                // immagine della palla: solo il contorno grigio, così non si confonde con la palla
                let (gx, gy) = (tx + shake - d / 2.0, r.screen_y(ty) - d / 2.0);
                draw_rectangle_lines(gx, gy, d, d, u, gray);
            }
        }
        for (i, &(tx, ty)) in self.trail.iter().take(len).enumerate() {
            let age = len - i;
            if comet && age < 30 {
                let size = d * 1.6 * (1.0 - age as f32 / 34.0);
                r.rect_centered(tx + shake, ty, size, size, if age < 8 { accent } else { gray });
            } else if !comet && age <= trail_ticks {
                let fade = 1.0 - age as f32 / (trail_ticks + 1) as f32;
                let c = Color::new(
                    black.r + (tail.r - black.r) * fade,
                    black.g + (tail.g - black.g) * fade,
                    black.b + (tail.b - black.b) * fade,
                    1.0,
                );
                r.rect_centered(tx + shake, ty, d, d, c);
            }
        }
        let serve_blink = game.serving() && (game.serve_timer * 8 / paddws_core::TICK_HZ) % 2 == 1;
        if !serve_blink && !n.ball_hidden(&game.params, game.tick) {
            let size = if comet { d * 1.6 } else { d };
            let (bx, by) = (pos[2].0 + shake, pos[2].1);
            match special {
                // STRAIGHT SHOT: righe di velocità orizzontali dietro la palla
                Some(Special::Straight) => {
                    let back = if ball.vx > 0 { -1.0 } else { 1.0 };
                    for (dy, len) in [(-d, 5.0 * d), (0.0, 9.0 * d), (d, 5.0 * d)] {
                        let lx = bx + back * (d + len / 2.0);
                        r.rect_centered(lx, by + dy, len, u, Color { a: 0.8, ..accent });
                    }
                    r.rect_centered(bx, by, size, size, ball_color);
                }
                // RISING STRIKE: la palla girata di 45 gradi, un rombo
                Some(Special::Rise) => {
                    draw_rectangle_ex(
                        bx,
                        r.screen_y(by),
                        size * 1.2,
                        size * 1.2,
                        DrawRectangleParams {
                            offset: vec2(0.5, 0.5),
                            rotation: std::f32::consts::FRAC_PI_4,
                            color: ball_color,
                        },
                    );
                }
                None => r.rect_centered(bx, by, size, size, ball_color),
            }
            if n.slow_timer > 0 && blink {
                draw_rectangle_lines(bx - d * 1.5, r.screen_y(by) - d * 1.5, d * 3.0, d * 3.0, u, gray);
            }
        }
        // colpo speciale: un quadrato che si allarga dal punto del colpo
        if let Some((cx, cy, t)) = self.burst {
            let k = 1.0 - (t / BURST_SECONDS) as f32;
            let side = d * (1.5 + 5.0 * k);
            let color = Color { a: 1.0 - k, ..accent };
            draw_rectangle_lines(cx + shake - side / 2.0, r.screen_y(cy) - side / 2.0, side, side, u, color);
        }
    }

    /// La racchetta del giocatore `side` in (x, y) (coordinate del core, x già interpolata), con i
    /// segni dei bonus, del tipo e del BULLET.
    pub fn draw_pad(&self, app: &App, game: &Match, (x, y): (f32, f32), shake: f32, side: usize) {
        let Some(n) = &game.next else { return };
        let r = &app.renderer;
        let u = unit(app);
        let blink = (game.tick / 16).is_multiple_of(2);
        let bullet = bullet_look(game);
        let pad = &game.paddles[side];
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        // nel bullet time la racchetta avversaria diventa grigia
        let cold = bullet.is_some_and(|b| b.on && b.side != side);
        let (white, gray, accent) = (
            slowed_color(white, cold, white, gray),
            slowed_color(gray, cold, white, gray),
            slowed_color(accent, cold, white, gray),
        );
        let x = x + shake;
        let (pw, ph) = (to_f32(pad.width), to_f32(pad.height));
        // chi ha il BULLET armato, in attesa della palla: un bordo di accento attorno alla
        // racchetta che pulsa piano (acceso 3/4 di secondo, spento 1/4); nel bullet time no, la
        // racchetta si distingue già perché resta nitida e a colori
        let armed_blink = (game.tick / u64::from(paddws_core::TICK_HZ / 4)) % 4 != 3;
        if bullet.is_some_and(|b| b.side == side && !b.on && armed_blink) {
            let m = 3.0 * u;
            let (bx, by) = (x - pw / 2.0 - m, r.screen_y(y) - ph / 2.0 - m);
            draw_rectangle_lines(bx, by, pw + 2.0 * m, ph + 2.0 * m, u, accent);
        }
        if let Some(from) = self.warp[side] {
            let progress = warp_progress(field_share(game, side));
            draw_warp(r, x, from, y, progress, pw, ph, u, white, accent);
            return;
        }
        let pl = &n.players[side];
        // RUSH vibra appena, a casa e avanzato: avanti e indietro di mezzo pixel arcade
        let x = if pl.kind == Some(PaddleKind::Rush) {
            x + if (game.tick / 8).is_multiple_of(2) {
                u / 2.0
            } else {
                -u / 2.0
            }
        } else {
            x
        };
        let steering = n.steer.is_some_and(|s| s as usize == side);
        // RUSH: immagini dello scatto dalla posizione di casa, che sfumano
        let dash = (self.rush_ghost[side] > 0.0)
            .then(|| (to_f32(pad.home_x) + shake, (self.rush_ghost[side] / RUSH_GHOST_SECONDS) as f32));
        let tilt = if pl.kind == Some(PaddleKind::Twist) {
            paddle_ui::twist_tilt(pad)
        } else {
            0.0
        };
        // la racchetta con il segno del suo tipo
        let body = |color: Color| {
            let shape = Shape {
                kind: pl.kind,
                x,
                y,
                w: pw,
                h: ph,
                front: if side == 0 { 1.0 } else { -1.0 },
                tilt,
                dash,
                preview: false,
            };
            let look = Look {
                body: color,
                mark: accent,
                detail: gray,
            };
            paddle_ui::draw_paddle(r, &shape, u, look);
        };
        // BLASTER: munizioni dietro la racchetta, lontano dalla palla: un rettangolino giallo per
        // colpo nel caricatore, dal basso, in un tratto corto della racchetta; spariscono a ogni
        // colpo e tornano tutte insieme con la ricarica
        if pl.kind == Some(PaddleKind::Blaster) {
            let bx = x + if side == 0 { -1.0 } else { 1.0 } * (pw / 2.0 + 3.0 * u);
            let (h, step) = (3.0 * u, 4.0 * u);
            let base = y - ph / 2.0 + u + h / 2.0;
            for k in 0..pl.ammo as usize {
                r.rect_centered(bx, base + k as f32 * step, 2.0 * u, h, accent);
            }
        }
        match pl.armed {
            // STEER: racchetta ferma (grigia) con il volante accanto finché si guida la palla
            _ if steering => {
                body(gray);
                let ix = if side == 0 { x + pw + 3.0 * u } else { x - pw - 12.0 * u };
                draw_icon(Bonus::Steer, ix, r.screen_y(y) - 4.5 * u, u, accent);
            }
            Some(Bonus::Super) if pl.super_anim == SuperAnim::Spin => {
                let angle = game.tick as f32 * 0.09;
                draw_rectangle_ex(
                    x,
                    r.screen_y(y),
                    pw,
                    ph,
                    DrawRectangleParams {
                        offset: vec2(0.5, 0.5),
                        rotation: angle,
                        color: white,
                    },
                );
            }
            Some(b) => {
                body(if blink { gray } else { white });
                let ix = if side == 0 { x + pw + 3.0 * u } else { x - pw - 12.0 * u };
                draw_icon(b, ix, r.screen_y(y) - 4.5 * u, u, gray);
            }
            // mossa armata: il suo segno accanto alla racchetta, come un bonus armato; al livello 2
            // anche la racchetta nel colore di accento
            _ if pl.straight > 0 || pl.rise > 0 => {
                let (special, level) = if pl.straight > 0 {
                    (Special::Straight, pl.straight)
                } else {
                    (Special::Rise, pl.rise)
                };
                body(if level >= MAX_SPECIAL_LEVEL { accent } else { white });
                let ix = if side == 0 { x + pw + 3.0 * u } else { x - pw - 12.0 * u };
                draw_special_icon(special, ix, r.screen_y(y) - 4.5 * u, u, side, accent);
            }
            _ => body(white),
        }
    }

    /// Riserve in alto, barre delle mosse speciali e capsule in volo (le scritte: `draw_labels`).
    pub fn draw_hud(&self, app: &App, game: &Match) {
        let Some(n) = &game.next else { return };
        let r = &app.renderer;
        let w = r.world_w;
        let u = unit(app);
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        let size = to_f32(game.params.capsule_half) * 2.0;
        // le capsule rare (SUPER e BULLET) hanno il colore di accento
        let capsule_color = |b: Bonus| if b.rare() { accent } else { white };
        let slow = bullet_time(game).is_some();

        for (side, pl) in n.players.iter().enumerate() {
            for i in 0..3 {
                let (cx, cy) = reserve_slot(w, u, size, side, i);
                match pl.reserve[i] {
                    Some(b) => draw_capsule(b, cx, cy, size, u, i == pl.selected as usize, capsule_color(b)),
                    None => draw_rectangle_lines(
                        cx - size / 2.0,
                        cy - size / 2.0,
                        size,
                        size,
                        u,
                        Color { a: 0.5, ..gray },
                    ),
                }
                if i == pl.selected as usize && pl.count() > 0 {
                    draw_triangle(
                        vec2(cx - 3.0 * u, cy + size / 2.0 + 2.0 * u),
                        vec2(cx + 3.0 * u, cy + size / 2.0 + 2.0 * u),
                        vec2(cx, cy + size / 2.0 + 5.0 * u),
                        accent,
                    );
                }
            }
        }

        // mosse speciali: barra accanto alla riserva, verso il centro, e scritta della mossa sotto
        // la banda, nella metà del giocatore
        if n.super_moves {
            let p = &game.params;
            let flash = (game.tick / 16).is_multiple_of(2);
            let (bw, bh) = (44.0 * u, 6.0 * u);
            for (side, pl) in n.players.iter().enumerate() {
                let (cx, cy) = reserve_slot(w, u, size, side, 2);
                let x = if side == 0 {
                    cx + size / 2.0 + 6.0 * u
                } else {
                    cx - size / 2.0 - 6.0 * u - bw
                };
                let ready = pl.special_ready(p) && !game.serving();
                draw_meter(
                    (x, cy - bh / 2.0, bw, bh),
                    u,
                    pl.meter as f32,
                    p.super_meter_max as f32,
                    p.super_cost as f32,
                    side == 1,
                    (ready, ready && flash),
                    (white, gray, accent),
                );
            }
        }

        let blink = (game.tick / 32).is_multiple_of(2);
        for c in n.capsules.iter().flatten() {
            let inverted = c.bonus == Bonus::Super && blink; // il SUPER si riconosce da lontano
            let color = slowed_color(capsule_color(c.bonus), slow, white, gray); // rallentano anche loro
            draw_capsule(c.bonus, to_f32(c.x), r.screen_y(to_f32(c.y)), size, u, inverted, color);
        }
    }

    /// Scritte della mossa speciale e del bonus attivato: sopra tutto, nitide anche nel bullet time.
    pub fn draw_labels(&self, app: &App, game: &Match) {
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let s = app.scale();
        let white = App::color(app.cfg.colors.white);
        let accent = App::color(app.cfg.colors.accent);
        if game.next.as_ref().is_some_and(|n| n.super_moves) {
            let p = &game.params;
            let font = &app.assets.font_text;
            // sotto le riserve; con i punteggi dritti (che stanno proprio lì, a 42 righe su 480) sotto
            // di loro, così il titolo, anche nella sua dimensione più grande, non li copre
            let y = if app.cfg.game.scores_upright {
                42.0 * h / 480.0 + 50.0 * s
            } else {
                to_f32(p.capsule_margin_top) + 16.0 * s
            };
            for (side, label) in self.special_label.iter().enumerate() {
                let Some((special, level, hit, t)) = *label else { continue };
                // entra grande e si stringe; nell'ultima parte lampeggia come le altre scritte
                if t < LABEL_SECONDS * 0.3 && (get_time() * 8.0) as i64 % 2 == 1 {
                    continue;
                }
                let zoom = ((t - (LABEL_SECONDS - SPECIAL_ZOOM_SECONDS)) / SPECIAL_ZOOM_SECONDS).clamp(0.0, 1.0) as f32;
                let base = (if hit { 34.0 } else { 28.0 }) * s;
                let size = base * (1.0 + 0.6 * zoom);
                // durante lo zoom i caratteri sono quelli grandi, scalati (`text_centered_zoom`);
                // fermi, quelli alla dimensione giusta, nitidi
                let raster = if zoom > 0.0 { base * 1.6 } else { base };
                // al colpo la scritta alterna accento e bianco
                let color = if hit && (get_time() * 12.0) as i64 % 2 == 0 {
                    white
                } else {
                    accent
                };
                let cx = if side == 0 { w / 4.0 } else { 3.0 * w / 4.0 };
                r.text_centered_zoom(&special_title(special, level), font, size, raster, cx, y, color);
            }
        }

        if let Some((text, t)) = &self.label
            && (*t > LABEL_SECONDS * 0.5 || (get_time() * 8.0) as i64 % 2 == 0)
        {
            let font = &app.assets.font_text;
            let y = h - 34.0 * s;
            draw_rectangle(w / 2.0 - 120.0 * s, y - 20.0 * s, 240.0 * s, 40.0 * s, BLACK);
            r.text_centered(text, font, 32.0 * s, w / 2.0, y, 0.0, accent);
        }
    }
}
