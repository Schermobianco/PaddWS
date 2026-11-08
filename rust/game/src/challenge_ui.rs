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
use paddws_core::challenge::{Entry, LEVELS, RUNGS, Score, TABLE_SIZE, Table};
use paddws_core::fixed::to_f32;
use paddws_core::{Event, Side};

use crate::attract::Attract;
use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::{Pick, draw_capsule, unit};
use crate::paddle_ui::{Look, Shape, draw_paddle, tagline};
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

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
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

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let run = app.run.as_ref().expect("CHALLENGE senza partita");
        let rung = &RUNGS[run.level];
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        r.fill(BLACK);
        let title = if run.level + 1 == LEVELS {
            "FINAL LEVEL".to_string()
        } else {
            format!("LEVEL {} OF {LEVELS}", run.level + 1)
        };
        text(app, &title, 44.0, 60.0, accent);
        // la racchetta dell'avversario, rivolta verso il giocatore
        let p = &app.params;
        let k = &p.kinds[rung.kind as usize];
        let shape = Shape {
            kind: Some(rung.kind),
            x: r.world_w / 2.0,
            y: r.world_h * 0.66, // y verso l'alto: la racchetta sta sopra il nome
            w: to_f32(p.pad_width),
            h: to_f32(k.height),
            front: if run.side == Side::Left { -1.0 } else { 1.0 },
            tilt: 0.0,
            dash: None,
            preview: true,
        };
        draw_paddle(
            r,
            &shape,
            unit(app),
            Look {
                body: white,
                mark: accent,
                detail: gray,
            },
        );
        let h = r.world_h / app.scale();
        text(app, rung.kind.name(), 52.0, h * 0.53, white);
        text(app, tagline(rung.kind), 26.0, h * 0.53 + 40.0, gray);
        // i bonus dell'avversario: capsula con l'icona e nome sotto, su tre colonne
        let (sc, u) = (app.scale(), unit(app));
        for (i, b) in rung.loadout.iter().enumerate() {
            let cx = r.world_w / 2.0 + (i as f32 - 1.0) * 150.0 * sc;
            draw_capsule(*b, cx, (h * 0.53 + 84.0) * sc, 13.0 * u, u, false, accent);
            r.text_centered(b.name(), &app.assets.font_text, 22.0 * sc, cx, (h * 0.53 + 112.0) * sc, 0.0, accent);
        }
        text(app, &format!("FIRST TO {}", rung.points), 26.0, h * 0.53 + 150.0, gray);
        text(
            app,
            &format!("SCORE {}    HI {}", pad(run.score), pad(app.scores.entries[0].score)),
            28.0,
            h - 30.0,
            white,
        );
        draw_join_hint(app, run.side.opponent());
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
            crate::attract::draw_game_over(&app.attract, &app.renderer, true, None, white);
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
