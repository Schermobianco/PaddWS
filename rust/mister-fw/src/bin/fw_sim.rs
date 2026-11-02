//! Banco di prova del firmware del core MiSTer: esegue il firmware (l'immagine della BRAM in
//! `mister/rtl/gen/pong_fw_b*.hex`, la stessa che va nella sintesi) su un emulatore RV32IM con un
//! modello dei registri di `pong_logic_rv.v`, e lo confronta con le tracce di paddws-trace (le
//! cartelle di `mister/sim`): parole di stato a ogni tick e comandi delle CPU.
//!
//! Uso: paddws-fw-sim [--fw CARTELLA] [--native] TRACCIA...
//!   --fw      cartella dei file pong_fw_b0..3.hex (default ../mister/rtl/gen, da rust/)
//!   --native  esegue `Engine` sul PC invece che nell'emulatore (più veloce, stessa verifica)
//!   --ticks N solo i primi N tick di ogni traccia
//!   --profile SIMBOLI  istruzioni per funzione, con i simboli di `llvm-nm -C -S` sul firmware

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Instant;

use paddws_mister_fw::engine::{Bus, Engine};
use paddws_mister_fw::map::*;
use paddws_mister_fw::words::{self, Layout, TRACE_WORDS, WORDS};

// ------------------------------------------------------------------ registri di pong_logic_rv

/// Modello dei registri di `pong_logic_rv.v` (vedi `paddws_mister_fw::map`).
#[derive(Default)]
struct Regs {
    epoch: u32,
    step: bool,
    busy: bool,
    config: u32,
    seed: u32,
    cpu: u32,
    cpu_seeds: [u32; 2],
    input: u32,
    input2: u32,
    tick_hz: u32,
    field: u32,
    words: Vec<u32>,
    panic: Option<u32>,
    /// letture di STATUS: la prima segna la fine dell'avvio
    status_reads: u64,
}

impl Regs {
    fn new(tick_hz: u32) -> Self {
        Self {
            tick_hz,
            field: 320 | 240 << 16,
            words: vec![0; WORDS],
            ..Self::default()
        }
    }

    fn reset(&mut self) {
        self.epoch = (self.epoch + 1) & STATUS_EPOCH;
        self.step = false;
        self.busy = true;
    }

    fn step(&mut self, input: u32, input2: u32) {
        self.input = input;
        self.input2 = input2;
        self.step = true;
        self.busy = true;
    }
}

impl Bus for Regs {
    fn read(&mut self, reg: u32) -> u32 {
        match reg {
            R_STATUS => {
                self.status_reads += 1;
                self.epoch | (self.step as u32) << 8
            }
            R_CONFIG => self.config,
            R_SEED => self.seed,
            R_CPU => self.cpu,
            R_CPU_SEED0 => self.cpu_seeds[0],
            R_CPU_SEED1 => self.cpu_seeds[1],
            R_INPUT => self.input,
            R_INPUT2 => self.input2,
            R_TICK_HZ => self.tick_hz,
            R_FIELD => self.field,
            _ => 0,
        }
    }

    fn write(&mut self, reg: u32, value: u32) {
        match reg {
            W_DONE => {
                if value & STATUS_EPOCH == self.epoch {
                    self.busy = false;
                    self.step = false;
                }
            }
            W_PANIC => self.panic = Some(value),
            W_PATCH_ACK => {}
            r if (W_WORD0..W_WORD0 + 4 * WORDS as u32).contains(&r) => {
                self.words[((r - W_WORD0) / 4) as usize] = value;
            }
            _ => {}
        }
    }
}

// ------------------------------------------------------------------ emulatore RV32IM

struct Rv32 {
    x: [u32; 32],
    pc: u32,
    mem: Vec<u8>,
    instret: u64,
    min_sp: u32,
    /// istruzioni eseguite per indirizzo (con --profile)
    prof: Option<Vec<u64>>,
}

impl Rv32 {
    fn new(image: Vec<u8>) -> Self {
        let mut mem = image;
        mem.resize(RAM_SIZE as usize, 0);
        Self {
            x: [0; 32],
            pc: RAM_BASE,
            mem,
            instret: 0,
            min_sp: u32::MAX,
            prof: None,
        }
    }

    fn ram(&self, a: u32, n: u32) -> Result<usize, String> {
        let o = a.wrapping_sub(RAM_BASE);
        if o as u64 + n as u64 > RAM_SIZE as u64 || !a.is_multiple_of(n) {
            return Err(format!(
                "accesso a {a:#010x} ({n} byte) fuori dalla RAM o non allineato, pc {:#010x}",
                self.pc
            ));
        }
        Ok(o as usize)
    }

    fn load(&mut self, io: &mut Regs, a: u32, n: u32) -> Result<u32, String> {
        if a >= IO_BASE {
            if n != 4 || !a.is_multiple_of(4) {
                return Err(format!("lettura di un registro non a 32 bit a {a:#010x}"));
            }
            return Ok(io.read(a - IO_BASE));
        }
        let o = self.ram(a, n)?;
        let m = &self.mem;
        Ok(match n {
            1 => m[o] as u32,
            2 => u16::from_le_bytes([m[o], m[o + 1]]) as u32,
            _ => u32::from_le_bytes([m[o], m[o + 1], m[o + 2], m[o + 3]]),
        })
    }

    fn store(&mut self, io: &mut Regs, a: u32, n: u32, v: u32) -> Result<(), String> {
        if a >= IO_BASE {
            if n != 4 || !a.is_multiple_of(4) {
                return Err(format!("scrittura di un registro non a 32 bit a {a:#010x}"));
            }
            io.write(a - IO_BASE, v);
            return Ok(());
        }
        let o = self.ram(a, n)?;
        match n {
            1 => self.mem[o] = v as u8,
            2 => self.mem[o..o + 2].copy_from_slice(&(v as u16).to_le_bytes()),
            _ => self.mem[o..o + 4].copy_from_slice(&v.to_le_bytes()),
        }
        Ok(())
    }

    /// Esegue un'istruzione.
    fn step(&mut self, io: &mut Regs) -> Result<(), String> {
        let pc = self.pc;
        let o = self.ram(pc, 4)?;
        let ins = u32::from_le_bytes([self.mem[o], self.mem[o + 1], self.mem[o + 2], self.mem[o + 3]]);
        let opc = ins & 0x7F;
        let rd = ((ins >> 7) & 31) as usize;
        let f3 = (ins >> 12) & 7;
        let rs1 = ((ins >> 15) & 31) as usize;
        let rs2 = ((ins >> 20) & 31) as usize;
        let f7 = ins >> 25;
        let a = self.x[rs1];
        let b = self.x[rs2];
        let imm_i = (ins as i32 >> 20) as u32;
        let mut next = pc.wrapping_add(4);
        let mut wr = None;
        let illegal = || format!("istruzione non valida {ins:#010x} a {pc:#010x}");
        match opc {
            0x37 => wr = Some(ins & 0xFFFF_F000),
            0x17 => wr = Some(pc.wrapping_add(ins & 0xFFFF_F000)),
            0x6F => {
                let imm = ((ins as i32 >> 31) as u32 & 0xFFF0_0000)
                    | (ins & 0x000F_F000)
                    | ((ins >> 9) & 0x800)
                    | ((ins >> 20) & 0x7FE);
                wr = Some(next);
                next = pc.wrapping_add(imm);
            }
            0x67 => {
                wr = Some(next);
                next = a.wrapping_add(imm_i) & !1;
            }
            0x63 => {
                let imm = ((ins as i32 >> 31) as u32 & 0xFFFF_F000)
                    | ((ins << 4) & 0x800)
                    | ((ins >> 20) & 0x7E0)
                    | ((ins >> 7) & 0x1E);
                let t = match f3 {
                    0 => a == b,
                    1 => a != b,
                    4 => (a as i32) < (b as i32),
                    5 => (a as i32) >= (b as i32),
                    6 => a < b,
                    7 => a >= b,
                    _ => return Err(illegal()),
                };
                if t {
                    next = pc.wrapping_add(imm);
                }
            }
            0x03 => {
                let addr = a.wrapping_add(imm_i);
                wr = Some(match f3 {
                    0 => self.load(io, addr, 1)? as i8 as i32 as u32,
                    1 => self.load(io, addr, 2)? as i16 as i32 as u32,
                    2 => self.load(io, addr, 4)?,
                    4 => self.load(io, addr, 1)?,
                    5 => self.load(io, addr, 2)?,
                    _ => return Err(illegal()),
                });
            }
            0x23 => {
                let imm = ((ins as i32 >> 20) as u32 & !0x1F) | ((ins >> 7) & 0x1F);
                let addr = a.wrapping_add(imm);
                match f3 {
                    0 => self.store(io, addr, 1, b)?,
                    1 => self.store(io, addr, 2, b)?,
                    2 => self.store(io, addr, 4, b)?,
                    _ => return Err(illegal()),
                }
            }
            0x13 => {
                let sh = rs2 as u32;
                wr = Some(match f3 {
                    0 => a.wrapping_add(imm_i),
                    1 => a << sh,
                    2 => ((a as i32) < (imm_i as i32)) as u32,
                    3 => (a < imm_i) as u32,
                    4 => a ^ imm_i,
                    5 if f7 & 0x20 != 0 => ((a as i32) >> sh) as u32,
                    5 => a >> sh,
                    6 => a | imm_i,
                    _ => a & imm_i,
                });
            }
            0x33 if f7 == 1 => {
                let (sa, sb) = (a as i32, b as i32);
                wr = Some(match f3 {
                    0 => a.wrapping_mul(b),
                    1 => ((sa as i64 * sb as i64) >> 32) as u32,
                    2 => ((sa as i64 * b as i64) >> 32) as u32,
                    3 => ((a as u64 * b as u64) >> 32) as u32,
                    4 if b == 0 => u32::MAX,
                    4 => sa.wrapping_div(sb) as u32,
                    5 if b == 0 => u32::MAX,
                    5 => a / b,
                    6 if b == 0 => a,
                    6 => sa.wrapping_rem(sb) as u32,
                    _ if b == 0 => a,
                    _ => a % b,
                });
            }
            0x33 => {
                let sh = b & 31;
                wr = Some(match (f3, f7) {
                    (0, 0) => a.wrapping_add(b),
                    (0, 0x20) => a.wrapping_sub(b),
                    (1, 0) => a << sh,
                    (2, 0) => ((a as i32) < (b as i32)) as u32,
                    (3, 0) => (a < b) as u32,
                    (4, 0) => a ^ b,
                    (5, 0) => a >> sh,
                    (5, 0x20) => ((a as i32) >> sh) as u32,
                    (6, 0) => a | b,
                    (7, 0) => a & b,
                    _ => return Err(illegal()),
                });
            }
            0x0F => {} // fence
            _ => return Err(illegal()),
        }
        if let Some(v) = wr
            && rd != 0
        {
            self.x[rd] = v;
            if rd == 2 {
                self.min_sp = self.min_sp.min(v);
            }
        }
        if let Some(p) = self.prof.as_mut() {
            p[(pc >> 2) as usize] += 1;
        }
        self.pc = next;
        self.instret += 1;
        Ok(())
    }
}

// ------------------------------------------------------------------ firmware: emulato o nativo

/// Istruzioni al massimo per una richiesta: oltre, il firmware è bloccato.
const LIMIT: u64 = 50_000_000;

enum Machine {
    Emu(Box<Rv32>),
    Native(Box<Engine>),
}

impl Machine {
    /// Avvio fino alla prima lettura di STATUS (fine di `Engine::new`): istruzioni usate.
    fn boot(emu: Option<&[u8]>, regs: &mut Regs) -> Result<(Self, u64), String> {
        match emu {
            Some(image) => {
                let mut cpu = Box::new(Rv32::new(image.to_vec()));
                while regs.status_reads == 0 {
                    cpu.step(regs)?;
                    if cpu.instret > LIMIT {
                        return Err("avvio senza fine".into());
                    }
                }
                let n = cpu.instret;
                Ok((Machine::Emu(cpu), n))
            }
            None => Ok((Machine::Native(Box::new(Engine::new(regs))), 0)),
        }
    }

    /// Esegue finché l'HDL non torna libero; restituisce le istruzioni (0 nativo).
    fn serve(&mut self, regs: &mut Regs) -> Result<u64, String> {
        match self {
            Machine::Emu(cpu) => {
                let start = cpu.instret;
                while regs.busy {
                    cpu.step(regs)?;
                    if let Some(code) = regs.panic {
                        return Err(format!("panic del firmware ({code:#x}) a pc {:#010x}", cpu.pc));
                    }
                    if cpu.instret - start > LIMIT {
                        return Err("il firmware non risponde".into());
                    }
                }
                Ok(cpu.instret - start)
            }
            Machine::Native(engine) => {
                engine.poll(regs);
                if regs.busy {
                    return Err("il firmware non ha finito la richiesta".into());
                }
                Ok(0)
            }
        }
    }

    fn min_sp(&self) -> Option<u32> {
        match self {
            Machine::Emu(cpu) => Some(cpu.min_sp),
            Machine::Native(_) => None,
        }
    }
}

// ------------------------------------------------------------------ tracce

fn parse_config(text: &str) -> HashMap<String, u64> {
    let mut out = HashMap::new();
    for line in text.lines() {
        let line = line.split("//").next().unwrap_or("").trim();
        let Some(rest) = line.strip_prefix("localparam") else {
            continue;
        };
        let Some((lhs, rhs)) = rest.split_once('=') else {
            continue;
        };
        let name = lhs.split_whitespace().last().unwrap_or("").to_string();
        let v = rhs.trim().trim_end_matches(';').trim();
        let value = if let Some((_, lit)) = v.split_once('\'') {
            let (base, digits) = lit.split_at(1);
            let radix = if base.eq_ignore_ascii_case("h") { 16 } else { 10 };
            u64::from_str_radix(digits, radix).ok()
        } else {
            v.parse::<i64>().ok().map(|x| x as u64)
        };
        if let Some(value) = value {
            out.insert(name, value);
        }
    }
    out
}

struct Trace {
    name: String,
    cfg: HashMap<String, u64>,
    inputs: Vec<u64>,
    states: Vec<Vec<u32>>,
}

fn load_trace(dir: &Path) -> Result<Trace, String> {
    let read = |f: &str| fs::read_to_string(dir.join(f)).map_err(|e| format!("{}: {e}", dir.join(f).display()));
    let cfg = parse_config(&read("trace_config.vh")?);
    let inputs = read("trace_input.hex")?
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| u64::from_str_radix(l.trim(), 16).map_err(|e| format!("trace_input.hex: {e}")))
        .collect::<Result<Vec<_>, _>>()?;
    let states = read("trace_state.hex")?
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| {
            let l = l.trim();
            (0..l.len() / 8)
                .map(|i| u32::from_str_radix(&l[8 * i..8 * i + 8], 16).map_err(|e| format!("trace_state.hex: {e}")))
                .collect::<Result<Vec<_>, _>>()
        })
        .collect::<Result<Vec<_>, _>>()?;
    let name = dir
        .file_name()
        .map_or_else(|| dir.display().to_string(), |n| n.to_string_lossy().into_owned());
    Ok(Trace {
        name,
        cfg,
        inputs,
        states,
    })
}

#[derive(Default)]
struct Report {
    ticks: usize,
    boot: u64,
    reset: u64,
    max: u64,
    max_at: usize,
    sum: u64,
    /// massimo di 4 tick consecutivi (un frame del core)
    frame: u64,
    min_sp: Option<u32>,
    /// stack usato dall'avvio (Engine::new)
    boot_sp: Option<u32>,
}

fn run_trace(t: &Trace, emu: Option<&[u8]>, max_ticks: usize, prof: &mut Option<Vec<u64>>) -> Result<Report, String> {
    let get = |k: &str| {
        t.cfg
            .get(k)
            .copied()
            .ok_or_else(|| format!("{}: manca {k} in trace_config.vh", t.name))
    };
    let next = get("P_NEXT")? != 0;
    let kinds = get("P_KINDS")?;
    let supers = get("P_SUPERS")? != 0;
    let layout = Layout {
        next,
        kinds: next && kinds != 0x3F,
        supers: next && supers,
    };
    let seed = get("P_SEED")? as u32;
    let mut regs = Regs::new(get("P_TICK_HZ")? as u32);
    regs.config = (get("P_PLAYERS")? == 2) as u32
        | ((get("P_EVO")? != 0) as u32) << 1
        | (next as u32) << 2
        | (supers as u32) << 3
        | (get("P_DIFFICULTY")? as u32 & 3) << 4
        | (get("P_LOADOUT0")? as u32) << 6
        | (get("P_LOADOUT1")? as u32) << 15
        | (kinds as u32) << 24;
    regs.seed = seed;
    regs.cpu = get("P_CPU_LEVEL0")? as u32 | (get("P_CPU_LEVEL1")? as u32) << 4 | (get("P_CONTROL")? as u32) << 8;
    regs.cpu_seeds = [seed, seed ^ 1];
    let cpu_sides = get("P_CPU_SIDES")? as u32;

    let mut rep = Report::default();
    let (mut machine, boot) = Machine::boot(emu, &mut regs)?;
    rep.boot = boot;
    rep.boot_sp = machine.min_sp();
    if let Machine::Emu(cpu) = &mut machine {
        cpu.min_sp = u32::MAX;
    }
    if let (Machine::Emu(cpu), Some(p)) = (&mut machine, prof.as_mut()) {
        cpu.prof = Some(std::mem::take(p));
    }
    regs.reset();
    rep.reset = machine.serve(&mut regs)?;

    let n = t.inputs.len().min(t.states.len()).min(max_ticks);
    let mut window = [0u64; 4];
    let mut got = [0u32; TRACE_WORDS];
    for tick in 0..n {
        let input = t.inputs[tick];
        regs.step(input as u32, ((input >> 32) as u32 & 15) | cpu_sides << 4);
        let cost = machine.serve(&mut regs)?;
        rep.sum += cost;
        if cost > rep.max {
            rep.max = cost;
            rep.max_at = tick + 1;
        }
        window[tick % 4] = cost;
        rep.frame = rep.frame.max(window.iter().sum());

        let full: [u32; WORDS] = regs.words.clone().try_into().unwrap();
        // comandi effettivi (con quelli delle CPU) uguali a quelli registrati
        let want_in = (input as u32, (input >> 32) as u32 & 15);
        let have_in = (full[words::W_INPUT], full[words::W_SPECIALS]);
        if want_in != have_in {
            return Err(format!(
                "{}: tick {}, comandi: attesi {:08x} mosse {:x}, ottenuti {:08x} mosse {:x}",
                t.name,
                tick + 1,
                want_in.0,
                want_in.1,
                have_in.0,
                have_in.1
            ));
        }
        let len = words::pack(&full, layout, &mut got);
        let want = &t.states[tick];
        if want.len() != len {
            return Err(format!(
                "{}: tick {}, {} parole invece di {}",
                t.name,
                tick + 1,
                len,
                want.len()
            ));
        }
        if let Some(w) = (0..len).find(|&w| got[w] != want[w]) {
            return Err(format!(
                "{}: tick {}, parola {w}: attesa {:08x}, ottenuta {:08x}",
                t.name,
                tick + 1,
                want[w],
                got[w]
            ));
        }
        rep.ticks += 1;
    }
    rep.min_sp = machine.min_sp();
    if let (Machine::Emu(cpu), Some(p)) = (&mut machine, prof.as_mut()) {
        *p = cpu.prof.take().unwrap_or_default();
    }
    Ok(rep)
}

// ------------------------------------------------------------------ immagine della BRAM

/// Immagine della RAM dai quattro file per byte (`pong_fw_b0.hex` = byte 0 di ogni parola).
fn load_image(dir: &Path) -> Result<Vec<u8>, String> {
    let mut lanes = Vec::new();
    for b in 0..4 {
        let p = dir.join(format!("pong_fw_b{b}.hex"));
        let text = fs::read_to_string(&p).map_err(|e| format!("{}: {e}", p.display()))?;
        let bytes = text
            .lines()
            .map(|l| l.split("//").next().unwrap_or("").trim())
            .filter(|l| !l.is_empty())
            .map(|l| u8::from_str_radix(l, 16).map_err(|e| format!("{}: {e}", p.display())))
            .collect::<Result<Vec<_>, _>>()?;
        lanes.push(bytes);
    }
    let words = lanes[0].len();
    if lanes.iter().any(|l| l.len() != words) || words * 4 > RAM_SIZE as usize {
        return Err("file pong_fw_b*.hex di lunghezze diverse o troppo lunghi".into());
    }
    Ok((0..words * 4).map(|i| lanes[i % 4][i / 4]).collect())
}

/// Istruzioni per funzione: simboli nel formato di `llvm-nm -C -S` (indirizzo, dimensione, tipo, nome).
fn print_profile(path: &Path, prof: &[u64]) {
    let Ok(text) = fs::read_to_string(path) else {
        eprintln!("{}: non leggibile", path.display());
        return;
    };
    let total: u64 = prof.iter().sum();
    let mut rows = Vec::new();
    for line in text.lines() {
        let mut it = line.splitn(4, ' ');
        let (Some(a), Some(sz), Some(_), Some(name)) = (it.next(), it.next(), it.next(), it.next()) else {
            continue;
        };
        let (Ok(a), Ok(sz)) = (u32::from_str_radix(a, 16), u32::from_str_radix(sz, 16)) else {
            continue;
        };
        let n: u64 = prof[(a / 4) as usize..((a + sz) / 4).min(prof.len() as u32) as usize]
            .iter()
            .sum();
        if n > 0 {
            rows.push((n, name.to_string()));
        }
    }
    rows.sort_by_key(|r| std::cmp::Reverse(r.0));
    println!("profilo ({total} istruzioni):");
    for (n, name) in rows.iter().take(25) {
        println!(
            "  {:6.2}%  {}",
            100.0 * *n as f64 / total as f64,
            &name[..name.len().min(110)]
        );
    }
}

fn main() -> ExitCode {
    let mut fw_dir = PathBuf::from("../mister/rtl/gen");
    let mut native = false;
    let mut max_ticks = usize::MAX;
    let mut dirs = Vec::new();
    let mut symbols: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--fw" => fw_dir = args.next().expect("--fw CARTELLA").into(),
            "--native" => native = true,
            "--profile" => symbols = Some(args.next().expect("--profile SIMBOLI").into()),
            "--ticks" => max_ticks = args.next().and_then(|v| v.parse().ok()).expect("--ticks N"),
            "-h" | "--help" => {
                println!("Uso: paddws-fw-sim [--fw CARTELLA] [--native] [--ticks N] TRACCIA...");
                return ExitCode::SUCCESS;
            }
            _ => dirs.push(PathBuf::from(a)),
        }
    }
    let image = if native {
        None
    } else {
        match load_image(&fw_dir) {
            Ok(i) => Some(i),
            Err(e) => {
                eprintln!("{e}");
                return ExitCode::FAILURE;
            }
        }
    };
    if let Some(i) = &image {
        println!("firmware: {} byte da {}", i.len(), fw_dir.display());
    }
    let mut prof = symbols.as_ref().map(|_| vec![0u64; RAM_SIZE as usize / 4]);
    let mut failed = 0;
    let mut worst = (0u64, String::new());
    let mut worst_frame = 0u64;
    for dir in &dirs {
        let started = Instant::now();
        let result =
            load_trace(dir).and_then(|t| run_trace(&t, image.as_deref(), max_ticks, &mut prof).map(|r| (t.name, r)));
        match result {
            Ok((name, r)) => {
                if image.is_some() {
                    let stack = r.min_sp.map_or(0, |sp| RAM_SIZE - sp);
                    let boot_stack = r.boot_sp.map_or(0, |sp| RAM_SIZE - sp);
                    println!(
                        "PASS {name}: {} tick; istruzioni: avvio {}, nuova partita {}, tick max {} (tick {}) media {}, 4 tick max {}; stack: avvio {boot_stack}, partita {stack} byte ({:.1} s)",
                        r.ticks,
                        r.boot,
                        r.reset,
                        r.max,
                        r.max_at,
                        r.sum / r.ticks.max(1) as u64,
                        r.frame,
                        started.elapsed().as_secs_f64()
                    );
                    if r.max > worst.0 {
                        worst = (r.max, name.clone());
                    }
                    worst_frame = worst_frame.max(r.frame);
                } else {
                    println!("PASS {name}: {} tick (nativo)", r.ticks);
                }
            }
            Err(e) => {
                println!("FAIL {e}");
                failed += 1;
            }
        }
    }
    if image.is_some() && !dirs.is_empty() {
        println!(
            "tick peggiore: {} istruzioni ({}), 4 tick consecutivi al massimo {}",
            worst.0, worst.1, worst_frame
        );
    }
    if let (Some(path), Some(p)) = (&symbols, &prof) {
        print_profile(path, p);
    }
    if failed > 0 {
        println!("{failed} tracce non coincidono");
        ExitCode::FAILURE
    } else {
        println!("Firmware identico al core Rust su tutte le tracce");
        ExitCode::SUCCESS
    }
}
