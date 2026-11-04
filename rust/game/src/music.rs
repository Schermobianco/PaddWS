//! Musica del SID suonata in tempo reale dal SID Rust (`paddws-sid`): il player legge la ROM della
//! musica come quello del MiSTer e del C64, quindi il tempo può cambiare in partita (match point,
//! bullet time) senza registrazioni a parte.
//!
//! - Nativo (Windows, Linux, Raspberry): la sintesi gira nel thread audio, dentro il mixer di
//!   quad-snd (`vendor/quad-snd`, `set_stream`), sopra gli effetti; i comandi arrivano con un
//!   canale. Un solo dispositivo audio, come prima: la latenza è quella del mixer (circa 90 ms).
//! - Web: il plugin JavaScript `rust/web/sid_audio.js` chiede i campioni con uno ScriptProcessor
//!   nello stesso AudioContext di quad-snd (blocchi da 2048, circa 45 ms); l'audio parte al primo
//!   gesto dell'utente, come gli effetti. Lo ScriptProcessor funziona anche fuori da https.

use paddws_sid::Music;

/// Volume della musica rispetto agli effetti (come i vecchi OGG suonati a 0,8).
pub const VOLUME: f32 = 0.8;

/// Frequenza del mixer nativo di quad-snd.
#[cfg(not(target_arch = "wasm32"))]
const NATIVE_RATE: u32 = 44_100;

#[derive(Clone, Copy, Debug)]
enum Cmd {
    Song(u8),
    Fast(bool),
    Slow(bool),
}

/// Livello di ogni canzone della ROM a volume 1: RMS delle parti che suonano (`song_level`, sui
/// primi `LEVEL_SECONDS` secondi). Il test `song_levels_match_the_rom` avvisa se la ROM cambia.
const SONG_LEVELS: [(&str, f32); 14] = [
    ("title", 0.223),
    ("intro", 0.189),
    ("clear", 0.185),
    ("continue", 0.171),
    ("game_over", 0.107),
    ("champion", 0.223),
    ("theme_arcade", 0.202),
    ("theme_titan", 0.121),
    ("theme_hammer", 0.200),
    ("theme_twist", 0.159),
    ("theme_blaster", 0.196),
    ("theme_rush", 0.168),
    ("theme_guardian", 0.161),
    ("ending", 0.189),
];
/// Sui telefoni ogni canzone si porta a questo livello: la media dei temi della partita.
const GAME_LEVEL: f32 = 0.172;
/// Secondi di musica misurati per `SONG_LEVELS`.
#[cfg(test)]
const LEVEL_SECONDS: usize = 30;

/// Guadagno della canzone `song` (da 1): sui telefoni la porta a `GAME_LEVEL` (il titolo copriva
/// il resto), altrove 1 (come sul MiSTer e sul C64).
fn song_gain(song: u8) -> f32 {
    if !crate::platform::touch_device() || song == 0 {
        return 1.0;
    }
    static ROM: std::sync::OnceLock<paddws_sid::Rom> = std::sync::OnceLock::new();
    let rom = ROM.get_or_init(paddws_sid::Rom::builtin);
    rom.names
        .get(song as usize - 1)
        .and_then(|name| SONG_LEVELS.iter().find(|(n, _)| n == name))
        .map_or(1.0, |(_, level)| GAME_LEVEL / level)
}

/// Volume della musica per la canzone `song`.
fn music_volume(song: u8) -> f32 {
    VOLUME * crate::platform::music_volume() * song_gain(song)
}

fn apply(m: &mut Music, cmd: Cmd) {
    match cmd {
        // con 0 (silenzio) le note rilasciano al volume della canzone di prima
        Cmd::Song(n) => {
            m.set_song(n);
            if n != 0 {
                m.set_volume(music_volume(n));
            }
        }
        Cmd::Fast(on) => m.set_fast(on),
        Cmd::Slow(on) => m.set_slow(on),
    }
}

/// Comandi alla musica che suona nel thread audio (o nel callback del browser).
pub struct SidMusic {
    #[cfg(not(target_arch = "wasm32"))]
    tx: std::sync::mpsc::Sender<Cmd>,
    song: u8,
    fast: bool,
    slow: bool,
}

impl SidMusic {
    /// Avvia la sorgente continua (in silenzio fino alla prima canzone).
    pub fn start() -> SidMusic {
        #[cfg(not(target_arch = "wasm32"))]
        let tx = {
            let (tx, rx) = std::sync::mpsc::channel::<Cmd>();
            let mut music = Music::new(NATIVE_RATE);
            music.set_volume(music_volume(0));
            quad_snd::set_stream(Some(Box::new(move |buffer: &mut [f32]| {
                while let Ok(cmd) = rx.try_recv() {
                    apply(&mut music, cmd);
                }
                music.mix_stereo(buffer);
            })));
            tx
        };
        #[cfg(target_arch = "wasm32")]
        web::start();
        SidMusic {
            #[cfg(not(target_arch = "wasm32"))]
            tx,
            song: 0,
            fast: false,
            slow: false,
        }
    }

    fn send(&self, cmd: Cmd) {
        #[cfg(not(target_arch = "wasm32"))]
        let _ = self.tx.send(cmd);
        #[cfg(target_arch = "wasm32")]
        web::send(cmd);
    }

    /// Canzone del SID (da 1; 0 = silenzio, con il rilascio delle note): riparte da capo se cambia.
    pub fn set_song(&mut self, song: u8) {
        if song != self.song {
            self.song = song;
            self.send(Cmd::Song(song));
        }
    }

    /// Tempo della musica: `fast` al match point (×1,25), `slow` nel bullet time (metà velocità,
    /// un'ottava sotto).
    pub fn set_tempo(&mut self, fast: bool, slow: bool) {
        if fast != self.fast {
            self.fast = fast;
            self.send(Cmd::Fast(fast));
        }
        if slow != self.slow {
            self.slow = slow;
            self.send(Cmd::Slow(slow));
        }
    }
}

#[cfg(target_arch = "wasm32")]
mod web {
    use std::cell::RefCell;

    use super::{Cmd, Music, apply, music_volume};

    unsafe extern "C" {
        /// Crea lo ScriptProcessor (`rust/web/sid_audio.js`) e restituisce la frequenza del
        /// contesto audio (0 se nel browser non c'è l'audio).
        fn paddws_music_init() -> u32;
    }

    thread_local! {
        /// la musica e il buffer dei campioni chiesti dal browser
        static MUSIC: RefCell<Option<(Music, Vec<f32>)>> = const { RefCell::new(None) };
    }

    pub fn start() {
        let rate = unsafe { paddws_music_init() };
        if rate > 0 {
            let mut music = Music::new(rate);
            music.set_volume(music_volume(0));
            MUSIC.with(|m| *m.borrow_mut() = Some((music, Vec::new())));
        }
    }

    pub fn send(cmd: Cmd) {
        MUSIC.with(|m| {
            if let Some((music, _)) = m.borrow_mut().as_mut() {
                apply(music, cmd);
            }
        });
    }

    /// Chiamata dal browser: `frames` campioni mono; restituisce dove leggerli (nulla senza audio).
    #[unsafe(no_mangle)]
    pub extern "C" fn paddws_music_fill(frames: u32) -> *const f32 {
        MUSIC.with(|m| match m.borrow_mut().as_mut() {
            Some((music, buf)) => {
                buf.resize(frames as usize, 0.0);
                music.render(buf);
                buf.as_ptr()
            }
            None => std::ptr::null(),
        })
    }

    /// Versione del plugin JavaScript che si aspetta il gioco (controllata da miniquad).
    #[unsafe(no_mangle)]
    pub extern "C" fn paddws_sid_crate_version() -> u32 {
        1
    }
}

/// RMS della canzone `song` nei primi `seconds` secondi, solo sulle finestre da 50 ms che suonano.
#[cfg(test)]
fn song_level(song: u8, seconds: usize) -> f32 {
    let mut m = Music::new(48_000);
    m.set_song(song);
    let mut buf = vec![0.0f32; 48_000 * seconds];
    m.render(&mut buf);
    let (mut acc, mut n) = (0.0f64, 0usize);
    for w in buf.chunks(2400) {
        let e = w.iter().map(|v| (*v as f64).powi(2)).sum::<f64>();
        if (e / w.len() as f64).sqrt() > 0.005 {
            acc += e;
            n += w.len();
        }
    }
    if n == 0 { 0.0 } else { (acc / n as f64).sqrt() as f32 }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// La tabella dei livelli copre tutte le canzoni della ROM, con i valori misurati: se la ROM
    /// cambia, i nuovi valori si leggono nel messaggio dell'errore.
    #[test]
    fn song_levels_match_the_rom() {
        let rom = paddws_sid::Rom::builtin();
        assert_eq!(rom.names.len(), SONG_LEVELS.len(), "canzoni della ROM: {:?}", rom.names);
        for (i, name) in rom.names.iter().enumerate() {
            let level = song_level(i as u8 + 1, LEVEL_SECONDS);
            let (_, table) = SONG_LEVELS.iter().find(|(n, _)| n == name).expect("canzone senza livello");
            assert!((level - table).abs() < 0.002, "{name}: misurato {level:.3}, in tabella {table:.3}");
        }
    }

    #[test]
    fn game_level_is_the_mean_of_the_themes() {
        let themes: Vec<f32> = SONG_LEVELS.iter().filter(|(n, _)| n.starts_with("theme_")).map(|(_, l)| *l).collect();
        let mean = themes.iter().sum::<f32>() / themes.len() as f32;
        assert!((mean - GAME_LEVEL).abs() < 0.001, "media dei temi {mean:.3}");
    }
}
