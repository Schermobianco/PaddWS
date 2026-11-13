//! Modalità CHALLENGE a schermo: presentazione di ogni avversario, livello superato, continue
//! a gettoni, iniziali per la classifica e classifica (anche nell'attract). La logica dei
//! livelli e dei punti è nel core (`paddws_core::challenge`).
//!
//! Nuovo sfidante: durante la presentazione di un livello, la partita
//! contro la CPU e il livello superato (non dopo l'ultimo) un secondo giocatore entra con un
//! credito, o in Free Play, premendo lo Start del lato libero: il tasto 1 o 2 (quello del lato,
//! come nei cabinati MAME), il click del suo encoder sul cabinato, sul touch un tocco prolungato
//! nella metà libera (solo nelle schermate, non in partita, dove il dito del giocatore usa tutto
//! lo schermo). Il click dell'encoder e il tocco prolungato, come nell'attract, mettono anche il
//! gettone se non c'è credito. Dopo "HERE COMES A NEW CHALLENGER!" lo sfidante sceglie bonus e
//! racchetta (la presentazione delle mosse speciali la vede una volta per lato in ogni sessione),
//! poi i due giocano a `Rung::points`; il vincitore riprende il livello dal suo lato. Durante la
//! sfida non entra nessun altro.

use macroquad::prelude::*;
use paddws_core::challenge::{Entry, LEVELS, RUNGS, Rung, Score, TABLE_SIZE, Table};
use paddws_core::fixed::to_f32;
use paddws_core::{Event, PaddleKind, Side};

use crate::attract::Attract;
use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::{Pick, draw_capsule, unit};
use crate::paddle_ui::{Look, Shape, TWIST_MAX_TILT, draw_paddle, tagline};
use crate::platform;
use crate::scenes::{App, Menu, Play, START_KEYS, Scene};
use crate::touch;

/// Durata delle schermate, in secondi.
const INTRO_SECONDS: f64 = 4.0;
const CLEAR_SECONDS: f64 = 4.0;
const CONTINUE_SECONDS: f64 = 10.0;
const INITIALS_SECONDS: f64 = 30.0;
const SCORES_SECONDS: f64 = 8.0;
const CHALLENGER_SECONDS: f64 = 3.0;
/// touch: tocco prolungato nella metà libera con cui entra uno sfidante
pub(crate) const HOLD_SECONDS: f64 = 1.0;
/// le schermate si possono saltare solo dopo questo tempo (non si salta per sbaglio)
const SKIP_AFTER: f64 = 1.0;
/// la voce dice il nome dell'avversario dopo questo tempo dall'inizio della presentazione
const ANNOUNCE_AFTER: f64 = 0.5;

/// Lettere delle iniziali, in ordine (come nel C64, `c64/src/challenge.s`). Il "!" è in fondo,
/// dopo lo spazio: le classifiche salvate prima restano uguali.
const LETTERS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !";

/// Iniziali segrete: confermate accendono l'easter egg, la volta dopo lo spengono
/// (`App::set_egg`). Il record si salva come gli altri.
const EGG_NAME: &[u8; 3] = b"WS!";

/// Easter egg dopo le iniziali `name`, se prima era `on`: "WS!" lo accende o lo spegne.
pub(crate) fn egg_after(on: bool, name: &[u8; 3]) -> bool {
    on ^ (name == EGG_NAME)
}

/// Partita CHALLENGE in corso: livello e punteggio.
pub struct Run {
    pub level: usize,
    pub score: u32,
    /// miglior punteggio e livello raggiunti in questa sessione: i continue azzerano il
    /// punteggio, ma in classifica va il migliore
    pub best: (u32, u8),
    /// lato del giocatore (la CPU è sull'altro): a sinistra all'inizio, poi quello di chi vince
    /// una sfida; bonus e racchetta sono quelli di `App::loadout` e `App::paddles` di questo lato
    pub side: Side,
    /// presentazione delle mosse speciali già vista dal giocatore di ciascun lato
    pub howto: [bool; 2],
}

impl Run {
    pub fn new() -> Self {
        Self {
            level: 0,
            score: 0,
            best: (0, 1),
            side: Side::Left,
            howto: [false; 2],
        }
    }

    pub(crate) fn remember(&mut self, level: u8) {
        if self.score > self.best.0 {
            self.best = (self.score, level);
        }
    }
}

/// Start in questo frame: tasti, tocco o click di un encoder.
fn start_pressed(app: &App) -> bool {
    input::any_pressed(&START_KEYS) || !touch::taps().is_empty() || app.knob_clicked()
}

// ------------------------------------------------------------- nuovo sfidante

/// Start di ciascun lato, come nei cabinati MAME: 1 a sinistra, 2 a destra.
pub(crate) const SIDE_START: [KeyCode; 2] = [KeyCode::Key1, KeyCode::Key2];

/// Gamepad nelle schermate tra un livello e l'altro (`input`): il primo è del campione (A e
/// Start come Invio), il secondo dello sfidante (A e Start come il suo Start, `SIDE_START`);
/// Select è il gettone.
pub fn pad_keys(app: &App) -> PadKeys {
    let champion = app.run.as_ref().map(|r| r.side as usize);
    input::pad_keys(|slot, c| match c {
        Control::A | Control::Start => Some(match champion {
            Some(ch) if app.pads.side_of(slot, Some(ch)) != ch => SIDE_START[1 - ch],
            _ => KeyCode::Enter,
        }),
        Control::Select => Some(KeyCode::Key5),
        _ => None,
    })
}

/// Lato libero per uno sfidante, se c'è una CHALLENGE in corso.
fn free_side(app: &App) -> Option<Side> {
    app.run.as_ref().map(|r| r.side.opponent())
}

/// Gettone (tasto 5) nelle schermate in cui può entrare uno sfidante.
fn insert_coin(app: &mut App) {
    if input::pressed(KeyCode::Key5) && !app.cfg.game.free_play && app.credits < 9 {
        app.credits += 1;
        app.play_coin();
    }
}

/// Click dell'encoder del lato `side` in questo frame.
fn knob_click(app: &App, side: Side) -> bool {
    app.knob_events
        .iter()
        .any(|e| e.player == side as usize && e.action == Action::Click)
}

/// Start del giocatore in corso: come `start_pressed`, ma senza lo Start e l'encoder del lato
/// libero, che sono dello sfidante; il tocco arriva da `Hold`.
fn champion_start(app: &App, free: Side, tap: bool) -> bool {
    let theirs = SIDE_START[free as usize];
    START_KEYS.iter().any(|k| *k != theirs && input::pressed(*k)) || tap || knob_click(app, free.opponent())
}

/// Lo sfidante del lato `free` preme Start (`held`: tocco prolungato sul touch): se c'è un
/// credito, o in Free Play, lo consuma e restituisce true. Il click dell'encoder e il tocco
/// prolungato mettono anche il gettone se manca, come nell'attract.
fn challenger(app: &mut App, free: Side, held: bool) -> bool {
    let knob = knob_click(app, free);
    if !(held || knob || input::pressed(SIDE_START[free as usize])) {
        return false;
    }
    if !app.cfg.game.free_play {
        if app.credits == 0 && (held || knob) {
            app.credits = 1;
            app.play_coin();
        }
        if app.credits == 0 {
            return false;
        }
        app.credits -= 1;
    }
    true
}

/// Partita contro la CPU in corso (`total`: punti arcade fin qui; `held`: sul touch un dito tenuto
/// per `HOLD_SECONDS` nella zona dello sfidante, `Play::read_join`): se entra uno sfidante la
/// partita si interrompe e i punti fatti restano.
pub fn challenger_during_play(app: &mut App, total: u32, held: bool) -> Option<Scene> {
    insert_coin(app);
    let free = free_side(app)?;
    if !challenger(app, free, held) {
        return None;
    }
    let run = app.run.as_mut()?;
    run.score = total;
    let level = run.level as u8 + 1;
    run.remember(level);
    Some(Scene::Challenger(Challenger::new(app)))
}

/// Touch nelle schermate in cui può entrare uno sfidante: un tocco vale come Start del giocatore
/// (nella metà libera al rilascio del dito), un dito tenuto per `HOLD_SECONDS` nella metà
/// libera fa entrare lo sfidante.
#[derive(Default)]
struct Hold {
    finger: Option<(u64, f64)>,
}

impl Hold {
    /// (tocco breve, tocco prolungato) in questo frame.
    fn update(&mut self, app: &App, free: Side, dt: f64) -> (bool, bool) {
        let half = app.renderer.world_w / 2.0;
        let mut tap = false;
        for f in touch::fingers() {
            let in_free = (f.pos.x >= half) == (free == Side::Right);
            let mine = self.finger.is_some_and(|(id, _)| id == f.id);
            match f.phase {
                TouchPhase::Started if in_free && self.finger.is_none() => self.finger = Some((f.id, 0.0)),
                TouchPhase::Started => tap = true,
                TouchPhase::Ended | TouchPhase::Cancelled if mine => {
                    self.finger = None;
                    tap = true;
                }
                _ => {}
            }
        }
        if let Some((_, t)) = &mut self.finger {
            *t += dt;
            if *t >= HOLD_SECONDS {
                self.finger = None;
                return (tap, true);
            }
        }
        (tap, false)
    }
}

/// Invito per lo sfidante, lampeggiante, in alto nella metà libera.
fn draw_join_hint(app: &App, free: Side) {
    if (get_time() * 2.0) as i64 % 2 == 1 {
        return;
    }
    let action = if app.touch {
        "HOLD HERE"
    } else if app.cfg.game.free_play || app.credits > 0 {
        "PRESS START"
    } else {
        "INSERT COIN"
    };
    let prompt = format!("P{} {action}", free as usize + 1);
    let r = &app.renderer;
    let sc = app.scale();
    let x = if free == Side::Left { r.world_w * 0.15 } else { r.world_w * 0.85 };
    let gray = App::color(app.cfg.colors.lgray);
    r.text_centered(&prompt, &app.assets.font_text, 20.0 * sc, x, 20.0 * sc, 0.0, gray);
}

/// "HERE COMES A NEW CHALLENGER!": la CHALLENGE si ferma, poi lo sfidante sceglie bonus e
/// racchetta.
pub struct Challenger {
    left: f64,
}

impl Challenger {
    pub fn new(app: &mut App) -> Self {
        // il jingle della presentazione riparte dall'inizio
        app.set_music(None);
        app.play(Event::Super);
        Self {
            left: CHALLENGER_SECONDS,
        }
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            app.run = None;
            return Some(Scene::Menu(Menu::new(app)));
        }
        self.left -= dt;
        if self.left > 0.0 {
            return None;
        }
        let free = free_side(app).expect("sfida senza CHALLENGE");
        Some(Scene::Pick(Pick::challenger(app, free)))
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let sc = app.scale();
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        r.fill(BLACK);
        // lampeggio: le scritte si scambiano accento e bianco, le bande accento e grigio
        let on = (get_time() * 4.0) as i64 % 2 == 0;
        let (main, other) = if on { (accent, white) } else { (white, accent) };
        let band = 12.0 * sc;
        for (i, y) in [h / 2.0 - 125.0 * sc, h / 2.0 + 125.0 * sc - band].into_iter().enumerate() {
            draw_rectangle(0.0, y, w, band, if on == (i == 0) { accent } else { gray });
        }
        let mid = h / sc / 2.0;
        text(app, "HERE COMES", 50.0, mid - 50.0, other);
        text(app, "A NEW CHALLENGER!", 62.0, mid + 15.0, main);
        if let Some(run) = &app.run {
            let who = if run.side == Side::Left { "P2" } else { "P1" };
            let line = format!("{who} VS CHAMPION   FIRST TO {}", RUNGS[run.level].points);
            text(app, &line, 24.0, mid + 80.0, white);
        }
    }
}

/// Fine della sfida: ha vinto il lato `winner`. Il vincitore prende `Score::after_duel` punti e
/// riprende il livello dal suo lato; prima il perdente mette le iniziali se il suo punteggio
/// migliore della sessione entra in classifica (lo sfidante entra con 0 punti: non succede).
pub fn duel_over(app: &mut App, winner: Side) -> Scene {
    let run = app.run.as_mut().expect("sfida senza CHALLENGE");
    let champion_won = winner == run.side;
    let loser_best = (!champion_won).then_some(run.best);
    run.score = Score::after_duel(run.score, champion_won, run.level);
    if !champion_won {
        run.side = winner;
        run.best = (0, 1);
    }
    let level = run.level as u8 + 1;
    run.remember(level);
    match loser_best.filter(|best| app.scores.rank(best.0).is_some()) {
        Some(best) => Scene::Initials(Initials::loser(best, winner.opponent())),
        None => Scene::Intro(Intro::new(app)),
    }
}

fn pad(n: u32) -> String {
    format!("{n:07}")
}

/// Testo centrato su `y` (coordinate di disegno), nel font dei testi.
fn text(app: &App, s: &str, size: f32, y: f32, color: Color) {
    let sc = app.scale();
    app.renderer.text_centered(
        s,
        &app.assets.font_text,
        size * sc,
        app.renderer.world_w / 2.0,
        y * sc,
        0.0,
        color,
    );
}

/// Fine della sessione: le iniziali se il punteggio entra in classifica, altrimenti la classifica.
pub(crate) fn finish(app: &mut App) -> Scene {
    let Some(run) = app.run.take() else {
        return Scene::Scores(Scores::new(None));
    };
    match app.scores.rank(run.best.0) {
        Some(_) => Scene::Initials(Initials::new(run.best)),
        None => Scene::Scores(Scores::new(None)),
    }
}

// ------------------------------------------------------------- presentazione

/// L'avversario del livello: racchetta a grandezza reale, nome, bonus e punteggio.
pub struct Intro {
    left: f64,
    hold: Hold,
    /// nome dell'avversario già annunciato
    announced: bool,
}

impl Intro {
    pub fn new(app: &App) -> Self {
        app.play(Event::Boost);
        Self {
            left: INTRO_SECONDS,
            hold: Hold::default(),
            announced: false,
        }
    }

    /// Per la verifica automatica: porta la presentazione a `seconds` dall'inizio.
    pub fn skip_to(&mut self, seconds: f64) {
        self.left = INTRO_SECONDS - seconds;
    }

    /// Come il MiSTer, il nome dell'avversario si ferma quando la presentazione finisce (saltata,
    /// arriva uno sfidante, Esc).
    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        let next = self.step(app, dt);
        if next.is_some() {
            app.stop_announce();
        }
        next
    }

    fn step(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            app.run = None;
            return Some(Scene::Menu(Menu::new(app)));
        }
        insert_coin(app);
        let free = free_side(app).expect("CHALLENGE senza partita");
        let (tap, held) = self.hold.update(app, free, dt);
        if challenger(app, free, held) {
            return Some(Scene::Challenger(Challenger::new(app)));
        }
        self.left -= dt;
        // la voce dice il nome dell'avversario poco dopo l'inizio del jingle
        if !self.announced && self.left <= INTRO_SECONDS - ANNOUNCE_AFTER {
            self.announced = true;
            let run = app.run.as_ref().expect("CHALLENGE senza partita");
            app.announce(RUNGS[run.level].kind);
        }
        let skip = self.left < INTRO_SECONDS - SKIP_AFTER && champion_start(app, free, tap);
        (self.left <= 0.0 || skip).then(|| Scene::Game(Box::new(Play::challenge(app))))
    }

    /// Presentazione animata: in cima la scala dei livelli, poi l'avversario entra a modo suo,
    /// mostrando quello che sa fare, e porta con sé nome, motto, bonus e punti da fare.
    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let run = app.run.as_ref().expect("CHALLENGE senza partita");
        r.fill(BLACK);
        let f = ((INTRO_SECONDS - self.left) * 60.0).floor() as f32;
        let st = Stage::new(app, run, f);
        st.header();
        match st.rung.kind {
            PaddleKind::Arcade => st.arcade(),
            PaddleKind::Twist => st.twist(),
            PaddleKind::Hammer => st.hammer(),
            PaddleKind::Titan => st.titan(),
            PaddleKind::Blaster => st.blaster(),
            PaddleKind::Rush => st.rush(),
            PaddleKind::Guardian => st.guardian(),
        }
        text(
            app,
            &format!("SCORE {}    HI {}", pad(run.score), pad(app.scores.entries[0].score)),
            28.0,
            r.world_h / app.scale() - 30.0,
            App::color(app.cfg.colors.white),
        );
        draw_join_hint(app, run.side.opponent());
    }
}

// Presentazione: righe (unità a 480 righe) della scala, del livello, del centro della racchetta,
// del nome, del motto, delle capsule e dei loro nomi, dei punti da fare.
const LADDER_Y: f32 = 14.0;
const LEVEL_Y: f32 = 52.0;
const PAD_Y: f32 = 163.0;
const NAME_Y: f32 = 254.0;
const TAG_Y: f32 = 294.0;
const CAP_Y: f32 = 338.0;
const CAP_NAME_Y: f32 = 366.0;
const FIRST_Y: f32 = 404.0;
/// HAMMER: scossa del colpo e dell'atterraggio del nome (unità a 480 righe, frame per frame).
const HAMMER_SHAKE: [(f32, f32); 8] = [
    (6.0, 0.0),
    (-6.0, 4.0),
    (6.0, -4.0),
    (-4.0, 2.0),
    (4.0, -2.0),
    (-2.0, 0.0),
    (2.0, 0.0),
    (0.0, 0.0),
];
const LAND_SHAKE: [(f32, f32); 6] = [(0.0, 6.0), (0.0, -4.0), (0.0, 4.0), (0.0, -2.0), (0.0, 2.0), (0.0, 0.0)];
/// ARCADE: capsule della raffica, spostamento verticale dalla racchetta.
const ARCADE_DY: [f32; 10] = [-28.0, 20.0, -8.0, 32.0, -36.0, 4.0, 24.0, -20.0, 12.0, -4.0];
/// GUARDIAN: frame in cui la palla arriva sul muro.
const GUARDIAN_HIT: f32 = 82.0;

/// Una presentazione al frame `f` (60 al secondo, dall'inizio). Le x si danno come distanza dal
/// centro verso la metà campo dell'avversario (`x`), da dove entra; le y come righe a 480 (`y`).
struct Stage<'a> {
    app: &'a App,
    rung: &'static Rung,
    level: usize,
    f: f32,
    /// +1 se l'avversario sta a destra (il giocatore a sinistra), -1 altrimenti
    away: f32,
    sc: f32,
    u: f32,
    shake: (f32, f32),
    white: Color,
    gray: Color,
    accent: Color,
}

impl<'a> Stage<'a> {
    fn new(app: &'a App, run: &Run, f: f32) -> Self {
        let rung = &RUNGS[run.level];
        let colors = &app.cfg.colors;
        let mut st = Self {
            app,
            rung,
            level: run.level,
            f,
            away: if run.side == Side::Left { 1.0 } else { -1.0 },
            sc: app.scale(),
            u: unit(app),
            shake: (0.0, 0.0),
            white: App::color(colors.white),
            gray: App::color(colors.lgray),
            accent: App::color(colors.accent),
        };
        let (dx, dy) = st.shake_at();
        st.shake = (dx * st.sc, dy * st.sc);
        st
    }

    /// Scossa dello schermo di questo frame (unità a 480 righe).
    fn shake_at(&self) -> (f32, f32) {
        let f = self.f;
        match self.rung.kind {
            PaddleKind::Hammer if (49.0..57.0).contains(&f) => HAMMER_SHAKE[(f - 49.0) as usize],
            PaddleKind::Hammer if (72.0..78.0).contains(&f) => LAND_SHAKE[(f - 72.0) as usize],
            // TITAN: un colpo sordo ogni quattro scatti della crescita
            PaddleKind::Titan if (6.0..78.0).contains(&f) && (f - 6.0) % 12.0 == 0.0 => (0.0, 2.0),
            // GUARDIAN: i pezzi del muro che si posano, la palla che lo colpisce
            PaddleKind::Guardian if (0..5).any(|s| f == 14.0 + 8.0 * s as f32) => (0.0, 2.0),
            PaddleKind::Guardian if f == GUARDIAN_HIT => (3.0, 0.0),
            _ => (0.0, 0.0),
        }
    }

    fn x(&self, dx: f32) -> f32 {
        self.app.renderer.world_w / 2.0 + self.away * dx * self.sc + self.shake.0
    }

    fn y(&self, y: f32) -> f32 {
        y * self.sc + self.shake.1
    }

    fn font(&self) -> &crate::render::GameFont {
        &self.app.assets.font_text
    }

    /// Testo centrato in (x, y) di disegno, alto `size` (unità a 480 righe).
    fn text_at(&self, s: &str, size: f32, x: f32, y: f32, color: Color) {
        self.app.renderer.text_centered(s, self.font(), size * self.sc, x, y, 0.0, color);
    }

    /// Racchetta dell'avversario con centro (x, y) di disegno, alta `h`, rivolta al giocatore.
    #[allow(clippy::too_many_arguments)]
    fn paddle(&self, x: f32, y: f32, h: f32, tilt: f32, dash: Option<(f32, f32)>, body: Color, preview: bool) {
        let r = &self.app.renderer;
        let shape = Shape {
            kind: Some(self.rung.kind),
            x,
            y: r.screen_y(y), // y del core, verso l'alto
            w: to_f32(self.app.params.pad_width),
            h,
            front: -self.away,
            tilt,
            dash,
            preview,
        };
        let look = Look {
            body,
            mark: self.accent,
            detail: self.gray,
        };
        draw_paddle(r, &shape, self.u, look);
    }

    fn pad_height(&self) -> f32 {
        to_f32(self.app.params.kinds[self.rung.kind as usize].height)
    }

    fn ball(&self) -> f32 {
        to_f32(self.app.params.ball_radius) * 2.0
    }

    /// Scala dei livelli: sette trattini come quelli della mezzeria (battuti bianchi, quello di
    /// adesso giallo che lampeggia, gli altri spenti), che compaiono uno ogni due frame, e sotto il
    /// livello (FINAL LEVEL lampeggia).
    fn header(&self) {
        let f = self.f;
        let dim = Color { a: 0.25, ..self.white };
        let w = self.app.renderer.world_w;
        for i in 0..LEVELS {
            if f < 2.0 * i as f32 {
                break;
            }
            let color = match i.cmp(&self.level) {
                std::cmp::Ordering::Less => self.white,
                std::cmp::Ordering::Equal if (f / 8.0) as i64 % 2 == 0 => self.accent,
                _ => dim,
            };
            let x = w / 2.0 + (i as f32 * 48.0 - 160.0) * self.sc + self.shake.0;
            draw_rectangle(x, self.y(LADDER_Y), 32.0 * self.sc, 10.0 * self.sc, color);
        }
        let last = self.level + 1 == LEVELS;
        if f >= 14.0 && (!last || (f / 10.0) as i64 % 2 == 0) {
            let title = if last {
                "FINAL LEVEL".to_string()
            } else {
                format!("LEVEL {} OF {LEVELS}", self.level + 1)
            };
            self.text_at(&title, 34.0, self.x(0.0), self.y(LEVEL_Y), self.accent);
        }
    }

    fn name(&self, x: f32, y: f32, color: Color) {
        self.text_at(self.rung.kind.name(), 52.0, x, y, color);
    }

    /// Lettere del nome: centro x di disegno di ciascuna (il nome centrato nello schermo).
    fn name_letters(&self) -> Vec<f32> {
        let r = &self.app.renderer;
        let cx = r.world_w / 2.0 + self.shake.0;
        r.ink_boxes(self.rung.kind.name(), self.font(), 52.0 * self.sc)
            .into_iter()
            .flatten()
            .map(|(x0, x1)| cx + (x0 + x1) / 2.0)
            .collect()
    }

    /// Una lettera del nome, centrata in (x, y) di disegno.
    fn letter(&self, i: usize, x: f32, y: f32, color: Color) {
        if let Some(ch) = self.rung.kind.name().chars().nth(i) {
            self.text_at(&ch.to_string(), 52.0, x, y, color);
        }
    }

    /// Motto scritto una lettera ogni `per` frame da `t0`.
    fn tag_typed(&self, t0: f32, per: f32) {
        if self.f < t0 {
            return;
        }
        let tag = tagline(self.rung.kind);
        let n = (((self.f - t0) / per) as usize + 1).min(tag.len());
        // la parte scritta, allineata dove starà il motto intero
        let r = &self.app.renderer;
        let size = 26.0 * self.sc;
        let full = r.text_width(tag, self.font(), size);
        let part = r.text_width(&tag[..n], self.font(), size);
        let cx = r.world_w / 2.0 + self.shake.0 - full / 2.0 + part / 2.0;
        self.text_at(&tag[..n], 26.0, cx, self.y(TAG_Y), self.gray);
    }

    fn cap_x(&self, i: usize) -> f32 {
        self.app.renderer.world_w / 2.0 + (i as f32 - 1.0) * 150.0 * self.sc + self.shake.0
    }

    fn capsule(&self, i: usize, x: f32, y: f32, inverted: bool) {
        draw_capsule(self.rung.loadout[i], x, y, 13.0 * self.u, self.u, inverted, self.accent);
    }

    fn cap_name(&self, i: usize) {
        self.text_at(self.rung.loadout[i].name(), 22.0, self.cap_x(i), self.y(CAP_NAME_Y), self.accent);
    }

    /// Capsule che arrivano dalla metà campo dell'avversario, una ogni `gap` frame da `t0`, a `sp`
    /// unità per frame; arrivate si accendono in negativo per un attimo e mostrano il nome.
    fn caps_slide(&self, t0: f32, gap: f32, sp: f32) {
        for i in 0..3 {
            let s = t0 + i as f32 * gap;
            if self.f < s {
                continue;
            }
            let (from, to) = (self.x(360.0), self.cap_x(i));
            let travel = (to - from).abs();
            let moved = (self.f - s) * sp * self.sc;
            if moved < travel {
                self.capsule(i, from + (to - from).signum() * moved, self.y(CAP_Y), false);
                continue;
            }
            let arrived = s + travel / (sp * self.sc);
            self.capsule(i, to, self.y(CAP_Y), self.f < arrived + 4.0);
            self.cap_name(i);
        }
    }

    /// Capsule che compaiono al loro posto in negativo, una ogni `gap` frame da `t0`.
    fn caps_pop(&self, t0: f32, gap: f32) {
        for i in 0..3 {
            let s = t0 + i as f32 * gap;
            if self.f >= s {
                self.capsule(i, self.cap_x(i), self.y(CAP_Y), self.f < s + 4.0);
                self.cap_name(i);
            }
        }
    }

    fn first_to(&self, at: f32) {
        if self.f >= at {
            let s = format!("FIRST TO {}", self.rung.points);
            self.text_at(&s, 26.0, self.x(0.0), self.y(FIRST_Y), self.gray);
        }
    }

    /// ARCADE (più bonus): una raffica di capsule parte dalla mezzeria e la racchetta le prende
    /// tutte, contandole; il nome lampeggia come INSERT COIN, poi i tre bonus escono dalla racchetta.
    fn arcade(&self) {
        let (f, u) = (self.f, self.u);
        let (net, face, sp): (f32, f32, f32) = (-240.0, -5.0, 12.0);
        let arrive = |k: usize| 10.0 + k as f32 * 6.0 + ((face - net) / sp).ceil();
        if (6.0..84.0).contains(&f) {
            for i in 0..5 {
                let y = PAD_Y - 56.0 + i as f32 * 24.0;
                draw_rectangle(self.x(net) - 2.0 * self.sc, self.y(y), 4.0 * self.sc, 12.0 * self.sc, self.white);
            }
        }
        let (mut caught, mut flash) = (0, false);
        for (k, dy) in ARCADE_DY.iter().enumerate() {
            let s = 10.0 + k as f32 * 6.0;
            if f >= arrive(k) {
                caught += 1;
                flash |= f < arrive(k) + 2.0;
            } else if f >= s {
                let x = self.x(net + (f - s) * sp);
                draw_capsule(self.rung.loadout[k % 3], x, self.y(PAD_Y + dy), 10.0 * u, u, false, self.accent);
            }
        }
        // la racchetta va incontro alla capsula che arriva, poi torna al centro
        let dy = match (0..ARCADE_DY.len()).find(|&k| arrive(k) > f) {
            _ if f < 10.0 => 0.0,
            Some(k) => {
                let (a0, y0) = if k > 0 { (arrive(k - 1), ARCADE_DY[k - 1]) } else { (10.0, 0.0) };
                y0 + (ARCADE_DY[k] - y0) * ((f - a0) / (arrive(k) - a0 - 2.0).max(1.0)).min(1.0)
            }
            None => ARCADE_DY[9] * (1.0 - ((f - arrive(9)) / 10.0).min(1.0)),
        };
        let body = if flash { self.accent } else { self.white };
        self.paddle(self.x(0.0), self.y(PAD_Y + dy), self.pad_height(), 0.0, None, body, false);
        if caught > 0 && f < 96.0 {
            self.text_at(&format!("+{caught}"), 26.0, self.x(30.0), self.y(PAD_Y + dy - 10.0), self.accent);
        }
        if f >= 84.0 && (f >= 108.0 || ((f - 84.0) / 4.0) as i64 % 2 == 0) {
            self.name(self.x(0.0), self.y(NAME_Y), self.white);
        }
        self.tag_typed(100.0, 1.0);
        for i in 0..3 {
            let s = 120.0 + 8.0 * i as f32;
            if f < s {
                continue;
            }
            let k = ((f - s) / 6.0).min(1.0);
            let (x0, y0) = (self.x(0.0), self.y(PAD_Y));
            let (x1, y1) = (self.cap_x(i), self.y(CAP_Y));
            self.capsule(i, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, k == 1.0 && f < s + 10.0);
            if k == 1.0 {
                self.cap_name(i);
            }
        }
        self.first_to(160.0);
    }

    /// TWIST (s'inclina con la velocità): corre su e giù inclinandosi, ribatte la palla di sbieco;
    /// il nome entra inclinato e oscilla finché non si raddrizza.
    fn twist(&self) {
        let f = self.f;
        // spostamento verticale e velocità (unità per frame, verso il basso) della racchetta
        let run = |f: f32| {
            if !(6.0..66.0).contains(&f) {
                return (0.0, 0.0);
            }
            let (t, a) = (f - 6.0, 44.0 * (1.0 - (f - 6.0) / 60.0));
            (a * (t * 0.35).sin(), a * 0.35 * (t * 0.35).cos())
        };
        let (dy, v) = run(f);
        // salendo la faccia si gira verso l'alto
        let tilt = (-v * 0.03).clamp(-TWIST_MAX_TILT, TWIST_MAX_TILT);
        self.paddle(self.x(0.0), self.y(PAD_Y + dy), self.pad_height(), tilt, None, self.white, false);
        let d = self.ball();
        let hit_y = PAD_Y + run(30.0).0;
        if (14.0..30.0).contains(&f) {
            draw_rectangle(self.x(-320.0 + (f - 14.0) * 19.0) - d / 2.0, self.y(hit_y) - d / 2.0, d, d, self.white);
        } else if f >= 30.0 {
            let t = f - 30.0;
            draw_rectangle(self.x(-15.0 - 14.0 * t) - d / 2.0, self.y(hit_y - 9.0 * t) - d / 2.0, d, d, self.white);
        }
        if f >= 66.0 {
            let t = f - 66.0;
            let rot = if t < 24.0 { 0.25 * (t * 0.6).cos() * (1.0 - t / 24.0) } else { 0.0 };
            let r = &self.app.renderer;
            r.text_centered(self.rung.kind.name(), self.font(), 52.0 * self.sc, self.x(0.0), self.y(NAME_Y), rot, self.white);
        }
        self.tag_typed(92.0, 1.0);
        self.caps_slide(112.0, 12.0, 60.0);
        self.first_to(160.0);
    }

    /// HAMMER (colpi potenti): la palla arriva piano, il martello carica e la ribatte fortissimo;
    /// il nome cade come un peso e alza la polvere, le capsule cadono pesanti.
    fn hammer(&self) {
        let f = self.f;
        // carica all'indietro, colpo in avanti, ritorno
        let px = if (40.0..48.0).contains(&f) {
            2.0 * (f - 39.0)
        } else if (49.0..55.0).contains(&f) {
            (-16.0 + 4.0 * (f - 50.0).max(0.0)).min(0.0)
        } else {
            0.0
        };
        self.paddle(self.x(px), self.y(PAD_Y), self.pad_height(), 0.0, None, self.white, false);
        let d = self.ball();
        let by = self.y(PAD_Y) - d / 2.0;
        if (12.0..49.0).contains(&f) {
            draw_rectangle(self.x(-20.0 - (49.0 - f) * 8.0) - d / 2.0, by, d, d, self.white);
        } else if f >= 49.0 {
            let bx = -20.0 - (f - 49.0) * 40.0;
            for (k, a) in [0.6, 0.35, 0.15].iter().enumerate() {
                let color = Color { a: *a, ..self.gray };
                draw_rectangle(self.x(bx + 16.0 * (k + 1) as f32) - d / 2.0, by, d, d, color);
            }
            draw_rectangle(self.x(bx) - d / 2.0, by, d, d, self.white);
        }
        if f >= 62.0 {
            let y = if f < 72.0 { NAME_Y - (72.0 - f).powi(2) * 2.6 } else { NAME_Y };
            self.name(self.x(0.0), self.y(y), self.white);
        }
        // polvere ai due lati del nome
        if (72.0..82.0).contains(&f) {
            let t = f - 72.0;
            let r = &self.app.renderer;
            let half = r.text_width(self.rung.kind.name(), self.font(), 52.0 * self.sc) / 2.0;
            let cx = r.world_w / 2.0 + self.shake.0;
            for (sp, up) in [(6.0, 5.0), (10.0, 3.0)] {
                let dy = self.y(NAME_Y + 20.0 - up * t + 0.8 * t * t);
                let off = half + (6.0 + sp * t) * self.sc;
                let s = 4.0 * self.sc;
                draw_rectangle(cx - off - s, dy, s, s, self.gray);
                draw_rectangle(cx + off, dy, s, s, self.gray);
            }
        }
        self.tag_typed(88.0, 1.0);
        for i in 0..3 {
            let s = 106.0 + 10.0 * i as f32;
            if f < s {
                continue;
            }
            let t = f - s;
            let y = if t < 8.0 { CAP_Y - (8.0 - t).powi(2) * 6.0 } else { CAP_Y };
            self.capsule(i, self.cap_x(i), self.y(y), (8.0..11.0).contains(&t));
            if t >= 8.0 {
                self.cap_name(i);
            }
        }
        self.first_to(150.0);
    }

    /// TITAN (alto ma lento): tutto lento; cresce dal pavimento a scatti che fanno tremare lo
    /// schermo, il nome sale da sotto terra, il motto si scrive piano, le capsule arrivano per ultime.
    fn titan(&self) {
        let f = self.f;
        let full = self.pad_height();
        if f >= 6.0 {
            let step = full / 24.0;
            let h = (((f - 6.0) / 3.0).floor() + 1.0).min(24.0) * step;
            let flash = h >= full && (78.0..82.0).contains(&f);
            let bottom = self.y(PAD_Y) + full / 2.0;
            let body = if flash { self.accent } else { self.white };
            self.paddle(self.x(0.0), bottom - h / 2.0, h, 0.0, None, body, false);
        }
        if f >= 84.0 {
            // sale da sotto il pavimento: quello che è ancora sotto resta coperto
            let r = &self.app.renderer;
            let th = r.text_height(self.rung.kind.name(), self.font(), 52.0 * self.sc);
            let ground = self.y(NAME_Y) + th / 2.0 + self.u;
            let y = (NAME_Y + 50.0 - (f - 84.0) * 2.0).max(NAME_Y);
            self.name(self.x(0.0), self.y(y), self.white);
            let w = r.world_w;
            draw_rectangle(0.0, ground, w, 60.0 * self.sc, BLACK);
            if f < 112.0 {
                let half = r.text_width(self.rung.kind.name(), self.font(), 52.0 * self.sc) / 2.0 + 16.0 * self.sc;
                draw_rectangle(w / 2.0 - half + self.shake.0, ground, 2.0 * half, 2.0 * self.sc, self.gray);
            }
        }
        self.tag_typed(114.0, 3.0);
        self.caps_slide(156.0, 12.0, 16.0);
        self.first_to(214.0);
    }

    /// BLASTER (spara alle capsule): da una parte spara, e ogni colpo accende una lettera del nome;
    /// poi scende e colpisce al volo le tre capsule, che si fermano al loro posto.
    fn blaster(&self) {
        let (f, sc) = (self.f, self.sc);
        let py = if f < 64.0 { NAME_Y } else { (NAME_Y + (f - 64.0) * 8.0).min(CAP_Y) };
        let muzzle = self.x(224.0);
        let shot = |x: f32, y: f32| {
            for dy in [-8.0, 6.0] {
                draw_rectangle(x - 7.0 * sc, self.y(y + dy), 14.0 * sc, 2.0 * sc, self.accent);
            }
        };
        if f >= 4.0 {
            self.paddle(self.x(240.0), self.y(py), self.pad_height(), 0.0, None, self.white, false);
        }
        // un colpo per lettera, dalla più vicina alla racchetta
        let letters = self.name_letters();
        let n = letters.len();
        for k in 0..n {
            let j = if self.away > 0.0 { n - 1 - k } else { k };
            let fired = 12.0 + 5.0 * k as f32;
            let target = letters[j];
            let reach = fired + ((muzzle - target).abs() / (40.0 * sc)).ceil();
            if (fired..reach).contains(&f) {
                shot(muzzle - self.away * (f - fired) * 40.0 * sc, NAME_Y);
            }
            if f == fired {
                draw_rectangle(muzzle - 3.0 * sc, self.y(NAME_Y - 10.0), 6.0 * sc, 20.0 * sc, self.accent);
            }
            if f >= reach {
                let color = if f < reach + 2.0 { self.accent } else { self.white };
                self.letter(j, target, self.y(NAME_Y), color);
            }
        }
        self.tag_typed(56.0, 1.0);
        // capsule colpite al volo: arrivano dalla parte del giocatore, il colpo le ferma al loro posto
        for i in 0..3 {
            let at = 96.0 + 14.0 * i as f32;
            let cx = self.cap_x(i);
            if f < at {
                let x = cx - self.away * (at - f) * 20.0 * sc;
                if (0.0..self.app.renderer.world_w).contains(&x) {
                    draw_rectangle_lines(x - 6.5 * self.u, self.y(CAP_Y) - 6.5 * self.u, 13.0 * self.u, 13.0 * self.u, 2.0 * self.u, self.accent);
                }
                let sx = cx + self.away * (20.0 + (at - f) * 40.0) * sc;
                if py == CAP_Y && (sx - muzzle) * self.away <= 0.0 {
                    shot(sx, CAP_Y);
                }
                continue;
            }
            self.capsule(i, cx, self.y(CAP_Y), f < at + 4.0);
            self.cap_name(i);
        }
        self.first_to(150.0);
    }

    /// RUSH (scatto lungo): tutto veloce; carica sul bordo e fa uno scatto lunghissimo con le
    /// immagini gialle, e nome, motto e capsule entrano allo stesso modo.
    fn rush(&self) {
        let f = self.f;
        // posizione (x di disegno) e intensità delle immagini di un elemento che scatta da `from` a
        // `to` in `steps` frame da `t0`; None prima
        let dash = |t0: f32, from: f32, to: f32, steps: f32| -> Option<(f32, f32)> {
            if f < t0 {
                return None;
            }
            let t = f - t0;
            let x = if t < steps { from + (to - from) * (t + 1.0) / steps } else { to };
            let fade = if t < steps { 1.0 } else { (1.0 - (t - steps + 1.0) / 12.0).max(0.0) };
            Some((x, fade))
        };
        let ghosts = |from: f32, x: f32, fade: f32| (1..=3).map(move |k| (from + (x - from) * k as f32 / 4.0, 0.18 * k as f32 * fade));
        let h = self.pad_height();
        if (4.0..16.0).contains(&f) && ((f / 3.0) as i64) % 2 == 0 {
            self.paddle(self.x(280.0), self.y(PAD_Y), h, 0.0, None, self.white, false);
        }
        if let Some((x, fade)) = dash(16.0, self.x(280.0), self.x(0.0), 4.0) {
            let trail = (fade > 0.0).then_some((self.x(280.0), fade));
            self.paddle(x, self.y(PAD_Y), h, 0.0, trail, self.white, false);
        }
        let name = self.rung.kind.name();
        if let Some((x, fade)) = dash(30.0, self.x(340.0), self.x(0.0), 4.0) {
            for (gx, a) in ghosts(self.x(340.0), x, fade) {
                self.name(gx, self.y(NAME_Y), Color { a, ..self.accent });
            }
            let color = if (34.0..36.0).contains(&f) { self.accent } else { self.white };
            self.text_at(name, 52.0, x, self.y(NAME_Y), color);
        }
        let tag = tagline(self.rung.kind);
        if let Some((x, fade)) = dash(44.0, self.x(340.0), self.x(0.0), 3.0) {
            for (gx, a) in ghosts(self.x(340.0), x, fade) {
                self.text_at(tag, 26.0, gx, self.y(TAG_Y), Color { a, ..self.accent });
            }
            self.text_at(tag, 26.0, x, self.y(TAG_Y), self.gray);
        }
        for i in 0..3 {
            let t0 = 58.0 + 6.0 * i as f32;
            if let Some((x, fade)) = dash(t0, self.x(360.0), self.cap_x(i), 3.0) {
                let s = 13.0 * self.u;
                for (gx, a) in ghosts(self.x(360.0), x, fade) {
                    let color = Color { a, ..self.accent };
                    draw_rectangle_lines(gx - s / 2.0, self.y(CAP_Y) - s / 2.0, s, s, 2.0 * self.u, color);
                }
                self.capsule(i, x, self.y(CAP_Y), (t0 + 3.0..t0 + 5.0).contains(&f));
                if f >= t0 + 3.0 {
                    self.cap_name(i);
                }
            }
        }
        self.first_to(90.0);
    }

    /// GUARDIAN (muro a cinque pezzi), l'ultimo livello: i cinque pezzi del muro cadono uno
    /// sull'altro, una palla passa sopra la racchetta e il muro la rimanda; il nome si posa lettera
    /// per lettera, come i mattoni.
    fn guardian(&self) {
        let (f, u, sc) = (self.f, self.u, self.sc);
        let h = self.pad_height();
        if f >= 4.0 {
            self.paddle(self.x(-20.0), self.y(PAD_Y), h, 0.0, None, self.white, false);
        }
        // muro dietro la racchetta: cinque settori tratteggiati come in partita, posati dal basso
        let (sect, gap) = (24.0, 4.0);
        let top = PAD_Y - (5.0 * sect + 4.0 * gap) / 2.0;
        let wall_x = self.x(36.0);
        for s in 0..5 {
            let idx = 4 - s;
            let t0 = 10.0 + 8.0 * s as f32;
            if f < t0 {
                continue;
            }
            let target = top + idx as f32 * (sect + gap);
            let t = f - t0;
            let y = if t < 5.0 { -30.0 + (target + 30.0) * ((t + 1.0) / 5.0).powi(2) } else { target };
            let hit = idx == 0 && (GUARDIAN_HIT..GUARDIAN_HIT + 8.0).contains(&f) && ((f - GUARDIAN_HIT) / 2.0) as i64 % 2 == 0;
            let color = if hit { self.white } else { Color { a: 0.9, ..self.accent } };
            let mut dy = 0.0;
            while dy < sect - 2.0 {
                draw_rectangle(wall_x - u, self.y(y + dy), 2.0 * u, (5.0 * u).min((sect - dy) * sc), color);
                dy += 8.0 * u / sc;
            }
        }
        // la palla passa sopra la racchetta, il muro la rimanda
        let d = self.ball();
        let by = self.y(top + sect / 2.0) - d / 2.0;
        if (52.0..GUARDIAN_HIT).contains(&f) {
            draw_rectangle(self.x(-324.0 + (f - 52.0) * 12.0) - d / 2.0, by, d, d, self.white);
        } else if f >= GUARDIAN_HIT {
            let x = self.x(32.0 - (f - GUARDIAN_HIT) * 12.0);
            if (0.0..self.app.renderer.world_w).contains(&x) {
                draw_rectangle(x - d / 2.0, by, d, d, self.white);
            }
        }
        // il nome: una lettera ogni tre frame cade al suo posto
        for (i, &x) in self.name_letters().iter().enumerate() {
            let t = f - (96.0 + 3.0 * i as f32);
            if t < 0.0 {
                continue;
            }
            let y = if t < 5.0 { NAME_Y - (NAME_Y + 60.0) * (1.0 - ((t + 1.0) / 5.0).powi(2)) } else { NAME_Y };
            self.letter(i, x, self.y(y), self.white);
        }
        self.tag_typed(130.0, 1.0);
        self.caps_pop(152.0, 10.0);
        self.first_to(190.0);
    }
}

// ----------------------------------------------------------------- livello superato

/// Livello vinto: premi e punteggio; dopo l'ultimo livello, la vittoria finale.
pub struct Clear {
    pub(crate) level: usize,
    win: u32,
    perfect: u32,
    left: f64,
    hold: Hold,
}

impl Clear {
    /// Il giocatore ha vinto il livello in corso con l'avversario a `opponent_points`.
    pub fn new(app: &mut App, opponent_points: u16) -> Self {
        let run = app.run.as_mut().expect("CHALLENGE senza partita");
        let (win, perfect) = Score::win_bonus(run.level, opponent_points);
        run.score = run.score.saturating_add(win + perfect);
        let level = run.level;
        let reached = if level + 1 == LEVELS { LEVELS + 1 } else { level + 2 };
        run.remember(reached as u8);
        app.play(Event::Score);
        Self {
            level,
            win,
            perfect,
            left: CLEAR_SECONDS,
            hold: Hold::default(),
        }
    }

    /// Ultimo livello: la scala è finita.
    pub fn last(&self) -> bool {
        self.level + 1 == LEVELS
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            app.run = None;
            return Some(Scene::Menu(Menu::new(app)));
        }
        // uno sfidante può entrare, tranne dopo l'ultimo livello (la scala è finita): la sfida si
        // gioca al livello dopo, quello che il vincitore affronterà
        let free = free_side(app).filter(|_| !self.last());
        let mut tap = false;
        if let Some(free) = free {
            insert_coin(app);
            let held;
            (tap, held) = self.hold.update(app, free, dt);
            if challenger(app, free, held) {
                app.run.as_mut().expect("CHALLENGE senza partita").level += 1;
                return Some(Scene::Challenger(Challenger::new(app)));
            }
        }
        self.left -= dt;
        let start = match free {
            Some(free) => champion_start(app, free, tap),
            None => start_pressed(app),
        };
        let skip = self.left < CLEAR_SECONDS - SKIP_AFTER && start;
        if self.left > 0.0 && !skip {
            return None;
        }
        if self.level + 1 == LEVELS {
            return Some(finish(app));
        }
        app.run.as_mut().expect("CHALLENGE senza partita").level += 1;
        Some(Scene::Intro(Intro::new(app)))
    }

    pub fn draw(&self, app: &App) {
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        app.renderer.fill(BLACK);
        let last = self.level + 1 == LEVELS;
        let title = if last {
            "CHAMPION!".to_string()
        } else {
            format!("LEVEL {} CLEAR", self.level + 1)
        };
        text(app, &title, 56.0, 120.0, accent);
        if last {
            text(app, "YOU BEAT EVERY PADDLE", 30.0, 175.0, white);
        }
        text(app, &format!("WIN BONUS  +{}", self.win), 32.0, 250.0, white);
        if self.perfect > 0 {
            text(app, &format!("PERFECT  +{}", self.perfect), 32.0, 295.0, accent);
        }
        let score = app.run.as_ref().map_or(0, |r| r.score);
        text(app, &format!("SCORE {}", pad(score)), 36.0, 360.0, white);
        text(app, "PRESS START", 22.0, 430.0, gray);
        if let Some(run) = app.run.as_ref().filter(|_| !last) {
            draw_join_hint(app, run.side.opponent());
        }
    }
}

// -------------------------------------------------------------------- continue

/// Partita persa: conto alla rovescia per continuare con un gettone (o Start in Free Play),
/// dallo stesso livello con il punteggio azzerato. Se scade (o con Esc) GAME OVER, poi le
/// iniziali o la classifica.
pub struct Continue {
    left: f64,
    /// secondi rimasti del GAME OVER, dopo il conto alla rovescia
    over: Option<f64>,
}

impl Continue {
    pub fn new(app: &mut App) -> Self {
        if let Some(run) = &mut app.run {
            let level = run.level as u8 + 1;
            run.remember(level);
        }
        app.play(Event::Score);
        Self { left: CONTINUE_SECONDS, over: None }
    }

    /// Il conto alla rovescia è scaduto: si vede GAME OVER.
    pub fn game_over(&self) -> bool {
        self.over.is_some()
    }

    /// Per la verifica automatica: il conto alla rovescia già scaduto.
    pub fn expire(&mut self, app: &App) {
        self.over = Some(app.attract.game_over_seconds());
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if let Some(left) = &mut self.over {
            *left -= dt;
            return (*left <= 0.0 || input::pressed(KeyCode::Escape)).then(|| finish(app));
        }
        if input::pressed(KeyCode::Escape) {
            self.over = Some(app.attract.game_over_seconds());
            return None;
        }
        if input::pressed(KeyCode::Key5) && !app.cfg.game.free_play && app.credits < 9 {
            app.credits += 1;
            app.play_coin();
        }
        if self.left < CONTINUE_SECONDS - SKIP_AFTER
            && start_pressed(app)
            && (app.cfg.game.free_play || app.credits > 0)
        {
            if !app.cfg.game.free_play {
                app.credits -= 1;
            }
            if let Some(run) = &mut app.run {
                run.score = 0;
            }
            return Some(Scene::Intro(Intro::new(app)));
        }
        let before = self.left.ceil();
        self.left -= dt;
        if self.left <= 0.0 {
            self.over = Some(app.attract.game_over_seconds());
            return None;
        }
        if self.left.ceil() < before {
            app.play(Event::Wall);
        }
        None
    }

    pub fn draw(&self, app: &App) {
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        app.renderer.fill(BLACK);
        if self.over.is_some() {
            crate::attract::draw_game_over(&app.attract, &app.renderer, Some("game_over"), None, white);
            return;
        }
        text(app, "CONTINUE?", 56.0, 120.0, accent);
        let sc = app.scale();
        let r = &app.renderer;
        let digit = format!("{}", (self.left.ceil() as u32).min(9));
        r.text_centered(
            &digit,
            &app.assets.font_score,
            140.0 * sc,
            r.world_w / 2.0,
            250.0 * sc,
            0.0,
            white,
        );
        let blink = (get_time() * 2.0) as i64 % 2 == 0;
        let prompt = if app.cfg.game.free_play || app.credits > 0 {
            "PRESS START"
        } else {
            "INSERT COIN"
        };
        if blink {
            text(app, prompt, 32.0, 370.0, white);
        }
        if let Some(run) = &app.run {
            text(
                app,
                &format!("LEVEL {}   SCORE RESETS TO 0", run.level + 1),
                22.0,
                420.0,
                gray,
            );
        }
    }
}

// --------------------------------------------------------------------- iniziali

/// Nuovo record: tre lettere scelte con su/giù e confermate con lo scatto (o Invio).
pub struct Initials {
    best: (u32, u8),
    /// dopo una sfida: lato del perdente (valgono solo i suoi comandi), poi il vincitore riprende
    loser: Option<Side>,
    name: [u8; 3],
    /// lettera in corso (0-2) e indice in `LETTERS` di quella sotto il cursore
    pos: usize,
    letter: usize,
    left: f64,
    knobs_ready: bool,
}

/// Tasti delle iniziali per lato: (su, giù, avanti = conferma la lettera).
const INITIALS_KEYS: [(KeyCode, KeyCode, KeyCode); 2] = [
    (KeyCode::W, KeyCode::S, KeyCode::D),
    (KeyCode::Up, KeyCode::Down, KeyCode::Left),
];

impl Initials {
    /// Gamepad come i tasti del lato (`input`): su e giù cambiano lettera, A e Start la
    /// confermano. Dopo una sfida scrive il perdente: con un solo gamepad è il suo.
    pub fn pad_keys(&self, app: &App) -> PadKeys {
        let solo = self.loser.map(|l| l as usize);
        input::pad_keys(|slot, c| {
            let (up, down, forward) = INITIALS_KEYS[app.pads.side_of(slot, solo)];
            match c {
                Control::Up => Some(up),
                Control::Down => Some(down),
                Control::A | Control::Start => Some(forward),
                _ => None,
            }
        })
    }

    pub fn new(best: (u32, u8)) -> Self {
        Self {
            best,
            loser: None,
            name: *b"AAA",
            pos: 0,
            letter: 0,
            left: INITIALS_SECONDS,
            knobs_ready: false,
        }
    }

    /// Iniziali del perdente di una sfida, che gioca dal lato `side`.
    pub fn loser(best: (u32, u8), side: Side) -> Self {
        Self {
            loser: Some(side),
            ..Self::new(best)
        }
    }

    /// Conferma la lettera sotto il cursore; dopo la terza salva e mostra la classifica (dopo
    /// una sfida invece il vincitore riprende il livello).
    fn confirm(&mut self, app: &mut App) -> Option<Scene> {
        self.name[self.pos] = LETTERS[self.letter];
        app.play(Event::Hit);
        self.pos += 1;
        if self.pos < 3 {
            return None;
        }
        let egg = egg_after(app.egg, &self.name);
        if egg != app.egg {
            app.set_egg(egg);
        }
        let rank = app.scores.insert(Entry {
            name: self.name,
            score: self.best.0,
            level: self.best.1,
        });
        save_scores(app);
        if self.loser.is_some() && app.run.is_some() {
            return Some(Scene::Intro(Intro::new(app)));
        }
        Some(Scene::Scores(Scores::new(rank)))
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        let n = LETTERS.len();
        self.left -= dt;
        if self.left <= 0.0 {
            // tempo scaduto: valgono le lettere scelte fin qui
            while self.pos < 3 {
                if let Some(scene) = self.confirm(app) {
                    return Some(scene);
                }
            }
        }
        if let Some(enc) = &mut app.encoders
            && !std::mem::replace(&mut self.knobs_ready, true)
        {
            enc.configure(0, n as i32 - 1, 1, 0);
        }
        let mut confirm = false;
        let mine = |side: usize| self.loser.is_none_or(|l| l as usize == side);
        for e in app.knob_events.clone() {
            if !mine(e.player) {
                continue;
            }
            match e.action {
                Action::Rotate(v) => self.letter = (v.max(0) as usize).min(n - 1),
                Action::Click | Action::Activate => confirm = true,
                _ => {}
            }
        }
        // tasti (su, giù, avanti) di ciascun lato; dopo una sfida solo quelli del perdente
        for (side, (up, down, forward)) in INITIALS_KEYS.into_iter().enumerate() {
            if !mine(side) {
                continue;
            }
            if input::pressed(up) {
                self.letter = (self.letter + n - 1) % n;
            }
            if input::pressed(down) {
                self.letter = (self.letter + 1) % n;
            }
            confirm |= input::pressed(forward);
        }
        // touch: un tocco in alto cambia lettera, in basso la conferma
        for p in touch::taps() {
            if p.y < app.renderer.world_h / 2.0 {
                self.letter = (self.letter + 1) % n;
            } else {
                confirm = true;
            }
        }
        // dopo una sfida niente Spazio: lo usa il vincitore per saltare le schermate
        let generic: &[KeyCode] = if self.loser.is_some() {
            &[KeyCode::Enter, KeyCode::KpEnter]
        } else {
            &[KeyCode::Enter, KeyCode::KpEnter, KeyCode::Space]
        };
        confirm |= generic.iter().any(|k| input::pressed(*k));
        if confirm {
            return self.confirm(app);
        }
        None
    }

    pub fn draw(&self, app: &App) {
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        app.renderer.fill(BLACK);
        text(app, "NEW RECORD!", 56.0, 100.0, accent);
        text(app, &format!("SCORE {}", pad(self.best.0)), 34.0, 160.0, white);
        let prompt = match self.loser {
            Some(side) => format!("P{} ENTER YOUR INITIALS", side as usize + 1),
            None => "ENTER YOUR INITIALS".to_string(),
        };
        text(app, &prompt, 28.0, 215.0, gray);
        let sc = app.scale();
        let r = &app.renderer;
        let blink = (get_time() * 4.0) as i64 % 2 == 0;
        for i in 0..3 {
            let c = match i.cmp(&self.pos) {
                std::cmp::Ordering::Less => self.name[i],
                std::cmp::Ordering::Equal => LETTERS[self.letter],
                std::cmp::Ordering::Greater => b'.',
            };
            let x = r.world_w / 2.0 + (i as f32 - 1.0) * 70.0 * sc;
            let color = if i == self.pos { accent } else { white };
            if i != self.pos || blink {
                r.text_centered(
                    &(c as char).to_string(),
                    &app.assets.font_text,
                    90.0 * sc,
                    x,
                    310.0 * sc,
                    0.0,
                    color,
                );
            }
        }
        if !app.touch {
            text(app, "UP DOWN TO CHOOSE, FORWARD TO CONFIRM", 20.0, 420.0, gray);
        }
    }
}

// --------------------------------------------------------------------- classifica

/// La classifica: dopo una partita (con il nuovo record evidenziato) e nell'attract.
pub struct Scores {
    left: f64,
    highlight: Option<usize>,
    /// mostrata dall'attract: poi viene la demo (dopo una partita si torna alle strisce)
    from_attract: bool,
}

impl Scores {
    pub fn new(highlight: Option<usize>) -> Self {
        Self {
            left: SCORES_SECONDS,
            highlight,
            from_attract: false,
        }
    }

    /// La classifica dell'attract, dopo il titolo.
    pub fn attract() -> Self {
        Self {
            from_attract: true,
            ..Self::new(None)
        }
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            return Some(Scene::Attract(Attract::new(&app.attract, false)));
        }
        // come nell'attract: gettone e Start
        if let Some(scene) = crate::scenes::coin_and_start(app) {
            return Some(scene);
        }
        self.left -= dt;
        if self.left > 0.0 {
            return None;
        }
        Some(if self.from_attract {
            Scene::Demo(Box::new(crate::scenes::Demo::new(app)))
        } else {
            Scene::Attract(Attract::new(&app.attract, false))
        })
    }

    pub fn draw(&self, app: &App) {
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        app.renderer.fill(BLACK);
        text(app, "CHALLENGE HIGH SCORES", 40.0, 55.0, accent);
        let sc = app.scale();
        let r = &app.renderer;
        let font = &app.assets.font_text;
        let w = r.world_w;
        for (i, e) in app.scores.entries.iter().enumerate().take(TABLE_SIZE) {
            let y = (110.0 + i as f32 * 31.0) * sc;
            let color = if Some(i) == self.highlight { accent } else { white };
            let level = if e.level as usize > LEVELS {
                "ALL".to_string()
            } else {
                format!("L{}", e.level)
            };
            let name = String::from_utf8_lossy(&e.name).to_string();
            for (s, x) in [
                (format!("{}", i + 1), 0.24),
                (name, 0.36),
                (pad(e.score), 0.56),
                (level, 0.76),
            ] {
                r.text_centered(&s, font, 30.0 * sc, w * x, y, 0.0, color);
            }
        }
        let prompt = if app.cfg.game.free_play || app.credits > 0 {
            "PRESS START"
        } else {
            "INSERT COIN"
        };
        if (get_time() * 2.0) as i64 % 2 == 0 {
            text(app, prompt, 24.0, r.world_h / sc - 25.0, gray);
        }
    }
}

// ------------------------------------------------------------- salvataggio

#[derive(serde::Serialize, serde::Deserialize)]
struct SavedEntry {
    name: String,
    score: u32,
    level: u8,
}

/// File della classifica, accanto alla configurazione.
fn scores_path(app: &App) -> std::path::PathBuf {
    app.config_path.with_file_name("padd_scores.json")
}

/// Classifica salvata accanto alla configurazione `config_path` (quella iniziale se manca).
pub fn load_scores(config_path: &std::path::Path) -> Table {
    let mut table = Table::default();
    let path = config_path.with_file_name("padd_scores.json");
    crate::config::migrate_old_name(&path, "pong_scores.json");
    let Some(text) = platform::read_text(&path) else {
        return table;
    };
    let Ok(saved) = serde_json::from_str::<Vec<SavedEntry>>(&text) else {
        return table;
    };
    for (slot, e) in table.entries.iter_mut().zip(saved) {
        let mut name = *b"   ";
        for (c, b) in name.iter_mut().zip(e.name.bytes()) {
            if LETTERS.contains(&b.to_ascii_uppercase()) {
                *c = b.to_ascii_uppercase();
            }
        }
        *slot = Entry {
            name,
            score: e.score,
            level: e.level,
        };
    }
    table.entries.sort_by_key(|e| std::cmp::Reverse(e.score));
    table
}

/// Salva la classifica (nel browser nel `localStorage`, come la configurazione).
fn save_scores(app: &App) {
    let saved: Vec<SavedEntry> = app
        .scores
        .entries
        .iter()
        .map(|e| SavedEntry {
            name: String::from_utf8_lossy(&e.name).to_string(),
            score: e.score,
            level: e.level,
        })
        .collect();
    if let Ok(text) = serde_json::to_string_pretty(&saved)
        && let Err(e) = platform::write_text(&scores_path(app), text.as_bytes())
    {
        eprintln!("Classifica non salvata: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_exclamation_mark_comes_after_the_space() {
        assert_eq!(&LETTERS[LETTERS.len() - 2..], b" !");
        // le lettere di prima non si spostano: la manopola e le classifiche salvate restano uguali
        assert_eq!(&LETTERS[..37], b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ");
        assert!(EGG_NAME.iter().all(|c| LETTERS.contains(c)));
    }

    #[test]
    fn ws_switches_the_egg_on_and_off() {
        let mut on = false;
        for (name, want) in [(b"WS!", true), (b"ABC", true), (b"WS ", true), (b"WS!", false), (b"!WS", false)] {
            on = egg_after(on, name);
            assert_eq!(on, want, "{}", String::from_utf8_lossy(name));
        }
    }

    #[test]
    fn saved_initials_keep_the_exclamation_mark() {
        let dir = std::env::temp_dir().join(format!("paddws_egg_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let config = dir.join("padd_config.json");
        let saved = r#"[{"name":"WS!","score":90000,"level":3},{"name":"a?b","score":50000,"level":1}]"#;
        std::fs::write(dir.join("padd_scores.json"), saved).unwrap();
        let table = load_scores(&config);
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(&table.entries[0].name, b"WS!");
        // i caratteri che non sono tra le lettere restano spazi
        assert_eq!(&table.entries[1].name, b"A B");
    }
}
