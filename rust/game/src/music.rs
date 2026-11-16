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
//!
//! Oscilloscopi (la rete di OMEGA, il JUKEBOX): con `set_scope` acceso il SID tiene l'uscita di
//! ogni voce (`paddws_sid::Scope`) e, dopo ogni blocco suonato, i campioni nuovi passano in
//! `SCOPE`, da dove il gioco legge la finestra che si sta ascoltando (`SidMusic::scope_window`).

use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

use paddws_sid::{Call, Music, SCOPE_LEN};

use crate::platform::Instant;

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

/// Ritardo stimato fra il campione appena prodotto e quello che si sente (il buffer del mixer,
/// circa 90 ms, vedi sopra).
const LATENCY: f64 = 0.09;

/// Oscilloscopi richiesti dal gioco (letto dal thread audio).
static SCOPE_ON: AtomicBool = AtomicBool::new(false);
/// Ultimi campioni di ogni voce, copiati dal thread audio dopo ogni blocco.
static SCOPE: Mutex<Option<Shared>> = Mutex::new(None);

/// Campioni delle voci condivisi con il gioco: un buffer circolare per voce come quello del SID,
/// con l'istante dell'ultima copia per sapere quale campione si sente adesso.
struct Shared {
    voices: [Vec<f32>; 3],
    written: u64,
    rate: u32,
    at: Instant,
}

/// Dopo un blocco suonato: accende o spegne gli oscilloscopi del SID come chiede il gioco e copia
/// i campioni nuovi (al più un buffer) in `SCOPE`.
fn share_scope(m: &mut Music) {
    let on = SCOPE_ON.load(Ordering::Relaxed);
    m.set_scope(on);
    let Ok(mut shared) = SCOPE.lock() else { return };
    let Some(scope) = m.scope() else {
        *shared = None;
        return;
    };
    let rate = m.rate();
    let sh = shared.get_or_insert_with(|| Shared {
        voices: std::array::from_fn(|_| vec![0.0; SCOPE_LEN]),
        written: 0,
        rate,
        at: Instant::now(),
    });
    let end = scope.written();
    let from = sh.written.max(end.saturating_sub(SCOPE_LEN as u64));
    for i in from..end {
        let k = (i % SCOPE_LEN as u64) as usize;
        for (v, voice) in sh.voices.iter_mut().enumerate() {
            voice[k] = scope.sample(v, i);
        }
    }
    (sh.written, sh.rate, sh.at) = (end, rate, Instant::now());
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
                share_scope(&mut music);
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

    /// CHALLENGE: il SID dice il nome dell'avversario (la voce `PaddleKind`, o quella di OMEGA), se
    /// non sta già parlando.
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

    /// Oscilloscopi delle voci per la scena (la rete di OMEGA, il JUKEBOX): costano poco, ma solo
    /// quando servono.
    pub fn set_scope(&self, on: bool) {
        SCOPE_ON.store(on, Ordering::Relaxed);
    }

    /// Frequenza dei campioni degli oscilloscopi (0 senza audio o con gli oscilloscopi spenti).
    pub fn scope_rate(&self) -> u32 {
        SCOPE.lock().ok().and_then(|s| s.as_ref().map(|s| s.rate)).unwrap_or(0)
    }

    /// `out.len()` campioni della voce `voice` (0-2) da `start` (in campioni rispetto a quello che
    /// si sente adesso: negativo nel passato) a scala piena 1 per l'uscita intera; dove non ci sono
    /// campioni restano 0. Il futuro si può chiedere fino al buffer del mixer (`LATENCY`).
    pub fn scope_window(&self, voice: usize, start: i64, out: &mut [f32]) {
        out.fill(0.0);
        let Ok(shared) = SCOPE.lock() else { return };
        let Some(sh) = shared.as_ref() else { return };
        let since = Instant::now().checked_duration_since(sh.at).map_or(0.0, |d| d.as_secs_f64());
        let now = sh.written as i64 + ((since - LATENCY) * sh.rate as f64) as i64;
        // si legge solo quello che c'è: la finestra non va oltre l'ultimo campione scritto
        let first = (now + start).min(sh.written as i64 - out.len() as i64);
        let oldest = sh.written as i64 - SCOPE_LEN as i64;
        for (k, o) in out.iter_mut().enumerate() {
            let i = first + k as i64;
            if i >= oldest.max(0) && i < sh.written as i64 {
                *o = sh.voices[voice][(i as u64 % SCOPE_LEN as u64) as usize];
            }
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

    use super::{Cmd, Music, apply, share_scope};

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
                share_scope(music);
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
