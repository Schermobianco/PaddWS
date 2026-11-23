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
use crate::paddle_ui::{self, Anim, Shape};
use crate::render::Renderer;
use crate::scenes::{App, Menu, Scene};
use crate::ships;
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
pub const READY_SECONDS: f64 = 1.2;
/// Riga dei nomi e dei conteggi sopra le colonne della scelta (unità a 480 righe).
const HEAD_Y: f32 = 132.0;
/// Scatto in avanti: booster accesi di tutte le racchette e immagini del RUSH (l'avanzamento a
/// schermo dura meno).
const RUSH_GHOST_SECONDS: f64 = paddle_ui::BOOST_SECONDS as f64;
/// Nome di una mossa speciale di livello `level`: al livello massimo con "MAX" davanti.
pub fn special_title(special: Special, level: u8) -> String {
    if level >= MAX_SPECIAL_LEVEL {
        format!("MAX {}", special.name())
    } else {
        special.name().to_string()
    }
}

/// Lampo del blocco del muro del GUARDIAN che rimanda la palla (0,25 s), poi si sbriciola in
/// schegge (0,45 s).
const BARRIER_FLASH_SECONDS: f64 = 0.7;
const BARRIER_BLINK_SECONDS: f64 = 0.25;
/// Durata della scritta "P1 SMASH!": si accende e si spegne come un vecchio televisore. Una riga
/// bianca si allarga (`CRT_STEP`) e si apre in altezza (`CRT_STEP`) mostrando la scritta; alla fine
/// si richiude in una riga, la riga si stringe e resta un puntino (`CRT_DOT`).
const LABEL_SECONDS: f64 = 1.2;
const CRT_STEP: f64 = 5.0 / 60.0;
const CRT_DOT: f64 = 3.0 / 60.0;
/// Scritta della mossa speciale. All'attivazione si disegnano i trattini sotto le lettere, uno ogni
/// `SPECIAL_DASH_STEP` dal lato del giocatore (due righe con la MAX), che poi si accendono mentre la
/// palla arriva verso di lui. Al colpo, per `SPECIAL_BLOCK` blocchi bianchi al posto delle lettere,
/// poi le lettere, bianche fino a `SPECIAL_WHITE`; i trattini restano accesi per
/// `SPECIAL_DASH_LIT`; da `SPECIAL_BLINK` lampeggia, fino a `SPECIAL_HIT_SECONDS`.
const SPECIAL_DASH_STEP: f64 = 2.0 / 60.0;
const SPECIAL_BLOCK: f64 = 2.0 / 60.0;
const SPECIAL_WHITE: f64 = 4.0 / 60.0;
const SPECIAL_DASH_LIT: f64 = 24.0 / 60.0;
const SPECIAL_BLINK: f64 = 44.0 / 60.0;
const SPECIAL_HIT_SECONDS: f64 = 1.0;
/// Quadrato che si allarga sul colpo speciale e dove RISING STRIKE s'impenna.
const BURST_SECONDS: f64 = 0.3;
/// Colpo di una mossa speciale, sulla racchetta di chi l'ha fatto: rinculo e onda d'urto (con la MAX
/// anche le immagini della racchetta), lampo nei primi `KICK_FLASH_SECONDS` e scossa dello schermo
/// della MAX per `KICK_SHAKE_SECONDS`.
const KICK_SECONDS: f64 = 0.3;
const KICK_FLASH_SECONDS: f64 = 0.07;
const KICK_SHAKE_SECONDS: f64 = 0.15;
/// Coda della palla con boost, curva, STEER e SLOW: posizioni dei tick precedenti (240 al secondo,
/// quindi 0,1 s), larghe quanto la palla, che sfumano dal grigio al nero.
const TRAIL_TICKS: usize = 24;
/// Salto del TELEPORT, seguendo la palla in arrivo dalla metà campo fino alla racchetta (così in
/// posizione di dash, anche quello lungo del RUSH, l'animazione accelera e termina sempre prima
/// dell'impatto): la racchetta si scompone a righe nei primi `WARP_SPAN` della corsa, poi si
/// ricompone sul punto d'arrivo da `WARP_EXIT_AT` per altri `WARP_SPAN`.
const WARP_SPAN: f32 = 0.32;
const WARP_EXIT_AT: f32 = 0.36;
/// Bullet time, solo con i colori della palette (come sul MiSTer e sul C64): quello che è bianco
/// diventa grigio, tranne la racchetta di chi l'ha attivato, che ha un bordo di accento; la coda
/// della palla è lunga il doppio e lascia immagini grigie ogni `BULLET_GHOST_STEP` posizioni, fino
/// a `BULLET_GHOST_TICKS` (meno immagini, e bordo che lampeggia, durante le rampe).
const BULLET_GHOST_STEP: usize = 12;
const BULLET_GHOST_TICKS: usize = 96;
/// OMEGA: la racchetta ha il corpo normale e i segni nel viola di OMEGA (il suo accento, come in
/// `portraits.json`; l'easter egg RED lascia stare i viola). A ogni trasformazione un lampo bianco di
/// 8 frame, anche sui segni.
const OMEGA_PURPLE: Color = Color::new(224.0 / 255.0, 64.0 / 255.0, 1.0, 1.0);
pub const MORPH_FLASH_SECONDS: f64 = 8.0 / 60.0;
/// OMEGA: a ogni trasformazione, con il lampo, il nome disegnato della forma nuova (la grafica delle
/// presentazioni) per `MORPH_NAME_SECONDS`, nella metà del campo di OMEGA in alto; negli ultimi
/// `MORPH_NAME_BLINK` lampeggia e sparisce.
pub const MORPH_NAME_SECONDS: f64 = 1.0;
const MORPH_NAME_BLINK: f64 = 10.0 / 60.0;
/// Altezza del centro del nome (frazione dell'altezza del campo, dall'alto).
const MORPH_NAME_Y: f32 = 0.3;

/// Colore dei segni della racchetta di OMEGA (il viola del suo accento, come il sigillo e il C64).
pub fn omega_color(_app: &App) -> Color {
    OMEGA_PURPLE
}

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

/// La palla quadrata di lato `size` centrata in (x, y) (coordinate del core) con il rilievo delle
/// racchette (`paddle_ui`): ombra portata grigio scuro 1 pixel in basso e 1 dietro rispetto al
/// moto, colonna del retro e fila di fondo un tono sotto il colore. Solo colori pieni.
fn draw_relief_ball(r: &Renderer, (x, y): (f32, f32), size: f32, u: f32, color: Color, rightward: bool) {
    let back = if rightward { -1.0 } else { 1.0 };
    let (x0, y0) = (x - size / 2.0, r.screen_y(y) - size / 2.0);
    draw_rectangle(x0 + back * u, y0 + u, size, size, Color::from_rgba(48, 48, 58, 255));
    draw_rectangle(x0, y0, size, size, color);
    let shade = Color::new(color.r * 212.0 / 255.0, color.g * 214.0 / 255.0, color.b * 224.0 / 255.0, color.a);
    draw_rectangle(if rightward { x0 } else { x0 + size - u }, y0, u, size, shade);
    draw_rectangle(x0, y0 + size - u, size, u, shade);
}

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

/// Raggi dei due archi delle righe di rotazione oltre la punta della racchetta, in pixel arcade.
const SPIN_RADII: [f32; 2] = [5.0, 2.0];
/// Per ogni arco, da dove a dove resta dietro la punta (radianti); e dove il bianco diventa
/// grigio e il grigio scuro a scacchi, per tutti e due.
const SPIN_SPANS: [(f32, f32); 2] = [(0.30, 1.75), (0.65, 1.45)];
const SPIN_GRAY_AT: f32 = 0.80;
const SPIN_DARK_AT: f32 = 1.15;

/// Righe di rotazione della racchetta che gira con il SUPER armato (centro `(cx, cy)` sullo schermo,
/// alta `ph`, girata di `angle` in senso orario): due archi dietro ogni punta, fermi rispetto alla
/// racchetta, quindi girano con lei. Bianchi vicino alla punta, poi grigi, poi scuri e a scacchi;
/// a pixel arcade (`u`).
fn draw_spin_lines((cx, cy): (f32, f32), ph: f32, angle: f32, u: f32, (white, gray): (Color, Color)) {
    let dark = Color::new(gray.r * 0.5, gray.g * 0.5, gray.b * 0.5, 1.0);
    for tip in [-std::f32::consts::FRAC_PI_2, std::f32::consts::FRAC_PI_2] {
        for (extra, (from, to)) in SPIN_RADII.into_iter().zip(SPIN_SPANS) {
            let rad = ph * 0.5 + extra * u;
            // un passo di mezzo pixel arcade: nessun buco lungo l'arco
            let steps = ((to - from) * rad / u * 2.0).ceil() as usize;
            for i in 0..=steps {
                let behind = from + (to - from) * i as f32 / steps as f32;
                let a = tip + angle - behind;
                let (px, py) = ((rad * a.cos() / u).round(), (rad * a.sin() / u).round());
                let color = if behind < SPIN_GRAY_AT {
                    white
                } else if behind < SPIN_DARK_AT {
                    gray
                } else if (px + py).rem_euclid(2.0) == 0.0 {
                    dark
                } else {
                    continue;
                };
                draw_rectangle(cx + (px - 0.5) * u, cy + (py - 0.5) * u, u, u, color);
            }
        }
    }
}

/// Onda d'urto del colpo di una mossa davanti alla racchetta in (x, y) (coordinate del core), a
/// `k` (0..1) della sua durata; `back` è il verso del fondo del campo di chi colpisce. STRAIGHT
/// SHOT: due righe orizzontali che partono dalla faccia e corrono avanti accorciandosi; RISING
/// STRIKE: un gallone a 45 gradi, come l'impennata, che si allontana (aperto in su e in giù: non
/// dice da che parte la palla s'impennerà). Con la MAX anche due immagini della racchetta dietro.
#[allow(clippy::too_many_arguments)]
fn draw_kick(
    r: &Renderer,
    special: Special,
    max: bool,
    k: f32,
    (x, y): (f32, f32),
    (pw, ph): (f32, f32),
    back: f32,
    u: f32,
    accent: Color,
) {
    let fwd = -back;
    let face = x + fwd * pw / 2.0;
    let fade = Color { a: 1.0 - k, ..accent };
    match special {
        Special::Straight => {
            let len = 12.0 * u * (1.0 - k) + 2.0 * u;
            let from = face + fwd * (2.0 * u + 30.0 * u * k);
            for dy in [-ph / 4.0, ph / 4.0] {
                r.rect_centered(from + fwd * len / 2.0, y + dy, len, u, fade);
            }
        }
        Special::Rise => {
            let tip = face + fwd * (4.0 * u + 24.0 * u * k);
            let arm = ((6.0 + 6.0 * k) as u32).max(1);
            for i in 0..arm {
                let d = i as f32 * u;
                r.rect_centered(tip - fwd * d, y + d, u, u, fade);
                r.rect_centered(tip - fwd * d, y - d, u, u, fade);
            }
        }
    }
    if max {
        for i in 1..=2 {
            let off = back * i as f32 * 4.0 * u * (1.0 + k);
            let a = (1.0 - k) * 0.5 / i as f32;
            r.rect_centered(x + off, y, pw, ph, Color { a, ..accent });
        }
    }
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

/// Posizione della racchetta di `side` come frazione della larghezza del campo, dal suo bordo.
fn pad_share(game: &Match, side: usize) -> f32 {
    let share = to_f32(game.paddles[side].x) / to_f32(game.params.width);
    if side == 0 { share } else { 1.0 - share }
}

/// Avanzamento del salto del TELEPORT con la palla a `share` e la racchetta a `pad` (da metà campo
/// alla racchetta): parte affondata nel primo portale e parte uscita dal secondo, da 0 a 1.
/// In posizione di dash la corsa dalla metà campo è più corta, quindi il salto accelera e termina
/// sempre prima che la palla arrivi alla racchetta.
fn warp_progress(share: f32, pad: f32) -> (f32, f32) {
    let span = (0.5 - pad).max(0.05);
    let t = ((0.5 - share) / span).clamp(0.0, 1.0);
    let sunk = (t / WARP_SPAN).clamp(0.0, 1.0);
    let out = ((t - WARP_EXIT_AT) / WARP_SPAN).clamp(0.0, 1.0);
    (sunk, out)
}

/// Salto del TELEPORT (coordinate del core, y verso l'alto): la racchetta vera (con il suo tipo e i
/// suoi dettagli) si scompone a righe dove si trovava (`sunk`) e si ricompone a righe sul punto
/// d'arrivo (`out`), con le righe che passano per il colore del personaggio (`paddle_ui::scan_row`).
/// `draw_at(y, scan)` disegna la racchetta.
fn draw_warp((from, to): (f32, f32), (sunk, out): (f32, f32), jitter: bool, mut draw_at: impl FnMut(f32, paddle_ui::Scan)) {
    let (s, o) = ((sunk * 32.0).round() as i32, (out * 32.0).round() as i32);
    draw_at(from, paddle_ui::Scan { level: s, arriving: false, jitter });
    draw_at(to, paddle_ui::Scan { level: o, arriving: true, jitter });
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
    ready: Option<f64>,
    /// encoder già impostati per la scelta
    knobs_ready: bool,
}

impl Pick {
    pub fn new(app: &App) -> Self {
        let mut chosen = [Vec::new(), Vec::new()];
        if let Some(run) = &app.run {
            // i bonus dell'avversario del primo livello (nell'allenamento di quello scelto)
            chosen[1] = crate::challenge_ui::rung(run.level).loadout.to_vec();
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
            cpu: app.vs_cpu(),
            fixed: app.vs_cpu().then_some(1),
            duel: None,
            cursor: [0; 2],
            chosen,
            confirmed: [false; 2],
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

    /// CHALLENGE che comincia con la sfida (`PaddlePick::opening_duel`): scelgono tutti e due.
    pub fn opening_duel(app: &App) -> Self {
        let mut pick = Self::new(app);
        pick.cpu = false;
        pick.fixed = None;
        pick.duel = Some(Side::Right);
        pick.chosen = [Vec::new(), Vec::new()];
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
                // la racchetta è già scelta (`PaddlePick`, prima di qui)
                app.loadout = self.loadouts();
                if let Some(free) = self.duel {
                    // sfida in CHALLENGE: lo sfidante vede le mosse speciali se dal suo lato non
                    // le ha ancora viste nessuno in questa sessione
                    // (nella sfida che apre la scalata la vedono tutti e due insieme)
                    let i = free as usize;
                    let run = app.run.as_mut().expect("sfida senza CHALLENGE");
                    let seen = if self.fixed.is_none() {
                        std::mem::replace(&mut run.howto, [true; 2]) == [true; 2]
                    } else {
                        std::mem::replace(&mut run.howto[i], true)
                    };
                    if !seen {
                        return Some(Scene::HowTo(crate::moves_ui::HowTo::duel(app)));
                    }
                    // prima della sfida lo schermo VS con i due giocatori
                    return Some(Scene::Intro(crate::challenge_ui::Intro::duel(app)));
                }
                // poi la presentazione delle mosse speciali (in CHALLENGE solo qui, prima del
                // primo incontro)
                if let Some(run) = &mut app.run {
                    run.howto[run.side as usize] = true;
                }
                return Some(Scene::HowTo(crate::moves_ui::HowTo::new(app)));
            }
            return None;
        }
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
        if done {
            // chi non ha scelto (la CPU, il campione) ha le scelte predefinite
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
        let t1 = r.text_1x();
        r.fill(BLACK);
        // le code delle stelle cadenti hanno il colore della racchetta di destra, se è già scelta
        let peak = app.paddles[1].map_or(crate::space::NEUTRAL, |k| app.assets.portraits.accent_rgb(k));
        crate::space::draw(app, peak);
        r.text_centered("PICK 3 BONUSES", font, t1, w / 2.0, 34.0 * s, 0.0, accent);
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
            r.text_centered(&self.name(side), font, t1, col - 70.0 * s, head, 0.0, white);
            if app.touch && chosen.len() == 3 && !self.confirmed[side] && self.fixed != Some(side) && self.ready.is_none() {
                // touch: il pulsante con cui si chiude la scelta
                draw_rectangle(col + 35.0 * s, head - 18.0 * s, 70.0 * s, 36.0 * s, accent);
                let black = App::color(app.cfg.colors.black);
                r.text_centered("OK", font, t1, col + 70.0 * s, head, 0.0, black);
            } else {
                r.text_centered(
                    &format!("{}/3", chosen.len()),
                    font,
                    t1,
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
                    r.text_centered(">", font, t1, col - 105.0 * s, cy, 0.0, accent);
                }
                draw_capsule(b, col - 70.0 * s, cy, size, u, on, color);
                // il nome allineato a sinistra, a distanza fissa dalla capsula (centrato, a 1x,
                // TELEPORT la toccava nel campo 4:3)
                let left = col - 70.0 * s + size / 2.0 + 10.0 * s;
                r.text_centered(b.name(), font, t1, left + r.text_width(b.name(), font, t1) / 2.0, cy, 0.0, color);
            }
        }
        if self.ready.is_some() && (get_time() * 6.0) as i64 % 2 == 0 {
            r.text_centered("READY!", font, t1, w / 2.0, h - 20.0 * s, 0.0, accent);
        } else if self.ready.is_none() && !app.touch {
            // tasti di ciascun giocatore, centrati sotto la sua colonna (chi non sceglie non ne ha)
            if self.fixed != Some(0) {
                r.text_centered("W S + C", font, t1, w / 4.0, h - 16.0 * s, 0.0, gray);
            }
            if self.fixed != Some(1) {
                r.text_centered("UP DOWN + -", font, t1, 3.0 * w / 4.0, h - 16.0 * s, 0.0, gray);
            }
        }
    }
}

// --------------------------------------------------------------- partita

/// Scritta di una mossa speciale: mossa, livello, se è già il colpo (altrimenti la mossa è armata e
/// si vedono solo i trattini) e secondi dall'attivazione o dal colpo.
#[derive(Clone, Copy)]
struct SpecialLabel {
    special: Special,
    level: u8,
    hit: bool,
    t: f64,
}

/// Mossa armata dal giocatore `side`: quanta strada ha fatto la palla verso la sua racchetta (0
/// dalla racchetta avversaria, 1 arrivata), 0 se va dall'altra parte.
fn approach(game: &Match, side: usize) -> f32 {
    let b = &game.ball;
    let toward = if side == 0 { b.vx < 0 } else { b.vx > 0 };
    let (pad, other) = (to_f32(game.paddles[side].x), to_f32(game.paddles[1 - side].x));
    if !toward || pad == other {
        return 0.0;
    }
    ((to_f32(b.x) - other) / (pad - other)).clamp(0.0, 1.0)
}

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
    /// secondi che restano dello scatto in avanti (booster accesi; RUSH anche le immagini)
    rush_ghost: [f64; 2],
    pad_home: [bool; 2],
    /// mosse speciali: barra prima del tick (per capire chi ha speso), scritta della mossa per
    /// giocatore, RISING STRIKE ancora da impennare prima del tick e quadrato del colpo o
    /// dell'impennata (x, y, secondi)
    meters: [u8; 2],
    special_label: [Option<SpecialLabel>; 2],
    rise_pending: bool,
    burst: Option<(f32, f32, f64)>,
    /// verso della palla al tick prima: la coda riparte a ogni colpo
    ball_left: bool,
    /// colpo di una mossa speciale per racchetta: mossa, livello e secondi dall'inizio
    kick: [Option<(Special, u8, f64)>; 2],
    /// OMEGA: tipi delle racchette prima del tick e secondi del lampo della trasformazione
    kinds_before: [Option<PaddleKind>; 2],
    morph_flash: [f64; 2],
    /// OMEGA: nome della forma nuova, lato di OMEGA e secondi che restano
    morph_name: Option<(PaddleKind, usize, f64)>,
    /// racchette dei personaggi (`paddle_ui::Anim`): colpi della cartuccera, muro del GUARDIAN e
    /// cooldown prima del tick; secondi dal gettone ARCADE, dallo sparo BLASTER, dal colpo potente
    /// di HAMMER e dal colpo che fa rientrare un corso del GUARDIAN (con l'altezza del colpo, 0 in
    /// cima e 1 in fondo); secondi dalla rottura di ogni corso
    ammo_before: [u8; 2],
    wall_before: [u8; 2],
    cooldown_before: [u32; 2],
    coin: [Option<f32>; 2],
    fire: [Option<f32>; 2],
    spark: [Option<(f32, f32)>; 2],
    recoil: [Option<(f32, f32)>; 2],
    wall_age: [[f32; GUARDIAN_SECTORS]; 2],
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
            ball_left: false,
            kick: [None; 2],
            kinds_before: [None; 2],
            morph_flash: [0.0; 2],
            morph_name: None,
            ammo_before: [0; 2],
            wall_before: [0; 2],
            cooldown_before: [0; 2],
            coin: [None; 2],
            fire: [None; 2],
            spark: [None; 2],
            recoil: [None; 2],
            wall_age: [[paddle_ui::BREAK_SECONDS; GUARDIAN_SECTORS]; 2],
        }
    }

    /// Nome della forma `kind` di OMEGA (dal lato `side`), già acceso da `seconds` (per le
    /// schermate di verifica; in partita parte con il lampo della trasformazione).
    pub fn show_morph_name(&mut self, kind: PaddleKind, side: usize, seconds: f64) {
        self.morph_name = Some((kind, side, MORPH_NAME_SECONDS - seconds));
    }

    /// Lampo della trasformazione di OMEGA sulla racchetta `side`, già acceso da `seconds` (per le
    /// schermate di verifica; in partita parte quando il tipo cambia).
    pub fn show_morph(&mut self, side: usize, seconds: f64) {
        self.morph_flash[side] = MORPH_FLASH_SECONDS - seconds;
    }

    /// Effetti della racchetta del giocatore `side` già avanti di `seconds` (per le schermate di
    /// verifica; in partita partono dagli eventi): sparo del BLASTER, scintille di HAMMER, onda di TWIST, rientro
    /// del corso del GUARDIAN colpito a metà altezza, rottura dei settori già persi con il lampo
    /// sul muro del primo.
    pub fn show_paddle_fx(&mut self, game: &Match, side: usize, seconds: f32) {
        let Some(n) = &game.next else { return };
        let pl = &n.players[side];
        match pl.kind {
            Some(PaddleKind::Arcade) => self.coin[side] = Some(seconds),
            Some(PaddleKind::Blaster) => self.fire[side] = Some(seconds),
            Some(PaddleKind::Hammer | PaddleKind::Twist) => self.spark[side] = Some((seconds, 0.5)),
            Some(PaddleKind::Guardian) => {
                self.recoil[side] = Some((seconds, 0.5));
                for (i, age) in self.wall_age[side].iter_mut().enumerate() {
                    if pl.barrier & (1 << i) == 0 {
                        *age = seconds;
                    }
                }
                if let Some(hit) = (0..GUARDIAN_SECTORS).find(|&i| pl.barrier & (1 << i) == 0) {
                    self.barrier_flash[side] = (BARRIER_FLASH_SECONDS - f64::from(seconds), hit);
                }
            }
            _ => {}
        }
    }

    /// Scritta di un bonus in alto al centro, sotto i punteggi (come "P1 SMASH!"), come sul MiSTer.
    pub fn show_label(&mut self, text: &str) {
        self.show_label_at(text, 0.0);
    }

    /// Come `show_label`, già accesa da `seconds` (per le schermate di verifica).
    pub fn show_label_at(&mut self, text: &str, seconds: f64) {
        self.label = Some((text.to_string(), LABEL_SECONDS - seconds));
    }

    /// Scritta di una mossa speciale di livello `level` per il giocatore `side`: all'attivazione
    /// o, con `hit`, al colpo.
    pub fn show_special(&mut self, side: usize, special: Special, level: u8, hit: bool) {
        self.special_label[side] = Some(SpecialLabel {
            special,
            level,
            hit,
            t: 0.0,
        });
    }

    /// Colpo di una mossa sulla racchetta del giocatore `side`, già avanti di `seconds` (per le
    /// schermate di verifica; in partita parte dall'evento del colpo).
    pub fn show_kick(&mut self, side: usize, special: Special, level: u8, seconds: f64) {
        self.kick[side] = Some((special, level, seconds));
    }

    /// Da chiamare prima di ogni tick: serve a capire chi ha attivato un bonus.
    pub fn before_tick(&mut self, game: &Match) {
        if let Some(n) = &game.next {
            self.counts = [n.players[0].count(), n.players[1].count()];
            self.meters = [n.players[0].meter, n.players[1].meter];
            self.rise_pending = n.rise_break.is_some();
            self.bullet_before = n.bullet;
            self.kinds_before = [n.players[0].kind, n.players[1].kind];
            self.ammo_before = n.players.each_ref().map(|pl| pl.ammo);
            self.wall_before = n.players.each_ref().map(|pl| pl.barrier);
            self.cooldown_before = n.players.each_ref().map(|pl| pl.cooldown);
        }
    }

    pub fn after_tick(&mut self, game: &Match, events: Events, scale: f32) {
        let Some(n) = &game.next else { return };
        // OMEGA: la racchetta che cambia tipo in questo tick lampeggia
        if let Some(side) = game.morph()
            && n.players[side as usize].kind != self.kinds_before[side as usize]
        {
            self.morph_flash[side as usize] = MORPH_FLASH_SECONDS;
            if let Some(kind) = n.players[side as usize].kind {
                self.morph_name = Some((kind, side as usize, MORPH_NAME_SECONDS));
            }
        }
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
            self.kick[side] = Some((special, n.special_level, 0.0));
        }
        // mossa armata che non c'è più senza il colpo (un punto, o le mosse spente): via i trattini
        for (label, pl) in self.special_label.iter_mut().zip(&n.players) {
            if label.is_some_and(|l| !l.hit) && pl.special_idle() {
                *label = None;
            }
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
        // a ogni colpo (la palla cambia verso) la coda riparte: altrimenti resterebbe piegata sul
        // percorso d'arrivo, e nel colore del nuovo tiro
        if (b.vx < 0) != self.ball_left {
            self.ball_left = b.vx < 0;
            self.trail.clear();
        }
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
        // racchette dei personaggi: sparo del BLASTER (la cartuccera perde un colpo), corsi del
        // GUARDIAN appena rotti, colpo della racchetta (la palla riparte dall'altra parte)
        let hit = events.has(Event::Hit) || events.has(Event::Boost) || events.has(Event::Super);
        let hitter = if b.vx > 0 { 0 } else { 1 };
        for (side, pl) in n.players.iter().enumerate() {
            // ARCADE: doppio clic USE a riserva vuota (Event::Collect + cooldown appena partito)
            if events.has(Event::Collect)
                && pl.kind == Some(PaddleKind::Arcade)
                && pl.count() == 0
                && self.counts[side] == 0
                && self.cooldown_before[side] == 0
                && pl.cooldown > 0
            {
                self.coin[side] = Some(0.0);
            }
            if pl.kind == Some(PaddleKind::Blaster) && pl.ammo < self.ammo_before[side] {
                self.fire[side] = Some(0.0);
            }
            for (i, age) in self.wall_age[side].iter_mut().enumerate() {
                if self.wall_before[side] & !pl.barrier & (1 << i) != 0 {
                    *age = 0.0;
                }
            }
            if hit && side == hitter {
                let pad = &game.paddles[side];
                let top = to_f32(pad.y) + to_f32(pad.height) / 2.0;
                let at = ((top - to_f32(b.y)) / to_f32(pad.height)).clamp(0.0, 1.0);
                match pl.kind {
                    // HAMMER (scintille + propulsore) e TWIST (onda): a ogni colpo, anche in dash
                    Some(PaddleKind::Hammer | PaddleKind::Twist) => self.spark[side] = Some((0.0, at)),
                    Some(PaddleKind::Guardian) => self.recoil[side] = Some((0.0, at)),
                    _ => {}
                }
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
            let out = warp_progress(field_share(game, side), pad_share(game, side)).1 >= 1.0;
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
        let flashes = self.barrier_flash.iter_mut().map(|(t, _)| t).chain(&mut self.rush_ghost);
        for t in flashes.chain(&mut self.morph_flash) {
            *t = (*t - dt).max(0.0);
        }
        let step = dt as f32;
        let advance = |t: &mut f32, limit: f32| {
            *t += step;
            *t < limit
        };
        for side in 0..2 {
            if let Some(t) = &mut self.coin[side]
                && !advance(t, paddle_ui::COIN_SECONDS)
            {
                self.coin[side] = None;
            }
            if let Some(t) = &mut self.fire[side]
                && !advance(t, paddle_ui::FIRE_SECONDS)
            {
                self.fire[side] = None;
            }
            if let Some((t, _)) = &mut self.spark[side]
                && !advance(t, paddle_ui::SPARK_SECONDS.max(paddle_ui::RING_SECONDS))
            {
                self.spark[side] = None;
            }
            if let Some((t, _)) = &mut self.recoil[side]
                && !advance(t, paddle_ui::RECOIL_SECONDS)
            {
                self.recoil[side] = None;
            }
            for age in &mut self.wall_age[side] {
                *age = (*age + step).min(paddle_ui::BREAK_SECONDS);
            }
        }
        if let Some((_, t)) = &mut self.label {
            *t -= dt;
            if *t <= 0.0 {
                self.label = None;
            }
        }
        if let Some((_, _, t)) = &mut self.morph_name {
            *t -= dt;
            if *t <= 0.0 {
                self.morph_name = None;
            }
        }
        // la scritta della mossa armata resta finché c'è la mossa (`after_tick`)
        for label in &mut self.special_label {
            if let Some(l) = label {
                l.t += dt;
                if l.hit && l.t >= SPECIAL_HIT_SECONDS {
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
        for kick in &mut self.kick {
            if let Some((_, _, t)) = kick {
                *t += dt;
                if *t >= KICK_SECONDS {
                    *kick = None;
                }
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
    /// `build`: secondi dall'inizio del conto alla rovescia, mentre c'è (il GUARDIAN costruisce il muro).
    pub fn draw_field(
        &self,
        app: &App,
        game: &Match,
        pos: &[(f32, f32); 3],
        shake: f32,
        skip: Option<usize>,
        build: Option<f32>,
    ) {
        let Some(n) = &game.next else { return };
        let r = &app.renderer;
        let u = unit(app);
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        // bullet time: il bianco diventa grigio tranne per la racchetta (e i colpi) di chi l'ha attivato
        let time = bullet_time(game);
        let owner = time.map(|b| b.side);
        let cold = |c: Color| slowed_color(c, owner.is_some(), white, gray);
        let tint = |side: usize, c: Color| if owner == Some(side) { c } else { cold(c) };

        // GUARDIAN: il muro non si vede in campo (è nei corsi della racchetta); dove la palla lo
        // colpisce, sulla sua linea, il blocco del settore lampeggia e poi si sbriciola in schegge
        // che cadono verso il fondo
        for (side, pl) in n.players.iter().enumerate() {
            let (flash, hit) = self.barrier_flash[side];
            if pl.kind != Some(PaddleKind::Guardian) || flash <= 0.0 {
                continue;
            }
            let p = &game.params;
            let bx = to_f32(p.guardian_barrier_x);
            let lx = if side == 0 { bx } else { to_f32(p.width) - bx } + shake;
            let back = if side == 0 { -1.0 } else { 1.0 };
            let top = if hit == 0 { to_f32(p.guardian_top) } else { to_f32(p.guardian_bounds[hit - 1]) };
            let bottom = p.guardian_bounds.get(hit).map_or(0.0, |&b| to_f32(b));
            // dall'alto dello schermo, in pixel arcade (la y del core cresce verso l'alto)
            let (s0, s1) = (r.screen_y(top) / u, r.screen_y(bottom) / u);
            let blue = app.assets.portraits.accent(PaddleKind::Guardian);
            let age = (BARRIER_FLASH_SECONDS - flash) as f32;
            let blink = BARRIER_BLINK_SECONDS as f32;
            if age < blink {
                let color = if (age * 16.0) as i64 % 2 == 1 { blue } else { Color::from_rgba(190, 214, 255, 255) };
                draw_rectangle(lx - 2.0 * u, (s0 + 3.0) * u, 4.0 * u, (s1 - s0 - 6.0) * u, tint(side, color));
                let mut y = s0 + 11.0;
                while y < s1 - 3.0 {
                    draw_rectangle(lx - 2.0 * u, y * u, 4.0 * u, u, BLACK);
                    y += 9.0;
                }
            } else {
                let k = (age - blink) / (BARRIER_FLASH_SECONDS as f32 - blink);
                let fade = 1.0 - 0.5 * k;
                let color = Color::new(blue.r * fade, blue.g * fade, blue.b * fade, 1.0);
                for j in 0..8 {
                    let jf = j as f32;
                    let y = s0 + 5.0 + jf * (s1 - s0 - 10.0) / 7.0;
                    let (dx, dy) = (k * (3.0 + (j % 3) as f32 * 3.0), k * k * 10.0);
                    let size = if j % 2 == 1 { 1.0 } else { 2.0 };
                    // le schegge vanno verso il fondo dietro il muro
                    let x = (lx / u + back * (1.0 + dx)).round() - if side == 0 { 0.0 } else { size };
                    draw_rectangle(x * u, (y + dy).round() * u, size * u, size * u, tint(side, color));
                }
            }
        }

        // BLASTER: colpi singoli (2 fasci laser verdi dai cannoni alari) oppure raggio laser
        // continuo quando più colpi ravvicinati partono tenendo premuto il fuoco
        let laser = app.assets.portraits.accent(PaddleKind::Blaster);
        let laser_core = Color::new(
            (laser.r + 0.55).min(1.0),
            (laser.g + 0.35).min(1.0),
            (laser.b + 0.55).min(1.0),
            1.0,
        );
        let beam_pulse = 0.5 + 0.5 * ((game.tick as f32 / paddws_core::TICK_HZ as f32) * 32.0).sin();
        let beam_span = 215.0 * (to_f32(game.params.scale));
        for (side, pl) in n.players.iter().enumerate() {
            let mut active: Vec<(f32, f32)> = pl
                .shots
                .iter()
                .flatten()
                .map(|s| (to_f32(s.x) + shake, to_f32(s.y)))
                .collect();
            if active.is_empty() {
                continue;
            }
            active.sort_by(|a, b| a.0.total_cmp(&b.0));
            let dir = if side == 0 { 1.0 } else { -1.0 };
            // distanza verticale tra il centro della racchetta e i due cannoni (gli agganci delle
            // armi dello sprite del BLASTER)
            let gun_dy = ships::gun_dy(to_f32(game.paddles[side].height)).max(2.0 * u);
            let draw_beam = |x0: f32, x1: f32, sy: f32| {
                let cx = (x0 + x1) * 0.5;
                let w = (x1 - x0).abs().max(9.0 * u);
                let halo = Color {
                    a: 0.24 + 0.16 * beam_pulse,
                    ..tint(side, laser)
                };
                for dy in [-gun_dy, gun_dy] {
                    r.rect_centered(cx, sy + dy, w, 3.0 * u, halo);
                    r.rect_centered(cx, sy + dy, w, 1.5 * u, tint(side, laser));
                    r.rect_centered(cx, sy + dy, w, 0.85 * u, tint(side, laser_core));
                }
            };
            // collega in un raggio continuo i colpi consecutivi ravvicinati (sparati tenendo premuto)
            let mut linked = vec![false; active.len()];
            for i in 0..active.len().saturating_sub(1) {
                let (x0, y0) = active[i];
                let (x1, y1) = active[i + 1];
                if (x1 - x0).abs() <= beam_span && (y1 - y0).abs() <= 12.0 * u {
                    draw_beam(x0, x1, (y0 + y1) * 0.5);
                    linked[i] = true;
                    linked[i + 1] = true;
                }
            }
            // se il raggio è attivo dalla navicella, collega la bocca dei cannoni al primo colpo
            if pl.kind == Some(PaddleKind::Blaster) && self.fire[side].is_some_and(|t| t < 0.25) {
                let pad = &game.paddles[side];
                let muzzle_x = to_f32(if side == 0 { pad.right() } else { pad.left() }) + shake + dir * ships::barrel() * u;
                let pad_y = to_f32(pad.y);
                let near = if side == 0 { 0 } else { active.len() - 1 };
                let (nx, ny) = active[near];
                if (nx - muzzle_x).abs() <= beam_span && (ny - pad_y).abs() <= 12.0 * u && (linked[near] || active.len() >= 2) {
                    draw_beam(muzzle_x, nx, (ny + pad_y) * 0.5);
                }
            }
            // colpi singoli isolati (e teste brillanti del raggio dai due cannoni)
            for &(sx, sy) in &active {
                for dy in [-gun_dy, gun_dy] {
                    r.rect_centered(sx, sy + dy, 9.0 * u, 1.5 * u, tint(side, laser));
                    r.rect_centered(sx + dir * 2.0 * u, sy + dy, 4.0 * u, 0.85 * u, tint(side, laser_core));
                }
            }
        }

        for (side, &at) in pos.iter().take(2).enumerate() {
            if skip != Some(side) {
                self.draw_pad(app, game, at, shake, side, build);
            }
        }

        // STEER: segni sui bordi alto e basso dove finisce la guida (3/4 del campo)
        if let Some(side) = n.steer {
            let w = to_f32(game.params.width);
            let lx = if side == Side::Left { w - w / 4.0 } else { w / 4.0 };
            draw_rectangle(lx - u, 0.0, 2.0 * u, 6.0 * u, accent);
            draw_rectangle(lx - u, r.world_h - 6.0 * u, 2.0 * u, 6.0 * u, accent);
        }

        self.draw_trail(app, game, shake);
        self.draw_ball(app, game, pos[2], shake);
        // colpo speciale: un quadrato che si allarga dal punto del colpo
        let d = to_f32(game.ball.radius) * 2.0;
        if let Some((cx, cy, t)) = self.burst {
            let k = 1.0 - (t / BURST_SECONDS) as f32;
            let side = d * (1.5 + 5.0 * k);
            let color = Color { a: 1.0 - k, ..accent };
            draw_rectangle_lines(cx + shake - side / 2.0, r.screen_y(cy) - side / 2.0, side, side, u, color);
        }
    }

    /// Scie della palla: lunga e piena per la COMETA; per gli altri effetti una coda larga quanto la
    /// palla che sfuma dal grigio al nero (dalla più vecchia, così le nuove la coprono), e nel
    /// bullet time le immagini della palla lungo la scia.
    fn draw_trail(&self, app: &App, game: &Match, shake: f32) {
        let Some(n) = &game.next else { return };
        let r = &app.renderer;
        let u = unit(app);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        let time = bullet_time(game);
        let owner = time.map(|b| b.side);
        let d = to_f32(game.ball.radius) * 2.0;
        let comet = n.super_flight == Some(SuperAnim::Comet);
        // la coda delle mosse speciali in volo sfuma dall'accento invece che dal grigio (la palla:
        // `draw_ball`)
        let tail = if n.special_flight.is_some() { accent } else { gray };
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
    }

    /// La palla in (x, y) (coordinate del core, già interpolate), con le righe dello STRAIGHT SHOT e
    /// l'alone di SLOW (niente quando lampeggia al servizio o GHOST la nasconde).
    fn draw_ball(&self, app: &App, game: &Match, (x, y): (f32, f32), shake: f32) {
        let Some(n) = &game.next else { return };
        let serve_blink = game.serving() && (game.serve_timer * 8 / paddws_core::TICK_HZ) % 2 == 1;
        if serve_blink || n.ball_hidden(&game.params, game.tick) {
            return;
        }
        let r = &app.renderer;
        let u = unit(app);
        let white = App::color(app.cfg.colors.white);
        let gray = App::color(app.cfg.colors.lgray);
        let accent = App::color(app.cfg.colors.accent);
        let blink = (game.tick / 16).is_multiple_of(2);
        let ball = &game.ball;
        let d = to_f32(ball.radius) * 2.0;
        let comet = n.super_flight == Some(SuperAnim::Comet);
        // la palla del SUPER e delle mosse speciali in volo (e la testa della cometa) ha il colore
        // di accento
        let special = n.special_flight;
        let ball_color = if n.super_flight.is_some() || special.is_some() {
            accent
        } else {
            white
        };
        let size = if comet { d * 1.6 } else { d };
        let (bx, by) = (x + shake, y);
        match special {
            // STRAIGHT SHOT: righe di velocità orizzontali dietro la palla
            Some(Special::Straight) => {
                let back = if ball.vx > 0 { -1.0 } else { 1.0 };
                for (dy, len) in [(-d, 5.0 * d), (0.0, 9.0 * d), (d, 5.0 * d)] {
                    let lx = bx + back * (d + len / 2.0);
                    r.rect_centered(lx, by + dy, len, u, Color { a: 0.8, ..accent });
                }
                draw_relief_ball(r, (bx, by), size, u, ball_color, ball.vx > 0);
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
            None => draw_relief_ball(r, (bx, by), size, u, ball_color, ball.vx > 0),
        }
        if n.slow_timer > 0 && blink {
            draw_rectangle_lines(bx - d * 1.5, r.screen_y(by) - d * 1.5, d * 3.0, d * 3.0, u, gray);
        }
    }

    /// La racchetta del giocatore `side` in (x, y) (coordinate del core, x già interpolata), con i
    /// segni dei bonus, del tipo e del BULLET.
    pub fn draw_pad(&self, app: &App, game: &Match, (x, y): (f32, f32), shake: f32, side: usize, build: Option<f32>) {
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
        // OMEGA: il corpo è quello di tutte, grigio nel bullet time dell'avversario; sono i segni a
        // prendere il viola di OMEGA, bianchi nel lampo della trasformazione e grigi nel bullet time
        let morphing = game.morph().is_some_and(|s| s as usize == side);
        let skin = if morphing && cold { gray } else { white };
        let omega_mark = morphing.then(|| {
            if self.morph_flash[side] > 0.0 {
                white
            } else if cold {
                gray
            } else {
                omega_color(app)
            }
        });
        let make_look = |kind: Option<PaddleKind>, color: Color| {
            let mut look = paddle_ui::look(app, kind, color);
            if let Some(m) = omega_mark {
                look.mark = m;
            }
            look
        };
        let pl = &n.players[side];
        let front = if side == 0 { 1.0 } else { -1.0 };
        // la racchetta con il segno del suo tipo e lo stato delle sue animazioni (l'orologio è
        // quello della partita: si ferma con la pausa)
        let hz = paddws_core::TICK_HZ as f32;
        let anim = Anim {
            t: game.tick as f32 / hz,
            vy: -to_f32(pad.motion) * hz / 60.0 / u,
            coin: self.coin[side],
            ammo: pl.ammo,
            reload: (pl.reload > 0)
                .then(|| 1.0 - pl.reload as f32 / game.params.blaster_reload_ticks.max(1) as f32),
            fire: self.fire[side],
            spark: self.spark[side],
            wall: std::array::from_fn(|i| (pl.barrier & (1 << i) == 0).then_some(self.wall_age[side][i])),
            build,
            recoil: self.recoil[side].map(|(_, at)| at),
            dashing: self.rush_ghost[side] > 0.0,
            clock: get_time() as f32,
        };
        if let Some(from) = self.warp[side] {
            let progress = warp_progress(field_share(game, side), pad_share(game, side));
            let look = make_look(pl.kind, skin);
            // tremolio delle righe in luce a 7,5 al secondo, come sul MiSTer
            let jitter = (game.tick / 32).is_multiple_of(2);
            draw_warp((from, y), progress, jitter, |cy, scan| {
                let shape = Shape {
                    kind: pl.kind,
                    x,
                    y: cy,
                    w: pw,
                    h: ph,
                    front,
                    tilt: 0.0,
                    dash: None,
                    preview: false,
                    scan: Some(scan),
                    anim,
                };
                paddle_ui::draw_paddle(r, &shape, u, look);
            });
            return;
        }
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
        // colpo di una mossa: la racchetta rincula verso il fondo e torna (di più con la MAX)
        let back = if side == 0 { -1.0 } else { 1.0 };
        let kick = self.kick[side].map(|(special, level, t)| (special, level >= MAX_SPECIAL_LEVEL, t));
        let x = match kick {
            Some((_, max, t)) => {
                let k = (t / KICK_SECONDS) as f32;
                x + back * if max { 5.0 } else { 3.0 } * u * (1.0 - k) * (1.0 - k)
            }
            None => x,
        };
        let steering = n.steer.is_some_and(|s| s as usize == side);
        // scatto dalla posizione di casa: booster accesi e, per RUSH, immagini che sfumano
        let dash = (self.rush_ghost[side] > 0.0)
            .then(|| (to_f32(pad.home_x) + shake, (self.rush_ghost[side] / RUSH_GHOST_SECONDS) as f32));
        let tilt = if pl.kind == Some(PaddleKind::Twist) {
            paddle_ui::twist_tilt(pad)
        } else {
            0.0
        };
        let body_rot = |color: Color, rot: f32| {
            // avversario colpito dal laser del BLASTER: lieve alone verde che segnala il rallentamento
            if pl.laser_slow > 0 {
                let pulse = 0.5 + 0.5 * ((game.tick as f32 / hz) * 28.0).sin();
                let laser = app.assets.portraits.accent(PaddleKind::Blaster);
                let cy = r.screen_y(y);
                let zap = Color {
                    a: 0.25 + 0.35 * pulse,
                    ..laser
                };
                draw_rectangle_lines(x - pw * 0.5 - 2.0 * u, cy - ph * 0.5 - 2.0 * u, pw + 4.0 * u, ph + 4.0 * u, u, zap);
            }
            let shape = Shape {
                kind: pl.kind,
                x,
                y,
                w: pw,
                h: ph,
                front,
                tilt: rot,
                dash,
                preview: false,
                scan: None,
                anim,
            };
            let look = make_look(pl.kind, color);
            paddle_ui::draw_paddle(r, &shape, u, look);
        };
        let body = |color: Color| body_rot(color, tilt);
        // colpo di una mossa: lampo della racchetta (giallo; con la MAX giallo e bianco a scatti)
        let mut flash = None;
        if let Some((special, max, t)) = kick {
            draw_kick(r, special, max, (t / KICK_SECONDS) as f32, (x, y), (pw, ph), back, u, accent);
            if t < KICK_FLASH_SECONDS * if max { 2.0 } else { 1.0 } {
                flash = Some(if max && (t * 30.0) as u32 % 2 == 1 { white } else { accent });
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
                // la racchetta vera (astronave del personaggio) ruota su se stessa attorno al centro
                let angle = game.tick as f32 * 0.09;
                draw_spin_lines((x, r.screen_y(y)), ph, angle, u, (white, gray));
                body_rot(skin, -angle * front);
            }
            Some(b) => {
                body(if blink { gray } else { skin });
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
                body(if level >= MAX_SPECIAL_LEVEL { accent } else { skin });
                let ix = if side == 0 { x + pw + 3.0 * u } else { x - pw - 12.0 * u };
                draw_special_icon(special, ix, r.screen_y(y) - 4.5 * u, u, side, accent);
            }
            _ => body(flash.unwrap_or(skin)),
        }
    }

    /// OMEGA: il nome della forma nuova (`morph_name`), centrato nella metà del campo di OMEGA in
    /// alto; dritto con i punteggi dritti, altrimenti girato verso il giocatore come il suo
    /// punteggio.
    fn draw_morph_name(&self, app: &App) {
        let Some((kind, side, left)) = self.morph_name else { return };
        if left < MORPH_NAME_BLINK && ((left * 30.0) as i64) % 2 == 0 {
            return;
        }
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let x = if side == 0 { w / 4.0 } else { w * 3.0 / 4.0 };
        // il giocatore sta dall'altra parte: a sinistra legge girato di 90 gradi in senso orario
        let rotation = if app.cfg.game.scores_upright {
            0.0
        } else if side == 1 {
            std::f32::consts::FRAC_PI_2
        } else {
            -std::f32::consts::FRAC_PI_2
        };
        let paint = crate::titles::paint(&app.cfg.colors);
        let art = app.assets.titles.name(kind);
        r.art_centered(art, 1.0, x, h * MORPH_NAME_Y, rotation, crate::render::ArtPart::Whole, &paint);
    }

    /// Scossa orizzontale dello schermo dopo il colpo di una mossa MAX (si somma a quella del SUPER).
    pub fn kick_shake(&self, u: f32) -> f32 {
        self.kick
            .iter()
            .flatten()
            .find(|&&(_, level, t)| level >= MAX_SPECIAL_LEVEL && t < KICK_SHAKE_SECONDS)
            .map_or(0.0, |&(_, _, t)| if ((t * 30.0) as u32).is_multiple_of(2) { 1.5 * u } else { -1.5 * u })
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

    /// Scritte della mossa speciale e del bonus attivato: sopra tutto, nitide anche nel bullet time,
    /// tranne le racchette e la palla in `pos` (coordinate del core) e la scia della palla, che si
    /// ridisegnano sopra quelle che toccano: le scritte passano sotto.
    pub fn draw_labels(&self, app: &App, game: &Match, pos: &[(f32, f32); 3], shake: f32) {
        self.draw_morph_name(app);
        let ball = pos[2];
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let s = app.scale();
        let white = App::color(app.cfg.colors.white);
        let accent = App::color(app.cfg.colors.accent);
        let u = unit(app);
        // riquadri delle scritte disegnate in questo frame
        let mut boxes: [Option<Rect>; 3] = [None; 3];
        if game.next.as_ref().is_some_and(|n| n.super_moves) {
            let p = &game.params;
            let font = &app.assets.font_text;
            let dim = Color {
                a: 0.45,
                ..App::color(app.cfg.colors.lgray)
            };
            // sotto le riserve; con i punteggi dritti (che stanno proprio lì, a 42 righe su 480) sotto
            // di loro, così il titolo non li copre
            let y = if app.cfg.game.scores_upright {
                42.0 * h / 480.0 + 50.0 * s
            } else {
                to_f32(p.capsule_margin_top) + 16.0 * s
            };
            let size = r.text_1x();
            for (side, label) in self.special_label.iter().enumerate() {
                let Some(l) = *label else { continue };
                let cx = if side == 0 { w / 4.0 } else { 3.0 * w / 4.0 };
                let title = special_title(l.special, l.level);
                let th = r.text_height(&title, font, size);
                // lettere (dall'inchiostro), contate dal lato del giocatore
                let mut letters: Vec<(f32, f32)> = r.ink_boxes(&title, font, size).into_iter().flatten().collect();
                if side == 1 {
                    letters.reverse();
                }
                let n_letters = letters.len();
                // trattini sotto le lettere: due righe con la MAX
                let dash_y = y + th / 2.0 + 3.0 * u;
                let dash = |(x0, x1): (f32, f32), color: Color| {
                    for row in 0..l.level.clamp(1, 2) {
                        draw_rectangle(cx + x0, dash_y + row as f32 * 4.0 * u, x1 - x0, 2.0 * u, color);
                    }
                };
                if !l.hit {
                    // armata: i trattini si disegnano dal lato del giocatore (l'ultimo bianco), poi si
                    // accendono man mano che la palla arriva verso di lui: quando c'è il colpo
                    let shown = ((l.t / SPECIAL_DASH_STEP) as usize + 1).min(n_letters);
                    let lit = if shown == n_letters {
                        (approach(game, side) * n_letters as f32) as usize
                    } else {
                        0
                    };
                    for (j, &letter) in letters.iter().take(shown).enumerate() {
                        let color = if j + 1 == shown && shown < n_letters {
                            white
                        } else if j < lit {
                            accent
                        } else {
                            dim
                        };
                        dash(letter, color);
                    }
                    continue;
                }
                // colpo: si accende, nell'ultima parte lampeggia
                if l.t >= SPECIAL_BLINK && (l.t * 7.5) as i64 % 2 == 1 {
                    continue;
                }
                let color = if l.t < SPECIAL_WHITE { white } else { accent };
                if l.t < SPECIAL_DASH_LIT {
                    for &letter in &letters {
                        dash(letter, color);
                    }
                }
                if l.t < SPECIAL_BLOCK {
                    for &(x0, x1) in &letters {
                        draw_rectangle(cx + x0, y - th / 2.0, x1 - x0, th, white);
                    }
                } else {
                    r.text_centered(&title, font, size, cx, y, 0.0, color);
                }
                let tw = r.text_width(&title, font, size);
                boxes[side] = Some(Rect::new(cx - tw / 2.0, y - size / 2.0, tw, size));
            }
        }

        if let Some((text, t)) = &self.label {
            // dall'accensione: riga che si allarga, immagine che si apre, ferma, che si richiude,
            // riga che si stringe, puntino
            let e = LABEL_SECONDS - t;
            let close = LABEL_SECONDS - 2.0 * CRT_STEP - CRT_DOT;
            let (open, line) = if e < CRT_STEP {
                (0.0, e / CRT_STEP)
            } else if e < 2.0 * CRT_STEP {
                ((e - CRT_STEP) / CRT_STEP, 1.0)
            } else if e < close {
                (1.0, 1.0)
            } else if e < close + CRT_STEP {
                (1.0 - (e - close) / CRT_STEP, 1.0)
            } else {
                (0.0, (1.0 - (e - close - CRT_STEP) / CRT_STEP).max(0.0))
            };
            let font = &app.assets.font_text;
            // in alto sotto i punteggi, nella stessa posizione del MiSTer (LABEL_MID = 46 su 240,
            // riquadro alto 20 pixel arcade e largo quanto la scritta con 4 pixel di margine per lato)
            let y = 46.0 * u;
            let bw = r.text_width(text, font, r.text_1x()) + 8.0 * u;
            let bh = 20.0 * u;
            let back = Rect::new(w / 2.0 - bw / 2.0, y - bh / 2.0, bw, bh);
            if open > 0.0 {
                // il riquadro nero, la scritta e, fuori dalla fascia aperta, di nuovo il nero; durante
                // l'apertura e la chiusura i bordi della fascia sono bianchi
                let band = (back.h * open as f32).max(2.0 * u);
                let top = y - band / 2.0;
                draw_rectangle(back.x, back.y, back.w, back.h, BLACK);
                r.text_centered(text, font, r.text_1x(), w / 2.0, y, 0.0, accent);
                draw_rectangle(back.x, back.y, back.w, top - back.y, BLACK);
                draw_rectangle(back.x, top + band, back.w, back.bottom() - top - band, BLACK);
                if open < 1.0 {
                    draw_rectangle(back.x, top, back.w, u, white);
                    draw_rectangle(back.x, top + band - u, back.w, u, white);
                }
                boxes[2] = Some(back);
            } else if line > 0.0 {
                let lw = (back.w * line as f32).max(2.0 * u);
                draw_rectangle(w / 2.0 - lw / 2.0, y - u, lw, 2.0 * u, white);
            } else {
                draw_rectangle(w / 2.0 - u, y - u, 2.0 * u, 2.0 * u, white);
            }
        }

        // palla e scia stanno sopra alle scritte: si ridisegnano solo quando ne toccano una, così
        // nel bullet time restano sfocate con il resto del campo finché non ci passano sopra
        let d = to_f32(game.ball.radius) * 3.0; // anche il rombo del RISING e la testa della cometa
        let near = |(x, y): (f32, f32)| {
            let at = Rect::new(x + shake - d / 2.0, r.screen_y(y) - d / 2.0, d, d);
            boxes.iter().flatten().any(|b| b.overlaps(&at))
        };
        // le racchette (con un po' di margine per i segni dei tipi) che toccano una scritta
        for (side, (&(x, y), pad)) in pos.iter().zip(&game.paddles).enumerate() {
            let (pw, ph) = (to_f32(pad.width) * 3.0, to_f32(pad.height));
            let at = Rect::new(x + shake - pw / 2.0, r.screen_y(y) - ph / 2.0, pw, ph);
            if boxes.iter().flatten().any(|b| b.overlaps(&at)) {
                self.draw_pad(app, game, (x, y), shake, side, None);
            }
        }
        if near(ball) || self.trail.iter().any(|&p| near(p)) {
            self.draw_trail(app, game, shake);
            self.draw_ball(app, game, ball, shake);
        }
    }
}

#[cfg(test)]
mod omega_tests {
    use super::*;
    use paddws_core::challenge::OMEGA;

    /// Il nome della forma nuova compare solo quando la racchetta di OMEGA cambia tipo, non
    /// all'inizio della partita, e sparisce dopo `MORPH_NAME_SECONDS`.
    #[test]
    fn the_new_form_is_named_only_at_a_transformation() {
        let params = paddws_core::Params::new(&paddws_core::Tuning::default());
        let mut m = Match::new_next_paddles(params, [OMEGA.loadout; 2], [None, Some(OMEGA.kind)], 3);
        m.set_morph(Side::Right);
        let mut fx = NextFx::new();
        fx.before_tick(&m);
        m.step(&paddws_core::Input::default());
        fx.after_tick(&m, Events::default(), 1.0);
        assert!(fx.morph_name.is_none() && fx.morph_flash[1] <= 0.0);
        // la racchetta era un'altra prima del tick: trasformazione
        fx.kinds_before[1] = Some(PaddleKind::Titan);
        fx.after_tick(&m, Events::default(), 1.0);
        assert_eq!(fx.morph_name, Some((OMEGA.kind, 1, MORPH_NAME_SECONDS)));
        assert_eq!(fx.morph_flash[1], MORPH_FLASH_SECONDS);
        fx.update(MORPH_NAME_SECONDS - 0.01);
        assert!(fx.morph_name.is_some());
        fx.update(0.02);
        assert!(fx.morph_name.is_none());
    }

    /// ARCADE: il doppio clic su USE a riserva vuota avvia l'animazione del gettone (0,5 s).
    #[test]
    fn arcade_double_click_triggers_coin_animation() {
        let params = paddws_core::Params::new(&paddws_core::Tuning::default());
        let loadout = [Bonus::Smash, Bonus::Teleport, Bonus::Slow];
        let mut m = Match::new_next_paddles(params, [loadout; 2], [Some(PaddleKind::Arcade), None], 7);
        m.serve_timer = 0;
        let mut fx = NextFx::new();
        let mut press = paddws_core::Input::default();
        press.players[0].activate = true;
        // primo clic: apre la finestra, nessun gettone
        fx.before_tick(&m);
        let ev1 = m.step(&press);
        fx.after_tick(&m, ev1, 1.0);
        assert!(fx.coin[0].is_none());
        // secondo clic: chiama il bonus e fa partire l'animazione del gettone
        fx.before_tick(&m);
        let ev2 = m.step(&press);
        fx.after_tick(&m, ev2, 1.0);
        assert_eq!(fx.coin[0], Some(0.0));
        fx.update(f64::from(paddle_ui::COIN_SECONDS) - 0.01);
        assert!(fx.coin[0].is_some());
        fx.update(0.02);
        assert!(fx.coin[0].is_none());
    }

    /// TELEPORT: il salto termina sempre prima che la palla arrivi alla racchetta, anche in dash
    /// normale (0,25) e in dash lungo del RUSH (0,344).
    #[test]
    fn teleport_warp_finishes_before_ball_reaches_dashed_paddle() {
        for pad in [20.0 / 320.0, 80.0 / 320.0, 110.0 / 320.0] {
            // appena passata la metà campo: inizia l'affondo, non ancora uscita
            let (s0, o0) = warp_progress(0.49, pad);
            assert!(s0 > 0.0 && o0 == 0.0);
            // ben prima che la palla arrivi alla racchetta: salto già completato
            let margin = (0.5 - pad) * 0.25;
            let (s1, o1) = warp_progress(pad + margin, pad);
            assert_eq!((s1, o1), (1.0, 1.0), "pad={pad}");
        }
    }
}
