//! Giocatore umano simulato, solo per le statistiche (non entra nel gioco né nel core MiSTer,
//! quindi usa la virgola mobile). Mette insieme modelli noti del controllo motorio:
//!
//! - tempo di reazione ex-gaussiano (gaussiana più coda esponenziale) quando si vede la palla
//!   partire verso di sé: la coda lunga sono le distrazioni;
//! - ritardo visuomotorio: vede la palla com'era 0,1-0,2 s fa (ritardo del cervello più quello
//!   dello schermo) e la proietta in avanti con la velocità stimata;
//! - errore di stima della velocità proporzionale alla velocità (frazione di Weber): una parte
//!   resta per tutta la traiettoria, una cambia a ogni sguardo; ogni rimbalzo sui bordi
//!   aggiunge un errore;
//! - controllo intermittente: rifà il piano ogni 100-160 ms (sottomovimenti), quindi la stima
//!   migliora man mano che la palla si avvicina;
//! - rumore motorio proporzionale all'ampiezza del movimento (Harris e Wolpert, 1998); sulla
//!   manopola ogni correzione è un movimento a jerk minimo (Flash e Hogan, 1985) che dura
//!   quanto dice la legge di Fitts e si somma a quelli ancora in corso (Flash e Henis, 1991);
//! - joystick e tastiera: pressione e rilascio con una latenza motoria e una conoscenza solo
//!   parziale dell'inerzia della racchetta, quindi a volte la si porta oltre il bersaglio;
//! - scatto in avanti a tempo: si preme quando si stima che la palla entri nella zona, con un
//!   errore di tempo di qualche decina di millisecondi.
//!
//! Le decisioni sui bonus NEXT (attivare, cambiare, sparare col BLASTER), sulle mosse speciali e
//! STEER restano quelle della CPU del gioco, al livello indicato nel profilo.

use std::collections::VecDeque;

use paddws_core::{Bonus, Control, Cpu, Fx, Match, PaddleKind, PlayerInput, Side, TICK_HZ};

/// Abilità di un giocatore: tempi in secondi, distanze in pixel a 800x480.
#[derive(Clone, Copy, Debug)]
pub struct Profile {
    pub name: &'static str,
    /// tempo di reazione ex-gaussiano: media e deviazione della gaussiana, media della coda
    rt_mu: f64,
    rt_sigma: f64,
    rt_tau: f64,
    /// ritardo con cui vede la palla durante il gioco
    delay: f64,
    /// errore relativo nella stima della velocità (frazione di Weber)
    weber: f64,
    /// errore in più a ogni rimbalzo previsto sui bordi
    bounce_px: f64,
    /// ogni quanto rifà il piano
    replan: f64,
    /// rumore motorio: deviazione del punto d'arrivo per pixel di movimento
    motor_k: f64,
    /// legge di Fitts: secondi per bit (più basso = mano più rapida a fermarsi sul bersaglio)
    fitts_b: f64,
    /// velocità massima della mano sulla manopola, px per tick a 240 Hz
    hand_px: f64,
    /// joystick e tastiera: latenza di pressione e rilascio, media e deviazione
    key_lat: f64,
    key_sd: f64,
    /// quanto tiene conto dell'inerzia della racchetta quando rilascia (0-1)
    momentum: f64,
    /// quanto torna verso il centro quando la palla si allontana (0-1)
    recenter: f64,
    /// probabilità di provare lo scatto a ogni palla in arrivo e errore di tempo
    dash_use: f64,
    dash_sigma: f64,
    /// probabilità di mirare apposta con un bordo della racchetta per dare angolo
    aim: f64,
    /// livello della CPU che decide i bonus
    cpu_level: u8,
}

pub const PROFILES: [Profile; 3] = [
    Profile {
        name: "principiante",
        rt_mu: 0.26,
        rt_sigma: 0.04,
        rt_tau: 0.09,
        delay: 0.16,
        weber: 0.14,
        bounce_px: 40.0,
        replan: 0.16,
        motor_k: 0.12,
        fitts_b: 0.16,
        hand_px: 4.0,
        key_lat: 0.09,
        key_sd: 0.03,
        momentum: 0.4,
        recenter: 0.4,
        dash_use: 0.3,
        dash_sigma: 0.06,
        aim: 0.1,
        cpu_level: 0,
    },
    Profile {
        name: "medio",
        rt_mu: 0.23,
        rt_sigma: 0.03,
        rt_tau: 0.06,
        delay: 0.13,
        weber: 0.10,
        bounce_px: 25.0,
        replan: 0.13,
        motor_k: 0.09,
        fitts_b: 0.13,
        hand_px: 5.0,
        key_lat: 0.07,
        key_sd: 0.02,
        momentum: 0.7,
        recenter: 0.7,
        dash_use: 0.6,
        dash_sigma: 0.04,
        aim: 0.3,
        cpu_level: 1,
    },
    Profile {
        name: "esperto",
        rt_mu: 0.20,
        rt_sigma: 0.02,
        rt_tau: 0.04,
        delay: 0.11,
        weber: 0.07,
        bounce_px: 14.0,
        replan: 0.10,
        motor_k: 0.06,
        fitts_b: 0.10,
        hand_px: 6.0,
        key_lat: 0.05,
        key_sd: 0.015,
        momentum: 0.9,
        recenter: 0.9,
        dash_use: 0.9,
        dash_sigma: 0.025,
        aim: 0.5,
        cpu_level: 3,
    },
];

/// Profilo dal nome (anche solo l'iniziale).
pub fn profile(name: &str) -> Option<usize> {
    PROFILES
        .iter()
        .position(|p| p.name.eq_ignore_ascii_case(name) || p.name[..1].eq_ignore_ascii_case(name))
}

/// Generatore SplitMix64: veloce e indipendente da quello della partita.
#[derive(Clone)]
struct Noise(u64);

impl Noise {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// uniforme in [0, 1)
    fn uniform(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }

    /// gaussiana standard (Box-Muller)
    fn normal(&mut self) -> f64 {
        let u = self.uniform().max(1e-12);
        (-2.0 * u.ln()).sqrt() * (std::f64::consts::TAU * self.uniform()).cos()
    }

    fn chance(&mut self, p: f64) -> bool {
        self.uniform() < p
    }

    fn sign(&mut self) -> f64 {
        if self.chance(0.5) { 1.0 } else { -1.0 }
    }

    /// tempo di reazione ex-gaussiano, in secondi
    fn ex_gauss(&mut self, mu: f64, sigma: f64, tau: f64) -> f64 {
        mu + sigma * self.normal() - tau * (1.0 - self.uniform()).ln()
    }
}

fn f(v: Fx) -> f64 {
    v as f64 / 65536.0
}

/// La mano sulla manopola: una posizione di partenza più i movimenti a jerk minimo in corso
/// (tick d'inizio, durata in tick, spostamento), che si sommano.
#[derive(Clone, Default)]
struct Hand {
    base: f64,
    moves: Vec<(u64, f64, f64)>,
}

impl Hand {
    /// Frazione percorsa di un movimento: lenta all'inizio e alla fine.
    fn shape(tick: u64, start: u64, ticks: f64) -> f64 {
        let s = ((tick - start) as f64 / ticks).min(1.0);
        s * s * s * (10.0 - 15.0 * s + 6.0 * s * s)
    }

    fn at(&self, tick: u64) -> f64 {
        self.base
            + self
                .moves
                .iter()
                .map(|&(t0, n, d)| d * Self::shape(tick, t0, n))
                .sum::<f64>()
    }

    /// Dove arriverà la mano a movimenti finiti.
    fn end(&self) -> f64 {
        self.base + self.moves.iter().map(|m| m.2).sum::<f64>()
    }

    /// I movimenti finiti entrano nella posizione di partenza.
    fn settle(&mut self, tick: u64) {
        let base = &mut self.base;
        self.moves.retain(|&(t0, n, d)| {
            let done = (tick - t0) as f64 >= n;
            if done {
                *base += d;
            }
            !done
        });
    }

    fn reset(&mut self, y: f64) {
        self.base = y;
        self.moves.clear();
    }
}

/// Quello che vede della palla in un tick.
#[derive(Clone, Copy)]
struct Seen {
    x: f64,
    y: f64,
    dx: f64,
    dy: f64,
    visible: bool,
    /// attesa della battuta
    serving: bool,
}

/// y d'arrivo alla faccia `face` partendo da (x, y) con velocità (vx, vy), rimbalzi sui bordi
/// `low` e `high` compresi: (y, tick all'arrivo, rimbalzi). `None` se la palla non arriva.
fn arrival(x: f64, y: f64, vx: f64, vy: f64, face: f64, low: f64, high: f64) -> Option<(f64, f64, u32)> {
    let t = (face - x) / vx;
    if !t.is_finite() || t < 0.0 {
        return None;
    }
    let span = high - low;
    let lin = y + vy * t - low;
    let bounces = (lin / span).floor().abs() as u32;
    let u = lin.rem_euclid(2.0 * span);
    let y = if u <= span { low + u } else { low + 2.0 * span - u };
    Some((y, t, bounces))
}

pub struct Human {
    side: Side,
    p: Profile,
    control: Control,
    noise: Noise,
    /// CPU del gioco: decide bonus, spari e STEER
    cpu: Cpu,
    /// ultimi tick visti della palla (il primo è quello che percepisce ora)
    seen: VecDeque<Seen>,
    /// ultimo tick in cui la palla era visibile, e quanti tick fa
    last_visible: Option<(Seen, f64)>,
    prev_y: f64,
    /// la palla (come la vede) veniva verso di sé
    was_coming: bool,
    /// tick in cui finisce la reazione e in cui rifà il piano
    react_at: u64,
    plan_at: u64,
    /// errori della traiettoria in arrivo: velocità e rimbalzi
    bias_v: f64,
    bias_b: f64,
    /// mira apposta con un bordo (pixel dal centro della racchetta)
    aim: f64,
    /// dove vuole portare la racchetta
    goal: f64,
    /// manopola: movimenti della mano e posizione della racchetta al tick prima
    hand: Hand,
    last_pad: f64,
    /// joystick e tastiera: comando applicato e quello in arrivo (con il tick)
    keys: (i8, bool),
    pending: Option<(u64, (i8, bool))>,
    /// scatto: vuole provarlo su questa palla, tick in cui preme, tick in cui torna a casa
    dash_wanted: bool,
    dash_at: Option<u64>,
    home_at: Option<u64>,
    /// fattore di scala dei pixel rispetto a 480 righe
    scale: f64,
    /// frequenza della simulazione (tick al secondo)
    hz: f64,
}

impl Human {
    pub fn new(m: &Match, profile: usize, control: Control, side: Side, seed: u32) -> Self {
        let p = PROFILES[profile];
        let h = f(m.params.height);
        Self {
            side,
            p,
            control,
            noise: Noise(seed as u64 ^ 0x4855_4D41_4E00 ^ ((side as u64) << 40)),
            cpu: Cpu::new(&m.params, p.cpu_level, side, seed).with_control(control),
            seen: VecDeque::new(),
            last_visible: None,
            prev_y: f(m.ball.y),
            was_coming: false,
            react_at: 0,
            plan_at: 0,
            bias_v: 0.0,
            bias_b: 0.0,
            aim: 0.0,
            goal: h / 2.0,
            hand: Hand {
                base: h / 2.0,
                moves: Vec::new(),
            },
            last_pad: h / 2.0,
            keys: (0, false),
            pending: None,
            dash_wanted: false,
            dash_at: None,
            home_at: None,
            scale: h / 480.0,
            hz: m.params.tick_hz as f64,
        }
    }

    /// Secondi -> tick.
    fn ticks(&self, s: f64) -> f64 {
        s * self.hz
    }

    pub const fn side(&self) -> Side {
        self.side
    }

    /// Ritardo di percezione in tick.
    fn delay(&self) -> usize {
        self.ticks(self.p.delay) as usize
    }

    /// Prende nota della palla di questo tick e restituisce quella che percepisce ora, con quanti
    /// tick fa era lì (più del ritardo se nel frattempo era nascosta).
    fn look(&mut self, m: &Match) -> (Seen, f64) {
        let b = &m.ball;
        let y = f(b.y);
        // spostamento verticale misurato; al rimbalzo sul bordo vale il verso nuovo
        let mut dy = y - self.prev_y;
        if dy * f(b.vy) < 0.0 {
            dy = dy.abs() * f(b.vy).signum();
        }
        if dy.abs() > f(m.params.height) / 4.0 {
            dy = f(b.vy); // nuova battuta: la palla è stata rimessa in campo
        }
        self.prev_y = y;
        let hidden = m.next.as_ref().is_some_and(|n| n.ball_hidden(&m.params, m.tick));
        self.seen.push_back(Seen {
            x: f(b.x),
            y,
            dx: f(b.dx),
            dy,
            visible: !hidden,
            serving: m.serving(),
        });
        while self.seen.len() > self.delay() + 1 {
            self.seen.pop_front();
        }
        let now = self.seen[0];
        let age = (self.seen.len() - 1) as f64;
        if now.serving {
            // palla nuova: quello visto prima non conta più
            self.last_visible = None;
            return (now, age);
        }
        self.last_visible = match (now.visible, self.last_visible) {
            (true, _) => Some((now, age)),
            (false, Some((s, a))) => Some((s, a + 1.0)),
            (false, None) => None,
        };
        self.last_visible.unwrap_or((now, age))
    }

    /// Comandi per il prossimo tick.
    pub fn input(&mut self, m: &Match) -> PlayerInput {
        let i = self.side as usize;
        let tick = m.tick;
        let (ball, age) = self.look(m);
        // decisioni sui bonus della CPU (la si chiama ogni tick perché tiene il suo stato)
        let cpu = self.cpu.input(m);
        let pad = &m.paddles[i];
        let (h, half) = (f(m.params.height), f(pad.height) / 2.0);
        let r = f(m.ball.radius);
        let coming = match self.side {
            Side::Left => ball.dx < 0.0,
            Side::Right => ball.dx > 0.0,
        } && !ball.serving;

        // palla nuova in arrivo: reazione, errori di questa traiettoria, mira e scatto
        if coming && !self.was_coming {
            let rt = self.noise.ex_gauss(self.p.rt_mu, self.p.rt_sigma, self.p.rt_tau);
            let seen_at = tick as f64 - age;
            self.react_at = (seen_at + self.ticks(rt)).max(tick as f64) as u64;
            self.plan_at = self.react_at;
            self.bias_v = self.noise.normal() * self.p.weber * 0.7;
            self.bias_b = self.noise.normal() * 0.7;
            self.aim = if self.noise.chance(self.p.aim) {
                self.noise.sign() * half * (0.4 + 0.4 * self.noise.uniform())
            } else {
                0.0
            };
            self.dash_wanted = self.noise.chance(self.p.dash_use);
            self.dash_at = None;
        }
        if !coming && self.was_coming {
            self.plan_at = tick + self.ticks(self.p.rt_mu * 0.7) as u64; // si accorge che è andata
        }
        self.was_coming = coming;

        // nuovo piano a intervalli: la palla prevista, una capsula o verso il centro
        if tick >= self.plan_at {
            let jitter = 0.7 + 0.6 * self.noise.uniform();
            self.plan_at = tick + self.ticks(self.p.replan * jitter).max(1.0) as u64;
            let target = if coming {
                let half_w = f(pad.width) / 2.0;
                let face = match self.side {
                    Side::Left => f(pad.home_x) + half_w + r,
                    Side::Right => f(pad.home_x) - half_w - r,
                };
                let ev = self.bias_v + self.noise.normal() * self.p.weber * 0.5;
                let ew = self.bias_v + self.noise.normal() * self.p.weber * 0.5;
                let (low, high) = (r + 1.0, h - 1.0 - r);
                // palla già oltre la faccia: resta dov'era diretta
                arrival(
                    ball.x,
                    ball.y,
                    ball.dx * (1.0 + ew),
                    ball.dy * (1.0 + ev),
                    face,
                    low,
                    high,
                )
                .map(|(y, _, bounces)| {
                    let err = (self.bias_b + self.noise.normal() * 0.5) * self.p.bounce_px * self.scale;
                    y + err * bounces as f64 - self.aim
                })
                .or(Some(self.goal))
            } else {
                None
            };
            let target = target.unwrap_or_else(|| {
                let capsule = m.next.as_ref().and_then(|n| {
                    if n.players[i].full() {
                        return None;
                    }
                    n.capsules
                        .iter()
                        .flatten()
                        .find(|c| c.toward() == self.side)
                        .map(|c| f(c.y))
                });
                capsule.unwrap_or(f(pad.y) + (h / 2.0 - f(pad.y)) * self.p.recenter)
            });
            // rumore motorio proporzionale al movimento da fare
            let dist = (target - f(pad.y)).abs();
            self.goal = (target + self.noise.normal() * self.p.motor_k * dist).clamp(half, h - half);
            // correzione della mano verso il nuovo bersaglio. Fitts: più lontano e più preciso
            // (mezza racchetta) = più lento
            let shift = self.goal - self.hand.end();
            if shift.abs() > 0.5 {
                let bits = (shift.abs() / (f(pad.height) / 2.0) + 1.0).log2();
                self.hand.moves.push((
                    tick,
                    self.ticks(self.p.fitts_b * bits).max(4.0 * self.hz / TICK_HZ as f64),
                    shift,
                ));
            }
        }

        let mut cmd = PlayerInput {
            select: cpu.select,
            activate: cpu.activate,
            fire: cpu.fire,
            // mosse speciali come la CPU, che le decide guardando questa racchetta: così anche
            // RISING STRIKE salva le palle che la mano non raggiunge
            special: cpu.special,
            ..PlayerInput::default()
        };
        let next = m.next.as_ref();
        let steering = next.is_some_and(|n| n.steer == Some(self.side));
        let teleport = next.is_some_and(|n| n.players[i].armed == Some(Bonus::Teleport)) && coming;
        if steering {
            // STEER: la racchetta è ferma, si sterza come fa la CPU
            cmd.direction = cpu.direction;
            cmd.top_offset = cpu.top_offset;
        } else if teleport {
            // TELEPORT: si aspetta il salto
            self.hand.reset(f(pad.y));
        } else {
            match self.control {
                Control::Spinner => {
                    // la mano segue il movimento in corso, con una velocità massima
                    let vmax = self.p.hand_px * self.scale * TICK_HZ as f64 / self.hz;
                    self.hand.settle(tick);
                    // la racchetta è saltata (TELEPORT): la mano riparte da lì
                    if (f(pad.y) - self.last_pad).abs() > f(pad.height) / 2.0 {
                        self.hand.reset(f(pad.y));
                    }
                    let goal = self.hand.at(tick);
                    let y = (f(pad.y) + (goal - f(pad.y)).clamp(-vmax, vmax)).clamp(half, h - half);
                    cmd.top_offset = Some((h - half - y).floor() as i32);
                }
                Control::Joystick | Control::Keyboard => {
                    let keyboard = self.control == Control::Keyboard;
                    // dove crede che si fermi la racchetta se lascia ora
                    let speed = f(pad.speed);
                    let brake = f(m.params.pad_deceleration).max(1e-6);
                    let stop = f(pad.y) + speed * speed.abs() / (2.0 * brake) * self.p.momentum;
                    let diff = self.goal - stop;
                    let dead = f(pad.height) * if keyboard { 0.2 } else { 0.12 };
                    let dir = if diff > dead {
                        1
                    } else if diff < -dead {
                        -1
                    } else {
                        0
                    };
                    // rapido: col joystick per i recuperi lunghi, con la tastiera (doppio tocco) solo lunghissimi
                    let far = f(pad.height) * if keyboard { 2.5 } else { 1.2 };
                    let want = (dir, dir != 0 && diff.abs() > far);
                    let queued = self.pending.map_or(self.keys, |(_, k)| k);
                    if want != queued {
                        // la prima pressione dopo la reazione è già nel tempo di reazione
                        let lat = if tick == self.react_at {
                            0.0
                        } else {
                            (self.p.key_lat + self.noise.normal() * self.p.key_sd).max(0.01)
                        };
                        self.pending = Some((tick + self.ticks(lat) as u64, want));
                    }
                    if let Some((at, k)) = self.pending
                        && tick >= at
                    {
                        self.keys = k;
                        self.pending = None;
                    }
                    (cmd.direction, cmd.fast) = self.keys;
                }
            }
        }

        self.last_pad = f(pad.y);

        // scatto in avanti: si preme quando si stima che la palla entri nella zona
        let blaster = m.paddle_kind(self.side) == Some(PaddleKind::Blaster);
        if blaster && !m.params.blaster_dash {
            cmd.forward = cpu.forward; // il BLASTER spara con il tasto dello scatto
        } else if m.evo || next.is_some() {
            let b = &m.ball;
            if coming && self.dash_wanted && pad.at_home() && self.dash_at.is_none() && tick >= self.react_at {
                let half_w = f(pad.width) / 2.0;
                let mid = (f(pad.home_x) + f(pad.fwd_x)) / 2.0;
                let (edge, zone) = match self.side {
                    Side::Left => (f(b.left()), mid + half_w),
                    Side::Right => (f(b.right()), mid - half_w),
                };
                let t = (zone - edge) / f(b.dx);
                if t.is_finite() && t >= 0.0 && t <= self.ticks(0.35) {
                    let err =
                        t * self.p.weber * self.noise.normal() + self.ticks(self.p.dash_sigma) * self.noise.normal();
                    self.dash_at = Some(tick + (t + err).max(0.0) as u64);
                }
            }
            if let Some(at) = self.dash_at
                && tick >= at
            {
                // come la CPU, scatta solo se la racchetta è all'altezza della palla, ma lo giudica a occhio:
                // fuori altezza lo scatto la porterebbe oltre la palla
                let margin = f(pad.height) / 2.0 + f(b.radius) - (f(b.y) - f(pad.y)).abs();
                let judged = margin + self.noise.normal() * self.p.bounce_px * 0.25 * self.scale;
                if pad.at_home() && coming && judged > 0.0 {
                    cmd.forward = true;
                }
                self.dash_at = None;
                self.dash_wanted = false;
            }
            // con la palla che si allontana torna a casa, dopo essersene accorto
            if !pad.at_home() && !coming {
                let at = *self.home_at.get_or_insert(tick + self.ticks(self.p.rt_mu * 0.7) as u64);
                if tick >= at {
                    cmd.forward = true;
                    self.home_at = None;
                }
            } else {
                self.home_at = None;
            }
        }
        cmd
    }
}
