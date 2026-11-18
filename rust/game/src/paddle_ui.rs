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
use crate::render::{ArtPart, Renderer};
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
            };
            draw_paddle(r, &shape, u, Look { body: white, mark: accent, detail: gray });
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
            draw_rectangle(x, cell.y + cell.h - 10.0 * u, tag_w, 9.0 * u, BLACK);
            r.text_centered(&tag, font, t1, x + tag_w / 2.0, cell.y + cell.h - 5.5 * u, 0.0, accent);
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
                    (false, 0) => "W S + C",
                    (false, _) => "UP DOWN + -",
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
