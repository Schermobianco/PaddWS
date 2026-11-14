//! Musica in tempo reale: il player (`player`) che pilota il SID (`chip`), con l'uscita
//! ricampionata alla frequenza del dispositivo audio.
//!
//! Regole di tempo (da replicare uguali sul MiSTer e sul C64):
//!
//! - **Normale**: un passo del player ogni 20.000 cicli del SID a 1 MHz (50 Hz).
//! - **Match point** (`set_fast`): un passo ogni 16.000 cicli (62,5 Hz, tempo ×1,25), con le note
//!   alla stessa altezza. Nel MiSTer il divisore del frame del player conta fino a 319.999 invece
//!   di 399.999 (a 20 MHz); dove il player è legato al frame da 50 Hz (C64) si fanno 5 passi ogni
//!   4 frame, meglio con il passo in più a metà frame: stessa sequenza di scritture.
//! - **Rallentata** (`set_slow`, bullet time): come gli effetti rallentati del MiSTer (`fx_slow`),
//!   i canali della canzone sono serviti un passo su due e scrivono le frequenze dimezzate; al
//!   cambio, al passo dopo, le frequenze dei canali attivi della canzone si riscrivono subito
//!   (vedi `player`). Si somma al match point: un passo su due di quelli da 62,5 Hz.
//!
//! L'arpeggio avanza a ogni passo, come nel player Verilog. Gli effetti (`effect`, sulla voce 3)
//! hanno il loro passo, sempre a 50 Hz come nel MiSTer, anche al match point.
//!
//! Voci "da SID" (`voice`), come in pong_sid.v: il nome dell'avversario (`say`) prende il SID con
//! il trucco di $D418, e intanto le scritture del player si saltano (la canzone continua a contare)
//! e gli effetti del SID (`effect`) aspettano la fine; le voci di partita
//! (`call`) si sommano all'uscita come `(campione - 8) << 11`, sopra musica ed effetti. Volumi
//! (`set_volume`, `set_fx_volume`) come i guadagni per voce del MiSTer: voci 1 e 2 della musica, la 3
//! degli effetti mentre ne suona uno; con il nome dell'avversario le voci 2 e 3, che ne danno il DC,
//! degli effetti; le voci di partita degli effetti. Gli eventi delle voci cadono al ciclo giusto
//! anche dentro un campione d'uscita.
//!
//! Ricampionamento: ogni campione d'uscita è la media dei cicli del SID che copre (22 o 23 a
//! 44,1 kHz), come la registrazione del core simulato (`mister/sim/sid/render.cpp`): un filtro
//! anti-aliasing semplice, e lo stesso suono delle registrazioni. I passi del player cadono sul
//! confine del campione (al più 23 microsecondi di scarto, senza deriva).

use crate::chip::{CLOCK_HZ, Sid};
use crate::player::Player;
use crate::rom::Rom;
use crate::voice::{Call, CallVoice, NameVoice, VoiceRom};

/// Cicli del SID per passo del player: 50 Hz.
pub const STEP_CYCLES: u32 = 20_000;
/// Al match point: 62,5 Hz, tempo ×1,25.
pub const FAST_STEP_CYCLES: u32 = 16_000;
/// Uscita a 16 bit del SID in [-1, 1].
const SCALE: f32 = 1.0 / 32768.0;
/// Voce di partita: `(campione - 8) << 11` sulla scala a 16 bit del SID, come in pong_top.v.
const CALL_SCALE: f32 = 2048.0 * SCALE;

/// Volume come guadagno di una voce del SID (256 = 1).
fn gain(volume: f32) -> u32 {
    (volume.max(0.0) * 256.0).round() as u32
}

/// Il SID con il suo player e il ricampionatore.
#[derive(Clone, Debug)]
pub struct Music {
    player: Player,
    sid: Sid,
    rate: u32,
    /// resto dei cicli del SID per campione (in unità di 1/rate)
    frac: u32,
    /// cicli del SID al prossimo passo della canzone e degli effetti
    until_step: i64,
    until_fx: i64,
    fast: bool,
    volume: f32,
    fx_volume: f32,
    voices: VoiceRom,
    name: NameVoice,
    call: CallVoice,
    /// effetto chiesto mentre il nome dell'avversario ha il SID: parte alla fine
    pending_fx: Option<(u8, bool)>,
    /// passi fatti (per le prove)
    steps: u64,
}

impl Music {
    /// Musica con la ROM inclusa, uscita a `rate` Hz.
    pub fn new(rate: u32) -> Music {
        Music::with_rom(Rom::builtin(), rate)
    }

    pub fn with_rom(rom: Rom, rate: u32) -> Music {
        Music {
            player: Player::new(rom),
            sid: Sid::new(),
            rate: rate.max(1),
            frac: 0,
            until_step: 0,
            until_fx: 0,
            fast: false,
            volume: 1.0,
            fx_volume: 1.0,
            voices: VoiceRom::builtin(),
            name: NameVoice::default(),
            call: CallVoice::default(),
            pending_fx: None,
            steps: 0,
        }
    }

    pub fn rate(&self) -> u32 {
        self.rate
    }

    pub fn rom(&self) -> &Rom {
        self.player.rom()
    }

    /// Canzone (da 1; 0 = silenzio, con il rilascio delle note): riparte da capo al prossimo passo
    /// se cambia.
    pub fn set_song(&mut self, song: u8) {
        self.player.set_song(song);
    }

    pub fn song(&self) -> u8 {
        self.player.song()
    }

    /// Match point: tempo ×1,25, note alla stessa altezza. Vale dal passo dopo quello già in
    /// attesa.
    pub fn set_fast(&mut self, on: bool) {
        self.fast = on;
    }

    /// Bullet time: un passo su due, un'ottava sotto.
    pub fn set_slow(&mut self, on: bool) {
        self.player.set_slow(on);
    }

    /// Volume della musica (1 = il livello delle registrazioni del core simulato).
    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume;
        self.update_gains();
    }

    /// Volume degli effetti del SID e delle voci "da SID" (1 = come nel core simulato).
    pub fn set_fx_volume(&mut self, volume: f32) {
        self.fx_volume = volume;
        self.update_gains();
    }

    /// Effetto del SID sulla voce 3 per gli eventi del frame (bit come in `player::effect_of`: ne
    /// suona uno, per priorità, e interrompe quello in corso); con `slow` a metà velocità (bullet
    /// time). Mentre il nome dell'avversario ha il SID aspetta la fine.
    pub fn effect(&mut self, events: u8, slow: bool) {
        if self.name.on() {
            self.pending_fx = Some((events, slow));
            return;
        }
        let sid = &mut self.sid;
        self.player.effect(events, slow, &mut |r, v| sid.write(r, v));
        self.update_gains();
    }

    /// CHALLENGE: il nome dell'avversario `id` (`PaddleKind`) detto dal SID con il trucco di
    /// $D418; niente se la voce di prima ha ancora il SID.
    pub fn say(&mut self, id: u8) {
        let sid = &mut self.sid;
        self.name.start(&self.voices, id, &mut |r, v| sid.write(r, v));
        if self.name.on() {
            self.player.voice_has_sid();
        }
        self.update_gains();
    }

    /// Fine della presentazione: il nome dell'avversario si ferma (il DC scende con il rilascio).
    pub fn stop_voice(&mut self) {
        let sid = &mut self.sid;
        self.name.stop(&mut |r, v| sid.write(r, v));
    }

    /// Il nome dell'avversario ha il SID (anche durante attacco e rilascio del DC).
    pub fn voice_on(&self) -> bool {
        self.name.on()
    }

    /// Voce di partita, sommata all'uscita: interrompe quella in corso.
    pub fn call(&mut self, call: Call) {
        let id = self.voices.call_id(call);
        self.call.start(&self.voices, id);
    }

    /// Il nome della racchetta `id` (`PaddleKind`) sommato all'uscita come le voci di partita, senza
    /// il trucco di $D418: la musica continua. Interrompe la voce di partita in corso.
    pub fn call_name(&mut self, id: u8) {
        self.call.start(&self.voices, id);
    }

    pub fn voices(&self) -> &VoiceRom {
        &self.voices
    }

    /// Guadagni delle voci del SID, come `gain_1`-`gain_3` di pong_sid.v.
    fn update_gains(&mut self) {
        let (music, fx) = (gain(self.volume), gain(self.fx_volume));
        let name = self.name.on();
        let third = if name || self.player.effect_playing() { fx } else { music };
        self.sid.set_gains([music, if name { fx } else { music }, third]);
    }

    pub fn steps(&self) -> u64 {
        self.steps
    }

    /// Prossimo campione d'uscita.
    #[inline]
    fn next(&mut self) -> f32 {
        self.frac += CLOCK_HZ;
        let n = self.frac / self.rate;
        self.frac %= self.rate;
        let (song, fx) = (self.until_step <= 0, self.until_fx <= 0);
        if song || fx {
            // con il nome dell'avversario il player conta ma non scrive
            let (sid, name) = (&mut self.sid, self.name.on());
            self.player.step(song, fx, &mut |r, v| {
                if !name {
                    sid.write(r, v)
                }
            });
            if name {
                self.player.voice_has_sid();
            }
            self.update_gains();
            if song {
                self.steps += 1;
                self.until_step += if self.fast { FAST_STEP_CYCLES } else { STEP_CYCLES } as i64;
            }
            if fx {
                self.until_fx += STEP_CYCLES as i64;
            }
        }
        self.until_step -= n as i64;
        self.until_fx -= n as i64;
        if n == 0 {
            return 0.0;
        }
        // i cicli del campione, spezzati agli eventi delle voci
        let (mut left, mut sum, mut call) = (n, 0i64, 0i64);
        while left > 0 {
            let k = left.min(self.name.until()).min(self.call.until());
            sum += self.sid.clock(k);
            call += self.call.offset() as i64 * k as i64;
            left -= k;
            let was = self.name.on();
            let sid = &mut self.sid;
            self.name.advance(k, &self.voices, &mut |r, v| sid.write(r, v));
            self.call.advance(k, &self.voices);
            if was && !self.name.on() {
                self.update_gains();
                if let Some((events, slow)) = self.pending_fx.take() {
                    self.effect(events, slow);
                }
            }
        }
        (sum as f32 * SCALE + call as f32 * CALL_SCALE * self.fx_volume) / n as f32
    }

    /// Campioni mono in `out`.
    pub fn render(&mut self, out: &mut [f32]) {
        for s in out {
            *s = self.next();
        }
    }

    /// Somma i campioni a un buffer stereo interleaved (sinistro, destro).
    pub fn mix_stereo(&mut self, out: &mut [f32]) {
        for [left, right] in out.as_chunks_mut::<2>().0 {
            let s = self.next();
            *left += s;
            *right += s;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|s| s * s).sum::<f32>() / x.len() as f32).sqrt()
    }

    #[test]
    fn suona_e_tace() {
        let mut m = Music::new(44_100);
        m.set_song(1);
        let mut buf = vec![0.0; 44_100];
        m.render(&mut buf);
        assert!(rms(&buf) > 0.05, "{}", rms(&buf));
        assert!(buf.iter().all(|s| s.abs() <= 1.0));
        // 50 passi al secondo
        assert_eq!(m.steps(), 50);
        // silenzio: le note si rilasciano e l'uscita va a zero
        m.set_song(0);
        m.render(&mut buf);
        let tail = &buf[buf.len() - 4410..];
        assert!(rms(tail) < 1e-3, "{}", rms(tail));
    }

    /// Nome dell'avversario: il DC delle voci 2 e 3 a volume 8 (circa un quarto della scala), i
    /// campioni sopra, poi il SID torna al player e in silenzio; la canzone intanto non scrive.
    #[test]
    fn nome_dell_avversario() {
        let rate = 44_100;
        let at = |s: f64| (s * rate as f64) as usize;
        let mut m = Music::new(rate);
        m.set_song(2);
        let mut buf = vec![0.0; at(0.43)];
        m.render(&mut buf);
        m.say(2);
        assert!(m.voice_on());
        let mut buf = vec![0.0; at(m.voices().seconds(2) + 0.2)];
        m.render(&mut buf);
        let play = &buf[at(0.1)..at(0.3)];
        let mean = play.iter().sum::<f32>() / play.len() as f32;
        let dev = rms(&play.iter().map(|s| s - mean).collect::<Vec<_>>());
        assert!((0.15..0.35).contains(&mean), "{mean}");
        assert!(dev > 0.01, "{dev}");
        assert!(!m.voice_on());
        // musica ferma (canzone 0): dopo il rilascio tutto tace
        m.set_song(0);
        let mut buf = vec![0.0; at(0.5)];
        m.render(&mut buf);
        assert!(rms(&buf[at(0.4)..]) < 1e-3, "{}", rms(&buf[at(0.4)..]));
    }

    /// Al match point la canzone accelera ma gli effetti restano a 50 Hz, come nel MiSTer: senza
    /// canzone l'effetto del punto suona identico.
    #[test]
    fn effetti_a_50_hz_al_match_point() {
        let render = |fast: bool| {
            let mut m = Music::new(44_100);
            m.set_fast(fast);
            m.effect(1 << 3, false);
            let mut buf = vec![0.0; 44_100];
            m.render(&mut buf);
            buf
        };
        let (normal, fast) = (render(false), render(true));
        assert!(rms(&normal) > 0.01);
        assert_eq!(normal, fast);
    }

    /// Voce di partita: si somma all'uscita e segue il volume degli effetti.
    #[test]
    fn voce_di_partita() {
        let mut m = Music::new(44_100);
        m.call(Call::Go);
        let mut a = vec![0.0; 4410 * 3];
        m.render(&mut a);
        assert!(rms(&a) > 0.02, "{}", rms(&a));
        let mut m = Music::new(44_100);
        m.set_fx_volume(0.25);
        m.call(Call::Go);
        let mut b = vec![0.0; 4410 * 3];
        m.render(&mut b);
        assert!((rms(&b) / rms(&a) - 0.25).abs() < 1e-3);
    }

    /// Match point: 62,5 passi al secondo; rallentata: i canali della canzone a metà.
    #[test]
    fn tempi() {
        let mut m = Music::new(48_000);
        m.set_song(7);
        m.set_fast(true);
        let mut buf = vec![0.0; 48_000];
        m.render(&mut buf);
        assert_eq!(m.steps(), 63); // il primo passo è al campione 0
        let mut normal = Music::new(48_000);
        normal.set_song(7);
        let mut slow = Music::new(48_000);
        slow.set_song(7);
        slow.set_slow(true);
        let (mut a, mut b) = (vec![0.0; 9600], vec![0.0; 9600]);
        normal.render(&mut a);
        slow.render(&mut b);
        // un'ottava sotto: il numero di passaggi per lo zero si dimezza circa
        let crossings = |x: &[f32]| x.windows(2).filter(|w| (w[0] < 0.0) != (w[1] < 0.0)).count();
        let (ca, cb) = (crossings(&a), crossings(&b));
        assert!(cb * 10 < ca * 7, "{ca} {cb}");
    }
}
