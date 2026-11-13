//! Tipi di racchetta di NEXT a schermo: il disegno di ogni tipo, uguale in partita e
//! nella scelta, e la schermata di scelta della racchetta, dopo quella dei bonus.
//!
//! Ogni tipo ha un segno che lo distingue (come nel mockup approvato): ARCADE una
//! capsula accanto, TITAN le estremità gialle sul retro, HAMMER più spessa con le
//! bande grigie, TWIST inclinata con la velocità, BLASTER smussata con le canne,
//! RUSH le immagini gialle dello scatto in avanti, GUARDIAN la barriera tratteggiata dietro.

use macroquad::prelude::*;
use paddws_core::fixed::to_f32;
use paddws_core::{Event, Paddle, PaddleKind, Side};

use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::{PICK_KEYS, PICK_SECONDS, Pick, READY_SECONDS, unit};
use crate::render::Renderer;
use crate::scenes::{App, Menu, Scene};
use crate::touch;

/// Inclinazione massima di TWIST (circa 20 gradi).
pub(crate) const TWIST_MAX_TILT: f32 = 0.35;

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

/// Colori di una racchetta: corpo, segno del tipo (di solito l'accento) e dettagli grigi.
#[derive(Clone, Copy)]
pub struct Look {
    pub body: Color,
    pub mark: Color,
    pub detail: Color,
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
    /// sfuma); RUSH lascia immagini gialle tra la partenza e dove si trova
    pub dash: Option<(f32, f32)>,
    /// anteprima della scelta: GUARDIAN mostra un pezzo di muro (in partita è a tutta altezza)
    pub preview: bool,
}

/// Inclinazione di TWIST dalla velocità della racchetta: salendo la faccia si gira verso l'alto.
pub fn twist_tilt(pad: &Paddle) -> f32 {
    if pad.max_speed == 0 {
        return 0.0;
    }
    (to_f32(pad.motion) / to_f32(pad.max_speed)).clamp(-1.0, 1.0) * TWIST_MAX_TILT
}

/// Disegna la racchetta `s` con i colori `look`; `u` è il pixel "arcade" (schermo a 240 righe).
pub fn draw_paddle(r: &Renderer, s: &Shape, u: f32, look: Look) {
    let (x, sy, w, h, f) = (s.x, r.screen_y(s.y), s.w, s.h, s.front);
    // rettangolo lungo `len` verso il retro, a partire da `back` dietro il centro (negativo: davanti)
    let behind = |back: f32, len: f32, dy: f32, hh: f32, color: Color| {
        let x0 = if f > 0.0 { x - back - len } else { x + back };
        draw_rectangle(x0, sy + dy - hh / 2.0, len, hh, color);
    };
    match s.kind {
        Some(PaddleKind::Twist) => {
            // la rotazione dello schermo è oraria: per il giocatore sinistro la faccia (a destra)
            // va verso l'alto girando in senso antiorario
            draw_rectangle_ex(
                x,
                sy,
                w,
                h,
                DrawRectangleParams {
                    offset: vec2(0.5, 0.5),
                    rotation: -s.tilt * f,
                    color: look.body,
                },
            );
        }
        Some(PaddleKind::Hammer) => {
            // più spessa, verso il retro (la faccia resta dove colpisce), con le bande del peso
            let thick = w * 1.5;
            behind(-w / 2.0, thick, 0.0, h, look.body);
            for dy in [-h * 0.22, h * 0.22] {
                behind(-w / 2.0, thick, dy, h / 16.0, look.detail);
            }
        }
        Some(PaddleKind::Blaster) => {
            // spigoli del davanti smussati in alto e in basso, due canne accanto al centro
            let cut = w / 2.0;
            let (top, bottom) = (sy - h / 2.0, sy + h / 2.0);
            behind(cut - w / 2.0, w - cut, 0.0, h, look.body);
            let fx = x + f * (w / 2.0 - cut); // inizio della parte smussata
            let face = x + f * w / 2.0;
            let (lo, hi) = (fx.min(face), fx.max(face));
            draw_rectangle(lo, top + cut, hi - lo, h - 2.0 * cut, look.body);
            draw_triangle(vec2(fx, top), vec2(fx, top + cut), vec2(face, top + cut), look.body);
            draw_triangle(
                vec2(fx, bottom),
                vec2(fx, bottom - cut),
                vec2(face, bottom - cut),
                look.body,
            );
            for dy in [-h / 16.0, h / 16.0] {
                let len = w / 2.0;
                let x0 = if f > 0.0 { face } else { face - len };
                draw_rectangle(x0, sy + dy - h / 32.0, len, h / 16.0, look.detail);
            }
        }
        _ => draw_rectangle(x - w / 2.0, sy - h / 2.0, w, h, look.body),
    }
    match s.kind {
        Some(PaddleKind::Titan) => {
            // estremità gialle sul retro: un terzo della larghezza, un ottavo dell'altezza
            for dy in [-h / 2.0 + h / 16.0, h / 2.0 - h / 16.0] {
                behind(w / 2.0 - w / 3.0, w / 3.0, dy, h / 8.0, look.mark);
            }
        }
        Some(PaddleKind::Rush) => {
            // immagini gialle della racchetta lungo lo scatto in avanti, più chiare verso la
            // partenza (nella scelta sempre: è il suo segno)
            let dash = s.dash.or(s.preview.then_some((x - f * w * 8.0, 1.0)));
            if let Some((from, fade)) = dash {
                for k in 1..=3 {
                    let gx = from + (x - from) * k as f32 / 4.0;
                    let color = Color {
                        a: look.mark.a * fade * 0.18 * k as f32,
                        ..look.mark
                    };
                    draw_rectangle(gx - w / 2.0, sy - h / 2.0, w, h, color);
                }
            }
        }
        Some(PaddleKind::Guardian) if s.preview => {
            let mut dy = -h * 0.75;
            while dy < h * 0.75 {
                behind(w * 1.7, 2.0 * u, dy + 2.5 * u, 5.0 * u, look.mark);
                dy += 8.0 * u;
            }
        }
        _ => {}
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
    };
    let colors = &app.cfg.colors;
    let look = Look {
        body: App::color(colors.white),
        mark: App::color(colors.accent),
        detail: App::color(colors.lgray),
    };
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
            cpu: app.cpu,
            fixed: app.cpu.then_some(1),
            duel: None,
            cursor: [0; 2],
            chosen: [false; 2],
            left: PICK_SECONDS,
            ready: None,
            knobs_ready: false,
        };
        if app.run.is_some() {
            // CHALLENGE: la CPU cambia racchetta a ogni livello, qui si vede quella del primo
            pick.cursor[1] = paddws_core::challenge::RUNGS[0].kind as usize;
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


    /// Gamepad come i tasti del lato (`input`): su e giù spostano il cursore, A sceglie la racchetta (o annulla la scelta), B torna al
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

    /// Per la verifica automatica: P1 sul BLASTER, P2 ha già scelto il GUARDIAN.
    pub fn demo(&mut self) {
        self.cpu = false;
        self.fixed = None;
        self.cursor = [PaddleKind::Blaster as usize, PaddleKind::Guardian as usize];
        self.chosen = [false, true];
    }

    /// y del centro della riga `i` e altezza delle righe (coordinate di disegno).
    fn row(app: &App, i: usize) -> (f32, f32) {
        let s = app.scale();
        let rows = PaddleKind::COUNT as f32;
        let row_h = ((app.renderer.world_h - 165.0 * s - 75.0 * s) / rows).min(50.0 * s);
        (165.0 * s + (i as f32 + 0.5) * row_h, row_h)
    }

    fn toggle(&mut self, app: &App, side: usize) {
        self.chosen[side] = !self.chosen[side];
        app.play(if self.chosen[side] { Event::Hit } else { Event::Wall });
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
                let cur = &mut self.cursor[side];
                if input::pressed(up) {
                    *cur = (*cur + n - 1) % n;
                }
                if input::pressed(down) {
                    *cur = (*cur + 1) % n;
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
        // touch: un tocco su una riga della propria colonna mostra quella racchetta, un altro tocco
        // sulla stessa riga la sceglie (o la lascia)
        for p in touch::taps() {
            let side = usize::from(p.x >= app.renderer.world_w / 2.0);
            if self.fixed == Some(side) {
                continue;
            }
            if let Some(i) = (0..n).find(|&i| {
                let (cy, row_h) = Self::row(app, i);
                (p.y - cy).abs() < row_h / 2.0
            }) {
                if i == self.cursor[side] {
                    self.toggle(app, side);
                } else {
                    self.cursor[side] = i;
                    self.chosen[side] = false;
                }
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
        let (w, h) = (r.world_w, r.world_h);
        let s = app.scale();
        let u = unit(app);
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        let dim = Color { a: 0.35, ..gray };
        let font = &app.assets.font_text;
        let p = &app.params;
        r.fill(BLACK);
        r.text_centered("PICK YOUR PADDLE", font, 34.0 * s, w / 2.0, 34.0 * s, 0.0, accent);
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

        let half = w / 2.0;
        let (first, _) = Self::row(app, 0);
        let (last, _) = Self::row(app, PaddleKind::COUNT - 1);
        let mid = (first + last) / 2.0;
        for side in 0..2 {
            let x0 = side as f32 * half;
            let front = if side == 0 { 1.0 } else { -1.0 };
            r.text_centered(&self.name(side), font, 30.0 * s, x0 + half * 0.19, 132.0 * s, 0.0, white);
            if self.chosen[side] {
                r.text_centered("OK", font, 30.0 * s, x0 + half * 0.68, 132.0 * s, 0.0, accent);
            }
            // anteprima a grandezza reale della racchetta sotto il cursore
            let sel = PaddleKind::ALL[self.cursor[side]];
            let k = &p.kinds[sel as usize];
            let shape = Shape {
                kind: Some(sel),
                x: x0 + half * 0.19,
                y: h - mid,
                w: to_f32(p.pad_width),
                h: to_f32(k.height),
                front,
                // TWIST si mostra inclinato, come quando sale
                tilt: if sel == PaddleKind::Twist { TWIST_MAX_TILT } else { 0.0 },
                dash: None,
                preview: true,
            };
            draw_paddle(
                r,
                &shape,
                u,
                Look {
                    body: white,
                    mark: accent,
                    detail: gray,
                },
            );

            for (i, &kind) in PaddleKind::ALL.iter().enumerate() {
                let (cy, row_h) = Self::row(app, i);
                let on = i == self.cursor[side];
                if on && !self.chosen[side] && self.ready.is_none() {
                    r.text_centered(">", font, 30.0 * s, x0 + half * 0.36, cy, 0.0, accent);
                }
                // miniatura: la stessa racchetta in piccolo
                let k = &p.kinds[kind as usize];
                let mini = (row_h * 0.8 / to_f32(p.kinds[PaddleKind::Titan as usize].height)).min(0.4);
                let shape = Shape {
                    kind: Some(kind),
                    x: x0 + half * 0.45,
                    y: h - cy,
                    w: (to_f32(p.pad_width) * mini).max(2.0 * u),
                    h: to_f32(k.height) * mini,
                    front,
                    tilt: if kind == PaddleKind::Twist { TWIST_MAX_TILT } else { 0.0 },
                    dash: (kind == PaddleKind::Rush).then_some((x0 + half * 0.45 - front * to_f32(p.pad_width) * mini * 8.0, 1.0)),
                    preview: false,
                };
                let look = if on {
                    Look {
                        body: white,
                        mark: accent,
                        detail: gray,
                    }
                } else {
                    Look {
                        body: gray,
                        mark: dim,
                        detail: dim,
                    }
                };
                draw_paddle(r, &shape, u, look);
                let color = match (on, self.chosen[side]) {
                    (true, true) => accent,
                    (true, false) => white,
                    _ => gray,
                };
                r.text_centered(kind.name(), font, 30.0 * s, x0 + half * 0.7, cy, 0.0, color);
            }
            r.text_centered(tagline(sel), font, 22.0 * s, x0 + half / 2.0, h - 50.0 * s, 0.0, gray);
        }
        if self.ready.is_some() && (get_time() * 6.0) as i64 % 2 == 0 {
            r.text_centered("READY!", font, 40.0 * s, w / 2.0, h - 18.0 * s, 0.0, accent);
        } else if self.ready.is_none() && app.touch {
            for side in 0..2 {
                if self.fixed != Some(side) && !self.chosen[side] {
                    let x = if side == 0 { w / 4.0 } else { 3.0 * w / 4.0 };
                    r.text_centered("TAP AGAIN TO CHOOSE", font, 20.0 * s, x, h - 16.0 * s, 0.0, gray);
                }
            }
        } else if self.ready.is_none() {
            if self.fixed != Some(0) {
                r.text_centered("W S + C", font, 20.0 * s, w / 4.0, h - 16.0 * s, 0.0, gray);
            }
            if self.fixed != Some(1) {
                r.text_centered("UP DOWN + -", font, 20.0 * s, 3.0 * w / 4.0, h - 16.0 * s, 0.0, gray);
            }
        }
    }
}
