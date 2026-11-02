//! Emulatore del 6502 NMOS (opcode documentati, modo decimale compreso) per il banco di prova
//! della versione C64: esegue il codice assemblato su 64 KB di RAM piatta, senza ROM né I/O, e
//! conta i cicli come il processore vero (penalità di pagina e dei salti comprese). Dell'I/O ci
//! sono solo i joystick, la riga del raster e il timer A del CIA2 con il suo NMI (`Cia2`); in più
//! la cartuccia EasyFlash (`EasyFlash`), da cui il programma gira.
//!
//! Verificato con il test funzionale di Klaus Dormann (`cargo test -p paddws-c64 -- --ignored`).

const C: u8 = 0x01;
const Z: u8 = 0x02;
const I: u8 = 0x04;
const D: u8 = 0x08;
const B: u8 = 0x10;
const U: u8 = 0x20;
const V: u8 = 0x40;
const N: u8 = 0x80;

/// Timer A del CIA2 con il suo NMI, quanto basta per la voce di CHALLENGE (c64/src/voice.s):
/// latch in $DD04-$DD05, controllo in $DD0E (avvio, una volta sola, ricarica), abilitazione e
/// richieste in $DD0D. La lettura di $DD0D spegne la richiesta e la linea dell'NMI.
#[derive(Clone, Default)]
pub struct Cia2 {
    latch: u16,
    /// cicli fino al prossimo passaggio per zero (periodo: latch + 1)
    left: u64,
    pub running: bool,
    one_shot: bool,
    /// NMI del timer A abilitato
    mask: bool,
    flag: std::cell::Cell<bool>,
    line: std::cell::Cell<bool>,
}

/// Cartuccia EasyFlash (c64/src/ef.inc): banco ($DE00), modo ($DE02) e le due flash da 64 banchi
/// di 8 KB, ROML a $8000 (modi a 8K e 16K con $01 = %x11, Ultimax) e ROMH a $A000 (16K) o $E000
/// (Ultimax). Nel modo Ultimax del C64 restano solo $0000-$0FFF e l'I/O; le scritture a $8000-$9FFF
/// vanno alla flash della ROML, che capisce i comandi dell'Am29F040 come in VICE (sblocco a $555 e
/// $2AA con gli 11 bit bassi dell'indirizzo, $A0 e il byte, $80 + sblocco + $30 per un settore di
/// 64 KB, $F0 per uscire) e li esegue subito: la lettura dà già il dato.
#[derive(Clone)]
pub struct EasyFlash {
    pub bank: u8,
    pub mode: u8,
    pub roml: Vec<u8>,
    pub romh: Vec<u8>,
    /// passo della sequenza di comando in corso
    step: u8,
    /// byte scritti e settori cancellati
    pub programs: u32,
    pub erases: u32,
    /// byte scritti dove non era cancellato (il dato resta l'AND)
    pub dirty_programs: u32,
    /// accessi sbagliati: RAM che nel modo Ultimax non c'è, scritture nella ROMH, comandi strani
    pub faults: std::cell::Cell<u32>,
    /// la flash non si lascia scrivere: i comandi non cambiano niente
    pub locked: bool,
}

/// Modi della EasyFlash ($DE02, bit 0-2)
pub const EF_OFF: u8 = 4;
const EF_ULTIMAX: u8 = 5;
const EF_8K: u8 = 6;
const EF_16K: u8 = 7;
pub const EF_HALF: usize = 0x2000;

impl EasyFlash {
    pub fn new() -> Self {
        Self {
            bank: 0,
            mode: EF_OFF,
            roml: vec![0xFF; 64 * EF_HALF],
            romh: vec![0xFF; 64 * EF_HALF],
            step: 0,
            programs: 0,
            erases: 0,
            dirty_programs: 0,
            faults: std::cell::Cell::new(0),
            locked: false,
        }
    }

    fn fault(&self) {
        self.faults.set(self.faults.get() + 1);
    }

    fn at(&self, addr: u16) -> usize {
        self.bank as usize * EF_HALF + (addr as usize & (EF_HALF - 1))
    }

    /// Lettura dalla cartuccia, se a quell'indirizzo c'è (`port`: la porta $01).
    fn read(&self, addr: u16, port: u8) -> Option<u8> {
        let roml = (0x8000..0xA000).contains(&addr);
        match self.mode & 7 {
            EF_ULTIMAX => match addr {
                0x8000..=0x9FFF => Some(self.roml[self.at(addr)]),
                0xE000..=0xFFFF => Some(self.romh[self.at(addr)]),
                0x1000..=0x7FFF | 0xA000..=0xCFFF => {
                    self.fault();
                    Some(0xFF)
                }
                _ => None,
            },
            EF_8K if roml && port & 3 == 3 => Some(self.roml[self.at(addr)]),
            EF_16K if roml && port & 3 == 3 => Some(self.roml[self.at(addr)]),
            EF_16K if (0xA000..0xC000).contains(&addr) && port & 2 != 0 => Some(self.romh[self.at(addr)]),
            _ => None,
        }
    }

    /// Scrittura nel modo Ultimax: true se l'ha presa la cartuccia (o non va da nessuna parte).
    fn write(&mut self, addr: u16, v: u8) -> bool {
        if self.mode & 7 != EF_ULTIMAX {
            return false;
        }
        match addr {
            0x8000..=0x9FFF => {
                self.command(addr, v);
                true
            }
            0x1000..=0x7FFF | 0xA000..=0xCFFF | 0xE000..=0xFFFF => {
                self.fault();
                true
            }
            _ => false,
        }
    }

    fn command(&mut self, addr: u16, v: u8) {
        let cmd = addr & 0x7FF;
        self.step = match (self.step, cmd, v) {
            (3, _, _) => {
                let at = self.at(addr);
                if self.roml[at] != 0xFF {
                    self.dirty_programs += 1;
                }
                if !self.locked {
                    self.roml[at] &= v;
                }
                self.programs += 1;
                0
            }
            (_, _, 0xF0) => 0,
            (0 | 4, 0x555, 0xAA) => self.step + 1,
            (1 | 5, 0x2AA, 0x55) => self.step + 1,
            (2, 0x555, 0xA0) => 3,
            (2, 0x555, 0x80) => 4,
            (6, _, 0x30) => {
                let sector = self.at(addr) & !0xFFFF;
                if !self.locked {
                    self.roml[sector..sector + 0x10000].fill(0xFF);
                }
                self.erases += 1;
                0
            }
            _ => {
                self.fault();
                0
            }
        };
    }
}

impl Default for EasyFlash {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Mode {
    Imp,
    Acc,
    Imm,
    Zp,
    Zpx,
    Zpy,
    Abs,
    Abx,
    Aby,
    Ind,
    Izx,
    Izy,
    Rel,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Op {
    Adc,
    And,
    Asl,
    Bcc,
    Bcs,
    Beq,
    Bit,
    Bmi,
    Bne,
    Bpl,
    Brk,
    Bvc,
    Bvs,
    Clc,
    Cld,
    Cli,
    Clv,
    Cmp,
    Cpx,
    Cpy,
    Dec,
    Dex,
    Dey,
    Eor,
    Inc,
    Inx,
    Iny,
    Jmp,
    Jsr,
    Lda,
    Ldx,
    Ldy,
    Lsr,
    Nop,
    Ora,
    Pha,
    Php,
    Pla,
    Plp,
    Rol,
    Ror,
    Rti,
    Rts,
    Sbc,
    Sec,
    Sed,
    Sei,
    Sta,
    Stx,
    Sty,
    Tax,
    Tay,
    Tsx,
    Txa,
    Txs,
    Tya,
}

/// Opcode: operazione, indirizzamento, cicli, un ciclo in più se l'indirizzo cambia pagina.
type Entry = (Op, Mode, u8, bool);

const fn e(op: Op, mode: Mode, cycles: u8, page: bool) -> Option<Entry> {
    Some((op, mode, cycles, page))
}

const TABLE: [Option<Entry>; 256] = {
    use Mode::*;
    use Op::*;
    let mut t: [Option<Entry>; 256] = [None; 256];
    // gruppo dell'accumulatore: aaabbb01
    let alu = [Ora, And, Eor, Adc, Sta, Lda, Cmp, Sbc];
    let mut i = 0;
    while i < 8 {
        let op = alu[i];
        let base = (i << 5) | 1;
        let st = matches!(op, Sta);
        t[base] = e(op, Izx, 6, false);
        t[base | 0x04] = e(op, Zp, 3, false);
        if !st {
            t[base | 0x08] = e(op, Imm, 2, false);
        }
        t[base | 0x0C] = e(op, Abs, 4, false);
        t[base | 0x10] = e(op, Izy, if st { 6 } else { 5 }, !st);
        t[base | 0x14] = e(op, Zpx, 4, false);
        t[base | 0x18] = e(op, Aby, if st { 5 } else { 4 }, !st);
        t[base | 0x1C] = e(op, Abx, if st { 5 } else { 4 }, !st);
        i += 1;
    }
    // scorrimenti e incrementi in memoria
    let rmw = [
        (Asl, 0x00),
        (Rol, 0x20),
        (Lsr, 0x40),
        (Ror, 0x60),
        (Dec, 0xC0),
        (Inc, 0xE0),
    ];
    let mut i = 0;
    while i < 6 {
        let (op, base) = rmw[i];
        if !matches!(op, Dec | Inc) {
            t[base | 0x0A] = e(op, Acc, 2, false);
        }
        t[base | 0x06] = e(op, Zp, 5, false);
        t[base | 0x16] = e(op, Zpx, 6, false);
        t[base | 0x0E] = e(op, Abs, 6, false);
        t[base | 0x1E] = e(op, Abx, 7, false);
        i += 1;
    }
    let branches = [
        (Bpl, 0x10),
        (Bmi, 0x30),
        (Bvc, 0x50),
        (Bvs, 0x70),
        (Bcc, 0x90),
        (Bcs, 0xB0),
        (Bne, 0xD0),
        (Beq, 0xF0),
    ];
    let mut i = 0;
    while i < 8 {
        t[branches[i].1] = e(branches[i].0, Rel, 2, false);
        i += 1;
    }
    let implied = [
        (Brk, 0x00, 7),
        (Php, 0x08, 3),
        (Clc, 0x18, 2),
        (Plp, 0x28, 4),
        (Sec, 0x38, 2),
        (Rti, 0x40, 6),
        (Pha, 0x48, 3),
        (Cli, 0x58, 2),
        (Rts, 0x60, 6),
        (Pla, 0x68, 4),
        (Sei, 0x78, 2),
        (Dey, 0x88, 2),
        (Txa, 0x8A, 2),
        (Tya, 0x98, 2),
        (Txs, 0x9A, 2),
        (Tay, 0xA8, 2),
        (Tax, 0xAA, 2),
        (Clv, 0xB8, 2),
        (Tsx, 0xBA, 2),
        (Iny, 0xC8, 2),
        (Dex, 0xCA, 2),
        (Cld, 0xD8, 2),
        (Inx, 0xE8, 2),
        (Nop, 0xEA, 2),
        (Sed, 0xF8, 2),
    ];
    let mut i = 0;
    while i < implied.len() {
        t[implied[i].1] = e(implied[i].0, Imp, implied[i].2, false);
        i += 1;
    }
    t[0x20] = e(Jsr, Abs, 6, false);
    t[0x4C] = e(Jmp, Abs, 3, false);
    t[0x6C] = e(Jmp, Ind, 5, false);
    t[0x24] = e(Bit, Zp, 3, false);
    t[0x2C] = e(Bit, Abs, 4, false);
    t[0x86] = e(Stx, Zp, 3, false);
    t[0x96] = e(Stx, Zpy, 4, false);
    t[0x8E] = e(Stx, Abs, 4, false);
    t[0x84] = e(Sty, Zp, 3, false);
    t[0x94] = e(Sty, Zpx, 4, false);
    t[0x8C] = e(Sty, Abs, 4, false);
    t[0xA2] = e(Ldx, Imm, 2, false);
    t[0xA6] = e(Ldx, Zp, 3, false);
    t[0xB6] = e(Ldx, Zpy, 4, false);
    t[0xAE] = e(Ldx, Abs, 4, false);
    t[0xBE] = e(Ldx, Aby, 4, true);
    t[0xA0] = e(Ldy, Imm, 2, false);
    t[0xA4] = e(Ldy, Zp, 3, false);
    t[0xB4] = e(Ldy, Zpx, 4, false);
    t[0xAC] = e(Ldy, Abs, 4, false);
    t[0xBC] = e(Ldy, Abx, 4, true);
    t[0xE0] = e(Cpx, Imm, 2, false);
    t[0xE4] = e(Cpx, Zp, 3, false);
    t[0xEC] = e(Cpx, Abs, 4, false);
    t[0xC0] = e(Cpy, Imm, 2, false);
    t[0xC4] = e(Cpy, Zp, 3, false);
    t[0xCC] = e(Cpy, Abs, 4, false);
    t
};

/// (Clone: il banco di prova rigioca un tratto da una copia, es. con e senza l'easter egg)
#[derive(Clone)]
pub struct Cpu {
    pub a: u8,
    pub x: u8,
    pub y: u8,
    pub sp: u8,
    pub pc: u16,
    pub p: u8,
    pub mem: Box<[u8; 0x10000]>,
    /// RAM sotto l'I/O ($D000-$DFFF): la vede il 6502 quando la porta $01 spegne l'I/O (bit 0 e
    /// 1 a zero, es. $34), altrimenti a quegli indirizzi ci sono i registri (in `mem`)
    pub under_io: Box<[u8; 0x1000]>,
    /// cicli eseguiti dall'accensione
    pub cycles: u64,
    /// indirizzi (primo, ultimo) delle scritture da registrare in `writes`, es. i registri del SID
    pub watch: Option<(u16, u16)>,
    pub writes: Vec<(u16, u8)>,
    /// con `stamp`, il ciclo di ogni scrittura registrata in `writes` (chi svuota l'una svuota
    /// l'altra)
    pub stamp: bool,
    pub write_cycles: Vec<u64>,
    /// cicli spesi per indirizzo di istruzione, durante `call` (vedi `paddws-c64 profile`)
    pub profile: Option<Vec<u64>>,
    /// linee dei joystick, bit a 0 = premuto come sul C64: porta 2 in $DC00, porta 1 in $DC01
    /// (si sommano, in AND, a quello che il programma scrive nel registro)
    pub joy_port2: u8,
    pub joy_port1: u8,
    /// ciclo dell'interrupt di raster alla riga 250, se il banco di prova esegue un frame: allora
    /// $D012 (e il bit 7 di $D011) danno la riga a cui sarebbe il VIC, con circa 58 cicli della
    /// CPU per riga (i 18.000 cicli utili del frame PAL sulle sue 312 righe)
    pub frame_start: Option<u64>,
    pub cia2: Cia2,
    /// fronte della linea dell'NMI da servire prima della prossima istruzione
    nmi_pending: bool,
    /// NMI serviti dall'accensione
    pub nmis: u64,
    /// la cartuccia, e se è accesa (mode diverso da EF_OFF: solo allora le letture la guardano)
    pub ef: Option<Box<EasyFlash>>,
    ef_on: bool,
    /// cicli spesi nella RAM della cartuccia ($DF00-$DFFF), durante `call`
    pub ef_cycles: u64,
}

impl Default for Cpu {
    fn default() -> Self {
        Self::new()
    }
}

impl Cpu {
    pub fn new() -> Self {
        Self {
            a: 0,
            x: 0,
            y: 0,
            sp: 0xFF,
            pc: 0,
            p: U | I,
            mem: Box::new([0; 0x10000]),
            under_io: Box::new([0; 0x1000]),
            cycles: 0,
            watch: None,
            writes: Vec::new(),
            stamp: false,
            write_cycles: Vec::new(),
            profile: None,
            joy_port2: 0xFF,
            joy_port1: 0xFF,
            frame_start: None,
            cia2: Cia2::default(),
            nmi_pending: false,
            nmis: 0,
            ef: None,
            ef_on: false,
            ef_cycles: 0,
        }
    }

    /// L'indirizzo è nella RAM sotto l'I/O, con l'I/O spento.
    fn ram_under_io(&self, addr: u16) -> bool {
        (0xD000..0xE000).contains(&addr) && self.mem[1] & 3 == 0
    }

    pub fn read(&self, addr: u16) -> u8 {
        if self.ef_on
            && let Some(v) = self.ef.as_ref().and_then(|ef| ef.read(addr, self.mem[1]))
        {
            return v;
        }
        if self.ram_under_io(addr) {
            return self.under_io[addr as usize - 0xD000];
        }
        match addr {
            0xDC00 => self.mem[addr as usize] & self.joy_port2,
            0xDC01 => self.mem[addr as usize] & self.joy_port1,
            0xDD0D => {
                let v = self.cia2.flag.get() as u8 | if self.cia2.line.get() { 0x80 } else { 0 };
                self.cia2.flag.set(false);
                self.cia2.line.set(false);
                v
            }
            0xD011 | 0xD012 if self.frame_start.is_some() => {
                let line = (250 + (self.cycles - self.frame_start.unwrap_or(0)) / 58) % 312;
                if addr == 0xD012 {
                    line as u8
                } else {
                    (self.mem[addr as usize] & 0x7F) | ((line >> 1) as u8 & 0x80)
                }
            }
            _ => self.mem[addr as usize],
        }
    }

    pub fn write(&mut self, addr: u16, v: u8) {
        if self.ef_on
            && let Some(ef) = self.ef.as_mut()
            && ef.write(addr, v)
        {
            return;
        }
        if self.ram_under_io(addr) {
            self.under_io[addr as usize - 0xD000] = v;
            return;
        }
        self.mem[addr as usize] = v;
        if let Some(ef) = self.ef.as_mut() {
            match addr {
                0xDE00 => ef.bank = v & 0x3F,
                0xDE02 => {
                    ef.mode = v & 7;
                    self.ef_on = ef.mode != EF_OFF;
                }
                _ => {}
            }
        }
        let t = &mut self.cia2;
        match addr {
            0xDD04 => t.latch = (t.latch & 0xFF00) | v as u16,
            0xDD05 => {
                t.latch = (t.latch & 0x00FF) | (v as u16) << 8;
                if !t.running {
                    t.left = t.latch as u64 + 1;
                }
            }
            0xDD0D if v & 1 != 0 => {
                t.mask = v & 0x80 != 0;
                self.nmi_edge();
            }
            0xDD0E => {
                t.running = v & 1 != 0;
                t.one_shot = v & 8 != 0;
                if v & 0x10 != 0 {
                    t.left = t.latch as u64 + 1;
                }
            }
            _ => {}
        }
        if let Some((lo, hi)) = self.watch
            && (lo..=hi).contains(&addr)
        {
            self.writes.push((addr, v));
            if self.stamp {
                self.write_cycles.push(self.cycles);
            }
        }
    }

    pub fn read16(&self, addr: u16) -> u16 {
        u16::from_le_bytes([self.read(addr), self.read(addr.wrapping_add(1))])
    }

    /// Copia `data` in memoria a partire da `addr`.
    pub fn load(&mut self, addr: u16, data: &[u8]) {
        let a = addr as usize;
        self.mem[a..a + data.len()].copy_from_slice(data);
    }

    fn fetch(&mut self) -> u8 {
        let v = self.read(self.pc);
        self.pc = self.pc.wrapping_add(1);
        v
    }

    fn fetch16(&mut self) -> u16 {
        let lo = self.fetch();
        let hi = self.fetch();
        u16::from_le_bytes([lo, hi])
    }

    fn push(&mut self, v: u8) {
        self.write(0x100 | self.sp as u16, v);
        self.sp = self.sp.wrapping_sub(1);
    }

    fn pull(&mut self) -> u8 {
        self.sp = self.sp.wrapping_add(1);
        self.read(0x100 | self.sp as u16)
    }

    fn set_nz(&mut self, v: u8) {
        self.p = (self.p & !(N | Z)) | (v & N) | if v == 0 { Z } else { 0 };
    }

    fn flag(&mut self, f: u8, on: bool) {
        if on {
            self.p |= f;
        } else {
            self.p &= !f;
        }
    }

    /// Chiama la subroutine a `addr` (come un JSR) ed esegue finché non ritorna; restituisce i
    /// cicli spesi, JSR e RTS compresi. Si ferma con un errore oltre `max_cycles` o su un
    /// opcode non documentato.
    pub fn call(&mut self, addr: u16, max_cycles: u64) -> Result<u64, String> {
        // indirizzo di ritorno fittizio: quando il PC ci arriva la subroutine è finita
        const SENTINEL: u16 = 0xFFF0;
        let start = self.cycles;
        let ret = SENTINEL.wrapping_sub(1);
        self.push((ret >> 8) as u8);
        self.push(ret as u8);
        self.pc = addr;
        self.cycles += 6;
        while self.pc != SENTINEL {
            let (pc, before) = (self.pc, self.cycles);
            self.step()?;
            if let Some(p) = &mut self.profile {
                p[pc as usize] += self.cycles - before;
            }
            if (0xDF00..0xE000).contains(&pc) {
                self.ef_cycles += self.cycles - before;
            }
            if self.cycles - start > max_cycles {
                return Err(format!("oltre {max_cycles} cicli a ${:04X}", self.pc));
            }
        }
        Ok(self.cycles - start)
    }

    /// Richiesta del timer abilitata: la linea dell'NMI scende (il 6502 sente solo il fronte).
    fn nmi_edge(&mut self) {
        let t = &self.cia2;
        if t.flag.get() && t.mask && !t.line.get() {
            t.line.set(true);
            self.nmi_pending = true;
        }
    }

    /// Il timer A del CIA2 avanza di `n` cicli.
    fn cia2_tick(&mut self, mut n: u64) {
        while self.cia2.running && n >= self.cia2.left {
            n -= self.cia2.left;
            self.cia2.left = self.cia2.latch as u64 + 1;
            self.cia2.flag.set(true);
            if self.cia2.one_shot {
                self.cia2.running = false;
            }
            self.nmi_edge();
        }
        if self.cia2.running {
            self.cia2.left -= n;
        }
    }

    /// Fuori dal programma fino al ciclo `until` (il ciclo principale che aspetta il frame): solo
    /// gli NMI che arrivano intanto.
    pub fn idle(&mut self, until: u64) -> Result<(), String> {
        const IDLE: u16 = 0xFFF0;
        while self.cycles < until {
            if self.nmi_pending {
                let pc = self.pc;
                self.pc = IDLE;
                let start = self.cycles;
                loop {
                    self.step()?;
                    if self.pc == IDLE {
                        break;
                    }
                    if self.cycles - start > 10_000 {
                        return Err(format!("NMI oltre 10000 cicli a ${:04X}", self.pc));
                    }
                }
                self.pc = pc;
                continue;
            }
            let wait = until - self.cycles;
            let wait = if self.cia2.running { wait.min(self.cia2.left) } else { wait };
            self.cycles += wait;
            self.cia2_tick(wait);
        }
        Ok(())
    }

    /// Esegue un'istruzione, prima l'NMI se la linea è scesa (con l'I/O acceso: il gestore
    /// scrive nel SID).
    pub fn step(&mut self) -> Result<(), String> {
        let before = self.cycles;
        if self.nmi_pending {
            self.nmi_pending = false;
            if self.mem[1] & 3 == 0 {
                return Err(format!("NMI con l'I/O spento ($01 = ${:02X}) a ${:04X}", self.mem[1], self.pc));
            }
            self.push((self.pc >> 8) as u8);
            self.push(self.pc as u8);
            self.push((self.p | U) & !B);
            self.p |= I;
            self.pc = self.read16(0xFFFA);
            self.cycles += 7;
            self.nmis += 1;
        }
        self.exec()?;
        self.cia2_tick(self.cycles - before);
        Ok(())
    }

    fn exec(&mut self) -> Result<(), String> {
        let at = self.pc;
        let opcode = self.fetch();
        let Some((op, mode, cycles, page_penalty)) = TABLE[opcode as usize] else {
            return Err(format!("opcode non documentato ${opcode:02X} a ${at:04X}"));
        };
        self.cycles += cycles as u64;
        // indirizzo effettivo (None: implicito, accumulatore, immediato)
        let mut crossed = false;
        let addr: Option<u16> = match mode {
            Mode::Imp | Mode::Acc => None,
            Mode::Imm | Mode::Rel => {
                let a = self.pc;
                self.pc = self.pc.wrapping_add(1);
                Some(a)
            }
            Mode::Zp => Some(self.fetch() as u16),
            Mode::Zpx => Some(self.fetch().wrapping_add(self.x) as u16),
            Mode::Zpy => Some(self.fetch().wrapping_add(self.y) as u16),
            Mode::Abs => Some(self.fetch16()),
            Mode::Abx | Mode::Aby => {
                let base = self.fetch16();
                let a = base.wrapping_add(if mode == Mode::Abx { self.x } else { self.y } as u16);
                crossed = (a ^ base) & 0xFF00 != 0;
                Some(a)
            }
            Mode::Ind => {
                // il bug del 6502: il byte alto non attraversa la pagina
                let ptr = self.fetch16();
                let hi = (ptr & 0xFF00) | (ptr.wrapping_add(1) & 0x00FF);
                Some(u16::from_le_bytes([self.read(ptr), self.read(hi)]))
            }
            Mode::Izx => {
                let zp = self.fetch().wrapping_add(self.x);
                Some(u16::from_le_bytes([
                    self.read(zp as u16),
                    self.read(zp.wrapping_add(1) as u16),
                ]))
            }
            Mode::Izy => {
                let zp = self.fetch();
                let base = u16::from_le_bytes([self.read(zp as u16), self.read(zp.wrapping_add(1) as u16)]);
                let a = base.wrapping_add(self.y as u16);
                crossed = (a ^ base) & 0xFF00 != 0;
                Some(a)
            }
        };
        if page_penalty && crossed {
            self.cycles += 1;
        }
        let operand = |cpu: &Self| cpu.read(addr.unwrap());

        match op {
            Op::Lda => {
                self.a = operand(self);
                self.set_nz(self.a);
            }
            Op::Ldx => {
                self.x = operand(self);
                self.set_nz(self.x);
            }
            Op::Ldy => {
                self.y = operand(self);
                self.set_nz(self.y);
            }
            Op::Sta => self.write(addr.unwrap(), self.a),
            Op::Stx => self.write(addr.unwrap(), self.x),
            Op::Sty => self.write(addr.unwrap(), self.y),
            Op::Ora => {
                self.a |= operand(self);
                self.set_nz(self.a);
            }
            Op::And => {
                self.a &= operand(self);
                self.set_nz(self.a);
            }
            Op::Eor => {
                self.a ^= operand(self);
                self.set_nz(self.a);
            }
            Op::Adc => {
                let m = operand(self);
                self.adc(m);
            }
            Op::Sbc => {
                let m = operand(self);
                self.sbc(m);
            }
            Op::Cmp => {
                let m = operand(self);
                self.compare(self.a, m);
            }
            Op::Cpx => {
                let m = operand(self);
                self.compare(self.x, m);
            }
            Op::Cpy => {
                let m = operand(self);
                self.compare(self.y, m);
            }
            Op::Bit => {
                let m = operand(self);
                self.p = (self.p & !(N | V | Z)) | (m & (N | V)) | if self.a & m == 0 { Z } else { 0 };
            }
            Op::Asl | Op::Lsr | Op::Rol | Op::Ror | Op::Inc | Op::Dec => {
                let v = match addr {
                    None => self.a,
                    Some(a) => self.read(a),
                };
                let carry = self.p & C;
                let r = match op {
                    Op::Asl => {
                        self.flag(C, v & 0x80 != 0);
                        v << 1
                    }
                    Op::Lsr => {
                        self.flag(C, v & 1 != 0);
                        v >> 1
                    }
                    Op::Rol => {
                        self.flag(C, v & 0x80 != 0);
                        v << 1 | carry
                    }
                    Op::Ror => {
                        self.flag(C, v & 1 != 0);
                        v >> 1 | carry << 7
                    }
                    Op::Inc => v.wrapping_add(1),
                    _ => v.wrapping_sub(1),
                };
                self.set_nz(r);
                match addr {
                    None => self.a = r,
                    Some(a) => self.write(a, r),
                }
            }
            Op::Inx => {
                self.x = self.x.wrapping_add(1);
                self.set_nz(self.x);
            }
            Op::Iny => {
                self.y = self.y.wrapping_add(1);
                self.set_nz(self.y);
            }
            Op::Dex => {
                self.x = self.x.wrapping_sub(1);
                self.set_nz(self.x);
            }
            Op::Dey => {
                self.y = self.y.wrapping_sub(1);
                self.set_nz(self.y);
            }
            Op::Tax => {
                self.x = self.a;
                self.set_nz(self.x);
            }
            Op::Tay => {
                self.y = self.a;
                self.set_nz(self.y);
            }
            Op::Txa => {
                self.a = self.x;
                self.set_nz(self.a);
            }
            Op::Tya => {
                self.a = self.y;
                self.set_nz(self.a);
            }
            Op::Tsx => {
                self.x = self.sp;
                self.set_nz(self.x);
            }
            Op::Txs => self.sp = self.x,
            Op::Pha => self.push(self.a),
            Op::Php => self.push(self.p | B | U),
            Op::Pla => {
                self.a = self.pull();
                self.set_nz(self.a);
            }
            Op::Plp => self.p = (self.pull() | U) & !B,
            Op::Clc => self.p &= !C,
            Op::Sec => self.p |= C,
            Op::Cli => self.p &= !I,
            Op::Sei => self.p |= I,
            Op::Cld => self.p &= !D,
            Op::Sed => self.p |= D,
            Op::Clv => self.p &= !V,
            Op::Nop => {}
            Op::Jmp => self.pc = addr.unwrap(),
            Op::Jsr => {
                let ret = self.pc.wrapping_sub(1);
                self.push((ret >> 8) as u8);
                self.push(ret as u8);
                self.pc = addr.unwrap();
            }
            Op::Rts => {
                let lo = self.pull();
                let hi = self.pull();
                self.pc = u16::from_le_bytes([lo, hi]).wrapping_add(1);
            }
            Op::Rti => {
                self.p = (self.pull() | U) & !B;
                let lo = self.pull();
                let hi = self.pull();
                self.pc = u16::from_le_bytes([lo, hi]);
            }
            Op::Brk => {
                let ret = self.pc.wrapping_add(1);
                self.push((ret >> 8) as u8);
                self.push(ret as u8);
                self.push(self.p | B | U);
                self.p |= I;
                self.pc = self.read16(0xFFFE);
            }
            Op::Bpl | Op::Bmi | Op::Bvc | Op::Bvs | Op::Bcc | Op::Bcs | Op::Bne | Op::Beq => {
                let taken = match op {
                    Op::Bpl => self.p & N == 0,
                    Op::Bmi => self.p & N != 0,
                    Op::Bvc => self.p & V == 0,
                    Op::Bvs => self.p & V != 0,
                    Op::Bcc => self.p & C == 0,
                    Op::Bcs => self.p & C != 0,
                    Op::Bne => self.p & Z == 0,
                    _ => self.p & Z != 0,
                };
                if taken {
                    let offset = operand(self) as i8;
                    let target = self.pc.wrapping_add(offset as u16);
                    self.cycles += if (target ^ self.pc) & 0xFF00 != 0 { 2 } else { 1 };
                    self.pc = target;
                }
            }
        }
        Ok(())
    }

    fn compare(&mut self, r: u8, m: u8) {
        self.flag(C, r >= m);
        self.set_nz(r.wrapping_sub(m));
    }

    fn adc(&mut self, m: u8) {
        let carry = (self.p & C) as u16;
        let bin = self.a as u16 + m as u16 + carry;
        // V e (sul 6502 NMOS) N e Z vengono dal risultato binario anche in decimale
        let v = (!(self.a ^ m) & (self.a ^ bin as u8) & 0x80) != 0;
        if self.p & D == 0 {
            self.flag(C, bin > 0xFF);
            self.flag(V, v);
            self.a = bin as u8;
            self.set_nz(self.a);
            return;
        }
        let mut lo = (self.a & 0x0F) as u16 + (m & 0x0F) as u16 + carry;
        if lo > 9 {
            lo += 6;
        }
        let mut r = (self.a & 0xF0) as u16 + (m & 0xF0) as u16 + if lo > 0x0F { 0x10 } else { 0 } + (lo & 0x0F);
        // N e V dal risultato prima della correzione delle decine
        self.flag(N, r & 0x80 != 0);
        self.flag(V, (!(self.a ^ m) & (self.a ^ r as u8) & 0x80) != 0);
        self.flag(Z, bin as u8 == 0);
        if r > 0x9F {
            r += 0x60;
        }
        self.flag(C, r > 0xFF);
        self.a = r as u8;
    }

    fn sbc(&mut self, m: u8) {
        let borrow = 1 - (self.p & C) as i16;
        let bin = self.a as i16 - m as i16 - borrow;
        let r8 = bin as u8;
        self.flag(V, ((self.a ^ m) & (self.a ^ r8) & 0x80) != 0);
        self.flag(C, bin >= 0);
        self.set_nz(r8);
        if self.p & D == 0 {
            self.a = r8;
            return;
        }
        // sul 6502 NMOS i flag in decimale sono quelli della sottrazione binaria
        let mut lo = (self.a & 0x0F) as i16 - (m & 0x0F) as i16 - borrow;
        let mut hi = (self.a >> 4) as i16 - (m >> 4) as i16;
        if lo < 0 {
            lo -= 6;
            hi -= 1;
        }
        if hi < 0 {
            hi -= 6;
        }
        self.a = ((hi as u8) << 4) | (lo as u8 & 0x0F);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(code: &[u8]) -> Cpu {
        let mut cpu = Cpu::new();
        cpu.load(0x1000, code);
        cpu.call(0x1000, 10_000).unwrap();
        cpu
    }

    #[test]
    fn loads_adds_and_counts_cycles() {
        // LDA #$10; CLC; ADC #$20; STA $02; RTS
        let mut cpu = Cpu::new();
        cpu.load(0x1000, &[0xA9, 0x10, 0x18, 0x69, 0x20, 0x85, 0x02, 0x60]);
        let cycles = cpu.call(0x1000, 1000).unwrap();
        assert_eq!(cpu.read(0x02), 0x30);
        assert_eq!(cycles, 6 + 2 + 2 + 2 + 3 + 6);
    }

    #[test]
    fn page_crossing_costs_a_cycle() {
        // LDX #$01; LDA $10FF,X; RTS
        let mut cpu = Cpu::new();
        cpu.load(0x2000, &[0xA2, 0x01, 0xBD, 0xFF, 0x10, 0x60]);
        let cycles = cpu.call(0x2000, 1000).unwrap();
        assert_eq!(cycles, 6 + 2 + 5 + 6);
    }

    #[test]
    fn decimal_addition() {
        // SED; CLC; LDA #$19; ADC #$28; STA $02; CLD; RTS
        let cpu = run(&[0xF8, 0x18, 0xA9, 0x19, 0x69, 0x28, 0x85, 0x02, 0xD8, 0x60]);
        assert_eq!(cpu.read(0x02), 0x47);
    }

    /// Test funzionale di Klaus Dormann (6502_functional_test.bin, caricato a $0000, partenza a
    /// $0400): se riesce si ferma in un ciclo infinito a $3469. Va scaricato a parte in
    /// `target/6502_functional_test.bin` (licenza GPL, non è nel repository).
    #[test]
    #[ignore]
    fn klaus_dormann_functional_test() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../target/6502_functional_test.bin");
        let bin = std::fs::read(path).expect("manca target/6502_functional_test.bin");
        let mut cpu = Cpu::new();
        cpu.load(0, &bin);
        cpu.pc = 0x0400;
        let mut last = 0xFFFF;
        loop {
            cpu.step().unwrap();
            if cpu.pc == last {
                break;
            }
            last = cpu.pc;
        }
        assert_eq!(cpu.pc, 0x3469, "fermo a ${:04X}", cpu.pc);
    }
}
