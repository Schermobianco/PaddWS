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
    /// frame di schermo nero dopo la chiusura del GAME OVER
    black_frames: u32,
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

    /// Secondi di schermo nero dopo la chiusura del GAME OVER (`draw_crt_close`), prima di passare
    /// oltre: si aggiungono a `game_over_seconds` solo quando lo schermo si chiude.
    pub fn game_over_black_seconds(&self) -> f64 {
        self.spec.game_over.black_frames as f64 * FRAME
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
        self.bitmap_part(bm, x, y, scale, color, Rect::new(0.0, 0.0, bm.width(), rows));
    }

    /// Il pezzo `src` della bitmap (in pixel della bitmap), con l'angolo in alto a sinistra del
    /// pezzo in (x, y).
    fn bitmap_part(&self, bm: &Bitmap, x: f32, y: f32, scale: f32, color: Color, src: Rect) {
        draw_texture_ex(
            &bm.texture,
            self.cx + (x - VW / 2.0) * self.k,
            y * self.k,
            color,
            DrawTextureParams {
                dest_size: Some(vec2(src.w * scale * self.k, src.h * scale * self.k)),
                source: Some(src),
                ..Default::default()
            },
        );
    }

    /// Punto del campo (coordinate di disegno) nello schermo virtuale.
    fn world_to_view(&self, p: Vec2) -> Vec2 {
        vec2((p.x - self.cx) / self.k + VW / 2.0, p.y / self.k)
    }
}

/// Lettere di una bitmap di testo: colonne (da, a) di pixel accesi separate da colonne vuote.
fn letters(bm: &Bitmap) -> Vec<(f32, f32)> {
    let (w, h) = (bm.width() as i32, bm.height() as i32);
    let mut out = Vec::new();
    let mut start = None;
    for x in 0..=w {
        let lit = x < w && (0..h).any(|y| bm.lit(x, y));
        match (lit, start) {
            (true, None) => start = Some(x),
            (false, Some(s)) => {
                out.push((s as f32, x as f32));
                start = None;
            }
            _ => {}
        }
    }
    out
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

/// Scritte e riquadro della fine partita, nello schermo virtuale.
struct Over<'a> {
    label: &'a Bitmap,
    label_color: Color,
    /// riga di chi ha vinto, sotto la prima
    win: Option<&'a Bitmap>,
    back: Rect,
}

impl<'a> Over<'a> {
    fn of(art: &'a AttractArt, title: Option<&str>, winner: Option<&str>, winner_color: Color) -> Self {
        let s = &art.spec;
        let (label, label_color, win) = match (title, winner) {
            (None, Some(name)) => (art.bm(name), winner_color, None),
            _ => (art.bm(title.unwrap_or("game_over")), rgb(s.colors.white), winner.map(|name| art.bm(name))),
        };
        let wide = art.bm("game_over").width();
        let text_w = win.map_or(label.width(), |b| b.width().max(wide));
        let bottom = if win.is_some() {
            s.game_over.winner_y
        } else {
            s.game_over.label_y
        };
        let (w, h) = (
            text_w * 2.0 + 12.0,
            bottom - s.game_over.label_y + label.height() * 2.0 + 10.0,
        );
        Self {
            label,
            label_color,
            win,
            back: Rect::new(((VW - w) / 2.0).round(), s.game_over.label_y - 5.0, w, h),
        }
    }
}

// Fine partita animata, in frame a 60 Hz dall'inizio (vedi `draw_game_over_anim`).
/// GAME OVER: trattini della mezzeria spenti dall'alto (`NET_OFF` frame), poi racchette che si
/// accorciano (`PADS_OFF`); la scritta si scrive da `TYPE_AT`, una lettera ogni `TYPE_STEP`, chi ha
/// vinto `WIN_GAP` dopo, una lettera ogni `WIN_STEP`; alla fine lo schermo si chiude in
/// `CLOSE_FRAMES` (si stringe, riga, puntino).
const NET_OFF: f64 = 48.0;
const PADS_OFF: f64 = 12.0;
const TYPE_AT: f64 = 56.0;
const TYPE_STEP: f64 = 5.0;
const WIN_GAP: f64 = 10.0;
const WIN_STEP: f64 = 3.0;
const CLOSE_SQUASH: f64 = 8.0;
const CLOSE_LINE: f64 = 8.0;
const CLOSE_DOT: f64 = 6.0;
const CLOSE_FRAMES: f64 = CLOSE_SQUASH + CLOSE_LINE + CLOSE_DOT;
/// PERFECT: scala del timbro nei primi frame (`STAMP_HOLD` frame ciascuna), scossa del riquadro,
/// chi ha vinto da `STAMP_WIN`, riflesso da `GLINT_AT` ogni `GLINT_PERIOD` frame.
const STAMP: [f32; 3] = [6.0, 4.5, 3.0];
const STAMP_HOLD: f64 = 4.0;
const STAMP_SHAKE: [(f32, f32); 8] = [
    (3.0, 0.0),
    (-3.0, 2.0),
    (3.0, -2.0),
    (-2.0, 1.0),
    (2.0, -1.0),
    (-1.0, 0.0),
    (1.0, 0.0),
    (0.0, 0.0),
];
const STAMP_WIN: f64 = 28.0;
const GLINT_AT: f64 = 48.0;
const GLINT_PERIOD: f64 = 60.0;
/// YOU WIN: la palla arriva sulla prima lettera in `HOP_FIRST` frame, poi un salto ogni `HOP`;
/// la lettera colpita si abbassa per `HOP_PRESS` frame; finiti i salti la scritta lampeggia.
const HOP_FIRST: f64 = 14.0;
const HOP: f64 = 6.0;
const HOP_PRESS: f64 = 3.0;

/// GAME OVER senza campo da spegnere (il continue scaduto della CHALLENGE): secondi da aggiungere al
/// tempo di `draw_game_over_anim` perché la scritta parta subito, come CPU WINS.
pub const TYPE_LEAD: f64 = (TYPE_AT - 12.0) * FRAME;

/// GAME OVER: quanto della mezzeria è già spento, dall'alto (0..1), a `t` secondi dall'inizio.
pub fn net_off(t: f64) -> f32 {
    (t / FRAME / NET_OFF).clamp(0.0, 1.0) as f32
}

/// GAME OVER: quanto resta delle racchette (1..0) a `t` secondi dall'inizio.
pub fn pads_left(t: f64) -> f32 {
    (1.0 - (t / FRAME - NET_OFF) / PADS_OFF).clamp(0.0, 1.0) as f32
}

/// GAME OVER: lo schermo si chiude come un vecchio televisore negli ultimi frame della fine
/// partita lunga `total` secondi (`t` dall'inizio): il nero sale e scende verso il centro lasciando
/// una fascia bordata di bianco, la fascia diventa una riga che si stringe, poi un puntino.
pub fn draw_crt_close(r: &Renderer, t: f64, total: f64) {
    let f = (t - total) / FRAME + CLOSE_FRAMES;
    if f < 0.0 {
        return;
    }
    let (w, h) = (r.world_w, r.world_h);
    let u = h / VH;
    if f < CLOSE_SQUASH {
        let band = (h * (1.0 - f / CLOSE_SQUASH) as f32).max(2.0 * u);
        let top = (h - band) / 2.0;
        draw_rectangle(0.0, 0.0, w, top, BLACK);
        draw_rectangle(0.0, top + band, w, h - top - band, BLACK);
        draw_rectangle(0.0, top, w, u, WHITE);
        draw_rectangle(0.0, top + band - u, w, u, WHITE);
        return;
    }
    draw_rectangle(0.0, 0.0, w, h, BLACK);
    let f = f - CLOSE_SQUASH;
    if f < CLOSE_LINE {
        let lw = (w * (1.0 - f / CLOSE_LINE) as f32).max(2.0 * u);
        draw_rectangle((w - lw) / 2.0, h / 2.0 - u, lw, 2.0 * u, WHITE);
    } else if f < CLOSE_LINE + CLOSE_DOT {
        draw_rectangle(w / 2.0 - u, h / 2.0 - u, 2.0 * u, 2.0 * u, WHITE);
    }
}

/// Fine partita al centro, su un riquadro nero sopra la partita, a `t` secondi dall'inizio. Con
/// `title` (`game_over`, o `perfect` quando un giocatore vince senza punti dell'avversario) quella
/// scritta in bianco e, sotto, chi ha vinto (`p1_wins`, `p2_wins`, `cpu_wins`; nessuno in singolo) nel
/// colore `winner_color`, su un riquadro largo come GAME OVER (come sul MiSTer); senza, solo chi ha
/// vinto, al posto di GAME OVER e nel colore `winner_color` (YOU WIN o PERFECT, o CPU WINS a un
/// livello perso della CHALLENGE, dove si può ancora continuare). Le animazioni:
/// - GAME OVER: dopo lo spegnimento del campo (`net_off`, `pads_left`, li fa la partita) GAME OVER e
///   chi ha vinto si scrivono con un cursore; lo schermo poi si chiude (`draw_crt_close`);
/// - PERFECT si stampa enorme e il riquadro trema; poi ogni secondo un riflesso di colore `accent`
///   attraversa le lettere (bianco se PERFECT è già di quel colore);
/// - YOU WIN: la palla, larga `ball`, parte da `from` (la racchetta di chi ha vinto, coordinate di
///   disegno) e salta da una lettera all'altra accendendole, poi la scritta lampeggia;
/// - CPU WINS (livello perso della CHALLENGE) si scrive con il cursore, subito.
#[allow(clippy::too_many_arguments)]
pub fn draw_game_over_anim(
    art: &AttractArt,
    r: &Renderer,
    title: Option<&str>,
    winner: Option<&str>,
    winner_color: Color,
    accent: Color,
    t: f64,
    (from, ball): (Vec2, f32),
) {
    let s = &art.spec;
    let view = View::of(r);
    let o = Over::of(art, title, winner, winner_color);
    let (white, black) = (rgb(s.colors.white), rgb(s.colors.black));
    let f = t / FRAME;
    let (ly, wy) = (s.game_over.label_y, s.game_over.winner_y);
    let lx = centered_x(o.label, 2.0);
    let perfect = title == Some("perfect") || (title.is_none() && winner == Some("perfect"));
    let hop = title.is_none() && winner == Some("you_win");
    if perfect {
        // timbro: enorme nei primi frame, poi il riquadro trema e si accende il bordo
        if let Some(&scale) = STAMP.get((f / STAMP_HOLD) as usize) {
            let bm = o.label;
            let y = ly + bm.height() - bm.height() * scale / 2.0;
            view.bitmap(bm, ((VW - bm.width() * scale) / 2.0).round(), y, scale, o.label_color);
            return;
        }
        let stamped = STAMP.len() as f64 * STAMP_HOLD;
        let (dx, dy) = STAMP_SHAKE.get((f - stamped) as usize).copied().unwrap_or_default();
        let b = o.back;
        view.rect(b.x + dx, b.y + dy, b.w, b.h, black);
        if f < stamped + 5.0 {
            for (x, y, w, h) in [(0.0, 0.0, b.w, 1.0), (0.0, b.h - 1.0, b.w, 1.0), (0.0, 0.0, 1.0, b.h), (b.w - 1.0, 0.0, 1.0, b.h)] {
                view.rect(b.x + dx + x, b.y + dy + y, w, h, accent);
            }
        }
        view.bitmap(o.label, lx + dx, ly + dy, 2.0, o.label_color);
        // riflesso: una banda in diagonale, colonna per colonna della bitmap
        if f >= GLINT_AT {
            let g = ((f - GLINT_AT) % GLINT_PERIOD) as f32 * 4.0 - 20.0;
            let shine = if o.label_color == accent { white } else { accent };
            for col in 0..o.label.width() as i32 {
                // pixel (col, row) nella banda se 0 <= 2 col + 2 row - g < 12
                let r0 = ((g - 2.0 * col as f32) / 2.0).ceil().max(0.0);
                let r1 = ((g + 12.0 - 2.0 * col as f32) / 2.0).ceil().min(o.label.height());
                if r1 > r0 {
                    let src = Rect::new(col as f32, r0, 1.0, r1 - r0);
                    view.bitmap_part(o.label, lx + dx + 2.0 * col as f32, ly + dy + 2.0 * r0, 2.0, shine, src);
                }
            }
        }
        if let (Some(win), true) = (o.win, f >= STAMP_WIN) {
            draw_centered(&view, win, 2.0, wy + dy, winner_color);
        }
        return;
    }
    if hop {
        view.rect(o.back.x, o.back.y, o.back.w, o.back.h, black);
        let bm = o.label;
        let spans = letters(bm);
        let n = spans.len();
        // dal lato di chi ha vinto
        let start = view.world_to_view(from);
        let rtl = start.x > VW / 2.0;
        let order: Vec<usize> = if rtl { (0..n).rev().collect() } else { (0..n).collect() };
        let lit_at = |i: usize| HOP_FIRST + order.iter().position(|&j| j == i).unwrap_or(0) as f64 * HOP;
        let end = HOP_FIRST + (n.max(1) - 1) as f64 * HOP;
        let blink = f > end + 14.0 && f < end + 62.0 && ((f - end - 14.0) / 6.0) as i64 % 2 == 0;
        let dim = Color { a: 0.3, ..o.label_color };
        for (i, &(c0, c1)) in spans.iter().enumerate() {
            let since = f - lit_at(i);
            let (color, dy) = if since < 0.0 {
                (dim, 0.0)
            } else if blink {
                (if o.label_color == white { dim } else { white }, 0.0)
            } else {
                (o.label_color, if since < HOP_PRESS { 1.0 } else { 0.0 })
            };
            let src = Rect::new(c0, 0.0, c1 - c0, bm.height());
            view.bitmap_part(bm, lx + 2.0 * c0, ly + dy, 2.0, color, src);
        }
        // la palla: dalla racchetta alla prima lettera, poi un salto per lettera, poi via
        let d = ball / view.k;
        let top = ly - d;
        let center = |i: usize| lx + (spans[i].0 + spans[i].1) - d / 2.0;
        if n > 0 {
            let (bx, by) = if f < HOP_FIRST {
                let u = (f / HOP_FIRST) as f32;
                let x1 = center(order[0]);
                (start.x - d / 2.0 + (x1 - start.x + d / 2.0) * u, start.y - d / 2.0 + (top - start.y + d / 2.0) * u - 80.0 * u * (1.0 - u))
            } else if f < end {
                let j = ((f - HOP_FIRST) / HOP) as usize;
                let u = (((f - HOP_FIRST) % HOP) / HOP) as f32;
                let (xa, xb) = (center(order[j]), center(order[(j + 1).min(n - 1)]));
                (xa + (xb - xa) * u, top - 72.0 * u * (1.0 - u))
            } else {
                let k = (f - end) as f32;
                let dir = if rtl { -1.0 } else { 1.0 };
                (center(order[n - 1]) + dir * 4.0 * k, top - 6.0 * k + 0.6 * k * k)
            };
            if by < VH {
                view.rect(bx.round(), by.round(), d, d, white);
            }
        }
        return;
    }
    // GAME OVER (dopo lo spegnimento del campo) o CPU WINS (subito): si scrive con il cursore
    let at = if title.is_some() { TYPE_AT } else { 12.0 };
    if f < at {
        return;
    }
    view.rect(o.back.x, o.back.y, o.back.w, o.back.h, black);
    let spans = letters(o.label);
    let shown = (((f - at) / TYPE_STEP) as usize + 1).min(spans.len());
    let upto = spans.get(shown.max(1) - 1).map_or(0.0, |s| s.1);
    view.bitmap_part(o.label, lx, ly, 2.0, o.label_color, Rect::new(0.0, 0.0, upto, o.label.height()));
    let mut cursor = (lx + 2.0 * upto + 2.0, ly);
    let mut done = shown == spans.len();
    if let (Some(win), true) = (o.win, done) {
        let at = at + spans.len() as f64 * TYPE_STEP + WIN_GAP;
        let wl = letters(win);
        done = false;
        if f >= at {
            let shown = (((f - at) / WIN_STEP) as usize + 1).min(wl.len());
            let upto = wl.get(shown.max(1) - 1).map_or(0.0, |s| s.1);
            let wx = centered_x(win, 2.0);
            view.bitmap_part(win, wx, wy, 2.0, winner_color, Rect::new(0.0, 0.0, upto, win.height()));
            cursor = (wx + 2.0 * upto + 2.0, wy);
            done = shown == wl.len();
        }
    }
    // cursore pieno mentre scrive, poi lampeggia
    if !done || (f / 15.0) as i64 % 2 == 0 {
        view.rect(cursor.0, cursor.1, 8.0, o.label.height() * 2.0, white);
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
