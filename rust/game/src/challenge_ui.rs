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
//!
//! OMEGA, il boss segreto: chi finisce la scala a HARD o EXPERT partendo dal livello 1 senza
//! continue (`omega_open`) dopo il GUARDIAN trova l'allarme (`Warning`) e la presentazione di
//! OMEGA invece del finale. Contro OMEGA non entrano sfidanti e non ci sono continue: persa, GAME
//! OVER e il finale normale; vinta, i premi (`Clear`) e il finale speciale. È il livello
//! `OMEGA_LEVEL` (dopo i sette della scala): `rung` dà il suo `Rung` come quello degli altri.

use macroquad::prelude::*;
use paddws_core::challenge::{
    Entry, LEVELS, OMEGA, OMEGA_LEVEL, RUNGS, Rung, SCORE_LEVEL_OMEGA, Score, TABLE_SIZE, Table,
};
use paddws_core::fixed::to_f32;
use paddws_core::{Event, PaddleKind, Side};

use crate::attract::Attract;
use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::{draw_capsule, unit};
use crate::paddle_ui::{
    self, Anim, HALF_X, PADDLE_X, PORTRAIT_H, PORTRAIT_W, PORTRAIT_X, PaddlePick, Shape, TOP, TWIST_MAX_TILT, draw_paddle, line,
    tagline,
};
use crate::platform;
use crate::render::{ArtPaint, ArtPart, PixelArt, TEXT_1X};
use crate::scenes::{App, Menu, Play, START_KEYS, Scene};
use crate::titles;
use crate::touch;

/// Durata delle schermate, in secondi.
const INTRO_SECONDS: f64 = 4.0;
/// OMEGA: la presentazione è più lunga, perché la racchetta passa per tutte le sette forme.
const OMEGA_INTRO_SECONDS: f64 = 5.0;
const CLEAR_SECONDS: f64 = 4.0;
const CONTINUE_SECONDS: f64 = 10.0;
const INITIALS_SECONDS: f64 = 30.0;
const SCORES_SECONDS: f64 = 8.0;
/// Classifica animata (`Scores::draw`): la palla parte da `SCORES_BALL_Y` sopra la prima riga e
/// scende di `SCORES_BALL_VY` unità al secondo rimbalzando fra i bordi (`SCORES_BALL_VX` larghezze
/// al secondo); ogni riga che tocca si accende e i suoi punti contano da zero in `SCORES_COUNT`
/// secondi. Da `SCORES_MARK` due racchette arrivano dai bordi ai lati del posto appena inserito (in
/// `SCORES_MARK_IN`) e un riflesso lo attraversa in `SCORES_GLINT` secondi, ogni `SCORES_GLINT_PERIOD`.
const SCORES_BALL_Y: f32 = 60.0;
const SCORES_BALL_VY: f32 = 140.0;
const SCORES_BALL_VX: f32 = 0.9;
const SCORES_COUNT: f64 = 0.7;
const SCORES_MARK: f64 = 3.2;
const SCORES_MARK_IN: f64 = 0.6;
const SCORES_GLINT: f64 = 0.5;
const SCORES_GLINT_PERIOD: f64 = 1.6;
/// prima riga della classifica (centro) e passo, in unità
const SCORES_ROW_Y: f32 = 110.0;
const SCORES_ROW_STEP: f32 = 36.0;
/// Righe della classifica a schermo (la tabella ne tiene `TABLE_SIZE`): un posto nuovo più in
/// basso prende il posto dell'ultima.
const SCORES_ROWS: usize = 8;
/// Centri delle colonne (posto, iniziali, punti, livello) dal centro dello schermo, in unità a 480
/// righe: con le scritte a 1x restano almeno due caratteri fra una colonna e l'altra.
const SCORES_COLS: [f32; 4] = [-165.0, -90.0, 20.0, 145.0];
/// Dal centro dello schermo al lato esterno delle racchette del posto nuovo, in unità.
const SCORES_REACH: f32 = 215.0;
const CHALLENGER_SECONDS: f64 = 3.0;
/// Nuovo sfidante (unità a 480 righe dal centro): bande lampeggianti (alte `CHALLENGER_BAND_H`), centro
/// della targa disegnata, riga dello sfidante sotto.
const CHALLENGER_BAND: f32 = 80.0;
const CHALLENGER_BAND_H: f32 = 8.0;
const CHALLENGER_PLATE: f32 = -22.0;
const CHALLENGER_LINE: f32 = 38.0;
/// touch: tocco prolungato nella metà libera con cui entra uno sfidante
pub(crate) const HOLD_SECONDS: f64 = 1.0;
/// le schermate si possono saltare solo dopo questo tempo (non si salta per sbaglio); il continue si
/// accetta quasi subito, già con il 9
const SKIP_AFTER: f64 = 1.0;
const CONTINUE_SKIP_AFTER: f64 = 0.25;
/// continue: pallina che rimbalza accanto al numero e tocca terra quando il numero cambia, alta
/// BOUNCE_HEIGHT (unità a 480 righe)
const BOUNCE_HEIGHT: f32 = 70.0;
/// la voce dice il nome dell'avversario dopo questo tempo dall'inizio della presentazione
const ANNOUNCE_AFTER: f64 = 0.5;

/// Lettere delle iniziali, in ordine (come nel C64, `c64/src/challenge.s`). Il "!" è in fondo,
/// dopo lo spazio: le classifiche salvate prima restano uguali.
const LETTERS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !";

/// Iniziali segrete: confermate accendono l'easter egg, la volta dopo lo spengono
/// (`App::set_egg`). Il record si salva come gli altri.
const EGG_NAME: &[u8; 3] = b"RED";

/// Easter egg dopo le iniziali `name`, se prima era `on`: "RED" lo accende o lo spegne.
pub(crate) fn egg_after(on: bool, name: &[u8; 3]) -> bool {
    on ^ (name == EGG_NAME)
}

/// Iniziali segrete che sbloccano il JUKEBOX per sempre (come battere OMEGA).
const JUKEBOX_NAME: &[u8; 3] = b"BAS";

/// JUKEBOX sbloccato dopo le iniziali `name`, se prima era `unlocked`: "BAS" lo sblocca, niente
/// lo blocca più.
pub(crate) fn jukebox_after(unlocked: bool, name: &[u8; 3]) -> bool {
    unlocked || name == JUKEBOX_NAME
}

/// Difficoltà minima per OMEGA (HARD).
const OMEGA_DIFFICULTY: u8 = 2;

/// L'avversario del livello `level` (da 0): quello della scala, o OMEGA a `OMEGA_LEVEL`.
pub(crate) fn rung(level: usize) -> &'static Rung {
    if level == OMEGA_LEVEL { &OMEGA } else { &RUNGS[level.min(LEVELS - 1)] }
}

/// Nome dell'avversario del livello `level` (da 0), come nel menu OPPONENT.
pub(crate) fn opponent_name(level: usize) -> &'static str {
    if level == OMEGA_LEVEL { "OMEGA" } else { rung(level).kind.name() }
}

/// Battuto il GUARDIAN arriva OMEGA: nella scalata (non nell'allenamento) fatta tutta dal livello 1
/// senza continue (`Run::clean`), a HARD o EXPERT.
pub(crate) fn omega_open(run: &Run, difficulty: u8) -> bool {
    !run.training && run.clean && run.level + 1 == LEVELS && difficulty >= OMEGA_DIFFICULTY
}

/// Livello della classifica a schermo: LV1-LV7, ALL per la scala finita, ALL+ con OMEGA battuto.
pub(crate) fn level_label(level: u8) -> String {
    match level {
        SCORE_LEVEL_OMEGA.. => "ALL+".to_string(),
        l if l as usize > LEVELS => "ALL".to_string(),
        l => format!("LV{l}"),
    }
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
    /// duelli vinti di fila dal campione in carica (chi tiene il posto contro la CPU): 0 finché
    /// non c'è stato un duello, 1 per chi ha appena preso il posto (`duel_won_by`)
    pub wins: u16,
    /// allenamento (voce OPPONENT del menu): una sola partita contro l'avversario del livello,
    /// senza punti arcade, classifica, continue né sfidanti; poi si torna al menu
    pub training: bool,
    /// scala fatta dal livello 1 senza continue: con HARD o EXPERT dopo il GUARDIAN arriva OMEGA
    /// (`omega_open`). La perde chi continua e lo sfidante che prende il posto del campione
    pub clean: bool,
    /// punti fatti dal GUARDIAN: il premio del campione arriva con il finale, dopo OMEGA
    pub guardian: u16,
    /// OMEGA battuto: finale speciale e ALL+ in classifica
    pub omega_won: bool,
}

impl Run {
    pub fn new() -> Self {
        Self {
            level: 0,
            score: 0,
            best: (0, 1),
            side: Side::Left,
            howto: [false; 2],
            wins: 0,
            training: false,
            clean: true,
            guardian: 0,
            omega_won: false,
        }
    }

    /// Allenamento contro l'avversario del livello `level` (da 0; `OMEGA_LEVEL` per OMEGA).
    pub fn training(level: usize) -> Self {
        Self {
            level: if level == OMEGA_LEVEL { level } else { level.min(LEVELS - 1) },
            training: true,
            clean: false,
            ..Self::new()
        }
    }

    /// Contro OMEGA.
    pub fn omega(&self) -> bool {
        self.level == OMEGA_LEVEL
    }

    pub(crate) fn remember(&mut self, level: u8) {
        if self.score > self.best.0 {
            self.best = (self.score, level);
        }
    }

    /// Duelli vinti di fila dopo un duello vinto dal lato `winner`: il campione ne aggiunge uno,
    /// lo sfidante che vince diventa il campione con il primo (vedi `wins`).
    pub(crate) fn wins_after(&self, winner: Side) -> u16 {
        if winner == self.side { self.wins.saturating_add(1) } else { 1 }
    }

    /// Fine di un duello vinto dal lato `winner`: conta i duelli vinti di fila e, se ha vinto lo
    /// sfidante, gli passa il posto. True se ha vinto il campione.
    pub(crate) fn duel_won_by(&mut self, winner: Side) -> bool {
        self.wins = self.wins_after(winner);
        let champion_won = winner == self.side;
        self.side = winner;
        // lo sfidante che prende il posto non ha fatto la scala dal livello 1: niente OMEGA
        self.clean &= champion_won;
        champion_won
    }
}

/// Duelli vinti di fila, "n WINS", centrata in (x, y) di disegno e ruotata di `rotation`: nel
/// colore di accento, come chi ha vinto in NEXT, su un fondo nero (la partita può essere ancora a
/// schermo). Niente scritta senza duelli vinti.
pub(crate) fn draw_wins(app: &App, wins: u16, x: f32, y: f32, rotation: f32) {
    if wins == 0 {
        return;
    }
    let r = &app.renderer;
    let sc = scale(app);
    let font = &app.assets.font_text;
    let size = T1 * sc;
    let label = format!("{wins} WINS");
    let (half_w, half_h) = (
        r.text_width(&label, font, size) / 2.0 + 4.0 * sc,
        r.text_height(&label, font, size) / 2.0 + 4.0 * sc,
    );
    let (bw, bh) = if rotation == 0.0 { (half_w, half_h) } else { (half_h, half_w) };
    draw_rectangle(x - bw, y - bh, 2.0 * bw, 2.0 * bh, BLACK);
    r.text_centered(&label, font, size, x, y, rotation, App::color(app.cfg.colors.accent));
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

/// Lato libero per uno sfidante, se c'è una scalata in corso (nell'allenamento e contro OMEGA non
/// entra nessuno).
fn free_side(app: &App) -> Option<Side> {
    app.run.as_ref().filter(|r| !r.training && !r.omega()).map(|r| r.side.opponent())
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
    let sc = scale(app);
    let font = &app.assets.font_text;
    // a un sesto dal bordo, ma mai fuori dallo schermo (il campo 4:3 è stretto)
    let half = r.text_width(&prompt, font, T1 * sc) / 2.0 + 8.0 * sc;
    let x = if free == Side::Left {
        (r.world_w * 0.15).max(half)
    } else {
        (r.world_w * 0.85).min(r.world_w - half)
    };
    let gray = App::color(app.cfg.colors.lgray);
    r.text_centered(&prompt, font, T1 * sc, x, 20.0 * sc, 0.0, gray);
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
        Some(Scene::Paddles(PaddlePick::challenger(app, free)))
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let sc = scale(app);
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        r.fill(BLACK);
        // lampeggio: la scritta scambia bianco e giallo, le bande accento e grigio
        let on = (get_time() * 4.0) as i64 % 2 == 0;
        let band = CHALLENGER_BAND_H * sc;
        for (i, y) in [h / 2.0 - CHALLENGER_BAND * sc, h / 2.0 + CHALLENGER_BAND * sc - band].into_iter().enumerate() {
            draw_rectangle(0.0, y, w, band, if on == (i == 0) { accent } else { gray });
        }
        let mid = h / sc / 2.0;
        // HERE COMES A NEW CHALLENGER! è la targa disegnata (`titles`), a 1x: nel lampeggio il
        // bianco e il giallo si scambiano, come facevano le due righe di testo
        let paint = titles::paint(colors);
        let paint = if on { paint } else { titles::swap_white_yellow(&paint) };
        r.art_centered(&app.assets.titles.challenger, 1.0, w / 2.0, (mid + CHALLENGER_PLATE) * sc, 0.0, ArtPart::Whole, &paint);
        if let Some(run) = &app.run {
            let who = if run.side == Side::Left { "P2" } else { "P1" };
            let line = format!("{who} VS CHAMPION   FIRST TO {}", rung(run.level).points);
            text(app, &line, T1, mid + CHALLENGER_LINE, white);
        }
    }
}

/// Fine della sfida: ha vinto il lato `winner`. Il vincitore prende `Score::after_duel` punti e
/// riprende il livello dal suo lato; prima il perdente mette le iniziali se il suo punteggio
/// migliore della sessione entra in classifica (lo sfidante entra con 0 punti: non succede).
pub fn duel_over(app: &mut App, winner: Side) -> Scene {
    let run = app.run.as_mut().expect("sfida senza CHALLENGE");
    let loser_best = (winner != run.side).then_some(run.best);
    let champion_won = run.duel_won_by(winner);
    run.score = Score::after_duel(run.score, champion_won, run.level);
    if !champion_won {
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

/// Scala delle schermate della CHALLENGE, disegnate su 480 righe: quella del campo, ma non oltre
/// l'altezza. Con il campo largo (nel browser fino a 2,2:1) la scala del campo, media tra larghezza
/// e altezza, porterebbe le ultime righe sotto il bordo e sopra il punteggio.
pub(crate) fn scale(app: &App) -> f32 {
    app.scale().min(app.renderer.world_h / 480.0)
}

/// Scritte a 1x (8 pixel arcade, `render::TEXT_1X`) nelle unità a 480 righe di `scale`: il
/// disegno le porta comunque alla grandezza esatta.
pub(crate) const T1: f32 = 2.0 * TEXT_1X;

/// Testo centrato su `y` (unità a 480 righe), nel font dei testi, alto `size` (`T1`).
fn text(app: &App, s: &str, size: f32, y: f32, color: Color) {
    let sc = scale(app);
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

/// L'avversario del livello nello schermo VS: ritratti, racchette a grandezza reale, nomi, bonus e
/// punteggio. Anche prima di una sfida tra due giocatori (`Intro::duel`), con i due giocatori.
pub struct Intro {
    /// durata (`INTRO_SECONDS`, `OMEGA_INTRO_SECONDS` per OMEGA) e secondi che restano
    length: f64,
    left: f64,
    hold: Hold,
    /// nome dell'avversario già annunciato
    announced: bool,
    /// sfida tra due giocatori: poi la sfida, nessun avversario da annunciare né sfidanti
    duel: bool,
}

impl Intro {
    pub fn new(app: &App) -> Self {
        app.play(Event::Boost);
        let length = if app.run.as_ref().is_some_and(Run::omega) { OMEGA_INTRO_SECONDS } else { INTRO_SECONDS };
        Self {
            length,
            left: length,
            hold: Hold::default(),
            announced: false,
            duel: false,
        }
    }

    /// Prima della sfida tra due giocatori (lo sfidante appena entrato, o la sfida che apre la
    /// scalata): lo schermo VS con i due giocatori, poi la sfida.
    pub fn duel(app: &App) -> Self {
        Self {
            announced: true,
            duel: true,
            ..Self::new(app)
        }
    }

    /// Per la verifica automatica: porta la presentazione a `seconds` dall'inizio.
    pub fn skip_to(&mut self, seconds: f64) {
        self.left = self.length - seconds;
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
        // nell'allenamento e nella sfida non c'è un lato libero: lo Start (o un tocco) salta e basta
        let free = if self.duel { None } else { free_side(app) };
        let mut tap = false;
        if let Some(free) = free {
            insert_coin(app);
            let held;
            (tap, held) = self.hold.update(app, free, dt);
            if challenger(app, free, held) {
                return Some(Scene::Challenger(Challenger::new(app)));
            }
        }
        let before = ((self.length - self.left) * 60.0) as f32;
        self.left -= dt;
        // schermo VS: un colpo quando i ritratti si posano e quando si posa il VS
        let now = ((self.length - self.left) * 60.0) as f32;
        let start = if app.run.as_ref().is_some_and(Run::omega) { OMEGA_VS_AT } else { 0.0 };
        let crossed = |at: f32| before < start + at && now >= start + at;
        if crossed(VS_LAND) {
            app.play(Event::Hit);
        }
        if crossed(VS_STAMP_AT + VS_STAMP_SETTLE) {
            app.play(Event::Score);
        }
        // la voce dice il nome dell'avversario poco dopo l'inizio del jingle
        if !self.announced && self.left <= self.length - ANNOUNCE_AFTER {
            self.announced = true;
            let run = app.run.as_ref().expect("CHALLENGE senza partita");
            if run.omega() {
                app.announce_omega();
            } else {
                app.announce(RUNGS[run.level].kind);
            }
        }
        let start = match free {
            Some(free) => champion_start(app, free, tap),
            // nella sfida salta lo Start di tutti e due
            None if self.duel => start_pressed(app) || input::any_pressed(&SIDE_START),
            None => start_pressed(app),
        };
        let skip = self.left < self.length - SKIP_AFTER && start;
        (self.left <= 0.0 || skip).then(|| {
            if self.duel {
                Scene::Game(Box::new(Play::duel(app)))
            } else {
                Scene::Game(Box::new(Play::challenge(app)))
            }
        })
    }

    /// Presentazione animata: in cima la scala dei livelli, poi lo schermo VS (`Stage::vs`); per
    /// OMEGA prima la sua racchetta che cambia forma e il sigillo.
    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let run = app.run.as_ref().expect("CHALLENGE senza partita");
        r.fill(BLACK);
        let f = ((self.length - self.left) * 60.0).floor() as f32;
        let st = Stage::new(app, run, f, self.duel);
        st.header();
        // OMEGA prima la sua parte speciale (forme e sigillo), poi come gli altri lo schermo VS
        if st.omega && st.f < OMEGA_VS_AT {
            st.omega();
        } else {
            st.vs();
        }
        if run.training {
            return; // l'allenamento non ha punti arcade né sfidanti
        }
        if !self.duel {
            text(
            app,
                &format!("SCORE {}    HI {}", pad(run.score), pad(app.scores.entries[0].score)),
                T1,
                r.world_h / scale(app) - 30.0,
                App::color(app.cfg.colors.white),
            );
            if let Some(free) = free_side(app) {
                draw_join_hint(app, free);
            }
        }
        // dopo un duello: quanti ne ha vinti di fila il campione, dal suo lato (di fronte
        // all'invito per lo sfidante)
        let sc = scale(app);
        let x = if run.side == Side::Left { r.world_w * 0.15 } else { r.world_w * 0.85 };
        draw_wins(app, run.wins, x, 22.0 * sc, 0.0);
    }
}

// Presentazione: righe (unità a 480 righe) della scala, del livello, del centro della racchetta,
// del motto (da qui 4 pixel arcade più in basso, `Stage::tag_row`; il nome sta subito sopra,
// `Stage::name_row`), delle capsule e dei loro nomi, dei punti da fare. La riga in cima resta
// all'invito per lo sfidante e ai duelli vinti (a 1x "P2 PRESS START" toccava la scala).
const LADDER_Y: f32 = 38.0;
const LEVEL_Y: f32 = 68.0;
const PAD_Y: f32 = 163.0;
const TAG_Y: f32 = 286.0;
/// Schermo VS (`Stage::vs`), in frame dall'inizio: i ritratti scivolano dentro da `VS_SLIDE_AT` per
/// `VS_SLIDE` frame e si posano con un colpo; VS si stampa da `VS_STAMP_AT` e si posa a 2x
/// `VS_STAMP_SETTLE` frame dopo (un altro colpo); la rete da `VS_COURT_AT` (una riga di trattini per
/// frame), le racchette da `VS_PADDLES_AT`; nome e motto del giocatore da `VS_NAME_AT` e `VS_TAG_AT`,
/// quelli dell'avversario `VS_THEIRS` frame dopo; le icone dei bonus da `VS_ICONS_AT`, una ogni
/// `VS_ICON_GAP`; i punti da fare a `VS_FIRST_AT`.
const VS_SLIDE_AT: f32 = 6.0;
const VS_SLIDE: f32 = 16.0;
const VS_LAND: f32 = VS_SLIDE_AT + VS_SLIDE;
const VS_STAMP_AT: f32 = 24.0;
const VS_STAMP_SETTLE: f32 = 7.0;
const VS_COURT_AT: f32 = 34.0;
const VS_PADDLES_AT: f32 = 42.0;
const VS_NAME_AT: f32 = 44.0;
const VS_THEIRS: f32 = 6.0;
const VS_TAG_AT: f32 = 54.0;
const VS_ICONS_AT: f32 = 74.0;
const VS_ICON_GAP: f32 = 6.0;
const VS_FIRST_AT: f32 = 100.0;
/// Schermo VS: posizioni in pixel del campo 320x240, sulle righe di caratteri del C64 (da `TOP`):
/// ritratti righe 1-13 (ai lati della scritta del livello), VS alla 4, campo righe 6-14, nomi
/// 15-18 (il sigillo di OMEGA, alto 33, da metà della 14), motti 19, icone 20-21, punti 22.
const VS_PORTRAIT_Y: f32 = TOP + 8.0;
const VS_Y: f32 = TOP + 4.0 * 8.0;
const VS_COURT_Y: f32 = TOP + 6.0 * 8.0;
const VS_COURT_H: f32 = 9.0 * 8.0;
/// centro dei nomi disegnati (righe 15-18); i più alti (TITAN, il sigillo di OMEGA alto 33) salgono
/// quanto basta a finire a `VS_NAME_BOTTOM`, 4 righe sopra il motto
const VS_NAME_Y: f32 = TOP + 15.0 * 8.0 + 16.0;
const VS_NAME_BOTTOM: f32 = TOP + 19.0 * 8.0 - 4.0;

/// Centro verticale di un nome disegnato alto `h` nello schermo VS.
fn vs_name_y(h: f32) -> f32 {
    VS_NAME_Y.min(VS_NAME_BOTTOM - h / 2.0)
}
const VS_TAG_ROW: u32 = 19;
const VS_ICON_Y: f32 = TOP + 20.0 * 8.0 + 8.0;
const VS_FIRST_ROW: u32 = 22;
/// OMEGA: la racchetta passa per le sette forme, una ogni `OMEGA_FORM_FRAMES` da `OMEGA_FORMS_AT`,
/// poi torna ARCADE; a ogni cambio un lampo bianco (`OMEGA_FLASH` frame per l'ultimo, come in
/// partita; la metà per gli altri, che sono più fitti).
const OMEGA_FORMS_AT: f32 = 6.0;
const OMEGA_FORM_FRAMES: f32 = 14.0;
const OMEGA_FLASH: f32 = 8.0;
/// OMEGA: il sigillo arriva a questo frame, con la racchetta già tornata ARCADE; poi lo schermo VS.
const OMEGA_NAME_AT: f32 = 110.0;
/// OMEGA: da questo frame lo schermo VS, con il suo ritratto svelato (`Stage::vs`, i tempi del VS
/// contati da qui).
const OMEGA_VS_AT: f32 = 150.0;
/// Motto di OMEGA.
pub(crate) const OMEGA_TAG: &str = "IT BECOMES THEM ALL";

/// Presentazione: riga del motto (unità a 480 righe, scala `sc`, `u` unità per pixel arcade), 4
/// pixel arcade sotto `TAG_Y` per fare posto al nome disegnato.
fn tag_row(sc: f32, u: f32) -> f32 {
    TAG_Y + 4.0 * u / sc
}

/// Presentazione: riga del centro del nome (unità a 480 righe) con il motto alto `tag_h` e il nome
/// alto `name_h` (unità di disegno): la grafica finisce 4 pixel arcade sopra l'inchiostro del
/// motto, alta quanto è (TITAN è alto più del triplo di una scritta).
fn name_row(sc: f32, u: f32, tag_h: f32, name_h: f32) -> f32 {
    tag_row(sc, u) - (tag_h / 2.0 + 4.0 * u + name_h / 2.0) / sc
}

/// Una presentazione al frame `f` (60 al secondo, dall'inizio). Le x si danno come distanza dal
/// centro verso la metà campo dell'avversario (`x`), da dove entra; le y come righe a 480 (`y`).
struct Stage<'a> {
    app: &'a App,
    rung: &'static Rung,
    level: usize,
    /// allenamento: TRAINING al posto del livello
    training: bool,
    /// OMEGA, il boss segreto
    omega: bool,
    /// sfida tra due giocatori (`Intro::duel`)
    duel: bool,
    f: f32,
    /// +1 se l'avversario sta a destra (il giocatore a sinistra), -1 altrimenti
    away: f32,
    sc: f32,
    u: f32,
    shake: (f32, f32),
    white: Color,
    gray: Color,
    accent: Color,
    /// colori dei ruoli delle grafiche (`titles::paint`)
    paint: ArtPaint,
}

impl<'a> Stage<'a> {
    fn new(app: &'a App, run: &Run, f: f32, duel: bool) -> Self {
        let rung = rung(run.level);
        let colors = &app.cfg.colors;
        let mut st = Self {
            app,
            rung,
            level: run.level,
            training: run.training,
            omega: run.omega() && !duel,
            duel,
            f,
            away: if run.side == Side::Left { 1.0 } else { -1.0 },
            sc: scale(app),
            u: unit(app),
            shake: (0.0, 0.0),
            white: App::color(colors.white),
            gray: App::color(colors.lgray),
            accent: App::color(colors.accent),
            paint: titles::paint(colors),
        };
        let (dx, dy) = st.shake_at();
        st.shake = (dx * st.sc, dy * st.sc);
        st
    }

    /// Scossa dello schermo di questo frame (unità a 480 righe).
    fn shake_at(&self) -> (f32, f32) {
        let f = self.f;
        match self.rung.kind {
            // OMEGA: un colpo a ogni cambio di forma
            _ if self.omega && f < OMEGA_VS_AT => {
                let since = f - OMEGA_FORMS_AT;
                let change = (0.0..=LEVELS as f32 * OMEGA_FORM_FRAMES).contains(&since) && since % OMEGA_FORM_FRAMES == 0.0;
                if change { (3.0, 0.0) } else { (0.0, 0.0) }
            }
            // VS: i ritratti che si posano, poi il VS che si posa
            _ => match f - self.vs_at() {
                v if v == VS_LAND => (0.0, 6.0),
                v if v == VS_LAND + 1.0 => (0.0, -3.0),
                v if v == VS_STAMP_AT + VS_STAMP_SETTLE => (4.0, 0.0),
                v if v == VS_STAMP_AT + VS_STAMP_SETTLE + 1.0 => (-2.0, 0.0),
                _ => (0.0, 0.0),
            },
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

    /// Scala dei livelli: sette trattini come quelli della mezzeria (battuti bianchi, quello di
    /// adesso giallo che lampeggia, gli altri spenti), che compaiono uno ogni due frame, e sotto il
    /// livello (FINAL LEVEL lampeggia; con OMEGA tutti battuti e SECRET LEVEL che lampeggia).
    fn header(&self) {
        let f = self.f;
        if self.duel {
            // la sfida: i due giocatori sopra i ritratti, CHALLENGE al centro
            for (side, x) in PORTRAIT_X.iter().enumerate() {
                let c = paddle_ui::at(self.app, x + PORTRAIT_W / 2.0, line(0));
                self.app.renderer.text_centered(&format!("P{}", side + 1), self.font(), self.app.renderer.text_1x(), c.x, c.y, 0.0, self.white);
            }
            if f >= 14.0 {
                self.text_at("CHALLENGE", T1, self.x(0.0), self.y(LEVEL_Y), self.accent);
            }
            return;
        }
        let dim = Color { a: 0.25, ..self.white };
        let w = self.app.renderer.world_w;
        for i in 0..LEVELS {
            if f < 2.0 * i as f32 {
                break;
            }
            // nell'allenamento nessun livello è stato battuto: si vede solo dove sta l'avversario
            let color = match i.cmp(&self.level) {
                std::cmp::Ordering::Less if !self.training => self.white,
                std::cmp::Ordering::Equal if (f / 8.0) as i64 % 2 == 0 => self.accent,
                _ => dim,
            };
            let x = w / 2.0 + (i as f32 * 48.0 - 160.0) * self.sc + self.shake.0;
            draw_rectangle(x, self.y(LADDER_Y), 32.0 * self.sc, 10.0 * self.sc, color);
        }
        let last = (self.level + 1 == LEVELS || self.omega) && !self.training;
        if f >= 14.0 && (!last || (f / 10.0) as i64 % 2 == 0) {
            let title = if self.training {
                "TRAINING".to_string()
            } else if self.omega {
                "SECRET LEVEL".to_string()
            } else if last {
                "FINAL LEVEL".to_string()
            } else {
                format!("LEVEL {} OF {LEVELS}", self.level + 1)
            };
            self.text_at(&title, T1, self.x(0.0), self.y(LEVEL_Y), self.accent);
        }
    }

    /// Il nome dell'avversario: la sua grafica (`titles`), alla grandezza delle scritte a 1x.
    fn name_art(&self) -> &PixelArt {
        if self.omega { &self.app.assets.titles.omega } else { self.app.assets.titles.name(self.rung.kind) }
    }

    /// Il motto dell'avversario.
    fn tag(&self) -> &'static str {
        if self.omega { OMEGA_TAG } else { tagline(self.rung.kind) }
    }

    /// Grandezza del nome in unità di disegno.
    fn name_size(&self) -> Vec2 {
        self.app.renderer.art_size(self.name_art(), 1.0)
    }

    fn name_row(&self) -> f32 {
        let tag = self.app.renderer.text_height(self.tag(), self.font(), T1 * self.sc);
        name_row(self.sc, self.u, tag, self.name_size().y)
    }

    /// Il nome centrato in (x, y) di disegno, ruotato di `rotation`, nei colori `paint`; `part`
    /// ne disegna solo un pezzo (una lettera), al suo posto.
    fn name(&self, x: f32, y: f32, rotation: f32, part: ArtPart, paint: &ArtPaint) {
        self.app.renderer.art_centered(self.name_art(), 1.0, x, y, rotation, part, paint);
    }

    /// Primo frame dello schermo VS: subito, o per OMEGA dopo le forme e il sigillo.
    fn vs_at(&self) -> f32 {
        if self.omega { OMEGA_VS_AT } else { 0.0 }
    }

    /// Lo schermo VS, al posto delle entrate dei singoli avversari (per OMEGA dopo la sua parte
    /// speciale, con il ritratto svelato per la prima volta e la racchetta rossa): i due ritratti scivolano dentro
    /// dai lati e si posano con un colpo, VS si stampa grande e si posa, poi il campo con le due
    /// racchette a grandezza reale, i nomi, i motti scritti una lettera per frame, le icone dei bonus
    /// di tutti e due e i punti da fare. Ognuno dalla parte in cui gioca: il giocatore sul suo lato
    /// (`Run::side`), l'avversario sull'altro. Disposizione sulla griglia di caratteri del C64, come
    /// la scelta della racchetta (`paddle_ui::at`).
    fn vs(&self) {
        let app = self.app;
        let r = &app.renderer;
        let (f, u) = (self.f - self.vs_at(), self.u);
        let run = app.run.as_ref().expect("CHALLENGE senza partita");
        let me = run.side as usize;
        let mut kinds = [app.paddles[me].unwrap_or(PaddleKind::Arcade); 2];
        let mut bonuses = [app.loadout[me]; 2];
        if self.duel {
            // la sfida: tutti e due con quello che hanno scelto
            kinds = app.paddles.map(|k| k.unwrap_or(PaddleKind::Arcade));
            bonuses = app.loadout;
        } else {
            kinds[1 - me] = self.rung.kind;
            bonuses[1 - me] = self.rung.loadout;
        }
        let shake = vec2(self.shake.0, self.shake.1);
        let at = |x: f32, y: f32| paddle_ui::at(app, x, y) + shake;
        let font = self.font();
        let t1 = r.text_1x();

        // i ritratti, da fuori dello schermo (anche largo) al loro posto, frenando
        if f >= VS_SLIDE_AT {
            let k = ((f - VS_SLIDE_AT) / VS_SLIDE).min(1.0);
            let ease = 1.0 - (1.0 - k).powi(3);
            let half = r.world_w / u / 2.0; // mezza larghezza dello schermo in pixel del campo
            for side in 0..2 {
                let end = PORTRAIT_X[side];
                let start = if side == 0 { 160.0 - half - PORTRAIT_W } else { 160.0 + half };
                let corner = at(start + (end - start) * ease, VS_PORTRAIT_Y);
                let params = DrawTextureParams {
                    dest_size: Some(vec2(PORTRAIT_W, PORTRAIT_H) * u),
                    flip_x: side == 1,
                    ..Default::default()
                };
                let texture = if self.omega && side != me {
                    &app.assets.portraits.omega_big
                } else {
                    app.assets.portraits.big(kinds[side])
                };
                draw_texture_ex(texture, corner.x, corner.y, WHITE, params);
            }
        }
        // VS: a 4x, poi 3x, poi si posa a 2x
        if f >= VS_STAMP_AT {
            let t = f - VS_STAMP_AT;
            let times = if t < 4.0 { 4.0 } else if t < VS_STAMP_SETTLE { 3.0 } else { 2.0 };
            let c = at(160.0, VS_Y);
            r.text_centered("VS", font, t1 * times, c.x, c.y, 0.0, self.accent);
        }
        // il campo: la rete si disegna dall'alto, poi le due racchette
        if f >= VS_COURT_AT {
            let last = VS_COURT_Y + ((f - VS_COURT_AT + 1.0) * 8.0).min(VS_COURT_H);
            let mut y = VS_COURT_Y + 2.0;
            while y < last {
                let p = at(160.0, y);
                draw_rectangle(p.x - u, p.y, 2.0 * u, 5.0 * u, self.white);
                y += 8.0;
            }
        }
        if f >= VS_PADDLES_AT {
            for (side, &kind) in kinds.iter().enumerate() {
                let c = at(PADDLE_X[side], VS_COURT_Y + VS_COURT_H / 2.0);
                let shape = Shape {
                    kind: Some(kind),
                    x: c.x,
                    y: r.screen_y(c.y),
                    w: to_f32(app.params.pad_width),
                    h: to_f32(app.params.kinds[kind as usize].height),
                    front: if side == 0 { 1.0 } else { -1.0 },
                    tilt: if kind == PaddleKind::Twist { TWIST_MAX_TILT } else { 0.0 },
                    dash: None,
                    preview: true,
                    anim: Anim::still(get_time() as f32),
                };
                let body = if self.omega && side != me { crate::next_ui::omega_color(app) } else { self.white };
                draw_paddle(r, &shape, u, paddle_ui::look(app, Some(kind), body));
            }
        }
        // nomi, motti e bonus: prima il giocatore, poi l'avversario `VS_THEIRS` frame dopo
        for side in 0..2 {
            let kind = kinds[side];
            // l'avversario (nella sfida, il giocatore di destra) arriva dopo, con il motto in grigio
            let theirs = if self.duel { side == 1 } else { side != me };
            let delay = if theirs { VS_THEIRS } else { 0.0 };
            if f >= VS_NAME_AT + delay {
                let art = if theirs && !self.duel { self.name_art() } else { app.assets.titles.name(kind) };
                let half = art.w / 2.0 + 2.0;
                let c = at((PORTRAIT_X[side] + PORTRAIT_W / 2.0).clamp(half, 320.0 - half), vs_name_y(art.h));
                r.art_centered(art, 1.0, c.x, c.y, 0.0, ArtPart::Whole, &self.paint);
            }
            let t0 = VS_TAG_AT + delay;
            if f >= t0 {
                // la parte scritta, allineata dove starà il motto intero
                let tag = if theirs && !self.duel { self.tag() } else { tagline(kind) };
                let n = ((f - t0) as usize + 1).min(tag.len());
                let full = r.text_width(tag, font, t1);
                let part = r.text_width(&tag[..n], font, t1);
                let c = at(HALF_X[side], line(VS_TAG_ROW));
                let color = if theirs && !self.duel { self.gray } else { self.white };
                r.text_centered(&tag[..n], font, t1, c.x - full / 2.0 + part / 2.0, c.y, 0.0, color);
            }
            for (i, &bonus) in bonuses[side].iter().enumerate() {
                let s = VS_ICONS_AT + delay / 2.0 + VS_ICON_GAP * i as f32;
                if f >= s {
                    let c = at(HALF_X[side] + (i as f32 - 1.0) * 20.0, VS_ICON_Y);
                    draw_capsule(bonus, c.x, c.y, 13.0 * u, u, f < s + 4.0, self.accent);
                }
            }
        }
        if f >= VS_FIRST_AT {
            let c = at(160.0, line(VS_FIRST_ROW));
            r.text_centered(&format!("FIRST TO {}", self.rung.points), font, t1, c.x, c.y, 0.0, self.gray);
        }
    }

    /// OMEGA (diventa tutti gli altri), la parte prima del VS: la racchetta rossa passa per le sette
    /// forme della scala, con un lampo bianco a ogni cambio, e torna ARCADE; il sigillo lampeggia
    /// bianco e prende i suoi colori.
    fn omega(&self) {
        let f = self.f;
        let since = f - OMEGA_FORMS_AT;
        if since >= 0.0 {
            let step = (since / OMEGA_FORM_FRAMES) as usize;
            // le sette forme, poi ARCADE per sempre
            let kind = if step < LEVELS { RUNGS[step].kind } else { OMEGA.kind };
            let changed = since - step.min(LEVELS) as f32 * OMEGA_FORM_FRAMES;
            let flash = if step < LEVELS { OMEGA_FLASH / 2.0 } else { OMEGA_FLASH };
            let body = if changed < flash { self.white } else { crate::next_ui::omega_color(self.app) };
            let r = &self.app.renderer;
            let shape = Shape {
                kind: Some(kind),
                x: self.x(0.0),
                y: r.screen_y(self.y(PAD_Y)),
                w: to_f32(self.app.params.pad_width),
                h: to_f32(self.app.params.kinds[kind as usize].height),
                front: -self.away,
                tilt: 0.0,
                dash: None,
                preview: false,
                anim: Anim::still(get_time() as f32),
            };
            draw_paddle(r, &shape, self.u, paddle_ui::look(self.app, Some(kind), body));
        }
        // il sigillo: bianco per qualche frame, poi un lampeggio, poi i suoi colori
        if f >= OMEGA_NAME_AT {
            let t = f - OMEGA_NAME_AT;
            let white = t < 4.0 || (t < 20.0 && (t / 4.0) as i64 % 2 == 1);
            let paint = if white { titles::solid(self.white) } else { self.paint };
            self.name(self.x(0.0), self.y(self.name_row()), 0.0, ArtPart::Whole, &paint);
        }
    }
}

// --------------------------------------------------------------------- allarme

/// Allarme prima di OMEGA: schermo nero e la targa WARNING! che lampeggia (`WARNING_BLINKS` volte,
/// accesa `WARNING_ON` e spenta `WARNING_OFF` secondi), poi resta accesa fino a `WARNING_SECONDS`;
/// la canzone del continue fa da sirena (`Scene::music`).
const WARNING_SECONDS: f64 = 3.5;
const WARNING_ON: f64 = 0.5;
const WARNING_OFF: f64 = 0.25;
const WARNING_BLINKS: f64 = 3.0;

/// La targa WARNING! a `t` secondi dall'inizio dell'allarme è accesa.
pub(crate) fn warning_lit(t: f64) -> bool {
    let period = WARNING_ON + WARNING_OFF;
    t >= period * WARNING_BLINKS || t % period < WARNING_ON
}

/// Battuto il GUARDIAN con la scala fatta tutta (`omega_open`): l'allarme, poi la presentazione di
/// OMEGA. Il premio del GUARDIAN aspetta il finale (`Run::guardian`).
pub struct Warning {
    t: f64,
}

impl Warning {
    /// Il GUARDIAN ha fatto `guardian_points` punti.
    pub fn new(app: &mut App, guardian_points: u16) -> Self {
        let run = app.run.as_mut().expect("CHALLENGE senza partita");
        run.guardian = guardian_points;
        run.level = OMEGA_LEVEL;
        Self { t: 0.0 }
    }

    /// Per la verifica automatica: l'allarme a `seconds` dall'inizio.
    pub fn skip_to(&mut self, seconds: f64) {
        self.t = seconds;
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            app.run = None;
            return Some(Scene::Menu(Menu::new(app)));
        }
        let before = self.t;
        self.t += dt;
        // un colpo a ogni accensione della targa
        let period = WARNING_ON + WARNING_OFF;
        if (before == 0.0 || (before / period).floor() < (self.t / period).floor()) && self.t < period * WARNING_BLINKS {
            app.play(Event::Score);
        }
        let skip = self.t >= SKIP_AFTER && start_pressed(app);
        (self.t >= WARNING_SECONDS || skip).then(|| Scene::Intro(Intro::new(app)))
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        r.fill(BLACK);
        if warning_lit(self.t) {
            let paint = titles::paint(&app.cfg.colors);
            let art = &app.assets.titles.warning;
            r.art_centered(art, 1.0, r.world_w / 2.0, r.world_h / 2.0, 0.0, ArtPart::Whole, &paint);
        }
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
    /// Il giocatore ha vinto il livello in corso con l'avversario a `opponent_points`. Contro
    /// OMEGA i premi di `Score::omega_bonus`, ALL+ in classifica e gli sblocchi (OMEGA
    /// nell'allenamento e il JUKEBOX), salvati subito.
    pub fn new(app: &mut App, opponent_points: u16) -> Self {
        let run = app.run.as_mut().expect("CHALLENGE senza partita");
        let level = run.level;
        let (win, perfect) = if run.omega() {
            Score::omega_bonus(opponent_points)
        } else {
            Score::win_bonus(run.level, opponent_points)
        };
        run.score = run.score.saturating_add(win + perfect);
        let reached = if run.omega() {
            run.omega_won = true;
            SCORE_LEVEL_OMEGA as usize
        } else if level + 1 == LEVELS {
            LEVELS + 1
        } else {
            level + 2
        };
        run.remember(reached as u8);
        if level == OMEGA_LEVEL && !(app.cfg.game.training_omega && app.cfg.game.jukebox) {
            (app.cfg.game.training_omega, app.cfg.game.jukebox) = (true, true);
            crate::config::save_preferences(&app.config_path, &app.cfg);
        }
        app.play(Event::Score);
        Self {
            level,
            win,
            perfect,
            left: CLEAR_SECONDS,
            hold: Hold::default(),
        }
    }

    /// Ultimo livello: la scala è finita (anche dopo OMEGA).
    pub fn last(&self) -> bool {
        self.level + 1 >= LEVELS
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
        if self.level == OMEGA_LEVEL {
            // OMEGA battuto: il finale speciale (il premio del campione arriva lì)
            let guardian = app.run.as_ref().map_or(0, |r| r.guardian);
            return Some(Scene::Ending(crate::ending_ui::Ending::new(app, guardian)));
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
        let last = self.last();
        let omega = self.level == OMEGA_LEVEL;
        let title = if omega {
            "OMEGA CLEAR!".to_string()
        } else if last {
            "CHAMPION!".to_string()
        } else {
            format!("LEVEL {} CLEAR", self.level + 1)
        };
        text(app, &title, T1, 140.0, accent);
        if omega {
            text(app, "YOU BEAT THEM ALL", T1, 172.0, white);
        } else if last {
            text(app, "YOU BEAT EVERY PADDLE", T1, 172.0, white);
        }
        text(app, &format!("WIN BONUS  +{}", self.win), T1, 232.0, white);
        if self.perfect > 0 {
            text(app, &format!("PERFECT  +{}", self.perfect), T1, 264.0, accent);
        }
        let score = app.run.as_ref().map_or(0, |r| r.score);
        text(app, &format!("SCORE {}", pad(score)), T1, 324.0, white);
        text(app, "PRESS START", T1, 430.0, gray);
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
            // dopo la chiusura del GAME OVER lo schermo resta nero per un po'
            *left -= dt;
            let black = app.attract.game_over_black_seconds();
            return (*left <= -black || input::pressed(KeyCode::Escape)).then(|| finish(app));
        }
        if input::pressed(KeyCode::Escape) {
            self.over = Some(app.attract.game_over_seconds());
            return None;
        }
        if input::pressed(KeyCode::Key5) && !app.cfg.game.free_play && app.credits < 9 {
            app.credits += 1;
            app.play_coin();
        }
        if self.left < CONTINUE_SECONDS - CONTINUE_SKIP_AFTER
            && start_pressed(app)
            && (app.cfg.game.free_play || app.credits > 0)
        {
            if !app.cfg.game.free_play {
                app.credits -= 1;
            }
            if let Some(run) = &mut app.run {
                run.score = 0;
                // con un continue la scala non è più fatta tutta di fila: niente OMEGA
                run.clean = false;
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
        if let Some(left) = self.over {
            // GAME OVER come a fine partita, ma senza campo da spegnere: si scrive subito, poi lo
            // schermo si chiude come un televisore
            let total = app.attract.game_over_seconds();
            let t = total - left;
            let r = &app.renderer;
            let none = (Vec2::ZERO, 0.0);
            let perfect = (&app.assets.titles.perfect, &titles::paint(&app.cfg.colors));
            crate::attract::draw_game_over_anim(&app.attract, perfect, r, Some("game_over"), None, white, accent,
                                                t + crate::attract::TYPE_LEAD, none);
            crate::attract::draw_crt_close(r, t, total);
            return;
        }
        text(app, "CONTINUE?", T1, 140.0, accent);
        let sc = scale(app);
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
        // pallina che rimbalza a destra del numero: tocca terra a ogni secondo, quando il numero
        // cambia; negli ultimi tre secondi diventa gialla
        let since = (self.left.ceil() - self.left) as f32; // 0 appena toccato terra
        let d = to_f32(app.params.ball_radius) * 3.0;
        let floor = 300.0 * sc;
        let bx = r.world_w / 2.0 + 80.0 * sc;
        let by = floor - d - BOUNCE_HEIGHT * sc * 4.0 * since * (1.0 - since);
        let ball = if self.left <= 3.0 { accent } else { white };
        draw_rectangle(bx - d / 2.0, by, d, d, ball);
        draw_rectangle(bx - d, floor, 2.0 * d, 2.0 * unit(app), gray);
        let blink = (get_time() * 2.0) as i64 % 2 == 0;
        let prompt = if app.cfg.game.free_play || app.credits > 0 {
            "PRESS START"
        } else {
            "INSERT COIN"
        };
        if blink {
            text(app, prompt, T1, 370.0, white);
        }
        if let Some(run) = &app.run {
            text(
                app,
                &format!("LEVEL {}   SCORE RESETS TO 0", run.level + 1),
                T1,
                420.0,
                gray,
            );
        }
        // crediti rimasti, come nell'attract (non in Free Play)
        if !app.cfg.game.free_play {
            text(app, &format!("CREDIT {}", app.credits), T1, 450.0, white);
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
        if jukebox_after(app.cfg.game.jukebox, &self.name) != app.cfg.game.jukebox {
            app.cfg.game.jukebox = true;
            crate::config::save_preferences(&app.config_path, &app.cfg);
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
        text(app, "NEW RECORD!", T1, 120.0, accent);
        text(app, &format!("SCORE {}", pad(self.best.0)), T1, 160.0, white);
        let prompt = match self.loser {
            Some(side) => format!("P{} ENTER YOUR INITIALS", side as usize + 1),
            None => "ENTER YOUR INITIALS".to_string(),
        };
        text(app, &prompt, T1, 215.0, gray);
        let sc = scale(app);
        let r = &app.renderer;
        let blink = (get_time() * 4.0) as i64 % 2 == 0;
        for i in 0..3 {
            let c = match i.cmp(&self.pos) {
                std::cmp::Ordering::Less => self.name[i],
                std::cmp::Ordering::Equal => LETTERS[self.letter],
                std::cmp::Ordering::Greater => b' ',
            };
            let x = r.world_w / 2.0 + (i as f32 - 1.0) * 32.0 * sc;
            let color = if i == self.pos { accent } else { white };
            // una lineetta sotto ogni posto: a 1x i puntini dei posti vuoti quasi non si vedevano
            let (lw, u) = (r.text_1x(), unit(app));
            draw_rectangle(x - lw / 2.0, 290.0 * sc + lw * 0.75, lw, u, if i == self.pos { accent } else { gray });
            if i != self.pos || blink {
                r.text_centered(
                    &(c as char).to_string(),
                    &app.assets.font_text,
                    T1 * sc,
                    x,
                    290.0 * sc,
                    0.0,
                    color,
                );
            }
        }
        if !app.touch {
            text(app, "UP DOWN TO CHOOSE, FORWARD TO CONFIRM", T1, 420.0, gray);
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

    /// Per la verifica automatica: la classifica a `t` secondi dall'inizio.
    pub fn at(highlight: Option<usize>, t: f64) -> Self {
        Self {
            left: SCORES_SECONDS - t,
            ..Self::new(highlight)
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

    /// Classifica animata (vedi `SCORES_BALL_Y` e seguenti): righe spente finché la palla non le
    /// tocca, punti che contano, poi il posto nuovo con le racchette ai lati e il riflesso.
    pub fn draw(&self, app: &App) {
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (
            App::color(colors.white),
            App::color(colors.lgray),
            App::color(colors.accent),
        );
        let dim = Color::from_rgba(0x3A, 0x3A, 0x3A, 255);
        app.renderer.fill(BLACK);
        text(app, "HIGH SCORES", T1, 64.0, accent);
        let t = SCORES_SECONDS - self.left;
        let sc = scale(app);
        let r = &app.renderer;
        let font = &app.assets.font_text;
        let w = r.world_w;
        let ball_y = |t: f64| SCORES_BALL_Y + SCORES_BALL_VY * t as f32;
        let w2 = w / 2.0;
        // posti a schermo: i primi `SCORES_ROWS`, con il posto nuovo al posto dell'ultimo se è più giù
        let shown: Vec<usize> = (0..SCORES_ROWS.min(TABLE_SIZE))
            .map(|k| match self.highlight {
                Some(h) if k + 1 == SCORES_ROWS && h >= k => h,
                _ => k,
            })
            .collect();
        let rows = shown.len();
        // posto nuovo: racchette in arrivo (0..1) e riflesso (posizione 0..1 sulla riga, se c'è)
        let mark = (t - SCORES_MARK).max(0.0);
        let glint = (mark > SCORES_MARK_IN)
            .then(|| ((mark - SCORES_MARK_IN) % SCORES_GLINT_PERIOD) / SCORES_GLINT)
            .filter(|&g| g < 1.0);
        for (k, &i) in shown.iter().enumerate() {
            let e = &app.scores.entries[i];
            let row_y = SCORES_ROW_Y + k as f32 * SCORES_ROW_STEP;
            let y = row_y * sc;
            // secondi da quando la palla ha toccato la riga
            let lit = t - ((row_y - SCORES_BALL_Y) / SCORES_BALL_VY) as f64;
            let counted = (lit / SCORES_COUNT).clamp(0.0, 1.0);
            let shown = (e.score as f64 * (1.0 - (1.0 - counted).powi(3))) as u32;
            let new = Some(i) == self.highlight;
            let color = if lit < 0.0 {
                dim
            } else if counted < 1.0 {
                gray
            } else if new {
                accent
            } else {
                white
            };
            let level = level_label(e.level);
            let name = String::from_utf8_lossy(&e.name).to_string();
            for (s, x) in [
                (format!("{}", i + 1), SCORES_COLS[0]),
                (name, SCORES_COLS[1]),
                (pad(shown), SCORES_COLS[2]),
                (level, SCORES_COLS[3]),
            ] {
                let (size, cx) = (T1 * sc, w2 + x * sc);
                r.text_centered(&s, font, size, cx, y, 0.0, color);
                // riflesso: le lettere sotto la banda che attraversa la riga diventano bianche
                if let (true, Some(g)) = (new, glint) {
                    let band = w2 + SCORES_REACH * sc * (2.0 * g as f32 - 1.0);
                    for (ch, ink) in s.chars().zip(r.ink_boxes(&s, font, size)) {
                        if let Some((x0, x1)) = ink
                            && cx + x1 > band - 14.0 * sc
                            && cx + x0 < band + 14.0 * sc
                        {
                            r.text_centered(&ch.to_string(), font, size, cx + (x0 + x1) / 2.0, y, 0.0, white);
                        }
                    }
                }
            }
            // racchette ai lati del posto nuovo, dai bordi dello schermo
            if new && mark > 0.0 {
                let p = 1.0 - (1.0 - (mark / SCORES_MARK_IN).min(1.0) as f32).powi(3);
                let (pw, ph) = (8.0 * sc, 30.0 * sc);
                let reach = SCORES_REACH * sc;
                let left = -pw + p * (w2 - reach + pw);
                let right = w - p * (w2 - reach);
                draw_rectangle(left, y - ph / 2.0, pw, ph, accent);
                draw_rectangle(right - pw, y - ph / 2.0, pw, ph, accent);
            }
        }
        // la palla, con una scia, finché non ha passato l'ultima riga
        let bottom = SCORES_ROW_Y + rows as f32 * SCORES_ROW_STEP;
        if ball_y(t) < bottom + 20.0 {
            let (x0, x1) = (w2 - (SCORES_REACH + 12.0) * sc, w2 + (SCORES_REACH + 12.0) * sc);
            let span = x1 - x0;
            let ball_x = |t: f64| {
                let p = (t as f32 * SCORES_BALL_VX * w) % (2.0 * span);
                x0 + if p < span { p } else { 2.0 * span - p }
            };
            let size = 8.0 * sc;
            for (k, v) in [(3, 0x30), (2, 0x5E), (1, 0x9A), (0, 0xFF)] {
                let tk = (t - k as f64 * 0.03).max(0.0);
                let c = Color::from_rgba(v, v, v, 255);
                draw_rectangle(ball_x(tk) - size / 2.0, ball_y(tk) * sc - size / 2.0, size, size, c);
            }
        }
        let prompt = if app.cfg.game.free_play || app.credits > 0 {
            "PRESS START"
        } else {
            "INSERT COIN"
        };
        if ball_y(t) >= bottom + 20.0 && (get_time() * 2.0) as i64 % 2 == 0 {
            text(app, prompt, T1, r.world_h / sc - 25.0, gray);
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
        for (name, want) in [(b"RED", true), (b"ABC", true), (b"RE ", true), (b"RED", false), (b"DER", false)] {
            on = egg_after(on, name);
            assert_eq!(on, want, "{}", String::from_utf8_lossy(name));
        }
    }

    #[test]
    fn bas_unlocks_the_jukebox_for_good() {
        assert!(jukebox_after(false, b"BAS"));
        assert!(!jukebox_after(false, b"BAD"));
        assert!(!jukebox_after(false, b"RED"));
        // una volta sbloccato resta
        assert!(jukebox_after(true, b"AAA"));
        assert!(jukebox_after(true, b"BAS"));
        assert!(JUKEBOX_NAME.iter().all(|c| LETTERS.contains(c)));
    }

    #[test]
    fn omega_needs_the_whole_ladder_at_hard_without_continues() {
        let at_guardian = |run: &mut Run| run.level = LEVELS - 1;
        let mut run = Run::new();
        at_guardian(&mut run);
        // HARD ed EXPERT sì, NORMAL ed EASY no
        assert!(omega_open(&run, 2) && omega_open(&run, 3));
        assert!(!omega_open(&run, 1) && !omega_open(&run, 0));
        // prima del GUARDIAN no
        run.level = LEVELS - 2;
        assert!(!omega_open(&run, 3));
        // il campione che batte uno sfidante resta idoneo
        let mut run = Run::new();
        at_guardian(&mut run);
        assert!(run.duel_won_by(Side::Left));
        assert!(omega_open(&run, 2));
        // lo sfidante che vince e prende il posto no
        assert!(!run.duel_won_by(Side::Right));
        assert!(!omega_open(&run, 2));
        // con un continue no
        let mut run = Run::new();
        at_guardian(&mut run);
        run.clean = false;
        assert!(!omega_open(&run, 3));
        // nell'allenamento no, neanche contro il GUARDIAN
        assert!(!omega_open(&Run::training(LEVELS - 1), 3));
    }

    #[test]
    fn omega_is_the_level_after_the_ladder() {
        assert_eq!(*rung(OMEGA_LEVEL), OMEGA);
        assert_eq!(*rung(3), RUNGS[3]);
        assert_eq!(opponent_name(OMEGA_LEVEL), "OMEGA");
        assert_eq!(opponent_name(6), "GUARDIAN");
        // l'allenamento contro OMEGA resta contro OMEGA, senza sfidanti
        let run = Run::training(OMEGA_LEVEL);
        assert!(run.omega() && run.training && !run.clean);
        assert!(!Run::new().omega());
    }

    #[test]
    fn the_scores_show_all_plus_after_omega() {
        assert_eq!(level_label(1), "LV1");
        assert_eq!(level_label(LEVELS as u8), "LV7");
        assert_eq!(level_label(LEVELS as u8 + 1), "ALL");
        assert_eq!(level_label(SCORE_LEVEL_OMEGA), "ALL+");
    }

    #[test]
    fn the_warning_blinks_three_times_then_stays() {
        let lit: Vec<bool> = (0..14).map(|i| warning_lit(i as f64 * 0.25 + 0.01)).collect();
        // accesa 0,5 s e spenta 0,25 s, tre volte, poi sempre accesa
        assert_eq!(lit, [true, true, false, true, true, false, true, true, false, true, true, true, true, true]);
    }

    #[test]
    fn the_champion_counts_the_duels_won_in_a_row() {
        let mut run = Run::new();
        assert_eq!(run.wins, 0); // senza duelli niente WINS
        // il campione (a sinistra) vince due duelli
        assert_eq!(run.wins_after(Side::Left), 1);
        assert!(run.duel_won_by(Side::Left));
        assert!(run.duel_won_by(Side::Left));
        assert_eq!((run.wins, run.side), (2, Side::Left));
        // vince lo sfidante: è il nuovo campione, con il primo duello vinto
        assert_eq!(run.wins_after(Side::Right), 1);
        assert!(!run.duel_won_by(Side::Right));
        assert_eq!((run.wins, run.side), (1, Side::Right));
        assert!(run.duel_won_by(Side::Right));
        assert_eq!(run.wins, 2);
        // lo sfidante da sinistra lo batte
        assert!(!run.duel_won_by(Side::Left));
        assert_eq!((run.wins, run.side), (1, Side::Left));
    }

    #[test]
    fn training_is_one_opponent_without_challengers() {
        let run = Run::training(3);
        assert!(run.training);
        assert_eq!((run.level, run.score, run.wins, run.side), (3, 0, 0, Side::Left));
        assert_eq!(Run::training(99).level, LEVELS - 1);
        assert!(!Run::new().training);
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

    /// Altezze dei titoli disegnati (pixel arcade) da `assets/titles/titles.json`.
    fn title_heights() -> Vec<(String, f32, f32)> {
        let spec: serde_json::Value = serde_json::from_str(include_str!("../../../assets/titles/titles.json")).unwrap();
        spec["titles"]
            .as_object()
            .unwrap()
            .iter()
            .map(|(n, t)| (n.clone(), t["size"][0].as_f64().unwrap() as f32, t["size"][1].as_f64().unwrap() as f32))
            .collect()
    }

    /// Campi 4:3, 16:9 e larghi a 480 righe, come nel gioco: (larghezza, scala della CHALLENGE `sc`,
    /// parametri del core).
    fn fields() -> Vec<(f32, f32, paddws_core::Params)> {
        [640u32, 852, 1056]
            .into_iter()
            .map(|width| {
                let mut cfg = crate::config::Config::default();
                (cfg.resolution.width, cfg.resolution.height) = (width, 480);
                let params = paddws_core::Params::new(&cfg.tuning());
                (width as f32, to_f32(params.scale).min(1.0), params)
            })
            .collect()
    }

    /// Schermo VS: ogni nome disegnato (anche il sigillo di OMEGA) sta sotto il ritratto e finisce
    /// sopra il motto, con almeno un pixel; centrato sotto il ritratto, resta nello schermo 320x240;
    /// i più alti non arrivano al ritratto.
    #[test]
    fn the_drawn_names_fit_under_the_portraits() {
        let tag_top = line(VS_TAG_ROW) - 3.5; // maiuscole di Press Start 2P a 1x, alte 7 righe
        for (name, w, h) in title_heights().into_iter().filter(|t| t.0.starts_with("name_")) {
            let (top, bottom) = (vs_name_y(h) - h / 2.0, vs_name_y(h) + h / 2.0);
            assert!(bottom + 1.0 <= tag_top, "{name}: fino a {bottom}, motto da {tag_top}");
            assert!(top >= VS_PORTRAIT_Y + PORTRAIT_H, "{name}: da {top}, ritratto fino a {}", VS_PORTRAIT_Y + PORTRAIT_H);
            assert!(w + 4.0 <= 320.0, "{name} largo {w}");
        }
    }

    /// Nuovo sfidante: la targa disegnata sta fra la banda in alto e la riga dello sfidante, con
    /// almeno un pixel arcade di spazio, e nel campo.
    #[test]
    fn the_challenger_plate_fits_between_the_band_and_the_line() {
        let (u, h) = (2.0, 480.0);
        let (_, pw, ph) = title_heights().into_iter().find(|t| t.0 == "challenger").unwrap();
        for (w, sc, _) in fields() {
            let mid = h / sc / 2.0;
            let center = (mid + CHALLENGER_PLATE) * sc;
            let (top, bottom) = (center - ph * u / 2.0, center + ph * u / 2.0);
            let band_bottom = h / 2.0 - (CHALLENGER_BAND - CHALLENGER_BAND_H) * sc;
            let line_top = (mid + CHALLENGER_LINE) * sc - 3.5 * u;
            assert!(top >= band_bottom + u, "{w}: targa a {top}, banda fino a {band_bottom}");
            assert!(bottom + u <= line_top, "{w}: targa fino a {bottom}, riga da {line_top}");
            assert!(pw * u <= w - 16.0 * u, "{w}");
        }
    }
}
