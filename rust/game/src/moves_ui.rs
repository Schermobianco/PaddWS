//! Presentazione delle mosse speciali di NEXT ("HOW TO PLAY", come nei giochi Neo Geo), prima
//! della partita quando l'opzione è accesa: per ogni mossa il nome, che cosa fa, il comando
//! disegnato per il controllo in uso (joystick, spinner del cabinato, mouse, tastiera o touch)
//! che si accende passo dopo passo, e nel riquadro a destra la palla che parte con l'effetto della
//! mossa. Sotto, il costo (mezza barra la mossa, la barra piena la MAX) e i comandi dei bonus. In
//! CHALLENGE compare prima del primo incontro e prima della sfida di un nuovo sfidante.
//!
//! Pixel art pensata a 320x240, il pixel arcade di `unit`, centrata nel campo. Solo disegno: i
//! gesti sono quelli di `gesture` (e della mezzaluna del MiSTer per il joystick), la logica delle
//! mosse è nel core.

use macroquad::prelude::*;
use paddws_core::{MAX_SPECIAL_LEVEL, Special};

use crate::challenge_ui::Intro;
use crate::gesture::Dir;
use crate::input;
use crate::next_ui::{draw_meter, unit};
use crate::render::{GameFont, Renderer};
use crate::scenes::{App, Menu, Play, START_KEYS, Scene};
use crate::touch;

/// Durata della presentazione (s) e tempo prima che si possa saltare (non la si salta per sbaglio
/// con il tasto che ha confermato la racchetta).
const HOWTO_SECONDS: f64 = 8.0;
const SKIP_AFTER: f64 = 0.3;
/// Animazione: durata di ogni passo del comando, poi la palla avanza di `SHOT_PIXELS` ogni
/// `SHOT_STEP` per `SHOT_STEPS` volte, poi una pausa con tutto spento; e si ricomincia.
const STEP: f64 = 0.22;
const SHOT_STEP: f64 = 0.11;
const SHOT_STEPS: f64 = 6.0;
const SHOT_PIXELS: f64 = 18.0;
const IDLE: f64 = 0.88;

/// Schermo arcade.
const W: i32 = 320;

/// Colori fissi della pixel art (gli altri vengono dalla configurazione).
const DARK: Color = rgb(55, 55, 60);
const FRAME: Color = rgb(70, 70, 70);
const HOLE: Color = rgb(25, 25, 25);
const RED: Color = rgb(230, 40, 40);
const RED_DARK: Color = rgb(140, 20, 20);
const RED_LIGHT: Color = rgb(255, 110, 110);
const SKIN: Color = rgb(240, 190, 150);
const SKIN_DARK: Color = rgb(190, 135, 100);
const SKIN_LIGHT: Color = rgb(255, 235, 220);
const CAP: Color = rgb(200, 200, 205);
const CAP_EDGE: Color = rgb(120, 120, 125);

const fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color::new(r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0, 1.0)
}

/// Controllo con cui gioca il giocatore di sinistra: decide come si disegnano i comandi.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Device {
    /// joystick con i pulsanti A, B, C: gamepad e stick arcade (`gamepad`), come sul MiSTer
    Joystick,
    /// encoder del cabinato
    Spinner,
    /// mouse come spinner
    Mouse,
    Keyboard,
    Touch,
}

impl Device {
    /// Il controllo usato per ultimo: un gamepad, altrimenti touch, mouse, spinner o tastiera.
    fn of(app: &App) -> Self {
        if app.pad_used {
            Device::Joystick
        } else if app.touch {
            Device::Touch
        } else if app.mouse_spinner() {
            Device::Mouse
        } else if app.encoders.is_some() {
            Device::Spinner
        } else {
            Device::Keyboard
        }
    }

    fn name(self) -> &'static str {
        match self {
            Device::Joystick => "JOYSTICK",
            Device::Spinner => "SPINNER",
            Device::Mouse => "MOUSE",
            Device::Keyboard => "KEYBOARD",
            Device::Touch => "TOUCH",
        }
    }

    /// Scritta per saltare la presentazione.
    fn skip(self) -> &'static str {
        match self {
            Device::Joystick | Device::Keyboard => "PRESS START TO SKIP",
            Device::Spinner | Device::Mouse => "CLICK TO SKIP",
            Device::Touch => "TAP TO SKIP",
        }
    }
}

/// Pulsante del mouse.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Button {
    Left,
    Right,
    Middle,
}

/// Scritta di un tasto della tastiera: lettera o freccia (dx, dy).
#[derive(Clone, Copy)]
enum Cap {
    Text(&'static str),
    Arrow(i32, i32),
}

/// Un passo del comando disegnato.
#[derive(Clone, Copy)]
enum Step {
    /// joystick inclinato verso (dx, dy), con dx = 1 verso l'avversario
    Stick(i32, i32),
    /// manopola girata in un verso
    Spin(Dir),
    /// mouse spostato in un verso
    Slide(Dir),
    /// dito che scorre in un verso
    Swipe(Dir),
    Key(Cap),
    /// pulsante arcade rosso
    Arcade(&'static str),
    Click(Button),
    /// tocco di un secondo dito
    Tap,
}

/// Simbolo della legenda dei comandi.
#[derive(Clone, Copy)]
enum Icon {
    Arcade(&'static str),
    Key(Cap),
    /// tasti del giocatore 1 e del giocatore 2
    Keys(Cap, Cap),
    Mouse(Button),
    Tap,
    /// capsula della riserva
    Capsule,
}

/// Tasti dei due giocatori: (su, giù, scatto, seleziona, usa), come in `scenes::CONTROLS` e
/// `next_ui::BONUS_KEYS`.
const KEYS: [[Cap; 5]; 2] = [
    [
        Cap::Text("W"),
        Cap::Text("S"),
        Cap::Text("D"),
        Cap::Text("F"),
        Cap::Text("C"),
    ],
    [
        Cap::Arrow(0, -1),
        Cap::Arrow(0, 1),
        Cap::Arrow(-1, 0),
        Cap::Text("."),
        Cap::Text("-"),
    ],
];

/// Direzioni del gesto della mossa (vedi `gesture`).
fn dirs(special: Special) -> [Dir; 2] {
    match special {
        Special::Straight => [Dir::Down, Dir::Up],
        Special::Rise => [Dir::Up, Dir::Down],
    }
}

/// Passi del comando della mossa per il controllo e il giocatore (0 o 1), scatto compreso.
fn steps(device: Device, special: Special, player: usize) -> Vec<Step> {
    let [d1, d2] = dirs(special);
    let key = |d: Dir| Step::Key(KEYS[player][if d == Dir::Up { 0 } else { 1 }]);
    match device {
        // la mezzaluna del MiSTer (`pong_top.v`)
        Device::Joystick => match special {
            Special::Straight => vec![
                Step::Stick(0, 1),
                Step::Stick(1, 1),
                Step::Stick(1, 0),
                Step::Arcade("A"),
            ],
            Special::Rise => vec![
                Step::Stick(1, 0),
                Step::Stick(0, 1),
                Step::Stick(1, 1),
                Step::Arcade("A"),
            ],
        },
        Device::Spinner => vec![Step::Spin(d1), Step::Spin(d2), Step::Arcade("A")],
        Device::Mouse => vec![Step::Slide(d1), Step::Slide(d2), Step::Click(Button::Left)],
        Device::Keyboard => vec![key(d1), key(d2), Step::Key(KEYS[player][2])],
        Device::Touch => vec![Step::Swipe(d1), Step::Swipe(d2), Step::Tap],
    }
}

/// Legenda dei comandi: scatto e bonus.
fn legend(device: Device, two_players: bool) -> Vec<(Icon, &'static str)> {
    let key = |i: usize| {
        if two_players {
            Icon::Keys(KEYS[0][i], KEYS[1][i])
        } else {
            Icon::Key(KEYS[0][i])
        }
    };
    match device {
        Device::Joystick => vec![
            (Icon::Arcade("A"), "DASH"),
            (Icon::Arcade("B"), "SELECT"),
            (Icon::Arcade("C"), "USE"),
        ],
        Device::Spinner => vec![
            (Icon::Arcade("A"), "CLICK = DASH"),
            (Icon::Arcade("B"), "SELECT"),
            (Icon::Arcade("C"), "USE"),
        ],
        Device::Mouse => vec![
            (Icon::Mouse(Button::Left), "DASH"),
            (Icon::Mouse(Button::Right), "SELECT"),
            (Icon::Mouse(Button::Middle), "USE"),
        ],
        Device::Keyboard => vec![(key(2), "DASH"), (key(3), "SELECT"), (key(4), "USE")],
        Device::Touch => vec![(Icon::Tap, "2ND FINGER = DASH"), (Icon::Capsule, "TAP A BONUS = USE")],
    }
}

/// Frase sotto il nome: che cosa fa la mossa.
fn effect(special: Special) -> &'static str {
    match special {
        Special::Straight => "NEXT SHOT FLAT AND FAST",
        Special::Rise => "FLAT SHOT WITH A LATE BREAK",
    }
}

/// Punto dell'animazione: il passo acceso (`n` = lo scatto) e da quanto è partita la palla.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Phase {
    step: Option<usize>,
    /// i passi prima di questo hanno la freccia accesa
    done: usize,
    shot: Option<f64>,
}

impl Phase {
    /// Al tempo `t` per un comando di `n` passi più lo scatto: un passo ogni `STEP`, poi la palla,
    /// poi la pausa.
    fn at(t: f64, n: usize) -> Self {
        let press = n as f64 * STEP;
        let flight = press + STEP + SHOT_STEP * SHOT_STEPS;
        let a = t.rem_euclid(flight + IDLE);
        if a >= flight {
            return Self {
                step: None,
                done: 0,
                shot: None,
            };
        }
        let step = ((a / STEP) as usize).min(n + 1);
        Self {
            step: (step <= n).then_some(step),
            done: step,
            shot: (a >= press).then_some(a - press),
        }
    }
}

/// Pennello della pixel art: coordinate dello schermo 320x240 (interi, un pixel arcade ciascuno)
/// portate nel campo, con lo schermo centrato in orizzontale.
struct Px<'a> {
    r: &'a Renderer,
    font: &'a GameFont,
    ox: f32,
    u: f32,
}

/// Allineamento orizzontale di un testo.
#[derive(Clone, Copy)]
enum Align {
    Left,
    Center,
    Right,
}

impl Px<'_> {
    /// Rettangolo pieno, estremi compresi.
    fn rect(&self, x0: i32, y0: i32, x1: i32, y1: i32, c: Color) {
        let u = self.u;
        draw_rectangle(
            self.ox + x0 as f32 * u,
            y0 as f32 * u,
            (x1 - x0 + 1) as f32 * u,
            (y1 - y0 + 1) as f32 * u,
            c,
        );
    }

    fn point(&self, x: i32, y: i32, c: Color) {
        self.rect(x, y, x, y, c);
    }

    /// Bordo di un pixel di un rettangolo, estremi compresi.
    fn frame(&self, x0: i32, y0: i32, x1: i32, y1: i32, c: Color) {
        self.rect(x0, y0, x1, y0, c);
        self.rect(x0, y1, x1, y1, c);
        self.rect(x0, y0, x0, y1, c);
        self.rect(x1, y0, x1, y1, c);
    }

    /// Figura nel riquadro (x0, y0, x1, y1): i pixel per cui `inside` è vero, pieni di `fill` e
    /// con il bordo (quelli con un vicino fuori) di `edge`.
    fn shape(
        &self,
        (x0, y0, x1, y1): (i32, i32, i32, i32),
        inside: impl Fn(i32, i32) -> bool,
        fill: Option<Color>,
        edge: Option<Color>,
    ) {
        for y in y0..=y1 {
            let mut x = x0;
            while x <= x1 {
                if !inside(x, y) {
                    x += 1;
                    continue;
                }
                // righe di pixel interni in un rettangolo solo
                let start = x;
                while x <= x1 && inside(x, y) {
                    x += 1;
                }
                if let Some(c) = fill {
                    self.rect(start, y, x - 1, y, c);
                }
                if let Some(c) = edge {
                    for e in start..x {
                        let border = !inside(e - 1, y) || !inside(e + 1, y) || !inside(e, y - 1) || !inside(e, y + 1);
                        if border {
                            self.point(e, y, c);
                        }
                    }
                }
            }
        }
    }

    /// Ellisse inscritta nel riquadro, estremi compresi (come `ImageDraw.ellipse`).
    fn ellipse(&self, x0: i32, y0: i32, x1: i32, y1: i32, fill: Option<Color>, edge: Option<Color>) {
        let (cx, cy) = ((x0 + x1 + 1) as f32 / 2.0, (y0 + y1 + 1) as f32 / 2.0);
        let (rx, ry) = ((x1 - x0 + 1) as f32 / 2.0, (y1 - y0 + 1) as f32 / 2.0);
        let inside = |x: i32, y: i32| {
            let (dx, dy) = ((x as f32 + 0.5 - cx) / rx, (y as f32 + 0.5 - cy) / ry);
            dx * dx + dy * dy <= 1.0
        };
        self.shape((x0, y0, x1, y1), inside, fill, edge);
    }

    /// Rettangolo con gli angoli arrotondati di raggio `rad`, estremi compresi.
    fn rounded(&self, (x0, y0, x1, y1): (i32, i32, i32, i32), rad: i32, fill: Option<Color>, edge: Option<Color>) {
        self.shape(
            (x0, y0, x1, y1),
            |x, y| in_rounded(x, y, (x0, y0, x1, y1), rad),
            fill,
            edge,
        );
    }

    /// Segmento di un pixel (Bresenham).
    fn line(&self, (x0, y0): (i32, i32), (x1, y1): (i32, i32), c: Color) {
        let (dx, dy) = ((x1 - x0).abs(), -(y1 - y0).abs());
        let (sx, sy) = ((x1 - x0).signum(), (y1 - y0).signum());
        let (mut x, mut y, mut err) = (x0, y0, dx + dy);
        loop {
            self.point(x, y, c);
            if x == x1 && y == y1 {
                break;
            }
            let e2 = 2 * err;
            if e2 >= dy {
                err += dy;
                x += sx;
            }
            if e2 <= dx {
                err += dx;
                y += sy;
            }
        }
    }

    /// Triangolo pieno: i pixel con il centro dentro (con un piccolo margine).
    fn triangle(&self, pts: [(f32, f32); 3], c: Color) {
        let area = (pts[1].0 - pts[0].0) * (pts[2].1 - pts[0].1) - (pts[2].0 - pts[0].0) * (pts[1].1 - pts[0].1);
        let sign = area.signum();
        let inside = |x: i32, y: i32| {
            let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
            (0..3).all(|i| {
                let (a, b) = (pts[i], pts[(i + 1) % 3]);
                let len = ((b.0 - a.0).powi(2) + (b.1 - a.1).powi(2)).sqrt().max(1e-3);
                sign * ((b.0 - a.0) * (py - a.1) - (b.1 - a.1) * (px - a.0)) / len >= -0.4
            })
        };
        let xs = pts.map(|p| p.0);
        let ys = pts.map(|p| p.1);
        let bounds = (
            xs.iter().copied().fold(f32::MAX, f32::min).floor() as i32 - 1,
            ys.iter().copied().fold(f32::MAX, f32::min).floor() as i32 - 1,
            xs.iter().copied().fold(f32::MIN, f32::max).ceil() as i32 + 1,
            ys.iter().copied().fold(f32::MIN, f32::max).ceil() as i32 + 1,
        );
        self.shape(bounds, inside, Some(c), None);
    }

    /// Arco di cerchio largo `width` pixel nel riquadro quadrato centrato in (cx, cy) di raggio
    /// `rad`, da `from` a `to` gradi (in senso orario dalle tre, come `ImageDraw.arc`).
    fn arc(&self, (cx, cy): (i32, i32), rad: i32, (from, to): (f32, f32), width: i32, c: Color) {
        let (fx, fy) = (cx as f32 + 0.5, cy as f32 + 0.5);
        let (outer, inner) = (rad as f32 + 0.5, (rad - width) as f32 + 0.5);
        let inside = |x: i32, y: i32| {
            let (dx, dy) = (x as f32 + 0.5 - fx, y as f32 + 0.5 - fy);
            let d = (dx * dx + dy * dy).sqrt();
            let deg = dy.atan2(dx).to_degrees();
            d <= outer && d > inner && deg >= from && deg <= to
        };
        self.shape((cx - rad, cy - rad, cx + rad, cy + rad), inside, Some(c), None);
    }

    /// Testo della Munro alto `size` pixel arcade (10 o 20), centrato in verticale su `cy`.
    fn text(&self, text: &str, size: f32, x: i32, cy: f32, align: Align, c: Color) {
        let size = size * self.u;
        let w = self.r.text_width(text, self.font, size);
        let x = self.ox + x as f32 * self.u;
        let cx = match align {
            Align::Left => x + w / 2.0,
            Align::Center => x,
            Align::Right => x - w / 2.0,
        };
        self.r.text_centered(text, self.font, size, cx, cy * self.u, 0.0, c);
    }

    /// Larghezza di un testo della Munro in pixel arcade.
    fn text_width(&self, text: &str, size: f32) -> i32 {
        (self.r.text_width(text, self.font, size * self.u) / self.u).round() as i32
    }
}

/// Il pixel (x, y) sta nel rettangolo con gli angoli arrotondati di raggio `rad`.
fn in_rounded(x: i32, y: i32, (x0, y0, x1, y1): (i32, i32, i32, i32), rad: i32) -> bool {
    if x < x0 || x > x1 || y < y0 || y > y1 {
        return false;
    }
    let dx = (x0 + rad - x).max(x - (x1 - rad)).max(0);
    let dy = (y0 + rad - y).max(y - (y1 - rad)).max(0);
    if dx == 0 || dy == 0 {
        return true;
    }
    let (fx, fy) = (dx as f32 - 0.5, dy as f32 - 0.5);
    fx * fx + fy * fy <= (rad as f32) * (rad as f32)
}

/// Colori della configurazione.
#[derive(Clone, Copy)]
struct Ink {
    white: Color,
    gray: Color,
    accent: Color,
}

/// Joystick arcade di tre quarti: base, asta e pallina rossa inclinate verso (dx, dy).
fn stick(px: &Px, (cx, cy): (i32, i32), (dx, dy): (i32, i32), lit: bool, ink: Ink) {
    let base = cy + 9;
    px.rounded(
        (cx - 11, base - 2, cx + 11, base + 4),
        2,
        Some(DARK),
        Some(if lit { ink.accent } else { rgb(90, 90, 95) }),
    );
    px.ellipse(cx - 5, base - 3, cx + 5, base + 1, Some(HOLE), None);
    let (bx, by) = (cx + dx * 7, cy - 6 + dy * 6);
    // asta larga due pixel
    let shaft = rgb(190, 190, 195);
    px.line((cx, base - 1), (bx, by), shaft);
    px.line((cx + 1, base - 1), (bx + 1, by), shaft);
    px.ellipse(
        bx - 5,
        by - 5,
        bx + 5,
        by + 5,
        Some(if lit { RED } else { RED_DARK }),
        None,
    );
    px.point(bx - 2, by - 3, ink.white);
    px.point(bx - 3, by - 2, ink.white);
}

/// Pulsante arcade rosso di tre quarti: premuto scende e si schiarisce.
fn arcade(px: &Px, (cx, cy): (i32, i32), label: &str, pressed: bool, small: bool, ink: Ink) {
    let r = if small { 7 } else { 9 };
    let base = cy + 5;
    px.ellipse(
        cx - r - 1,
        base - r / 2 - 1,
        cx + r + 1,
        base + r / 2 + 1,
        Some(HOLE),
        None,
    );
    let top = base - 2 - if pressed { 1 } else { 3 };
    // fianco del cilindro: chiuso in basso da un'ellisse (con il solo rettangolo sembrava tagliato)
    px.ellipse(cx - r + 2, base - 1 - r / 2, cx + r - 2, base - 1 + r / 2, Some(RED_DARK), None);
    px.rect(cx - r + 2, top, cx + r - 2, base - 1, RED_DARK);
    px.ellipse(
        cx - r + 2,
        top - r / 2,
        cx + r - 2,
        top + r / 2,
        Some(if pressed { RED_LIGHT } else { RED }),
        pressed.then_some(ink.white),
    );
    px.text(label, 10.0, cx, top as f32 + 0.5, Align::Center, ink.white);
}

/// Freccia di pixel di un tasto, centrata in (cx, cy), verso (dx, dy).
fn cap_arrow(px: &Px, (cx, cy): (i32, i32), (dx, dy): (i32, i32), c: Color) {
    // punta, due righe che si allargano e l'asta
    for k in 0..3 {
        let (x, y) = (cx + dx * (2 - k), cy + dy * (2 - k));
        if dx == 0 {
            px.rect(x - k, y, x + k, y, c);
        } else {
            px.rect(x, y - k, x, y + k, c);
        }
    }
    for k in 1..4 {
        px.point(cx - dx * k, cy - dy * k, c);
    }
}

/// Tasto della tastiera: cappuccio grigio con il bordo in rilievo, giallo e un pixel più giù
/// quando è premuto.
fn key(px: &Px, (cx, cy): (i32, i32), cap: Cap, pressed: bool, ink: Ink) {
    let off = i32::from(pressed);
    px.rect(cx - 8, cy - 6, cx + 8, cy + 9, rgb(40, 40, 45));
    px.rect(
        cx - 8,
        cy - 7 + off,
        cx + 8,
        cy + 6 + off,
        if pressed { ink.accent } else { CAP },
    );
    px.frame(cx - 8, cy - 7 + off, cx + 8, cy + 6 + off, CAP_EDGE);
    px.rect(cx - 7, cy - 6 + off, cx + 7, cy - 6 + off, ink.white);
    match cap {
        Cap::Text(t) => px.text(t, 10.0, cx, (cy + off) as f32 + 0.5, Align::Center, BLACK),
        Cap::Arrow(dx, dy) => cap_arrow(px, (cx, cy + off), (dx, dy), BLACK),
    }
}

/// Manopola dello spinner vista dall'alto, con la freccia curva della rotazione: giù = senso
/// orario sul lato destro (la manopola del giocatore di sinistra), su = antiorario.
fn spinner(px: &Px, (cx, cy): (i32, i32), dir: Dir, lit: bool, ink: Ink) {
    px.ellipse(
        cx - 9,
        cy - 9,
        cx + 9,
        cy + 9,
        Some(rgb(30, 30, 35)),
        Some(rgb(110, 110, 115)),
    );
    px.ellipse(cx - 6, cy - 6, cx + 6, cy + 6, Some(rgb(80, 80, 88)), None);
    let sgn = if dir == Dir::Down { 1 } else { -1 };
    let ang = (60.0 * sgn as f32).to_radians();
    let tip = (
        cx + (5.0 * ang.sin()).round() as i32,
        cy - (5.0 * ang.cos()).round() as i32,
    );
    px.line((cx, cy), tip, ink.white);
    let c = if lit { ink.accent } else { ink.gray };
    px.arc((cx, cy), 13, (-50.0, 50.0), 2, c);
    let ty = (cy + 10 * sgn) as f32;
    let s = sgn as f32;
    let x = cx as f32;
    px.triangle(
        [(x + 6.0, ty + 3.0 * s), (x + 12.0, ty - s), (x + 13.0, ty + 6.0 * s)],
        c,
    );
}

/// Freccia verticale del movimento (dito o mouse), con le righe della scia.
fn motion(px: &Px, (cx, cy): (i32, i32), sgn: i32, c: Color) {
    for k in 0..3 {
        let y = cy - sgn * (9 - 3 * k);
        px.rect(cx - 2 + k, y, cx + 2 - k, y, c);
    }
    px.line((cx, cy - sgn * 10), (cx, cy + sgn * 6), c);
    let (x, y, s) = (cx as f32 + 0.5, cy as f32 + 0.5, sgn as f32);
    px.triangle([(x - 4.0, y + 5.0 * s), (x + 4.0, y + 5.0 * s), (x, y + 10.0 * s)], c);
}

/// Dito che scorre in su o in giù: la freccia della corsa e il polpastrello.
fn finger(px: &Px, (cx, cy): (i32, i32), dir: Dir, lit: bool, ink: Ink) {
    let sgn = if dir == Dir::Down { 1 } else { -1 };
    motion(px, (cx, cy), sgn, if lit { ink.accent } else { ink.gray });
    let fy = cy - sgn * 2;
    px.ellipse(cx + 5, fy - 6, cx + 15, fy + 6, Some(SKIN), Some(SKIN_DARK));
    px.ellipse(cx + 8, fy - 4, cx + 12, fy - 1, Some(SKIN_LIGHT), None);
}

/// Tocco di un dito: polpastrello, con le onde del tocco quando tocca.
fn tap(px: &Px, (cx, cy): (i32, i32), pressed: bool, ink: Ink) {
    if pressed {
        px.ellipse(cx - 11, cy - 11, cx + 11, cy + 11, None, Some(ink.accent));
        px.ellipse(cx - 8, cy - 8, cx + 8, cy + 8, None, Some(ink.accent));
    }
    px.ellipse(cx - 5, cy - 6, cx + 5, cy + 6, Some(SKIN), Some(SKIN_DARK));
    px.ellipse(cx - 2, cy - 4, cx + 2, cy - 1, Some(SKIN_LIGHT), None);
}

/// Mouse visto dall'alto, con il pulsante `button` evidenziato: grigio scuro o, se `lit`, acceso.
fn mouse(px: &Px, (cx, cy): (i32, i32), button: Option<Button>, lit: bool, ink: Ink) {
    let body = (cx - 5, cy - 7, cx + 5, cy + 7);
    px.rounded(body, 4, Some(CAP), Some(CAP_EDGE));
    let split = cy - 2;
    if let Some(b) = button {
        let c = if lit { ink.accent } else { rgb(110, 110, 115) };
        match b {
            Button::Left | Button::Right => {
                let left = b == Button::Left;
                let inside = |x: i32, y: i32| {
                    let half = if left { x < cx } else { x > cx };
                    half && y < split && in_rounded(x, y, (body.0 + 1, body.1 + 1, body.2 - 1, body.3 - 1), 3)
                };
                px.shape((body.0, body.1, body.2, split), inside, Some(c), None);
            }
            Button::Middle => px.rect(cx - 1, cy - 6, cx + 1, cy - 3, c),
        }
    }
    px.rect(body.0 + 1, split, body.2 - 1, split, CAP_EDGE);
    if button != Some(Button::Middle) {
        px.rect(cx, body.1 + 1, cx, split - 1, CAP_EDGE);
        // rotella
        px.rect(cx, cy - 6, cx, cy - 4, rgb(60, 60, 65));
    }
}

/// Mouse spostato in su o in giù: la freccia della corsa e il mouse.
fn slide(px: &Px, (cx, cy): (i32, i32), dir: Dir, lit: bool, ink: Ink) {
    let sgn = if dir == Dir::Down { 1 } else { -1 };
    motion(px, (cx, cy), sgn, if lit { ink.accent } else { ink.gray });
    mouse(px, (cx + 11, cy - sgn), None, false, ink);
}

/// Un passo del comando centrato in (x, y); `lit` mentre l'animazione lo esegue.
fn draw_step(px: &Px, step: Step, at: (i32, i32), lit: bool, ink: Ink) {
    let (x, y) = at;
    match step {
        Step::Stick(dx, dy) => stick(px, at, (dx, dy), lit, ink),
        Step::Spin(dir) => spinner(px, at, dir, lit, ink),
        // freccia e figura insieme sono più larghe: si spostano a sinistra
        Step::Slide(dir) => slide(px, (x - 5, y), dir, lit, ink),
        Step::Swipe(dir) => finger(px, (x - 4, y), dir, lit, ink),
        Step::Key(cap) => key(px, at, cap, lit, ink),
        Step::Arcade(label) => arcade(px, at, label, lit, false, ink),
        Step::Click(button) => mouse(px, at, Some(button), lit, ink),
        Step::Tap => tap(px, at, lit, ink),
    }
}

/// Freccetta tra due passi.
fn step_arrow(px: &Px, (x, y): (i32, i32), c: Color) {
    let (fx, fy) = (x as f32, y as f32 + 0.5);
    px.triangle([(fx, fy - 3.0), (fx + 4.0, fy), (fx, fy + 3.0)], c);
}

/// Comando di una mossa a partire da `x0` sulla riga `cy`: i passi a `pitch` pixel l'uno
/// dall'altro con le freccette, "+", lo scatto e la scritta `label` (se c'è).
fn draw_command(
    px: &Px,
    steps: &[Step],
    (x0, cy): (i32, i32),
    pitch: i32,
    label: Option<&str>,
    phase: Phase,
    ink: Ink,
) {
    let (moves, dash) = steps.split_at(steps.len() - 1);
    let mut x = x0;
    for (i, &step) in moves.iter().enumerate() {
        draw_step(px, step, (x, cy), phase.step == Some(i), ink);
        if i + 1 < moves.len() {
            let c = if phase.done > i { ink.accent } else { ink.gray };
            step_arrow(px, (x + pitch / 2 - 2, cy), c);
        }
        x += pitch;
    }
    let last = x - pitch;
    let (plus, fin) = if pitch >= 30 { (28, 48) } else { (15, 30) };
    px.text("+", 20.0, last + plus, cy as f32 - 0.5, Align::Center, ink.white);
    draw_step(px, dash[0], (last + fin, cy), phase.step == Some(moves.len()), ink);
    if let Some(label) = label {
        px.text(label, 10.0, last + fin + 16, cy as f32 + 1.5, Align::Left, ink.gray);
    }
}

/// Riquadro del tiro a destra della riga `cy`: la racchetta e la palla che parte dritta
/// (STRAIGHT SHOT, con la scia) o che dopo un tratto s'impenna (RISING STRIKE).
fn draw_shot(px: &Px, special: Special, cy: i32, phase: Phase, ink: Ink) {
    let (bx, by) = (206, cy - 2);
    let right = W - 18;
    px.frame(bx - 2, by - 16, right, by + 14, FRAME);
    px.rect(bx + 2, by - 6, bx + 4, by + 6, ink.white);
    let Some(t) = phase.shot else { return };
    let k = 8 + (t / SHOT_STEP * SHOT_PIXELS) as i32;
    let x = bx + 6 + k;
    if x + 2 >= right - 1 {
        return;
    }
    match special {
        Special::Straight => {
            if k > 10 {
                for dy in [-2, 0, 2] {
                    px.rect(bx + 6, by + dy, x - 4, by + dy, ink.accent);
                }
            }
            px.rect(x, by - 1, x + 2, by + 1, ink.accent);
        }
        Special::Rise => {
            // dritta fino a metà riquadro, poi a 45° fin quasi al bordo alto
            let turn = bx + 50;
            let y = (by - (x - turn).max(0)).max(by - 14);
            let trail = Color { a: 0.45, ..ink.accent };
            for i in 1..4 {
                let tx = x - 4 * i;
                if tx > bx + 6 {
                    let ty = (by - (tx - turn).max(0)).max(by - 14);
                    px.point(tx + 1, ty, trail);
                }
            }
            px.rect(x, y - 1, x + 2, y + 1, ink.accent);
        }
    }
}

/// Simbolo della legenda centrato in (x, y); restituisce la larghezza occupata a destra del centro.
fn draw_icon(px: &Px, icon: Icon, (x, y): (i32, i32), ink: Ink) -> i32 {
    match icon {
        Icon::Arcade(label) => {
            arcade(px, (x, y - 3), label, false, true, ink);
            10
        }
        Icon::Key(cap) => {
            key(px, (x, y - 1), cap, false, ink);
            11
        }
        Icon::Keys(p1, p2) => {
            key(px, (x, y - 1), p1, false, ink);
            key(px, (x + 19, y - 1), p2, false, ink);
            30
        }
        Icon::Mouse(button) => {
            mouse(px, (x, y), Some(button), true, ink);
            9
        }
        Icon::Tap => {
            tap(px, (x, y), false, ink);
            9
        }
        Icon::Capsule => {
            px.rounded((x - 7, y - 7, x + 7, y + 7), 2, Some(BLACK), Some(ink.white));
            px.text("+", 10.0, x, y as f32 + 0.5, Align::Center, ink.white);
            11
        }
    }
}

/// La presentazione.
pub struct HowTo {
    t: f64,
    /// CHALLENGE: prima della sfida tra il campione e un nuovo sfidante
    duel: bool,
    /// controllo da mostrare al posto di quello in uso (giro delle schermate)
    device: Option<Device>,
}

impl HowTo {
    pub fn new(_app: &App) -> Self {
        Self {
            t: 0.0,
            duel: false,
            device: None,
        }
    }

    /// Prima della sfida di un nuovo sfidante in CHALLENGE: i comandi di tutti e due.
    pub fn duel(app: &App) -> Self {
        Self {
            duel: true,
            ..Self::new(app)
        }
    }

    /// Per la verifica automatica: porta la presentazione al tempo `t`.
    pub fn skip_to(&mut self, t: f64) {
        self.t = t;
    }

    /// Per la verifica automatica: mostra i comandi di `device`.
    pub fn show_device(&mut self, device: Device) {
        self.device = Some(device);
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            app.run = None;
            return Some(Scene::Menu(Menu::new(app)));
        }
        self.t += dt;
        let start = input::any_pressed(&START_KEYS)
            || !touch::taps().is_empty()
            || app.knob_clicked();
        if self.t < HOWTO_SECONDS && !(start && self.t >= SKIP_AFTER) {
            return None;
        }
        // CHALLENGE: la sfida o la presentazione del primo avversario; altrimenti la partita
        Some(if self.duel {
            Scene::Game(Box::new(Play::duel(app)))
        } else if app.run.is_some() {
            Scene::Intro(Intro::new(app))
        } else {
            Scene::Game(Box::new(Play::new(app)))
        })
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let u = unit(app);
        let px = Px {
            r,
            font: &app.assets.font_text,
            ox: (r.world_w - W as f32 * u) / 2.0,
            u,
        };
        let colors = &app.cfg.colors;
        let ink = Ink {
            white: App::color(colors.white),
            gray: App::color(colors.lgray),
            accent: App::color(colors.accent),
        };
        r.fill(BLACK);
        let device = self.device.unwrap_or_else(|| Device::of(app));
        // in due sulla tastiera: i tasti di tutti e due
        let two_players = device == Device::Keyboard && (self.duel || (!app.cpu && app.players == 2));
        px.text("HOW TO PLAY", 20.0, W / 2, 12.0, Align::Center, ink.accent);
        px.text(
            &format!("SUPER MOVES - {}", device.name()),
            10.0,
            W / 2,
            28.0,
            Align::Center,
            ink.gray,
        );
        for (row, special) in Special::ALL.into_iter().enumerate() {
            let y0 = 42 + 70 * row as i32;
            px.frame(8, y0 - 4, W - 9, y0 + 62, FRAME);
            px.text(special.name(), 20.0, 16, y0 as f32 + 8.0, Align::Left, ink.accent);
            px.text(effect(special), 10.0, 16, y0 as f32 + 22.5, Align::Left, ink.white);
            let cy = y0 + 44;
            let p1 = steps(device, special, 0);
            let phase = Phase::at(self.t, p1.len() - 1);
            if two_players {
                for (player, x) in [(0, 16), (1, 106)] {
                    px.text(
                        &format!("P{}", player + 1),
                        10.0,
                        x,
                        cy as f32 + 1.5,
                        Align::Left,
                        ink.gray,
                    );
                    draw_command(&px, &steps(device, special, player), (x + 18, cy), 26, None, phase, ink);
                }
            } else {
                let label = if device == Device::Touch { "TAP" } else { "DASH" };
                draw_command(&px, &p1, (30, cy), 34, Some(label), phase, ink);
            }
            draw_shot(&px, special, cy, phase, ink);
        }
        self.draw_costs(app, &px, ink);
        // legenda dei comandi dei bonus
        let (mut x, y) = (22, 208);
        for (icon, label) in legend(device, two_players) {
            let w = draw_icon(&px, icon, (x, y), ink);
            px.text(label, 10.0, x + w + 3, y as f32 + 0.5, Align::Left, ink.gray);
            x += w + 13 + px.text_width(label, 10.0) + 10;
        }
        if (get_time() * 2.0) as i64 % 2 == 0 {
            px.text(device.skip(), 10.0, W / 2, 232.0, Align::Center, ink.gray);
        }
    }

    /// Costo: mezza barra per la mossa, la barra piena (spesa tutta) per la MAX.
    fn draw_costs(&self, app: &App, px: &Px, ink: Ink) {
        let p = &app.params;
        let max = (p.super_meter_max / p.super_cost.max(1)).min(MAX_SPECIAL_LEVEL) >= MAX_SPECIAL_LEVEL;
        let costs: &[(i32, &str, u8, &str)] = if max {
            &[
                (58, "HALF", p.super_cost, "= MOVE"),
                (196, "FULL", p.super_meter_max, "= MAX"),
            ]
        } else {
            &[(127, "COST", p.super_cost, "= MOVE")]
        };
        let y = 186;
        for &(x, name, fill, what) in costs {
            px.text(name, 10.0, x - 6, y as f32 + 3.5, Align::Right, ink.white);
            let u = px.u;
            draw_meter(
                (px.ox + x as f32 * u, y as f32 * u, 38.0 * u, 6.0 * u),
                u,
                fill as f32,
                p.super_meter_max as f32,
                p.super_cost as f32,
                false,
                (true, false),
                (ink.white, ink.gray, ink.accent),
            );
            let c = if fill == p.super_meter_max && max {
                ink.accent
            } else {
                ink.white
            };
            px.text(what, 10.0, x + 42, y as f32 + 3.5, Align::Left, c);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_animation_lights_each_step_then_shoots_then_rests() {
        // due direzioni e lo scatto: un passo ogni STEP
        let at = |t: f64| Phase::at(t, 2);
        assert_eq!(at(0.0).step, Some(0));
        assert_eq!(at(STEP * 1.5).step, Some(1));
        assert_eq!(at(STEP * 1.5).done, 1);
        // lo scatto: la palla parte
        let press = at(STEP * 2.0 + 0.01);
        assert_eq!(press.step, Some(2));
        assert!(press.shot.is_some_and(|s| s < 0.02));
        // in volo: niente acceso, frecce ancora accese, palla in viaggio
        let flying = at(STEP * 3.0 + 0.1);
        assert_eq!((flying.step, flying.done), (None, 3));
        assert!(flying.shot.is_some());
        // pausa, poi da capo
        let cycle = STEP * 3.0 + SHOT_STEP * SHOT_STEPS + IDLE;
        assert_eq!(at(cycle - 0.01).shot, None);
        assert_eq!(at(cycle - 0.01).done, 0);
        assert_eq!(at(cycle + 0.01).step, Some(0));
    }

    #[test]
    fn every_control_shows_the_real_gestures() {
        for special in Special::ALL {
            let [d1, d2] = dirs(special);
            for device in [
                Device::Joystick,
                Device::Spinner,
                Device::Mouse,
                Device::Keyboard,
                Device::Touch,
            ] {
                let s = steps(device, special, 0);
                // i passi della tastiera e del movimento continuo sono le due direzioni di `gesture`
                match (s[0], s[1]) {
                    (Step::Spin(a), Step::Spin(b))
                    | (Step::Slide(a), Step::Slide(b))
                    | (Step::Swipe(a), Step::Swipe(b)) => {
                        assert_eq!((a, b), (d1, d2));
                    }
                    (Step::Key(Cap::Text(a)), Step::Key(Cap::Text(b))) => {
                        let name = |d: Dir| if d == Dir::Up { "W" } else { "S" };
                        assert_eq!((a, b), (name(d1), name(d2)));
                    }
                    (Step::Stick(..), Step::Stick(..)) => assert_eq!(s.len(), 4),
                    _ => panic!("passi inattesi per {device:?}"),
                }
            }
        }
    }
}
