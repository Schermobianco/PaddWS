//! Avversario controllato dal computer.
//!
//! Produce a ogni tick lo stesso `PlayerInput` di un giocatore vero, guardando solo
//! lo stato della partita. A ogni palla in arrivo decide dove mirare: ogni tanto
//! sbaglia apposta (più spesso ai livelli bassi), altrimenti mira con un piccolo
//! errore per variare l'angolo. Ai livelli alti prevede il punto d'arrivo, ai bassi
//! insegue la palla. Quando la palla si allontana torna al centro o va a prendere
//! una capsula NEXT; usa lo scatto in avanti e i bonus (il BULLET solo per salvare una palla
//! che non prenderebbe, vedi `Cpu::bullet_rescue`). Il livello è quello della difficoltà.
//!
//! Con le mosse speciali accese (`Next::super_moves`) usa anche quelle, con regole fatte solo di
//! confronti, somme e shift (vedi `Cpu::special`); spente, il generatore non viene toccato e i
//! comandi sono identici a quelli senza mosse.
//!
//! Come il resto del core: interi, nessuna divisione nel tick, generatore proprio con
//! seme esplicito (non tocca quello della partita), quindi è ripetibile e si può
//! portare in hardware.

use crate::fixed::{self, Fx, mul, mul_recip};
use crate::game::{Match, PlayerInput, Side};
use crate::next::{Bonus, Capsule, MAX_SPECIAL_LEVEL, PaddleKind, Special};
use crate::params::{DIFFICULTY_LEVELS, Params, TICK_HZ};
use crate::rng::Rng;

/// Abilità di un livello (pixel a 800x480, scalati sull'altezza del campo; tick e probabilità per
/// tick a 240 Hz, convertiti sulla frequenza della simulazione da `CpuLevel::new`).
#[derive(Clone, Copy)]
struct Skill {
    /// errore di mira massimo quando non sbaglia, in pixel
    error_px: i32,
    /// palle mancate apposta, per mille
    miss_permille: u32,
    /// tempo di reazione quando la palla parte verso di sé, in tick (240 al secondo)
    reaction_ticks: u32,
    /// reagisce quando la palla è entro questa frazione di campo (millesimi)
    react_permille: i32,
    /// usa l'accelerazione rapida per i recuperi lunghi
    fast: bool,
    /// mira al punto d'arrivo previsto invece che alla palla
    predict: bool,
    /// scatto in avanti: una probabilità su N per tick quando la palla è a tiro (0 = mai)
    forward_odds: u32,
    /// NEXT: una probabilità su N per tick di attivare un bonus quando conviene
    bonus_odds: u32,
}

const SKILLS: [Skill; DIFFICULTY_LEVELS as usize] = [
    Skill {
        error_px: 30,
        miss_permille: 200,
        reaction_ticks: 70,
        react_permille: 500,
        fast: false,
        predict: false,
        forward_odds: 0,
        bonus_odds: 480,
    },
    Skill {
        error_px: 32,
        miss_permille: 320,
        reaction_ticks: 60,
        react_permille: 850,
        fast: true,
        predict: true,
        forward_odds: 45,
        bonus_odds: 180,
    },
    Skill {
        error_px: 28,
        miss_permille: 300,
        reaction_ticks: 56,
        react_permille: 900,
        fast: true,
        predict: true,
        forward_odds: 30,
        bonus_odds: 120,
    },
    Skill {
        error_px: 24,
        miss_permille: 220,
        reaction_ticks: 46,
        react_permille: 1000,
        fast: true,
        predict: true,
        forward_odds: 15,
        bonus_odds: 60,
    },
];

/// Livelli della CPU oltre il boss finale, per il GUARDIAN a HARD ed EXPERT (`Rung::cpu_at`).
pub const CHALLENGE_EXTRA: usize = 2;

/// Livelli della modalità CHALLENGE, più graduali di quelli della difficoltà: vanno dal
/// primo avversario (più facile di EASY) al boss finale, poi i `CHALLENGE_EXTRA` oltre il boss.
/// Indici `DIFFICULTY_LEVELS..CPU_LEVELS`.
const CHALLENGE_SKILLS: [Skill; crate::challenge::LEVELS + CHALLENGE_EXTRA] = [
    Skill {
        error_px: 34,
        miss_permille: 240,
        reaction_ticks: 80,
        react_permille: 450,
        fast: false,
        predict: false,
        forward_odds: 0,
        bonus_odds: 480,
    },
    Skill {
        error_px: 32,
        miss_permille: 200,
        reaction_ticks: 72,
        react_permille: 500,
        fast: false,
        predict: false,
        forward_odds: 0,
        bonus_odds: 400,
    },
    Skill {
        error_px: 30,
        miss_permille: 175,
        reaction_ticks: 62,
        react_permille: 650,
        fast: true,
        predict: true,
        forward_odds: 200,
        bonus_odds: 360,
    },
    Skill {
        error_px: 30,
        miss_permille: 185,
        reaction_ticks: 64,
        react_permille: 700,
        fast: true,
        predict: true,
        forward_odds: 160,
        bonus_odds: 300,
    },
    Skill {
        error_px: 28,
        miss_permille: 160,
        reaction_ticks: 58,
        react_permille: 750,
        fast: true,
        predict: true,
        forward_odds: 120,
        bonus_odds: 240,
    },
    Skill {
        error_px: 30,
        miss_permille: 170,
        reaction_ticks: 60,
        react_permille: 780,
        fast: true,
        predict: true,
        forward_odds: 110,
        bonus_odds: 180,
    },
    // GUARDIAN, il boss finale
    Skill {
        error_px: 28,
        miss_permille: 150,
        reaction_ticks: 56,
        react_permille: 820,
        fast: true,
        predict: true,
        forward_odds: 90,
        bonus_odds: 140,
    },
    // oltre il boss: il GUARDIAN a HARD
    Skill {
        error_px: 26,
        miss_permille: 125,
        reaction_ticks: 52,
        react_permille: 860,
        fast: true,
        predict: true,
        forward_odds: 70,
        bonus_odds: 110,
    },
    // ... e a EXPERT
    Skill {
        error_px: 24,
        miss_permille: 100,
        reaction_ticks: 48,
        react_permille: 900,
        fast: true,
        predict: true,
        forward_odds: 55,
        bonus_odds: 90,
    },
];

/// Livelli della CPU: i primi `DIFFICULTY_LEVELS` sono quelli della difficoltà, poi quelli di
/// CHALLENGE (con i due oltre il boss).
pub const CPU_LEVELS: u8 = DIFFICULTY_LEVELS + (crate::challenge::LEVELS + CHALLENGE_EXTRA) as u8;

const fn skill(level: u8) -> Skill {
    if level < DIFFICULTY_LEVELS {
        SKILLS[level as usize]
    } else if level < CPU_LEVELS {
        CHALLENGE_SKILLS[(level - DIFFICULTY_LEVELS) as usize]
    } else {
        CHALLENGE_SKILLS[CHALLENGE_SKILLS.len() - 1]
    }
}

/// Valori di un livello già scalati sul campo: servono anche a generare i parametri
/// del core MiSTer (paddws-trace).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CpuLevel {
    pub max_error: Fx,
    pub miss_permille: u32,
    pub reaction_ticks: u32,
    pub react: Fx,
    pub fast: bool,
    pub predict: bool,
    pub forward_odds: u32,
    pub bonus_odds: u32,
    /// reciproci (Q8.24) della velocità massima della palla in Classic/EVO e in NEXT:
    /// errore e palle mancate crescono con la velocità, come per una persona
    pub inv_speed: i32,
    pub inv_speed_next: i32,
    /// tick da avanzata, con la palla che si allontana, prima di tornare a casa
    pub return_ticks: u32,
    /// BULLET: lo attiva solo con la palla a meno di `|dx| << bullet_shift` dalla racchetta (circa
    /// mezzo secondo di volo, arrotondato in basso a una potenza di 2)
    pub bullet_shift: u32,
}

/// Tick a 240 Hz -> tick della simulazione (invariato a 240 Hz).
fn scale_ticks(ticks: u32, tick_hz: u32) -> u32 {
    ((ticks as u64 * tick_hz as u64 + TICK_HZ as u64 / 2) / TICK_HZ as u64) as u32
}

/// "Una probabilità su N per tick" a 240 Hz -> stessa probabilità al secondo alla frequenza della
/// simulazione (0 resta "mai", invariato a 240 Hz).
fn scale_odds(odds: u32, tick_hz: u32) -> u32 {
    if odds == 0 {
        0
    } else {
        scale_ticks(odds, tick_hz).max(1)
    }
}

impl CpuLevel {
    pub fn new(params: &Params, level: u8) -> Self {
        let s = skill(level);
        let hz = params.tick_hz;
        // calcolati una volta, fuori dal tick
        let max_error = (fixed::int(s.error_px) as i64 * params.height as i64 / fixed::int(480) as i64) as Fx;
        Self {
            max_error,
            miss_permille: s.miss_permille,
            reaction_ticks: scale_ticks(s.reaction_ticks, hz),
            react: (params.width as i64 * s.react_permille as i64 / 1000) as Fx,
            fast: s.fast,
            predict: s.predict,
            forward_odds: scale_odds(s.forward_odds, hz),
            bonus_odds: scale_odds(s.bonus_odds, hz),
            inv_speed: fixed::recip(params.max_ball_speed_2p),
            inv_speed_next: fixed::recip(params.max_ball_speed_next),
            return_ticks: scale_ticks(RETURN_TICKS, hz),
            bullet_shift: (hz >> 1).max(1).ilog2(),
        }
    }
}

/// Dopo lo scatto in avanti la CPU resta avanzata 0,3 s (in tick a 240 Hz) con la palla che si
/// allontana, poi torna a casa: lo scatto si vede, come quando lo fa una persona.
const RETURN_TICKS: u32 = 72;

/// Come si comanda la racchetta: cambia rapidità e precisione dei movimenti. Le simulazioni
/// dei bonus lo usano per tener conto di chi gioca con la tastiera o il joystick, che sono un
/// handicap rispetto a uno spinner.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Control {
    /// spinner o encoder: posizione diretta, con la velocità massima di una mano sulla manopola
    Spinner,
    /// joystick: digitale, accelerazione rapida con un pulsante (secondo il livello)
    Joystick,
    /// tastiera: digitale, accelerazione rapida solo con il doppio tocco (di rado), mira meno fine
    Keyboard,
}

/// Velocità massima della manopola dello spinner: px per tick (a 240 Hz) a 800x480.
const KNOB_PX_PER_TICK: i32 = 6;

/// Stato iniziale del generatore della CPU dal seme (come `Rng::new`).
pub const fn cpu_seed(seed: u32) -> u32 {
    seed ^ 0xC0FF_EE11
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cpu {
    side: Side,
    rng: Rng,
    /// errore di mira per la palla in arrivo (Fx)
    error: Fx,
    max_error: Fx,
    miss_permille: u32,
    /// la palla veniva verso di sé al tick precedente, e un RISING STRIKE doveva ancora impennarsi
    was_coming: bool,
    was_rising: bool,
    /// ultimo punto di arrivo scelto: durante la reazione e con la palla fantasma nascosta si resta lì
    last_target: Fx,
    /// tick da quando la palla viene verso di sé, e tempo di reazione
    since_coming: u32,
    reaction_ticks: u32,
    inv_speed: i32,
    inv_speed_next: i32,
    /// distanza orizzontale dalla racchetta entro cui insegue la palla
    react: Fx,
    fast: bool,
    predict: bool,
    forward_odds: u32,
    bonus_odds: u32,
    control: Control,
    /// posizione della manopola (y del centro della racchetta) con lo spinner
    knob: Fx,
    knob_speed: Fx,
    /// tick passati con la racchetta avanzata e la palla che si allontana, e quanti se ne aspettano
    /// prima di tornare a casa
    away_ticks: u32,
    return_ticks: u32,
    bullet_shift: u32,
}

impl Cpu {
    /// Avversario per il lato `side`, al livello di difficoltà `level`.
    pub fn new(params: &Params, level: u8, side: Side, seed: u32) -> Self {
        let l = CpuLevel::new(params, level);
        Self {
            side,
            rng: Rng::new(cpu_seed(seed)),
            error: 0,
            max_error: l.max_error,
            miss_permille: l.miss_permille,
            was_coming: false,
            was_rising: false,
            last_target: params.height / 2,
            since_coming: 0,
            reaction_ticks: l.reaction_ticks,
            inv_speed: l.inv_speed,
            inv_speed_next: l.inv_speed_next,
            react: l.react,
            fast: l.fast,
            predict: l.predict,
            forward_odds: l.forward_odds,
            bonus_odds: l.bonus_odds,
            control: Control::Joystick,
            knob: params.height / 2,
            knob_speed: (fixed::int(KNOB_PX_PER_TICK) as i64 * params.height as i64 * TICK_HZ as i64
                / (fixed::int(480) as i64 * params.tick_hz as i64)) as Fx,
            away_ticks: 0,
            return_ticks: l.return_ticks,
            bullet_shift: l.bullet_shift,
        }
    }

    /// Stessa CPU con un altro modo di comandare la racchetta (default: joystick).
    pub const fn with_control(mut self, control: Control) -> Self {
        self.control = control;
        self
    }

    pub const fn side(&self) -> Side {
        self.side
    }

    /// Comandi per il prossimo tick.
    pub fn input(&mut self, m: &Match) -> PlayerInput {
        let mut cmd = PlayerInput::default();
        let i = self.side as usize;
        let pad = &m.paddles[i];
        let b = &m.ball;
        let blaster = m.paddle_kind(self.side) == Some(PaddleKind::Blaster);

        let coming = match self.side {
            Side::Left => b.vx < 0,
            Side::Right => b.vx > 0,
        };
        if coming && !self.was_coming {
            self.since_coming = 0;
            // velocità della palla rispetto alla massima normale (1.0): più è veloce, più si sbaglia
            let inv = if m.next.is_some() {
                self.inv_speed_next
            } else {
                self.inv_speed
            };
            let speed = mul_recip(mul(b.vx, b.boost).abs(), inv);
            let miss = ((self.miss_permille as i64 * speed as i64) >> fixed::FRAC_BITS) as u32;
            // palla nuova in arrivo: a volte la si manca apposta, oltre il bordo della racchetta
            self.error = if self.rng.below(1000) < miss {
                (pad.height / 2 + b.radius * 3) * self.rng.sign()
            } else {
                mul(mul(self.max_error, self.rng.unit()), speed)
            };
        }
        // RISING STRIKE in arrivo che s'impenna: come una persona, la CPU ci mette il suo tempo di
        // reazione ad accorgersene (resta dov'era diretta), poi rifà la previsione
        let rising = m.next.as_ref().is_some_and(|n| n.rise_break.is_some());
        if coming && self.was_rising && !rising {
            self.since_coming = 0;
        }
        self.was_rising = rising;
        // durante l'attesa della battuta si riparte da capo: la mira si sceglie quando la palla parte
        self.was_coming = coming && !m.serving();
        let distance = (b.x - pad.home_x).abs();

        // dove andare: la palla in arrivo, altrimenti una capsula NEXT verso di sé, altrimenti il centro
        let mut target = m.params.height / 2;
        // come una persona: la palla fantasma nascosta non si vede
        let hidden = m.next.as_ref().is_some_and(|n| n.ball_hidden(&m.params, m.tick));
        // la curva, la palla fantasma e quella guidata non si possono prevedere: si guarda dov'è la palla
        let curving = m
            .next
            .as_ref()
            .is_some_and(|n| n.curve != 0 || n.ghost.is_some() || n.steer.is_some());
        self.since_coming = self.since_coming.saturating_add(1);
        let reacting = self.since_coming > self.reaction_ticks;
        // dove crede che arrivi la palla, senza l'errore di mira (solo con la palla in arrivo, già
        // vista e visibile): serve alle mosse speciali
        let mut aim = None;
        if coming && distance < self.react && !m.serving() && reacting {
            target = if hidden {
                self.last_target
            } else {
                let y = if self.predict && !curving {
                    arrival_y(m, self.side)
                } else {
                    b.y
                };
                aim = Some(y);
                y + self.error
            };
        } else if coming && !m.serving() && !reacting {
            target = self.last_target; // non si è ancora accorta della palla
        } else if let Some(n) = &m.next
            && let Some(c) = n.capsules.iter().flatten().find(|c| self.wants(m, c))
        {
            target = c.y;
        }
        self.last_target = target;
        let diff = target - pad.y;
        let steering = m.next.as_ref().is_some_and(|n| n.steer == Some(self.side));
        match self.control {
            // STEER: la racchetta è ferma e su/giù sterzano la palla, lontano dalla racchetta avversaria;
            // con lo spinner si gira la manopola di un quarto di racchetta da quella parte
            _ if steering => {
                let up = b.y >= m.paddles[self.side.opponent() as usize].y;
                if self.control == Control::Spinner {
                    let (half, quarter) = (pad.height / 2, pad.height / 4);
                    let knob = if up { pad.y + quarter } else { pad.y - quarter };
                    self.knob = knob.clamp(half, m.params.height - half); // la manopola ha un fine corsa
                    cmd.top_offset = Some(fixed::floor(m.params.height - half - self.knob));
                } else {
                    cmd.direction = if up { 1 } else { -1 };
                }
            }
            Control::Spinner => {
                // la manopola porta la racchetta dove serve, alla velocità di una mano; con TELEPORT
                // attivo e la palla in arrivo la si lascia ferma: salterà da sola
                let aiming = m
                    .next
                    .as_ref()
                    .is_some_and(|n| n.players[i].armed == Some(crate::next::Bonus::Teleport) && coming);
                let half = pad.height / 2;
                self.knob = pad.y;
                if !aiming {
                    let goal = target.clamp(half, m.params.height - half);
                    self.knob += (goal - self.knob).clamp(-self.knob_speed, self.knob_speed);
                    cmd.top_offset = Some(fixed::floor(m.params.height - half - self.knob));
                }
            }
            Control::Joystick | Control::Keyboard => {
                let keyboard = self.control == Control::Keyboard;
                let dead = if keyboard { pad.height / 5 } else { pad.height / 8 };
                cmd.direction = if diff > dead {
                    1
                } else if diff < -dead {
                    -1
                } else {
                    0
                };
                // con la tastiera il doppio tocco riesce solo per i recuperi molto lunghi
                let far = if keyboard { pad.height * 2 } else { pad.height };
                cmd.fast = self.fast && diff.abs() > far;
            }
        }

        if blaster {
            // BLASTER: spara quando una capsula che vuole è davanti alla racchetta
            let pl = &m.next.as_ref().unwrap().players[i];
            let aligned = m.next.as_ref().unwrap().capsules.iter().flatten().any(|c| {
                let ahead = match self.side {
                    Side::Left => c.x > pad.right(),
                    Side::Right => c.x < pad.left(),
                };
                ahead && (c.y - pad.y).abs() <= m.params.capsule_half && self.wants(m, c)
            });
            let odds = if self.forward_odds > 0 { self.forward_odds } else { 60 };
            // un colpo alla volta: la CPU non spreca il caricatore sulla stessa capsula
            let idle = pl.shots.iter().all(Option::is_none);
            let fire = pl.can_fire() && idle && aligned && self.rng.below(odds) == 0;
            // senza scatto si spara con il suo tasto
            if m.params.blaster_dash {
                cmd.fire = fire;
            } else {
                cmd.forward = fire;
            }
        }

        // scatto in avanti solo quando lo scatto intercetta davvero la palla (stessa area del
        // core: tra la faccia della racchetta a casa e quella avanzata); poi si torna a casa
        if (m.evo || m.next.is_some()) && !(blaster && !m.params.blaster_dash) {
            let half = fixed::int(fixed::floor(pad.width >> 1));
            let in_reach = match self.side {
                Side::Left => pad.home_x + half <= b.left() && b.left() <= pad.fwd_x + half,
                Side::Right => pad.fwd_x - half <= b.right() && b.right() <= pad.home_x - half,
            } && b.bottom() <= pad.top()
                && b.top() >= pad.bottom();
            let strike =
                pad.at_home() && coming && in_reach && self.forward_odds > 0 && self.rng.below(self.forward_odds) == 0;
            // avanzata con la palla che si allontana: resta lì un momento, così lo scatto si vede
            let back = if !pad.at_home() && !coming {
                self.away_ticks = self.away_ticks.saturating_add(1);
                self.away_ticks > self.return_ticks
            } else {
                self.away_ticks = 0;
                false
            };
            cmd.forward = back || strike;
        }

        // NEXT: attiva il bonus selezionato mentre la palla arriva; ogni tanto ne sceglie un altro.
        // Il BULLET si usa come gli altri; in più, in emergenza (vedi `Cpu::bullet_rescue`) ci si va
        // e lo si attiva con probabilità per tick 16 volte più alta (`bonus_odds >> 4`): la palla è
        // vicina. Con un BULLET già armato o in corso (di chiunque) quello selezionato non parte:
        // si passa al successivo
        if let Some(n) = &m.next {
            let pl = &n.players[i];
            let ready = pl.count() > 0 && pl.armed.is_none() && pl.cooldown == 0 && coming && !m.serving();
            let rescue = pl.has_bullet() && ready && n.bullet.is_none() && self.bullet_rescue(m, aim, distance);
            let on_bullet = pl.selected_bonus() == Some(Bonus::Bullet);
            if rescue {
                if on_bullet {
                    cmd.activate = self.rng.below((self.bonus_odds >> 4).max(1)) == 0;
                } else {
                    cmd.select = true;
                }
            } else if on_bullet && n.bullet.is_some() {
                cmd.select = pl.count() > 1;
            } else {
                if ready {
                    cmd.activate = self.rng.below(self.bonus_odds) == 0;
                }
                if pl.count() > 1 && self.rng.below(self.bonus_odds * 2) == 0 {
                    cmd.select = true;
                }
            }
        }
        if m.super_moves() && !cmd.activate {
            cmd.special = self.special(m, aim);
        }
        cmd
    }

    /// Mosse speciali, con le stesse probabilità per tick dei bonus (`bonus_odds`: i livelli alti le
    /// usano prima e più spesso). Solo confronti, somme e shift, per la CPU HDL:
    ///
    /// Le due mosse sono tiri: la CPU ne arma una quando la palla arriva, la racchetta copre già
    /// il punto d'arrivo previsto (`aim`, entro mezza racchetta) e non ha deciso di mancarla
    /// (errore di mira entro mezza racchetta), così il colpo ci sarà. Con un solo settore pieno
    /// la probabilità è dimezzata (`bonus_odds << 1`): di solito aspetta la barra piena, la mossa
    /// di livello 2. Un'estrazione sola sceglie anche la mossa: 0 STRAIGHT SHOT, 1 RISING STRIKE.
    ///
    /// Il generatore si usa solo quando la condizione vale.
    fn special(&mut self, m: &Match, aim: Option<Fx>) -> Option<Special> {
        let pl = &m.next.as_ref()?.players[self.side as usize];
        let aim = aim?;
        if !pl.special_ready(&m.params) {
            return None;
        }
        let pad = &m.paddles[self.side as usize];
        let half = pad.height >> 1;
        let gap = (aim - pad.y).abs();
        if gap > half || self.error.abs() > half {
            return None;
        }
        let odds = if pl.special_level(&m.params) >= MAX_SPECIAL_LEVEL {
            self.bonus_odds
        } else {
            self.bonus_odds << 1
        };
        match self.rng.below(odds << 1) {
            0 => Some(Special::Straight),
            1 => Some(Special::Rise),
            _ => None,
        }
    }

    /// Emergenza per il BULLET: palla in arrivo già vista (`aim`, il punto d'arrivo previsto),
    /// veloce (spostamento dell'ultimo tick oltre metà della velocità massima di NEXT), vicina (a
    /// meno di `|dx| << bullet_shift`) e con il punto d'arrivo fuori dalla racchetta (oltre mezza
    /// racchetta più il raggio della palla): senza rallentarla non la si prende. Solo se la CPU non
    /// ha deciso di mancarla (errore di mira entro mezza racchetta, come per STRAIGHT SHOT):
    /// altrimenti lo sprecherebbe su una palla persa apposta. Solo confronti e shift; non usa il
    /// generatore.
    fn bullet_rescue(&self, m: &Match, aim: Option<Fx>, distance: Fx) -> bool {
        let Some(aim) = aim else { return false };
        let pad = &m.paddles[self.side as usize];
        let dx = m.ball.dx.abs();
        let half = pad.height >> 1;
        dx > m.params.max_ball_speed_next >> 1
            && distance <= dx << self.bullet_shift
            && (aim - pad.y).abs() > half + m.ball.radius
            && self.error.abs() <= half
    }

    /// La CPU va a prendere questa capsula: quelle verso di sé finché la riserva non è piena; il
    /// BLASTER, che le raccoglie sparando, anche quelle dell'avversario (con la riserva piena
    /// solo quelle, per distruggerle).
    fn wants(&self, m: &Match, c: &Capsule) -> bool {
        let n = m.next.as_ref().unwrap();
        let full = n.players[self.side as usize].full();
        if m.paddle_kind(self.side) == Some(PaddleKind::Blaster) {
            !full || c.toward() != self.side
        } else {
            !full && c.toward() == self.side
        }
    }
}

/// y della palla quando arriverà alla racchetta di `side`, con i rimbalzi sui bordi.
/// Avanza la palla a passi di `Params::predict_step` tick, al massimo `Params::predict_max` passi
/// (oltre si mira all'ultimo punto): niente divisioni, pochi passi.
fn arrival_y(m: &Match, side: Side) -> Fx {
    let b = &m.ball;
    let pad = &m.paddles[side as usize];
    let face = match side {
        Side::Left => pad.right() + b.radius,
        Side::Right => pad.left() - b.radius,
    };
    let (low, high) = (b.radius + fixed::ONE, m.params.height - fixed::ONE - b.radius);
    let p = &m.params;
    let dx = mul(b.vx, b.boost) * p.predict_step;
    let (mut x, mut y, mut dy) = (b.x, b.y, b.vy * p.predict_step);
    for _ in 0..p.predict_max {
        let arrived = match side {
            Side::Left => x <= face,
            Side::Right => x >= face,
        };
        if arrived || dx == 0 {
            break;
        }
        x += dx;
        y += dy;
        if y > high {
            y = 2 * high - y;
            dy = -dy;
        } else if y < low {
            y = 2 * low - y;
            dy = -dy;
        }
    }
    y.clamp(low, high)
}
