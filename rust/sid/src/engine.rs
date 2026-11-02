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
//! L'arpeggio avanza a ogni passo, come nel player Verilog. Gli effetti del gioco Rust restano i
//! campioni WAV registrati dal core simulato, con i loro tempi.
//!
//! Ricampionamento: ogni campione d'uscita è la media dei cicli del SID che copre (22 o 23 a
//! 44,1 kHz), come la registrazione del core simulato (`mister/sim/sid/render.cpp`): un filtro
//! anti-aliasing semplice, e lo stesso suono delle registrazioni. I passi del player cadono sul
//! confine del campione (al più 23 microsecondi di scarto, senza deriva).

use crate::chip::{CLOCK_HZ, Sid};
use crate::player::Player;
use crate::rom::Rom;

/// Cicli del SID per passo del player: 50 Hz.
pub const STEP_CYCLES: u32 = 20_000;
/// Al match point: 62,5 Hz, tempo ×1,25.
pub const FAST_STEP_CYCLES: u32 = 16_000;
/// Uscita a 16 bit del SID in [-1, 1].
const SCALE: f32 = 1.0 / 32768.0;

/// Il SID con il suo player e il ricampionatore.
#[derive(Clone, Debug)]
pub struct Music {
    player: Player,
    sid: Sid,
    rate: u32,
    /// resto dei cicli del SID per campione (in unità di 1/rate)
    frac: u32,
    /// cicli del SID al prossimo passo del player
    until_step: i64,
    fast: bool,
    volume: f32,
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
            fast: false,
            volume: 1.0,
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

    /// Volume dell'uscita (1 = il livello delle registrazioni del core simulato).
    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume;
    }

    /// Effetto del SID sulla voce 3 (eventi come in `player::effect_of`): il gioco usa i campioni
    /// WAV, questo serve alle prove.
    pub fn effect(&mut self, events: u8, slow: bool) {
        let sid = &mut self.sid;
        self.player.effect(events, slow, &mut |r, v| sid.write(r, v));
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
        if self.until_step <= 0 {
            let sid = &mut self.sid;
            self.player.tick(&mut |r, v| sid.write(r, v));
            self.steps += 1;
            self.until_step += if self.fast { FAST_STEP_CYCLES } else { STEP_CYCLES } as i64;
        }
        self.until_step -= n as i64;
        if n == 0 {
            return 0.0;
        }
        self.sid.clock(n) as f32 / n as f32 * SCALE * self.volume
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
