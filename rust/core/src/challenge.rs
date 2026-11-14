//! Modalità CHALLENGE: da soli contro una scala di avversari controllati dal computer.
//!
//! Ogni livello è un avversario con il suo tipo di racchetta (uno diverso per livello), i suoi
//! bonus, l'abilità della CPU e la velocità della palla; il giocatore sceglie bonus e racchetta
//! una volta, all'inizio. Le partite NEXT sono brevi (`Rung::points`); vincendo si passa al
//! livello dopo, perdendo si può continuare con un gettone (punteggio azzerato).
//!
//! Punti arcade: colpi, scatti riusciti, SUPER e punti segnati, con un moltiplicatore che cresce
//! con la lunghezza dello scambio; alla vittoria un premio che cresce con il livello, più uno se
//! l'avversario non ha fatto punti. Classifica dei 10 punteggi migliori con le iniziali.
//!
//! Nuovo sfidante: durante la presentazione di un livello, la
//! partita contro la CPU o il livello superato un secondo giocatore può entrare con un credito.
//! I due giocano una partita NEXT a `Rung::points` con la velocità della palla del livello in
//! corso; il vincitore riprende quel livello da 0-0 dal suo lato (`Rung::sides`) con
//! `Score::after_duel` punti. Il flusso delle schermate è nelle versioni, qui solo le regole.
//!
//! Solo interi e nessuna divisione nel tick, come il resto del core.

use crate::game::{Event, Events, Match, Side};
use crate::next::{Bonus, LOADOUT_SIZE, PaddleKind};

/// Un livello: l'avversario e la partita.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rung {
    /// racchetta della CPU
    pub kind: PaddleKind,
    /// livello della CPU (da `DIFFICULTY_LEVELS`: i livelli propri di CHALLENGE in `cpu.rs`)
    pub cpu: u8,
    /// difficoltà della partita, che decide la velocità della palla (0-3)
    pub speed: u8,
    /// bonus della CPU
    pub loadout: [Bonus; LOADOUT_SIZE],
    /// punti per vincere
    pub points: u16,
}

pub const LEVELS: usize = 7;

/// I livelli, dal più facile al boss finale: ognuno ha un livello proprio della CPU e la
/// velocità della palla di una delle difficoltà. Regolati con `paddws-trace --challenge-stats`
/// perché un giocatore simulato medio con il joystick vinca il primo livello il 95% delle
/// volte e il boss circa una su quattro.
pub const RUNGS: [Rung; LEVELS] = {
    use Bonus::*;
    use PaddleKind::*;
    [
        Rung {
            kind: Arcade,
            cpu: 4,
            speed: 0,
            loadout: [Slow, Curve, Smash],
            points: 5,
        },
        Rung {
            kind: Twist,
            cpu: 5,
            speed: 0,
            loadout: [Curve, Steer, Slow],
            points: 5,
        },
        Rung {
            kind: Hammer,
            cpu: 6,
            speed: 0,
            loadout: [Smash, Teleport, Slow],
            points: 5,
        },
        Rung {
            kind: Titan,
            cpu: 7,
            speed: 1,
            loadout: [Teleport, Slow, Ghost],
            points: 5,
        },
        Rung {
            kind: Blaster,
            cpu: 8,
            speed: 1,
            loadout: [Smash, Ghost, Curve],
            points: 5,
        },
        Rung {
            kind: Rush,
            cpu: 9,
            speed: 1,
            loadout: [Smash, Steer, Teleport],
            points: 5,
        },
        Rung {
            kind: Guardian,
            cpu: 10,
            speed: 2,
            loadout: [Ghost, Steer, Smash],
            points: 5,
        },
    ]
};

impl Rung {
    /// Difficoltà della partita (velocità della palla) con la difficoltà scelta nel menu: la
    /// scala è tarata su NORMAL (1) con il joystick; ogni livello in più o in meno sposta la
    /// velocità di un gradino (con spinner e paddle conviene HARD o EXPERT).
    pub const fn speed_at(&self, difficulty: u8) -> u8 {
        let s = self.speed as i32 + difficulty as i32 - 1;
        let max = crate::params::DIFFICULTY_LEVELS as i32 - 1;
        (if s < 0 {
            0
        } else if s > max {
            max
        } else {
            s
        }) as u8
    }

    /// Livello della CPU con la difficoltà scelta nel menu: a NORMAL quello del livello, a HARD ed
    /// EXPERT quello di uno e due livelli dopo (oltre il GUARDIAN i livelli in più di
    /// `CHALLENGE_SKILLS`), a EASY quello del livello prima (mai sotto il primo).
    pub const fn cpu_at(&self, difficulty: u8) -> u8 {
        let first = crate::params::DIFFICULTY_LEVELS as i32;
        let last = crate::cpu::CPU_LEVELS as i32 - 1;
        let c = self.cpu as i32 + difficulty as i32 - 1;
        (if c < first {
            first
        } else if c > last {
            last
        } else {
            c
        }) as u8
    }

    /// Bonus e racchette della partita del livello con il giocatore sul lato `human` e la CPU
    /// sull'altro: indici come `Match::new_next_paddles` (0 sinistra, 1 destra). Dopo una sfida
    /// tra due giocatori il vincitore continua dal suo lato, anche a destra.
    pub const fn sides(
        &self,
        human: Side,
        loadout: [Bonus; LOADOUT_SIZE],
        kind: Option<PaddleKind>,
    ) -> ([[Bonus; LOADOUT_SIZE]; 2], [Option<PaddleKind>; 2]) {
        match human {
            Side::Left => ([loadout, self.loadout], [kind, Some(self.kind)]),
            Side::Right => ([self.loadout, loadout], [Some(self.kind), kind]),
        }
    }
}

/// Punti arcade.
pub const HIT_POINTS: u32 = 10;
pub const BOOST_POINTS: u32 = 40;
pub const SUPER_POINTS: u32 = 100;
pub const POINT_POINTS: u32 = 100;
/// premi della vittoria, per numero di livello (1-7)
pub const WIN_POINTS: u32 = 1000;
pub const PERFECT_POINTS: u32 = 2000;
/// il moltiplicatore sale di uno ogni `RALLY_STEP` colpi dello scambio, fino a `MAX_MULTIPLIER`
pub const RALLY_STEP: u16 = 4;
pub const MAX_MULTIPLIER: u32 = 8;

/// Punteggio arcade di chi gioca dal lato `side`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Score {
    pub side: Side,
    pub total: u32,
    /// colpi dello scambio in corso (di tutti e due)
    pub rally: u16,
}

impl Score {
    pub const fn new(side: Side) -> Self {
        Self {
            side,
            total: 0,
            rally: 0,
        }
    }

    pub fn multiplier(&self) -> u32 {
        (1 + (self.rally / RALLY_STEP) as u32).min(MAX_MULTIPLIER)
    }

    /// Conta i punti del tick appena giocato: `before` è il punteggio della partita prima del
    /// tick, `m` la partita dopo. Restituisce i punti guadagnati.
    pub fn on_tick(&mut self, m: &Match, before: [u16; 2], events: Events) -> u32 {
        let me = self.side as usize;
        let mut gained = 0;
        if events.has(Event::Hit) || events.has(Event::Boost) || events.has(Event::Super) {
            // chi ha colpito: la palla ora si allontana da lui
            let hitter = if m.ball.vx > 0 { Side::Left } else { Side::Right };
            self.rally = self.rally.saturating_add(1);
            if hitter == self.side {
                gained += HIT_POINTS * self.multiplier();
                if events.has(Event::Boost) {
                    gained += BOOST_POINTS;
                }
                if events.has(Event::Super) {
                    gained += SUPER_POINTS;
                }
            }
        }
        if events.has(Event::Score) {
            if m.score[me] > before[me] {
                gained += POINT_POINTS * self.multiplier();
            }
            self.rally = 0;
        }
        self.total = self.total.saturating_add(gained);
        gained
    }

    /// Premi per la vittoria al livello `level` (da 0): (vittoria, partita perfetta).
    pub fn win_bonus(level: usize, opponent_points: u16) -> (u32, u32) {
        let n = level as u32 + 1;
        (
            WIN_POINTS * n,
            if opponent_points == 0 { PERFECT_POINTS * n } else { 0 },
        )
    }

    /// Premio per chi vince la sfida tra due giocatori al livello `level` (da 0): quanto la
    /// vittoria di quel livello, `WIN_POINTS * (level + 1)`, senza il premio della partita
    /// perfetta.
    pub const fn duel_bonus(level: usize) -> u32 {
        WIN_POINTS * (level as u32 + 1)
    }

    /// Punteggio con cui il vincitore della sfida continua la scala: il campione (`champion`
    /// è il suo punteggio prima della sfida) tiene il suo, lo sfidante parte da 0; a tutti e due
    /// va `duel_bonus(level)`. I punti della partita tra i due non contano.
    pub const fn after_duel(champion: u32, champion_won: bool, level: usize) -> u32 {
        let base = if champion_won { champion } else { 0 };
        base.saturating_add(Self::duel_bonus(level))
    }
}

/// Una riga della classifica.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Entry {
    /// iniziali (A-Z, 0-9 o spazio)
    pub name: [u8; 3],
    pub score: u32,
    /// livello raggiunto (1-7; 8 = scala finita)
    pub level: u8,
}

pub const TABLE_SIZE: usize = 10;

/// Classifica dei punteggi migliori, dal più alto.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Table {
    pub entries: [Entry; TABLE_SIZE],
}

impl Default for Table {
    /// Classifica iniziale: punteggi da battere, da 20000 a 2000.
    fn default() -> Self {
        let mut entries = [Entry {
            name: *b"PWS",
            score: 0,
            level: 1,
        }; TABLE_SIZE];
        for (i, e) in entries.iter_mut().enumerate() {
            e.score = 2000 * (TABLE_SIZE - i) as u32;
            e.level = (LEVELS - i * LEVELS / TABLE_SIZE) as u8;
        }
        Self { entries }
    }
}

impl Table {
    /// Posizione che avrebbe il punteggio (0 = primo), `None` se non entra in classifica. A
    /// parità di punti il nuovo va sotto.
    pub fn rank(&self, score: u32) -> Option<usize> {
        self.entries.iter().position(|e| score > e.score)
    }

    /// Inserisce il punteggio e restituisce la posizione.
    pub fn insert(&mut self, entry: Entry) -> Option<usize> {
        let i = self.rank(entry.score)?;
        self.entries.copy_within(i..TABLE_SIZE - 1, i + 1);
        self.entries[i] = entry;
        Some(i)
    }
}
