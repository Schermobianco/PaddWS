//! Sequenza "attract" in stile cabinato anni '80: auto-test, strisce, logo, titolo.
//!
//! Tempi, posizioni e bitmap vengono da `assets/attract/` (tools/gen_attract_assets.py),
//! gli stessi del core MiSTer. Tutto è definito su uno schermo virtuale 320x240 e
//! ingrandito di altezza/240 intorno al centro del campo; le strisce arrivano ai bordi
//! anche sugli schermi più larghi. Dopo il titolo e la classifica viene la demo di gioco
//! (`scenes::Demo`), di cui qui ci sono le scritte sovrapposte.

use std::collections::HashMap;

use macroquad::prelude::*;
use paddws_core::Event;
use serde::Deserialize;

use crate::render::Renderer;

const FRAME: f64 = 1.0 / 60.0;
const VW: f32 = 320.0;
const VH: f32 = 240.0;

#[derive(Deserialize)]
struct Spec {
    colors: Colors,
    frames: Frames,
    boot: Boot,
    stripes: Stripes,
    logo: Logo,
    ws: Ws,
    title: Title,
    demo: Demo,
    game_over: GameOver,
}

#[derive(Deserialize)]
struct Colors {
    yellow: [u8; 3],
    black: [u8; 3],
    white: [u8; 3],
    phosphor: [u8; 3],
}

#[derive(Deserialize)]
struct Frames {
    boot: u32,
    stripes: u32,
    logo: u32,
    title: u32,
    demo: u32,
    game_over: u32,
}

#[derive(Deserialize)]
struct Boot {
    lines: Vec<Option<String>>,
    x: f32,
    y: f32,
    line_step: f32,
    line_frames: u32,
    cursor: [f32; 2],
    cursor_period: u32,
    grid_from: u32,
    grid_step: f32,
}

#[derive(Deserialize)]
struct Stripes {
    rows: Vec<f32>,
    height: f32,
    left_end: f32,
    right_start: f32,
    start_step: u32,
    slide: Vec<u32>,
}

#[derive(Deserialize)]
struct Logo {
    x: f32,
    y: f32,
    wipe_frames: u32,
    flash_frames: u32,
}

#[derive(Deserialize)]
struct Ws {
    x: f32,
    y: f32,
    off: Vec<[u32; 2]>,
}

#[derive(Deserialize)]
struct Title {
    label_y: f32,
    label_scale: f32,
    credit_y: f32,
    copyright_y: f32,
    blink_period: u32,
    blink_on: u32,
    label_from: u32,
    ball: BallSpec,
}

#[derive(Deserialize)]
struct BallSpec {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    size: f32,
}

#[derive(Deserialize)]
struct Demo {
    /// riga della scritta a scala 2 al centro
    label_y: f32,
    /// crediti: dal bordo sinistro e dall'alto (dal basso se in alto ci sono le riserve di NEXT)
    credit_x: f32,
    credit_y: f32,
}

#[derive(Deserialize)]
struct GameOver {
    label_y: f32,
    /// riga di chi ha vinto, sotto GAME OVER
    winner_y: f32,
}

/// Bitmap a 1 bit: texture per il disegno e pixel per i rimbalzi della pallina.
struct Bitmap {
    texture: Texture2D,
    image: Image,
}

impl Bitmap {
    fn width(&self) -> f32 {
        self.image.width as f32
    }

    fn height(&self) -> f32 {
        self.image.height as f32
    }

    fn lit(&self, x: i32, y: i32) -> bool {
        x >= 0
            && y >= 0
            && (x as u32) < self.image.width as u32
            && (y as u32) < self.image.height as u32
            && self.image.get_pixel(x as u32, y as u32).a > 0.5
    }
}

macro_rules! bitmaps {
    ($($name:literal),* $(,)?) => {
        &[$(($name, include_bytes!(concat!("../../../assets/attract/", $name, ".png")))),*]
    };
}

const BITMAPS: &[(&str, &[u8])] = bitmaps!(
    "logo",
    "ws",
    "insert_coin",
    "press_start",
    "credit",
    "free_play",
    "copyright",
    "game_over",
    "p1_wins",
    "p2_wins",
    "you_win",
    "cpu_wins",
    "perfect",
    "mode_classic",
    "mode_evo",
    "mode_next",
    "mode_challenge",
    "boot_0",
    "boot_2",
    "boot_3",
    "boot_4",
    "boot_5",
    "digit_0",
    "digit_1",
    "digit_2",
    "digit_3",
    "digit_4",
    "digit_5",
    "digit_6",
    "digit_7",
    "digit_8",
    "digit_9",
);

/// Spec e bitmap della sequenza, caricati una volta.
pub struct AttractArt {
    spec: Spec,
    bitmaps: HashMap<&'static str, Bitmap>,
}

impl AttractArt {
    pub fn load() -> Self {
        let spec: Spec = serde_json::from_str(include_str!("../../../assets/attract/attract.json"))
            .expect("assets/attract/attract.json incluso nell'eseguibile");
        let bitmaps = BITMAPS
            .iter()
            .map(|(name, bytes)| {
                let image = Image::from_file_with_format(bytes, Some(ImageFormat::Png)).expect("bitmap PNG inclusa");
                let texture = Texture2D::from_image(&image);
                texture.set_filter(FilterMode::Nearest);
                (*name, Bitmap { texture, image })
            })
            .collect();
        Self { spec, bitmaps }
    }

    fn bm(&self, name: &str) -> &Bitmap {
        &self.bitmaps[name]
    }

    /// Durata del "GAME OVER" in secondi.
    pub fn game_over_seconds(&self) -> f64 {
        self.spec.frames.game_over as f64 * FRAME
    }

    /// Durata della demo in frame a 60 Hz.
    pub fn demo_frames(&self) -> u32 {
        self.spec.frames.demo
    }
}

fn rgb(c: [u8; 3]) -> Color {
    Color::from_rgba(c[0], c[1], c[2], 255)
}

/// Schermo virtuale 320x240 ingrandito sul campo, intorno al suo centro.
struct View {
    k: f32,
    cx: f32,
    left: f32,
    right: f32,
}

impl View {
    fn of(r: &Renderer) -> Self {
        let k = r.world_h / VH;
        let half = r.world_w / 2.0 / k;
        Self {
            k,
            cx: r.world_w / 2.0,
            left: VW / 2.0 - half,
            right: VW / 2.0 + half,
        }
    }

    fn rect(&self, x: f32, y: f32, w: f32, h: f32, color: Color) {
        draw_rectangle(
            self.cx + (x - VW / 2.0) * self.k,
            y * self.k,
            w * self.k,
            h * self.k,
            color,
        );
    }

    fn bitmap(&self, bm: &Bitmap, x: f32, y: f32, scale: f32, color: Color) {
        self.bitmap_rows(bm, x, y, scale, color, bm.height());
    }

    fn bitmap_rows(&self, bm: &Bitmap, x: f32, y: f32, scale: f32, color: Color, rows: f32) {
        draw_texture_ex(
            &bm.texture,
            self.cx + (x - VW / 2.0) * self.k,
            y * self.k,
            color,
            DrawTextureParams {
                dest_size: Some(vec2(bm.width() * scale * self.k, rows * scale * self.k)),
                source: Some(Rect::new(0.0, 0.0, bm.width(), rows)),
                ..Default::default()
            },
        );
    }
}

/// Scritte del titolo che dipendono dai crediti.
#[derive(Clone, Copy)]
pub struct Hud {
    /// None = Free Play
    pub credits: Option<u8>,
}

impl Hud {
    fn label(&self) -> &'static str {
        match self.credits {
            Some(0) => "insert_coin",
            _ => "press_start",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Phase {
    Boot,
    Stripes,
    Logo,
    Title,
}

pub struct Attract {
    pub phase: Phase,
    frame: u32,
    acc: f64,
    ball: [f32; 4],
    /// suoni già suonati nella fase corrente (uno per bit)
    fired: u64,
}

impl Attract {
    /// `self_test`: inizia con l'auto-test (solo all'accensione).
    pub fn new(art: &AttractArt, self_test: bool) -> Self {
        let b = &art.spec.title.ball;
        Self {
            phase: if self_test { Phase::Boot } else { Phase::Stripes },
            frame: 0,
            acc: 0.0,
            ball: [b.x, b.y, b.vx, b.vy],
            fired: 0,
        }
    }

    fn enter(&mut self, art: &AttractArt, phase: Phase) {
        self.phase = phase;
        self.frame = 0;
        self.fired = 0;
        let b = &art.spec.title.ball;
        self.ball = [b.x, b.y, b.vx, b.vy];
    }

    fn once(&mut self, bit: u32, event: Event, sounds: &mut Vec<Event>) {
        if self.fired & (1 << bit) == 0 {
            self.fired |= 1 << bit;
            sounds.push(event);
        }
    }

    /// Avanza la sequenza del tempo reale `dt`; restituisce i suoni da riprodurre.
    pub fn update(&mut self, art: &AttractArt, r: &Renderer, hud: Hud, dt: f64) -> Vec<Event> {
        let mut sounds = Vec::new();
        self.acc += dt.min(0.25);
        while self.acc >= FRAME {
            self.acc -= FRAME;
            self.step(art, r, hud, &mut sounds);
        }
        sounds
    }

    /// Un frame a 60 Hz.
    pub fn step(&mut self, art: &AttractArt, r: &Renderer, hud: Hud, sounds: &mut Vec<Event>) {
        let s = &art.spec;
        let f = self.frame;
        match self.phase {
            Phase::Boot => {
                if f < s.boot.grid_from {
                    let shown = (f / s.boot.line_frames + 1).min(s.boot.lines.len() as u32);
                    for i in 0..shown {
                        if s.boot.lines[i as usize].is_some() {
                            self.once(i, if i == 0 { Event::Hit } else { Event::Wall }, sounds);
                        }
                    }
                } else {
                    self.once(31, Event::Boost, sounds);
                }
            }
            Phase::Stripes => {
                let last = s.stripes.slide.len() as u32 - 1;
                for i in 0..6 {
                    if f >= i * s.stripes.start_step + last {
                        self.once(i, Event::Hit, sounds);
                    }
                }
            }
            Phase::Logo => {
                if f >= s.logo.wipe_frames {
                    self.once(0, Event::Boost, sounds);
                }
            }
            Phase::Title => {
                if self.step_ball(art, r, hud) {
                    sounds.push(Event::Wall);
                }
            }
        }
        self.frame += 1;
        let duration = match self.phase {
            Phase::Boot => s.frames.boot,
            Phase::Stripes => s.frames.stripes,
            Phase::Logo => s.frames.logo,
            Phase::Title => s.frames.title,
        };
        if self.frame >= duration {
            let next = match self.phase {
                Phase::Boot | Phase::Title => Phase::Stripes,
                Phase::Stripes => Phase::Logo,
                Phase::Logo => Phase::Title,
            };
            self.enter(art, next);
        }
    }

    // ----------------------------------------------------------------- pallina

    fn label_visible(&self, art: &AttractArt) -> bool {
        let t = &art.spec.title;
        self.frame > t.label_from && self.frame % t.blink_period < t.blink_on
    }

    /// Il pixel virtuale (x, y) del titolo è nero? Strisce, logo e scritte, esclusa la pallina.
    fn black(&self, art: &AttractArt, hud: Hud, x: i32, y: i32) -> bool {
        let s = &art.spec;
        let (fx, fy) = (x as f32, y as f32);
        for &row in &s.stripes.rows {
            if fy >= row && fy < row + s.stripes.height && (fx < s.stripes.left_end || fx >= s.stripes.right_start) {
                let ws = art.bm("ws");
                return !ws.lit(x - s.ws.x as i32, y - s.ws.y as i32); // "WS" è giallo
            }
        }
        if art.bm("logo").lit(x - s.logo.x as i32, y - s.logo.y as i32) {
            return true;
        }
        let t = &s.title;
        if self.label_visible(art) && centered_lit(art.bm(hud.label()), t.label_scale, t.label_y, x, y) {
            return true;
        }
        if credit_line(art, hud)
            .iter()
            .any(|(bm, x0)| art.bm(bm).lit(x - *x0 as i32, y - t.credit_y as i32))
        {
            return true;
        }
        centered_lit(art.bm("copyright"), 1.0, t.copyright_y, x, y)
    }

    fn blocked(&self, art: &AttractArt, view: &View, hud: Hud, x: f32, y: f32) -> bool {
        let size = art.spec.title.ball.size;
        let (ix, iy) = (x.round() as i32, y.round() as i32);
        if (ix as f32) < view.left.ceil() || ix as f32 > view.right.floor() - size || iy < 0 || iy as f32 > VH - size {
            return true; // i bordi dello schermo
        }
        let n = size as i32;
        (0..n).any(|dy| (0..n).any(|dx| self.black(art, hud, ix + dx, iy + dy)))
    }

    /// La pallina rimbalza contro i bordi e contro qualunque pixel nero, un asse alla volta.
    fn step_ball(&mut self, art: &AttractArt, r: &Renderer, hud: Hud) -> bool {
        let view = View::of(r);
        let [x, y, vx, vy] = self.ball;
        let size = art.spec.title.ball.size;
        if self.blocked(art, &view, hud, x, y) {
            // una scritta è comparsa sopra la pallina: la si lascia uscire
            let nx = (x + vx).clamp(view.left.ceil(), view.right.floor() - size);
            let ny = (y + vy).clamp(0.0, VH - size);
            self.ball = [nx, ny, vx, vy];
            return false;
        }
        let mut bounced = false;
        let (mut nx, mut nvx) = (x + vx, vx);
        if self.blocked(art, &view, hud, nx, y) {
            nx = x;
            nvx = -vx;
            bounced = true;
        }
        let (mut ny, mut nvy) = (y + vy, vy);
        if self.blocked(art, &view, hud, nx, ny) {
            ny = y;
            nvy = -vy;
            bounced = true;
        }
        self.ball = [nx, ny, nvx, nvy];
        bounced
    }

    // ------------------------------------------------------------------ disegno

    pub fn draw(&self, art: &AttractArt, r: &Renderer, hud: Hud) {
        let s = &art.spec;
        let view = View::of(r);
        let (yellow, black, white) = (rgb(s.colors.yellow), rgb(s.colors.black), rgb(s.colors.white));
        let f = self.frame;
        match self.phase {
            Phase::Boot => {
                r.fill(black);
                let b = &s.boot;
                if f < b.grid_from {
                    let shown = (f / b.line_frames + 1).min(b.lines.len() as u32) as usize;
                    let phosphor = rgb(s.colors.phosphor);
                    let mut cursor_x = b.x;
                    for (i, line) in b.lines.iter().take(shown).enumerate() {
                        cursor_x = b.x;
                        if let Some(name) = line {
                            let bm = art.bm(name);
                            view.bitmap(bm, b.x, b.y + i as f32 * b.line_step, 1.0, phosphor);
                            cursor_x = b.x + bm.width();
                        }
                    }
                    if (f / (b.cursor_period / 2)).is_multiple_of(2) {
                        let y = b.y + (shown - 1) as f32 * b.line_step;
                        view.rect(cursor_x + 2.0, y, b.cursor[0], b.cursor[1], phosphor);
                    }
                } else {
                    // reticolo di test dei vecchi cabinati
                    let mut x = (view.left / b.grid_step).floor() * b.grid_step;
                    while x <= view.right {
                        view.rect(x, 0.0, 1.0, VH, white);
                        x += b.grid_step;
                    }
                    let mut y = 0.0;
                    while y < VH {
                        view.rect(view.left, y, view.right - view.left, 1.0, white);
                        y += b.grid_step;
                    }
                    view.rect(view.left, VH - 1.0, view.right - view.left, 1.0, white);
                }
            }
            Phase::Stripes => {
                r.fill(yellow);
                let last = s.stripes.slide.len() - 1;
                let progress: Vec<f32> = (0..6)
                    .map(|i| {
                        let local = f.saturating_sub(i * s.stripes.start_step) as usize;
                        s.stripes.slide[local.min(last)] as f32 / 1000.0
                    })
                    .collect();
                draw_stripes(art, &view, &progress, black);
            }
            Phase::Logo => {
                r.fill(yellow);
                draw_stripes(art, &view, &[1.0; 6], black);
                view.bitmap(art.bm("ws"), s.ws.x, s.ws.y, 1.0, yellow);
                let logo = art.bm("logo");
                if f < s.logo.wipe_frames {
                    let rows = (logo.height() * f as f32 / s.logo.wipe_frames as f32).floor();
                    view.bitmap_rows(logo, s.logo.x, s.logo.y, 1.0, black, rows);
                    view.rect(s.logo.x, s.logo.y + rows + 1.0, logo.width(), 1.0, white); // il raster che scende
                } else {
                    view.bitmap(logo, s.logo.x, s.logo.y, 1.0, black);
                    if f < s.logo.wipe_frames + s.logo.flash_frames {
                        r.fill(white); // lampo
                    }
                }
            }
            Phase::Title => {
                let t = &s.title;
                r.fill(yellow);
                draw_stripes(art, &view, &[1.0; 6], black);
                if !s.ws.off.iter().any(|[a, b]| f >= *a && f < *b) {
                    view.bitmap(art.bm("ws"), s.ws.x, s.ws.y, 1.0, yellow);
                }
                view.bitmap(art.bm("logo"), s.logo.x, s.logo.y, 1.0, black);
                if self.label_visible(art) {
                    draw_centered(&view, art.bm(hud.label()), t.label_scale, t.label_y, black);
                }
                for (bm, x0) in credit_line(art, hud) {
                    view.bitmap(art.bm(bm), x0, t.credit_y, 1.0, black);
                }
                draw_centered(&view, art.bm("copyright"), 1.0, t.copyright_y, black);
                let size = t.ball.size;
                view.rect(self.ball[0].round(), self.ball[1].round(), size, size, black);
            }
        }
    }
}

/// Fine partita al centro, su un riquadro nero sopra la partita: con `title` (`game_over`, o
/// `perfect` quando un giocatore vince senza punti dell'avversario) quella scritta in bianco e,
/// sotto, chi ha vinto (`p1_wins`, `p2_wins`, `cpu_wins`; nessuno in singolo) nel colore
/// `winner_color`, su un riquadro largo come GAME OVER (come sul MiSTer); senza, solo chi ha
/// vinto, al posto di GAME OVER e nel colore `winner_color` (YOU WIN o PERFECT, o CPU WINS a un
/// livello perso della CHALLENGE, dove si può ancora continuare).
pub fn draw_game_over(art: &AttractArt, r: &Renderer, title: Option<&str>, winner: Option<&str>, winner_color: Color) {
    let s = &art.spec;
    let view = View::of(r);
    let (bm, label_color, win) = match (title, winner) {
        (None, Some(name)) => (art.bm(name), winner_color, None),
        _ => (art.bm(title.unwrap_or("game_over")), rgb(s.colors.white), winner.map(|name| art.bm(name))),
    };
    let wide = art.bm("game_over").width();
    let text_w = win.map_or(bm.width(), |b| b.width().max(wide));
    let bottom = if win.is_some() {
        s.game_over.winner_y
    } else {
        s.game_over.label_y
    };
    let (w, h) = (
        text_w * 2.0 + 12.0,
        bottom - s.game_over.label_y + bm.height() * 2.0 + 10.0,
    );
    view.rect(
        ((VW - w) / 2.0).round(),
        s.game_over.label_y - 5.0,
        w,
        h,
        rgb(s.colors.black),
    );
    draw_centered(&view, bm, 2.0, s.game_over.label_y, label_color);
    if let Some(b) = win {
        draw_centered(&view, b, 2.0, s.game_over.winner_y, winner_color);
    }
}

/// Scritte della demo, come nel core MiSTer: "CREDIT n" (o "FREE PLAY") in alto a sinistra, in
/// basso se `credits_bottom` (in NEXT in alto ci sono le riserve), e al centro un riquadro nero con
/// INSERT COIN o PRESS START a scala 2, che nella parte spenta del lampeggio mostra la modalità
/// (`mode_classic`, `mode_evo`, `mode_next`, `mode_challenge`). `frame`: frame della demo.
pub fn draw_demo_overlay(art: &AttractArt, r: &Renderer, hud: Hud, mode: &str, frame: u32, credits_bottom: bool) {
    let s = &art.spec;
    let view = View::of(r);
    let white = rgb(s.colors.white);
    let d = &s.demo;
    let parts: Vec<&str> = match hud.credits {
        None => vec!["free_play"],
        Some(n) => vec!["credit", DIGITS[n.min(9) as usize]],
    };
    let y = if credits_bottom {
        VH - d.credit_y - art.bm(parts[0]).height()
    } else {
        d.credit_y
    };
    let mut x = view.left.ceil() + d.credit_x;
    for p in parts {
        view.bitmap(art.bm(p), x, y, 1.0, white);
        x += art.bm(p).width();
    }
    let t = &s.title;
    let label = if frame % t.blink_period < t.blink_on {
        hud.label()
    } else {
        mode
    };
    let bm = art.bm(label);
    let w = bm.width() * 2.0;
    view.rect(((VW - w - 12.0) / 2.0).floor(), d.label_y - 4.0, w + 12.0, 24.0, rgb(s.colors.black));
    draw_centered(&view, bm, 2.0, d.label_y, white);
}

fn draw_stripes(art: &AttractArt, view: &View, progress: &[f32], color: Color) {
    let st = &art.spec.stripes;
    for (i, &row) in st.rows.iter().enumerate() {
        // la striscia sinistra arriva al bordo sinistro, la destra a quello destro
        let len_l = st.left_end - view.left;
        let right_edge = view.left + len_l * progress[i * 2];
        view.rect(right_edge - len_l, row, len_l, st.height, color);
        let len_r = view.right - st.right_start;
        let left_edge = view.right - len_r * progress[i * 2 + 1];
        view.rect(left_edge, row, len_r + 1.0, st.height, color);
    }
}

fn centered_x(bm: &Bitmap, scale: f32) -> f32 {
    ((VW - bm.width() * scale) / 2.0).round()
}

fn draw_centered(view: &View, bm: &Bitmap, scale: f32, y: f32, color: Color) {
    view.bitmap(bm, centered_x(bm, scale), y, scale, color);
}

fn centered_lit(bm: &Bitmap, scale: f32, y0: f32, x: i32, y: i32) -> bool {
    let x0 = centered_x(bm, scale) as i32;
    let s = scale as i32;
    x >= x0 && y >= y0 as i32 && bm.lit((x - x0) / s, (y - y0 as i32) / s)
}

/// "CREDIT n" (o "FREE PLAY") centrato: bitmap e posizione x di ogni pezzo.
fn credit_line(art: &AttractArt, hud: Hud) -> Vec<(&'static str, f32)> {
    let parts: Vec<&'static str> = match hud.credits {
        None => vec!["free_play"],
        Some(n) => vec!["credit", DIGITS[n.min(9) as usize]],
    };
    let total: f32 = parts.iter().map(|p| art.bm(p).width()).sum();
    let mut x = ((VW - total) / 2.0).round();
    parts
        .into_iter()
        .map(|p| {
            let x0 = x;
            x += art.bm(p).width();
            (p, x0)
        })
        .collect()
}

const DIGITS: [&str; 10] = [
    "digit_0", "digit_1", "digit_2", "digit_3", "digit_4", "digit_5", "digit_6", "digit_7", "digit_8", "digit_9",
];
