//! PADD WS - versione nativa Rust (Windows, Linux, Raspberry Pi).

#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod attract;
mod challenge_ui;
mod config;
mod encoder;
mod ending_ui;
mod gamepad;
mod gesture;
mod input;
mod mouse;
mod moves_ui;
mod music;
mod next_ui;
mod paddle_ui;
mod platform;
mod render;
mod scenes;
mod touch;

use std::path::PathBuf;
use std::time::Duration;

use macroquad::audio::{PlaySoundParams, load_sound_from_bytes, play_sound};
use macroquad::prelude::*;
use paddws_core::Params;

use crate::attract::{Attract, AttractArt};
use crate::config::Config;
use crate::moves_ui::{Device, HowTo};
use crate::next_ui::Pick;
use crate::paddle_ui::PaddlePick;
use crate::platform::Instant;
use crate::render::{GameFont, Renderer};
use crate::scenes::{App, Assets, Demo, DemoMode, Menu, Play, Scene};

/// Sui portatili con due GPU chiede ai driver NVIDIA di usare quella dedicata
/// (il simbolo viene esportato dall'eseguibile, vedi build.rs).
#[cfg(windows)]
#[unsafe(no_mangle)]
#[used]
pub static NvOptimusEnablement: u32 = 1;

/// Stessa richiesta per i driver AMD.
#[cfg(windows)]
#[unsafe(no_mangle)]
#[used]
pub static AmdPowerXpressRequestHighPerformance: u32 = 1;

const USAGE: &str = "\
Uso: paddws [opzioni]
  --config FILE           file di configurazione (default: padd_config.json)
  --fullscreen | --windowed
  --crt | --no-crt        filtro CRT
  --width N               larghezza del campo (0 = proporzioni del monitor)
  --height N              altezza del campo (es. --width 320 --height 240: risoluzione del core MiSTer)
  --version
Verifica:
  --screenshot-tour DIR   salva una schermata di ogni scena ed esce
  --bench SECONDI         gioca da solo per N secondi e stampa le statistiche dei frame
  --paddle-gallery DIR    salva un'immagine di ogni tipo di racchetta (per il README) ed esce";

#[derive(Default)]
struct Args {
    config: Option<PathBuf>,
    fullscreen: Option<bool>,
    crt: Option<bool>,
    width: Option<u32>,
    height: Option<u32>,
    screenshot_tour: Option<PathBuf>,
    bench: Option<f64>,
    paddle_gallery: Option<PathBuf>,
}

fn parse_args() -> Args {
    let mut args = Args::default();
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        let mut value = || {
            it.next()
                .unwrap_or_else(|| exit_with(&format!("{arg} richiede un valore")))
        };
        match arg.as_str() {
            "--config" => args.config = Some(value().into()),
            "--fullscreen" => args.fullscreen = Some(true),
            "--windowed" => args.fullscreen = Some(false),
            "--crt" => args.crt = Some(true),
            "--no-crt" => args.crt = Some(false),
            "--width" => args.width = value().parse().ok(),
            "--height" => args.height = value().parse().ok(),
            "--screenshot-tour" => args.screenshot_tour = Some(value().into()),
            "--bench" => args.bench = value().parse().ok(),
            "--paddle-gallery" => args.paddle_gallery = Some(value().into()),
            "--version" => {
                println!("paddws {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            other => exit_with(&format!("Opzione sconosciuta: {other}\n{USAGE}")),
        }
    }
    args
}

fn exit_with(message: &str) -> ! {
    eprintln!("{message}");
    std::process::exit(2);
}

fn main() {
    let args = parse_args();
    let config_path = args.config.clone().unwrap_or_else(config::default_path);
    let mut cfg = config::load(&config_path);
    if let Some(f) = args.fullscreen {
        cfg.game.fullscreen = f;
    }
    if let Some(c) = args.crt {
        cfg.crt_effects.enabled = c;
    }
    if let Some(w) = args.width {
        cfg.resolution.width = w;
    }
    if let Some(h) = args.height {
        cfg.resolution.height = h;
    }
    if cfg.resolution.width == 0 {
        let (sw, sh) = platform::monitor_size().unwrap_or((16, 9));
        cfg.resolution.width = config::auto_width(cfg.resolution.height, sw, sh);
    }
    println!(
        "PADD WS {} - campo {}x{}",
        env!("CARGO_PKG_VERSION"),
        cfg.resolution.width,
        cfg.resolution.height
    );

    let conf = Conf {
        window_title: cfg.game.game_name.clone(),
        window_width: cfg.resolution.width as i32,
        window_height: cfg.resolution.height as i32,
        high_dpi: true,
        fullscreen: cfg.game.fullscreen,
        window_resizable: cfg.game.title_bar,
        sample_count: 1,
        // icona della finestra (barra del titolo, barra delle applicazioni, Alt+Tab)
        icon: Some(macroquad::miniquad::conf::Icon {
            small: *include_bytes!("../icon/icon_16.rgba"),
            medium: *include_bytes!("../icon/icon_32.rgba"),
            big: *include_bytes!("../icon/icon_64.rgba"),
        }),
        platform: macroquad::miniquad::conf::Platform {
            swap_interval: Some(if cfg.game.vsync { 1 } else { 0 }),
            ..Default::default()
        },
    };
    macroquad::Window::from_config(conf, run(args, cfg, config_path));
}

/// Copia di un WAV PCM con la frequenza di campionamento dimezzata: suona a metà velocità,
/// un'ottava sotto (il suono del bullet time). Senza il blocco `fmt ` resta com'è.
fn slowed_wav(bytes: &[u8]) -> Vec<u8> {
    let mut wav = bytes.to_vec();
    let mut at = 12; // dopo "RIFF", dimensione e "WAVE"
    while at + 8 <= wav.len() {
        let size = u32::from_le_bytes([wav[at + 4], wav[at + 5], wav[at + 6], wav[at + 7]]) as usize;
        if &wav[at..at + 4] == b"fmt " && at + 20 <= wav.len() {
            // frequenza di campionamento a +12, byte al secondo a +16
            for field in [at + 12, at + 16] {
                let v = u32::from_le_bytes([wav[field], wav[field + 1], wav[field + 2], wav[field + 3]]);
                wav[field..field + 4].copy_from_slice(&(v / 2).to_le_bytes());
            }
            break;
        }
        at += 8 + size + (size & 1);
    }
    wav
}

async fn load_assets() -> Assets {
    let sound = async |bytes: &[u8]| {
        load_sound_from_bytes(bytes)
            .await
            .expect("suono incluso nell'eseguibile")
    };
    let slow = async |bytes: &[u8]| sound(&slowed_wav(bytes)).await;
    Assets {
        font_text: GameFont::from_bytes(include_bytes!("../../../assets/fonts/munro.ttf")),
        font_score: GameFont::from_bytes(include_bytes!("../../../assets/fonts/pong-score.ttf")),
        sid: [
            sound(include_bytes!("../../../assets/sounds/sid/wall.wav")).await,
            sound(include_bytes!("../../../assets/sounds/sid/hit.wav")).await,
            sound(include_bytes!("../../../assets/sounds/sid/boost.wav")).await,
            sound(include_bytes!("../../../assets/sounds/sid/score.wav")).await,
            sound(include_bytes!("../../../assets/sounds/sid/coin.wav")).await,
            sound(include_bytes!("../../../assets/sounds/sid/move.wav")).await,
            sound(include_bytes!("../../../assets/sounds/sid/special.wav")).await,
        ],
        slow_sid: [
            slow(include_bytes!("../../../assets/sounds/sid/wall.wav")).await,
            slow(include_bytes!("../../../assets/sounds/sid/hit.wav")).await,
            slow(include_bytes!("../../../assets/sounds/sid/boost.wav")).await,
            slow(include_bytes!("../../../assets/sounds/sid/score.wav")).await,
            slow(include_bytes!("../../../assets/sounds/sid/coin.wav")).await,
            slow(include_bytes!("../../../assets/sounds/sid/move.wav")).await,
            slow(include_bytes!("../../../assets/sounds/sid/special.wav")).await,
        ],
        voices: [
            sound(include_bytes!("../../../assets/sounds/voice/arcade.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/titan.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/hammer.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/twist.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/blaster.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/rush.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/guardian.wav")).await,
        ],
        shouts: [
            sound(include_bytes!("../../../assets/sounds/voice/move_straight.wav")).await,
            sound(include_bytes!("../../../assets/sounds/voice/move_rise.wav")).await,
        ],
        ready: sound(include_bytes!("../../../assets/sounds/voice/ready.wav")).await,
        go: sound(include_bytes!("../../../assets/sounds/voice/go.wav")).await,
        you_win: sound(include_bytes!("../../../assets/sounds/voice/you_win.wav")).await,
    }
}

/// Nome della GPU in uso, per il log (sui portatili ibridi dice se si usa quella dedicata).
fn gl_renderer() -> String {
    const GL_RENDERER: u32 = 0x1F01;
    let ptr = unsafe { macroquad::miniquad::gl::glGetString(GL_RENDERER) };
    if ptr.is_null() {
        return "?".into();
    }
    unsafe { std::ffi::CStr::from_ptr(ptr as *const std::ffi::c_char) }
        .to_string_lossy()
        .into_owned()
}

async fn run(args: Args, mut cfg: Config, config_path: PathBuf) {
    println!("GPU: {}", gl_renderer());
    if platform::WEB {
        // nel browser il campo prende le proporzioni della tela (vedi anche il ciclo qui sotto)
        cfg.resolution.width = config::web_field_width(cfg.resolution.height, screen_width(), screen_height());
    }
    touch::init();
    platform::boost_priority();
    show_mouse(false);
    let assets = load_assets().await;
    for s in &assets.sid {
        play_sound(
            s,
            PlaySoundParams {
                looped: false,
                volume: 0.0,
            },
        ); // apre subito il dispositivo audio
    }
    let mut app = App {
        params: Params::new(&cfg.tuning()),
        renderer: Renderer::new(cfg.resolution.width, cfg.resolution.height, cfg.game.keep_aspect),
        on_raspberry: platform::is_raspberry_pi(),
        quit: false,
        players: 2,
        cpu: false,
        evo: false,
        next: false,
        loadout: [[
            paddws_core::Bonus::Smash,
            paddws_core::Bonus::Teleport,
            paddws_core::Bonus::Slow,
        ]; 2],
        paddles: [None; 2],
        challenge: false,
        run: None,
        scores: challenge_ui::load_scores(&config_path),
        seed: platform::clock_seed(),
        assets,
        attract: AttractArt::load(),
        credits: 0,
        touch: false,
        encoders: App::open_encoders(&cfg),
        knob_events: Vec::new(),
        mouse: mouse::Spinner::default(),
        pads: gamepad::Pads::open(),
        pad_used: false,
        music: None,
        sid_music: music::SidMusic::start(),
        egg: false,
        suspended: None,
        config_path,
        cfg,
    };
    // GAME TYPE e PLAYERS dell'ultima volta (anche per la demo dell'attract)
    app.load_mode();

    if let Some(dir) = &args.paddle_gallery {
        let _ = std::fs::create_dir_all(dir);
        for kind in paddws_core::PaddleKind::ALL {
            for _ in 0..3 {
                app.renderer.update_layout(&app.cfg.crt_effects);
                app.renderer.begin();
                paddle_ui::draw_gallery(&app, kind, 3.0);
                app.renderer.end(app.cfg.game.white_level);
                next_frame().await;
            }
            app.renderer.begin();
            paddle_ui::draw_gallery(&app, kind, 3.0);
            app.renderer.end(app.cfg.game.white_level);
            let path = dir.join(format!("paddle_{}.png", kind.name().to_lowercase()));
            get_screen_data().export_png(&path.to_string_lossy());
            println!("{}", path.display());
            next_frame().await;
        }
        return;
    }

    if let Some(dir) = &args.screenshot_tour {
        screenshot_tour(&mut app, dir).await;
        return;
    }

    let mut scene = Scene::Attract(Attract::new(&app.attract, app.cfg.game.self_test));
    let mut pacer = Pacer::new(app.cfg.game.vsync, app.cfg.game.fps);
    let mut bench: Option<(Instant, f64, Vec<f64>)> = None;
    if let Some(secs) = args.bench {
        app.evo = true;
        let mut play = Play::new(&mut app);
        play.skip_countdown();
        scene = Scene::Game(Box::new(play));
        bench = Some((Instant::now(), secs, Vec::new()));
    }

    loop {
        let time = pacer.begin_frame();
        let dt = time.sim;
        if let Some((start, secs, frames)) = &mut bench {
            frames.push(time.raw);
            if start.elapsed().as_secs_f64() >= *secs {
                print_frame_stats(frames, pacer.refresh);
                break;
            }
        }

        if is_key_pressed(KeyCode::F11) {
            app.toggle_fullscreen();
            pacer.remeasure();
        }
        if is_key_pressed(KeyCode::C) && !scene.uses_bonus_keys() {
            app.toggle_crt();
        }
        // encoder del cabinato o mouse come spinner: eventi del frame per la scena
        let mouse = app.mouse.frame(app.mouse_spinner());
        app.knob_events = app.encoders.as_mut().map(|e| e.poll(get_time(), mouse)).unwrap_or_default();
        // si gioca con il touch (non con il mouse): niente scritte dei tasti, comandi da toccare
        app.touch |= !touches().is_empty();
        touch::poll(&app.renderer);
        // gamepad: i loro comandi come tasti per la scena, e quale controllo si è usato per ultimo
        app.pads.poll(get_time());
        input::set_pads(&app.pads, &scene.pad_keys(&app));
        if app.pads.any_pressed() {
            app.pad_used = true;
        } else if !get_keys_pressed().is_empty() || !touches().is_empty() || !app.knob_events.is_empty() {
            app.pad_used = false;
        }
        // telefono in verticale: il gioco si ferma finché non lo si ruota
        let portrait = touch::portrait();
        // nel browser, finché si è nell'attract, il campo segue la tela: quando si ruota il
        // telefono (la pagina aperta in verticale) o Safari mostra o nasconde le sue barre, prende
        // le nuove proporzioni e l'attract riparte; in partita e nei menu resta com'è
        if platform::WEB && !portrait && matches!(scene, Scene::Attract(_)) {
            let width = config::web_field_width(app.cfg.resolution.height, screen_width(), screen_height());
            if width != app.cfg.resolution.width {
                app.set_field_width(width);
                scene = Scene::Attract(Attract::new(&app.attract, false));
            }
        }
        if !portrait && let Some(next) = scene.update(&mut app, dt) {
            // una partita lasciata per il menu resta da riprendere (RESUME)
            if let Scene::Game(play) = std::mem::replace(&mut scene, next)
                && play.suspend
            {
                app.suspended = Some(play);
            }
        }
        let music = scene.music(&app);
        app.set_music(music);
        app.set_tempo(scene.tempo(&app));
        if app.quit {
            break;
        }

        app.renderer.update_layout(&app.cfg.crt_effects);
        app.renderer.begin();
        if portrait {
            draw_rotate(&app);
        } else {
            scene.draw(&app);
        }
        app.renderer.end(app.cfg.game.white_level);

        pacer.wait();
        next_frame().await;
        pacer.after_present();
    }
}

/// Schermo in verticale: si chiede di ruotare il dispositivo (il campo è sempre orizzontale).
fn draw_rotate(app: &App) {
    let r = &app.renderer;
    let (w, h, s) = (r.world_w, r.world_h, app.scale());
    let white = App::color(app.cfg.colors.white);
    r.fill(BLACK);
    r.text_centered(
        "ROTATE",
        &app.assets.font_text,
        90.0 * s,
        w / 2.0,
        h / 2.0 - 50.0 * s,
        0.0,
        white,
    );
    r.text_centered(
        "THE DEVICE",
        &app.assets.font_text,
        90.0 * s,
        w / 2.0,
        h / 2.0 + 50.0 * s,
        0.0,
        white,
    );
}

/// Schermate di verifica di ogni scena, salvate in `dir`.
async fn screenshot_tour(app: &mut App, dir: &std::path::Path) {
    let _ = std::fs::create_dir_all(dir);
    let suffix = if app.cfg.crt_effects.enabled { "_crt" } else { "" };
    type MakeScene = fn(&mut App) -> Scene;
    // l'attract viene portato al frame voluto; il ciclo qui sotto aggiunge altri 30 frame
    fn attract_at(app: &mut App, self_test: bool, frames: u32) -> Scene {
        let mut a = Attract::new(&app.attract, self_test);
        let mut sounds = Vec::new();
        for _ in 0..frames {
            a.step(&app.attract, &app.renderer, app.hud(), &mut sounds);
        }
        Scene::Attract(a)
    }
    // demo dell'attract di una modalità, portata a un frame con il nome della modalità (il ciclo
    // qui sotto aggiunge altri 30 frame)
    fn demo_at(app: &mut App, mode: DemoMode) -> Scene {
        let mut scene = Scene::Demo(Box::new(Demo::of(app, mode)));
        for _ in 0..615 {
            if let Some(next) = scene.update(app, 1.0 / 60.0) {
                scene = next;
            }
        }
        scene
    }
    // partita NEXT con questi tipi di racchetta
    fn kinds(app: &mut App, kinds: [paddws_core::PaddleKind; 2]) -> Scene {
        app.players = 2;
        app.next = true;
        app.paddles = kinds.map(Some);
        let mut play = Play::new(app);
        play.skip_countdown();
        play.fill_kinds_demo();
        app.next = false;
        app.paddles = [None; 2];
        Scene::Game(Box::new(play))
    }
    // CHALLENGE al livello `level` (da 0), con una partita a metà
    fn challenge(app: &mut App, level: usize) {
        app.players = 2;
        app.cpu = true;
        app.next = true;
        app.challenge = true;
        app.paddles = [Some(paddws_core::PaddleKind::Arcade), None];
        let mut run = challenge_ui::Run::new();
        run.level = level;
        run.score = 8_750;
        app.run = Some(run);
    }
    // HOW TO PLAY delle mosse speciali con il controllo `device` (None: quello in uso), all'istante
    // `at` dell'animazione dopo i 30 frame del ciclo qui sotto
    fn howto(app: &mut App, device: Option<Device>, at: f64) -> Scene {
        app.players = 2;
        app.cpu = false;
        app.next = true;
        app.cfg.next.super_moves = true;
        let mut howto = HowTo::new(app);
        howto.skip_to(at - 0.5);
        if let Some(device) = device {
            howto.show_device(device);
        }
        Scene::HowTo(howto)
    }
    // finale della CHALLENGE, alla parte `part` più `at` secondi dopo i 30 frame del ciclo qui sotto
    fn ending(app: &mut App, part: ending_ui::Part, at: f64) -> Scene {
        challenge(app, paddws_core::challenge::LEVELS - 1);
        if let Some(run) = &mut app.run {
            run.score = 1_234_560;
        }
        let mut e = ending_ui::Ending::new(app, 2);
        e.skip_to(part, at - 0.5);
        Scene::Ending(e)
    }
    use ending_ui::Part as E;
    use paddws_core::PaddleKind as K;
    // easter egg acceso (iniziali "WS!"): giallo e rosso scambiati
    fn egg(app: &mut App, scene: Scene) -> Scene {
        app.set_egg(true);
        scene
    }
    let shots: [(&str, MakeScene); 62] = [
        ("1_demo_classic", |app| demo_at(app, DemoMode::Classic)),
        ("1_demo_evo", |app| demo_at(app, DemoMode::Evo)),
        ("1_demo_next", |app| demo_at(app, DemoMode::Next)),
        ("1_demo_challenge", |app| demo_at(app, DemoMode::Challenge)),
        ("8_challenge_intro", |app| {
            challenge(app, 5);
            Scene::Intro(challenge_ui::Intro::new(app))
        }),
        ("8_challenge_game", |app| {
            challenge(app, 2);
            let mut play = Play::challenge(app);
            play.skip_countdown();
            play.fill_challenge_demo();
            Scene::Game(Box::new(play))
        }),
        // touch: P2 HOLD HERE nella metà della CPU, con la scritta del conto alla rovescia
        ("8_challenge_countdown_touch", |app| {
            challenge(app, 2);
            app.touch = true;
            Scene::Game(Box::new(Play::challenge(app)))
        }),
        ("8_challenge_challenger", |app| {
            challenge(app, 2);
            Scene::Challenger(challenge_ui::Challenger::new(app))
        }),
        ("8_challenge_challenger_pick", |app| {
            challenge(app, 2);
            Scene::Pick(Pick::challenger(app, paddws_core::Side::Right))
        }),
        ("8_challenge_game_right", |app| {
            // il campione ha vinto la sfida da destra: la CPU gioca a sinistra
            challenge(app, 2);
            app.paddles = [None, Some(paddws_core::PaddleKind::Arcade)];
            if let Some(run) = &mut app.run {
                run.side = paddws_core::Side::Right;
            }
            let mut play = Play::challenge(app);
            play.skip_countdown();
            play.fill_challenge_demo();
            Scene::Game(Box::new(play))
        }),
        ("8_challenge_clear", |app| {
            challenge(app, 3);
            Scene::Clear(challenge_ui::Clear::new(app, 0))
        }),
        ("8_challenge_continue", |app| {
            challenge(app, 4);
            app.cfg.game.free_play = false;
            app.credits = 0;
            Scene::Continue(challenge_ui::Continue::new(app))
        }),
        ("8_challenge_lost", |app| {
            // livello perso: solo CPU WINS, si può ancora continuare
            challenge(app, 2);
            let mut play = Play::challenge(app);
            play.skip_countdown();
            play.set_scores([2, 5], 0);
            play.show_game_over();
            Scene::Game(Box::new(play))
        }),
        ("8_challenge_continue_over", |app| {
            // CONTINUE scaduto: GAME OVER, poi iniziali o classifica
            challenge(app, 4);
            let mut cont = challenge_ui::Continue::new(app);
            cont.expire(app);
            Scene::Continue(cont)
        }),
        ("8_challenge_initials", |_| {
            Scene::Initials(challenge_ui::Initials::new((25_000, 6)))
        }),
        ("9_ending_1_congrats", |app| ending(app, E::Congrats, 1.5)),
        ("9_ending_2_parade", |app| ending(app, E::Parade, 7.0)),
        ("9_ending_3_score", |app| ending(app, E::Score, 6.0)),
        ("9_ending_4_fireworks", |app| ending(app, E::Champion, 3.5)),
        ("9_ending_5_credits", |app| ending(app, E::Credits, 14.0)),
        ("9_ending_6_the_end", |app| ending(app, E::TheEnd, 0.2)),
        ("8_challenge_scores", |app| {
            app.run = None;
            app.challenge = false;
            app.cpu = false;
            app.next = false;
            Scene::Scores(challenge_ui::Scores::new(Some(2)))
        }),
        ("0_boot", |app| attract_at(app, true, 100)),
        ("0_boot_grid", |app| attract_at(app, true, 210)),
        ("0_stripes", |app| attract_at(app, false, 0)),
        ("0_logo", |app| attract_at(app, false, 144)),
        ("0_title_free", |app| attract_at(app, false, 144 + 132 + 150)),
        ("0_title_coin", |app| {
            app.cfg.game.free_play = false;
            app.credits = 0;
            attract_at(app, false, 144 + 132 + 150)
        }),
        ("2_menu", |app| Scene::Menu(Menu::new(app))),
        ("2_menu_top", |app| {
            // la ruota alla prima voce: sopra il rullo resta vuoto
            let mut menu = Menu::new(app);
            menu.show(0);
            Scene::Menu(menu)
        }),
        ("3_game_evo", |app| {
            app.players = 2;
            app.evo = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.set_scores([3, 11], 0);
            Scene::Game(Box::new(play))
        }),
        ("4_game_1p", |app| {
            app.players = 1;
            app.evo = false;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.set_scores([7, 0], 12);
            Scene::Game(Box::new(play))
        }),
        ("5_countdown", |app| {
            app.players = 2;
            app.evo = false;
            Scene::Game(Box::new(Play::new(app)))
        }),
        // touch: il simbolo della pausa in cima alla linea, con la scritta nel conto alla rovescia
        ("5_countdown_touch", |app| {
            app.players = 2;
            app.evo = false;
            app.touch = true;
            Scene::Game(Box::new(Play::new(app)))
        }),
        ("4_game_touch", |app| {
            app.players = 2;
            app.evo = false;
            app.touch = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.set_scores([3, 5], 0);
            Scene::Game(Box::new(play))
        }),
        ("2_menu_challenge", |app| {
            app.players = 2;
            app.cpu = true;
            app.challenge = true;
            app.evo = false;
            app.next = true;
            Scene::Menu(Menu::new(app))
        }),
        ("2_menu_next", |app| {
            app.players = 2;
            app.cpu = false;
            app.challenge = false;
            app.evo = false;
            app.next = true;
            Scene::Menu(Menu::new(app))
        }),
        // presentazione delle mosse speciali, una per controllo, in punti diversi dell'animazione
        // (il ciclo qui sotto aggiunge mezzo secondo)
        ("6_next_howto", |app| howto(app, None, 0.55)),
        ("6_next_howto_keyboard_1p", |app| {
            let scene = howto(app, None, 0.8);
            app.cpu = true; // contro la CPU: solo i tasti del giocatore 1
            scene
        }),
        ("6_next_howto_touch", |app| {
            app.touch = true;
            howto(app, None, 0.6)
        }),
        ("6_next_howto_spinner", |app| howto(app, Some(Device::Spinner), 0.3)),
        ("6_next_howto_mouse", |app| howto(app, Some(Device::Mouse), 0.9)),
        ("6_next_howto_joystick", |app| {
            // si gioca con il gamepad: la presentazione mostra da sola i comandi del joystick
            app.pad_used = true;
            howto(app, None, 0.7)
        }),
        ("6_next_howto_joystick_press", |app| {
            // lo stesso, con il pulsante A premuto
            app.pad_used = true;
            howto(app, None, 0.3)
        }),
        ("6_next_pick", |app| {
            app.players = 2;
            app.next = true;
            Scene::Pick(Pick::new(app))
        }),
        ("6_next_paddles", |app| {
            app.players = 2;
            app.next = true;
            let mut pick = PaddlePick::new(app);
            pick.demo();
            Scene::Paddles(pick)
        }),
        ("7_next_kinds_blaster_guardian", |app| {
            kinds(app, [K::Blaster, K::Guardian])
        }),
        ("7_next_kinds_titan_twist", |app| kinds(app, [K::Titan, K::Twist])),
        ("7_next_kinds_hammer_rush", |app| kinds(app, [K::Hammer, K::Rush])),
        ("7_next_game", |app| {
            app.players = 2;
            app.next = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.fill_next_demo();
            app.next = false;
            Scene::Game(Box::new(play))
        }),
        ("7_next_super", |app| {
            app.players = 2;
            app.next = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.fill_super_demo();
            app.next = false;
            Scene::Game(Box::new(play))
        }),
        ("7_next_bullet", |app| {
            app.players = 2;
            app.next = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.fill_bullet_demo(false);
            app.next = false;
            Scene::Game(Box::new(play))
        }),
        ("7_next_bullet_armed", |app| {
            app.players = 2;
            app.next = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.fill_bullet_demo(true);
            app.next = false;
            Scene::Game(Box::new(play))
        }),
        ("7_next_steer", |app| {
            app.players = 2;
            app.next = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.fill_steer_demo();
            app.next = false;
            Scene::Game(Box::new(play))
        }),
        ("5_game_over", |app| {
            app.players = 2;
            app.evo = false;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.set_scores([11, 6], 0);
            play.show_game_over();
            Scene::Game(Box::new(play))
        }),
        ("5_game_over_win", |app| {
            // contro la CPU vince chi gioca: solo YOU WIN
            app.players = 2;
            app.cpu = true;
            app.evo = false;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.set_scores([11, 6], 0);
            play.show_game_over();
            app.cpu = false;
            Scene::Game(Box::new(play))
        }),
        ("a_egg_scores", |app| {
            app.run = None;
            app.challenge = false;
            app.cpu = false;
            app.next = false;
            egg(app, Scene::Scores(challenge_ui::Scores::new(Some(0))))
        }),
        ("a_egg_title", |app| {
            let scene = attract_at(app, false, 144 + 132 + 150);
            egg(app, scene)
        }),
        ("a_egg_menu", |app| egg(app, Scene::Menu(Menu::new(app)))),
        ("a_egg_next_super", |app| {
            app.players = 2;
            app.next = true;
            let mut play = Play::new(app);
            play.skip_countdown();
            play.fill_super_demo();
            app.next = false;
            egg(app, Scene::Game(Box::new(play)))
        }),
        ("a_egg_howto", |app| {
            let scene = howto(app, None, 0.3);
            egg(app, scene)
        }),
        ("a_egg_fireworks", |app| {
            let scene = ending(app, E::Champion, 3.5);
            egg(app, scene)
        }),
    ];
    // le schermate che accendono le mosse speciali, il touch o il gamepad non cambiano le altre
    let (super_moves, touch) = (app.cfg.next.super_moves, app.touch);
    for (name, make) in shots {
        (app.cfg.next.super_moves, app.touch, app.pad_used) = (super_moves, touch, false);
        app.set_egg(false);
        let mut scene = make(app);
        for _ in 0..30 {
            scene.update(app, 1.0 / 60.0);
            app.renderer.update_layout(&app.cfg.crt_effects);
            app.renderer.begin();
            scene.draw(app);
            app.renderer.end(app.cfg.game.white_level);
            next_frame().await;
        }
        app.renderer.begin();
        scene.draw(app);
        app.renderer.end(app.cfg.game.white_level);
        let path = dir.join(format!("{name}{suffix}.png"));
        get_screen_data().export_png(&path.to_string_lossy());
        println!("{}", path.display());
        next_frame().await;
    }
}

fn print_frame_stats(frames: &[f64], refresh: Option<f64>) {
    // i primi 2 secondi (riscaldamento e misura del vsync) sono esclusi
    let mut elapsed = 0.0;
    let ms: Vec<f64> = frames
        .iter()
        .filter_map(|d| {
            elapsed += d;
            (elapsed > 2.0).then_some(d * 1000.0)
        })
        .collect();
    let mean = ms.iter().sum::<f64>() / ms.len() as f64;
    let stdev = (ms.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / ms.len() as f64).sqrt();
    let max = ms.iter().cloned().fold(0.0, f64::max);
    let late = ms.iter().filter(|v| **v > mean * 1.5).count();
    // frame persi davvero: quelli attesi alla frequenza del monitor meno quelli prodotti
    let dropped = refresh.map_or(0.0, |r| {
        (ms.iter().sum::<f64>() / 1000.0 * r - ms.len() as f64).max(0.0)
    });
    println!(
        "frames={} mean={mean:.2}ms stdev={stdev:.2} max={max:.2} late={late} dropped={dropped:.0}",
        ms.len()
    );
}

/// Ritmo dei frame.
///
/// - Con il vsync è lo scambio dei buffer a cadenzare i frame. Alcuni driver però
///   ignorano la richiesta: se succede, il frame rate viene limitato alla frequenza
///   del monitor (o a `game.fps` se la frequenza non è nota).
/// - Con il vsync funzionante il dt della simulazione viene agganciato ai multipli
///   del periodo di refresh: i frame arrivano a schermo a intervalli regolari anche
///   quando la CPU si sveglia con qualche millisecondo di ritardo, e senza
///   l'aggancio quel rumore diventerebbe un micro-scatto del movimento.
/// - L'attesa della GPU dopo lo scambio (glFinish) impedisce al driver di accodare
///   frame in anticipo: ~1 frame di latenza. Se fa perdere frame viene disattivata,
///   perché la fluidità ha la precedenza.
struct Pacer {
    vsync: bool,
    fps: u32,
    last: Option<Instant>,
    samples: Vec<f64>,
    checked: bool,
    cap: Option<Duration>,
    deadline: Option<Instant>,
    gpu_sync: bool,
    /// frequenza del monitor: letta dal sistema o stimata dalle misure
    refresh: Option<f64>,
    /// vsync verificato: il dt viene agganciato al periodo
    snap: bool,
    /// differenza accumulata tra tempo reale e tempo agganciato
    debt: f64,
}

struct FrameTime {
    /// tempo reale misurato
    raw: f64,
    /// tempo con cui avanzare la simulazione
    sim: f64,
}

impl Pacer {
    fn new(vsync: bool, fps: u32) -> Self {
        let refresh = platform::refresh_rate().map(|r| r.clamp(30.0, 360.0));
        // nel browser i frame li scandisce il browser stesso: niente limite né attesa della GPU
        let cap = (!vsync && !platform::WEB).then(|| Duration::from_secs_f64(1.0 / fps.max(1) as f64));
        let gpu_sync = !platform::WEB && std::env::var_os("PADDWS_NO_GPU_SYNC").is_none();
        Self {
            vsync,
            fps,
            last: None,
            samples: Vec::new(),
            checked: false,
            cap,
            deadline: None,
            gpu_sync,
            refresh,
            snap: false,
            debt: 0.0,
        }
    }

    fn remeasure(&mut self) {
        self.samples.clear();
        self.checked = false;
        self.snap = false;
        self.debt = 0.0;
    }

    fn begin_frame(&mut self) -> FrameTime {
        let now = Instant::now();
        let raw = self.last.map_or(0.0, |t| (now - t).as_secs_f64());
        self.last = Some(now);
        self.check(raw);
        FrameTime {
            raw,
            sim: self.snapped(raw),
        }
    }

    fn snapped(&mut self, dt: f64) -> f64 {
        let (true, Some(refresh)) = (self.snap, self.refresh) else {
            return dt;
        };
        let period = 1.0 / refresh;
        let frames = (dt / period).round().max(1.0);
        if (dt - frames * period).abs() > period * 0.3 {
            self.debt = 0.0; // intervallo anomalo (blocco, cambio modalità): tempo reale
            return dt;
        }
        let mut sim = frames * period;
        self.debt += dt - sim;
        // il ritardo accumulato si recupera a periodi interi: nessuna deriva nel tempo
        if self.debt > period {
            self.debt -= period;
            sim += period;
        } else if self.debt < -period {
            self.debt += period;
            sim -= period;
        }
        sim
    }

    fn check(&mut self, dt: f64) {
        if self.checked || dt <= 0.0 || platform::WEB {
            return;
        }
        self.samples.push(dt);
        if self.samples.len() < 120 {
            return;
        }
        self.checked = true;
        let mut s: Vec<f64> = self.samples[20..].to_vec(); // i primi frame sono di riscaldamento
        let mean = s.iter().sum::<f64>() / s.len() as f64;
        s.sort_by(f64::total_cmp);
        let median = s[s.len() / 2];
        if !self.vsync || self.cap.is_some() {
            return;
        }
        let refresh = match self.refresh {
            Some(r) => r,
            // frequenza non nota (es. Linux): oltre 300 fps il vsync non sta agendo
            None if median < 1.0 / 300.0 => {
                println!(
                    "vsync not honored by the driver ({:.0} fps): capping at {} fps",
                    1.0 / median,
                    self.fps
                );
                self.cap = Some(Duration::from_secs_f64(1.0 / self.fps.max(1) as f64));
                return;
            }
            None => *self.refresh.insert(1.0 / median),
        };
        if median < 0.75 / refresh {
            println!(
                "vsync not honored by the driver ({:.0} fps): capping at {refresh:.0} Hz",
                1.0 / median
            );
            self.cap = Some(Duration::from_secs_f64(1.0 / refresh));
        } else if self.gpu_sync && mean > 1.02 / refresh {
            // la media (non la mediana) vede anche i frame persi sporadici
            println!(
                "frames late with GPU sync ({:.1} fps on {refresh:.0} Hz): disabling it",
                1.0 / mean
            );
            self.gpu_sync = false;
            self.remeasure();
        } else {
            self.snap = true;
        }
    }

    /// Con il limite attivo attende la scadenza del frame: sleep e poi attesa attiva
    /// per l'ultimo millisecondo, così l'intervallo è regolare.
    fn wait(&mut self) {
        let Some(cap) = self.cap else { return };
        let now = Instant::now();
        let deadline = match self.deadline {
            Some(d) if d > now && d - now <= cap => d,
            _ => now + cap,
        };
        if let Some(rest) = deadline.checked_duration_since(Instant::now())
            && rest > Duration::from_millis(2)
        {
            std::thread::sleep(rest - Duration::from_millis(1));
        }
        while Instant::now() < deadline {
            std::hint::spin_loop();
        }
        self.deadline = Some(deadline + cap);
    }

    fn after_present(&self) {
        if self.gpu_sync {
            unsafe { macroquad::miniquad::gl::glFinish() };
        }
    }
}
