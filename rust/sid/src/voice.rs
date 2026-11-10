//! Voci "da SID": port della voce digitalizzata e delle voci di partita di `mister/rtl/pong_sid.v`,
//! con gli stessi campioni (`mister/rtl/gen/sid_voices.hex` e `sid_voices.vh`, da
//! `tools/gen_voices.py`) e gli stessi tempi, in cicli del SID a 1 MHz.
//!
//! - **Nome dell'avversario** (`NameVoice`, CHALLENGE): il trucco del registro del volume ($D418)
//!   del C64. Le voci 2 e 3 danno un DC costante (impulso con il bit di test, sostegno al massimo),
//!   perché l'8580 un DC suo non ce l'ha; ogni campione a 4 bit si scrive come volume e moltiplica
//!   quel DC. La voce 1 si spegne, il filtro è spento, e intanto il player non scrive (`Music`
//!   salta le sue scritture). Il DC sale con l'attacco in 70 ms prima della voce e scende con il
//!   rilascio in 120 ms dopo, per non fare il colpo all'inizio e alla fine. Le scritture sono
//!   quelle di pong_sid.v, nello stesso ordine.
//! - **Voci di partita** (`CallVoice`: urla delle mosse, READY, GO, YOU WIN, PERFECT): un secondo
//!   player che non tocca il SID; il campione a 4 bit si somma all'uscita (`Music`), così musica ed
//!   effetti continuano. Una voce nuova interrompe quella in corso.
//!
//! Campioni a `VOICE_RATE` Hz (5000: un campione ogni 200 cicli), due per byte, prima il nibble
//! alto; 8 = silenzio.

use crate::chip::CLOCK_HZ;
use crate::player::Writes;

/// Il gate chiuso dura qualche ciclo (100 cicli a 20 MHz nel MiSTer): l'attacco parte dal fronte.
const GATE_CYCLES: u32 = 5;
/// 70 ms: l'attacco 6 (68 ms) del DC, prima del primo campione.
const PRE_CYCLES: u32 = 70_000;
/// 120 ms: il rilascio 4 (114 ms) del DC, dopo l'ultimo campione.
const REL_CYCLES: u32 = 120_000;

/// Voci di partita, con il numero `VOICE_*` di sid_voices.vh.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Call {
    /// urlo della mossa STRAIGHT SHOT
    Straight,
    /// urlo della mossa RISING STRIKE
    Rise,
    Ready,
    Go,
    YouWin,
    Perfect,
}

impl Call {
    const ALL: [Call; 6] = [Call::Straight, Call::Rise, Call::Ready, Call::Go, Call::YouWin, Call::Perfect];

    fn param(self) -> &'static str {
        match self {
            Call::Straight => "VOICE_STRAIGHT",
            Call::Rise => "VOICE_RISE",
            Call::Ready => "VOICE_READY",
            Call::Go => "VOICE_GO",
            Call::YouWin => "VOICE_YOU_WIN",
            Call::Perfect => "VOICE_PERFECT",
        }
    }
}

/// ROM delle voci: i campioni, inizio e lunghezza in byte di ogni voce, la frequenza.
#[derive(Clone, Debug)]
pub struct VoiceRom {
    data: Vec<u8>,
    /// inizio e lunghezza in byte, per numero di voce (0-6 i nomi nell'ordine di `PaddleKind`)
    voices: Vec<(usize, usize)>,
    /// numero delle voci di partita, nell'ordine di `Call::ALL`
    calls: [u8; 6],
    /// cicli del SID per campione
    period: u32,
}

/// Numero decimale dopo "'d" (es. 4'd7; o 15'd1281;).
fn num(s: &str) -> Option<usize> {
    s.split_once('d')
        .and_then(|(_, n)| n.trim().trim_end_matches(';').trim().parse().ok())
}

impl VoiceRom {
    /// La ROM inclusa nell'eseguibile, la stessa del MiSTer.
    pub fn builtin() -> VoiceRom {
        VoiceRom::parse(
            include_str!("../../../mister/rtl/gen/sid_voices.hex"),
            include_str!("../../../mister/rtl/gen/sid_voices.vh"),
        )
        .expect("sid_voices.hex o sid_voices.vh non validi")
    }

    /// Campioni da `sid_voices.hex` (un byte per riga) e indici da `sid_voices.vh`.
    pub fn parse(hex: &str, vh: &str) -> Result<VoiceRom, String> {
        let data = hex
            .split_whitespace()
            .map(|b| u8::from_str_radix(b, 16).map_err(|e| format!("byte {b:?}: {e}")))
            .collect::<Result<Vec<u8>, String>>()?;
        let mut starts: Vec<Option<usize>> = Vec::new();
        let mut lens: Vec<Option<usize>> = Vec::new();
        let mut rate = None;
        let mut calls = [None; 6];
        for l in vh.lines() {
            let l = l.split("//").next().unwrap_or("").trim();
            // 4'd3: voice_start = 15'd3522;   e   4'd3: voice_len = 12'd1043;
            for (key, table) in [(": voice_start = ", &mut starts), (": voice_len = ", &mut lens)] {
                if let Some((id, value)) = l.split_once(key)
                    && let (Some(id), Some(value)) = (num(id), num(value))
                {
                    if table.len() <= id {
                        table.resize(id + 1, None);
                    }
                    table[id] = Some(value);
                }
            }
            if let Some(v) = l.strip_prefix("localparam VOICE_RATE = ") {
                rate = v.trim_end_matches(';').trim().parse::<u32>().ok();
            }
            for (i, c) in Call::ALL.iter().enumerate() {
                // localparam [3:0] VOICE_READY = 4'd9;
                if let Some(rest) = l.strip_prefix("localparam [3:0] ")
                    && let Some(v) = rest.strip_prefix(c.param())
                    && let Some(v) = v.trim_start().strip_prefix('=')
                {
                    calls[i] = num(v).map(|n| n as u8);
                }
            }
        }
        let rate = rate.filter(|&r| r > 0).ok_or("VOICE_RATE non trovato in sid_voices.vh")?;
        let mut voices = Vec::new();
        for (id, (s, n)) in starts.iter().zip(&lens).enumerate() {
            let (Some(s), Some(n)) = (*s, *n) else {
                return Err(format!("voce {id} senza inizio o lunghezza in sid_voices.vh"));
            };
            if s + n > data.len() {
                return Err(format!("voce {id} oltre la fine di sid_voices.hex"));
            }
            voices.push((s, n));
        }
        let mut ids = [0; 6];
        for (i, c) in Call::ALL.iter().enumerate() {
            ids[i] = calls[i].ok_or(format!("{} non trovato in sid_voices.vh", c.param()))?;
            if ids[i] as usize >= voices.len() {
                return Err(format!("{}: voce {} inesistente", c.param(), ids[i]));
            }
        }
        Ok(VoiceRom {
            data,
            voices,
            calls: ids,
            period: CLOCK_HZ / rate,
        })
    }

    /// Numero della voce di partita.
    pub fn call_id(&self, call: Call) -> u8 {
        self.calls[Call::ALL.iter().position(|&c| c == call).unwrap_or(0)]
    }

    /// Campioni della voce `id` (due per byte): inizio in byte e numero di campioni; 0 se non c'è.
    fn span(&self, id: u8) -> (usize, u32) {
        self.voices
            .get(id as usize)
            .map_or((0, 0), |&(s, n)| (s, 2 * n as u32))
    }

    /// Durata della voce `id` in secondi (per le prove).
    pub fn seconds(&self, id: u8) -> f64 {
        self.span(id).1 as f64 * self.period as f64 / CLOCK_HZ as f64
    }

    /// Campione `i` (da 0) dalla voce che inizia al byte `start`: prima il nibble alto.
    fn sample(&self, start: usize, i: u32) -> u8 {
        let b = self.data.get(start + i as usize / 2).copied().unwrap_or(0x88);
        if i & 1 == 0 { b >> 4 } else { b & 0x0F }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum State {
    Idle,
    /// gate chiuso sulle voci 2 e 3 dopo la preparazione
    Gate,
    /// il DC sale con l'attacco, a volume fermo
    Pre,
    /// un campione ogni `period` cicli come volume
    Play,
    /// volume a metà e gate chiuso: il DC scende con il rilascio
    Rel,
}

/// Nome dell'avversario con il trucco di $D418: ha il SID da `start` alla fine del rilascio.
#[derive(Clone, Debug)]
pub struct NameVoice {
    state: State,
    /// cicli al prossimo evento
    timer: u32,
    start: usize,
    /// prossimo campione e campioni della voce
    next: u32,
    count: u32,
    /// la presentazione è finita: la voce si ferma appena può
    stop: bool,
}

impl Default for NameVoice {
    fn default() -> Self {
        NameVoice {
            state: State::Idle,
            timer: 0,
            start: 0,
            next: 0,
            count: 0,
            stop: false,
        }
    }
}

impl NameVoice {
    /// La voce ha il SID (anche durante attacco e rilascio): il player intanto non scrive.
    pub fn on(&self) -> bool {
        self.state != State::Idle
    }

    /// Cicli al prossimo evento (`u32::MAX` a riposo).
    pub fn until(&self) -> u32 {
        if self.on() { self.timer } else { u32::MAX }
    }

    /// Parte la voce `id` (solo a riposo, come nel MiSTer): voce 1 spenta, volume a metà (il
    /// silenzio), voci 2 e 3 a DC costante con il gate ancora chiuso, nessuna voce nel filtro.
    pub fn start(&mut self, rom: &VoiceRom, id: u8, w: &mut impl Writes) {
        let (start, count) = rom.span(id);
        if self.on() || count == 0 {
            return;
        }
        for (reg, value) in [
            (0x0B, 0x48),
            (0x12, 0x48),
            (0x04, 0x00),
            (0x18, 0x08),
            (0x0C, 0x60),
            (0x0D, 0xF4),
            (0x13, 0x60),
            (0x14, 0xF4),
            (0x17, 0x00),
        ] {
            w.write(reg, value);
        }
        self.start = start;
        self.next = 0;
        self.count = count;
        self.stop = false;
        self.state = State::Gate;
        self.timer = GATE_CYCLES;
    }

    /// Fine della presentazione (saltata, o arriva uno sfidante): la voce si ferma e il DC scende.
    pub fn stop(&mut self, w: &mut impl Writes) {
        self.stop = true;
        if matches!(self.state, State::Pre | State::Play) {
            self.end(w);
        }
    }

    /// Avanti di `k` cicli (al più `until`): all'evento le sue scritture.
    pub fn advance(&mut self, k: u32, rom: &VoiceRom, w: &mut impl Writes) {
        if !self.on() {
            return;
        }
        self.timer -= k.min(self.timer);
        if self.timer > 0 {
            return;
        }
        match self.state {
            State::Gate => {
                // gate aperto sulle voci 2 e 3: il DC sale con l'attacco
                w.write(0x0B, 0x49);
                w.write(0x12, 0x49);
                if self.stop {
                    self.end(w);
                } else {
                    self.state = State::Pre;
                    self.timer = PRE_CYCLES;
                }
            }
            State::Pre => {
                self.state = State::Play;
                self.sample(rom, w);
            }
            State::Play => {
                if self.next == self.count {
                    self.end(w);
                } else {
                    self.sample(rom, w);
                }
            }
            State::Rel => {
                // voci 2 e 3 spente, volume al massimo: il SID torna al player
                w.write(0x0B, 0x00);
                w.write(0x12, 0x00);
                w.write(0x18, 0x0F);
                self.state = State::Idle;
            }
            State::Idle => {}
        }
    }

    fn sample(&mut self, rom: &VoiceRom, w: &mut impl Writes) {
        w.write(0x18, rom.sample(self.start, self.next));
        self.next += 1;
        self.timer = rom.period;
    }

    fn end(&mut self, w: &mut impl Writes) {
        w.write(0x18, 0x08);
        w.write(0x0B, 0x48);
        w.write(0x12, 0x48);
        self.state = State::Rel;
        self.timer = REL_CYCLES;
    }
}

/// Voce di partita: il campione a 4 bit da sommare all'uscita.
#[derive(Clone, Debug, Default)]
pub struct CallVoice {
    on: bool,
    level: u8,
    timer: u32,
    start: usize,
    next: u32,
    count: u32,
}

impl CallVoice {
    /// Campione in corso meno il silenzio (-8..7).
    pub fn offset(&self) -> i32 {
        if self.on { self.level as i32 - 8 } else { 0 }
    }

    /// Cicli al prossimo campione (`u32::MAX` a riposo).
    pub fn until(&self) -> u32 {
        if self.on { self.timer } else { u32::MAX }
    }

    /// Parte la voce `id`, anche sopra quella in corso.
    pub fn start(&mut self, rom: &VoiceRom, id: u8) {
        let (start, count) = rom.span(id);
        if count == 0 {
            return;
        }
        self.start = start;
        self.next = 0;
        self.count = count;
        self.on = true;
        self.sample(rom);
    }

    pub fn advance(&mut self, k: u32, rom: &VoiceRom) {
        if !self.on {
            return;
        }
        self.timer -= k.min(self.timer);
        if self.timer == 0 {
            if self.next == self.count {
                self.on = false;
            } else {
                self.sample(rom);
            }
        }
    }

    fn sample(&mut self, rom: &VoiceRom) {
        self.level = rom.sample(self.start, self.next);
        self.next += 1;
        self.timer = rom.period;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rom_inclusa() {
        let rom = VoiceRom::builtin();
        assert_eq!(rom.period, 200);
        assert!(rom.voices.len() >= 13);
        assert_eq!(rom.call_id(Call::Straight), 7);
        assert_eq!(rom.call_id(Call::Perfect), 12);
        // ARCADE: 1281 byte, 0,51 s
        assert_eq!(rom.span(0), (0, 2562));
        assert!((rom.seconds(0) - 0.5124).abs() < 1e-6);
    }

    /// Le scritture della voce come in pong_sid.v: preparazione, gate, campioni, chiusura.
    #[test]
    fn scritture_della_voce() {
        let rom = VoiceRom::builtin();
        let mut v = NameVoice::default();
        let mut writes = Vec::new();
        let mut w = |r: u8, x: u8| writes.push((r, x));
        v.start(&rom, 5, &mut w);
        assert_eq!(writes.len(), 9);
        assert!(v.on());
        let mut cycles = 0u64;
        while v.on() {
            let k = v.until();
            cycles += k as u64;
            v.advance(k, &rom, &mut |r: u8, x: u8| writes.push((r, x)));
        }
        let (_, count) = rom.span(5);
        // $D418: il silenzio della preparazione e della chiusura, i campioni, il volume al massimo
        let volumes = writes.iter().filter(|&&(r, _)| r == 0x18).count() as u32;
        assert_eq!(volumes, count + 3);
        // gate + attacco + campioni + rilascio
        assert_eq!(cycles, (GATE_CYCLES + PRE_CYCLES + count * 200 + REL_CYCLES) as u64);
        assert_eq!(&writes[writes.len() - 3..], &[(0x0B, 0), (0x12, 0), (0x18, 0x0F)]);
    }

    /// Fermata durante l'attacco: subito la chiusura, poi il rilascio.
    #[test]
    fn voce_fermata() {
        let rom = VoiceRom::builtin();
        let mut v = NameVoice::default();
        let mut writes = Vec::new();
        v.start(&rom, 0, &mut |r: u8, x: u8| writes.push((r, x)));
        v.advance(GATE_CYCLES, &rom, &mut |r: u8, x: u8| writes.push((r, x)));
        v.advance(1000, &rom, &mut |r: u8, x: u8| writes.push((r, x)));
        v.stop(&mut |r: u8, x: u8| writes.push((r, x)));
        assert_eq!(v.until(), REL_CYCLES);
        assert_eq!(&writes[writes.len() - 3..], &[(0x18, 0x08), (0x0B, 0x48), (0x12, 0x48)]);
    }

    #[test]
    fn voce_di_partita() {
        let rom = VoiceRom::builtin();
        let mut c = CallVoice::default();
        c.start(&rom, rom.call_id(Call::Go));
        let (_, count) = rom.span(rom.call_id(Call::Go));
        let mut cycles = 0u64;
        while c.until() != u32::MAX {
            cycles += c.until() as u64;
            c.advance(c.until(), &rom);
        }
        assert_eq!(cycles, count as u64 * 200);
        assert_eq!(c.offset(), 0);
    }
}
