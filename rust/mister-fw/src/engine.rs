//! Ciclo del firmware: nuova partita e tick, con i comandi delle CPU avversarie.
//!
//! Allo stesso `reset` e agli stessi comandi dà le stesse parole di stato delle tracce di
//! paddws-trace, con le CPU avversarie del core Rust. Generico sul bus ([`Bus`]): nel firmware gli
//! accessi sono letture e scritture volatili dei registri, nei banchi di prova un modello.

use paddws_core::{Bonus, Capsule, Control, Cpu, DIFFICULTY_LEVELS, Input, Match, PaddleKind, Params, Side, Tuning};

use core::mem::MaybeUninit;
use core::ptr::addr_of_mut;

use crate::map::*;
use crate::words;

/// Accesso ai registri di `pong_logic_rv` (indirizzi relativi a `IO_BASE`).
pub trait Bus {
    fn read(&mut self, reg: u32) -> u32;
    fn write(&mut self, reg: u32, value: u32);
}

/// Partita in corso con le due CPU (usate solo dai lati che l'HDL indica a ogni tick).
struct Game {
    m: Match,
    cpus: [Cpu; 2],
}

pub struct Engine {
    /// parametri per ogni difficoltà, calcolati all'avvio: `Params::new` usa la virgola mobile
    /// (in software sul RV32IM) e così una nuova partita costa solo una copia
    params: [Params; DIFFICULTY_LEVELS as usize],
    game: Option<Game>,
    /// numero dell'ultima partita servita (`STATUS[7:0]`)
    epoch: u32,
}

/// Le parole di stato vanno direttamente nei registri dell'HDL, una scrittura ciascuna.
struct Regs<'a, B: Bus>(&'a mut B);

impl<B: Bus> words::Sink for Regs<'_, B> {
    #[inline(always)]
    fn put(&mut self, i: usize, v: u32) {
        self.0.write(W_WORD0 + 4 * i as u32, v);
    }
}

/// Codice a 4 bit di un bonus (8 o più = nessuno), come nelle parole di stato.
fn bonus(code: u32) -> Option<Bonus> {
    Bonus::ALL.get(code as usize).copied()
}

/// Una modifica di prova (`R_PATCH0`): il campo `field & 0xFF` con indice `field >> 8`.
fn patch(m: &mut Match, field: u32, value: u32) {
    let i = ((field >> 8) & 0xFF) as usize;
    if field & 0xFF == PATCH_SCORE {
        m.score[i & 1] = value as u16;
        return;
    }
    let Some(n) = m.next.as_mut() else { return };
    let pl = &mut n.players[i & 1];
    match field & 0xFF {
        PATCH_ARMED => pl.armed = bonus(value),
        PATCH_RESERVE => n.players[(i / 3) & 1].reserve[i % 3] = bonus(value),
        PATCH_SELECTED => pl.selected = value as u8,
        PATCH_COOLDOWN => pl.cooldown = value,
        PATCH_METER => pl.meter = value as u8,
        PATCH_CAPSULE => {
            let c = &mut n.capsules[i & 3];
            *c = bonus(value).map(|b| Capsule {
                bonus: b,
                ..c.unwrap_or(Capsule {
                    x: 0,
                    y: 0,
                    vx: 0,
                    vy: 0,
                    bonus: b,
                })
            });
        }
        f @ PATCH_CAPSULE_X..=PATCH_CAPSULE_VY => {
            if let Some(c) = n.capsules[i & 3].as_mut() {
                let v = value as i32;
                match f {
                    PATCH_CAPSULE_X => c.x = v,
                    PATCH_CAPSULE_Y => c.y = v,
                    PATCH_CAPSULE_VX => c.vx = v,
                    _ => c.vy = v,
                }
            }
        }
        _ => {}
    }
}

fn control(code: u32) -> Control {
    match code & 3 {
        1 => Control::Spinner,
        2 => Control::Keyboard,
        _ => Control::Joystick,
    }
}

fn kind(code: u32) -> Option<PaddleKind> {
    PaddleKind::ALL.get((code & 7) as usize).copied()
}

fn loadout(code: u32) -> [Bonus; 3] {
    core::array::from_fn(|k| Bonus::ALL[((code >> (3 * k)) & 7) as usize])
}

impl Engine {
    /// Avvio: legge dall'HDL frequenza e campo e calcola i parametri delle quattro difficoltà.
    pub fn new<B: Bus>(bus: &mut B) -> Self {
        let mut slot = MaybeUninit::uninit();
        Self::init(&mut slot, bus);
        // SAFETY: `init` ha scritto tutti i campi
        unsafe { slot.assume_init() }
    }

    /// Come `new`, ma costruisce il motore direttamente in `slot`: nel firmware è in .bss, così i
    /// parametri (alcuni KB) non passano dallo stack.
    pub fn init<'a, B: Bus>(slot: &'a mut MaybeUninit<Self>, bus: &mut B) -> &'a mut Self {
        let tick_hz = bus.read(R_TICK_HZ);
        let field = bus.read(R_FIELD);
        let p = slot.as_mut_ptr();
        for d in 0..DIFFICULTY_LEVELS {
            let params = Params::new(&Tuning {
                width: field & 0xFFFF,
                height: field >> 16,
                difficulty: d,
                tick_hz,
                ..Tuning::default()
            });
            // SAFETY: `p` punta a un Engine non inizializzato; si scrive un campo alla volta, senza leggerlo
            unsafe { addr_of_mut!((*p).params[d as usize]).write(params) };
        }
        // SAFETY: come sopra; dopo queste scritture tutti i campi sono inizializzati
        unsafe {
            addr_of_mut!((*p).game).write(None);
            addr_of_mut!((*p).epoch).write(0);
            slot.assume_init_mut()
        }
    }

    /// Serve una richiesta dell'HDL, se c'è: prima una nuova partita, poi un tick.
    /// Restituisce `true` se ha lavorato.
    pub fn poll<B: Bus>(&mut self, bus: &mut B) -> bool {
        let status = bus.read(R_STATUS);
        let epoch = status & STATUS_EPOCH;
        if epoch != self.epoch {
            self.epoch = epoch;
            self.start(bus);
            if let Some(g) = &self.game {
                words::encode_state(&g.m, 0, &mut Regs(bus));
            }
            bus.write(W_WORD0 + 4 * words::W_INPUT as u32, 0);
            bus.write(W_WORD0 + 4 * words::W_SPECIALS as u32, 0);
        } else if status & STATUS_STEP != 0 {
            self.tick(bus);
        } else {
            return false;
        }
        bus.write(W_DONE, epoch);
        true
    }

    /// Nuova partita dagli ingressi di `pong_logic_rv` letti al `reset` (stesse regole: NEXT solo in
    /// due, EVO non in NEXT, mosse speciali solo in NEXT).
    fn start<B: Bus>(&mut self, bus: &mut B) {
        let c = bus.read(R_CONFIG);
        let seed = bus.read(R_SEED);
        let cpu = bus.read(R_CPU);
        let cpu_seeds = [bus.read(R_CPU_SEED0), bus.read(R_CPU_SEED1)];
        let two = c & 1 != 0;
        let evo = c & 2 != 0;
        let next = c & 4 != 0 && two;
        let supers = c & 8 != 0;
        let params = self.params[((c >> 4) & 3) as usize].clone();
        let m = if next {
            let mut m = Match::new_next_paddles(
                params,
                [loadout(c >> 6), loadout(c >> 15)],
                [kind(c >> 24), kind(c >> 27)],
                seed,
            );
            m.set_super_moves(supers);
            m
        } else {
            Match::new(params, if two { 2 } else { 1 }, evo, seed)
        };
        let cpu_for = |side: Side| {
            let i = side as usize;
            Cpu::new(&m.params, ((cpu >> (4 * i)) & 15) as u8, side, cpu_seeds[i])
                .with_control(control(cpu >> (8 + 2 * i)))
        };
        let cpus = [cpu_for(Side::Left), cpu_for(Side::Right)];
        self.game = Some(Game { m, cpus });
    }

    /// Un tick: comandi dell'HDL, quelli delle CPU per i lati indicati, `Match::step`, parole di
    /// stato. Senza partita (l'HDL non chiede tick prima di un reset) non fa nulla.
    fn tick<B: Bus>(&mut self, bus: &mut B) {
        let Some(g) = self.game.as_mut() else { return };
        let patches = bus.read(R_PATCH_N);
        if patches != 0 {
            for k in 0..patches.min(PATCH_MAX) {
                let at = R_PATCH0 + 8 * k;
                let (field, value) = (bus.read(at), bus.read(at + 4));
                patch(&mut g.m, field, value);
            }
            bus.write(W_PATCH_ACK, 0);
        }
        let word = bus.read(R_INPUT);
        let extra = bus.read(R_INPUT2);
        let mut input: Input = words::decode_input(word, extra & 15);
        for side in Side::BOTH {
            let i = side as usize;
            if extra >> (4 + i) & 1 != 0 {
                // la CPU comanda tutto tranne lo sparo del BLASTER (bit 7), che resta dell'HDL:
                // le tracce lo usano per le raffiche che provano il caricatore
                let fire = input.players[i].fire;
                input.players[i] = g.cpus[i].input(&g.m);
                input.players[i].fire |= fire;
            }
        }
        let events = g.m.step(&input);
        words::encode_state(&g.m, events.bits(), &mut Regs(bus));
        bus.write(W_WORD0 + 4 * words::W_INPUT as u32, words::encode_input(&input));
        bus.write(W_WORD0 + 4 * words::W_SPECIALS as u32, words::encode_specials(&input));
    }
}
