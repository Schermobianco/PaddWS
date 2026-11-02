//! Modalità NEXT: Classic con lo scatto in avanti, più i bonus.
//!
//! Dalla mezzeria partono capsule verso i giocatori; chi ne tocca una con la
//! racchetta mette il bonus nella sua riserva (3 posti), poi lo sceglie
//! (`PlayerInput::select`) e lo attiva (`PlayerInput::activate`). Le capsule
//! che arrivano a un giocatore contengono uno dei 3 bonus che ha scelto prima
//! della partita, oppure, raramente, il SUPER o il BULLET (vedi `Params::super_cut`).
//!
//! BULLET (bullet time) è difensivo. Attivato resta armato finché la palla entra nella metà campo
//! di chi l'ha attivato andando verso di lui (`Params::bullet_zone`); allora scatta e tutto rallenta tranne la sua
//! racchetta (palla con i suoi effetti, racchetta avversaria, capsule, colpi del BLASTER
//! avversario), finché lui ribatte la palla (che torna ad allontanarsi) o c'è un punto. Si rallenta
//! il passo di movimento del tick, mai la velocità memorizzata: `passo = v - (v >> k)` (`slowed`),
//! con `k = Params::bullet_shift` (1 = metà) e `Params::bullet_ramp_shift` (2 = 3/4) nei primi
//! `Params::bullet_ramp_ticks` tick. Timer e pause restano in tempo reale. Un punto prima che
//! scatti non lo consuma. Un BULLET alla volta: mentre uno è armato o in corso nessuno ne attiva
//! un altro.
//!
//! Ogni giocatore può avere anche un tipo di racchetta (`PaddleKind`), scelto
//! prima della partita: cambia altezza, velocità e un'abilità propria.
//!
//! Con l'opzione della partita `Next::super_moves` (spenta di default, `Match::set_super_moves`)
//! ci sono anche le mosse speciali (`Special`), comandate con `PlayerInput::special`: ogni
//! giocatore ha una barra (`NextPlayer::meter`) che si carica con i colpi e con i punti subiti,
//! e ogni mossa ne spende una parte. Con l'opzione spenta la partita è identica bit per bit a
//! quella senza mosse.
//!
//! Come il resto del core: tutto intero, nessuna divisione, generatore della
//! partita per ogni scelta casuale, così una partita NEXT si può rigiocare
//! identica (anche in un core HDL).

use crate::fixed::{Fx, ONE, mul};
use crate::game::{Ball, Event, Events, Input, Match, Paddle, PlayerInput, Side};
use crate::params::Params;

/// Posti della riserva e bonus scelti prima della partita.
pub const RESERVE_SLOTS: usize = 3;
pub const LOADOUT_SIZE: usize = 3;
/// Capsule in volo contemporaneamente.
pub const MAX_CAPSULES: usize = 4;
/// Colpi del BLASTER in volo contemporaneamente (e colpi massimi del caricatore).
pub const MAX_SHOTS: usize = 4;
/// Livello massimo di una mossa speciale (settori della barra spesi in una volta).
pub const MAX_SPECIAL_LEVEL: u8 = 2;
/// GUARDIAN: settori del muro (uno per partita), dall'alto; `NextPlayer::barrier` ne ha un bit
/// per settore, il bit 0 è quello in alto.
pub const GUARDIAN_SECTORS: usize = 5;
pub const GUARDIAN_WALL: u8 = (1 << GUARDIAN_SECTORS) - 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Bonus {
    /// quando la palla in arrivo passa la metà campo la racchetta salta alla sua altezza
    Teleport = 0,
    /// schiacciata: il prossimo colpo parte più veloce e quasi piatto
    Smash = 1,
    /// la palla perde un terzo della velocità fino al prossimo colpo di chi l'ha usato, poi
    /// riparte alla velocità di prima
    Slow = 2,
    /// palla a effetto: dopo il colpo la traiettoria curva
    Curve = 3,
    /// palla fantasma: dopo il colpo si vede solo a lampi
    Ghost = 4,
    /// super schiacciata, solo dalle capsule
    Super = 5,
    /// palla guidata: dopo il colpo la si sterza su e giù fino a 3/4 del campo, a racchetta ferma
    Steer = 6,
    /// bullet time, solo dalle capsule: per un tempo fisso tutto rallenta tranne la propria
    /// racchetta. Come SLOW agisce subito e non resta mai armato
    Bullet = 7,
}

impl Bonus {
    pub const COUNT: usize = 8;
    /// Tutti i bonus, nell'ordine dei codici.
    pub const ALL: [Bonus; Self::COUNT] = [
        Bonus::Teleport,
        Bonus::Smash,
        Bonus::Slow,
        Bonus::Curve,
        Bonus::Ghost,
        Bonus::Super,
        Bonus::Steer,
        Bonus::Bullet,
    ];

    /// Bonus che si possono scegliere prima della partita.
    pub const PICKABLE: [Bonus; 6] = [
        Bonus::Teleport,
        Bonus::Smash,
        Bonus::Slow,
        Bonus::Curve,
        Bonus::Ghost,
        Bonus::Steer,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            Bonus::Teleport => "TELEPORT",
            Bonus::Smash => "SMASH",
            Bonus::Slow => "SLOW",
            Bonus::Curve => "CURVE",
            Bonus::Ghost => "GHOST",
            Bonus::Super => "SUPER",
            Bonus::Steer => "STEER",
            Bonus::Bullet => "BULLET",
        }
    }

    /// Bonus raro, che arriva solo dalle capsule e non si sceglie prima della partita.
    pub const fn rare(self) -> bool {
        matches!(self, Bonus::Super | Bonus::Bullet)
    }
}

/// Passo di movimento rallentato dal BULLET: `v - (v >> shift)` (shift 1 = metà, 2 = 3/4),
/// oppure `v` con shift 0. Una sottrazione e uno shift aritmetico, come in hardware.
pub const fn slowed(v: Fx, shift: u32) -> Fx {
    if shift == 0 { v } else { v - (v >> shift) }
}

/// Tipo di racchetta di NEXT, per tutta la partita. `None` in `NextPlayer::kind` è la racchetta
/// di NEXT senza tipo (quella del core MiSTer di oggi): ARCADE ha la stessa fisica, ma una
/// pausa più breve tra due bonus.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum PaddleKind {
    /// la racchetta dei bonus: più capsule e una pausa più breve tra due attivazioni
    Arcade = 0,
    /// più alta e più lenta
    Titan = 1,
    /// lenta, ma ogni colpo parte più veloce
    Hammer = 2,
    /// passa alla palla parte della sua velocità verticale
    Twist = 3,
    /// spara colpi che raccolgono le capsule, anche quelle dell'avversario
    Blaster = 4,
    /// più corta, con uno scatto in avanti più lungo e più veloce quando è avanzata
    Rush = 5,
    /// più corta, con un muro a settori dietro: ogni settore rimanda una palla mancata e sparisce
    Guardian = 6,
}

impl PaddleKind {
    pub const COUNT: usize = 7;
    pub const ALL: [PaddleKind; Self::COUNT] = [
        PaddleKind::Arcade,
        PaddleKind::Titan,
        PaddleKind::Hammer,
        PaddleKind::Twist,
        PaddleKind::Blaster,
        PaddleKind::Rush,
        PaddleKind::Guardian,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            PaddleKind::Arcade => "ARCADE",
            PaddleKind::Titan => "TITAN",
            PaddleKind::Hammer => "HAMMER",
            PaddleKind::Twist => "TWIST",
            PaddleKind::Blaster => "BLASTER",
            PaddleKind::Rush => "RUSH",
            PaddleKind::Guardian => "GUARDIAN",
        }
    }
}

/// Colpo del BLASTER: due colpi paralleli trattati come una fascia di ±`Params::blaster_band`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Shot {
    pub x: Fx,
    pub y: Fx,
    pub vx: Fx,
}

/// Animazione del SUPER, estratta a caso quando lo si attiva.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum SuperAnim {
    /// la racchetta ruota su se stessa mentre aspetta la palla
    Spin = 0,
    /// al colpo il gioco si ferma per un istante (`Next::freeze`)
    HitStop = 1,
    /// palla grande con la coda che spazza la mezzeria
    Comet = 2,
}

impl SuperAnim {
    const ALL: [SuperAnim; 3] = [SuperAnim::Spin, SuperAnim::HitStop, SuperAnim::Comet];
}

/// Mossa speciale (`PlayerInput::special`), con il codice a 2 bit delle tracce (0 = nessuna).
///
/// Una mossa alla volta: non parte durante l'attesa della battuta, senza `Params::super_cost`
/// nella barra, con un'altra mossa armata o con un bonus armato; e mentre una mossa è armata
/// non si attivano bonus. Così mossa e bonus non si sommano mai sullo stesso colpo e non
/// servono regole di precedenza (i tipi di racchetta invece restano: vedi `next_on_hit`).
///
/// La mossa spende tutti i settori pieni della barra (`super_cost` ciascuno, al massimo
/// `MAX_SPECIAL_LEVEL`) e ha il livello di quanti ne ha spesi: col livello 2 è più forte.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Special {
    /// il prossimo colpo parte orizzontale (vy = 0) e più veloce: x1,5 al livello 1, x2 al
    /// livello 2 (`Params::super_straight_shift`)
    Straight = 1,
    /// il prossimo colpo parte orizzontale e, passati i 5/8 del campo (7/8 al livello 2),
    /// s'impenna a 45 gradi lontano dalla racchetta avversaria
    Rise = 2,
}

impl Special {
    pub const ALL: [Special; 2] = [Special::Straight, Special::Rise];

    pub const fn name(self) -> &'static str {
        match self {
            Special::Straight => "STRAIGHT SHOT",
            Special::Rise => "RISING STRIKE",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Capsule {
    pub x: Fx,
    pub y: Fx,
    pub vx: Fx,
    pub vy: Fx,
    pub bonus: Bonus,
}

impl Capsule {
    /// Il giocatore verso cui viaggia.
    pub const fn toward(&self) -> Side {
        if self.vx < 0 { Side::Left } else { Side::Right }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NextPlayer {
    pub loadout: [Bonus; LOADOUT_SIZE],
    /// bonus raccolti, sempre nei primi posti
    pub reserve: [Option<Bonus>; RESERVE_SLOTS],
    pub selected: u8,
    /// bonus attivato che aspetta il prossimo colpo (o, per TELEPORT, la palla in arrivo)
    pub armed: Option<Bonus>,
    pub super_anim: SuperAnim,
    /// tick prima di poter attivare un altro bonus
    pub cooldown: u32,
    /// tipo di racchetta (None: racchetta di NEXT senza tipo)
    pub kind: Option<PaddleKind>,
    /// BLASTER: colpi in volo, colpi nel caricatore, tick prima del colpo successivo e tick
    /// prima che il caricatore torni pieno (partono dal primo colpo a caricatore pieno)
    pub shots: [Option<Shot>; MAX_SHOTS],
    pub ammo: u8,
    pub gap: u32,
    pub reload: u32,
    /// GUARDIAN: settori del muro ancora in piedi, un bit per settore (`GUARDIAN_SECTORS`)
    pub barrier: u8,
    /// mosse speciali: barra (0..=`Params::super_meter_max`, resta da un punto all'altro come la
    /// riserva) e livello di STRAIGHT SHOT o RISING STRIKE armato per il prossimo colpo (0 = no)
    pub meter: u8,
    pub straight: u8,
    pub rise: u8,
}

impl NextPlayer {
    fn new(loadout: [Bonus; LOADOUT_SIZE]) -> Self {
        Self {
            loadout,
            reserve: [None; RESERVE_SLOTS],
            selected: 0,
            armed: None,
            super_anim: SuperAnim::Spin,
            cooldown: 0,
            kind: None,
            shots: [None; MAX_SHOTS],
            ammo: 0,
            gap: 0,
            reload: 0,
            barrier: 0,
            meter: 0,
            straight: 0,
            rise: 0,
        }
    }

    /// Nessuna mossa speciale armata.
    pub const fn special_idle(&self) -> bool {
        self.straight == 0 && self.rise == 0
    }

    /// Livello della mossa che partirebbe ora: settori pieni della barra, al massimo
    /// `MAX_SPECIAL_LEVEL` (0 se non basta per una mossa).
    pub fn special_level(&self, p: &Params) -> u8 {
        (self.meter / p.super_cost).min(MAX_SPECIAL_LEVEL)
    }

    /// Può eseguire una mossa speciale ora (barra sufficiente, nessuna mossa né bonus armato);
    /// l'attesa della battuta e l'opzione della partita li controlla `Match`.
    pub fn special_ready(&self, p: &Params) -> bool {
        self.meter >= p.super_cost && self.special_idle() && self.armed.is_none()
    }

    /// Carica la barra, fino al massimo.
    fn gain(&mut self, amount: u8, p: &Params) {
        self.meter = self.meter.saturating_add(amount).min(p.super_meter_max);
    }

    fn cooldown_ticks(&self, p: &Params) -> u32 {
        if self.kind == Some(PaddleKind::Arcade) {
            p.arcade_cooldown_ticks
        } else {
            p.bonus_cooldown_ticks
        }
    }

    /// BLASTER: può sparare ora (colpi nel caricatore, pausa finita, un posto libero)
    pub fn can_fire(&self) -> bool {
        self.ammo > 0 && self.gap == 0 && self.shots.iter().any(Option::is_none)
    }

    pub fn count(&self) -> usize {
        self.reserve.iter().filter(|b| b.is_some()).count()
    }

    pub fn full(&self) -> bool {
        self.count() == RESERVE_SLOTS
    }

    /// Bonus selezionato nella riserva (quello che `activate` userebbe), se c'è.
    pub fn selected_bonus(&self) -> Option<Bonus> {
        let n = self.count();
        if n == 0 {
            return None;
        }
        self.reserve[(self.selected as usize).min(n - 1)]
    }

    /// Ha un BULLET nella riserva.
    pub fn has_bullet(&self) -> bool {
        self.reserve.contains(&Some(Bonus::Bullet))
    }

    fn push(&mut self, bonus: Bonus) -> bool {
        match self.reserve.iter_mut().find(|slot| slot.is_none()) {
            Some(slot) => {
                *slot = Some(bonus);
                true
            }
            None => false,
        }
    }

    fn select_next(&mut self) {
        let n = self.count() as u8;
        if n > 0 {
            self.selected = if self.selected + 1 >= n { 0 } else { self.selected + 1 };
        }
    }

    /// Toglie dalla riserva il bonus selezionato, compattando gli altri.
    fn take_selected(&mut self) -> Option<Bonus> {
        let n = self.count();
        if n == 0 {
            return None;
        }
        let i = (self.selected as usize).min(n - 1);
        let bonus = self.reserve[i].take();
        for j in i..RESERVE_SLOTS - 1 {
            self.reserve[j] = self.reserve[j + 1].take();
        }
        if self.selected as usize >= n - 1 {
            self.selected = self.selected.saturating_sub(1);
        }
        bonus
    }
}

/// Stato della modalità NEXT dentro `Match::next`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Next {
    pub players: [NextPlayer; 2],
    pub capsules: [Option<Capsule>; MAX_CAPSULES],
    pub spawn_timer: u32,
    /// tick rimasti dell'alone del rallentamento (solo per il disegno): resta pieno finché la
    /// palla è rallentata
    pub slow_timer: u32,
    /// SLOW: chi l'ha usato, finché la palla è rallentata (al suo colpo torna veloce)
    pub slow: Option<Side>,
    /// accelerazione verticale per tick della palla a effetto (0 = nessun effetto)
    pub curve: Fx,
    /// la palla è fantasma dopo il tiro di questo giocatore
    pub ghost: Option<Side>,
    /// questo giocatore sta guidando la palla (STEER), con la direzione del tick: +1 su, -1 giù
    pub steer: Option<Side>,
    pub steer_dir: i8,
    /// la palla viaggia con un SUPER (per il disegno)
    pub super_flight: Option<SuperAnim>,
    /// tick di fermo del gioco (hit-stop del SUPER)
    pub freeze: u32,
    /// capsule partite dall'inizio della partita (statistiche)
    pub spawned: u32,
    /// opzione della partita: mosse speciali attive (`Match::set_super_moves`, spenta di default)
    pub super_moves: bool,
    /// la palla viaggia con il tiro di una mossa speciale (per il disegno), fino al colpo
    /// successivo, con il suo livello
    pub special_flight: Option<Special>,
    pub special_level: u8,
    /// RISING STRIKE in volo: x oltre la quale la palla s'impenna (None: già impennata o nessuna)
    pub rise_break: Option<Fx>,
    /// BULLET: chi l'ha attivato (armato o in corso), se è scattato e i tick di rampa rimasti,
    /// contando quello in corso. Stato e timer cambiano all'inizio di ogni tick (non durante il
    /// fermo del SUPER, come le altre pause): vedi `Next::bullet_step`
    pub bullet: Option<Side>,
    pub bullet_on: bool,
    pub bullet_timer: u32,
}

impl Next {
    fn new(loadouts: [[Bonus; LOADOUT_SIZE]; 2], p: &Params) -> Self {
        Self {
            players: loadouts.map(NextPlayer::new),
            capsules: [None; MAX_CAPSULES],
            spawn_timer: p.spawn_ticks,
            slow_timer: 0,
            slow: None,
            curve: 0,
            ghost: None,
            steer: None,
            steer_dir: 0,
            super_flight: None,
            freeze: 0,
            spawned: 0,
            super_moves: false,
            special_flight: None,
            special_level: 0,
            rise_break: None,
            bullet: None,
            bullet_on: false,
            bullet_timer: 0,
        }
    }

    /// Shift del rallentamento del BULLET in questo tick per palla e capsule (0 = piena
    /// velocità, anche con il BULLET solo armato): `Params::bullet_ramp_shift` nei primi
    /// `bullet_ramp_ticks` tick dallo scatto, poi `Params::bullet_shift`. Solo confronti.
    pub const fn bullet_shift(&self, p: &Params) -> u32 {
        if !self.bullet_on {
            0
        } else if self.bullet_timer > 0 {
            p.bullet_ramp_shift
        } else {
            p.bullet_shift
        }
    }

    /// Come `bullet_shift`, per ciò che appartiene al giocatore `side` (racchetta, colpi del
    /// BLASTER): chi ha attivato il BULLET resta a piena velocità.
    pub fn bullet_shift_for(&self, side: Side, p: &Params) -> u32 {
        if self.bullet == Some(side) {
            0
        } else {
            self.bullet_shift(p)
        }
    }

    /// Fine del BULLET (alla ribattuta o al punto).
    fn end_bullet(&mut self) {
        self.bullet = None;
        self.bullet_on = false;
        self.bullet_timer = 0;
    }

    /// BULLET armato da `side`: scatta se la palla è nella sua metà campo e va verso di lui.
    fn bullet_trigger(&mut self, ball: &Ball, p: &Params) {
        let Some(side) = self.bullet else { return };
        let inside = match side {
            Side::Left => ball.x < p.bullet_zone,
            Side::Right => ball.x > p.width - p.bullet_zone,
        };
        if !self.bullet_on && inside && coming_toward(ball, side) {
            self.bullet_on = true;
            self.bullet_timer = p.bullet_ramp_ticks;
        }
    }

    /// Inizio del tick: il BULLET armato scatta (`bullet_trigger`); quello in corso finisce
    /// quando la palla si allontana da chi l'ha attivato (l'ha ribattuta), altrimenti scende la
    /// rampa.
    fn bullet_step(&mut self, ball: &Ball, p: &Params) {
        let Some(side) = self.bullet else { return };
        if !self.bullet_on {
            self.bullet_trigger(ball, p);
        } else if !coming_toward(ball, side) {
            self.end_bullet();
        } else if self.bullet_timer > 0 {
            self.bullet_timer -= 1;
        }
    }

    /// Effetti che valgono per un solo tiro: finiscono al colpo successivo o al punto.
    fn clear_shot(&mut self) {
        self.curve = 0;
        self.ghost = None;
        self.steer = None;
        self.steer_dir = 0;
        self.super_flight = None;
        self.special_flight = None;
        self.special_level = 0;
        self.rise_break = None;
    }

    /// Spostamento della palla nel tick con l'effetto (CURVE), guidata (STEER) o impennata da
    /// RISING STRIKE, rallentato dal BULLET: il passo (`dx`, `dy`) e, perché la traiettoria resti
    /// la stessa, le accelerazioni di CURVE e STEER; la velocità memorizzata non cambia.
    pub(crate) fn ball_motion(&mut self, ball: &mut Ball, p: &Params, paddles: &[Paddle; 2], dx: &mut Fx, dy: &mut Fx) {
        let limit = ball.vx.abs(); // mai più ripida di 45 gradi
        let slow = self.bullet_shift(p);
        // RISING STRIKE: passata la soglia s'impenna di colpo verso il bordo lontano dalla
        // racchetta verso cui va
        if let Some(at) = self.rise_break {
            let (past, toward) = if ball.vx > 0 {
                (ball.x >= at, Side::Right)
            } else {
                (ball.x <= at, Side::Left)
            };
            if past {
                self.rise_break = None;
                ball.vy = away_from(&paddles[toward as usize], ball.y, limit);
                *dy = ball.vy;
            }
        }
        if self.curve != 0 {
            ball.vy = (ball.vy + slowed(self.curve, slow)).clamp(-limit, limit);
            *dy = ball.vy;
        }
        if let Some(side) = self.steer {
            // si guida fino a 3/4 del campo, contati da chi ha colpito
            let past = match side {
                Side::Left => ball.x >= p.width - (p.width >> 2),
                Side::Right => ball.x <= p.width >> 2,
            };
            if past {
                self.steer = None;
                self.steer_dir = 0;
            } else if self.steer_dir != 0 {
                // fino al doppio della velocità orizzontale (circa 63 gradi): a 45 gradi l'ultimo
                // quarto di campo è troppo prevedibile e il tiro guidato vale poco più di uno normale
                let steep = limit << 1;
                let accel = if self.steer_dir > 0 {
                    p.steer_accel
                } else {
                    -p.steer_accel
                };
                ball.vy = (ball.vy + slowed(accel, slow)).clamp(-steep, steep);
                *dy = ball.vy;
            }
        }
        *dx = slowed(*dx, slow);
        *dy = slowed(*dy, slow);
        if self.slow.is_none() {
            self.slow_timer = self.slow_timer.saturating_sub(1);
        }
    }

    /// La palla è nascosta nel tick `tick`: dopo un tiro GHOST si vede solo a lampi
    /// (0,1 s ogni 0,4 s) fino al tocco dell'avversario.
    pub fn ball_hidden(&self, p: &Params, tick: u64) -> bool {
        self.ghost.is_some() && tick % p.ghost_period as u64 >= p.ghost_visible as u64
    }
}

/// GUARDIAN: settore del muro all'altezza `y` (0 in alto: la y cresce verso l'alto). Il primo
/// settore copre anche la banda delle riserve, dove il muro non si disegna.
pub fn guardian_sector(p: &Params, y: Fx) -> usize {
    p.guardian_bounds.iter().filter(|&&b| y < b).count()
}

/// Velocità verticale `speed` diretta verso il bordo lontano dalla racchetta `pad`.
fn away_from(pad: &Paddle, y: Fx, speed: Fx) -> Fx {
    if pad.y > y { -speed } else { speed }
}

fn coming_toward(ball: &Ball, side: Side) -> bool {
    match side {
        Side::Left => ball.vx < 0,
        Side::Right => ball.vx > 0,
    }
}

/// y della palla quando arriverà alla faccia della racchetta `pad`, con i rimbalzi sui bordi,
/// a velocità costante (la curva non si prevede). Avanza a passi di `Params::arrival_step` tick
/// (al massimo `Params::arrival_max` passi) con lo spostamento orizzontale dell'ultimo tick
/// (`Ball::dx`): niente moltiplicazioni né divisioni.
pub fn arrival_y(b: &Ball, pad: &Paddle, p: &Params) -> Fx {
    let face = match pad.side {
        Side::Left => pad.right() + b.radius,
        Side::Right => pad.left() - b.radius,
    };
    let (low, high) = (b.radius + ONE, p.height - ONE - b.radius);
    let dx = b.dx * p.arrival_step;
    let (mut x, mut y, mut dy) = (b.x, b.y, b.vy * p.arrival_step);
    for _ in 0..p.arrival_max {
        let arrived = match pad.side {
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

fn touches(c: &Capsule, pad: &Paddle, half: Fx) -> bool {
    (c.x - pad.x).abs() <= half + pad.width / 2 && (c.y - pad.y).abs() <= half + pad.height / 2
}

impl Match {
    /// Nuova partita NEXT a due giocatori con i bonus scelti da ciascuno.
    pub fn new_next(params: Params, loadouts: [[Bonus; LOADOUT_SIZE]; 2], seed: u32) -> Self {
        let mut m = Match::new(params, 2, false, seed);
        m.next = Some(Next::new(loadouts, &m.params));
        m
    }

    /// Come `new_next`, con il tipo di racchetta di ciascun giocatore (None: senza tipo).
    pub fn new_next_paddles(
        params: Params,
        loadouts: [[Bonus; LOADOUT_SIZE]; 2],
        kinds: [Option<PaddleKind>; 2],
        seed: u32,
    ) -> Self {
        let mut m = Match::new_next(params, loadouts, seed);
        for side in Side::BOTH {
            let Some(kind) = kinds[side as usize] else { continue };
            let k = m.params.kinds[kind as usize];
            let pad = &mut m.paddles[side as usize];
            pad.height = k.height;
            pad.inv_half_height = k.inv_half_height;
            pad.max_speed = k.max_speed;
            pad.acceleration = k.acceleration;
            pad.fast_acceleration = k.fast_acceleration;
            pad.fwd_max_speed = k.fwd_max_speed;
            pad.fwd_acceleration = k.fwd_acceleration;
            pad.fwd_fast_acceleration = k.fwd_fast_acceleration;
            pad.encoder_step = k.encoder_step;
            pad.fwd_x = match side {
                Side::Left => k.fwd_pos,
                Side::Right => m.params.width - k.fwd_pos,
            };
            let pl = &mut m.next.as_mut().unwrap().players[side as usize];
            pl.kind = Some(kind);
            pl.barrier = if kind == PaddleKind::Guardian { GUARDIAN_WALL } else { 0 };
            if kind == PaddleKind::Blaster {
                pl.ammo = m.params.blaster_shots;
            }
        }
        m
    }

    /// Tipo della racchetta di un giocatore (None fuori da NEXT o senza tipo).
    pub fn paddle_kind(&self, side: Side) -> Option<PaddleKind> {
        self.next.as_ref().and_then(|n| n.players[side as usize].kind)
    }

    /// Accende o spegne le mosse speciali della partita (opzione del menu e dell'OSD). Fuori da
    /// NEXT non fa nulla. Va scelta prima di iniziare; spegnendole a partita in corso le mosse in
    /// corso finiscono (altrimenti bloccherebbero i bonus) e le barre restano dove sono.
    pub fn set_super_moves(&mut self, on: bool) {
        if let Some(n) = self.next.as_mut() {
            n.super_moves = on;
            if !on {
                for pl in &mut n.players {
                    pl.straight = 0;
                    pl.rise = 0;
                }
            }
        }
    }

    /// Le mosse speciali sono attive (solo in NEXT, con l'opzione accesa).
    pub fn super_moves(&self) -> bool {
        self.next.as_ref().is_some_and(|n| n.super_moves)
    }

    /// BLASTER: spara (`PlayerInput::fire`), se ha colpi nel caricatore e la pausa tra due colpi
    /// è finita. Il primo colpo a caricatore pieno fa partire la ricarica.
    pub(crate) fn next_fire(&mut self, side: Side, events: &mut Events) {
        let Match {
            next,
            params: p,
            paddles,
            ..
        } = self;
        let Some(n) = next.as_mut() else { return };
        let pl = &mut n.players[side as usize];
        if !pl.can_fire() {
            return;
        }
        let pad = &paddles[side as usize];
        let (x, vx) = match side {
            Side::Left => (pad.right(), p.blaster_shot_speed),
            Side::Right => (pad.left(), -p.blaster_shot_speed),
        };
        if let Some(slot) = pl.shots.iter_mut().find(|s| s.is_none()) {
            *slot = Some(Shot { x, y: pad.y, vx });
        }
        if pl.ammo == p.blaster_shots {
            pl.reload = p.blaster_reload_ticks;
        }
        pl.ammo -= 1;
        pl.gap = p.blaster_gap_ticks;
        events.add(Event::Fire);
    }

    /// GUARDIAN: la palla mancata rimbalza sul settore del muro dietro la racchetta in cui si
    /// trova il suo centro, se c'è ancora, e il settore sparisce. Il muro non torna.
    /// True se ha rimbalzato.
    pub(crate) fn next_barrier(&mut self, side: Side) -> bool {
        let Match {
            next,
            params: p,
            ball: b,
            ..
        } = self;
        let Some(n) = next.as_mut() else { return false };
        if n.players[side as usize].barrier == 0 {
            return false;
        }
        let line = match side {
            Side::Left => p.guardian_barrier_x,
            Side::Right => p.width - p.guardian_barrier_x,
        };
        let reached = match side {
            Side::Left => b.left() <= line,
            Side::Right => b.right() >= line,
        };
        if !reached {
            return false;
        }
        let sector = guardian_sector(p, b.y);
        if n.players[side as usize].barrier & (1 << sector) == 0 {
            return false;
        }
        // rimbalzo semplice: niente accelerazione e finiscono gli effetti del tiro
        n.players[side as usize].barrier &= !(1 << sector);
        n.clear_shot();
        b.boost = ONE;
        b.radius = p.ball_radius;
        b.vx = -b.vx;
        b.x = match side {
            Side::Left => line + b.radius,
            Side::Right => line - b.radius,
        };
        true
    }

    /// Selezione e attivazione dei bonus di un giocatore.
    pub(crate) fn next_command(&mut self, side: Side, cmd: &PlayerInput, events: &mut Events) {
        let serving = self.serving();
        let Match {
            next,
            params: p,
            rng,
            ball,
            ..
        } = self;
        let Some(n) = next.as_mut() else { return };
        let bullet_on = n.bullet.is_some();
        let pl = &mut n.players[side as usize];
        if cmd.select {
            pl.select_next();
        }
        // un bonus alla volta, non durante l'attesa della battuta, con una pausa tra due attivazioni;
        // con le mosse speciali, nemmeno durante una mossa (vedi `Special`)
        if !cmd.activate || serving || pl.cooldown > 0 || pl.armed.is_some() || !pl.special_idle() {
            return;
        }
        // un BULLET alla volta: con uno attivo (di chiunque) resta in riserva
        if bullet_on && pl.selected_bonus() == Some(Bonus::Bullet) {
            return;
        }
        let Some(bonus) = pl.take_selected() else { return };
        pl.cooldown = pl.cooldown_ticks(p);
        events.add(Event::Activate);
        match bonus {
            Bonus::Slow => {
                // la palla perde velocità fino al prossimo colpo di chi l'ha usato (vedi
                // `next_on_hit`), ma non va sotto la battuta
                let floor = p.serve_unit * 2;
                ball.vx = mul(ball.vx, p.slow_mul);
                if ball.vx.abs() < floor {
                    ball.vx = if ball.vx < 0 { -floor } else { floor };
                }
                ball.vy = mul(ball.vy, p.slow_mul);
                n.slow_timer = p.slow_ticks;
                n.slow = Some(side);
            }
            Bonus::Super => {
                pl.super_anim = SuperAnim::ALL[rng.below(3) as usize];
                pl.armed = Some(bonus);
            }
            // armato; se la palla è già nella sua metà campo e va verso di lui scatta da questo tick:
            // rallenta già le racchette, che si muovono subito dopo
            Bonus::Bullet => {
                n.bullet = Some(side);
                n.bullet_trigger(ball, p);
            }
            _ => pl.armed = Some(bonus),
        }
    }

    /// Inizio del tick NEXT (dopo il fermo del SUPER): il BULLET scatta, scende la sua rampa o
    /// finisce alla ribattuta (`Next::bullet_step`).
    pub(crate) fn next_bullet_countdown(&mut self) {
        if let Some(n) = self.next.as_mut() {
            n.bullet_step(&self.ball, &self.params);
        }
    }

    /// Fermo del gioco dopo un SUPER: true se il tick va saltato.
    pub(crate) fn next_frozen(&mut self) -> bool {
        match self.next.as_mut() {
            Some(n) if n.freeze > 0 => {
                n.freeze -= 1;
                true
            }
            _ => false,
        }
    }

    /// Parte del tick NEXT dopo il movimento delle racchette: pause, TELEPORT, capsule, colpi del
    /// BLASTER e, per ultime, le mosse speciali.
    pub(crate) fn next_tick(&mut self, input: &Input, events: &mut Events) {
        self.next_timers_and_capsules(events);
        if self.super_moves() && !self.serving() {
            for side in Side::BOTH {
                if let Some(special) = input.players[side as usize].special {
                    self.next_special(side, special, events);
                }
            }
        }
    }

    /// Mossa speciale di un giocatore, dopo il movimento delle racchette: si spendono tutti i
    /// settori pieni della barra e la mossa si arma, di quel livello, per il prossimo colpo.
    fn next_special(&mut self, side: Side, special: Special, events: &mut Events) {
        let Match { next, params: p, .. } = self;
        let Some(n) = next.as_mut() else { return };
        let pl = &mut n.players[side as usize];
        if !pl.special_ready(p) {
            return;
        }
        let level = pl.special_level(p);
        pl.meter -= level * p.super_cost;
        match special {
            Special::Straight => {
                pl.straight = level;
                events.add(Event::Straight);
            }
            Special::Rise => {
                pl.rise = level;
                events.add(Event::Rise);
            }
        }
    }

    /// Pause, TELEPORT, capsule e colpi del BLASTER.
    fn next_timers_and_capsules(&mut self, events: &mut Events) {
        let serving = self.serving();
        let Match {
            next,
            params: p,
            rng,
            paddles,
            ball,
            ..
        } = self;
        let Some(n) = next.as_mut() else { return };
        for pl in &mut n.players {
            pl.cooldown = pl.cooldown.saturating_sub(1);
            pl.gap = pl.gap.saturating_sub(1);
            // BLASTER: finita la ricarica il caricatore torna pieno
            if pl.reload > 0 {
                pl.reload -= 1;
                if pl.reload == 0 {
                    pl.ammo = p.blaster_shots;
                }
            }
        }

        // TELEPORT: passata la metà campo, la racchetta salta dove arriverà la palla e resta sul
        // punto d'arrivo previsto (rifatto a ogni tick: segue anche le palle a effetto) fino al
        // colpo; prima si muove come sempre
        if !serving {
            for side in Side::BOTH {
                let past_half = match side {
                    Side::Left => ball.x < p.width / 2,
                    Side::Right => ball.x > p.width / 2,
                };
                if n.players[side as usize].armed == Some(Bonus::Teleport) && coming_toward(ball, side) && past_half {
                    let pad = &mut paddles[side as usize];
                    let half = pad.height / 2;
                    let target = arrival_y(ball, pad, p).clamp(half, p.height - half);
                    // il salto vero (non i piccoli passi dietro alla palla) ha la sua animazione
                    if (target - pad.y).abs() > pad.height / 4 {
                        events.add(Event::Teleport);
                    }
                    pad.y = target;
                    pad.speed = 0;
                }
            }
        }

        let half = p.capsule_half;
        let (low, high) = (half + ONE, p.height - p.capsule_margin_top - half);
        // ARCADE: le capsule partono più spesso e, contro un altro tipo, vanno più spesso a lui
        let arcade = n.players.each_ref().map(|pl| pl.kind == Some(PaddleKind::Arcade));
        n.spawn_timer = n.spawn_timer.saturating_sub(1);
        if n.spawn_timer == 0 {
            let base = if arcade[0] || arcade[1] {
                p.arcade_spawn_ticks
            } else {
                p.spawn_ticks
            };
            n.spawn_timer = base + rng.below(p.spawn_jitter);
            if let Some(slot) = n.capsules.iter_mut().find(|c| c.is_none()) {
                let side = if arcade[0] != arcade[1] {
                    let fan = if arcade[0] { Side::Left } else { Side::Right };
                    if rng.below(3) < p.arcade_share {
                        fan
                    } else {
                        fan.opponent()
                    }
                } else if rng.sign() > 0 {
                    Side::Left
                } else {
                    Side::Right
                };
                // un'estrazione a 16 bit: sotto `super_cut` SUPER, sotto `bullet_cut` BULLET,
                // altrimenti uno dei bonus scelti (vedi `Params::super_cut`)
                let roll = rng.bits16();
                let bonus = if roll < p.super_cut {
                    Bonus::Super
                } else if roll < p.bullet_cut {
                    Bonus::Bullet
                } else {
                    n.players[side as usize].loadout[rng.below(LOADOUT_SIZE as u32) as usize]
                };
                let y = low + mul(high - low, rng.frac());
                let vx = if side == Side::Left {
                    -p.capsule_speed
                } else {
                    p.capsule_speed
                };
                *slot = Some(Capsule {
                    x: p.width / 2,
                    y,
                    vx,
                    vy: p.capsule_drift * rng.sign(),
                    bonus,
                });
                n.spawned += 1;
            }
        }

        // BULLET: le capsule in volo rallentano tutte
        let slow = n.bullet_shift(p);
        for slot in &mut n.capsules {
            let Some(c) = slot else { continue };
            c.x += slowed(c.vx, slow);
            c.y += slowed(c.vy, slow);
            if c.y < low {
                c.y = low;
                c.vy = c.vy.abs();
            } else if c.y > high {
                c.y = high;
                c.vy = -c.vy.abs();
            }
            let side = c.toward();
            let pl = &mut n.players[side as usize];
            // con la riserva piena la capsula passa oltre
            if touches(c, &paddles[side as usize], half) && !pl.full() {
                pl.push(c.bonus);
                events.add(Event::Collect);
                *slot = None;
            } else if c.x + half < 0 || c.x - half > p.width {
                *slot = None;
            }
        }

        // BLASTER: il colpo attraversa la palla, raccoglie la prima capsula che tocca (con la
        // riserva piena la distrugge) e si ferma sulla racchetta avversaria o fuori dal campo
        for side in Side::BOTH {
            // BULLET: rallentano i colpi dell'avversario di chi l'ha attivato
            let slow = n.bullet_shift_for(side, p);
            let pl = &mut n.players[side as usize];
            for i in 0..MAX_SHOTS {
                let Some(shot) = pl.shots[i].as_mut() else { continue };
                let step = slowed(shot.vx, slow);
                shot.x += step;
                let (sx, sy) = (shot.x, shot.y);
                let reach = half + step.abs();
                let band = half + p.blaster_band;
                if let Some(slot) = n
                    .capsules
                    .iter_mut()
                    .find(|c| c.is_some_and(|c| (c.x - sx).abs() <= reach && (c.y - sy).abs() <= band))
                {
                    let bonus = slot.take().unwrap().bonus;
                    if !pl.full() {
                        pl.push(bonus);
                    }
                    events.add(Event::Collect);
                    pl.shots[i] = None;
                    continue;
                }
                let opp = &paddles[side.opponent() as usize];
                let stopped = match side {
                    Side::Left => sx >= opp.left(),
                    Side::Right => sx <= opp.right(),
                } && (sy - opp.y).abs() <= opp.height / 2 + p.blaster_band;
                if stopped || sx < 0 || sx > p.width {
                    pl.shots[i] = None;
                }
            }
        }
    }

    /// Colpo di un giocatore in NEXT: finiscono gli effetti del tiro precedente e parte quello armato.
    /// `dash`: il colpo è lo scatto in avanti che intercetta la palla (carica di più la barra).
    pub(crate) fn next_on_hit(&mut self, side: Side, dash: bool, events: &mut Events) {
        let max_speed = self.max_ball_speed();
        let Match {
            next,
            params: p,
            ball: b,
            paddles,
            ..
        } = self;
        let Some(n) = next.as_mut() else { return };
        n.clear_shot();
        // SLOW: al colpo di chi l'ha usato la palla riparte alla velocità di prima (quella di
        // adesso divisa per il rallentamento), mai oltre la massima e mai più ripida di 45 gradi
        if n.slow == Some(side) {
            n.slow = None;
            n.slow_timer = 0;
            let vx = mul(b.vx, p.slow_back).clamp(-max_speed, max_speed);
            let vy = mul(b.vy, p.slow_back);
            b.vy = vy.clamp(-vx.abs(), vx.abs());
            b.vx = vx;
        }
        let pl = &mut n.players[side as usize];
        match pl.kind {
            // la palla prende parte della velocità della racchetta, sempre entro i 45 gradi
            Some(PaddleKind::Twist) => {
                let limit = b.vx.abs();
                b.vy = (b.vy + mul(paddles[side as usize].motion, p.twist_transfer)).clamp(-limit, limit);
            }
            // un tiro più veloce, ma solo se la palla non ha già un boost (scatto) e non c'è SMASH o SUPER
            Some(PaddleKind::Hammer) if b.boost == ONE && !matches!(pl.armed, Some(Bonus::Smash | Bonus::Super)) => {
                b.boost = p.hammer_mul;
            }
            // dalla posizione avanzata (anche con lo scatto che intercetta la palla) il tiro parte più
            // veloce, se non c'è SMASH o SUPER; il boost è sempre positivo, come in hardware
            Some(PaddleKind::Rush)
                if !paddles[side as usize].at_home() && !matches!(pl.armed, Some(Bonus::Smash | Bonus::Super)) =>
            {
                b.boost = mul(b.boost, p.rush_mul);
            }
            _ => {}
        }
        match pl.armed.take() {
            Some(Bonus::Smash) => {
                // schiacciata: veloce e angolata verso il lato lontano dalla racchetta avversaria
                b.boost = p.smash_mul;
                b.vy = away_from(&paddles[side.opponent() as usize], b.y, b.vx.abs() - (b.vx.abs() >> 2));
                events.add(Event::Boost);
            }
            Some(Bonus::Super) => {
                b.boost = p.super_mul;
                b.vy = away_from(&paddles[side.opponent() as usize], b.y, b.vx.abs()); // a 45 gradi
                n.super_flight = Some(pl.super_anim);
                if pl.super_anim == SuperAnim::HitStop {
                    n.freeze = p.hitstop_ticks;
                }
                events.add(Event::Super);
            }
            // curva verso il lato opposto a quello in cui sale o scende: traiettoria a banana
            Some(Bonus::Curve) => n.curve = if b.vy >= 0 { -p.curve_accel } else { p.curve_accel },
            Some(Bonus::Ghost) => n.ghost = Some(side),
            Some(Bonus::Steer) => n.steer = Some(side),
            Some(Bonus::Teleport | Bonus::Slow | Bonus::Bullet) | None => {}
        }
        if !n.super_moves {
            return;
        }
        // mosse speciali: ogni colpo carica la barra (di più lo scatto); poi, se c'è, il tiro della
        // mossa. Un bonus armato non c'è mai insieme alla mossa (vedi `Special`); gli effetti dei
        // tipi di racchetta sì: la mossa sceglie l'angolo (TWIST non conta) e STRAIGHT SHOT
        // moltiplica il boost che il colpo ha già (HAMMER, RUSH, scatto)
        pl.gain(if dash { p.super_gain_dash } else { p.super_gain_hit }, p);
        if pl.straight > 0 {
            // orizzontale e più veloce (`super_straight_shift` al livello 2, di default il doppio;
            // al livello 1 uno shift in più, x1,5), con uno shift e una somma. Si moltiplica il
            // boost (velocità di un solo tiro, come SMASH) e non vx: vx resta alla velocità dello
            // scambio, che il core fa solo crescere fino al massimo (`max_ball_speed`) e non frena
            // mai, e il tiro dopo torna normale. Il boost si annulla come gli altri se l'avversario
            // lo intercetta con lo scatto (`forward_boost`)
            let level = core::mem::take(&mut pl.straight);
            b.vy = 0;
            b.boost += b.boost >> (p.super_straight_shift + (MAX_SPECIAL_LEVEL - level) as u32);
            n.special_flight = Some(Special::Straight);
            n.special_level = level;
            events.add(Event::SpecialHit);
        } else if pl.rise > 0 {
            // parte orizzontale e s'impenna passati i 5/8 del campo (livello 1) o i 7/8 (livello
            // 2), contati da chi ha colpito: vedi `ball_motion`
            let level = core::mem::take(&mut pl.rise);
            b.vy = 0;
            let ahead = if level >= MAX_SPECIAL_LEVEL {
                p.width - (p.width >> 3)
            } else {
                (p.width >> 1) + (p.width >> 3)
            };
            n.rise_break = Some(match side {
                Side::Left => ahead,
                Side::Right => p.width - ahead,
            });
            n.special_flight = Some(Special::Rise);
            n.special_level = level;
            events.add(Event::SpecialHit);
        }
    }

    /// Dopo un punto gli effetti sulla palla e il BULLET in corso finiscono; i bonus armati (anche
    /// il BULLET non ancora scattato) restano. Le
    /// mosse speciali in corso finiscono e chi ha subito il punto (l'avversario di `scorer`) carica
    /// la barra.
    pub(crate) fn next_on_point(&mut self, scorer: Side) {
        if let Some(n) = self.next.as_mut() {
            n.clear_shot();
            n.slow_timer = 0;
            n.slow = None;
            if n.bullet_on {
                n.end_bullet();
            }
            if n.super_moves {
                for pl in &mut n.players {
                    pl.straight = 0;
                    pl.rise = 0;
                }
                n.players[scorer.opponent() as usize].gain(self.params.super_gain_conceded, &self.params);
            }
        }
    }

    /// Al rimbalzo sul bordo l'effetto si inverte con la palla: la curva continua verso il centro.
    pub(crate) fn next_on_wall(&mut self) {
        if let Some(n) = self.next.as_mut() {
            n.curve = -n.curve;
        }
    }
}
