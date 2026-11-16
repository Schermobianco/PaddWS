//! JUKEBOX (voce del menu, sbloccata battendo OMEGA o con le iniziali BAS): i temi del gioco con
//! tre oscilloscopi, uno per voce del SID, come i visualizzatori delle musiche chiptune.
//!
//! Brani: i sette temi degli avversari nell'ordine della scala, il finale e OMEGA, che passa da
//! una sezione alla successiva ogni due giri (da OMEGA0 a OMEGA6, poi da capo). Su e giù scelgono
//! il brano e lo fanno partire, il fuoco (Invio, Spazio, A, il click) lo ferma o lo fa ripartire,
//! Esc (B, la pressione lunga dell'encoder) torna al menu. Il volume è quello della musica.

use macroquad::prelude::*;
use paddws_core::challenge::{LEVELS, RUNGS};

use crate::challenge_ui::{T1, scale};
use crate::encoder::Action;
use crate::gamepad::Control;
use crate::input::{self, PadKeys};
use crate::next_ui::unit;
use crate::scenes::{App, Menu, Scene, Song};
use crate::scope;
use crate::touch;

/// Brani: i temi della scala, il finale, OMEGA.
pub const TRACKS: usize = LEVELS + 2;
/// Giri di ogni sezione di OMEGA prima della successiva.
const OMEGA_LOOPS: u32 = 2;
/// Passi del player al secondo (a tempo normale).
const STEPS_PER_SECOND: f64 = 50.0;

/// Nome del brano `i`.
pub fn track_name(i: usize) -> &'static str {
    match i {
        i if i < LEVELS => RUNGS[i].kind.name(),
        i if i == LEVELS => "ENDING",
        _ => "OMEGA",
    }
}

/// Passi del player di un giro della traccia della voce `voice` della canzone `song` (da 1): la
/// somma delle durate delle note e delle pause fino al comando che la fa ricominciare (formato in
/// tools/gen_sid_music.py). 0 se la traccia finisce senza ricominciare.
fn loop_steps(rom: &paddws_sid::Rom, song: u8, voice: usize) -> u32 {
    let Some(start) = rom.songs.get(song as usize - 1).map(|s| s[voice]) else { return 0 };
    let mut ptr = start;
    let mut steps = 0u32;
    for _ in 0..4096 {
        let cmd = rom.byte(ptr);
        ptr = ptr.wrapping_add(match cmd {
            // nota o pausa e la durata
            0x00..=0x6F => {
                steps += rom.byte(ptr.wrapping_add(1)) as u32;
                2
            }
            // strumento, arpeggio
            0x70..=0x7F | 0x90..=0x9F => 1,
            // scivolata, taglio
            0x80 | 0xA0..=0xAF => 2,
            // scivolata del taglio, wobble
            0xB0 | 0xC0..=0xCF => 3,
            0xFE => return steps,
            _ => return 0,
        });
    }
    0
}

/// Secondi di ogni sezione di OMEGA nel JUKEBOX: `OMEGA_LOOPS` giri della traccia del basso.
fn omega_sections() -> [f64; LEVELS] {
    let rom = paddws_sid::Rom::builtin();
    std::array::from_fn(|k| {
        let song = rom.song_number(&format!("omega{k}")).unwrap_or(0);
        let steps = if song == 0 { 0 } else { loop_steps(&rom, song, 1) };
        // senza la canzone (una ROM vecchia) si passa alla sezione dopo ogni 15 secondi
        if steps == 0 { 15.0 } else { (OMEGA_LOOPS * steps) as f64 / STEPS_PER_SECOND }
    })
}

/// La canzone del brano `track` con `played` secondi di ascolto (per OMEGA, la sezione).
fn song_of(track: usize, played: f64, sections: &[f64; LEVELS]) -> Song {
    match track {
        t if t < LEVELS => Song::Theme(RUNGS[t].kind),
        t if t == LEVELS => Song::Ending,
        _ => {
            let total: f64 = sections.iter().sum();
            let mut t = played % total.max(1.0);
            for (k, len) in sections.iter().enumerate() {
                if t < *len {
                    return Song::Omega(k as u8);
                }
                t -= len;
            }
            Song::Omega(0)
        }
    }
}

pub struct Jukebox {
    track: usize,
    playing: bool,
    /// secondi di ascolto del brano (da quando è partito)
    played: f64,
    sections: [f64; LEVELS],
    knobs_ready: bool,
}

impl Jukebox {
    pub fn new() -> Self {
        Self {
            track: 0,
            playing: true,
            played: 0.0,
            sections: omega_sections(),
            knobs_ready: false,
        }
    }

    /// Per la verifica automatica: il brano `track` dopo `played` secondi.
    pub fn show(&mut self, track: usize, played: f64) {
        self.track = track.min(TRACKS - 1);
        self.played = played;
    }

    /// Gamepad: su e giù scelgono, A e Start fermano o fanno ripartire, B torna al menu.
    pub fn pad_keys(&self) -> PadKeys {
        input::pad_keys(|_, c| match c {
            Control::Up => Some(KeyCode::Up),
            Control::Down => Some(KeyCode::Down),
            Control::A | Control::Start => Some(KeyCode::Enter),
            Control::B => Some(KeyCode::Escape),
            _ => None,
        })
    }

    /// Canzone che suona (None se fermo).
    pub fn song(&self) -> Option<Song> {
        self.playing.then(|| song_of(self.track, self.played, &self.sections))
    }

    fn choose(&mut self, track: usize) {
        (self.track, self.played, self.playing) = (track % TRACKS, 0.0, true);
    }

    pub fn update(&mut self, app: &mut App, dt: f64) -> Option<Scene> {
        if input::pressed(KeyCode::Escape) {
            return Some(Scene::Menu(Menu::new(app)));
        }
        if self.playing {
            self.played += dt;
        }
        // encoder: la manopola sceglie il brano, il click ferma, la pressione lunga esce
        if let Some(enc) = &mut app.encoders
            && !std::mem::replace(&mut self.knobs_ready, true)
        {
            enc.configure(0, TRACKS as i32 - 1, 1, self.track as i32);
        }
        let mut toggle = false;
        for e in app.knob_events.clone() {
            match e.action {
                Action::Rotate(v) if v.max(0) as usize != self.track => self.choose((v.max(0) as usize).min(TRACKS - 1)),
                Action::Click => toggle = true,
                Action::LongClick => return Some(Scene::Menu(Menu::new(app))),
                _ => {}
            }
        }
        let mut step = 0i32;
        if input::pressed(KeyCode::Up) || input::pressed(KeyCode::W) {
            step = -1;
        }
        if input::pressed(KeyCode::Down) || input::pressed(KeyCode::S) {
            step = 1;
        }
        // touch: in alto il brano dopo, in basso ferma o fa ripartire, MENU in fondo esce
        let h = app.renderer.world_h;
        for p in touch::taps() {
            if p.y > h - 50.0 * scale(app) {
                return Some(Scene::Menu(Menu::new(app)));
            } else if p.y < h / 2.0 {
                step = 1;
            } else {
                toggle = true;
            }
        }
        if step != 0 {
            self.choose((self.track as i32 + step).rem_euclid(TRACKS as i32) as usize);
            self.knobs_ready = false;
        }
        toggle |= input::any_pressed(&[KeyCode::Enter, KeyCode::KpEnter, KeyCode::Space]);
        if toggle {
            self.playing = !self.playing;
            self.played = 0.0;
        }
        None
    }

    pub fn draw(&self, app: &App) {
        let r = &app.renderer;
        let (sc, u) = (scale(app), unit(app));
        let colors = &app.cfg.colors;
        let (white, gray, accent) = (App::color(colors.white), App::color(colors.lgray), App::color(colors.accent));
        r.fill(BLACK);
        let font = &app.assets.font_text;
        let text = |s: &str, y: f32, color: Color| r.text_centered(s, font, T1 * sc, r.world_w / 2.0, y * sc, 0.0, color);
        text("JUKEBOX", 64.0, accent);
        // il brano, con le frecce del cambio, e la sua posizione
        let name = match self.song() {
            Some(Song::Omega(k)) => format!("< OMEGA {} >", k + 1),
            _ => format!("< {} >", track_name(self.track)),
        };
        text(&name, 120.0, white);
        text(&format!("{}/{TRACKS}", self.track + 1), 150.0, gray);
        // tre oscilloscopi affiancati, uno per voce
        let w = r.world_w;
        let gap = 12.0 * u;
        let box_w = ((w - 4.0 * gap) / 3.0).min(110.0 * u);
        let box_h = 70.0 * u;
        let top = 190.0 * sc;
        let gain = crate::music::VOLUME * crate::config::volume_gain(app.cfg.game.music_volume);
        let points = (box_w / u) as usize;
        let dim = Color::from_rgba(0x3A, 0x3A, 0x3A, 255);
        for v in 0..3 {
            let x0 = w / 2.0 + (v as f32 - 1.0) * (box_w + gap) - box_w / 2.0;
            draw_rectangle_lines(x0, top, box_w, box_h, u, dim);
            let mid = top + box_h / 2.0;
            draw_rectangle(x0 + u, mid, box_w - 2.0 * u, u, dim);
            let trace = match scope::read(&app.sid_music, v).filter(|_| self.playing) {
                Some((x, rate)) => scope::trace(&x, rate, scope::SCOPE_FULL * gain, points),
                None => vec![0.0; points],
            };
            let half = box_h / 2.0 - 3.0 * u;
            for (k, pair) in trace.windows(2).enumerate() {
                let xa = x0 + u + k as f32 * (box_w - 2.0 * u) / (points - 1) as f32;
                let xb = x0 + u + (k + 1) as f32 * (box_w - 2.0 * u) / (points - 1) as f32;
                draw_line(xa, mid - pair[0] * half, xb, mid - pair[1] * half, u, accent);
            }
            r.text_centered(&format!("VOICE {}", v + 1), font, T1 * sc, x0 + box_w / 2.0, top + box_h + 20.0 * sc, 0.0, gray);
        }
        let state = if !self.playing {
            "STOPPED"
        } else if app.cfg.game.music_volume == 0 {
            "MUSIC VOLUME 0%"
        } else {
            "PLAYING"
        };
        text(state, 380.0, if self.playing { white } else { gray });
        if app.touch {
            text("TAP TOP: NEXT   BOTTOM: STOP", 420.0, gray);
            text("MENU", r.world_h / sc - 25.0, white);
        } else {
            text("UP DOWN TO CHOOSE, FIRE TO STOP", 420.0, gray);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tracks_are_the_themes_the_ending_and_omega() {
        let names: Vec<&str> = (0..TRACKS).map(track_name).collect();
        assert_eq!(names, ["ARCADE", "TWIST", "HAMMER", "TITAN", "BLASTER", "RUSH", "GUARDIAN", "ENDING", "OMEGA"]);
        let s = omega_sections();
        assert_eq!(song_of(2, 99.0, &s), Song::Theme(paddws_core::PaddleKind::Hammer));
        assert_eq!(song_of(LEVELS, 0.0, &s), Song::Ending);
    }

    /// OMEGA: ogni sezione dura due giri del basso (4 battute di 8 ottavi, `OMEGA_EIGHTH` di
    /// tools/gen_sid_music.py), la batteria fa giri della stessa lunghezza; poi da capo.
    #[test]
    fn omega_moves_to_the_next_section_every_two_loops() {
        let rom = paddws_sid::Rom::builtin();
        let eighths = [11, 11, 10, 10, 9, 9, 8];
        for (k, e) in eighths.iter().enumerate() {
            let song = rom.song_number(&format!("omega{k}")).unwrap();
            assert_eq!(loop_steps(&rom, song, 1), 32 * e, "omega{k}");
            assert_eq!(loop_steps(&rom, song, 0), 32 * e, "omega{k} batteria");
        }
        let s = omega_sections();
        assert_eq!(s[0], 2.0 * 32.0 * 11.0 / 50.0);
        let omega = LEVELS + 1;
        assert_eq!(song_of(omega, 0.0, &s), Song::Omega(0));
        assert_eq!(song_of(omega, s[0] - 0.01, &s), Song::Omega(0));
        assert_eq!(song_of(omega, s[0] + 0.01, &s), Song::Omega(1));
        let total: f64 = s.iter().sum();
        assert_eq!(song_of(omega, total - 0.01, &s), Song::Omega(6));
        assert_eq!(song_of(omega, total + 0.01, &s), Song::Omega(0));
    }
}
