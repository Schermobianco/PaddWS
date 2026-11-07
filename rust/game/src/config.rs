//! Configurazione: stesso file `padd_config.json` e stesse chiavi della versione Python.
//! Le chiavi mancanti prendono il valore di default, quelle sconosciute vengono ignorate.
//! Nel browser lo stesso JSON sta nel `localStorage` (`platform::read_text`): le preferenze del
//! menu restano da una visita all'altra.

use std::fs;
use std::path::{Path, PathBuf};

use paddws_core::{NextTuning, PaddleTuning, Tuning};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::platform;

pub type Rgb = [u8; 3];

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Resolution {
    /// 0 = automatica: proporzioni del monitor (4:3, 16:9, ...) con l'altezza data
    pub width: u32,
    pub height: u32,
}

impl Default for Resolution {
    fn default() -> Self {
        Self { width: 0, height: 480 }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Game {
    pub title_bar: bool,
    /// limite di frame, usato solo con vsync disattivato
    pub fps: u32,
    pub vsync: bool,
    pub game_name: String,
    pub fullscreen: bool,
    /// bande nere invece di deformare quando le proporzioni non coincidono
    pub keep_aspect: bool,
    pub serve_delay: f64,
    /// partite senza monete (sul PC); con false servono crediti: tasto 5, poi Start
    pub free_play: bool,
    /// in due vince chi arriva per primo a questi punti
    pub points_to_win: u16,
    /// palle a disposizione in singolo
    pub lives: u8,
    /// auto-test all'accensione nella sequenza attract
    pub self_test: bool,
    /// 0 facile, 1 normale, 2 difficile, 3 esperto: accelerazione e velocità massima della palla
    pub difficulty: u8,
    /// suoni e musica della sequenza attract, e musica del menu e delle scelte (gettone e Start si
    /// sentono sempre)
    pub attract_sound: bool,
    /// volume della musica del SID in percento, da 0 (nessuna musica) a 100 a passi di
    /// `VOLUME_STEP` (menu MUSIC VOLUME)
    pub music_volume: u8,
    /// volume degli effetti e delle voci in percento, come `music_volume` (menu EFFECTS VOLUME)
    pub effects_volume: u8,
    /// luminosità del bianco in percento: tutta l'immagine scala in proporzione
    pub white_level: u8,
    /// spessore della pallina e delle racchette in percento (menu ZOOM), per gli schermi piccoli:
    /// cambia anche gli urti, l'altezza delle racchette e il campo restano gli stessi
    pub zoom: u16,
    /// punteggi dritti in alto, per un cabinato o un monitor normale, invece che rivolti ai
    /// giocatori seduti ai lati di un tavolo (come l'opzione Scores del MiSTer)
    pub scores_upright: bool,
    /// GAME TYPE dell'ultima scelta nel menu: "classic", "evo" o "next" (di default NEXT)
    pub game_type: String,
    /// PLAYERS dell'ultima scelta nel menu: "two", "cpu", "challenge" o "one" (di default
    /// CHALLENGE)
    pub players: String,
}

impl Default for Game {
    fn default() -> Self {
        Self {
            title_bar: true,
            fps: 60,
            vsync: true,
            game_name: "PADD WS".into(),
            fullscreen: false,
            keep_aspect: true,
            serve_delay: 0.5,
            free_play: true,
            points_to_win: 11,
            lives: 3,
            self_test: true,
            difficulty: 1,
            attract_sound: true,
            music_volume: 100,
            effects_volume: 100,
            white_level: 100,
            zoom: 100,
            scores_upright: true,
            game_type: "next".into(),
            players: "challenge".into(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Ball {
    pub radius: f64,
    pub radius_boost: f64,
    pub radius_boost_fwd: f64,
}

impl Default for Ball {
    fn default() -> Self {
        Self {
            radius: 5.0,
            radius_boost: 8.0,
            radius_boost_fwd: 6.0,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Paddle {
    pub width: f64,
    pub height: f64,
    pub start_pos: f64,
    pub forward_pos: f64,
    pub base_speed: f64,
    pub max_speed: f64,
    pub acceleration: f64,
    pub fast_acceleration: f64,
    pub deceleration: f64,
    /// ms
    pub double_click_time: f64,
}

impl Default for Paddle {
    fn default() -> Self {
        Self {
            width: 10.0,
            height: 80.0,
            start_pos: 50.0,
            forward_pos: 200.0,
            base_speed: 2.0,
            max_speed: 15.0,
            acceleration: 0.3,
            fast_acceleration: 1.0,
            deceleration: 2.0,
            double_click_time: 300.0,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Boost {
    pub multiplier: f64,
    pub area_ratio: f64,
    pub forward_multiplier: f64,
    pub enable_area_decay: bool,
    pub decay_rate: f64,
    pub min_area_ratio: f64,
}

impl Default for Boost {
    fn default() -> Self {
        Self {
            multiplier: 2.0,
            area_ratio: 4.0,
            forward_multiplier: 1.5,
            enable_area_decay: true,
            decay_rate: 0.8,
            min_area_ratio: 20.0,
        }
    }
}

/// Encoder con pulsante del cabinato Raspberry Pi, numeri GPIO (BCM), come nella versione Python;
/// in più i pulsanti SELEZIONA e USA del bonus di NEXT (un numero negativo = pulsante assente).
/// Tipo di encoder: impulsi per giro (20 = KY-040 a scatti; 360 o 600 = ottici, senza scatti),
/// giri di manopola per attraversare il campo e antirimbalzo (0 per gli ottici).
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Encoder {
    pub enabled: bool,
    pub e1_clock_pin: i32,
    pub e1_data_pin: i32,
    pub e1_switch_pin: i32,
    pub e2_clock_pin: i32,
    pub e2_data_pin: i32,
    pub e2_switch_pin: i32,
    pub e1_select_pin: i32,
    pub e1_activate_pin: i32,
    pub e2_select_pin: i32,
    pub e2_activate_pin: i32,
    pub pulses_per_revolution: u32,
    pub turns_per_travel: f64,
    pub debounce_us: u32,
}

impl Default for Encoder {
    fn default() -> Self {
        Self {
            enabled: false,
            e1_clock_pin: 5,
            e1_data_pin: 6,
            e1_switch_pin: 13,
            e2_clock_pin: 16,
            e2_data_pin: 20,
            e2_switch_pin: 21,
            e1_select_pin: 19,
            e1_activate_pin: 26,
            e2_select_pin: 12,
            e2_activate_pin: 25,
            pulses_per_revolution: 20,
            turns_per_travel: 1.0,
            debounce_us: 500,
        }
    }
}

/// Il mouse come spinner del giocatore 1 (PC e browser): il movimento verticale muove la racchetta
/// come la manopola del cabinato, sinistro = click (scatto), destro = SELEZIONA, centrale = USA.
/// Spento di default; si cambia anche dal menu (MOUSE SPINNER).
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Mouse {
    pub spinner: bool,
    /// pixel di movimento del mouse per portare la racchetta da un bordo all'altro
    pub travel_pixels: f64,
}

impl Default for Mouse {
    fn default() -> Self {
        Self {
            spinner: false,
            travel_pixels: 1000.0,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Colors {
    pub white: Rgb,
    pub black: Rgb,
    pub lgray: Rgb,
    /// colore di accento, usato con parsimonia: la voce scelta del menu e i segni di NEXT
    /// (default: il giallo dell'attract)
    pub accent: Rgb,
}

impl Default for Colors {
    fn default() -> Self {
        Self {
            white: [255, 255, 255],
            black: [0, 0, 0],
            lgray: [180, 180, 180],
            accent: [255, 210, 37],
        }
    }
}

/// Passo dei volumi del menu, in percento.
pub const VOLUME_STEP: u8 = 10;

/// Guadagno di un volume in percento (0-100): il quadrato, così i passi del menu si sentono più
/// uguali tra loro di quanto farebbero con un guadagno lineare (50% = un quarto, circa -12 dB).
pub fn volume_gain(percent: u8) -> f32 {
    let v = f32::from(percent.min(100)) / 100.0;
    v * v
}

/// Righe emulate del filtro CRT di prima (`resolution_scale` 1.0: 1440 righe, con il moiré): se
/// nel file nessuno l'ha cambiata, passa al default nuovo.
const OLD_RESOLUTION_SCALE: f32 = 1.0;

/// Bombatura dello schermo CRT (orizzontale e verticale). Le bombature di prima (`OLD_WARPS`), se
/// nel file nessuno le ha cambiate, passano a questa: il doppio della prima toglieva spazio agli
/// angoli, dove stanno le riserve dei bonus; poi un quarto in meno.
const WARP: (f32, f32) = (0.01172, 0.015625);
const OLD_WARPS: [(f32, f32); 2] = [(0.03125, 0.04167), (0.015625, 0.020833)];

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Crt {
    pub enabled: bool,
    pub resolution_scale: f32,
    pub hard_scan: f32,
    pub hard_pix: f32,
    pub warp_x: f32,
    pub warp_y: f32,
    pub mask_dark: f32,
    pub mask_light: f32,
}

impl Default for Crt {
    fn default() -> Self {
        Self {
            enabled: false,
            resolution_scale: 2.5,
            hard_scan: -8.0,
            hard_pix: -3.0,
            warp_x: WARP.0,
            warp_y: WARP.1,
            mask_dark: 0.5,
            mask_light: 1.5,
        }
    }
}

/// Modalità NEXT: palla, capsule e bonus, con le stesse unità del resto del file (800x480,
/// tick a 60 Hz). I default sono quelli del core MiSTer.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Next {
    pub ball_speedup: [f64; 4],
    pub ball_max_speed: [f64; 4],
    pub capsule_size: f64,
    pub capsule_speed: f64,
    pub capsule_drift: f64,
    pub hud_band: f64,
    pub spawn_seconds: f64,
    pub spawn_jitter_seconds: f64,
    pub super_odds: u32,
    /// BULLET: rarità, rampa e velocità (vedi `NextTuning` nel core)
    pub bullet_odds: u32,
    pub bullet_ramp_seconds: f64,
    pub bullet_speed: f64,
    pub bullet_ramp_speed: f64,
    pub cooldown_seconds: f64,
    pub smash_multiplier: f64,
    pub super_multiplier: f64,
    pub slow_multiplier: f64,
    pub slow_seconds: f64,
    pub curve_accel: f64,
    pub steer_accel: f64,
    pub hitstop_seconds: f64,
    /// mosse speciali: barra, guadagni, costo, salto e finestra di RISING STRIKE, tiro di
    /// STRAIGHT SHOT (vedi `NextTuning` nel core)
    pub super_meter_max: u32,
    pub super_gain_hit: u32,
    pub super_gain_dash: u32,
    pub super_gain_conceded: u32,
    pub super_cost: u32,
    pub super_straight_multiplier: f64,
    pub paddles: NextPaddles,
}

/// Tipi di racchetta di NEXT (vedi `PaddleTuning` nel core).
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct NextPaddles {
    pub arcade_cooldown_seconds: f64,
    pub arcade_spawn_seconds: f64,
    pub arcade_height: f64,
    pub arcade_share: u32,
    pub titan_height: f64,
    pub titan_speed: f64,
    pub hammer_multiplier: f64,
    pub hammer_speed: f64,
    pub twist_transfer: f64,
    pub blaster_height: f64,
    pub blaster_speed: f64,
    pub blaster_shots: u32,
    pub blaster_gap_seconds: f64,
    pub blaster_reload_seconds: f64,
    pub blaster_shot_speed: f64,
    pub blaster_band: f64,
    pub blaster_dash: bool,
    pub rush_height: f64,
    pub rush_dash: f64,
    pub rush_forward_speed: f64,
    pub rush_ball_multiplier: f64,
    pub guardian_height: f64,
    pub guardian_barrier_x: f64,
    pub encoder_max_speed: f64,
}

impl Default for NextPaddles {
    fn default() -> Self {
        let t = PaddleTuning::default();
        Self {
            arcade_cooldown_seconds: t.arcade_cooldown_seconds,
            arcade_spawn_seconds: t.arcade_spawn_seconds,
            arcade_height: t.arcade_height,
            arcade_share: t.arcade_share,
            titan_height: t.titan_height,
            titan_speed: t.titan_speed,
            hammer_multiplier: t.hammer_multiplier,
            hammer_speed: t.hammer_speed,
            twist_transfer: t.twist_transfer,
            blaster_height: t.blaster_height,
            blaster_speed: t.blaster_speed,
            blaster_shots: t.blaster_shots,
            blaster_gap_seconds: t.blaster_gap_seconds,
            blaster_reload_seconds: t.blaster_reload_seconds,
            blaster_shot_speed: t.blaster_shot_speed,
            blaster_band: t.blaster_band,
            blaster_dash: t.blaster_dash,
            rush_height: t.rush_height,
            rush_dash: t.rush_dash,
            rush_forward_speed: t.rush_forward_speed,
            rush_ball_multiplier: t.rush_ball_multiplier,
            guardian_height: t.guardian_height,
            guardian_barrier_x: t.guardian_barrier_x,
            encoder_max_speed: t.encoder_max_speed,
        }
    }
}

impl NextPaddles {
    fn tuning(&self) -> PaddleTuning {
        PaddleTuning {
            arcade_cooldown_seconds: self.arcade_cooldown_seconds,
            arcade_spawn_seconds: self.arcade_spawn_seconds,
            arcade_height: self.arcade_height,
            arcade_share: self.arcade_share,
            titan_height: self.titan_height,
            titan_speed: self.titan_speed,
            hammer_multiplier: self.hammer_multiplier,
            hammer_speed: self.hammer_speed,
            twist_transfer: self.twist_transfer,
            blaster_height: self.blaster_height,
            blaster_speed: self.blaster_speed,
            blaster_shots: self.blaster_shots,
            blaster_gap_seconds: self.blaster_gap_seconds,
            blaster_reload_seconds: self.blaster_reload_seconds,
            blaster_shot_speed: self.blaster_shot_speed,
            blaster_band: self.blaster_band,
            blaster_dash: self.blaster_dash,
            rush_height: self.rush_height,
            rush_dash: self.rush_dash,
            rush_forward_speed: self.rush_forward_speed,
            rush_ball_multiplier: self.rush_ball_multiplier,
            guardian_height: self.guardian_height,
            guardian_barrier_x: self.guardian_barrier_x,
            encoder_max_speed: self.encoder_max_speed,
        }
    }
}

impl Default for Next {
    fn default() -> Self {
        let t = NextTuning::default();
        Self {
            ball_speedup: t.ball_speedup,
            ball_max_speed: t.ball_max_speed,
            capsule_size: t.capsule_size,
            capsule_speed: t.capsule_speed,
            capsule_drift: t.capsule_drift,
            hud_band: t.hud_band,
            spawn_seconds: t.spawn_seconds,
            spawn_jitter_seconds: t.spawn_jitter_seconds,
            super_odds: t.super_odds,
            bullet_odds: t.bullet_odds,
            bullet_ramp_seconds: t.bullet_ramp_seconds,
            bullet_speed: t.bullet_speed,
            bullet_ramp_speed: t.bullet_ramp_speed,
            cooldown_seconds: t.cooldown_seconds,
            smash_multiplier: t.smash_multiplier,
            super_multiplier: t.super_multiplier,
            slow_multiplier: t.slow_multiplier,
            slow_seconds: t.slow_seconds,
            curve_accel: t.curve_accel,
            steer_accel: t.steer_accel,
            hitstop_seconds: t.hitstop_seconds,
            super_meter_max: t.super_meter_max,
            super_gain_hit: t.super_gain_hit,
            super_gain_dash: t.super_gain_dash,
            super_gain_conceded: t.super_gain_conceded,
            super_cost: t.super_cost,
            super_straight_multiplier: t.super_straight_multiplier,
            paddles: NextPaddles::default(),
        }
    }
}

impl Next {
    fn tuning(&self) -> NextTuning {
        NextTuning {
            ball_speedup: self.ball_speedup,
            ball_max_speed: self.ball_max_speed,
            capsule_size: self.capsule_size,
            capsule_speed: self.capsule_speed,
            capsule_drift: self.capsule_drift,
            hud_band: self.hud_band,
            spawn_seconds: self.spawn_seconds,
            spawn_jitter_seconds: self.spawn_jitter_seconds,
            super_odds: self.super_odds,
            bullet_odds: self.bullet_odds,
            bullet_ramp_seconds: self.bullet_ramp_seconds,
            bullet_speed: self.bullet_speed,
            bullet_ramp_speed: self.bullet_ramp_speed,
            cooldown_seconds: self.cooldown_seconds,
            smash_multiplier: self.smash_multiplier,
            super_multiplier: self.super_multiplier,
            slow_multiplier: self.slow_multiplier,
            slow_seconds: self.slow_seconds,
            curve_accel: self.curve_accel,
            steer_accel: self.steer_accel,
            hitstop_seconds: self.hitstop_seconds,
            super_meter_max: self.super_meter_max,
            super_gain_hit: self.super_gain_hit,
            super_gain_dash: self.super_gain_dash,
            super_gain_conceded: self.super_gain_conceded,
            super_cost: self.super_cost,
            super_straight_multiplier: self.super_straight_multiplier,
            paddles: self.paddles.tuning(),
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub resolution: Resolution,
    pub game: Game,
    pub ball: Ball,
    pub paddle: Paddle,
    pub boost: Boost,
    pub encoder: Encoder,
    pub mouse: Mouse,
    pub colors: Colors,
    pub crt_effects: Crt,
    pub next: Next,
}

impl Config {
    /// Parametri per il core; la larghezza deve essere già risolta.
    pub fn tuning(&self) -> Tuning {
        let (b, p, bo) = (&self.ball, &self.paddle, &self.boost);
        let zoom = self.zoom();
        Tuning {
            width: self.resolution.width,
            height: self.resolution.height,
            ball_radius: b.radius * zoom,
            ball_radius_boost: b.radius_boost * zoom,
            ball_radius_boost_fwd: b.radius_boost_fwd * zoom,
            difficulty: self.game.difficulty,
            pad_width: p.width * zoom,
            pad_height: p.height,
            pad_start_pos: p.start_pos,
            pad_forward_pos: p.forward_pos,
            pad_max_speed: p.max_speed,
            pad_acceleration: p.acceleration,
            pad_fast_acceleration: p.fast_acceleration,
            pad_deceleration: p.deceleration,
            boost_multiplier: bo.multiplier,
            boost_area_ratio: bo.area_ratio,
            boost_forward_multiplier: bo.forward_multiplier,
            boost_decay: bo.enable_area_decay,
            boost_decay_rate: bo.decay_rate,
            boost_min_area_ratio: bo.min_area_ratio,
            serve_delay: self.game.serve_delay,
            tick_hz: paddws_core::TICK_HZ,
            next: self.next.tuning(),
        }
    }

    /// Fattore di `Game::zoom`, tenuto fra 50% e 300% (un valore assurdo nel file non rompe il
    /// campo).
    pub fn zoom(&self) -> f64 {
        self.game.zoom.clamp(50, 300) as f64 / 100.0
    }
}

/// Larghezza del campo con le stesse proporzioni dello schermo: niente bande nere.
pub fn auto_width(height: u32, screen_w: u32, screen_h: u32) -> u32 {
    ((height as f64 * screen_w as f64 / screen_h as f64).round() as u32).max(1)
}

/// Fascia per le dita lasciata ai lati del campo sui telefoni, per lato, in frazione della tela.
const WEB_FINGER_BAND: f32 = 0.07;
/// Lato corto della tela (in punti CSS) sotto il quale si è su un telefono.
const WEB_PHONE_SHORT_SIDE: f32 = 500.0;

/// Larghezza del campo nel browser, dalla tela di `screen_w` x `screen_h` punti presa in
/// orizzontale (anche se il telefono è ancora in verticale): le sue proporzioni, tra il 4:3 e il
/// 2,2:1. Sui telefoni restano ai lati due fasce nere per le dita (`WEB_FINGER_BAND`).
pub fn web_field_width(height: u32, screen_w: f32, screen_h: f32) -> u32 {
    let (long, short) = (screen_w.max(screen_h), screen_w.min(screen_h).max(1.0));
    let band = if short < WEB_PHONE_SHORT_SIDE { WEB_FINGER_BAND } else { 0.0 };
    let aspect = (long * (1.0 - 2.0 * band) / short).clamp(4.0 / 3.0, 2.2);
    (height as f32 * aspect).round() as u32
}

/// Dove cercare il file se non è indicato: accanto all'eseguibile, nella cartella
/// corrente e (per `cargo run` dentro `rust/`) nella cartella superiore.
pub fn default_path() -> PathBuf {
    let mut candidates = Vec::new();
    if let Some(dir) = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
    {
        candidates.push(dir.join("padd_config.json"));
    }
    candidates.push(PathBuf::from("padd_config.json"));
    candidates.push(PathBuf::from("../padd_config.json"));
    for path in &candidates {
        migrate_old_name(path, "pong_config.json");
    }
    candidates
        .iter()
        .find(|p| p.exists())
        .cloned()
        .unwrap_or_else(|| candidates[0].clone())
}

/// Prima del cambio di nome il file si chiamava `old_name`: se c'è ancora solo quello, lo rinomina.
pub fn migrate_old_name(path: &Path, old_name: &str) {
    let old = path.with_file_name(old_name);
    if !path.exists() && old.exists() {
        let _ = fs::rename(&old, path);
    }
}

/// Chiavi della musica di prima: `game.music` (MUSIC: ON/OFF, fino alla 4.0.0-beta.19) e, prima
/// della 4.0.0-beta.16, `game.sid_sound` (false = i campioni originali, senza musica) e
/// `game.match_music` (i temi della CHALLENGE). In un file che non ha ancora `game.music_volume`
/// la musica resta spenta (volume 0) se una di loro la spegneva.
const OLD_MUSIC_KEYS: [&str; 3] = ["music", "sid_sound", "match_music"];

/// Chiavi di `next` tolte dal file: le mosse speciali sono sempre accese (fino alla
/// 4.0.0-beta.19 c'era l'opzione SUPER MOVES).
const OLD_NEXT_KEYS: [&str; 1] = ["super_moves"];

/// Il file ha ancora solo le chiavi vecchie della musica e una di loro la spegneva.
fn old_music_off(data: &Value) -> bool {
    let Some(game) = data.get("game").and_then(Value::as_object) else {
        return false;
    };
    !game.contains_key("music_volume")
        && OLD_MUSIC_KEYS.iter().any(|k| game.get(*k).and_then(Value::as_bool) == Some(false))
}

/// Carica il file (nel browser dal `localStorage`); se manca lo crea con i default, non
/// sovrascrive mai un file rovinato.
pub fn load(path: &Path) -> Config {
    match platform::read_text(path) {
        Some(text) => match serde_json::from_str::<Config>(&text) {
            Ok(mut cfg) => {
                // una bombatura di prima, mai cambiata a mano, passa alla nuova
                let crt = &mut cfg.crt_effects;
                if OLD_WARPS
                    .iter()
                    .any(|old| (crt.warp_x - old.0).abs() < 1e-5 && (crt.warp_y - old.1).abs() < 1e-5)
                {
                    (crt.warp_x, crt.warp_y) = WARP;
                }
                // lo stesso per le righe emulate
                if (crt.resolution_scale - OLD_RESOLUTION_SCALE).abs() < 1e-5 {
                    crt.resolution_scale = Crt::default().resolution_scale;
                }
                if serde_json::from_str::<Value>(&text).ok().as_ref().is_some_and(old_music_off) {
                    cfg.game.music_volume = 0;
                }
                let g = &mut cfg.game;
                (g.music_volume, g.effects_volume) = (g.music_volume.min(100), g.effects_volume.min(100));
                add_missing(path, &text, &cfg);
                cfg
            }
            Err(err) => {
                eprintln!(
                    "Config {} is not valid JSON ({err}); using defaults without overwriting",
                    path.display()
                );
                Config::default()
            }
        },
        None => {
            let cfg = Config::default();
            if let Ok(value) = serde_json::to_value(&cfg) {
                write_json(path, &value);
            }
            cfg
        }
    }
}

/// Aggiunge al file le voci nuove che non ha ancora (le sezioni `next` e `mouse`, le voci nuove di
/// `next`, `colors.accent` e i volumi di `game`), con i valori letti (i default per quelle che
/// mancano), e toglie le chiavi di prima (`OLD_MUSIC_KEYS`, `OLD_NEXT_KEYS`), lasciando intatto il
/// resto: chi aggiorna il gioco trova i nuovi parametri da regolare.
fn add_missing(path: &Path, text: &str, cfg: &Config) {
    let Ok(mut data) = serde_json::from_str::<Value>(text) else {
        return;
    };
    let Some(obj) = data.as_object_mut() else { return };
    let mut changed = false;
    if let Ok(Value::Object(next)) = serde_json::to_value(&cfg.next) {
        match obj.get_mut("next") {
            // voci nuove della sezione in fondo, nell'ordine della struttura
            Some(Value::Object(section)) => {
                for key in OLD_NEXT_KEYS {
                    changed |= section.shift_remove(key).is_some();
                }
                for (key, v) in next {
                    if !section.contains_key(&key) {
                        section.insert(key, v);
                        changed = true;
                    }
                }
            }
            Some(_) => {}
            None => {
                obj.insert("next".into(), Value::Object(next));
                changed = true;
            }
        }
    }
    // la sezione del mouse, con lo spinner spento
    if !obj.contains_key("mouse")
        && let Ok(mouse) = serde_json::to_value(&cfg.mouse)
    {
        obj.insert("mouse".into(), mouse);
        changed = true;
    }
    let colors = obj.entry("colors").or_insert_with(|| Value::Object(Default::default()));
    if let Some(colors) = colors.as_object_mut()
        && !colors.contains_key("accent")
    {
        colors.insert("accent".into(), cfg.colors.accent.to_vec().into());
        changed = true;
    }
    // i volumi della musica e degli effetti al posto di MUSIC (e prima di SOUND e della musica in
    // partita)
    let game = obj.entry("game").or_insert_with(|| Value::Object(Default::default()));
    if let Some(game) = game.as_object_mut() {
        for key in OLD_MUSIC_KEYS {
            changed |= game.shift_remove(key).is_some();
        }
        for (key, v) in [("music_volume", cfg.game.music_volume), ("effects_volume", cfg.game.effects_volume)] {
            if !game.contains_key(key) {
                game.insert(key.into(), v.into());
                changed = true;
            }
        }
    }
    // la bombatura e le righe emulate nuove al posto di quelle vecchie (vedi `load`)
    if let Some(Value::Object(crt)) = obj.get_mut("crt_effects") {
        for (key, v) in [
            ("warp_x", cfg.crt_effects.warp_x),
            ("warp_y", cfg.crt_effects.warp_y),
            ("resolution_scale", cfg.crt_effects.resolution_scale),
        ] {
            let old = crt.get(key).and_then(Value::as_f64);
            if old.is_some_and(|old| (old - v as f64).abs() > 1e-5) {
                crt.insert(key.into(), (v as f64).into());
                changed = true;
            }
        }
    }
    if changed {
        write_json(path, &data);
    }
}

/// Salva solo le impostazioni modificabili durante il gioco, lasciando intatto il resto del file
/// (nel browser lo stesso JSON sta nel `localStorage`).
pub fn save_preferences(path: &Path, cfg: &Config) {
    let mut data: Value = platform::read_text(path)
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| serde_json::to_value(cfg).unwrap_or(Value::Null));
    if !data.is_object() {
        return;
    }
    set(&mut data, "game", "fullscreen", cfg.game.fullscreen);
    set(&mut data, "game", "difficulty", cfg.game.difficulty);
    set(&mut data, "game", "attract_sound", cfg.game.attract_sound);
    set(&mut data, "game", "music_volume", cfg.game.music_volume);
    set(&mut data, "game", "effects_volume", cfg.game.effects_volume);
    set(&mut data, "game", "white_level", cfg.game.white_level);
    set(&mut data, "game", "zoom", cfg.game.zoom);
    set(&mut data, "game", "scores_upright", cfg.game.scores_upright);
    set(&mut data, "game", "game_type", cfg.game.game_type.as_str());
    set(&mut data, "game", "players", cfg.game.players.as_str());
    set(&mut data, "crt_effects", "enabled", cfg.crt_effects.enabled);
    set(&mut data, "mouse", "spinner", cfg.mouse.spinner);
    write_json(path, &data);
}

fn set(data: &mut Value, section: &str, key: &str, value: impl Into<Value>) {
    let obj = data.as_object_mut().expect("oggetto JSON");
    let entry = obj.entry(section).or_insert_with(|| Value::Object(Default::default()));
    if let Some(section) = entry.as_object_mut() {
        section.insert(key.into(), value.into());
    }
}

fn write_json(path: &Path, value: &Value) {
    // stesso formato della versione Python (indentazione di 4 spazi)
    let mut out = Vec::new();
    let formatter = serde_json::ser::PrettyFormatter::with_indent(b"    ");
    let mut ser = serde_json::Serializer::with_formatter(&mut out, formatter);
    if value.serialize(&mut ser).is_ok() {
        out.push(b'\n');
        if let Err(err) = platform::write_text(path, &out) {
            eprintln!("Cannot write config {}: {err}", path.display());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_width_follows_screen_aspect() {
        for ((w, h), expected) in [
            ((1024, 768), 640),
            ((1920, 1080), 853),
            ((800, 480), 800),
            ((1280, 1024), 600),
        ] {
            assert_eq!(auto_width(480, w, h), expected);
        }
    }

    #[test]
    fn web_field_leaves_room_for_fingers_on_phones() {
        for ((w, h), expected) in [
            // iPhone in Safari con le barre: si arriva al 2,2:1 e le fasce restano larghe
            ((734.0, 268.0), 1056),
            // iPhone da Home (schermo intero): proporzioni della tela meno le fasce
            ((740.0, 372.0), 821),
            // lo stesso telefono ancora in verticale
            ((372.0, 740.0), 821),
            // tablet e computer: tutta la tela
            ((1180.0, 820.0), 691),
            ((1920.0, 950.0), 970),
            // mai sotto il 4:3
            ((500.0, 480.0), 640),
        ] {
            assert_eq!(web_field_width(480, w, h), expected, "tela {w}x{h}");
        }
    }

    #[test]
    fn reads_the_python_config_format() {
        let cfg: Config =
            serde_json::from_str(r#"{"resolution": {"width": 0}, "ball": {"radius": 7}, "extra": 1}"#).unwrap();
        assert_eq!(cfg.resolution.width, 0);
        assert_eq!(cfg.resolution.height, 480);
        assert_eq!(cfg.ball.radius, 7.0);
        assert_eq!(cfg.paddle.height, 80.0);
    }

    #[test]
    fn preferences_keep_the_rest_of_the_file() {
        let path = std::env::temp_dir().join(format!("paddws_prefs_{}.json", std::process::id()));
        fs::write(&path, r#"{"ball": {"radius": 9}, "game": {"fullscreen": false}}"#).unwrap();
        let mut cfg = load(&path);
        assert_eq!((cfg.game.music_volume, cfg.game.effects_volume), (100, 100));
        cfg.game.fullscreen = true;
        cfg.game.music_volume = 30;
        cfg.game.effects_volume = 0;
        cfg.crt_effects.enabled = true;
        save_preferences(&path, &cfg);
        let data: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(data["ball"]["radius"], 9);
        assert_eq!(data["game"]["fullscreen"], true);
        assert_eq!(data["crt_effects"]["enabled"], true);
        assert_eq!(data["game"]["music_volume"], 30);
        assert_eq!(data["game"]["effects_volume"], 0);
        let cfg = load(&path);
        assert_eq!((cfg.game.music_volume, cfg.game.effects_volume), (30, 0));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn the_old_sound_keys_become_the_music_volume() {
        let path = std::env::temp_dir().join(format!("paddws_music_{}.json", std::process::id()));
        // MUSIC spenta, musica in partita spenta o i campioni originali (senza musica): volume 0
        for (old, volume) in [
            (r#""music": false"#, 0),
            (r#""music": true"#, 100),
            (r#""sid_sound": true, "match_music": false"#, 0),
            (r#""sid_sound": false, "match_music": true"#, 0),
            (r#""sid_sound": true, "match_music": true"#, 100),
            (r#""match_music": true"#, 100),
        ] {
            fs::write(&path, format!(r#"{{"game": {{"fullscreen": true, {old}, "difficulty": 2}}}}"#)).unwrap();
            assert_eq!(load(&path).game.music_volume, volume, "{old}");
            let text = fs::read_to_string(&path).unwrap();
            let data: Value = serde_json::from_str(&text).unwrap();
            // le chiavi vecchie spariscono, le altre restano nel loro ordine
            assert_eq!(data["game"]["music_volume"], volume);
            assert_eq!(data["game"]["effects_volume"], 100);
            for key in OLD_MUSIC_KEYS {
                assert!(data["game"].get(key).is_none(), "{key}");
            }
            assert!(text.find("fullscreen").unwrap() < text.find("difficulty").unwrap());
            // da qui in poi vale la chiave nuova
            assert_eq!(load(&path).game.music_volume, volume);
        }
        // un file senza la sezione del gioco prende i volumi pieni
        fs::write(&path, r#"{"ball": {"radius": 9}}"#).unwrap();
        assert_eq!(load(&path).game.music_volume, 100);
        let data: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(data["game"]["music_volume"], 100);
        // un volume oltre il 100% si ferma a 100
        fs::write(&path, r#"{"game": {"music_volume": 250, "effects_volume": 120}}"#).unwrap();
        let cfg = load(&path);
        assert_eq!((cfg.game.music_volume, cfg.game.effects_volume), (100, 100));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn volumes_follow_a_square_curve() {
        assert_eq!(volume_gain(0), 0.0);
        assert_eq!(volume_gain(100), 1.0);
        assert!((volume_gain(50) - 0.25).abs() < 1e-6);
        assert_eq!(volume_gain(200), 1.0);
        assert!((0..100).step_by(VOLUME_STEP as usize).all(|v| volume_gain(v) < volume_gain(v + VOLUME_STEP)));
    }

    #[test]
    fn the_old_crt_rows_become_the_new_default() {
        let path = std::env::temp_dir().join(format!("paddws_crt_{}.json", std::process::id()));
        fs::write(&path, r#"{"crt_effects": {"enabled": true, "resolution_scale": 1.0}}"#).unwrap();
        assert_eq!(load(&path).crt_effects.resolution_scale, 2.5);
        let data: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(data["crt_effects"]["resolution_scale"], 2.5);
        // un valore scelto a mano resta
        fs::write(&path, r#"{"crt_effects": {"resolution_scale": 6.0}}"#).unwrap();
        assert_eq!(load(&path).crt_effects.resolution_scale, 6.0);
        assert_eq!(Config::default().crt_effects.resolution_scale, 2.5);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn next_section_is_added_and_read() {
        let path = std::env::temp_dir().join(format!("paddws_next_{}.json", std::process::id()));
        fs::write(&path, r#"{"paddle": {"width": 12}, "ball": {"radius": 9}}"#).unwrap();
        load(&path);
        let text = fs::read_to_string(&path).unwrap();
        // le voci nuove vanno in fondo, il resto resta nell'ordine del file
        assert!(text.find("paddle").unwrap() < text.find("ball").unwrap());
        assert!(text.find("ball").unwrap() < text.find("next").unwrap());
        let data: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(data["ball"]["radius"], 9);
        assert_eq!(data["next"]["super_odds"], 8);
        assert_eq!(data["next"]["bullet_odds"], 16);
        assert_eq!(data["colors"]["accent"][0], 255);
        fs::write(
            &path,
            r#"{"next": {"smash_multiplier": 3.0, "ball_max_speed": [5, 6, 7, 8]}}"#,
        )
        .unwrap();
        let t = load(&path).tuning();
        assert_eq!(t.next.smash_multiplier, 3.0);
        assert_eq!(t.next.ball_max_speed[1], 6.0);
        assert_eq!(t.next.slow_multiplier, NextTuning::default().slow_multiplier);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn zoom_thickens_ball_and_paddles_only() {
        let base = Config::default().tuning();
        let mut cfg = Config::default();
        cfg.game.zoom = 150;
        let t = cfg.tuning();
        assert_eq!(t.ball_radius, base.ball_radius * 1.5);
        assert_eq!(t.ball_radius_boost, base.ball_radius_boost * 1.5);
        assert_eq!(t.ball_radius_boost_fwd, base.ball_radius_boost_fwd * 1.5);
        assert_eq!(t.pad_width, base.pad_width * 1.5);
        assert_eq!(t.pad_height, base.pad_height);
        assert_eq!(t.pad_max_speed, base.pad_max_speed);
        // un valore assurdo nel file resta nei limiti
        cfg.game.zoom = 5000;
        assert_eq!(cfg.tuning().pad_width, base.pad_width * 3.0);
    }

    #[test]
    fn the_super_moves_option_leaves_old_files() {
        let path = std::env::temp_dir().join(format!("paddws_super_{}.json", std::process::id()));
        // file di una versione precedente: l'opzione delle mosse speciali, senza i loro parametri
        fs::write(&path, r#"{"next": {"smash_multiplier": 3.0, "super_moves": false, "super_cost": 16}}"#).unwrap();
        let cfg = load(&path);
        assert_eq!(cfg.tuning().next.super_cost, 16);
        assert_eq!(cfg.tuning().next.super_meter_max, NextTuning::default().super_meter_max);
        let text = fs::read_to_string(&path).unwrap();
        let data: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(data["next"]["smash_multiplier"], 3.0);
        assert!(data["next"].get("super_moves").is_none());
        assert_eq!(data["next"]["super_cost"], 16);
        assert_eq!(data["next"]["super_gain_hit"], 2);
        assert!(text.find("smash_multiplier").unwrap() < text.find("super_cost").unwrap());
        let _ = fs::remove_file(path);
    }

    #[test]
    fn the_menu_starts_in_next_challenge() {
        let g = Game::default();
        assert_eq!((g.game_type.as_str(), g.players.as_str()), ("next", "challenge"));
    }

    #[test]
    fn the_mouse_spinner_is_off_by_default_added_to_old_files_and_saved() {
        let path = std::env::temp_dir().join(format!("paddws_mouse_{}.json", std::process::id()));
        fs::write(&path, r#"{"game": {"fullscreen": false}}"#).unwrap();
        let mut cfg = load(&path);
        assert!(!cfg.mouse.spinner);
        let data: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(data["mouse"]["spinner"], false);
        assert_eq!(data["mouse"]["travel_pixels"], 1000.0);
        cfg.mouse.spinner = true;
        save_preferences(&path, &cfg);
        assert!(load(&path).mouse.spinner);
        let _ = fs::remove_file(path);
    }
}
