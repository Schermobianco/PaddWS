//! Simulazione di una partita, un tick alla volta.
//!
//! Coordinate in pixel (Fx) con origine in basso a sinistra e y verso l'alto.
//! Gli input arrivano come `Input` a ogni tick: lo stato completo della
//! partita dipende solo da parametri, seme e sequenza di input, quindi una
//! registrazione può essere rigiocata identica (anche da un core HDL).
//!
//! Vincoli per l'hardware: nel passo di simulazione non ci sono divisioni
//! (solo somme, confronti, shift e moltiplicazioni, anche per reciproci
//! precalcolati in `Params`) e nessuna allocazione.

use crate::fixed::{self, Fx, ONE, mul, mul_recip};
use crate::next::{Next, PaddleKind, Special, slowed};
use crate::params::Params;
use crate::rng::Rng;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Left = 0,
    Right = 1,
}

impl Side {
    pub const BOTH: [Side; 2] = [Side::Left, Side::Right];

    pub const fn opponent(self) -> Side {
        match self {
            Side::Left => Side::Right,
            Side::Right => Side::Left,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u16)]
pub enum Event {
    /// la palla ha rimbalzato sul bordo alto/basso
    Wall = 1,
    /// palla respinta da una racchetta
    Hit = 2,
    /// palla respinta con un boost
    Boost = 4,
    /// è stato segnato un punto
    Score = 8,
    /// NEXT: capsula raccolta
    Collect = 16,
    /// NEXT: bonus attivato
    Activate = 32,
    /// NEXT: colpo con il SUPER
    Super = 64,
    /// NEXT: la racchetta con TELEPORT è saltata all'altezza della palla
    Teleport = 128,
    /// NEXT: il BLASTER ha sparato
    Fire = 256,
    /// NEXT: la palla è rimbalzata sulla barriera del GUARDIAN
    Barrier = 512,
    /// NEXT, mosse speciali: STRAIGHT SHOT attivato (il prossimo colpo è armato)
    Straight = 1024,
    /// NEXT, mosse speciali: RISING STRIKE attivato (la racchetta è saltata verso la palla)
    Rise = 2048,
    /// NEXT, mosse speciali: colpo con una mossa speciale (quale in `Next::special_flight`)
    SpecialHit = 4096,
}

/// Insieme degli eventi di un tick (bitmask, un bit per evento).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Events(u16);

impl Events {
    pub const fn has(self, e: Event) -> bool {
        self.0 & e as u16 != 0
    }

    pub const fn bits(self) -> u16 {
        self.0
    }

    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }

    pub fn add(&mut self, e: Event) {
        self.0 |= e as u16;
    }

    pub fn iter(self) -> impl Iterator<Item = Event> {
        [
            Event::Wall,
            Event::Hit,
            Event::Boost,
            Event::Score,
            Event::Collect,
            Event::Activate,
            Event::Super,
            Event::Teleport,
            Event::Fire,
            Event::Barrier,
            Event::Straight,
            Event::Rise,
            Event::SpecialHit,
        ]
        .into_iter()
        .filter(move |e| self.has(*e))
    }
}

/// Comandi di un giocatore per un tick.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PlayerInput {
    /// +1 su, -1 giù, 0 ferma
    pub direction: i8,
    /// accelerazione rapida (doppio tocco)
    pub fast: bool,
    /// scatto in avanti/indietro (EVO): va a true per un solo tick
    pub forward: bool,
    /// posizione assoluta da encoder: distanza in pixel dal bordo alto
    pub top_offset: Option<i32>,
    /// NEXT: seleziona il bonus successivo della riserva (un solo tick)
    pub select: bool,
    /// NEXT: attiva il bonus selezionato (un solo tick)
    pub activate: bool,
    /// NEXT: il BLASTER spara (un solo tick)
    pub fire: bool,
    /// NEXT con le mosse speciali: mossa da eseguire (un solo tick). Il gesto (il movimento
    /// del joystick) lo riconosce chi legge i comandi, non il core; senza barra sufficiente o
    /// con le mosse spente il comando non fa nulla
    pub special: Option<Special>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Input {
    pub players: [PlayerInput; 2],
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Ball {
    pub x: Fx,
    pub y: Fx,
    pub radius: Fx,
    pub vx: Fx,
    pub vy: Fx,
    /// moltiplicatore della velocità orizzontale
    pub boost: Fx,
    /// spostamento orizzontale dell'ultimo tick (0 prima della battuta): la previsione del
    /// TELEPORT lo usa al posto di `vx * boost`
    pub dx: Fx,
}

impl Ball {
    pub const fn left(&self) -> Fx {
        self.x - self.radius
    }
    pub const fn right(&self) -> Fx {
        self.x + self.radius
    }
    pub const fn bottom(&self) -> Fx {
        self.y - self.radius
    }
    pub const fn top(&self) -> Fx {
        self.y + self.radius
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Paddle {
    pub side: Side,
    pub x: Fx,
    pub y: Fx,
    pub width: Fx,
    pub height: Fx,
    pub home_x: Fx,
    pub fwd_x: Fx,
    /// reciproco (Q8.24) di metà altezza
    pub inv_half_height: i32,
    /// livello di restringimento dell'area boost (indice in `Params::boost_heights`)
    pub boost_level: u8,
    /// altezza dell'area boost EVO al centro della racchetta, in pixel interi
    pub boost_height: Fx,
    pub speed: Fx,
    pub direction: i8,
    pub fast: bool,
    /// velocità massima e accelerazioni: quelle di `Params`, o del tipo di racchetta in NEXT
    pub max_speed: Fx,
    pub acceleration: Fx,
    pub fast_acceleration: Fx,
    /// velocità massima e accelerazioni con la racchetta avanzata (RUSH è più veloce)
    pub fwd_max_speed: Fx,
    pub fwd_acceleration: Fx,
    pub fwd_fast_acceleration: Fx,
    /// spostamento verticale per tick, smorzato (anche con l'encoder): serve a TWIST
    pub motion: Fx,
    /// spostamento massimo per tick con l'encoder (0 = nessun limite, la racchetta va alla manopola)
    pub encoder_step: Fx,
}

impl Paddle {
    pub const fn left(&self) -> Fx {
        self.x - self.width / 2
    }
    pub const fn right(&self) -> Fx {
        self.x + self.width / 2
    }
    pub const fn bottom(&self) -> Fx {
        self.y - self.height / 2
    }
    pub const fn top(&self) -> Fx {
        self.y + self.height / 2
    }
    pub const fn at_home(&self) -> bool {
        self.x == self.home_x
    }

    fn set_boost_level(&mut self, level: u8, p: &Params) {
        self.boost_level = level.min(p.boost_levels - 1);
        self.boost_height = p.boost_heights[self.boost_level as usize];
    }

    fn set_direction(&mut self, direction: i8, fast: bool) {
        if (direction as i32) * self.speed.signum() < 0 {
            self.speed = mul(self.speed, fixed::ONE * 3 / 10); // conserva un po' di slancio quando si inverte
        }
        self.direction = direction;
        self.fast = fast;
    }

    /// Un tick di movimento. `slow` è lo shift del BULLET (0 = piena velocità): rallenta il passo,
    /// non la velocità né le accelerazioni.
    fn update(&mut self, p: &Params, slow: u32) {
        if self.direction != 0 {
            let (max, accel, fast) = if self.at_home() {
                (self.max_speed, self.acceleration, self.fast_acceleration)
            } else {
                (self.fwd_max_speed, self.fwd_acceleration, self.fwd_fast_acceleration)
            };
            let accel = if self.fast { fast } else { accel };
            self.speed = (self.speed + accel * self.direction as Fx).clamp(-max, max);
        } else if self.speed.abs() > p.pad_stop_speed {
            self.speed = if self.speed > 0 {
                (self.speed - p.pad_deceleration).max(0)
            } else {
                (self.speed + p.pad_deceleration).min(0)
            };
        } else {
            self.speed = 0;
        }

        let half = self.height / 2;
        let y = self.y + slowed(self.speed, slow);
        if y < half || y > p.height - half {
            self.y = y.clamp(half, p.height - half);
            self.speed = 0;
        } else {
            self.y = y;
        }
    }
}

/// STEER con l'encoder: la racchetta è ferma, quindi la manopola lontana dalla racchetta
/// (oltre 1/8 della sua altezza) vale come su o giù tenuti premuti.
fn steer_from_offset(pad: &Paddle, offset: i32, height: Fx) -> i8 {
    let goal = height - fixed::int(offset) - pad.height / 2;
    let dead = pad.height >> 3;
    if goal > pad.y + dead {
        1
    } else if goal < pad.y - dead {
        -1
    } else {
        0
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Match {
    pub params: Params,
    pub players: u8,
    pub evo: bool,
    pub paddles: [Paddle; 2],
    pub ball: Ball,
    pub score: [u16; 2],
    /// record del giocatore singolo
    pub best: u16,
    /// tick di attesa della palla al centro prima della battuta
    pub serve_timer: u32,
    pub tick: u64,
    pub rng: Rng,
    /// stato della modalità NEXT, None in Classic ed EVO
    pub next: Option<Next>,
}

impl Match {
    pub fn new(params: Params, players: u8, evo: bool, seed: u32) -> Self {
        assert!(players == 1 || players == 2, "players must be 1 or 2");
        let p = &params;
        let right_height = if players == 2 { p.pad_height } else { p.height }; // giocatore singolo: muro a tutta altezza
        let paddle = |side, x, height, fwd_x| Paddle {
            side,
            x,
            y: p.height / 2,
            width: p.pad_width,
            height,
            home_x: x,
            fwd_x,
            inv_half_height: if height == p.pad_height {
                p.pad_inv_half_height
            } else {
                p.wall_inv_half_height
            },
            boost_level: 0,
            boost_height: p.boost_heights[0],
            speed: 0,
            direction: 0,
            fast: false,
            max_speed: p.pad_max_speed,
            acceleration: p.pad_acceleration,
            fast_acceleration: p.pad_fast_acceleration,
            fwd_max_speed: p.pad_max_speed,
            fwd_acceleration: p.pad_acceleration,
            fwd_fast_acceleration: p.pad_fast_acceleration,
            motion: 0,
            encoder_step: 0,
        };
        let paddles = [
            paddle(Side::Left, p.pad_start_pos, p.pad_height, p.pad_fwd_pos),
            paddle(
                Side::Right,
                p.width - p.pad_start_pos,
                right_height,
                p.width - p.pad_fwd_pos,
            ),
        ];
        let ball = Ball {
            x: p.width / 2,
            y: p.height / 2,
            radius: p.ball_radius,
            vx: 0,
            vy: 0,
            boost: ONE,
            dx: 0,
        };
        let mut m = Self {
            players,
            evo: evo && players == 2,
            paddles,
            ball,
            score: [0, 0],
            best: 0,
            serve_timer: 0,
            tick: 0,
            rng: Rng::new(seed),
            params,
            next: None,
        };
        let first = if m.rng.sign() > 0 { Side::Left } else { Side::Right };
        m.serve(first);
        m
    }

    pub const fn max_ball_speed(&self) -> Fx {
        if self.next.is_some() {
            self.params.max_ball_speed_next
        } else if self.players == 2 {
            self.params.max_ball_speed_2p
        } else {
            self.params.max_ball_speed_1p
        }
    }

    /// Accelerazione della palla a ogni colpo.
    pub const fn kspeed(&self) -> Fx {
        if self.next.is_some() {
            self.params.kspeed_next
        } else if self.players == 2 {
            self.params.kspeed_2p
        } else {
            self.params.kspeed_1p
        }
    }

    /// La palla è ferma al centro in attesa della battuta.
    pub const fn serving(&self) -> bool {
        self.serve_timer > 0
    }

    fn serve(&mut self, toward: Side) {
        let toward = if self.players == 1 { Side::Left } else { toward };
        let p = &self.params;
        let vx = p.serve_unit * self.rng.range(2, 4);
        let vy = p.serve_unit * self.rng.range(1, 3) * self.rng.sign();
        self.ball = Ball {
            x: p.width / 2,
            y: p.height / 2,
            radius: p.ball_radius,
            vx: if toward == Side::Left { -vx } else { vx },
            vy,
            boost: ONE,
            dx: 0,
        };
        self.serve_timer = p.serve_ticks;
    }

    // ------------------------------------------------------------- simulazione

    /// Avanza la partita di un tick (1 / `TICK_HZ` secondi).
    pub fn step(&mut self, input: &Input) -> Events {
        let mut events = Events::default();
        self.tick += 1;
        if self.next_frozen() {
            return events;
        }
        self.next_bullet_countdown();
        let before = [self.paddles[0].y, self.paddles[1].y];
        self.apply_input(input, &mut events);

        // BULLET: rallenta la racchetta dell'avversario di chi l'ha attivato
        let slow = self.bullet_shifts();
        for ((pad, y), slow) in self.paddles.iter_mut().zip(before).zip(slow) {
            pad.update(&self.params, slow);
            pad.motion += (pad.y - y - pad.motion) >> 2;
        }
        if self.next.is_some() {
            self.next_tick(input, &mut events);
        }

        if self.serve_timer > 0 {
            self.serve_timer -= 1;
            return events;
        }

        let (prev_x, prev_y) = (self.ball.x, self.ball.y);
        let mut dx = mul(self.ball.vx, self.ball.boost);
        let mut dy = self.ball.vy;
        if let Some(n) = self.next.as_mut() {
            n.ball_motion(&mut self.ball, &self.params, &self.paddles, &mut dx, &mut dy);
        }
        let p = &self.params;
        let b = &mut self.ball;
        b.x += dx;
        b.y += dy;
        b.dx = dx;

        if b.top() >= p.height - ONE {
            b.y = p.height - ONE - b.radius;
            b.vy = -b.vy.abs();
            events.add(Event::Wall);
        } else if b.bottom() <= ONE {
            b.y = ONE + b.radius;
            b.vy = b.vy.abs();
            events.add(Event::Wall);
        }

        if events.has(Event::Wall) {
            self.next_on_wall();
        }

        let side = if self.ball.vx < 0 { Side::Left } else { Side::Right };
        if let Some(contact_y) = self.contact(side, prev_x, prev_y) {
            self.ball.y = contact_y;
            events.add(self.bounce(side));
            self.next_on_hit(side, false, &mut events);
        } else if self.next_barrier(side) {
            events.add(Event::Barrier);
        } else if self.ball.left() <= 0 {
            events.add(self.point(Side::Right));
        } else if self.ball.right() >= self.params.width {
            events.add(self.point(Side::Left));
        }
        events
    }

    fn apply_input(&mut self, input: &Input, events: &mut Events) {
        for side in Side::BOTH {
            if side == Side::Right && self.players == 1 {
                continue; // il muro non si muove
            }
            let cmd = input.players[side as usize];
            if let Some(n) = self.next.as_mut()
                && n.steer == Some(side)
            {
                // STEER: la racchetta resta ferma e su/giù guidano la palla
                let pad = &mut self.paddles[side as usize];
                n.steer_dir = match cmd.top_offset {
                    Some(offset) => steer_from_offset(pad, offset, self.params.height),
                    None => cmd.direction.signum(),
                };
                pad.direction = 0;
                pad.speed = 0;
            } else {
                let pad = &mut self.paddles[side as usize];
                if cmd.direction != pad.direction || (cmd.direction != 0 && cmd.fast != pad.fast) {
                    pad.set_direction(cmd.direction.signum(), cmd.fast);
                }
                if let Some(offset) = cmd.top_offset {
                    self.set_paddle_top(side, offset);
                }
            }
            // il BLASTER senza scatto spara con il tasto dello scatto
            let blaster = self.paddle_kind(side) == Some(PaddleKind::Blaster);
            let dash = !blaster || self.params.blaster_dash;
            if blaster && (cmd.fire || (cmd.forward && !dash)) {
                self.next_fire(side, events);
            }
            if cmd.forward && dash {
                let boost = self.toggle_forward(side);
                // NEXT: nel giro delle capsule di questo tick la racchetta tocca tutto il tratto saltato
                if let Some(n) = self.next.as_mut() {
                    n.players[side as usize].dashed = true;
                }
                if let Some(e) = boost {
                    events.add(e);
                    self.next_on_hit(side, true, events); // lo scatto che intercetta la palla vale come colpo
                }
            }
            if cmd.select || cmd.activate {
                self.next_command(side, &cmd, events);
            }
        }
    }

    /// Shift del BULLET per le due racchette in questo tick (0 = piena velocità).
    pub fn bullet_shifts(&self) -> [u32; 2] {
        match &self.next {
            Some(n) => Side::BOTH.map(|side| n.bullet_shift_for(side, &self.params)),
            None => [0, 0],
        }
    }

    /// Posiziona una racchetta in base alla distanza dal bordo alto (input dell'encoder).
    fn set_paddle_top(&mut self, side: Side, offset: i32) {
        let h = self.params.height;
        let slow = self.bullet_shifts()[side as usize];
        let pad = &mut self.paddles[side as usize];
        let half = pad.height / 2;
        let goal = (h - fixed::int(offset) - half).clamp(half, h - half);
        // i tipi di racchetta lenti seguono la manopola con una velocità massima; con il BULLET
        // dell'avversario tutte, a velocità rallentata (quella di una mano veloce per le altre)
        let step = if pad.encoder_step > 0 {
            pad.encoder_step
        } else if slow > 0 {
            self.params.encoder_hand_step
        } else {
            0
        };
        let step = slowed(step, slow);
        pad.y = if step > 0 {
            pad.y + (goal - pad.y).clamp(-step, step)
        } else {
            goal
        };
        pad.speed = 0;
    }

    /// Mossa EVO e NEXT: la racchetta scatta in avanti (o torna indietro). Se intercetta la palla la potenzia.
    fn toggle_forward(&mut self, side: Side) -> Option<Event> {
        if !self.evo && self.next.is_none() {
            return None;
        }
        let pad = &mut self.paddles[side as usize];
        if !pad.at_home() {
            pad.x = pad.home_x;
            return None;
        }
        let old_x = pad.x;
        pad.x = pad.fwd_x;
        if self.ball_in_forward_area(side, old_x) {
            Some(self.forward_boost(side))
        } else {
            None
        }
    }

    /// La y della palla nel momento in cui tocca la racchetta nell'ultimo spostamento, o None.
    ///
    /// Se il bordo anteriore della palla ha attraversato la faccia della racchetta
    /// nel tick, la y del contatto è il punto medio dello spostamento (uno shift,
    /// nessuna divisione): le palle veloci non possono attraversare la racchetta.
    /// Altrimenti vale un semplice test di sovrapposizione.
    fn contact(&self, side: Side, prev_x: Fx, prev_y: Fx) -> Option<Fx> {
        let b = &self.ball;
        let pad = &self.paddles[side as usize];
        let r = b.radius;
        let crossed = match side {
            Side::Left => {
                if prev_x < pad.x {
                    return None; // già dietro la racchetta
                }
                prev_x - r >= pad.right() && pad.right() > b.x - r
            }
            Side::Right => {
                if prev_x > pad.x {
                    return None;
                }
                prev_x + r <= pad.left() && pad.left() < b.x + r
            }
        };
        if crossed {
            let y = (prev_y + b.y) >> 1;
            if y - r <= pad.top() && y + r >= pad.bottom() {
                return Some(y);
            }
        }
        let overlap =
            b.left() <= pad.right() && b.right() >= pad.left() && b.bottom() <= pad.top() && b.top() >= pad.bottom();
        overlap.then_some(b.y)
    }

    /// Velocità verticale aggiunta dalla racchetta: proporzionale alla distanza dal centro,
    /// fortemente smorzata dentro l'area boost EVO. Il secondo valore dice se la palla è dentro
    /// l'area boost (EVO).
    fn reflection(&self, pad: &Paddle) -> (Fx, bool) {
        let b = &self.ball;
        let size = pad.height;
        let speed = b.vx.abs();
        if self.evo {
            let bh = pad.boost_height;
            let start = fixed::int(fixed::floor((size - bh) >> 1));
            let rel = b.y - (pad.y - fixed::int(fixed::floor(size >> 1)));
            if bh > 0 && start <= rel && rel <= start + bh {
                let center = start + fixed::int(fixed::floor(bh >> 1));
                let inv = self.params.boost_inv_half[pad.boost_level as usize];
                return (mul(mul_recip(mul(speed, rel - center), inv), ONE / 5), true);
            }
        }
        (mul_recip(mul(speed, b.y - pad.y), pad.inv_half_height), false)
    }

    fn bounce(&mut self, side: Side) -> Event {
        let (reflection, in_area) = self.reflection(&self.paddles[side as usize]);
        let max_speed = self.max_ball_speed();
        let kspeed = self.kspeed();
        // in singolo il muro rimanda la palla senza accelerarla: accelerano solo i colpi del giocatore
        let speeds_up = !(self.players == 1 && side == Side::Right);
        let p = &self.params;
        let pad = &mut self.paddles[side as usize];
        let b = &mut self.ball;

        b.vy += reflection;
        if b.vx.abs() < b.vy.abs() {
            b.vy = b.vx.abs() * b.vy.signum(); // mai più ripida di 45 gradi
        }

        // EVO: la palla normale colpita dentro l'area boost (la banda grigia) parte potenziata
        let event = if self.evo && b.boost == ONE && in_area {
            b.boost = p.boost_mul;
            b.radius = p.ball_radius_boost;
            pad.set_boost_level(pad.boost_level + 1, p); // l'area si restringe
            Event::Boost
        } else {
            b.boost = ONE;
            b.radius = p.ball_radius;
            Event::Hit
        };

        b.x = match side {
            Side::Left => pad.right() + b.radius,
            Side::Right => pad.left() - b.radius,
        };
        b.vx = -b.vx;
        if speeds_up && b.vx.abs() < max_speed {
            b.vx = mul(b.vx, kspeed);
            b.vy = mul(b.vy, kspeed);
        }

        if self.players == 1 && side == Side::Right {
            self.score[Side::Left as usize] = self.score[Side::Left as usize].saturating_add(1);
        }
        event
    }

    fn point(&mut self, scorer: Side) -> Event {
        if self.players == 2 {
            self.score[scorer as usize] = self.score[scorer as usize].saturating_add(1);
            for pad in &mut self.paddles {
                pad.set_boost_level(0, &self.params);
            }
        } else {
            self.best = self.best.max(self.score[Side::Left as usize]);
            self.score[Side::Left as usize] = 0;
        }
        self.next_on_point(scorer);
        self.serve(scorer.opponent()); // la battuta va verso chi ha subito il punto
        Event::Score
    }

    /// Lo scatto prende la palla: è in arrivo tra la faccia di casa e quella avanzata e, nel tratto
    /// che le resta fino al retro della racchetta di casa, passerebbe all'altezza della racchetta
    /// (le palle che stando ferma avrebbe preso, anche nello spessore come `contact`). Il tratto si percorre a passi di un tick, solo con somme: in
    /// diagonale la palla che adesso è appena sopra o sotto la racchetta ci entra poco dopo.
    fn ball_in_forward_area(&self, side: Side, old_x: Fx) -> bool {
        let b = &self.ball;
        let pad = &self.paddles[side as usize];
        let half = fixed::int(fixed::floor(pad.width >> 1));
        let inside = match side {
            Side::Left => old_x + half <= b.left() && b.left() <= pad.x + half && b.vx < 0,
            Side::Right => pad.x - half <= b.right() && b.right() <= old_x - half && b.vx > 0,
        };
        if !inside || b.vx == 0 {
            return false;
        }
        // distanza dal retro della racchetta di casa, consumata un tick alla volta (al massimo 64)
        let (mut gap, step) = match side {
            Side::Left => (b.right() - (old_x - half), -b.vx),
            Side::Right => ((old_x + half) - b.left(), b.vx),
        };
        let mut y = b.y;
        for _ in 0..64 {
            if y - b.radius <= pad.top() && y + b.radius >= pad.bottom() {
                return true;
            }
            if gap <= 0 {
                break;
            }
            gap -= step;
            y += b.vy;
        }
        false
    }

    fn forward_boost(&mut self, side: Side) -> Event {
        let p = &self.params;
        let b = &mut self.ball;
        // un boost più forte di quello dello scatto (EVO, SMASH, SUPER) si annulla; quello più
        // debole del colpo di HAMMER no, altrimenti toglierebbe all'avversario lo scatto
        let event = if b.boost < p.boost_fwd_mul {
            b.boost = p.boost_fwd_mul;
            b.radius = p.ball_radius_boost_fwd;
            Event::Boost
        } else {
            b.boost = ONE;
            b.radius = p.ball_radius;
            Event::Hit
        };
        let push = mul(b.vx.abs(), ONE * 6 / 5);
        b.vx = if side == Side::Left { push } else { -push };
        b.vy += mul(self.rng.unit(), p.serve_unit);
        // la palla presa tra la posizione di casa e quella avanzata riparte dalla faccia della
        // racchetta, non da dietro
        let pad = &self.paddles[side as usize];
        match side {
            Side::Left => b.x = b.x.max(pad.right() + b.radius),
            Side::Right => b.x = b.x.min(pad.left() - b.radius),
        }
        event
    }
}
