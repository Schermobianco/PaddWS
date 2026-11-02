//! SID semplificato, scritto per PADD WS: solo quello che usano le nostre musiche, con lo stesso
//! comportamento del SID 8580 del core MiSTer (`mister/rtl/sid`, quello delle registrazioni).
//!
//! - Tre voci con oscillatore a 24 bit (frequenza a 16 bit) a 1 MHz.
//! - Forme d'onda triangolo, dente di sega, impulso (larghezza a 12 bit) e rumore (LFSR a 23 bit
//!   che avanza sul fronte di salita del bit 19 dell'oscillatore, come il chip). Le forme d'onda
//!   combinate danno silenzio; ring, sync e il bit di test non ci sono (il player non li usa).
//! - Inviluppo ADSR con le tabelle dei tempi del chip, il contatore esponenziale del decadimento
//!   e del rilascio, il contatore a 15 bit che fa ripartire il giro quando il periodo scende sotto
//!   il conteggio (il ritardo dell'ADSR del chip vero).
//! - DAC lineari e senza offset come nell'8580; senza forma d'onda il DAC tiene l'ultimo valore
//!   per 5 secondi.
//! - Il filtro dell'8580 (`Filter`): state variable a 12 dB/ottava con le tre uscite, la curva
//!   lineare del taglio e la risonanza dell'8580, port del modo 8580 di
//!   `mister/rtl/sid/sid_filter.sv` con la stessa aritmetica intera, un passo ogni 2 cicli. Gira
//!   solo quando serve (voci nel filtro, o la coda di un'uscita accesa): senza, non costa niente.
//!   C'è anche il bit "voce 3 spenta" di $D418; l'ingresso esterno no.
//!
//! L'uscita di un ciclo è quella di `pong_sid.v`: senza filtro `volume * (v1 + v2 + v3) / 1024`,
//! dove ogni voce è `(forma d'onda a 12 bit - 0x800) * inviluppo`, a 16 bit; con il filtro
//! `volume * (diretto / 1024 + filtro / 8)` (vedi `Sid::clock_filtered`). `clock` restituisce la
//! somma di `n` cicli, per fare la media su ogni campione d'uscita (il filtro anti-aliasing a
//! finestra rettangolare della registrazione del core simulato, `mister/sim/sid/render.cpp`). Per
//! leggerezza le forme d'onda si calcolano ciclo per ciclo, l'inviluppo a salti (resta fermo
//! dentro un campione).

/// Clock del SID: 1 MHz come nel core MiSTer (`SID_CLOCK` di tools/gen_sid_music.py).
pub const CLOCK_HZ: u32 = 1_000_000;

const OSC_MASK: u32 = 0xFF_FFFF;
/// cicli per passo dell'inviluppo, per i valori 0-15 di attacco, decadimento e rilascio
const RATES: [u16; 16] = [
    8, 31, 62, 94, 148, 219, 266, 312, 391, 976, 1953, 3125, 3906, 11719, 19531, 31250,
];
/// senza forma d'onda il DAC dell'8580 tiene l'ultimo valore per circa 5 secondi
const DAC_HOLD_CYCLES: u32 = 5_000_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Env {
    Release,
    Attack,
    DecaySustain,
}

#[derive(Clone, Debug)]
struct Voice {
    freq: u32,
    pw: u32,
    ctrl: u8,
    ad: u8,
    sr: u8,
    osc: u32,
    lfsr: u32,
    env: u8,
    state: Env,
    rate_counter: u16,
    exp_counter: u8,
    exp_period: u8,
    hold_zero: bool,
    /// ultimo valore del DAC (forma d'onda - 0x800) e cicli per cui lo tiene senza forma d'onda
    dac: i32,
    hold: u32,
}

impl Voice {
    fn new() -> Voice {
        Voice {
            freq: 0,
            pw: 0,
            ctrl: 0,
            ad: 0,
            sr: 0,
            osc: 0,
            lfsr: 0x7F_FFFF,
            env: 0,
            state: Env::Release,
            rate_counter: 0,
            exp_counter: 0,
            exp_period: 0,
            hold_zero: true,
            dac: 0,
            hold: 0,
        }
    }

    fn set_ctrl(&mut self, value: u8) {
        let (was, gate) = (self.ctrl & 1 != 0, value & 1 != 0);
        if !was && gate {
            self.state = Env::Attack;
            self.hold_zero = false;
        } else if was && !gate {
            self.state = Env::Release;
        }
        self.ctrl = value;
    }

    fn rate_period(&self) -> u16 {
        RATES[match self.state {
            Env::Attack => self.ad >> 4,
            Env::DecaySustain => self.ad & 0x0F,
            Env::Release => self.sr & 0x0F,
        } as usize]
    }

    /// Un passo dell'inviluppo (il contatore del periodo è arrivato in fondo).
    fn env_step(&mut self) {
        let old = self.exp_counter;
        self.exp_counter = (old + 1) & 0x1F;
        if self.state != Env::Attack && old != self.exp_period {
            return;
        }
        self.exp_counter = 0;
        let env = self.env;
        match self.state {
            Env::Attack => {
                self.env = env.wrapping_add(1);
                if env == 0xFE {
                    self.state = Env::DecaySustain;
                }
            }
            Env::DecaySustain => {
                if env != (self.sr >> 4) * 0x11 && !self.hold_zero {
                    self.env = env.wrapping_sub(1);
                }
            }
            Env::Release => {
                if !self.hold_zero {
                    self.env = env.wrapping_sub(1);
                }
            }
        }
        if self.state != Env::Attack && env == 1 {
            self.hold_zero = true;
        }
        // il periodo esponenziale segue i livelli in cui passa l'inviluppo
        self.exp_period = match self.env {
            0xFF | 0x00 => 0,
            0x5D => 1,
            0x36 => 3,
            0x1A => 7,
            0x0E => 15,
            0x06 => 29,
            _ => self.exp_period,
        };
    }

    /// Inviluppo avanti di `n` cicli, a salti fino al prossimo passo.
    fn env_clock(&mut self, mut n: u32) {
        while n > 0 {
            let period = self.rate_period();
            // cicli prima di quello in cui il contatore vale il periodo (a 15 bit: se il periodo
            // è sceso sotto il conteggio, prima si fa il giro)
            let dist = (period.wrapping_sub(self.rate_counter) & 0x7FFF) as u32;
            if n <= dist {
                self.rate_counter = (self.rate_counter as u32 + n) as u16 & 0x7FFF;
                return;
            }
            n -= dist + 1;
            self.rate_counter = 0;
            self.env_step();
        }
    }

    fn lfsr_shift(&mut self, times: u32) {
        for _ in 0..times {
            let bit = (self.lfsr >> 22 ^ self.lfsr >> 17) & 1;
            self.lfsr = (self.lfsr << 1 | bit) & 0x7F_FFFF;
        }
    }

    /// Uscita del rumore: otto bit dell'LFSR in cima ai 12.
    fn noise(&self) -> u32 {
        let l = self.lfsr;
        ((l >> 20 & 1) << 11)
            | ((l >> 18 & 1) << 10)
            | ((l >> 14 & 1) << 9)
            | ((l >> 11 & 1) << 8)
            | ((l >> 9 & 1) << 7)
            | ((l >> 5 & 1) << 6)
            | ((l >> 2 & 1) << 5)
            | ((l & 1) << 4)
    }

    /// Somma dell'uscita della voce in `n` cicli (DAC per inviluppo), e voce avanti di `n` cicli.
    fn clock(&mut self, n: u32) -> i64 {
        self.run::<false>(n, &mut [])
    }

    /// Come `clock`, e in più somma l'uscita di ogni ciclo in `out` (lungo almeno `n`), per il
    /// filtro.
    fn clock_into(&mut self, n: u32, out: &mut [i32]) -> i64 {
        self.run::<true>(n, out)
    }

    fn run<const PER_CYCLE: bool>(&mut self, n: u32, out: &mut [i32]) -> i64 {
        let env = self.env as i64;
        let e32 = self.env as i32;
        let f = self.freq;
        let start = self.osc;
        let wave = self.ctrl >> 4;
        // oscillatore dopo `n` cicli
        let end = start as u64 + n as u64 * f as u64;
        let mut sum = 0;
        let mut lfsr_done = false;
        // uscita del ciclo i (forma d'onda a 12 bit d), solo per il filtro
        let mut put = |i: u32, d: u32| {
            if PER_CYCLE {
                out[i as usize] += (d as i32 - 0x800) * e32;
            }
        };
        if env == 0 || !matches!(wave, 0 | 1 | 2 | 4 | 8) {
            // voce muta (o forma d'onda combinata, che qui tace): l'oscillatore e l'LFSR
            // avanzano lo stesso
            self.osc = (end & OSC_MASK as u64) as u32;
        } else {
            let mut osc = start;
            let dacs: u64 = match wave {
                // triangolo: il dente di sega ribaltato nella seconda metà, un bit più in alto
                1 => {
                    let mut s = 0u64;
                    for i in 0..n {
                        osc = (osc + f) & OSC_MASK;
                        let t = osc >> 12 & 0x7FF;
                        let d = (if osc & 0x80_0000 != 0 { t ^ 0x7FF } else { t }) << 1;
                        s += d as u64;
                        put(i, d);
                    }
                    s
                }
                2 => {
                    let mut s = 0u64;
                    for i in 0..n {
                        osc = (osc + f) & OSC_MASK;
                        let d = osc >> 12;
                        s += d as u64;
                        put(i, d);
                    }
                    s
                }
                4 => {
                    let mut high = 0u64;
                    for i in 0..n {
                        osc = (osc + f) & OSC_MASK;
                        let h = osc >> 12 >= self.pw;
                        high += h as u64;
                        put(i, if h { 0xFFF } else { 0 });
                    }
                    high * 0xFFF
                }
                8 => {
                    // il rumore cambia sul fronte di salita del bit 19: qui ciclo per ciclo
                    let mut s = 0u64;
                    for i in 0..n {
                        let next = (osc + f) & OSC_MASK;
                        if !osc & next & 0x8_0000 != 0 {
                            self.lfsr_shift(1);
                        }
                        osc = next;
                        let d = self.noise();
                        s += d as u64;
                        put(i, d);
                    }
                    lfsr_done = true;
                    s
                }
                // senza forma d'onda il DAC tiene l'ultimo valore, poi va a zero
                _ => {
                    osc = (end & OSC_MASK as u64) as u32;
                    let held = n.min(self.hold);
                    if PER_CYCLE {
                        for i in 0..held {
                            put(i, (self.dac + 0x800) as u32);
                        }
                    }
                    (self.dac + 0x800) as u64 * held as u64 + 0x800 * (n - held) as u64
                }
            };
            self.osc = osc;
            sum = (dacs as i64 - 0x800 * n as i64) * env;
        }
        if wave == 0 {
            self.hold = self.hold.saturating_sub(n);
            if self.hold == 0 {
                self.dac = 0;
            }
        } else {
            self.dac = self.wave_now() as i32 - 0x800;
            self.hold = DAC_HOLD_CYCLES;
        }
        if !lfsr_done {
            // fronti di salita del bit 19 nel tratto percorso (incrementi sotto 2^19: uno per giro)
            let edges = ((end + 0x8_0000) >> 20) - ((start as u64 + 0x8_0000) >> 20);
            self.lfsr_shift(edges as u32);
        }
        self.env_clock(n);
        sum
    }

    /// Forma d'onda a 12 bit all'oscillatore attuale (per il valore tenuto dal DAC).
    fn wave_now(&self) -> u32 {
        let osc = self.osc;
        match self.ctrl >> 4 {
            1 => {
                let t = osc >> 12 & 0x7FF;
                (if osc & 0x80_0000 != 0 { t ^ 0x7FF } else { t }) << 1
            }
            2 => osc >> 12,
            4 => {
                if osc >> 12 >= self.pw {
                    0xFFF
                } else {
                    0
                }
            }
            8 => self.noise(),
            _ => 0,
        }
    }
}

/// 1/Q del filtro dell'8580 (<< 10) per la risonanza 0-15: 2^((4 - res) / 8), come la tabella
/// di `sid_filter.sv` in modo 8580.
const Q_8580: [i32; 16] = [
    1448, 1328, 1218, 1117, 1024, 939, 861, 790, 724, 664, 609, 558, 512, 470, 431, 395,
];
/// Cicli per blocco del filtro: le voci danno l'uscita ciclo per ciclo in un buffer lungo così,
/// poi il filtro lo legge.
const BLOCK: usize = 64;
/// Sotto questa ampiezza lo stato del filtro senza voci in ingresso si considera spento.
const FILTER_QUIET: i32 = 8;
/// Il filtro fa un passo ogni 2^FILTER_DECIM cicli (500 kHz), con w0 moltiplicato per lo stesso
/// fattore e l'ingresso medio di quei cicli: è una catena di moltiplicazioni che dipendono l'una
/// dall'altra, e un passo per ciclo costa di più. Contro le registrazioni del core lo spettro per
/// ottave resta entro 0,3 dB (con un passo per ciclo è identico, con uno ogni 4 cicli arriva a
/// 0,9 dB sopra i 4 kHz).
const FILTER_DECIM: u32 = 1;

fn clamp18(x: i32) -> i32 {
    x.clamp(-0x2_0000, 0x1_FFFF)
}

fn clamp16(x: i32) -> i32 {
    x.clamp(-0x8000, 0x7FFF)
}

/// Il filtro dell'8580: state variable a 12 dB/ottava (passa-basso, passa-banda, passa-alto), port
/// del modo 8580 di `mister/rtl/sid/sid_filter.sv` (da reDIP-SID) con la stessa aritmetica intera.
/// Un passo ogni 2 cicli (`FILTER_DECIM`; il Verilog ne fa uno per ciclo a 1 MHz); stato a 18 bit (2 bit frazionari in più del segnale);
/// w0 = 5 · taglio, cioè circa 6,07 Hz per passo del registro a 11 bit, lineare come nell'8580
/// (da 0 a 12,4 kHz); 1/Q = 2^((4 - res) / 8).
#[derive(Clone, Debug, Default)]
struct Filter {
    /// taglio a 11 bit ($D415 i 3 bit bassi, $D416 gli 8 alti)
    fc: u16,
    /// $D417: risonanza (bit 4-7) e voci nel filtro (bit 0-2; il 3, l'ingresso esterno, non c'è)
    res_filt: u8,
    /// bit 4-7 di $D418: passa-basso, passa-banda, passa-alto, voce 3 spenta
    mode: u8,
    lp: i32,
    bp: i32,
    hp: i32,
    /// somma dell'ingresso dei cicli del passo in corso, cicli contati, uscita dell'ultimo passo
    acc: i32,
    phase: u32,
    tap: i32,
}

impl Filter {
    /// Il filtro lavora: voci nel filtro, oppure un'uscita accesa con lo stato che ancora suona.
    fn busy(&self) -> bool {
        self.res_filt & 7 != 0
            || (self.mode & 7 != 0 && (self.lp.abs() | self.bp.abs() | self.hp.abs()) >= FILTER_QUIET)
    }

    /// Spento: stato a zero.
    fn clear(&mut self) {
        (self.lp, self.bp, self.hp, self.acc, self.phase, self.tap) = (0, 0, 0, 0, 0, 0);
    }

    /// Un passo: ingresso `vi` (somma delle voci nel filtro >> 5), uscita delle prese scelte a 16
    /// bit. `w0 * x >> shift` è `w0 << FILTER_DECIM` per `x`, `>> 17` come nel Verilog.
    #[inline(always)]
    fn step(&mut self, w0: i32, q: i32, vi: i32) -> i32 {
        const SHIFT: u32 = 17 - FILTER_DECIM;
        // vlp = vlp - w0*vbp; vbp = vbp - w0*vhp; vhp = 1/Q*vbp - vlp - vi
        let lp = clamp18(self.lp + ((-(w0 * self.bp)) >> SHIFT));
        let bp = clamp18(self.bp + ((-(w0 * self.hp)) >> SHIFT));
        let o = q * bp - ((lp + vi) << 10);
        // o[10 +: 19] nel Verilog: 19 bit con il segno, poi a 18
        let hp = clamp18(((o >> 10) << 13) >> 13);
        self.lp = lp;
        self.bp = bp;
        self.hp = hp;
        let mut tap = 0;
        if self.mode & 1 != 0 {
            tap += lp >> 2;
        }
        if self.mode & 2 != 0 {
            tap += bp >> 2;
        }
        if self.mode & 4 != 0 {
            tap += hp >> 2;
        }
        clamp16(tap)
    }
}

/// Il SID: tre voci, il filtro e il volume.
#[derive(Clone, Debug)]
pub struct Sid {
    voices: [Voice; 3],
    volume: u8,
    filter: Filter,
}

impl Default for Sid {
    fn default() -> Self {
        Sid::new()
    }
}

impl Sid {
    /// SID dopo il reset: registri a zero, inviluppi a zero, LFSR tutto a uno.
    pub fn new() -> Sid {
        Sid {
            voices: [Voice::new(), Voice::new(), Voice::new()],
            volume: 0,
            filter: Filter::default(),
        }
    }

    /// Scrittura di un registro (0-0x18).
    pub fn write(&mut self, reg: u8, value: u8) {
        let f = &mut self.filter;
        match reg {
            0x15 => f.fc = (f.fc & 0x7F8) | (value & 7) as u16,
            0x16 => f.fc = (f.fc & 7) | (value as u16) << 3,
            0x17 => f.res_filt = value,
            0x18 => {
                self.volume = value & 0x0F;
                f.mode = value >> 4;
            }
            0..=20 => {
                let v = &mut self.voices[reg as usize / 7];
                match reg % 7 {
                    0 => v.freq = (v.freq & 0xFF00) | value as u32,
                    1 => v.freq = (v.freq & 0x00FF) | (value as u32) << 8,
                    2 => v.pw = (v.pw & 0xF00) | value as u32,
                    3 => v.pw = (v.pw & 0x0FF) | ((value & 0x0F) as u32) << 8,
                    4 => v.set_ctrl(value),
                    5 => v.ad = value,
                    _ => v.sr = value,
                }
            }
            _ => {}
        }
    }

    /// Avanza di `n` cicli e restituisce la somma dell'uscita in quei cicli, in unità di un
    /// campione a 16 bit (diviso per `n` è la media).
    pub fn clock(&mut self, n: u32) -> i64 {
        if self.filter.busy() {
            let mut sum = 0;
            let mut left = n;
            while left > 0 {
                let k = left.min(BLOCK as u32);
                sum += self.clock_filtered(k as usize);
                left -= k;
            }
            return sum;
        }
        // senza filtro: lo stato rimasto si azzera (nel chip decade in pochi millisecondi)
        let f = &mut self.filter;
        f.clear();
        let off3 = f.mode & 8 != 0;
        let mut sum = 0;
        for (i, v) in self.voices.iter_mut().enumerate() {
            let s = v.clock(n);
            if !(i == 2 && off3) {
                sum += s;
            }
        }
        sum * self.volume as i64 / 1024
    }

    /// `k` cicli (al più `BLOCK`) con il filtro, come `sid_filter.sv` in modo 8580 ma con un passo
    /// ogni 2^FILTER_DECIM cicli (l'uscita del passo vale per i cicli dopo). Le voci nel filtro
    /// danno l'uscita ciclo per ciclo, quelle dirette solo la somma: l'uscita è
    /// `volume · (diretto / 1024 + filtro / 8)`, come `volume · (diretto >> 7 + filtro) >> 3` del
    /// Verilog ma senza la saturazione di ogni ciclo, che con le nostre musiche non scatta mai
    /// (nessun campione saturato nelle registrazioni del core); si satura la somma del blocco.
    fn clock_filtered(&mut self, k: usize) -> i64 {
        let mut filtered = [0i32; BLOCK];
        let route = self.filter.res_filt;
        let off3 = self.filter.mode & 8 != 0;
        let mut direct = 0;
        for (i, v) in self.voices.iter_mut().enumerate() {
            if route >> i & 1 != 0 {
                v.clock_into(k as u32, &mut filtered[..k]);
            } else if i == 2 && off3 {
                v.clock(k as u32);
            } else {
                direct += v.clock(k as u32);
            }
        }
        let f = &mut self.filter;
        let w0 = 5 * f.fc as i32;
        let q = Q_8580[(f.res_filt >> 4) as usize];
        let vol = self.volume as i64;
        let mut taps = 0i64;
        for &x in &filtered[..k] {
            f.acc += x;
            f.phase += 1;
            if f.phase == 1 << FILTER_DECIM {
                f.tap = f.step(w0, q, f.acc >> (FILTER_DECIM + 5));
                f.acc = 0;
                f.phase = 0;
            }
            taps += f.tap as i64;
        }
        let full = 0x8000 * k as i64;
        (direct * vol / 1024 + taps * vol / 8).clamp(-full, full - k as i64)
    }

    /// Tutte le voci mute (inviluppo a zero).
    pub fn silent(&self) -> bool {
        self.voices.iter().all(|v| v.env == 0)
    }

    /// Inviluppo della voce 0-2 (per le prove).
    pub fn envelope(&self, voice: usize) -> u8 {
        self.voices[voice].env
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Attacco 0 (2 ms) fino al massimo, poi il decadimento verso il sostegno.
    #[test]
    fn inviluppo() {
        let mut sid = Sid::new();
        sid.write(5, 0x09); // attacco 0, decadimento 9 (750 ms al tempo del chip)
        sid.write(6, 0x80); // sostegno 8 (0x88)
        sid.write(4, 0x21);
        sid.clock(9 * 254);
        assert!(sid.envelope(0) >= 0xFD, "{}", sid.envelope(0));
        sid.clock(30);
        assert_eq!(sid.envelope(0), 0xFF);
        // il decadimento esponenziale arriva al sostegno e si ferma
        sid.clock(1_000_000);
        assert_eq!(sid.envelope(0), 0x88);
        // rilascio 0: in pochi millisecondi a zero, e resta lì
        sid.write(4, 0x20);
        sid.clock(100_000);
        assert_eq!(sid.envelope(0), 0);
        sid.clock(100_000);
        assert_eq!(sid.envelope(0), 0);
    }

    /// Dente di sega a volume pieno: media zero, picco intorno a 2047 * 255 * 15 / 1024.
    #[test]
    fn dente_di_sega() {
        let mut sid = Sid::new();
        sid.write(0x18, 0x0F);
        sid.write(5, 0x00);
        sid.write(6, 0xF0);
        sid.write(0, 0xD6);
        sid.write(1, 0x1C); // 440 Hz
        sid.write(4, 0x21);
        sid.clock(10_000);
        let (mut lo, mut hi, mut total) = (i64::MAX, i64::MIN, 0);
        for _ in 0..10_000 {
            let s = sid.clock(1);
            lo = lo.min(s);
            hi = hi.max(s);
            total += s;
        }
        let peak = 2047 * 255 * 15 / 1024;
        assert!(hi > peak * 95 / 100 && hi <= peak, "{hi}");
        assert!(lo < -peak * 95 / 100, "{lo}");
        assert!((total / 10_000).abs() < 200, "{total}");
    }

    /// RMS dell'uscita di un dente di sega di frequenza `reg` (registro), dopo l'attacco.
    fn saw_rms(reg: u16, filter: Option<(u16, u8, u8)>) -> f64 {
        let mut sid = Sid::new();
        if let Some((fc, res, mode)) = filter {
            sid.write(0x15, (fc & 7) as u8);
            sid.write(0x16, (fc >> 3) as u8);
            sid.write(0x17, res << 4 | 1);
            sid.write(0x18, mode << 4 | 0x0F);
        } else {
            sid.write(0x18, 0x0F);
        }
        sid.write(5, 0x00);
        sid.write(6, 0xF0);
        sid.write(0, reg as u8);
        sid.write(1, (reg >> 8) as u8);
        sid.write(4, 0x21);
        sid.clock(20_000);
        let mut sq = 0.0;
        for _ in 0..20_000 {
            let s = sid.clock(1) as f64;
            sq += s * s;
        }
        (sq / 20_000.0).sqrt()
    }

    /// Passa-basso dell'8580: un dente di sega a 2 kHz passa quasi tutto con il taglio in cima,
    /// perde molto con il taglio a circa 300 Hz; la risonanza alza la banda vicino al taglio.
    #[test]
    fn filtro_passa_basso() {
        let f2k = (2000.0 * 16_777_216.0 / 1e6) as u16;
        let open = saw_rms(f2k, None);
        let wide = saw_rms(f2k, Some((2047, 0, 1)));
        let closed = saw_rms(f2k, Some((50, 0, 1)));
        assert!(wide > open * 0.8 && wide < open * 1.2, "{open} {wide}");
        assert!(closed < open * 0.2, "{open} {closed}");
        // taglio sulla fondamentale (2 kHz = 330 passi): con la risonanza al massimo sale
        let flat = saw_rms(f2k, Some((330, 0, 1)));
        let peak = saw_rms(f2k, Some((330, 15, 1)));
        assert!(peak > flat * 1.5, "{flat} {peak}");
        // passa-alto con il taglio in basso: passa quasi tutto
        let hp = saw_rms(f2k, Some((10, 0, 4)));
        assert!(hp > open * 0.8, "{open} {hp}");
    }

    /// Senza voci nel filtro e con il modo spento il filtro non costa niente e lo stato si azzera.
    #[test]
    fn filtro_spento() {
        let mut sid = Sid::new();
        sid.write(0x17, 0xF1);
        sid.write(0x18, 0x1F);
        sid.write(0x16, 0x20);
        sid.write(5, 0x00);
        sid.write(6, 0xF0);
        sid.write(1, 0x10);
        sid.write(4, 0x21);
        sid.clock(10_000);
        assert!(sid.filter.busy());
        sid.write(0x17, 0x00);
        sid.write(0x18, 0x0F);
        sid.clock(100);
        assert!(!sid.filter.busy());
        assert_eq!((sid.filter.lp, sid.filter.bp, sid.filter.hp), (0, 0, 0));
    }
}
