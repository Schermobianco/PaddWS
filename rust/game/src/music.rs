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

fn apply(m: &mut Music, cmd: Cmd) {
    match cmd {
        Cmd::Song(n) => m.set_song(n),
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
            music.set_volume(VOLUME);
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

    use super::{Cmd, Music, VOLUME, apply};

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
            music.set_volume(VOLUME);
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
