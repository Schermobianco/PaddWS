//! Scene: attract, menu, scelta dei bonus e della racchetta NEXT, presentazione delle mosse
//! speciali, partita, schermate di CHALLENGE.

use std::f32::consts::FRAC_PI_2;

use macroquad::prelude::*;
use paddws_core::challenge::{LEVELS, RUNGS, Score, Table};
use paddws_core::fixed::to_f32;
use paddws_sid::Call;
use paddws_core::{
    Bonus, Cpu, DIFFICULTY_LEVELS, Event, Input, Match, PaddleKind, Params, Rng, Side, Special, TICK_HZ, Tuning,
};

use crate::attract::{self, Attract, AttractArt, Hud};
use crate::challenge_ui::{self, Challenger, Clear, Continue, Initials, Intro, Run, Scores};
use crate::config::{self, Config, Rgb};
use crate::encoder::{self, Action, Encoders};
use crate::ending_ui::Ending;
use crate::gamepad::{self, Control};
use crate::gesture::{Dir, Gesture, Stick};
use crate::input::{self, PadKeys};
use crate::moves_ui::HowTo;
use crate::mouse;
use crate::next_ui::{self, NextFx, Pick};
use crate::paddle_ui::PaddlePick;
use crate::platform;
use crate::render::{GameFont, Renderer};
use crate::touch;

const PHYSICS_STEP: f64 = 1.0 / TICK_HZ as f64;
/// evita la "spirale della morte" dopo un blocco
const MAX_FRAME_TIME: f64 = 0.25;
/// lampo bianco quando viene segnato un punto
const FLASH_TIME: f64 = 0.05;
/// conto alla rovescia (3, 2, 1) prima del primo servizio
const COUNTDOWN_TIME: f64 = 3.0;
/// spostamenti più lunghi in un tick sono teletrasporti: niente interpolazione
const SNAP_DISTANCE: f32 = 40.0;

/// Scatto in avanti a schermo: la racchetta raggiunge la nuova x dimezzando la distanza ogni
/// 1/60 s (almeno 6 pixel arcade), in circa 5 frame invece di teletrasportarsi, come nel core
/// MiSTer. Solo grafica: la logica resta istantanea. `unit` è un pixel dello schermo 320x240.
fn slide(cur: f32, target: f32, dt: f64, unit: f32) -> f32 {
    let d = target - cur;
    if d.abs() > 100.0 * unit {
        return target; // nuova partita: nessuna animazione
    }
    let frames = (dt * 60.0) as f32;
    let step = (d.abs() * (1.0 - 0.5f32.powf(frames)))
        .max(6.0 * unit * frames)
        .min(d.abs());
    cur + step * d.signum()
}

pub struct Assets {
    pub font_text: GameFont,
    pub font_score: GameFont,
}

/// Effetti del SID: i bit degli eventi di `paddws_sid::player::effect_of` (come `sid_events` di
/// pong_top.v).
const SFX_WALL: u8 = 1 << 0;
const SFX_HIT: u8 = 1 << 1;
const SFX_BOOST: u8 = 1 << 2;
const SFX_SCORE: u8 = 1 << 3;
const SFX_COIN: u8 = 1 << 4;
const SFX_MOVE: u8 = 1 << 5;
const SFX_SPECIAL_HIT: u8 = 1 << 6;

/// I suoni degli eventi di un frame (anche di più tick), da suonare con `App::play_frame`.
#[derive(Clone, Copy, Debug, Default)]
pub struct FrameSound {
    /// effetti del SID (`SFX_*`)
    sid: u8,
    /// voce di partita: l'urlo della mossa speciale al colpo, insieme alla scritta (`special_hit`),
    /// o YOU WIN / PERFECT a fine partita, che vincono sugli urli
    shout: Option<Call>,
}

impl FrameSound {
    pub fn add(&mut self, event: Event) {
        self.sid |= match event {
            Event::Wall => SFX_WALL,
            Event::Hit => SFX_HIT,
            Event::Boost => SFX_BOOST,
            Event::Score => SFX_SCORE,
            // NEXT: capsula raccolta, bonus attivato, colpo con il SUPER, salto del TELEPORT
            Event::Collect => SFX_WALL,
            Event::Activate | Event::Teleport => SFX_BOOST,
            Event::Super => SFX_SCORE,
            // tipi di racchetta: colpo del BLASTER, rimbalzo sulla barriera del GUARDIAN
            Event::Fire => SFX_HIT,
            Event::Barrier => SFX_WALL,
            // mosse speciali: i loro effetti, e l'urlo con il nome della mossa
            Event::Straight | Event::Rise => SFX_MOVE,
            Event::SpecialHit => SFX_SPECIAL_HIT,
        };
    }

    /// Colpo di una mossa speciale: l'urlo con il suo nome parte insieme al tiro e alla scritta.
    pub fn special_hit(&mut self, special: Special) {
        self.shout = self.shout.or(Some(match special {
            Special::Straight => Call::Straight,
            Special::Rise => Call::Rise,
        }));
    }
}

/// Musiche del SID (tools/gen_sid_music.py), suonate in tempo reale dal SID Rust (`music`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Song {
    Title,
    Intro,
    Clear,
    Continue,
    GameOver,
    Champion,
    /// CHALLENGE: il tema dell'avversario, in partita contro la CPU
    Theme(PaddleKind),
    /// il finale della CHALLENGE: ENDING se la ROM ce l'ha, altrimenti CHAMPION
    Ending,
}

/// Con l'easter egg (`App::egg`) al posto della canzone del titolo suona quella del finale.
fn egg_song(song: Option<Song>, egg: bool) -> Option<Song> {
    match song {
        Some(Song::Title) if egg => Some(Song::Ending),
        s => s,
    }
}

impl Song {
    /// Numero della canzone nella ROM del SID, cercato per nome (`SID_SONG_*` di sid_music.vh, in
    /// minuscolo): così una canzone nuova nella ROM non sposta le altre. Le musiche di sottofondo
    /// e i temi si ripetono da soli (le loro tracce ricominciano), i jingle finiscono. 0 (silenzio)
    /// se il nome non c'è.
    fn number(self) -> u8 {
        static ROM: std::sync::OnceLock<paddws_sid::Rom> = std::sync::OnceLock::new();
        let rom = ROM.get_or_init(paddws_sid::Rom::builtin);
        let name = match self {
            Song::Title => "title".to_string(),
            Song::Intro => "intro".into(),
            Song::Clear => "clear".into(),
            Song::Continue => "continue".into(),
            Song::GameOver => "game_over".into(),
            Song::Champion => "champion".into(),
            Song::Theme(kind) => format!("theme_{}", kind.name()),
            Song::Ending => return rom.song_number("ending").unwrap_or_else(|| Song::Champion.number()),
        };
        rom.song_number(&name).unwrap_or(0)
    }
}

/// Stato condiviso tra le scene.
pub struct App {
    pub cfg: Config,
    pub config_path: std::path::PathBuf,
    pub params: Params,
    pub renderer: Renderer,
    pub assets: Assets,
    pub players: u8,
    /// in due, il giocatore di destra è il computer
    pub cpu: bool,
    pub evo: bool,
    /// modalità NEXT (a due giocatori, senza EVO)
    pub next: bool,
    /// bonus scelti da ciascun giocatore per la partita NEXT
    pub loadout: [[Bonus; 3]; 2],
    /// tipi di racchetta scelti per la partita NEXT
    pub paddles: [Option<PaddleKind>; 2],
    /// modalità CHALLENGE scelta nel menu (NEXT contro la scala di CPU), partita in corso e classifica
    pub challenge: bool,
    pub run: Option<Run>,
    pub scores: Table,
    pub on_raspberry: bool,
    pub quit: bool,
    /// partite con seme diverso a ogni avvio
    pub seed: u32,
    pub attract: AttractArt,
    /// crediti inseriti (contano solo senza Free Play)
    pub credits: u8,
    /// si gioca con il touch: in pausa compaiono i comandi da toccare
    pub touch: bool,
    /// encoder del cabinato (Raspberry Pi) o mouse come spinner, ed eventi dell'ultimo frame
    pub encoders: Option<Encoders>,
    pub knob_events: Vec<encoder::Event>,
    /// il mouse letto come spinner (cursore catturato)
    pub mouse: mouse::Spinner,
    /// gamepad e stick arcade dei due giocatori, e se l'ultimo comando usato è stato un gamepad
    /// (la HOW TO PLAY mostra allora i comandi del joystick)
    pub pads: gamepad::Pads,
    pub pad_used: bool,
    /// musica che sta suonando, e la musica del SID suonata in tempo reale
    pub music: Option<Song>,
    pub sid_music: crate::music::SidMusic,
    /// easter egg (iniziali "RED", `challenge_ui::egg_after`): fino allo spegnimento, mai nella
    /// configurazione
    pub egg: bool,
    /// partita lasciata per il menu (pausa, Esc, encoder): la voce RESUME la riprende
    pub suspended: Option<Box<Play>>,
}

impl App {
    pub fn color(c: Rgb) -> Color {
        Color::from_rgba(c[0], c[1], c[2], 255)
    }

    /// Accende o spegne l'easter egg: giallo e rosso scambiati in tutto quello che si disegna
    /// (`Renderer::set_color_swap`) e la canzone del finale al posto di quella del titolo
    /// (`egg_song`). Si vede subito, già nella classifica dopo le iniziali.
    pub fn set_egg(&mut self, on: bool) {
        self.egg = on;
        self.renderer.set_color_swap(on);
    }

    /// Cambia la larghezza del campo (nel browser, quando cambia la tela): parametri del core e
    /// coordinate del disegno. Solo fuori dalla partita: chi ha uno stato del campo va rifatto.
    pub fn set_field_width(&mut self, width: u32) {
        self.cfg.resolution.width = width;
        self.params = Params::new(&self.cfg.tuning());
        self.renderer.set_world_width(width);
    }

    /// GAME TYPE e PLAYERS della configurazione (`Game::game_type`, `Game::players`), con gli
    /// stessi vincoli del menu: EVO e NEXT sono a due, la CHALLENGE è in NEXT.
    pub fn load_mode(&mut self) {
        let g = &self.cfg.game;
        (self.evo, self.next) = match g.game_type.as_str() {
            "evo" => (true, false),
            "next" => (false, true),
            _ => (false, false),
        };
        (self.players, self.cpu, self.challenge) = match g.players.as_str() {
            "cpu" => (2, true, false),
            "challenge" => (2, true, true),
            "one" if !self.evo && !self.next => (1, false, false),
            _ => (2, false, false),
        };
        if self.challenge {
            (self.evo, self.next) = (false, true);
        }
    }

    /// Salva GAME TYPE e PLAYERS scelti nel menu (nel browser nel localStorage), per ritrovarli
    /// alla prossima accensione.
    fn save_mode(&mut self) {
        let g = &mut self.cfg.game;
        g.game_type = match (self.evo, self.next) {
            (true, _) => "evo",
            (_, true) => "next",
            _ => "classic",
        }
        .into();
        g.players = match (self.players, self.cpu, self.challenge) {
            (1, _, _) => "one",
            (_, _, true) => "challenge",
            (_, true, _) => "cpu",
            _ => "two",
        }
        .into();
        config::save_preferences(&self.config_path, &self.cfg);
    }

    /// La partita lasciata per il menu non si riprende più (se ne sceglie un'altra o si esce).
    pub fn drop_suspended(&mut self) {
        if self.suspended.take().is_some() {
            self.run = None;
        }
    }

    /// Click di un encoder in questo frame.
    pub fn knob_clicked(&self) -> bool {
        self.knob_events.iter().any(|e| e.action == Action::Click)
    }

    /// Il mouse fa da spinner del giocatore 1.
    pub fn mouse_spinner(&self) -> bool {
        self.encoders.as_ref().is_some_and(Encoders::is_mouse)
    }

    /// Encoder all'avvio: quelli del cabinato se ci sono, altrimenti il mouse se fa da spinner.
    pub fn open_encoders(cfg: &Config) -> Option<Encoders> {
        let enc = Encoders::open(&cfg.encoder)
            .or_else(|| cfg.mouse.spinner.then(|| Encoders::mouse(cfg.mouse.travel_pixels)));
        touch::set_mouse_spinner(enc.as_ref().is_some_and(Encoders::is_mouse));
        enc
    }

    /// Accende o spegne il mouse come spinner (voce del menu) e salva la scelta. Con gli encoder
    /// del cabinato il mouse non serve e la voce non c'è.
    fn set_mouse_spinner(&mut self, on: bool) {
        if self.encoders.as_ref().is_some_and(|e| !e.is_mouse()) {
            return;
        }
        self.cfg.mouse.spinner = on;
        self.encoders = on.then(|| Encoders::mouse(self.cfg.mouse.travel_pixels));
        touch::set_mouse_spinner(on);
        config::save_preferences(&self.config_path, &self.cfg);
    }

    pub fn hud(&self) -> Hud {
        Hud {
            credits: if self.cfg.game.free_play {
                None
            } else {
                Some(self.credits)
            },
        }
    }

    /// Fa suonare `want` (o il silenzio, con il rilascio delle note); la musica cambia solo quando
    /// cambia quella richiesta, e riparte da capo. Il volume segue MUSIC VOLUME anche mentre la
    /// canzone suona; a 0 non suona nessuna musica.
    pub fn set_music(&mut self, want: Option<Song>) {
        self.sid_music.set_gain(config::volume_gain(self.cfg.game.music_volume));
        self.sid_music.set_fx_gain(config::volume_gain(self.cfg.game.effects_volume));
        let want = want.filter(|_| self.cfg.game.music_volume > 0);
        if want == self.music {
            return;
        }
        self.sid_music.set_song(want.map_or(0, Song::number));
        self.music = want;
    }

    /// Tempo della musica: più veloce al match point, rallentata nel bullet time (vedi
    /// `Scene::tempo`).
    pub fn set_tempo(&mut self, (fast, slow): (bool, bool)) {
        self.sid_music.set_tempo(fast, slow);
    }

    pub fn scale(&self) -> f32 {
        to_f32(self.params.scale)
    }

    /// Gettone inserito: l'effetto più importante, non rallenta mai.
    pub fn play_coin(&self) {
        self.sid_music.effect(SFX_COIN, false);
    }

    /// CHALLENGE: il nome dell'avversario, detto dal SID con il trucco di $D418 (intanto la musica
    /// tace), al volume degli effetti.
    pub fn announce(&self, kind: PaddleKind) {
        self.sid_music.say(kind as u8);
    }

    /// Scelta della racchetta: il nome della racchetta sommato all'uscita come le voci di partita,
    /// così la musica non si ferma; interrompe quello di prima.
    pub fn announce_paddle(&self, kind: PaddleKind) {
        self.sid_music.call_name(kind as u8);
    }

    /// Fine della presentazione: il nome dell'avversario si ferma, se c'è ancora.
    pub fn stop_announce(&self) {
        self.sid_music.stop_voice();
    }

    /// L'effetto di un evento fuori dalla partita (menu, scelte, attract).
    pub fn play(&self, event: Event) {
        let mut sound = FrameSound::default();
        sound.add(event);
        self.play_frame(sound, false);
    }

    /// Una delle voci di partita "da SID" (gli urli delle mosse, READY, GO, YOU WIN, PERFECT):
    /// la suona il SID Rust sopra musica ed effetti, al volume degli effetti.
    pub fn say(&self, call: Call) {
        self.sid_music.call(call);
    }

    /// I suoni degli eventi di un frame, come il MiSTer: l'urlo della mossa speciale attivata e un
    /// solo effetto del SID sulla voce 3, scelto per priorità (`paddws_sid::player::effect_of`),
    /// che interrompe quello in corso; con `slow` (bullet time) a metà velocità, un'ottava sotto.
    pub fn play_frame(&self, sound: FrameSound, slow: bool) {
        if let Some(call) = sound.shout {
            self.say(call);
        }
        if sound.sid != 0 {
            self.sid_music.effect(sound.sid, slow);
        }
    }

    /// Schermo intero, come lo mostra la voce del menu: nel browser quello vero della pagina.
    pub fn fullscreen(&self) -> bool {
        if platform::WEB { platform::web_fullscreen() } else { self.cfg.game.fullscreen }
    }

    pub fn toggle_fullscreen(&mut self) {
        if platform::WEB {
            // nel browser decide la pagina (`rust/web/fullscreen.js`): niente preferenza salvata
            platform::set_web_fullscreen(!platform::web_fullscreen());
            return;
        }
        self.cfg.game.fullscreen = !self.cfg.game.fullscreen;
        set_fullscreen(self.cfg.game.fullscreen);
        config::save_preferences(&self.config_path, &self.cfg);
    }

    pub fn toggle_crt(&mut self) {
        self.cfg.crt_effects.enabled = !self.cfg.crt_effects.enabled;
        config::save_preferences(&self.config_path, &self.cfg);
    }

    /// Passa al livello di difficoltà successivo (vale dalla prossima partita).
    pub fn next_difficulty(&mut self) {
        self.cfg.game.difficulty = (self.cfg.game.difficulty.min(DIFFICULTY_LEVELS - 1) + 1) % DIFFICULTY_LEVELS;
        self.params = Params::new(&self.cfg.tuning());
        config::save_preferences(&self.config_path, &self.cfg);
    }
}

pub enum Scene {
    Attract(Attract),
    Menu(Menu),
    Pick(Pick),
    Paddles(PaddlePick),
    HowTo(HowTo),
    Game(Box<Play>),
    Demo(Box<Demo>),
    Intro(Intro),
    Challenger(Challenger),
    Clear(Clear),
    Continue(Continue),
    Initials(Initials),
    Scores(Scores),
    Ending(Ending),
}

impl Scene {
    /// Aggiorna la scena; restituisce la prossima scena se cambia.
    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        match self {
            Scene::Attract(s) => update_attract(s, app, dt),
            Scene::Menu(s) => s.update(app, dt),
            Scene::Pick(s) => s.update(app, dt),
            Scene::Paddles(s) => s.update(app, dt),
            Scene::HowTo(s) => s.update(app, dt),
            Scene::Game(s) => s.update(app, dt),
            Scene::Demo(s) => s.update(app, dt),
            Scene::Intro(s) => s.update(app, dt),
            Scene::Challenger(s) => s.update(app, dt),
            Scene::Clear(s) => s.update(app, dt),
            Scene::Continue(s) => s.update(app, dt),
            Scene::Initials(s) => s.update(app, dt),
            Scene::Scores(s) => s.update(app, dt),
            Scene::Ending(s) => s.update(app, dt),
        }
    }

    /// Musica della scena: il titolo nell'attract (se ha i suoni) e nei menu, i jingle di
    /// CHALLENGE, il game over a fine partita; in partita e nella demo silenzio, tranne in CHALLENGE
    /// contro la CPU (non nella sfida tra due giocatori), dove suona il tema dell'avversario del
    /// livello. Con MUSIC VOLUME a 0 (`game.music_volume`) nessuna musica, gli effetti restano; con
    /// ATTRACT SOUND spento l'attract è muto, musica compresa.
    pub fn music(&self, app: &App) -> Option<Song> {
        if app.cfg.game.music_volume == 0 {
            return None;
        }
        egg_song(self.scene_music(app), app.egg)
    }

    fn scene_music(&self, app: &App) -> Option<Song> {
        match self {
            Scene::Attract(_) | Scene::Scores(_) => app.cfg.game.attract_sound.then_some(Song::Title),
            // il menu e le scelte che seguono suonano il titolo come l'attract: ATTRACT SOUND
            // spegne anche loro
            Scene::Menu(_) | Scene::Pick(_) | Scene::Paddles(_) | Scene::HowTo(_) => {
                app.cfg.game.attract_sound.then_some(Song::Title)
            }
            Scene::Game(s) => match (s.game_over, &s.challenge) {
                (Some(_), None) => Some(Song::GameOver),
                (None, Some((level, _))) => Some(Song::Theme(RUNGS[*level].kind)),
                // la sfida della CHALLENGE tra due giocatori: il tema di un avversario a caso
                (None, None) if s.duel.is_some() => Some(Song::Theme(s.theme)),
                _ => None,
            },
            Scene::Demo(_) => None,
            // nuovo sfidante: il jingle della presentazione, da capo
            Scene::Intro(_) | Scene::Challenger(_) => Some(Song::Intro),
            Scene::Clear(s) => Some(if s.last() { Song::Champion } else { Song::Clear }),
            Scene::Continue(s) => Some(if s.game_over() { Song::GameOver } else { Song::Continue }),
            Scene::Initials(_) => Some(Song::Champion),
            Scene::Ending(_) => Some(Song::Ending),
        }
    }

    /// Tempo della musica della scena (match point, bullet time): solo il tema della partita lo
    /// cambia, le altre musiche suonano normali.
    pub fn tempo(&self, app: &App) -> (bool, bool) {
        match self {
            Scene::Game(s) if matches!(self.music(app), Some(Song::Theme(_))) => s.tempo(app),
            _ => (false, false),
        }
    }

    /// Tasti che valgono i comandi dei gamepad in questa schermata (vedi `input`): nei menu
    /// direzioni, A per confermare e B per tornare indietro; nell'attract A e Start sono lo Start e
    /// Select il gettone; nelle scelte e nelle iniziali ogni gamepad fa i tasti del suo lato.
    pub fn pad_keys(&self, app: &App) -> PadKeys {
        let start = |key: KeyCode| {
            input::pad_keys(move |_, c| match c {
                Control::A | Control::Start => Some(key),
                Control::Select => Some(KeyCode::Key5),
                _ => None,
            })
        };
        match self {
            Scene::Attract(_) | Scene::Scores(_) | Scene::Demo(_) | Scene::Ending(_) => start(KeyCode::Key1),
            Scene::Menu(_) => input::pad_keys(|_, c| match c {
                Control::Up => Some(KeyCode::Up),
                Control::Down => Some(KeyCode::Down),
                Control::Left => Some(KeyCode::Left),
                Control::Right => Some(KeyCode::Right),
                Control::A | Control::Start => Some(KeyCode::Enter),
                Control::B => Some(KeyCode::Escape),
                _ => None,
            }),
            Scene::Pick(s) => s.pad_keys(app),
            Scene::Paddles(s) => s.pad_keys(app),
            Scene::HowTo(_) => input::pad_keys(|_, c| match c {
                Control::A | Control::Start => Some(KeyCode::Key1),
                Control::B => Some(KeyCode::Escape),
                _ => None,
            }),
            Scene::Game(s) => s.pad_keys(app),
            Scene::Intro(_) | Scene::Challenger(_) | Scene::Clear(_) | Scene::Continue(_) => challenge_ui::pad_keys(app),
            Scene::Initials(s) => s.pad_keys(app),
        }
    }

    /// La scena usa C come tasto di gioco (NEXT): il tasto rapido del filtro CRT va spento.
    pub fn uses_bonus_keys(&self) -> bool {
        match self {
            Scene::Pick(_) | Scene::Paddles(_) => true,
            Scene::Game(s) => s.fx.is_some(),
            _ => false,
        }
    }

    pub fn draw(&self, app: &App) {
        match self {
            Scene::Attract(s) => s.draw(&app.attract, &app.renderer, app.hud()),
            Scene::Menu(s) => s.draw(app),
            Scene::Pick(s) => s.draw(app),
            Scene::Paddles(s) => s.draw(app),
            Scene::HowTo(s) => s.draw(app),
            Scene::Game(s) => s.draw(app),
            Scene::Demo(s) => s.draw(app),
            Scene::Intro(s) => s.draw(app),
            Scene::Challenger(s) => s.draw(app),
            Scene::Clear(s) => s.draw(app),
            Scene::Continue(s) => s.draw(app),
            Scene::Initials(s) => s.draw(app),
            Scene::Scores(s) => s.draw(app),
            Scene::Ending(s) => s.draw(app),
        }
    }
}

// --------------------------------------------------------------------- attract

/// Tasti di avvio partita: Invio, Spazio e 1 (come lo Start dei cabinati).
pub(crate) const START_KEYS: [KeyCode; 4] = [KeyCode::Enter, KeyCode::KpEnter, KeyCode::Space, KeyCode::Key1];

/// Moneta con il tasto 5 (come nei core arcade), Start per giocare se c'è credito o in Free Play.
/// Dopo il titolo l'attract mostra la classifica di CHALLENGE, poi la demo.
fn update_attract(attract: &mut Attract, app: &mut App, dt: f64) -> Option<Scene> {
    if input::pressed(KeyCode::Escape) {
        app.quit = true;
        return None;
    }
    if let Some(scene) = coin_and_start(app) {
        return Some(scene);
    }
    let hud = app.hud();
    let title = attract.phase == attract::Phase::Title;
    for event in attract.update(&app.attract, &app.renderer, hud, dt) {
        if app.cfg.game.attract_sound {
            app.play(event);
        }
    }
    (title && attract.phase != attract::Phase::Title).then(|| Scene::Scores(Scores::attract()))
}

/// Gettone (tasto 5) e Start nell'attract e nella classifica: Start va al menu.
pub(crate) fn coin_and_start(app: &mut App) -> Option<Scene> {
    if input::pressed(KeyCode::Key5) && !app.cfg.game.free_play && app.credits < 9 {
        app.credits += 1;
        app.play_coin();
    }
    // un tocco o il click di un encoder valgono come Start
    let tapped = !touch::taps().is_empty() || app.knob_clicked();
    if tapped && !app.cfg.game.free_play && app.credits == 0 {
        app.credits = 1; // touch: il primo tocco è il gettone, il secondo lo Start
        app.play_coin();
        return None;
    }
    if (tapped || input::any_pressed(&START_KEYS)) && (app.cfg.game.free_play || app.credits > 0) {
        if !app.cfg.game.free_play {
            app.credits -= 1;
        }
        app.play(Event::Hit);
        return Some(Scene::Menu(Menu::new(app)));
    }
    None
}

// ------------------------------------------------------------------------ menu

/// Nomi dei livelli di difficoltà del core (`Tuning::difficulty`).
const DIFFICULTY_NAMES: [&str; DIFFICULTY_LEVELS as usize] = ["EASY", "NORMAL", "HARD", "EXPERT"];
/// Livelli del bianco proposti dal menu, in percento (gli stessi dell'OSD del MiSTer).
const WHITE_LEVELS: [u8; 4] = [100, 87, 75, 62];
/// Spessori di pallina e racchette proposti dal menu ZOOM, in percento (`Game::zoom`).
const ZOOM_LEVELS: [u16; 5] = [100, 125, 150, 175, 200];

/// Volume del menu dopo un passo (vedi `Menu::change`): +1 e -1 si fermano a 0 e a 100, 0 (la
/// conferma) sale e dopo il 100 torna a 0. Un valore fuori dai passi (dal file) va al passo vicino.
fn step_volume(volume: u8, step: i8) -> u8 {
    let volume = volume.min(100);
    let v = volume / config::VOLUME_STEP * config::VOLUME_STEP;
    if step < 0 {
        if v < volume { v } else { v.saturating_sub(config::VOLUME_STEP) }
    } else if step == 0 && volume == 100 {
        0
    } else {
        (v + config::VOLUME_STEP).min(100)
    }
}

/// Simbolo della pausa per il touch: dove finisce sotto la cima del campo (unità a 480 righe,
/// scalate con `App::scale`) e luminosità in partita rispetto al grigio chiaro.
const PAUSE_ICON_BOTTOM: f32 = 26.0;
const PAUSE_ICON_DIM: f32 = 0.3;
/// Fondo della zona che mette in pausa (`in_pause_zone`), sotto la scritta TAP TO / PAUSE.
const PAUSE_ZONE_BOTTOM: f32 = 72.0;

/// Zona del touch che mette in pausa: in cima al centro, intorno al simbolo e alla scritta di
/// `Play::draw_pause_hint` (punto in coordinate di disegno).
fn in_pause_zone(app: &App, p: Vec2) -> bool {
    let (w, s) = (app.renderer.world_w, app.scale());
    (p.x - w / 2.0).abs() < w * 0.08 && p.y < PAUSE_ZONE_BOTTOM * s
}

/// Simbolo della pausa (due barrette) centrato in orizzontale su `cx`, da `top` alto `height`.
fn pause_icon(cx: f32, top: f32, height: f32, s: f32, color: Color) {
    let (bar_w, gap) = ((4.0 * s).round().max(1.0), (4.0 * s).round().max(1.0));
    for x in [cx - gap / 2.0 - bar_w, cx + gap / 2.0] {
        draw_rectangle(x, top, bar_w, height, color);
    }
}

/// Ruota del menu: angolo sul rullo tra una voce e la successiva (rad), raggio del rullo e altezza
/// del suo centro (in unità del campo a 480 righe, scalate con `App::scale`).
const WHEEL_STEP: f32 = 0.30;
const WHEEL_RADIUS: f32 = 150.0;
const WHEEL_CENTER: f32 = 300.0;
/// Le voci oltre questo angolo sul rullo non si vedono più.
const WHEEL_EDGE: f32 = FRAC_PI_2 * 0.95;
/// Durata dello scorrimento da una voce all'altra (s).
const WHEEL_SCROLL: f32 = 0.18;
/// Touch: corsa del dito oltre la quale trascina la ruota invece di toccare una voce.
const DRAG_START: f32 = 16.0;
/// secondi tra due passi della rotella del mouse
const WHEEL_GAP: f64 = 0.06;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Item {
    GameType,
    Players,
    Difficulty,
    /// volume di tutte le musiche, in percento (0 = nessuna musica)
    MusicVolume,
    /// volume degli effetti e delle voci, in percento
    EffectsVolume,
    AttractSound,
    WhiteLevel,
    /// spessore di pallina e racchette, per gli schermi piccoli
    Zoom,
    Fullscreen,
    Crt,
    /// punteggi dritti o rivolti ai giocatori (tavolo)
    Scores,
    /// il mouse come spinner del giocatore 1: non con il touch né con gli encoder del cabinato
    MouseSpinner,
    /// riprende la partita lasciata per il menu (`App::suspended`)
    Resume,
    Play,
    Quit,
    Shutdown,
}

/// Un dito sulla ruota: dove è partito, la posizione della ruota in quel momento e se la sta
/// trascinando.
#[derive(Clone, Copy)]
struct Drag {
    id: u64,
    y0: f32,
    pos0: f32,
    dragging: bool,
}

/// Menu principale a ruota: la voce scelta al centro, gialla e grande, le altre sopra e sotto su un
/// rullo, sempre più piccole e scure con la distanza. Su e giù (o la manopola, o il dito) girano la
/// ruota, sinistra e destra cambiano il valore, Invio (o Start, A, il click) conferma.
pub struct Menu {
    items: Vec<Item>,
    selected: usize,
    /// voce al centro della ruota (frazionaria durante lo scorrimento), da dove parte lo
    /// scorrimento in corso e da quanto
    pos: f32,
    from: f32,
    t: f32,
    drag: Option<Drag>,
    /// encoder già impostati per questa schermata
    knobs_ready: bool,
    /// ultimo passo della rotella del mouse (nel browser)
    wheel_at: f64,
}

impl Menu {
    pub fn new(app: &App) -> Self {
        Self::with_resume(app, app.suspended.is_some())
    }

    /// Menu con o senza la voce RESUME (`resume`: la partita che si lascia ora, non ancora in
    /// `App::suspended`); la voce al centro è RESUME se c'è, altrimenti PLAY.
    fn with_resume(app: &App, resume: bool) -> Self {
        let items = Self::items(app, resume);
        let start = if resume { Item::Resume } else { Item::Play };
        let selected = items.iter().position(|i| *i == start).unwrap_or(0);
        Self {
            items,
            selected,
            pos: selected as f32,
            from: selected as f32,
            t: WHEEL_SCROLL,
            drag: None,
            knobs_ready: false,
            wheel_at: 0.0,
        }
    }

    /// Voci del menu (le mosse speciali di NEXT sono sempre accese: non hanno una voce).
    fn items(app: &App, resume: bool) -> Vec<Item> {
        let mut items = vec![Item::GameType, Item::Players, Item::Difficulty];
        items.extend([
            Item::MusicVolume,
            Item::EffectsVolume,
            Item::AttractSound,
            Item::WhiteLevel,
            Item::Zoom,
            Item::Fullscreen,
            Item::Crt,
            Item::Scores,
        ]);
        if !app.touch && (app.encoders.is_none() || app.mouse_spinner()) {
            items.push(Item::MouseSpinner);
        }
        if resume {
            items.push(Item::Resume);
        }
        items.push(Item::Play);
        if !platform::WEB {
            items.push(Item::Quit); // nel browser si chiude la pagina
        }
        if app.on_raspberry {
            items.push(Item::Shutdown);
        }
        items
    }

    /// Per la verifica automatica: la ruota ferma sulla voce `i`.
    pub fn show(&mut self, i: usize) {
        self.select(i);
        (self.pos, self.from) = (self.selected as f32, self.selected as f32);
    }

    /// Dopo un cambio di modalità le voci possono cambiare: la ruota resta sulla stessa voce.
    fn refresh_items(&mut self, app: &App) {
        let items = Self::items(app, app.suspended.is_some());
        if items != self.items {
            let item = self.items[self.selected];
            let selected = items.iter().position(|i| *i == item).unwrap_or(0);
            let shift = selected as f32 - self.selected as f32;
            (self.pos, self.from) = (self.pos + shift, self.from + shift);
            self.selected = selected;
            self.items = items;
            self.knobs_ready = false; // gli encoder ripartono con il nuovo numero di voci
        }
    }

    /// Porta la voce `i` al centro, con lo scorrimento.
    fn select(&mut self, i: usize) {
        let i = i.min(self.items.len() - 1);
        if i != self.selected {
            self.selected = i;
            self.from = self.pos;
            self.t = 0.0;
        }
    }

    /// Avanza lo scorrimento della ruota verso la voce scelta (rallenta all'arrivo).
    fn scroll(&mut self, dt: f64) {
        if self.drag.is_some_and(|d| d.dragging) {
            return; // la ruota la tiene il dito
        }
        self.t = (self.t + dt as f32).min(WHEEL_SCROLL);
        let k = 1.0 - (1.0 - self.t / WHEEL_SCROLL).powi(3);
        self.pos = self.from + (self.selected as f32 - self.from) * k;
    }

    /// Voce `i` sul rullo con la ruota in `pos`: y del centro (coordinate di disegno) e coseno
    /// dell'angolo (1 al centro, verso 0 ai bordi); None se è oltre il bordo del rullo.
    fn place(app: &App, i: usize, pos: f32) -> Option<(f32, f32)> {
        let s = app.scale();
        let angle = (i as f32 - pos) * WHEEL_STEP;
        (angle.abs() <= WHEEL_EDGE).then(|| ((WHEEL_CENTER + WHEEL_RADIUS * angle.sin()) * s, angle.cos()))
    }

    /// Voce disegnata più vicina alla y toccata (coordinate di disegno), se è abbastanza vicina.
    fn item_at(&self, app: &App, y: f32) -> Option<usize> {
        let reach = WHEEL_RADIUS * WHEEL_STEP * app.scale() * 0.6;
        (0..self.items.len())
            .filter_map(|i| Self::place(app, i, self.pos).map(|(iy, _)| (i, (iy - y).abs())))
            .filter(|&(_, d)| d < reach)
            .min_by(|a, b| a.1.total_cmp(&b.1))
            .map(|(i, _)| i)
    }

    /// Touch: il dito trascina la ruota; un tocco sulla voce al centro la usa (true), un tocco su
    /// un'altra voce la porta al centro.
    fn read_touch(&mut self, app: &App) -> bool {
        let s = app.scale();
        let last = (self.items.len() - 1) as f32;
        let mut used = false;
        for f in touch::fingers() {
            let mine = self.drag.filter(|d| d.id == f.id);
            match f.phase {
                TouchPhase::Started if self.drag.is_none() => {
                    self.drag = Some(Drag {
                        id: f.id,
                        y0: f.pos.y,
                        pos0: self.pos,
                        dragging: false,
                    });
                }
                TouchPhase::Moved | TouchPhase::Stationary => {
                    if let Some(mut d) = mine {
                        d.dragging |= (f.pos.y - d.y0).abs() > DRAG_START * s;
                        if d.dragging {
                            // trascinare in su porta al centro le voci di sotto
                            self.pos = (d.pos0 - (f.pos.y - d.y0) / (WHEEL_RADIUS * WHEEL_STEP * s)).clamp(0.0, last);
                            self.selected = self.pos.round() as usize;
                        }
                        self.drag = Some(d);
                    }
                }
                TouchPhase::Ended | TouchPhase::Cancelled => {
                    if let Some(d) = mine {
                        self.drag = None;
                        if d.dragging {
                            // la ruota si ferma sulla voce più vicina
                            (self.from, self.t) = (self.pos, 0.0);
                        } else if f.phase == TouchPhase::Ended && f.id == touch::MOUSE_ID {
                            // il click del mouse (nel browser) usa sempre la voce attiva
                            used = true;
                        } else if f.phase == TouchPhase::Ended
                            && let Some(i) = self.item_at(app, f.pos.y)
                        {
                            if i == self.selected {
                                used = true;
                            } else {
                                self.select(i);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        used
    }

    fn label(app: &App, item: Item) -> String {
        let on_off = |b: bool| if b { "ON" } else { "OFF" };
        match item {
            Item::GameType => {
                let name = if app.next {
                    "NEXT"
                } else if app.evo {
                    "EVO"
                } else {
                    "CLASSIC"
                };
                format!("GAME TYPE : {name}")
            }
            Item::Players => {
                let name = match (app.players, app.cpu, app.challenge) {
                    (1, _, _) => "ONE",
                    (_, _, true) => "CHALLENGE",
                    (_, true, _) => "VS CPU",
                    _ => "TWO",
                };
                format!("PLAYERS : {name}")
            }
            Item::Difficulty => {
                let level = app.cfg.game.difficulty.min(DIFFICULTY_LEVELS - 1);
                format!("DIFFICULTY : {}", DIFFICULTY_NAMES[level as usize])
            }
            Item::MusicVolume => format!("MUSIC VOLUME : {}%", app.cfg.game.music_volume),
            Item::EffectsVolume => format!("EFFECTS VOLUME : {}%", app.cfg.game.effects_volume),
            Item::AttractSound => format!("ATTRACT SOUND : {}", on_off(app.cfg.game.attract_sound)),
            Item::WhiteLevel => format!("WHITE LEVEL : {}%", app.cfg.game.white_level),
            Item::Zoom => format!("ZOOM : {}%", app.cfg.game.zoom),
            Item::Fullscreen => format!("FULLSCREEN : {}", on_off(app.fullscreen())),
            Item::Crt => format!("CRT FILTER : {}", on_off(app.cfg.crt_effects.enabled)),
            Item::Scores => format!("SCORES : {}", if app.cfg.game.scores_upright { "UPRIGHT" } else { "FACING" }),
            Item::MouseSpinner => format!("MOUSE SPINNER : {}", on_off(app.mouse_spinner())),
            Item::Resume => "RESUME".into(),
            Item::Play => "PLAY".into(),
            Item::Quit => "QUIT".into(),
            Item::Shutdown => "SHUTDOWN".into(),
        }
    }

    /// Cambia il valore di una voce di opzione; false se la voce è un'azione. `step` è +1 o -1
    /// per destra e sinistra, 0 per la conferma (Invio, tocco, click): i volumi salgono o scendono
    /// di `VOLUME_STEP` fermandosi a 0 e a 100, con la conferma salgono e dopo il 100 tornano a 0;
    /// le altre voci passano sempre al valore successivo.
    fn change(app: &mut App, item: Item, step: i8) -> bool {
        // con un'altra partita scelta quella lasciata non si riprende più
        if matches!(item, Item::GameType | Item::Players | Item::Difficulty) {
            app.drop_suspended();
        }
        match item {
            Item::GameType => {
                // CLASSIC -> EVO -> NEXT -> CLASSIC
                (app.evo, app.next) = match (app.evo, app.next) {
                    (false, false) => (true, false),
                    (true, _) => (false, true),
                    (false, true) => (false, false),
                };
                if app.evo || app.next {
                    app.players = 2; // EVO e NEXT sono modalità a due giocatori
                }
                app.challenge &= app.next; // CHALLENGE si gioca in NEXT
                app.save_mode();
            }
            Item::Players => {
                // TWO -> VS CPU -> CHALLENGE -> ONE -> TWO, solo con le voci del tipo di gioco scelto
                // (CHALLENGE in NEXT, ONE in CLASSIC): PLAYERS non cambia GAME TYPE
                let classic = !app.evo && !app.next;
                (app.players, app.cpu, app.challenge) = match (app.players, app.cpu, app.challenge) {
                    (2, false, _) => (2, true, false),
                    (2, true, false) if app.next => (2, true, true),
                    (2, true, _) if classic => (1, false, false),
                    _ => (2, false, false),
                };
                app.save_mode();
            }
            Item::Difficulty => app.next_difficulty(),
            Item::MusicVolume => {
                // la musica che suona cambia subito (`App::set_music`)
                app.cfg.game.music_volume = step_volume(app.cfg.game.music_volume, step);
                config::save_preferences(&app.config_path, &app.cfg);
            }
            Item::EffectsVolume => {
                app.cfg.game.effects_volume = step_volume(app.cfg.game.effects_volume, step);
                config::save_preferences(&app.config_path, &app.cfg);
                app.play(Event::Hit); // per sentire il volume nuovo
            }
            Item::AttractSound => {
                app.cfg.game.attract_sound = !app.cfg.game.attract_sound;
                config::save_preferences(&app.config_path, &app.cfg);
            }
            Item::WhiteLevel => {
                // come l'opzione White level del MiSTer: 100 -> 87 -> 75 -> 62 -> 100
                let levels = WHITE_LEVELS;
                let i = levels
                    .iter()
                    .position(|&l| l == app.cfg.game.white_level)
                    .map_or(0, |i| i + 1);
                app.cfg.game.white_level = levels[i % levels.len()];
                config::save_preferences(&app.config_path, &app.cfg);
            }
            Item::Zoom => {
                // 100 -> 125 -> 150 -> 175 -> 200 -> 100; vale dalla prossima partita (quella
                // lasciata per il menu tiene i suoi parametri) e subito nelle demo
                let i = ZOOM_LEVELS
                    .iter()
                    .position(|&z| z == app.cfg.game.zoom)
                    .map_or(0, |i| i + 1);
                app.cfg.game.zoom = ZOOM_LEVELS[i % ZOOM_LEVELS.len()];
                app.params = Params::new(&app.cfg.tuning());
                config::save_preferences(&app.config_path, &app.cfg);
            }
            Item::Fullscreen => app.toggle_fullscreen(),
            Item::Crt => app.toggle_crt(),
            Item::Scores => {
                app.cfg.game.scores_upright = !app.cfg.game.scores_upright;
                config::save_preferences(&app.config_path, &app.cfg);
            }
            Item::MouseSpinner => app.set_mouse_spinner(!app.mouse_spinner()),
            _ => return false,
        }
        true
    }

    /// Usa la voce al centro: cambia il valore di un'opzione o fa l'azione.
    fn use_item(&self, app: &mut App) -> Option<Scene> {
        let item = self.items[self.selected];
        if Self::change(app, item, 0) {
            return None;
        }
        if item == Item::Play {
            app.drop_suspended();
        }
        match item {
            Item::Resume => app.suspended.take().map(|mut play| {
                // si torna in pausa: si riprende con un tocco (o Start), quando si è pronti
                play.suspend = false;
                play.paused = true;
                Scene::Game(play)
            }),
            // NEXT: prima la racchetta, poi i bonus
            Item::Play if app.next => {
                app.run = app.challenge.then(Run::new);
                Some(Scene::Paddles(PaddlePick::new(app)))
            }
            Item::Play => Some(Scene::Game(Box::new(Play::new(app)))),
            Item::Quit => {
                app.quit = true;
                None
            }
            Item::Shutdown => {
                platform::shutdown_system();
                None
            }
            _ => None,
        }
    }

    fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        let n = self.items.len();
        let mut confirm = self.read_touch(app);
        // nel browser la rotella del mouse gira la ruota, una voce per scatto (al più una ogni
        // WHEEL_GAP: i trackpad mandano tanti piccoli scatti), anche con il mouse come spinner
        let (_, wheel) = mouse_wheel();
        if platform::WEB && wheel != 0.0 && get_time() - self.wheel_at >= WHEEL_GAP {
            self.wheel_at = get_time();
            if wheel < 0.0 {
                self.select(self.selected + 1);
            } else {
                self.select(self.selected.saturating_sub(1));
            }
            self.knobs_ready = false; // lo spinner riparte dalla voce nuova
        }
        // encoder (o mouse come spinner): la manopola gira la ruota, il click usa la voce
        if let Some(enc) = &mut app.encoders
            && !std::mem::replace(&mut self.knobs_ready, true)
        {
            enc.configure(0, n as i32 - 1, 1, self.selected as i32);
        }
        for e in app.knob_events.clone() {
            match e.action {
                Action::Rotate(v) => self.select(v.max(0) as usize),
                Action::Click => confirm = true,
                _ => {}
            }
        }
        // tastiera e gamepad (`input`): la ruota si ferma alla prima e all'ultima voce
        if input::pressed(KeyCode::Up) || input::pressed(KeyCode::W) {
            self.select(self.selected.saturating_sub(1));
        }
        if input::pressed(KeyCode::Down) || input::pressed(KeyCode::S) {
            self.select(self.selected + 1);
        }
        let item = self.items[self.selected];
        let had_mouse = app.mouse_spinner();
        if input::pressed(KeyCode::Right) || input::pressed(KeyCode::D) {
            Self::change(app, item, 1);
        } else if input::pressed(KeyCode::Left) || input::pressed(KeyCode::A) {
            Self::change(app, item, -1);
        }
        confirm |= input::any_pressed(&[KeyCode::Enter, KeyCode::KpEnter, KeyCode::Space]);
        if confirm && let Some(scene) = self.use_item(app) {
            return Some(scene);
        }
        if app.mouse_spinner() != had_mouse {
            self.knobs_ready = false; // il mouse appena acceso riparte dalla voce scelta
        }
        self.refresh_items(app);
        self.scroll(dt);
        if input::pressed(KeyCode::Escape) {
            app.drop_suspended();
            return Some(Scene::Attract(Attract::new(&app.attract, false)));
        }
        None
    }

    fn draw(&self, app: &App) {
        let r = &app.renderer;
        let s = app.scale();
        let (w, h) = (r.world_w, r.world_h);
        let colors = &app.cfg.colors;
        // con GAME TYPE: NEXT il titolo prende il colore di accento
        let title = if app.next { colors.accent } else { colors.white };

        let title_y = 100.0 * s; // in coordinate di disegno (dall'alto)
        draw_rectangle(
            w / 2.0 - 150.0 * s,
            title_y - 30.0 * s,
            300.0 * s,
            60.0 * s,
            App::color(title),
        );
        r.text_centered(
            "MAIN MENU",
            &app.assets.font_text,
            50.0 * s,
            w / 2.0,
            title_y,
            0.0,
            App::color(colors.black),
        );

        // le voci lontane prima, quella al centro per ultima
        let mut order: Vec<usize> = (0..self.items.len()).collect();
        order.sort_by(|a, b| {
            let d = |i: usize| (i as f32 - self.pos).abs();
            d(*b).total_cmp(&d(*a))
        });
        let white = App::color(colors.white);
        for i in order {
            let Some((y, k)) = Self::place(app, i, self.pos) else { continue };
            let d = (i as f32 - self.pos).abs();
            // 40 al centro, 30 le vicine, 20 le altre: la Munro è nitida a multipli di 10
            let size = ((40.0 - 10.0 * d).max(20.0) / 10.0).round() * 10.0;
            let color = if d < 0.5 {
                App::color(colors.accent)
            } else {
                let light = 0.25 + 0.6 * k; // più scure verso i bordi del rullo
                Color::new(white.r * light, white.g * light, white.b * light, 1.0)
            };
            let label = Self::label(app, self.items[i]);
            r.text_centered(&label, &app.assets.font_text, size * s, w / 2.0, y, 0.0, color);
        }
        // versione in basso a destra: dice subito cosa gira sul cabinato
        let version = concat!("v", env!("CARGO_PKG_VERSION"));
        r.text_bottom_right(
            version,
            &app.assets.font_text,
            20.0 * s,
            w - 8.0 * s,
            h - 6.0 * s,
            App::color(colors.lgray),
        );
    }
}

#[cfg(test)]
mod menu_tests {
    use super::*;

    #[test]
    fn songs_are_found_by_name_and_the_ending_falls_back_to_champion() {
        let mut all = vec![Song::Title, Song::Intro, Song::Clear, Song::Continue, Song::GameOver, Song::Champion];
        all.extend(PaddleKind::ALL.map(Song::Theme));
        let numbers: Vec<u8> = all.iter().map(|s| s.number()).collect();
        assert!(numbers.iter().all(|&n| n > 0));
        let mut unique = numbers.clone();
        unique.dedup();
        assert_eq!(unique.len(), numbers.len());
        // i temi in fila, nell'ordine di PaddleKind
        assert!(numbers[6..].windows(2).all(|w| w[1] == w[0] + 1));
        let rom = paddws_sid::Rom::builtin();
        let ending = rom.song_number("ending").unwrap_or(Song::Champion.number());
        assert_eq!(Song::Ending.number(), ending);
    }

    #[test]
    fn the_egg_plays_the_ending_instead_of_the_title() {
        assert_eq!(egg_song(Some(Song::Title), true), Some(Song::Ending));
        assert_eq!(egg_song(Some(Song::Title), false), Some(Song::Title));
        for s in [None, Some(Song::Intro), Some(Song::Champion), Some(Song::Theme(PaddleKind::Titan))] {
            assert_eq!(egg_song(s, true), s);
        }
    }

    #[test]
    fn volumes_step_by_ten_and_stop_or_wrap() {
        assert_eq!(step_volume(50, 1), 60);
        assert_eq!(step_volume(50, -1), 40);
        assert_eq!(step_volume(100, 1), 100);
        assert_eq!(step_volume(0, -1), 0);
        // la conferma sale e dopo il 100 riparte da 0
        assert_eq!(step_volume(90, 0), 100);
        assert_eq!(step_volume(100, 0), 0);
        // valori scritti a mano nel file: al passo vicino
        assert_eq!(step_volume(35, 1), 40);
        assert_eq!(step_volume(35, -1), 30);
        assert_eq!(step_volume(30, -1), 20);
        assert_eq!(step_volume(95, 0), 100);
        assert_eq!(step_volume(250, -1), 90);
    }

    #[test]
    fn the_wheel_eases_into_the_chosen_item_and_stops_at_the_ends() {
        let mut m = Menu {
            items: vec![Item::GameType, Item::Players, Item::Difficulty, Item::Play, Item::Quit],
            selected: 3,
            pos: 3.0,
            from: 3.0,
            t: WHEEL_SCROLL,
            drag: None,
            knobs_ready: false,
            wheel_at: 0.0,
        };
        m.select(1);
        m.scroll(0.03);
        // prima veloce, poi rallenta: dopo un sesto del tempo ha già fatto più di un terzo della strada
        assert!(m.pos < 3.0 - 2.0 / 3.0 && m.pos > 1.0, "{}", m.pos);
        m.scroll(1.0);
        assert_eq!(m.pos, 1.0);
        m.select(99);
        assert_eq!(m.selected, 4);
    }
}

// ---------------------------------------------------------------------- partita

/// Tasti di un giocatore: (su, giù, avanti).
const CONTROLS: [(KeyCode, KeyCode, KeyCode); 2] = [
    (KeyCode::W, KeyCode::S, KeyCode::D),
    (KeyCode::Up, KeyCode::Down, KeyCode::Left),
];

#[derive(Default)]
struct Controls {
    direction: i8,
    fast: bool,
    forward: bool,
    /// NEXT: seleziona e attiva un bonus (valgono per un solo tick)
    select: bool,
    activate: bool,
    last_press: [Option<f64>; 2],
    /// touch: dito che tiene la racchetta e y (dall'alto) a cui portarne il centro
    finger: Option<u64>,
    target: Option<f32>,
    /// touch: tocco su una capsula della riserva, pressioni di "seleziona" ancora da fare e poi "usa"
    bonus_selects: u8,
    bonus_use: bool,
    /// mosse speciali: gesti del giocatore e mossa completata dall'ultimo scatto (vale per un tick)
    gesture: Gesture,
    special: Option<Special>,
    /// gamepad: verso della levetta al frame prima (1 su, -1 giù) e mezzelune del joystick
    pad_dir: i8,
    stick: Stick,
}

impl Controls {
    /// Scatto in avanti al tempo `now`; con le mosse speciali accese può completare un gesto, e
    /// allora `take_input` sceglie tra mossa e scatto.
    fn dash(&mut self, now: f64, moves: bool) {
        self.forward = true;
        if moves && let Some(special) = self.gesture.dash(now) {
            self.special = Some(special);
        }
    }
}

pub struct Play {
    /// si va al menu lasciando la partita da riprendere (`App::suspended`)
    pub suspend: bool,
    /// touch in CHALLENGE: il dito tenuto nella zona dello sfidante (`read_join`) e da quanto
    join: Option<(u64, f64)>,
    game: Match,
    controls: [Controls; 2],
    accumulator: f64,
    /// posizioni (x, y) di racchette e palla al tick precedente, per l'interpolazione
    previous: [(f32, f32); 3],
    flash: f64,
    paused: bool,
    /// vite rimaste in singolo
    lives: u8,
    /// secondi rimasti del "GAME OVER", poi si torna all'attract
    game_over: Option<f64>,
    /// effetti grafici della modalità NEXT
    pub(crate) fx: Option<NextFx>,
    /// x disegnata delle racchette (scatto in avanti animato)
    pad_draw_x: [f32; 2],
    /// secondi del conto alla rovescia iniziale: intanto la partita resta ferma
    countdown: f64,
    /// giocatori comandati dal computer: l'avversario a destra, tutti e due nella demo
    cpus: Vec<Cpu>,
    /// demo dell'attract: niente comandi, conto alla rovescia e fine partita
    demo: bool,
    /// encoder: impostati per la partita, e posizione delle manopole (pixel dal bordo alto; con il
    /// mouse come spinner solo quella del giocatore 1)
    knobs_ready: bool,
    knob: Option<[Option<i32>; 2]>,
    /// CHALLENGE: livello e punti arcade del giocatore (dal lato di `Score::side`)
    challenge: Option<(usize, Score)>,
    /// lato del giocatore contro la CPU: a sinistra, a destra in CHALLENGE dopo che lo sfidante
    /// di destra ha vinto
    solo: Side,
    /// CHALLENGE: sfida tra il campione e un nuovo sfidante al livello in corso
    duel: Option<usize>,
    /// secondi dall'ultimo colpo dell'HAMMER (la sua rete vibra subito dopo)
    hammer_net: f64,
    /// tema della sfida della CHALLENGE tra due giocatori: quello di un avversario, a caso (dal seme
    /// della partita, che il core usa per altro: la partita non cambia)
    theme: PaddleKind,
}

/// Seme della prossima partita.
fn next_seed(app: &mut App) {
    app.seed = app.seed.wrapping_mul(747_796_405).wrapping_add(2_891_336_453);
}

/// Parametri della partita al livello `level` di CHALLENGE: la velocità della palla del livello
/// con la difficoltà scelta.
fn rung_params(app: &App, level: usize) -> Params {
    Params::new(&Tuning {
        difficulty: RUNGS[level].speed_at(app.cfg.game.difficulty),
        ..app.cfg.tuning()
    })
}

impl Play {
    pub fn new(app: &mut App) -> Self {
        next_seed(app);
        let mut game = if app.next {
            Match::new_next_paddles(app.params.clone(), app.loadout, app.paddles, app.seed)
        } else {
            Match::new(app.params.clone(), app.players, app.evo, app.seed)
        };
        game.set_super_moves(true); // sempre accese in NEXT; fuori da NEXT non fa nulla
        let cpus = (app.cpu && app.players == 2)
            .then(|| Cpu::new(&app.params, app.cfg.game.difficulty, Side::Right, app.seed))
            .into_iter()
            .collect();
        Self::with_match(app, game, cpus)
    }

    /// Partita già creata, con i giocatori comandati dal computer.
    fn with_match(app: &App, game: Match, cpus: Vec<Cpu>) -> Self {
        let next = game.next.is_some();
        let mut play = Self {
            suspend: false,
            join: None,
            game,
            controls: Default::default(),
            accumulator: 0.0,
            previous: [(0.0, 0.0); 3],
            flash: 0.0,
            paused: false,
            lives: app.cfg.game.lives.max(1),
            game_over: None,
            fx: next.then(NextFx::new),
            pad_draw_x: [0.0; 2],
            countdown: COUNTDOWN_TIME,
            cpus,
            demo: false,
            knobs_ready: false,
            knob: None,
            challenge: None,
            solo: Side::Left,
            duel: None,
            hammer_net: 1.0,
            theme: PaddleKind::ALL[(app.seed >> 16) as usize % PaddleKind::COUNT],
        };
        play.pad_draw_x = [to_f32(play.game.paddles[0].x), to_f32(play.game.paddles[1].x)];
        play.previous = play.snapshot();
        for c in &mut play.controls {
            c.gesture = Gesture::new(to_f32(play.game.params.height));
        }
        play
    }

    /// Partita del livello in corso di CHALLENGE: la CPU con racchetta, bonus e abilità del
    /// livello, la velocità della palla del livello e della difficoltà scelta. Il giocatore sta
    /// dal suo lato (`Run::side`), con i bonus e la racchetta di quel lato; la CPU dall'altro.
    pub fn challenge(app: &mut App) -> Self {
        let run = app.run.as_ref().expect("CHALLENGE senza partita");
        let (level, total, side) = (run.level, run.score, run.side);
        let rung = RUNGS[level];
        let params = rung_params(app, level);
        let (loadouts, kinds) = rung.sides(side, app.loadout[side as usize], app.paddles[side as usize]);
        next_seed(app);
        let mut game = Match::new_next_paddles(params.clone(), loadouts, kinds, app.seed);
        game.set_super_moves(true);
        let cpus = vec![Cpu::new(&params, rung.cpu, side.opponent(), app.seed)];
        let mut play = Self::with_match(app, game, cpus);
        play.solo = side;
        let mut score = Score::new(side);
        score.total = total;
        play.challenge = Some((level, score));
        play
    }

    /// Sfida di CHALLENGE tra il campione e un nuovo sfidante: NEXT a due giocatori, ciascuno con
    /// i bonus e la racchetta del suo lato, ai punti e alla velocità della palla del livello in
    /// corso. I punti arcade non contano.
    pub fn duel(app: &mut App) -> Self {
        let level = app.run.as_ref().expect("sfida senza CHALLENGE").level;
        let params = rung_params(app, level);
        next_seed(app);
        let mut game = Match::new_next_paddles(params, app.loadout, app.paddles, app.seed);
        game.set_super_moves(true);
        let mut play = Self::with_match(app, game, Vec::new());
        play.duel = Some(level);
        play
    }

    /// Demo dell'attract, CPU contro CPU alla difficoltà NORMAL, come nel core MiSTer: in NEXT
    /// bonus e racchette a caso per tutti e due, in CHALLENGE a destra l'avversario di un livello a
    /// caso (racchetta, bonus, CPU e velocità della palla del livello). Le mosse speciali seguono
    /// l'opzione del menu (le CPU le usano da sole).
    pub fn demo(app: &mut App, mode: DemoMode) -> Self {
        next_seed(app);
        let mut rng = Rng::new(app.seed ^ 0xDE30_5EED);
        let tuning = Tuning {
            difficulty: DEMO_DIFFICULTY,
            ..app.cfg.tuning()
        };
        let mut params = Params::new(&tuning);
        let mut right_level = DEMO_DIFFICULTY;
        let mut game = if mode >= DemoMode::Next {
            let mut loadouts = [random_loadout(&mut rng), random_loadout(&mut rng)];
            let mut kinds = [random_kind(&mut rng), random_kind(&mut rng)];
            if mode == DemoMode::Challenge {
                let rung = RUNGS[rng.below(RUNGS.len() as u32) as usize];
                params = Params::new(&Tuning {
                    difficulty: rung.speed_at(DEMO_DIFFICULTY),
                    ..tuning
                });
                loadouts[1] = rung.loadout;
                kinds[1] = Some(rung.kind);
                right_level = rung.cpu;
            }
            Match::new_next_paddles(params.clone(), loadouts, kinds, app.seed)
        } else {
            Match::new(params.clone(), 2, mode == DemoMode::Evo, app.seed)
        };
        game.set_super_moves(true);
        let cpus = vec![
            Cpu::new(&params, DEMO_DIFFICULTY, Side::Left, app.seed),
            Cpu::new(&params, right_level, Side::Right, app.seed ^ 1),
        ];
        let mut play = Self::with_match(app, game, cpus);
        play.demo = true;
        play.countdown = 0.0;
        play
    }

    fn snapshot(&self) -> [(f32, f32); 3] {
        let [l, r] = &self.game.paddles;
        let b = &self.game.ball;
        [
            (to_f32(l.x), to_f32(l.y)),
            (to_f32(r.x), to_f32(r.y)),
            (to_f32(b.x), to_f32(b.y)),
        ]
    }

    /// Lati comandati dalla tastiera (o dagli encoder).
    fn active_sides(&self) -> &'static [Side] {
        if self.demo {
            &[]
        } else if self.game.players == 2 && self.cpus.is_empty() {
            &Side::BOTH
        } else if self.solo == Side::Right {
            &[Side::Right]
        } else {
            &[Side::Left]
        }
    }

    fn read_keys(&mut self, app: &App) {
        let window = app.cfg.paddle.double_click_time / 1000.0;
        let now = get_time();
        let moves = self.game.super_moves();
        for &side in self.active_sides() {
            let (up, down, forward) = CONTROLS[side as usize];
            let c = &mut self.controls[side as usize];
            for (i, (key, dir)) in [(up, 1i8), (down, -1i8)].into_iter().enumerate() {
                if input::pressed(key) {
                    // doppio tocco = accelerazione rapida
                    c.fast = c.last_press[i].is_some_and(|t| now - t <= window);
                    c.last_press[i] = Some(now);
                    c.direction = dir;
                    c.gesture.press(if dir > 0 { Dir::Up } else { Dir::Down }, now);
                }
            }
            for (key, other, other_dir) in [(up, down, -1i8), (down, up, 1i8)] {
                if input::released(key) {
                    // se il tasto opposto è ancora premuto si va da quella parte
                    if input::down(other) {
                        c.direction = other_dir;
                    } else {
                        c.direction = 0;
                        c.fast = false;
                    }
                }
            }
            if input::pressed(forward) {
                c.dash(now, moves);
            }
            if self.fx.is_some() {
                let (select, activate) = next_ui::BONUS_KEYS[side as usize];
                c.select |= input::pressed(select);
                c.activate |= input::pressed(activate);
            }
        }
    }

    /// Gamepad di ciascun lato comandato da un giocatore (`gamepad::side_of`): la levetta o la croce
    /// muove la racchetta (doppio tocco = accelerazione rapida, come i tasti), A scatta, B seleziona
    /// e C usa il bonus di NEXT. Con le mosse speciali le mezzelune del joystick + A
    /// (`gesture::Stick`, con le diagonali della levetta).
    fn read_pads(&mut self, app: &App) {
        let sides = self.active_sides();
        let solo = (sides.len() == 1).then(|| sides[0] as usize);
        let window = app.cfg.paddle.double_click_time / 1000.0;
        let now = get_time();
        let moves = self.game.super_moves();
        let pads = &app.pads;
        for &side in sides {
            let Some(slot) = pads.slot_of(side as usize, solo) else {
                continue;
            };
            let c = &mut self.controls[side as usize];
            let (dx, dy) = pads.dir(slot);
            let vertical = -dy; // 1 su, -1 giù, come `PlayerInput::direction`
            if vertical != c.pad_dir {
                if vertical != 0 {
                    let i = usize::from(vertical < 0);
                    c.fast = c.last_press[i].is_some_and(|t| now - t <= window);
                    c.last_press[i] = Some(now);
                    c.direction = vertical;
                } else if c.direction == c.pad_dir {
                    c.direction = 0;
                    c.fast = false;
                }
                c.pad_dir = vertical;
            }
            let forward = if side == Side::Left { dx > 0 } else { dx < 0 };
            c.stick.track(dy > 0, dy < 0, forward, now);
            if pads.pressed(slot, Control::A) {
                c.forward = true;
                if moves && let Some(special) = c.stick.dash(now) {
                    c.special = Some(special);
                }
            }
            if self.fx.is_some() {
                c.select |= pads.pressed(slot, Control::B);
                c.activate |= pads.pressed(slot, Control::C);
            }
        }
    }

    /// Gamepad come tasti in partita (`input`): Start mette e toglie la pausa, Select è il gettone;
    /// in pausa anche A riprende e B torna al menu. In CHALLENGE contro la CPU lo Start del
    /// gamepad del lato libero è quello dello sfidante.
    fn pad_keys(&self, app: &App) -> PadKeys {
        if self.demo || self.game_over.is_some() {
            return input::NO_KEYS;
        }
        let solo = self.solo as usize;
        let free = self.challenge.map(|_| 1 - solo);
        let paused = self.paused;
        input::pad_keys(|slot, c| match c {
            Control::Start if free.is_some_and(|f| app.pads.side_of(slot, Some(solo)) == f) => {
                free.map(|f| challenge_ui::SIDE_START[f])
            }
            Control::Start => Some(KeyCode::P),
            Control::A if paused => Some(KeyCode::P),
            Control::B if paused => Some(KeyCode::Escape),
            Control::Select => Some(KeyCode::Key5),
            _ => None,
        })
    }

    /// Touch: la racchetta segue il dito nella propria metà (tutto lo schermo se si gioca da soli),
    /// un altro dito nella stessa metà fa lo scatto in avanti, un tocco su una capsula della
    /// riserva usa quel bonus. Al centro in alto un tocco mette in pausa. Con le mosse speciali,
    /// uno scorrimento rapido del dito della racchetta (giù e su, o su e giù) seguito dallo scatto
    /// è una mossa.
    fn read_touch(&mut self, app: &mut App) -> bool {
        let fingers = touch::fingers();
        if fingers.is_empty() {
            return false;
        }
        let w = app.renderer.world_w;
        let alone = self.active_sides().len() == 1;
        let now = get_time();
        let moves = self.game.super_moves();
        for f in fingers {
            // il dito dello sfidante (`read_join`) non muove la racchetta
            if self.join.is_some_and(|(id, _)| id == f.id) {
                continue;
            }
            let held = self.controls.iter().position(|c| c.finger == Some(f.id));
            match f.phase {
                TouchPhase::Started => {
                    if in_pause_zone(app, f.pos) {
                        return true; // pausa
                    }
                    let side = if alone {
                        self.solo as usize
                    } else {
                        usize::from(f.pos.x >= w / 2.0)
                    };
                    let slot = self
                        .fx
                        .as_ref()
                        .and(next_ui::reserve_slot_at(app, &self.game, side, f.pos));
                    let c = &mut self.controls[side];
                    if let Some(slot) = slot {
                        // si seleziona quel posto un tick alla volta, poi lo si usa
                        let pl = &self.game.next.as_ref().expect("riserva solo in NEXT").players[side];
                        let n = pl.count();
                        c.bonus_selects = ((slot + n - (pl.selected as usize).min(n - 1)) % n) as u8;
                        c.bonus_use = true;
                    } else if c.finger.is_none() {
                        c.finger = Some(f.id);
                        c.target = Some(f.pos.y);
                        c.gesture.track(f.pos.y, now);
                    } else {
                        c.dash(now, moves);
                    }
                }
                TouchPhase::Moved | TouchPhase::Stationary => {
                    if let Some(i) = held {
                        self.controls[i].target = Some(f.pos.y);
                        self.controls[i].gesture.track(f.pos.y, now);
                    }
                }
                TouchPhase::Ended | TouchPhase::Cancelled => {
                    if let Some(i) = held {
                        self.controls[i].finger = None;
                        self.controls[i].target = None;
                        self.controls[i].gesture.lift();
                    }
                }
            }
        }
        false
    }

    /// Lato dello sfidante se in questo momento può entrare (CHALLENGE contro la CPU, non durante
    /// la sfida né nella demo).
    fn join_side(&self) -> Option<Side> {
        (self.challenge.is_some() && self.duel.is_none() && !self.demo && self.game_over.is_none())
            .then(|| self.solo.opponent())
    }

    /// Zona del touch in cui lo sfidante tiene il dito per entrare: dietro la racchetta della CPU,
    /// tra lei e il bordo (e oltre, nella fascia nera per le dita), dove c'è la scritta di
    /// `draw_join_hint`.
    fn in_join_zone(&self, app: &App, p: Vec2) -> bool {
        let Some(free) = self.join_side() else { return false };
        let back = self.join_strip();
        let w = app.renderer.world_w;
        if free == Side::Right { p.x > w - back } else { p.x < back }
    }

    /// Larghezza della striscia dietro la racchetta della CPU, dal bordo del campo fin quasi al
    /// dorso della racchetta nella posizione di partenza: si ferma prima del dorso di un quarto
    /// della distanza della racchetta dal bordo, anche con lo ZOOM (10 pixel su 15 di default).
    fn join_strip(&self) -> f32 {
        let p = &self.game.params;
        to_f32(p.pad_start_pos) * 0.75 - to_f32(p.pad_width) / 2.0
    }

    /// Touch in CHALLENGE: un dito appoggiato nella zona dello sfidante (`in_join_zone`) e tenuto
    /// lì è suo, non della racchetta; true quando è stato tenuto per `HOLD_SECONDS`.
    fn read_join(&mut self, app: &App, dt: f64) -> bool {
        for f in touch::fingers() {
            let mine = self.join.is_some_and(|(id, _)| id == f.id);
            match f.phase {
                TouchPhase::Started if self.join.is_none() && self.in_join_zone(app, f.pos) => {
                    self.join = Some((f.id, 0.0));
                }
                TouchPhase::Ended | TouchPhase::Cancelled if mine => self.join = None,
                _ => {}
            }
        }
        match &mut self.join {
            Some((_, t)) => {
                *t += dt;
                *t >= challenge_ui::HOLD_SECONDS
            }
            None => false,
        }
    }

    /// Encoder del cabinato (o il mouse come spinner del giocatore 1), come nella versione Python:
    /// la manopola dà la posizione della racchetta
    /// (dal centro; un giro per tutta la corsa, `turns_per_travel`), il click lo scatto in avanti,
    /// la pressione lunga torna al
    /// menu; i pulsanti SELEZIONA e USA comandano i bonus di NEXT. Con le mosse speciali, un giro
    /// rapido in un verso e ritorno seguito dal click è una mossa. True per tornare al menu.
    fn read_knobs(&mut self, app: &mut App) -> bool {
        let Some(enc) = &mut app.encoders else { return false };
        if !std::mem::replace(&mut self.knobs_ready, true) {
            // corsa di ciascuna manopola: le racchette di NEXT possono avere altezze diverse
            for (player, pad) in self.game.paddles.iter().enumerate() {
                let travel = paddws_core::fixed::floor(self.game.params.height - pad.height);
                let scale = enc.travel_scale(travel);
                enc.configure_one(player, 0, travel, scale, travel / 2);
            }
        }
        let knob = [0, 1].map(|p| enc.has_knob(p).then(|| enc.value(p)));
        self.knob = Some(knob);
        let sides = self.active_sides();
        let now = get_time();
        let moves = self.game.super_moves();
        for &side in sides {
            if let Some(value) = knob[side as usize] {
                self.controls[side as usize].gesture.track(value as f32, now);
            }
        }
        for e in &app.knob_events {
            if !sides.iter().any(|s| *s as usize == e.player) {
                continue;
            }
            let c = &mut self.controls[e.player];
            match e.action {
                Action::Click => c.dash(now, moves),
                Action::LongClick => return true,
                Action::Select => c.select = true,
                Action::Activate => c.activate = true,
                Action::Rotate(_) => {}
            }
        }
        false
    }

    /// Input per il prossimo tick; lo scatto in avanti vale per un solo tick.
    ///
    /// Mosse speciali: lo scatto che completa un gesto diventa la mossa solo se la mossa parte
    /// davvero (stesse condizioni del core: opzione accesa, niente battuta, barra sufficiente,
    /// nessuna mossa né bonus armato), e allora lo scatto normale di quel tick non c'è; altrimenti
    /// resta uno scatto normale, così un gesto senza barra non fa perdere lo scatto.
    fn take_input(&mut self) -> Input {
        let mut input = Input::default();
        let g = &self.game;
        let ready = Side::BOTH.map(|side| {
            g.super_moves()
                && !g.serving()
                && g.next.as_ref().is_some_and(|n| n.players[side as usize].special_ready(&g.params))
        });
        for (((cmd, c), pad), ready) in input
            .players
            .iter_mut()
            .zip(self.controls.iter_mut())
            .zip(&self.game.paddles)
            .zip(ready)
        {
            cmd.direction = c.direction;
            cmd.fast = c.fast;
            cmd.forward = std::mem::take(&mut c.forward);
            if let Some(special) = c.special.take()
                && ready
            {
                cmd.special = Some(special);
                cmd.forward = false;
            }
            cmd.select = std::mem::take(&mut c.select);
            cmd.activate = std::mem::take(&mut c.activate);
            // touch: posizione del dito come quella di un encoder (pixel dal bordo alto)
            cmd.top_offset = c.target.map(|y| (y - to_f32(pad.height) / 2.0).round() as i32);
            if c.bonus_selects > 0 {
                c.bonus_selects -= 1;
                cmd.select = true;
            } else if std::mem::take(&mut c.bonus_use) {
                cmd.activate = true;
            }
        }
        // encoder: la manopola dà la posizione a ogni tick (con STEER, lontana dalla racchetta, sterza)
        if let Some(knob) = self.knob {
            for &side in self.active_sides() {
                let cmd = &mut input.players[side as usize];
                cmd.top_offset = cmd.top_offset.or(knob[side as usize]);
            }
        }
        for cpu in &mut self.cpus {
            input.players[cpu.side() as usize] = cpu.input(&self.game);
        }
        input
    }

    fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        // il lampo del punto si spegne anche a partita finita: quello del punto decisivo, se si
        // fermasse qui, coprirebbe di bianco tutto il GAME OVER (e YOU WIN)
        self.flash = (self.flash - dt).max(0.0);
        // con GAME OVER, dopo la chiusura da televisore lo schermo resta nero per un po'
        let black = if self.over_texts().0 == Some("game_over") {
            app.attract.game_over_black_seconds()
        } else {
            0.0
        };
        if let Some(left) = &mut self.game_over {
            *left -= dt;
            if *left > -black {
                return None;
            }
            // CHALLENGE: fine della sfida, livello vinto o continue; altrimenti l'attract
            if self.duel.is_some() {
                let winner = if self.game.score[0] > self.game.score[1] {
                    Side::Left
                } else {
                    Side::Right
                };
                return Some(challenge_ui::duel_over(app, winner));
            }
            let Some((_, score)) = self.challenge else {
                return Some(Scene::Attract(Attract::new(&app.attract, false)));
            };
            let run = app.run.as_mut().expect("CHALLENGE senza partita");
            run.score = score.total;
            let me = score.side as usize;
            let (me, cpu) = (self.game.score[me], self.game.score[1 - me]);
            return Some(if me > cpu && run.level + 1 == LEVELS {
                // l'ultimo avversario: il finale
                Scene::Ending(Ending::new(app, cpu))
            } else if me > cpu {
                Scene::Clear(Clear::new(app, cpu))
            } else {
                Scene::Continue(Continue::new(app))
            });
        }
        // nella demo comandano le CPU: tasti, gettone e Start li legge la scena Demo
        if !self.demo {
            if input::pressed(KeyCode::Escape) {
                return Some(self.leave_for_menu(app));
            }
            if input::pressed(KeyCode::P) || input::pressed(KeyCode::Pause) {
                self.paused = !self.paused;
            }
            // CHALLENGE contro la CPU: può entrare un nuovo sfidante (non durante la sfida)
            let held = !self.paused && self.read_join(app, dt);
            if !self.paused
                && let Some((_, score)) = self.challenge
                && let Some(scene) = challenge_ui::challenger_during_play(app, score.total, held)
            {
                return Some(scene);
            }
            if self.paused {
                // touch: MENU in basso torna al menu, un tocco altrove riprende
                let (h, s) = (app.renderer.world_h, app.scale());
                for p in touch::taps() {
                    if (p.y - (h / 2.0 + 90.0 * s)).abs() < 30.0 * s {
                        return Some(self.leave_for_menu(app));
                    }
                    self.paused = false;
                    for c in &mut self.controls {
                        (c.finger, c.target) = (None, None);
                    }
                }
                return None;
            }
            if self.countdown > 0.0 {
                // un bip a ogni secondo, poi il via; la logica non avanza (partite identiche). In
                // CHALLENGE la voce dice "READY?" all'inizio e "GO!" al via, al posto del suo bip
                let calls = self.challenge.is_some() || self.duel.is_some();
                if calls && self.countdown == COUNTDOWN_TIME {
                    app.say(Call::Ready);
                }
                let before = self.countdown.ceil();
                self.countdown -= dt;
                if self.countdown <= 0.0 {
                    self.countdown = 0.0;
                    if calls {
                        app.say(Call::Go);
                    } else {
                        app.play(Event::Boost);
                    }
                } else if self.countdown.ceil() < before {
                    app.play(Event::Wall);
                }
                return None;
            }
            self.read_keys(app);
            self.read_pads(app);
            if self.read_knobs(app) {
                return Some(self.leave_for_menu(app));
            }
            if self.read_touch(app) {
                self.paused = true;
                return None;
            }
        }
        if let Some(fx) = &mut self.fx {
            fx.update(dt);
        }
        self.accumulator += dt.min(MAX_FRAME_TIME);
        // i suoni dei tick del frame, insieme alla fine (come il MiSTer: un effetto per frame)
        let mut sound = FrameSound::default();
        while self.accumulator >= PHYSICS_STEP {
            self.accumulator -= PHYSICS_STEP;
            self.previous = self.snapshot();
            let input = self.take_input();
            if let Some(fx) = &mut self.fx {
                fx.before_tick(&self.game);
            }
            let homes = self.game.paddles.each_ref().map(|pad| pad.at_home());
            let before = self.game.score;
            let events = self.game.step(&input);
            if let Some((_, score)) = &mut self.challenge {
                score.on_tick(&self.game, before, events);
            }
            // lo scatto che intercetta la palla la colpisce subito: la racchetta a schermo non
            // scivola, altrimenti la palla rimbalzerebbe prima che arrivi
            if events.has(Event::Hit) || events.has(Event::Boost) {
                for (side, pad) in self.game.paddles.iter().enumerate() {
                    let away = if side == 0 {
                        self.game.ball.vx > 0
                    } else {
                        self.game.ball.vx < 0
                    };
                    if homes[side] && !pad.at_home() && away {
                        self.pad_draw_x[side] = to_f32(pad.x);
                    }
                }
            }
            if let Some(fx) = &mut self.fx {
                fx.after_tick(&self.game, events, app.scale());
            }
            for event in events.iter() {
                // la demo suona solo con i suoni dell'attract
                // colpo della racchetta HAMMER della CPU (la palla riparte verso il giocatore): la
                // sua rete vibra
                if event == Event::Hit
                    && self.net_kind() == Some(PaddleKind::Hammer)
                    && (self.game.ball.vx > 0) == (self.solo == Side::Right)
                {
                    self.hammer_net = 0.0;
                }
                if !self.demo || app.cfg.game.attract_sound {
                    sound.add(event);
                    if event == Event::SpecialHit
                        && let Some(special) = self.game.next.as_ref().and_then(|n| n.special_flight)
                    {
                        sound.special_hit(special);
                    }
                }
                if event == Event::Score {
                    self.flash = FLASH_TIME;
                    if self.game.players == 1 {
                        self.lives = self.lives.saturating_sub(1); // palla mancata contro il muro
                    }
                }
            }
            // fine partita: chi arriva per primo ai punti stabiliti, o le vite finite in singolo;
            // la demo finisce invece a tempo
            if self.demo {
                continue;
            }
            let target = self.target(app);
            let over = if self.game.players == 2 {
                self.game.score.iter().any(|&s| s >= target)
            } else {
                self.lives == 0
            };
            if over {
                self.game_over = Some(app.attract.game_over_seconds());
                // vittoria contro la CPU: la voce "YOU WIN!" con la scritta (all'ultimo livello
                // della CHALLENGE la dice il finale, poco dopo); "PERFECT!" se un giocatore vince
                // senza punti dell'avversario, anche in due
                let last = self.challenge.is_some_and(|(level, _)| level + 1 == LEVELS);
                if !last && self.perfect() {
                    sound.shout = Some(Call::Perfect);
                } else if self.winner() == Some("you_win") && !last {
                    sound.shout = Some(Call::YouWin);
                }
                break;
            }
        }
        // nel bullet time gli effetti rallentano con il gioco
        app.play_frame(sound, self.game.next.as_ref().is_some_and(|n| n.bullet_on));
        self.hammer_net += dt;
        let unit = app.renderer.world_h / 240.0;
        for (x, pad) in self.pad_draw_x.iter_mut().zip(&self.game.paddles) {
            *x = slide(*x, to_f32(pad.x), dt, unit);
        }
        None
    }

    /// Punti per vincere: quelli del livello in CHALLENGE, altrimenti quelli delle opzioni.
    fn target(&self, app: &App) -> u16 {
        match (self.challenge, self.duel) {
            (Some((level, _)), _) | (None, Some(level)) => RUNGS[level].points,
            (None, None) => app.cfg.game.points_to_win.max(1),
        }
    }

    /// Tempo della musica: `fast` al match point (in due, uno dei giocatori a un punto dalla
    /// vittoria: dura fino alla fine della partita, perché i punti non calano), `slow` nel bullet
    /// time di NEXT (anche durante la rampa d'entrata).
    pub fn tempo(&self, app: &App) -> (bool, bool) {
        let target = self.target(app);
        let fast = self.game.players == 2 && self.game.score.iter().any(|&s| s.saturating_add(1) >= target);
        let slow = self.game.next.as_ref().is_some_and(|n| n.bullet_on);
        (fast, slow)
    }

    /// Posizioni interpolate tra gli ultimi due tick: movimento fluido a qualunque refresh.
    fn positions(&self, scale: f32) -> [(f32, f32); 3] {
        let alpha = (self.accumulator / PHYSICS_STEP) as f32;
        let snap = SNAP_DISTANCE * scale;
        let current = self.snapshot();
        let mut pos: [(f32, f32); 3] = std::array::from_fn(|i| {
            let ((x0, y0), (x1, y1)) = (self.previous[i], current[i]);
            if (x1 - x0).abs() > snap || (y1 - y0).abs() > snap {
                (x1, y1)
            } else {
                (x0 + (x1 - x0) * alpha, y0 + (y1 - y0) * alpha)
            }
        });
        pos[0].0 = self.pad_draw_x[0];
        pos[1].0 = self.pad_draw_x[1];
        pos
    }

    fn draw(&self, app: &App) {
        let r = &app.renderer;
        let colors = &app.cfg.colors;
        let white = App::color(colors.white);
        if self.flash > 0.0 {
            r.fill(white);
            return;
        }
        let s = app.scale();
        let p = &self.game.params;
        let (w, h) = (r.world_w, r.world_h);
        let (invert, shake) = NextFx::hit_stop(&self.game, h / 240.0);
        let shake = shake + self.fx.as_ref().map_or(0.0, |fx| fx.kick_shake(h / 240.0));
        if invert {
            r.fill(white); // hit-stop del SUPER: un istante a schermo invertito
            return;
        }

        // nel bullet time tutto diventa grigio e sfocato tranne la racchetta di chi l'ha attivato,
        // disegnata dopo, nitida (senza la sfocatura resta solo il grigio)
        let bullet = next_ui::bullet_time(&self.game);
        let blurred = bullet.is_some() && r.begin_blur();
        let white = next_ui::slowed_color(white, bullet.is_some(), white, App::color(colors.lgray));
        // fine partita: secondi dall'inizio (dopo il lampo del punto) e, con GAME OVER, il campo
        // che si spegne (`attract::net_off`, `attract::pads_left`)
        let over = self
            .game_over
            .map(|left| (app.attract.game_over_seconds() - left - FLASH_TIME).max(0.0));
        let field_off = over.filter(|_| self.over_texts().0 == Some("game_over"));
        let net_off = field_off.map_or(0.0, attract::net_off) * h;
        // linea tratteggiata centrale (in NEXT la COMETA ne spazza i trattini)
        let dash = (10.0 * s).floor().max(1.0);
        let line_w = ((to_f32(p.pad_width) / 2.0).floor() * w / 800.0).floor().max(1.0);
        // touch: in cima alla linea il simbolo della pausa (`draw_pause_hint`) al posto dei trattini
        let pause_hint = self.pause_hint(app);
        let mut y = if let Some(kind) = self.net_kind() {
            self.draw_net(app, kind, white, net_off, pause_hint);
            h
        } else {
            0.0
        };
        let mut i = 0;
        while y < h {
            let dx = self.fx.as_ref().map_or(0.0, |fx| fx.dash_offset(i));
            if !(pause_hint && y < PAUSE_ICON_BOTTOM * s) && y >= net_off {
                draw_rectangle(w / 2.0 - line_w / 2.0 + dx, y, line_w, dash.min(h - y), white);
            }
            y += dash * 2.0;
            i += 1;
        }

        let pos = self.positions(s);
        if let Some(fx) = &self.fx {
            fx.draw_field(app, &self.game, &pos, shake, bullet.map(|b| b.side));
        }
        for (pad, &(x, y)) in self.game.paddles.iter().zip(&pos).filter(|_| self.fx.is_none()) {
            r.rect_centered(x, y, to_f32(pad.width), to_f32(pad.height), white);
            if self.game.evo {
                r.rect_centered(
                    x,
                    y,
                    to_f32(pad.width),
                    to_f32(pad.boost_height),
                    App::color(colors.lgray),
                );
            }
        }
        let ball = &self.game.ball;
        let blink_off = self.game.serving() && (self.game.serve_timer * 8 / TICK_HZ) % 2 == 1;
        if !blink_off && self.fx.is_none() {
            let d = to_f32(ball.radius) * 2.0;
            r.rect_centered(pos[2].0, pos[2].1, d, d, white);
        }
        // GAME OVER: spenta la mezzeria se ne va la palla e le racchette si accorciano fino a sparire
        if let Some(t) = field_off {
            let left = attract::pads_left(t);
            if left < 1.0 {
                let d = to_f32(ball.radius) * 4.0;
                r.rect_centered(pos[2].0, pos[2].1, d, d, BLACK);
                for (pad, &(x, y)) in self.game.paddles.iter().zip(&pos) {
                    let (ph, cw) = (to_f32(pad.height) + 4.0 * s, to_f32(pad.width) * 6.0);
                    let cut = ph * (1.0 - left) / 2.0;
                    let top = r.screen_y(y) - ph / 2.0;
                    draw_rectangle(x - cw / 2.0, top, cw, cut, BLACK);
                    draw_rectangle(x - cw / 2.0, top + ph - cut, cw, cut, BLACK);
                }
            }
        }

        // punteggi rivolti ai giocatori, seduti ai lati sinistro e destro del tavolo, oppure (SCORES:
        // UPRIGHT) dritti in alto ai lati della linea centrale, record e palle del singolo a destra,
        // come sul MiSTer
        let (ox, oy) = (60.0 * w / 800.0, 60.0 * h / 480.0);
        let font = &app.assets.font_score;
        let score = self.game.score;
        if app.cfg.game.scores_upright {
            let y = 42.0 * h / 480.0;
            r.text_centered(&format!("{:02}", score[0]), font, 50.0 * s, w / 2.0 - 2.0 * ox, y, 0.0, white);
            if self.game.players == 2 {
                r.text_centered(&format!("{:02}", score[1]), font, 50.0 * s, w / 2.0 + 2.0 * ox, y, 0.0, white);
            } else {
                let text = &app.assets.font_text;
                let x = w / 2.0 + 2.0 * ox;
                r.text_centered(&format!("TOP {:02}", self.game.best), text, 32.0 * s, x, 30.0 * h / 480.0, 0.0, white);
                r.text_centered(&format!("BALLS {}", self.lives), text, 32.0 * s, x, 30.0 * h / 480.0 + 32.0 * s, 0.0, white);
            }
        } else {
            r.text_centered(
                &format!("{:02}", score[0]),
                font,
                50.0 * s,
                w / 2.0 - ox,
                h - oy,
                FRAC_PI_2,
                white,
            );
            if self.game.players == 2 {
                r.text_centered(
                    &format!("{:02}", score[1]),
                    font,
                    50.0 * s,
                    w / 2.0 + ox,
                    oy,
                    -FRAC_PI_2,
                    white,
                );
            } else {
                // record in singolo, centrato sul punteggio
                let text = format!("TOP {:02}", self.game.best);
                r.text_centered(
                    &text,
                    &app.assets.font_text,
                    32.0 * s,
                    w / 2.0 - ox - 55.0 * s,
                    h - oy,
                    FRAC_PI_2,
                    white,
                );
                // palle rimaste, accanto al record
                r.text_centered(
                    &format!("BALLS {}", self.lives),
                    &app.assets.font_text,
                    32.0 * s,
                    w / 2.0 - ox - 85.0 * s,
                    h - oy,
                    FRAC_PI_2,
                    white,
                );
            }
        }
        if let Some(fx) = &self.fx {
            fx.draw_hud(app, &self.game);
        }
        if let Some((level, score)) = &self.challenge {
            // punti arcade in basso dalla parte dell'avversario (mai sotto la racchetta del
            // giocatore, come sul MiSTer), lontano dai punteggi e dalla linea centrale, con il
            // livello e il moltiplicatore dello scambio
            let gray = App::color(colors.lgray);
            let font = &app.assets.font_text;
            let y = h - 14.0 * s;
            let x = |f: f32| if score.side == Side::Left { w * f } else { w * (1.0 - f) };
            r.text_centered(&format!("{:07}", score.total), font, 26.0 * s, x(0.72), y, 0.0, white);
            r.text_centered(&format!("L{}", level + 1), font, 22.0 * s, x(0.6), y, 0.0, gray);
            if score.multiplier() > 1 {
                let accent = App::color(colors.accent);
                let mult = format!("x{}", score.multiplier());
                r.text_centered(&mult, font, 22.0 * s, x(0.83), y, 0.0, accent);
            }
        }
        if blurred {
            r.end_blur(bullet.map_or(1.0, |b| b.k));
        }
        if let Some(fx) = &self.fx {
            if let Some(b) = bullet {
                fx.draw_pad(app, &self.game, pos[b.side], shake, b.side);
            }
            fx.draw_labels(app, &self.game, &pos, shake);
        }
        if pause_hint {
            self.draw_pause_hint(app);
            self.draw_join_hint(app);
        }
        if self.countdown > 0.0 {
            let size = 110.0 * s;
            draw_rectangle(
                w / 2.0 - size * 0.55,
                h / 2.0 - size * 0.6,
                size * 1.1,
                size * 1.2,
                BLACK,
            );
            let digit = format!("{}", self.countdown.ceil() as u32);
            r.text_centered(&digit, &app.assets.font_score, size, w / 2.0, h / 2.0, 0.0, white);
        }
        if self.paused {
            r.text_centered("PAUSE", &app.assets.font_text, 60.0 * s, w / 2.0, h / 2.0, 0.0, white);
            let gray = App::color(colors.lgray);
            let font = &app.assets.font_text;
            if app.touch {
                r.text_centered("TAP TO RESUME", font, 30.0 * s, w / 2.0, h / 2.0 + 45.0 * s, 0.0, gray);
                r.text_centered("MENU", font, 40.0 * s, w / 2.0, h / 2.0 + 90.0 * s, 0.0, white);
            } else if app.pad_used {
                r.text_centered("START TO RESUME", font, 30.0 * s, w / 2.0, h / 2.0 + 45.0 * s, 0.0, gray);
                r.text_centered("B = MENU", font, 30.0 * s, w / 2.0, h / 2.0 + 80.0 * s, 0.0, gray);
            }
        }
        if let Some(t) = over {
            // in NEXT chi ha vinto prende il colore di accento
            let colors = &app.cfg.colors;
            let winner_color = if self.fx.is_some() { colors.accent } else { colors.white };
            let (title, winner) = self.over_texts();
            // YOU WIN: la palla parte dalla racchetta del giocatore
            let me = pos[self.solo as usize];
            let ball = (vec2(me.0, r.screen_y(me.1)), to_f32(self.game.ball.radius) * 2.0);
            let (winner_color, accent) = (App::color(winner_color), App::color(colors.accent));
            attract::draw_game_over_anim(&app.attract, r, title, winner, winner_color, accent, t, ball);
            if field_off.is_some() {
                attract::draw_crt_close(r, t, app.attract.game_over_seconds() - FLASH_TIME);
            }
        }
    }

    /// Rete dell'avversario: solo nella CHALLENGE contro la CPU (non nelle sfide tra due giocatori,
    /// nelle altre modalità e nella demo).
    fn net_kind(&self) -> Option<PaddleKind> {
        let (level, _) = self.challenge.as_ref().filter(|_| !self.demo && self.duel.is_none())?;
        Some(RUNGS[*level].kind)
    }

    /// Rete dell'avversario `kind`, come `net_px` di mister/rtl/pong_render.v, in pixel di uno schermo a
    /// 240 righe: riga per riga, colonne dal centro (quelle della rete di sempre sono -1 e 0).
    /// - ARCADE: quadratini vuoti 6x6 ogni 16 righe;
    /// - TWIST: trattini inclinati di 4 righe ogni 8, che si piegano verso la palla quando passa;
    /// - HAMMER: rete doppia, trattini di 10 righe ogni 16, che vibra dopo un colpo dell'HAMMER;
    /// - TITAN: trattini lunghi 20 righe ogni 32;
    /// - BLASTER: due file di puntini 2x2 sfalsati, ogni 8 righe;
    /// - RUSH: trattini di 8 righe ogni 16 che scorrono verso il basso, con 2 righe gialle scure sopra;
    /// - GUARDIAN: mattoni 4x4 sfalsati, due per riga, ogni 8 righe, e gli angoli del campo gialli.
    ///
    /// Come la rete di sempre: grigia nel bullet time (`white`), spenta dall'alto fino a `net_off`
    /// a fine partita, senza la zona del simbolo della pausa sul touch; la COMETA ne sposta i pezzi.
    fn draw_net(&self, app: &App, kind: PaddleKind, white: Color, net_off: f32, pause_hint: bool) {
        let r = &app.renderer;
        let (w, h) = (r.world_w, r.world_h);
        let (s, u) = (app.scale(), h / 240.0);
        let accent = App::color(app.cfg.colors.accent);
        let trail = Color::from_rgba(0x5C, 0x4C, 0x0D, 255);
        let dash = (10.0 * s).floor().max(1.0);
        let t = (get_time() * 60.0) as i32;
        // TWIST: palla vicina alla rete (entro 30 righe), suo verso e sua riga
        let pos = self.positions(s);
        let (bx, by) = (pos[2].0, r.screen_y(pos[2].1) / u);
        let bend_on = (bx - w / 2.0).abs() < 30.0 * u;
        let bend_dir = if self.game.ball.vx > 0 { 1 } else { -1 };
        // HAMMER: 14 frame di vibrazione, un pixel a un lato e all'altro ogni due frame
        let since = (self.hammer_net * 60.0) as i32;
        let shake = if since < 14 && since / 2 % 2 == 1 { 1 } else { 0 };
        let shake_dir = since / 4 % 2 == 1;
        let mut spans: Vec<(i32, i32, Color)> = Vec::with_capacity(2);
        for yy in 0..240 {
            spans.clear();
            match kind {
                PaddleKind::Arcade => {
                    let q = yy & 15;
                    if q == 2 || q == 7 {
                        spans.push((-3, 2, white));
                    } else if (3..7).contains(&q) {
                        spans.extend([(-3, -3, white), (2, 2, white)]);
                    }
                }
                PaddleKind::Twist => {
                    if yy & 4 == 0 {
                        let d = (yy as f32 - by).abs();
                        let b = match d {
                            _ if !bend_on => 0,
                            d if d < 10.0 => 4,
                            d if d < 20.0 => 3,
                            d if d < 30.0 => 2,
                            d if d < 40.0 => 1,
                            _ => 0,
                        };
                        let x0 = ((yy >> 1) & 3) - 2 + bend_dir * b;
                        spans.push((x0, x0 + 1, white));
                    }
                }
                PaddleKind::Hammer => {
                    if yy & 15 < 10 {
                        let sh = shake * if ((yy >> 4) & 1 == 1) != shake_dir { 1 } else { -1 };
                        spans.extend([(-4 + sh, -2 + sh, white), (1 + sh, 3 + sh, white)]);
                    }
                }
                PaddleKind::Titan => {
                    if (2..22).contains(&(yy & 31)) {
                        spans.push((-1, 0, white));
                    }
                }
                PaddleKind::Blaster => match (yy >> 1) & 3 {
                    0 => spans.push((-3, -2, white)),
                    2 => spans.push((1, 2, white)),
                    _ => {}
                },
                PaddleKind::Rush => {
                    let q = ((yy & 15) - (t & 15)) & 15;
                    if q < 8 {
                        spans.push((-1, 0, white));
                    } else if q >= 14 {
                        spans.push((-1, 0, trail));
                    }
                }
                PaddleKind::Guardian => {
                    let sx = if yy & 8 != 0 { -3 } else { 0 };
                    if yy & 7 < 4 {
                        spans.extend([(-3 + sx, sx, white), (2 + sx, 5 + sx, white)]);
                    }
                }
            }
            let y = yy as f32 * u;
            if y < net_off || (pause_hint && y < PAUSE_ICON_BOTTOM * s) {
                continue;
            }
            let dx = self.fx.as_ref().map_or(0.0, |fx| fx.dash_offset((y / (dash * 2.0)) as usize));
            for &(a, b, color) in &spans {
                draw_rectangle(w / 2.0 + a as f32 * u + dx, y, (b - a + 1) as f32 * u, u, color);
            }
        }
        // il boss: gli angoli del campo gialli, 14 pixel per lato, spessi 2
        if kind == PaddleKind::Guardian {
            let (l, t2) = (14.0 * u, 2.0 * u);
            for (x, y, fx, fy) in [(0.0, 0.0, 0.0, 0.0), (w, 0.0, 1.0, 0.0), (0.0, h, 0.0, 1.0), (w, h, 1.0, 1.0)] {
                draw_rectangle(x - fx * l, y - fy * t2, l, t2, accent);
                draw_rectangle(x - fx * t2, y - fy * l, t2, l, accent);
            }
        }
    }

    /// Scritte della fine partita: (titolo, chi ha vinto). Solo chi ha vinto: YOU WIN, o CPU WINS a
    /// un livello perso della CHALLENGE (il GAME OVER viene dopo, se il CONTINUE scade); vinta senza
    /// punti dell'avversario, PERFECT al posto di YOU WIN, o di GAME OVER sopra chi ha vinto.
    fn over_texts(&self) -> (Option<&'static str>, Option<&'static str>) {
        let winner = self.winner();
        let lost_level = self.challenge.is_some() && self.duel.is_none() && winner == Some("cpu_wins");
        match (winner, self.perfect()) {
            (Some("you_win"), true) => (None, Some("perfect")),
            (Some("you_win"), false) => (None, winner),
            (_, true) => (Some("perfect"), winner),
            _ if lost_level => (None, winner),
            _ => (Some("game_over"), winner),
        }
    }

    /// Touch: si mostra dove toccare per la pausa (non nella demo, in pausa né a partita finita).
    fn pause_hint(&self, app: &App) -> bool {
        app.touch && !self.demo && !self.paused && self.game_over.is_none()
    }

    /// Simbolo della pausa in cima alla linea centrale, dentro la zona che mette in pausa
    /// (`in_pause_zone`): in partita appena visibile; durante il conto alla rovescia in grigio
    /// chiaro, con sotto TAP TO / PAUSE su due righe brevi, che restano nella zona e tra i punteggi
    /// (nei campi stretti, dove TAP TO non ci sta, solo PAUSE).
    fn draw_pause_hint(&self, app: &App) {
        let r = &app.renderer;
        let (w, s) = (r.world_w, app.scale());
        let gray = App::color(app.cfg.colors.lgray);
        let counting = self.countdown > 0.0;
        let k = if counting { 1.0 } else { PAUSE_ICON_DIM };
        let color = Color::new(gray.r * k, gray.g * k, gray.b * k, 1.0);
        let top = 8.0 * s;
        pause_icon(w / 2.0, top, PAUSE_ICON_BOTTOM * s - top, s, color);
        if counting {
            let font = &app.assets.font_text;
            let size = 18.0 * s;
            // dove comincia, dal centro, il punteggio più vicino in cima (vedi `draw`)
            let ox = 60.0 * w / 800.0;
            let inner = if app.cfg.game.scores_upright {
                2.0 * ox - r.text_width("00", &app.assets.font_score, 50.0 * s) / 2.0
            } else {
                ox - 25.0 * s
            };
            // nei campi stretti (4:3) TAP TO non ci sta tra i punteggi: resta solo PAUSE
            let full = r.text_width("TAP TO", font, size) / 2.0 + 6.0 * s < inner;
            let lines: &[&str] = if full { &["TAP TO", "PAUSE"] } else { &["PAUSE"] };
            let half = lines.iter().map(|l| r.text_width(l, font, size)).fold(0.0, f32::max) / 2.0;
            let y = (PAUSE_ICON_BOTTOM + 13.0) * s;
            // fondo nero: la linea tratteggiata passa sotto la scritta
            let box_h = (lines.len() as f32 * 19.0 + 4.0) * s;
            draw_rectangle(w / 2.0 - half - 3.0 * s, y - 11.0 * s, 2.0 * half + 6.0 * s, box_h, BLACK);
            for (i, line) in lines.iter().enumerate() {
                r.text_centered(line, font, size, w / 2.0, y + i as f32 * 19.0 * s, 0.0, color);
            }
        }
    }

    /// Al menu: se la partita non è finita resta da riprendere con RESUME (il ciclo principale la
    /// mette in `App::suspended`, vedi `suspend`).
    fn leave_for_menu(&mut self, app: &mut App) -> Scene {
        self.suspend = self.game_over.is_none();
        if !self.suspend {
            app.run = None;
        }
        Scene::Menu(Menu::with_resume(app, self.suspend))
    }

    /// Touch in CHALLENGE: P2 HOLD HERE nella zona dello sfidante (`in_join_zone`), dietro la
    /// racchetta della CPU, in verticale lungo il bordo e girata verso chi sta da quel lato del
    /// tavolo (come il suo punteggio). Come il simbolo della pausa: appena visibile in partita, in
    /// grigio chiaro nel conto alla rovescia e mentre lo sfidante tiene il dito.
    fn draw_join_hint(&self, app: &App) {
        let Some(free) = self.join_side() else { return };
        let r = &app.renderer;
        let (w, h, s) = (r.world_w, r.world_h, app.scale());
        let gray = App::color(app.cfg.colors.lgray);
        let k = if self.countdown > 0.0 || self.join.is_some() { 1.0 } else { PAUSE_ICON_DIM };
        let color = Color::new(gray.r * k, gray.g * k, gray.b * k, 1.0);
        let half = self.join_strip() / 2.0;
        let (x, rotation) = if free == Side::Right { (w - half, -FRAC_PI_2) } else { (half, FRAC_PI_2) };
        let text = format!("P{} HOLD HERE", free as usize + 1);
        r.text_centered(&text, &app.assets.font_text, 18.0 * s, x, h / 2.0, rotation, color);
    }

    /// Chi ha vinto, per la scritta sotto GAME OVER: in singolo nessuno; contro la CPU il
    /// giocatore è dal lato `solo`.
    fn winner(&self) -> Option<&'static str> {
        if self.game.players != 2 {
            return None;
        }
        let [left, right] = self.game.score;
        let me = self.game.score[self.solo as usize] >= self.game.score[self.solo.opponent() as usize];
        Some(match (!self.cpus.is_empty(), me, left >= right) {
            (true, true, _) => "you_win",
            (true, false, _) => "cpu_wins",
            (false, _, true) => "p1_wins",
            (false, _, false) => "p2_wins",
        })
    }

    /// Partita vinta da un giocatore (non dalla CPU) senza punti dell'avversario: PERFECT, scritto e
    /// detto, come il bonus PERFECT dei livelli della CHALLENGE.
    fn perfect(&self) -> bool {
        let [left, right] = self.game.score;
        matches!(self.winner(), Some("you_win" | "p1_wins" | "p2_wins")) && left.min(right) == 0 && left.max(right) > 0
    }

    /// Per la verifica automatica e il benchmark: niente conto alla rovescia.
    pub fn skip_countdown(&mut self) {
        self.countdown = 0.0;
    }

    /// Per la verifica automatica: imposta i punteggi mostrati.
    pub fn set_scores(&mut self, score: [u16; 2], best: u16) {
        self.game.score = score;
        self.game.best = best;
    }

    /// Per la verifica automatica: riserve piene, un SUPER armato e due capsule in volo.
    pub fn fill_next_demo(&mut self) {
        use paddws_core::{Capsule, SuperAnim};
        let p = self.game.params.clone();
        let Some(n) = &mut self.game.next else { return };
        n.players[0].reserve = [Some(Bonus::Smash), Some(Bonus::Teleport), Some(Bonus::Curve)];
        n.players[0].selected = 1;
        n.players[1].reserve = [Some(Bonus::Slow), Some(Bonus::Ghost), None];
        n.players[1].armed = Some(Bonus::Super);
        n.players[1].super_anim = SuperAnim::Spin;
        n.capsules[0] = Some(Capsule {
            x: p.width / 3,
            y: p.height / 3,
            vx: -p.capsule_speed,
            vy: 0,
            bonus: Bonus::Super,
        });
        n.capsules[1] = Some(Capsule {
            x: p.width * 2 / 3,
            y: p.height * 3 / 5,
            vx: p.capsule_speed,
            vy: 0,
            bonus: Bonus::Ghost,
        });
        self.game.score = [4, 6];
    }

    /// Per la verifica automatica: segni dei tipi di racchetta in azione (colpo del BLASTER in
    /// volo, muro del GUARDIAN con un settore già usato, TWIST che sale) e una capsula in volo.
    pub fn fill_kinds_demo(&mut self) {
        use paddws_core::{Capsule, Shot};
        let p = self.game.params.clone();
        let Some(n) = &mut self.game.next else { return };
        n.spawn_timer = u32::MAX;
        n.capsules[0] = Some(Capsule {
            x: p.width * 3 / 5,
            y: p.height * 4 / 5,
            vx: -p.capsule_speed,
            vy: 0,
            bonus: Bonus::Curve,
        });
        n.players[0].reserve = [Some(Bonus::Smash), None, None];
        for side in 0..2 {
            let pad = &mut self.game.paddles[side];
            pad.y = if side == 0 { p.height / 3 } else { p.height * 2 / 3 };
            let pl = &mut n.players[side];
            match pl.kind {
                Some(PaddleKind::Blaster) => {
                    let vx = if side == 0 {
                        p.blaster_shot_speed
                    } else {
                        -p.blaster_shot_speed
                    };
                    // due colpi in volo, uno nel caricatore che si ricarica
                    for (i, slot) in pl.shots.iter_mut().take(2).enumerate() {
                        let x = p.width * (4 + i as i32) / 10;
                        *slot = Some(Shot {
                            x: if side == 0 { x } else { p.width - x },
                            y: pad.y,
                            vx,
                        });
                    }
                    pl.ammo = 1;
                    pl.reload = p.blaster_reload_ticks / 2;
                }
                Some(PaddleKind::Twist) => pad.motion = pad.max_speed / 2,
                Some(PaddleKind::Guardian) => pl.barrier &= !(1 << 2),
                _ => {}
            }
        }
        self.game.score = [3, 4];
    }

    /// Per la verifica automatica: palla appena colpita dal giocatore sinistro con STEER.
    pub fn fill_steer_demo(&mut self) {
        let (w, h) = (self.game.params.width, self.game.params.height);
        let Some(n) = &mut self.game.next else { return };
        n.spawn_timer = u32::MAX;
        n.players[0].reserve = [Some(Bonus::Steer), Some(Bonus::Slow), None];
        n.steer = Some(paddws_core::Side::Left);
        self.game.serve_timer = 0;
        let b = &mut self.game.ball;
        b.x = w / 4;
        b.y = h / 3;
        b.vx = self.game.params.serve_unit * 4;
        b.vy = b.vx * 3 / 2;
        self.game.score = [5, 5];
    }

    /// Per la verifica automatica: mosse speciali accese, barra di P1 con una mossa pronta, tiro di
    /// STRAIGHT SHOT di P1 in volo con la sua scritta, STRAIGHT SHOT armato per P2.
    pub fn fill_super_demo(&mut self) {
        let p = self.game.params.clone();
        self.game.set_super_moves(true);
        let Some(n) = &mut self.game.next else { return };
        n.spawn_timer = u32::MAX;
        n.players[0].reserve = [Some(Bonus::Smash), Some(Bonus::Curve), None];
        n.players[1].reserve = [Some(Bonus::Slow), None, None];
        n.players[0].meter = p.super_cost + p.super_cost / 4;
        n.players[1].meter = p.super_cost / 4;
        n.players[1].straight = 1;
        n.special_flight = Some(Special::Straight);
        n.special_level = 2;
        self.game.serve_timer = 0;
        let b = &mut self.game.ball;
        b.x = p.width / 6;
        b.y = p.height * 2 / 5;
        b.vx = p.serve_unit * 2;
        b.vy = 0;
        b.boost = paddws_core::fixed::ONE * 2;
        self.game.paddles[0].y = b.y;
        self.game.score = [6, 5];
        if let Some(fx) = &mut self.fx {
            fx.show_special(0, Special::Straight, 2, true);
            // il giro delle schermate scatta dopo 30 frame (0,5 s): lì il colpo è a 0,1 s
            fx.show_kick(0, Special::Straight, 2, 0.1 - 0.5);
        }
    }

    /// Per la verifica automatica: bullet time di P1 scattato (la palla veloce arriva lontano dalla
    /// sua racchetta), capsule in volo rallentate, BULLET in arrivo verso P2 e scritta del bonus;
    /// con `armed` il BULLET è solo armato e la palla va verso P2.
    pub fn fill_bullet_demo(&mut self, armed: bool) {
        use paddws_core::Capsule;
        let p = self.game.params.clone();
        let Some(n) = &mut self.game.next else { return };
        n.spawn_timer = u32::MAX;
        n.players[0].reserve = [Some(Bonus::Smash), None, None];
        n.players[1].reserve = [Some(Bonus::Ghost), Some(Bonus::Curve), None];
        n.bullet = Some(Side::Left);
        // scattato da poco: la rampa d'entrata finisce nei frame che la verifica lascia passare
        n.bullet_on = !armed;
        n.bullet_timer = if armed { 0 } else { p.bullet_ramp_ticks };
        n.capsules[0] = Some(Capsule {
            x: p.width * 3 / 5,
            y: p.height / 4,
            vx: p.capsule_speed,
            vy: p.capsule_drift,
            bonus: Bonus::Bullet,
        });
        n.capsules[1] = Some(Capsule {
            x: p.width * 2 / 5,
            y: p.height * 3 / 5,
            vx: -p.capsule_speed,
            vy: 0,
            bonus: Bonus::Smash,
        });
        self.game.serve_timer = 0;
        let b = &mut self.game.ball;
        b.x = p.width / 2;
        b.y = p.height * 2 / 3;
        b.vx = -p.max_ball_speed_next;
        b.vy = -p.max_ball_speed_next / 3;
        if armed {
            // la palla si allontana da P1, lenta: non torna nella sua metà prima della schermata
            b.x = p.width / 3;
            b.vx = p.serve_unit * 2;
            b.vy = p.serve_unit / 2;
        }
        self.game.paddles[0].y = p.height / 4;
        self.game.paddles[1].y = p.height * 3 / 5;
        self.game.score = [7, 8];
        if let Some(fx) = &mut self.fx {
            fx.show_label("P1 BULLET!");
        }
    }

    /// Per la verifica automatica: CHALLENGE con punti arcade e uno scambio lungo in corso.
    pub fn fill_challenge_demo(&mut self) {
        if let Some((_, score)) = &mut self.challenge {
            score.total = 12_340;
            score.rally = 9;
        }
        self.game.score = [4, 2]; // sotto i punti del livello: la partita non finisce
    }

    /// Per la verifica automatica: mostra la schermata di fine partita.
    pub fn show_game_over(&mut self) {
        self.game_over = Some(1.0);
    }

    /// Per la verifica automatica: fine partita a `seconds` dall'inizio (dopo il lampo del punto).
    pub fn show_game_over_at(&mut self, app: &App, seconds: f64) {
        self.game_over = Some(app.attract.game_over_seconds() - FLASH_TIME - seconds);
    }

    /// Per la verifica automatica: P1 ha armato una MAX STRAIGHT SHOT e la palla gli arriva contro,
    /// a metà strada; la scritta del bonus di P2 si sta accendendo.
    pub fn fill_super_armed(&mut self) {
        let p = self.game.params.clone();
        self.game.set_super_moves(true);
        let Some(n) = &mut self.game.next else { return };
        n.spawn_timer = u32::MAX;
        n.players[0].straight = 2;
        n.players[1].meter = p.super_cost / 2;
        self.game.serve_timer = 0;
        let b = &mut self.game.ball;
        b.x = p.width * 3 / 5;
        b.y = p.height / 2;
        b.vx = -p.serve_unit * 2;
        b.vy = 0;
        self.game.score = [3, 4];
        if let Some(fx) = &mut self.fx {
            fx.show_special(0, Special::Straight, 2, false);
            fx.show_label_at("P2 SMASH!", 0.12 - 0.5);
        }
    }
}

// ------------------------------------------------------------------------ demo

/// Difficoltà della demo (NORMAL), come DEMO_DIFFICULTY del core MiSTer.
const DEMO_DIFFICULTY: u8 = 1;

/// Modalità della demo: quella scelta nel menu.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum DemoMode {
    Classic,
    Evo,
    Next,
    Challenge,
}

impl DemoMode {
    fn of_app(app: &App) -> Self {
        if app.challenge {
            DemoMode::Challenge
        } else if app.next {
            DemoMode::Next
        } else if app.evo {
            DemoMode::Evo
        } else {
            DemoMode::Classic
        }
    }

    /// Bitmap del nome (assets/attract).
    fn label(self) -> &'static str {
        match self {
            DemoMode::Classic => "mode_classic",
            DemoMode::Evo => "mode_evo",
            DemoMode::Next => "mode_next",
            DemoMode::Challenge => "mode_challenge",
        }
    }
}

/// Tre bonus diversi a caso, come la CPU nella scelta.
fn random_loadout(rng: &mut Rng) -> [Bonus; 3] {
    let mut chosen = Vec::with_capacity(3);
    while chosen.len() < 3 {
        let b = Bonus::PICKABLE[rng.below(Bonus::PICKABLE.len() as u32) as usize];
        if !chosen.contains(&b) {
            chosen.push(b);
        }
    }
    [chosen[0], chosen[1], chosen[2]]
}

fn random_kind(rng: &mut Rng) -> Option<PaddleKind> {
    Some(PaddleKind::ALL[rng.below(PaddleKind::COUNT as u32) as usize])
}

/// Demo dell'attract dopo la classifica: una partita CPU contro CPU per il tempo della demo, con le
/// scritte del core MiSTer; gettone e Start come nell'attract, alla fine si torna alle strisce.
pub struct Demo {
    play: Box<Play>,
    mode: DemoMode,
    frame: u32,
    acc: f64,
}

impl Demo {
    /// Demo della modalità scelta nel menu.
    pub fn new(app: &mut App) -> Self {
        let mode = DemoMode::of_app(app);
        Self::of(app, mode)
    }

    /// Demo di una modalità precisa (anche per la verifica automatica).
    pub fn of(app: &mut App, mode: DemoMode) -> Self {
        Self {
            play: Box::new(Play::demo(app, mode)),
            mode,
            frame: 0,
            acc: 0.0,
        }
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            app.quit = true;
            return None;
        }
        if let Some(scene) = coin_and_start(app) {
            return Some(scene);
        }
        self.play.update(app, dt);
        self.acc += dt.min(MAX_FRAME_TIME);
        while self.acc >= 1.0 / 60.0 {
            self.acc -= 1.0 / 60.0;
            self.frame += 1;
        }
        (self.frame >= app.attract.demo_frames()).then(|| Scene::Attract(Attract::new(&app.attract, false)))
    }

    pub fn draw(&self, app: &App) {
        self.play.draw(app);
        let next = self.mode >= DemoMode::Next;
        attract::draw_demo_overlay(&app.attract, &app.renderer, app.hud(), self.mode.label(), self.frame, next);
    }
}
