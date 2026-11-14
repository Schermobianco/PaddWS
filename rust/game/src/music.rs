//! Musica del SID suonata in tempo reale dal SID Rust (`paddws-sid`): il player legge la ROM della
//! musica come quello del MiSTer e del C64, quindi il tempo può cambiare in partita (match point,
//! bullet time) senza registrazioni a parte. Anche effetti e voci "da SID" passano da qui, come
//! nel MiSTer: gli effetti sulla voce 3 (uno alla volta), il nome dell'avversario con il trucco di
//! $D418 (intanto la musica tace) e le voci di partita sommate all'uscita, al volume degli effetti.
//!
//! - Nativo (Windows, Linux, Raspberry): la sintesi gira nel thread audio, dentro il mixer di
//!   quad-snd (`vendor/quad-snd`, `set_stream`), sopra gli effetti; i comandi arrivano con un
//!   canale. Un solo dispositivo audio, come prima: la latenza è quella del mixer (circa 90 ms).
//! - Web: il plugin JavaScript `rust/web/sid_audio.js` chiede i campioni con uno ScriptProcessor
//!   nello stesso AudioContext di quad-snd (blocchi da 2048, circa 45 ms); l'audio parte al primo
//!   gesto dell'utente, come gli effetti. Lo ScriptProcessor funziona anche fuori da https.

use paddws_sid::{Call, Music};

/// Volume della musica rispetto agli effetti (come i vecchi OGG suonati a 0,8), con MUSIC VOLUME
/// al 100%.
pub const VOLUME: f32 = 0.8;

/// Frequenza del mixer nativo di quad-snd.
#[cfg(not(target_arch = "wasm32"))]
const NATIVE_RATE: u32 = 44_100;

#[derive(Clone, Copy, Debug)]
enum Cmd {
    Song(u8),
    Fast(bool),
    Slow(bool),
    /// volume finale (`VOLUME` per il guadagno di MUSIC VOLUME)
    Volume(f32),
    /// volume delle voci (il guadagno di EFFECTS VOLUME)
    FxVolume(f32),
    /// CHALLENGE: il nome dell'avversario (`PaddleKind`), e la sua fine con la presentazione
    Say(u8),
    StopVoice,
    /// voce di partita
    Call(Call),
    /// nome della racchetta (`PaddleKind`) come voce di partita, sopra la musica
    CallName(u8),
    /// effetto per i bit degli eventi del frame, rallentato o no
    Effect(u8, bool),
}

fn apply(m: &mut Music, cmd: Cmd) {
    match cmd {
        Cmd::Song(n) => m.set_song(n),
        Cmd::Fast(on) => m.set_fast(on),
        Cmd::Slow(on) => m.set_slow(on),
        Cmd::Volume(v) => m.set_volume(v),
        Cmd::FxVolume(v) => m.set_fx_volume(v),
        Cmd::Say(id) => m.say(id),
        Cmd::StopVoice => m.stop_voice(),
        Cmd::Call(c) => m.call(c),
        Cmd::CallName(id) => m.call_name(id),
        Cmd::Effect(events, slow) => m.effect(events, slow),
    }
}

/// Comandi alla musica che suona nel thread audio (o nel callback del browser).
pub struct SidMusic {
    #[cfg(not(target_arch = "wasm32"))]
    tx: std::sync::mpsc::Sender<Cmd>,
    song: u8,
    fast: bool,
    slow: bool,
    gain: f32,
    fx_gain: f32,
}

impl SidMusic {
    /// Avvia la sorgente continua (in silenzio fino alla prima canzone), con i guadagni `gain` di
    /// MUSIC VOLUME e `fx_gain` di EFFECTS VOLUME (da 0 a 1, `config::volume_gain`).
    pub fn start(gain: f32, fx_gain: f32) -> SidMusic {
        #[cfg(not(target_arch = "wasm32"))]
        let tx = {
            let (tx, rx) = std::sync::mpsc::channel::<Cmd>();
            let mut music = Music::new(NATIVE_RATE);
            music.set_volume(VOLUME * gain);
            music.set_fx_volume(fx_gain);
            quad_snd::set_stream(Some(Box::new(move |buffer: &mut [f32]| {
                while let Ok(cmd) = rx.try_recv() {
                    apply(&mut music, cmd);
                }
                music.mix_stereo(buffer);
            })));
            tx
        };
        #[cfg(target_arch = "wasm32")]
        web::start(VOLUME * gain, fx_gain);
        SidMusic {
            #[cfg(not(target_arch = "wasm32"))]
            tx,
            song: 0,
            fast: false,
            slow: false,
            gain,
            fx_gain,
        }
    }

    /// Guadagno di MUSIC VOLUME (da 0 a 1): vale subito, anche per la canzone che suona.
    pub fn set_gain(&mut self, gain: f32) {
        if gain != self.gain {
            self.gain = gain;
            self.send(Cmd::Volume(VOLUME * gain));
        }
    }

    /// Guadagno di EFFECTS VOLUME (da 0 a 1) per le voci: vale subito.
    pub fn set_fx_gain(&mut self, gain: f32) {
        if gain != self.fx_gain {
            self.fx_gain = gain;
            self.send(Cmd::FxVolume(gain));
        }
    }

    /// CHALLENGE: il SID dice il nome dell'avversario (`PaddleKind`), se non sta già parlando.
    pub fn say(&self, kind: u8) {
        self.send(Cmd::Say(kind));
    }

    /// Fine della presentazione: il nome dell'avversario si ferma, se c'è ancora.
    pub fn stop_voice(&self) {
        self.send(Cmd::StopVoice);
    }

    /// Effetto del SID sulla voce 3 per i bit degli eventi (`paddws_sid::player::effect_of`): ne
    /// suona uno per priorità e interrompe quello in corso; `slow` nel bullet time.
    pub fn effect(&self, events: u8, slow: bool) {
        self.send(Cmd::Effect(events, slow));
    }

    /// Voce di partita (urli delle mosse, READY, GO, YOU WIN, PERFECT): interrompe quella in corso.
    pub fn call(&self, call: Call) {
        self.send(Cmd::Call(call));
    }

    /// Nome della racchetta (`PaddleKind`) sommato all'uscita come le voci di partita: la musica
    /// non si ferma; interrompe la voce in corso.
    pub fn call_name(&self, kind: u8) {
        self.send(Cmd::CallName(kind));
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

    use super::{Cmd, Music, apply};

    unsafe extern "C" {
        /// Crea lo ScriptProcessor (`rust/web/sid_audio.js`) e restituisce la frequenza del
        /// contesto audio (0 se nel browser non c'è l'audio).
        fn paddws_music_init() -> u32;
    }

    thread_local! {
        /// la musica e il buffer dei campioni chiesti dal browser
        static MUSIC: RefCell<Option<(Music, Vec<f32>)>> = const { RefCell::new(None) };
    }

    pub fn start(volume: f32, fx_volume: f32) {
        let rate = unsafe { paddws_music_init() };
        if rate > 0 {
            let mut music = Music::new(rate);
            music.set_volume(volume);
            music.set_fx_volume(fx_volume);
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
