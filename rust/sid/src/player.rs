//! Player della musica: port in Rust di quello Verilog del MiSTer (`mister/rtl/pong_sid.v`), senza
//! la voce digitalizzata. Legge la ROM di `tools/gen_sid_music.py` e scrive i registri del SID
//! nello stesso ordine: le scritture di ogni passo sono identiche a quelle del player Verilog
//! (`c64/test/sid_reference.txt`, verificato da `tests/reference.rs`).
//!
//! Quattro canali: lo 0, l'1 e il 2 suonano la canzone sulle voci 1-3, il 3 gli effetti sulla
//! voce 3 (intanto la canzone su quella voce continua a contare senza scrivere). Un passo
//! (`tick`) serve i canali in ordine; un effetto (`effect`) parte subito, senza aspettare il passo.
//!
//! Oltre al player Verilog, il rallentamento della musica (`set_slow`, il bullet time di NEXT):
//! come gli effetti rallentati del MiSTer (`fx_slow`), i canali della canzone sono serviti un
//! passo su due e scrivono le frequenze dimezzate (un'ottava sotto). Al cambio, al passo dopo, si
//! riscrivono subito le frequenze dei canali attivi della canzone (dimezzate o intere), perché le
//! note in corso cambino ottava senza aspettare la nota dopo. Il tempo dei passi (50 Hz, o 62,5 Hz
//! al match point) lo decide chi chiama `tick`: vedi `engine`.
//!
//! Filtro (formato in `tools/gen_sid_music.py`): taglio e scivolata del taglio sono comandi di
//! traccia, $D417 e $D418 sono nei byte 6 e 7 degli strumenti nel filtro, che il generatore mette
//! solo nelle voci 1 e 2: la voce 3, degli effetti, non passa mai dal filtro. Il taglio è a 16 bit
//! con 5 bit di frazione. Il player tiene una copia di $D417 e $D418 e li riscrive, con il taglio,
//! solo quando cambiano; all'inizio di ogni canzone $D418 = $0F e $D417 = 0.

use crate::rom::Rom;

/// Comandi delle tracce (vedi `tools/gen_sid_music.py`).
const PAUSE: u8 = 0x60;
const SLIDE: u8 = 0x80;
/// 0xA0 + i 3 bit bassi del taglio, poi gli 8 alti
const CUTOFF: u8 = 0xA0;
/// scivolata del taglio: i due byte dopo (16 bit con segno) si sommano al taglio a 16 bit a ogni
/// passo della canzone
const SWEEP: u8 = 0xB0;
const RESTART: u8 = 0xFE;

#[derive(Clone, Copy, Debug, Default)]
struct Chan {
    ptr: u16,
    start: u16,
    cnt: u8,
    note: u8,
    ins: u8,
    arp: u8,
    slide: u8,
    freq: u16,
    /// forma d'onda dello strumento (registro di controllo senza gate)
    wave: u8,
    /// frame di rilascio prima della fine della nota
    rel: u8,
}

/// Effetto da suonare per gli eventi del frame (bit 0 muro, 1 colpo, 2 boost, 3 punto, 4 gettone,
/// 5 mossa, 6 colpo della mossa): stesse priorità di `fx_of` in pong_sid.v. 0 = nessuno.
pub fn effect_of(events: u8) -> u8 {
    let e = events & 0x7F;
    let bit = |i: u8| e >> i & 1 != 0;
    if bit(4) {
        5 // gettone
    } else if bit(3) {
        4 // punto
    } else if bit(6) {
        7 // colpo con una mossa speciale
    } else if bit(2) {
        3 // boost
    } else if bit(5) {
        6 // mossa speciale attivata
    } else if bit(1) {
        2 // colpo
    } else if bit(0) {
        1 // muro
    } else {
        0
    }
}

/// Semitoni da aggiungere alla nota nel passo 0-2 dell'arpeggio.
fn arp_offset(mode: u8, phase: u8) -> u8 {
    match (mode, phase) {
        (1, 1) => 3,
        (1, 2) => 7,
        (2, 1) => 4,
        (2, 2) => 7,
        (3, 1 | 2) => 12,
        _ => 0,
    }
}

/// Player: stato dei quattro canali.
#[derive(Clone, Debug)]
pub struct Player {
    rom: Rom,
    ch: [Chan; 4],
    active: [bool; 4],
    /// passo degli arpeggi della canzone e degli effetti (uguali fuori dal match point)
    phase: u8,
    fx_phase: u8,
    song: u8,
    song_new: bool,
    /// effetto rallentato e passo saltato (il canale 3 avanza un passo su due)
    fx_slow: bool,
    fx_skip: bool,
    /// musica rallentata, passo saltato, frequenze da riscrivere al prossimo passo
    slow: bool,
    skip: bool,
    retune: bool,
    /// filtro: taglio a 16 bit (il registro a 11 bit è `>> 5`), scivolata del taglio per passo,
    /// copia di $D417 e $D418 come sono nel SID
    cutoff: u16,
    sweep: u16,
    res_filt: u8,
    vol_mode: u8,
}

/// Uscita delle scritture: registro del SID (0-0x18) e valore.
pub trait Writes {
    fn write(&mut self, reg: u8, value: u8);
}

impl<F: FnMut(u8, u8)> Writes for F {
    fn write(&mut self, reg: u8, value: u8) {
        self(reg, value)
    }
}

impl Player {
    /// Player appena acceso: al primo passo il volume al massimo e i gate chiusi, come dopo il
    /// reset del player Verilog.
    pub fn new(rom: Rom) -> Player {
        Player {
            rom,
            ch: [Chan::default(); 4],
            active: [false; 4],
            phase: 0,
            fx_phase: 0,
            song: 0,
            song_new: true,
            fx_slow: false,
            fx_skip: false,
            slow: false,
            skip: false,
            retune: false,
            cutoff: 0,
            sweep: 0,
            res_filt: 0,
            vol_mode: 0x0F,
        }
    }

    pub fn rom(&self) -> &Rom {
        &self.rom
    }

    /// Canzone (da 1; 0 = silenzio): se cambia, riparte da capo al prossimo passo.
    pub fn set_song(&mut self, song: u8) {
        if song != self.song {
            self.song = song;
            self.song_new = true;
        }
    }

    pub fn song(&self) -> u8 {
        self.song
    }

    /// Musica rallentata (bullet time): un passo su due, un'ottava sotto.
    pub fn set_slow(&mut self, on: bool) {
        if on != self.slow {
            self.slow = on;
            self.skip = false;
            self.retune = true;
        }
    }

    /// Qualche canale della canzone o degli effetti sta ancora leggendo la sua traccia.
    pub fn playing(&self) -> bool {
        self.active.iter().any(|&a| a)
    }

    /// Un effetto suona sulla voce 3 (la voce prende il guadagno degli effetti).
    pub fn effect_playing(&self) -> bool {
        self.active[3]
    }

    /// La voce digitalizzata ha il SID (`voice::NameVoice`): il filtro è spento ($D417 = 0 alla
    /// sua partenza, $D418 = $0F alla fine) e la copia del player resta così, così la prima nota
    /// nel filtro dopo la voce riscrive tutto (taglio, $D417, $D418), come in pong_sid.v.
    pub fn voice_has_sid(&mut self) {
        self.res_filt = 0;
        self.vol_mode = 0x0F;
    }

    /// Voce del SID del canale: registri da 0, 7 o 14 (gli effetti sulla voce 3).
    fn base(c: usize) -> u8 {
        [0, 7, 14, 14][c]
    }

    /// Scrittura di un registro della voce del canale: la canzone sulla voce 3 tace mentre suona
    /// un effetto.
    fn wr(&self, c: usize, ofs: u8, value: u8, w: &mut impl Writes) {
        if !(c == 2 && self.active[3]) {
            w.write(Self::base(c) + ofs, value);
        }
    }

    /// Le frequenze del canale si scrivono dimezzate (effetto o musica rallentati).
    fn half(&self, c: usize) -> bool {
        if c == 3 { self.fx_slow } else { self.slow }
    }

    /// Effetto per gli eventi del frame (`effect_of`), subito, sul canale 3; con `slow` a metà
    /// velocità (bullet time).
    pub fn effect(&mut self, events: u8, slow: bool, w: &mut impl Writes) {
        let fx = effect_of(events);
        if fx == 0 {
            return;
        }
        let a = self.rom.effects.get(fx as usize - 1).copied().unwrap_or(0);
        let c = &mut self.ch[3];
        c.ptr = a;
        c.start = a;
        c.cnt = 0;
        c.ins = 0;
        c.arp = 0;
        c.slide = 0;
        self.active[3] = true;
        self.fx_slow = slow;
        self.fx_skip = false;
        // prima si chiude il gate della voce 3
        w.write(0x12, 0x00);
        self.serve(3, w);
    }

    /// Un passo del player per la canzone e per gli effetti (50 volte al secondo nel MiSTer).
    pub fn tick(&mut self, w: &mut impl Writes) {
        self.step(true, true, w);
    }

    /// Un passo della canzone (`song`) e/o degli effetti (`fx`). Nel MiSTer hanno due divisori: al
    /// match point la canzone avanza a 62,5 Hz e gli effetti restano a 50 Hz, ognuno con la sua
    /// fase degli arpeggi; fuori dal match point i due passi coincidono (`tick`).
    pub fn step(&mut self, song: bool, fx: bool, w: &mut impl Writes) {
        let next = |p: u8| if p == 2 { 0 } else { p + 1 };
        if song {
            self.phase = next(self.phase);
        }
        if fx {
            self.fx_phase = next(self.fx_phase);
        }
        let new = song && self.song_new;
        if new {
            // canzone nuova (o silenzio): i canali 0-2 ripartono
            self.song_new = false;
            for v in 0..3 {
                let start = match self.song {
                    0 => 0,
                    s => self.rom.songs.get(s as usize - 1).map_or(0, |t| t[v]),
                };
                let c = &mut self.ch[v];
                c.ptr = start;
                c.start = start;
                c.cnt = 0;
                c.ins = 0;
                c.arp = 0;
                c.slide = 0;
                self.active[v] = self.song != 0;
            }
            // volume al massimo, senza filtro: modo spento, nessuna voce nel filtro; la scivolata
            // del taglio si ferma (il taglio resta)
            w.write(0x18, 0x0F);
            w.write(0x17, 0x00);
            self.res_filt = 0;
            self.vol_mode = 0x0F;
            self.sweep = 0;
        }
        // musica appena rallentata o tornata normale: le note in corso cambiano ottava subito
        if song && self.retune {
            self.retune = false;
            if !new {
                for c in 0..3 {
                    if self.active[c] {
                        let f = self.ch[c].freq;
                        self.write_freq(c, f, w);
                    }
                }
            }
        }
        // l'effetto e la musica rallentati avanzano un passo su due
        let serve_fx = fx && !(self.fx_slow && self.fx_skip);
        if fx {
            self.fx_skip = !self.fx_skip;
        }
        let serve_song = song && !(self.slow && self.skip);
        if song {
            self.skip = !self.skip;
        }
        if new && self.song == 0 {
            // silenzio: si chiude il gate delle voci della canzone, altrimenti l'ultima nota
            // resta tenuta (la voce 3 no se suona un effetto)
            for c in 0..3 {
                self.wr(c, 4, self.ch[c].wave, w);
            }
        }
        if serve_song {
            // la scivolata del taglio, prima dei canali (un taglio letto in questo passo vale subito,
            // la scivolata dal passo dopo), senza saturazione (il generatore controlla i limiti);
            // il taglio si scrive sempre
            if self.sweep != 0 {
                self.cutoff = self.cutoff.wrapping_add(self.sweep);
                self.write_cutoff(w);
            }
            for c in 0..3 {
                self.serve(c, w);
            }
        }
        if serve_fx {
            self.serve(3, w);
        }
    }

    /// Un canale in un passo: nota finita (si legge il comando dopo) o nota in corso.
    fn serve(&mut self, c: usize, w: &mut impl Writes) {
        if !self.active[c] {
            return;
        }
        let ch = self.ch[c];
        if ch.cnt <= 1 {
            self.ch[c].cnt = 0;
            self.fetch(c, w);
        } else {
            let cnt = ch.cnt - 1;
            self.ch[c].cnt = cnt;
            // rilascio qualche frame prima della fine: la nota dopo riparte con l'attacco
            if cnt == ch.rel {
                self.wr(c, 4, ch.wave, w);
            }
            self.run(c, w);
        }
    }

    /// Comandi della traccia fino alla prossima nota o pausa (o alla fine).
    fn fetch(&mut self, c: usize, w: &mut impl Writes) {
        // una traccia senza note che ricomincia girerebbe per sempre (nel Verilog anche)
        for _ in 0..1024 {
            let ptr = self.ch[c].ptr;
            let cmd = self.rom.byte(ptr);
            if cmd < 0x70 {
                // nota o pausa, poi la durata
                let dur = self.rom.byte(ptr.wrapping_add(1));
                let ch = &mut self.ch[c];
                ch.cnt = dur;
                ch.ptr = ptr.wrapping_add(2) & 0xFFF;
                if cmd == PAUSE {
                    let wave = ch.wave;
                    self.wr(c, 4, wave, w); // pausa: gate chiuso
                } else {
                    ch.note = cmd & 0x7F;
                    self.start_note(c, w);
                }
                return;
            } else if cmd >> 4 == 7 {
                self.ch[c].ins = cmd & 0x0F;
                self.ch[c].ptr = ptr.wrapping_add(1) & 0xFFF;
            } else if cmd == SLIDE {
                self.ch[c].slide = self.rom.byte(ptr.wrapping_add(1));
                self.ch[c].ptr = ptr.wrapping_add(2) & 0xFFF;
            } else if cmd >> 4 == 9 {
                self.ch[c].arp = cmd & 0x03;
                self.ch[c].ptr = ptr.wrapping_add(1) & 0xFFF;
            } else if cmd >> 4 == CUTOFF >> 4 {
                self.cutoff = (self.rom.byte(ptr.wrapping_add(1)) as u16) << 8 | ((cmd & 7) as u16) << 5;
                self.ch[c].ptr = ptr.wrapping_add(2) & 0xFFF;
                self.write_cutoff(w);
            } else if cmd == SWEEP {
                self.sweep =
                    self.rom.byte(ptr.wrapping_add(1)) as u16 | (self.rom.byte(ptr.wrapping_add(2)) as u16) << 8;
                self.ch[c].ptr = ptr.wrapping_add(3) & 0xFFF;
            } else if cmd == RESTART {
                self.ch[c].ptr = self.ch[c].start;
            } else {
                // fine della traccia: la voce tace
                self.active[c] = false;
                self.wr(c, 4, 0x00, w);
                return;
            }
        }
        self.active[c] = false;
    }

    /// Nota nuova: strumento (forma d'onda, inviluppo, impulso, rilascio), frequenza, gate e
    /// filtro.
    fn start_note(&mut self, c: usize, w: &mut impl Writes) {
        let base = self.rom.instr_base.wrapping_add(self.ch[c].ins as u16 * 8);
        let b = |i: u16| self.rom.byte(base.wrapping_add(i));
        self.ch[c].wave = b(0);
        self.wr(c, 5, b(1), w);
        self.wr(c, 6, b(2), w);
        self.wr(c, 3, b(4), w);
        self.wr(c, 2, b(3), w);
        self.ch[c].rel = b(5);
        let (res_filt, vol_mode) = (b(6), b(7));
        let note = self.ch[c].note;
        self.load_freq(c, note, w);
        let wave = self.ch[c].wave;
        self.wr(c, 4, wave | 0x01, w); // gate: parte l'inviluppo
        // filtro dello strumento: se $D417 e $D418 cambiano si riscrivono, con il taglio
        if res_filt != 0 && (res_filt != self.res_filt || vol_mode != self.vol_mode) {
            self.res_filt = res_filt;
            self.vol_mode = vol_mode;
            self.write_cutoff(w);
            w.write(0x17, res_filt);
            w.write(0x18, vol_mode);
        }
    }

    /// Registri del taglio: i 3 bit bassi, poi gli 8 alti. Il filtro è di tutto il SID: queste
    /// scritture non tacciono mai, nemmeno sulla voce 3 durante un effetto.
    fn write_cutoff(&self, w: &mut impl Writes) {
        w.write(0x15, (self.cutoff >> 5 & 7) as u8);
        w.write(0x16, (self.cutoff >> 8) as u8);
    }

    /// Frequenza della nota dalla tabella (byte basso, byte alto), scritta nei registri.
    fn load_freq(&mut self, c: usize, note: u8, w: &mut impl Writes) {
        let a = self.rom.freq_base.wrapping_add((note & 0x7F) as u16 * 2);
        let f = self.rom.byte(a) as u16 | (self.rom.byte(a.wrapping_add(1)) as u16) << 8;
        self.ch[c].freq = f;
        self.write_freq(c, f, w);
    }

    /// Registri della frequenza: byte basso e alto; dimezzata prima l'alto e poi il basso con il
    /// bit che scende dall'alto, come nel player Verilog.
    fn write_freq(&self, c: usize, f: u16, w: &mut impl Writes) {
        if self.half(c) {
            self.wr(c, 1, (f >> 9) as u8, w);
            self.wr(c, 0, (f >> 1) as u8, w);
        } else {
            self.wr(c, 0, f as u8, w);
            self.wr(c, 1, (f >> 8) as u8, w);
        }
    }

    /// Nota in corso: arpeggio o scivolata.
    fn run(&mut self, c: usize, w: &mut impl Writes) {
        let ch = self.ch[c];
        if ch.arp != 0 {
            let phase = if c == 3 { self.fx_phase } else { self.phase };
            let note = ch.note.wrapping_add(arp_offset(ch.arp, phase)) & 0x7F;
            self.load_freq(c, note, w);
        } else if ch.slide != 0 {
            let f = ch.freq.wrapping_add(ch.slide as i8 as i16 as u16);
            self.ch[c].freq = f;
            self.write_freq(c, f, w);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn priorita_degli_effetti() {
        assert_eq!(effect_of(0), 0);
        assert_eq!(effect_of(1), 1);
        assert_eq!(effect_of(3), 2);
        assert_eq!(effect_of(0b111), 3);
        assert_eq!(effect_of(0b1_1111), 5);
        assert_eq!(effect_of(0b1000), 4);
        assert_eq!(effect_of(0b100_0111), 7);
        assert_eq!(effect_of(0b10_0011), 6);
    }

    /// Rallentata: un passo su due e le frequenze dimezzate, anche quelle delle note in corso.
    #[test]
    fn musica_rallentata() {
        let mut p = Player::new(Rom::builtin());
        let mut sink = |_: u8, _: u8| {};
        p.tick(&mut sink);
        p.set_song(1);
        p.tick(&mut sink);
        let mut log = Vec::new();
        p.set_slow(true);
        p.tick(&mut |r, v| log.push((r, v)));
        // le tre voci riscrivono la frequenza dimezzata (voce 1: prima l'alto, poi il basso)
        let f1 = p.ch[0].freq;
        assert_eq!(&log[..2], &[(1, (f1 >> 9) as u8), (0, (f1 >> 1) as u8)]);
        // due passi rallentati valgono uno normale per il contatore delle note
        let cnt = p.ch[0].cnt;
        p.tick(&mut sink);
        assert_eq!(p.ch[0].cnt, cnt);
        p.tick(&mut sink);
        assert_eq!(p.ch[0].cnt, cnt - 1);
    }

    /// HAMMER: il taglio della traccia, il basso (voce 2) nel passa-basso con la risonanza, la
    /// scivolata del taglio a ogni passo; una canzone senza filtro lo spegne.
    #[test]
    fn filtro_di_hammer() {
        let mut p = Player::new(Rom::builtin());
        let hammer = p.rom().song_number("theme_hammer").unwrap();
        p.set_song(hammer);
        let mut log = Vec::new();
        p.tick(&mut |r, v| log.push((r, v)));
        // taglio 60 = 7 * 8 + 4: $D415 = 4, $D416 = 7
        let i = log.iter().position(|&w| w == (0x15, 4)).unwrap();
        assert_eq!(log[i + 1], (0x16, 7));
        let j = log.iter().position(|&w| w == (0x17, 0xC2)).unwrap();
        assert_eq!(log[j + 1], (0x18, 0x1F));
        // un passo (32/32) in più al passo dopo, prima dei canali: 61
        let mut log = Vec::new();
        p.tick(&mut |r, v| log.push((r, v)));
        assert_eq!(&log[..2], &[(0x15, 5), (0x16, 7)]);
        // la presentazione non ha il filtro: modo spento, voci fuori dal filtro
        let intro = p.rom().song_number("intro").unwrap();
        p.set_song(intro);
        let mut log = Vec::new();
        p.tick(&mut |r, v| log.push((r, v)));
        assert_eq!(&log[..2], &[(0x18, 0x0F), (0x17, 0x00)]);
        assert!(!log[2..].iter().any(|&(r, _)| (0x15..=0x18).contains(&r)));
    }
}
