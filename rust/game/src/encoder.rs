//! Encoder rotativi con pulsante del cabinato Raspberry Pi, come nella versione Python
//! (`python/paddws/hardware.py`), più i pulsanti SELEZIONA e USA del bonus di NEXT.
//!
//! Encoder meccanici con scatti (KY-040, fino a 30 impulsi per giro): il contatore si muove a ogni
//! scatto, come in Python. Encoder ottici senza scatti (360 o 600 impulsi per giro): conta ogni
//! transizione della quadratura, movimento continuo; di solito senza pulsante (lo scatto in avanti
//! va su un pulsante a parte collegato al pin dello SW) e senza antirimbalzo.
//!
//! I GPIO si leggono dal dispositivo a caratteri del kernel (`/dev/gpiochip*`, crate gpiocdev):
//! funziona su Pi 4 e Pi 5 senza il demone pigpio, che sul Pi 5 non c'è. Le linee si cercano per
//! nome (`GPIO5`...), con pull-up interno e antirimbalzo del kernel; un thread inoltra i fronti al
//! ciclo di gioco, che li decodifica in `poll`. La decodifica (`Knob`) non dipende dai GPIO.
//!
//! Su PC e nel browser il mouse può fare da spinner del giocatore 1 (`Encoders::mouse`): il suo
//! movimento verticale gira la manopola di sinistra come un encoder ottico e i tre pulsanti sono
//! il click, SELEZIONA e USA. Il mouse lo legge `mouse.rs`; qui arriva solo `MouseFrame`.

use crate::config;

/// Pressione oltre la quale il click diventa "lungo" (torna al menu), come in Python.
const LONG_PRESS: f64 = 1.5;
/// "Tacche" per giro: un passo del menu e del contatore. Il KY-040 ha 20 scatti per giro; gli
/// encoder ottici dividono il giro nello stesso numero di tacche, ognuna di più transizioni.
pub const NOTCHES_PER_TURN: i32 = 20;
/// Oltre questo numero di impulsi per giro l'encoder non ha scatti: si conta ogni transizione.
const MAX_DETENT_PPR: u32 = 30;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    /// nuovo valore del contatore
    Rotate(i32),
    /// pulsante dell'encoder: click (al rilascio) e pressione lunga
    Click,
    LongClick,
    /// pulsanti di NEXT (alla pressione)
    Select,
    Activate,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Event {
    /// 0 sinistra, 1 destra
    pub player: usize,
    pub action: Action,
}

/// Un encoder: decodifica della quadratura, contatore limitato e pulsante.
#[derive(Clone, Debug)]
pub struct Knob {
    /// livelli (clk << 1 | dt) dell'ultimo fronte
    state: u8,
    /// encoder con scatti: il contatore si muove solo a scatto completato (4 transizioni)
    detents: bool,
    /// transizioni di quadratura per tacca (4 nel KY-040, 120 in un 600 impulsi per giro)
    notch: i32,
    /// transizioni dall'ultimo scatto (con scatti) o frazione di unità in 1/notch (senza)
    steps: i32,
    pub counter: i32,
    min: i32,
    max: i32,
    scale: i32,
    /// pulsante premuto dal tempo indicato, e pressione lunga già segnalata
    pressed: Option<f64>,
    long_sent: bool,
}

impl Knob {
    /// Encoder da `ppr` impulsi per giro (20 = KY-040).
    pub fn new(ppr: u32) -> Self {
        let ppr = ppr.max(1);
        Self {
            state: 0b11,
            detents: ppr <= MAX_DETENT_PPR,
            notch: (4 * ppr as i32 / NOTCHES_PER_TURN).max(1),
            steps: 0,
            counter: 0,
            min: 0,
            max: 100,
            scale: 1,
            pressed: None,
            long_sent: false,
        }
    }

    /// Manopola senza scatti mossa da un movimento continuo (il mouse): `notch` passi per tacca.
    pub fn continuous(notch: i32) -> Self {
        Self {
            detents: false,
            notch: notch.max(1),
            ..Self::new(1)
        }
    }

    /// Livelli attuali di clk e dt (all'avvio): da qui si contano le transizioni.
    pub fn sync(&mut self, clk: bool, dt: bool) {
        self.state = (clk as u8) << 1 | dt as u8;
    }

    /// Intervallo del contatore e passo per tacca, con il contatore portato a `start`.
    pub fn configure(&mut self, min: i32, max: i32, scale: i32, start: i32) {
        (self.min, self.max, self.scale) = (min, max.max(min), scale.max(1));
        self.counter = start.clamp(self.min, self.max);
        self.steps = 0;
    }

    /// Nuovi livelli di clk e dt; il nuovo valore se il contatore è cambiato. Come in Python il
    /// contatore sale quando dt scende prima di clk (11 -> 10 -> 00 -> 01 -> 11).
    pub fn rotate(&mut self, clk: bool, dt: bool) -> Option<i32> {
        let next = (clk as u8) << 1 | dt as u8;
        // passo in avanti o indietro; due livelli cambiati insieme (rimbalzo) non contano
        let delta: i8 = match (self.state, next) {
            (0b11, 0b10) | (0b10, 0b00) | (0b00, 0b01) | (0b01, 0b11) => 1,
            (0b11, 0b01) | (0b01, 0b00) | (0b00, 0b10) | (0b10, 0b11) => -1,
            _ => 0,
        };
        self.state = next;
        self.advance(delta as i32)
    }

    /// `delta` transizioni in avanti (positive) o indietro; il nuovo valore se il contatore è
    /// cambiato.
    fn advance(&mut self, delta: i32) -> Option<i32> {
        let moved = if self.detents {
            // a scatti: uno scatto completo sono 4 transizioni e vale `scale`
            self.steps += delta;
            if self.steps.abs() < 4 {
                return None;
            }
            let detent = self.steps.signum();
            self.steps = 0;
            detent * self.scale
        } else {
            // continuo: ogni transizione vale scale/notch, i resti si accumulano
            self.steps += delta * self.scale;
            let units = self.steps / self.notch;
            self.steps -= units * self.notch;
            units
        };
        let value = (self.counter + moved).clamp(self.min, self.max);
        // al fine corsa non si accumula verso l'esterno: girando al contrario si riparte subito
        if (value == self.max && self.steps > 0) || (value == self.min && self.steps < 0) {
            self.steps = 0;
        }
        (value != self.counter).then(|| {
            self.counter = value;
            value
        })
    }

    /// Pulsante premuto o rilasciato al tempo `now` (secondi): il click arriva al rilascio,
    /// se non è già scattata la pressione lunga.
    pub fn button(&mut self, down: bool, now: f64) -> Option<Action> {
        match (down, self.pressed) {
            (true, None) => {
                self.pressed = Some(now);
                self.long_sent = false;
                None
            }
            (false, Some(_)) => {
                self.pressed = None;
                (!self.long_sent).then_some(Action::Click)
            }
            _ => None,
        }
    }

    /// Pressione lunga: da controllare a ogni frame mentre il pulsante è giù.
    pub fn hold(&mut self, now: f64) -> Option<Action> {
        let t = self.pressed?;
        (!self.long_sent && now - t >= LONG_PRESS).then(|| {
            self.long_sent = true;
            Action::LongClick
        })
    }
}

/// Pixel per tacca perché `turns` giri di manopola portino la racchetta da un bordo all'altro.
fn travel_scale(travel: i32, turns: f64) -> i32 {
    ((travel as f64 / (turns.max(0.05) * NOTCHES_PER_TURN as f64)).round() as i32).max(1)
}

/// Ruolo di una linea GPIO.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Role {
    Clock,
    Data,
    Switch,
    Select,
    Activate,
}

/// Linee del cabinato per giocatore, dalla configurazione: (pin, giocatore, ruolo).
fn pins(cfg: &config::Encoder) -> Vec<(u32, usize, Role)> {
    let all = [
        (cfg.e1_clock_pin, 0, Role::Clock),
        (cfg.e1_data_pin, 0, Role::Data),
        (cfg.e1_switch_pin, 0, Role::Switch),
        (cfg.e1_select_pin, 0, Role::Select),
        (cfg.e1_activate_pin, 0, Role::Activate),
        (cfg.e2_clock_pin, 1, Role::Clock),
        (cfg.e2_data_pin, 1, Role::Data),
        (cfg.e2_switch_pin, 1, Role::Switch),
        (cfg.e2_select_pin, 1, Role::Select),
        (cfg.e2_activate_pin, 1, Role::Activate),
    ];
    all.into_iter()
        .filter(|(pin, ..)| *pin >= 0)
        .map(|(pin, player, role)| (pin as u32, player, role))
        .collect()
}

/// Il mouse usato come spinner in questo frame: movimento verticale (pixel, positivo in giù) e
/// pulsanti appena premuti.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct MouseFrame {
    pub dy: f32,
    /// sinistro: click (scatto in avanti), destro: SELEZIONA, centrale (rotella): USA
    pub click: bool,
    pub select: bool,
    pub activate: bool,
}

/// I due encoder con i loro pulsanti, oppure il mouse come manopola del giocatore 1.
pub struct Encoders {
    knobs: [Knob; 2],
    /// giri di manopola per attraversare il campo
    turns_per_travel: f64,
    /// livello attuale di ogni linea (true = alto), indice come in `lines`
    levels: Vec<bool>,
    lines: Vec<(u32, usize, Role)>,
    /// None con il mouse
    gpio: Option<gpio::Lines>,
    /// mouse: frazione di pixel non ancora contata
    mouse_rest: Option<f32>,
}

impl Encoders {
    /// Il mouse come spinner del giocatore 1: `travel_pixels` pixel di movimento verticale per
    /// portare la racchetta da un bordo all'altro (un "giro" della manopola).
    pub fn mouse(travel_pixels: f64) -> Self {
        let notch = (travel_pixels / NOTCHES_PER_TURN as f64).round() as i32;
        Self {
            knobs: [Knob::continuous(notch), Knob::new(NOTCHES_PER_TURN as u32)],
            turns_per_travel: 1.0,
            levels: Vec::new(),
            lines: Vec::new(),
            gpio: None,
            mouse_rest: Some(0.0),
        }
    }

    /// È il mouse e non gli encoder del cabinato.
    pub fn is_mouse(&self) -> bool {
        self.mouse_rest.is_some()
    }

    /// Il giocatore ha una manopola: con il mouse solo il primo.
    pub fn has_knob(&self, player: usize) -> bool {
        player == 0 || !self.is_mouse()
    }

    /// Apre gli encoder se abilitati in configurazione; None se disabilitati o non disponibili.
    pub fn open(cfg: &config::Encoder) -> Option<Self> {
        if !cfg.enabled {
            return None;
        }
        let lines = pins(cfg);
        let offsets: Vec<u32> = lines.iter().map(|l| l.0).collect();
        match gpio::Lines::open(&offsets, cfg.debounce_us) {
            Ok((gpio, levels)) => {
                println!(
                    "Encoders on GPIO {offsets:?}, {} pulses per revolution",
                    cfg.pulses_per_revolution
                );
                let mut enc = Self {
                    knobs: [
                        Knob::new(cfg.pulses_per_revolution),
                        Knob::new(cfg.pulses_per_revolution),
                    ],
                    turns_per_travel: cfg.turns_per_travel,
                    levels,
                    lines,
                    gpio: Some(gpio),
                    mouse_rest: None,
                };
                // si parte dai livelli reali: un encoder ottico può fermarsi in qualunque stato
                for player in 0..2 {
                    let (clk, dt) = (enc.level(player, Role::Clock), enc.level(player, Role::Data));
                    enc.knobs[player].sync(clk, dt);
                }
                Some(enc)
            }
            Err(err) => {
                eprintln!("Rotary encoders disabled: {err}");
                None
            }
        }
    }

    /// Imposta l'intervallo dei contatori di entrambi gli encoder e li porta a `start`.
    pub fn configure(&mut self, min: i32, max: i32, scale: i32, start: i32) {
        for knob in &mut self.knobs {
            knob.configure(min, max, scale, start);
        }
    }

    /// Come `configure`, per la sola manopola di `player`.
    pub fn configure_one(&mut self, player: usize, min: i32, max: i32, scale: i32, start: i32) {
        self.knobs[player].configure(min, max, scale, start);
    }

    /// Pixel per tacca della racchetta, con una corsa `travel` (pixel) per `turns_per_travel` giri.
    pub fn travel_scale(&self, travel: i32) -> i32 {
        travel_scale(travel, self.turns_per_travel)
    }

    /// Livello della linea con quel ruolo (alto se la linea non c'è).
    fn level(&self, player: usize, role: Role) -> bool {
        self.lines
            .iter()
            .position(|l| l.1 == player && l.2 == role)
            .is_none_or(|j| self.levels[j])
    }

    /// Valore del contatore dell'encoder di `player`.
    pub fn value(&self, player: usize) -> i32 {
        self.knobs[player].counter
    }

    /// Eventi dall'ultimo frame; `now` in secondi (per la pressione lunga), `mouse` il mouse del
    /// frame (conta solo se fa da spinner).
    pub fn poll(&mut self, now: f64, mouse: MouseFrame) -> Vec<Event> {
        let mut events = Vec::new();
        if let Some(rest) = &mut self.mouse_rest {
            // pixel interi alla manopola, i resti al frame dopo; il click arriva alla pressione
            let total = *rest + mouse.dy;
            let whole = total.trunc();
            *rest = total - whole;
            let actions = [
                self.knobs[0].advance(whole as i32).map(Action::Rotate),
                mouse.click.then_some(Action::Click),
                mouse.select.then_some(Action::Select),
                mouse.activate.then_some(Action::Activate),
            ];
            events.extend(actions.into_iter().flatten().map(|action| Event { player: 0, action }));
            return events;
        }
        let edges = self.gpio.as_mut().map(gpio::Lines::edges).unwrap_or_default();
        for (pin, high) in edges {
            let Some(i) = self.lines.iter().position(|l| l.0 == pin) else {
                continue;
            };
            self.levels[i] = high;
            let (_, player, role) = self.lines[i];
            let action = match role {
                Role::Clock | Role::Data => {
                    let (clk, dt) = (self.level(player, Role::Clock), self.level(player, Role::Data));
                    self.knobs[player].rotate(clk, dt).map(Action::Rotate)
                }
                // pulsanti verso massa: premuto = livello basso
                Role::Switch => self.knobs[player].button(!high, now),
                Role::Select => (!high).then_some(Action::Select),
                Role::Activate => (!high).then_some(Action::Activate),
            };
            events.extend(action.map(|action| Event { player, action }));
        }
        for (player, knob) in self.knobs.iter_mut().enumerate() {
            events.extend(knob.hold(now).map(|action| Event { player, action }));
        }
        events
    }
}

#[cfg(target_os = "linux")]
mod gpio {
    use std::sync::mpsc::{Receiver, channel};
    use std::time::Duration;

    use gpiocdev::Request;
    use gpiocdev::line::{Bias, EdgeDetection, EdgeKind, Value};

    /// Fronti delle linee richieste, letti da un thread.
    pub struct Lines {
        rx: Receiver<(u32, bool)>,
    }

    impl Lines {
        /// Richiede le linee `GPIO<n>` come ingressi con pull-up, antirimbalzo (0 = nessuno) e fronti;
        /// restituisce anche il livello iniziale di ognuna.
        pub fn open(pins: &[u32], debounce_us: u32) -> Result<(Self, Vec<bool>), String> {
            let mut builder = Request::builder();
            // un 600 impulsi per giro girato forte manda migliaia di fronti al secondo
            builder.with_consumer("paddws").with_kernel_event_buffer_size(1024);
            // (pin BCM, offset sul chip): sul Pi coincidono, ma l'offset si legge dal nome
            let mut offsets = Vec::new();
            for &pin in pins {
                let found =
                    gpiocdev::find_named_line(&format!("GPIO{pin}")).ok_or_else(|| format!("GPIO{pin} non trovato"))?;
                offsets.push((pin, found.info.offset));
                builder
                    .with_found_line(&found)
                    .as_input()
                    .with_bias(Bias::PullUp)
                    .with_edge_detection(EdgeDetection::BothEdges);
                if debounce_us > 0 {
                    builder.with_debounce_period(Duration::from_micros(debounce_us as u64));
                }
            }
            let req = builder.request().map_err(|e| e.to_string())?;
            let levels = offsets
                .iter()
                .map(|&(_, o)| req.value(o).map(|v| v == Value::Active).map_err(|e| e.to_string()))
                .collect::<Result<Vec<_>, _>>()?;
            let (tx, rx) = channel();
            std::thread::spawn(move || {
                for edge in req.edge_events() {
                    let Ok(edge) = edge else { break };
                    let Some(&(pin, _)) = offsets.iter().find(|&&(_, o)| o == edge.offset) else {
                        continue;
                    };
                    if tx.send((pin, edge.kind == EdgeKind::Rising)).is_err() {
                        break; // il gioco è finito
                    }
                }
            });
            Ok((Self { rx }, levels))
        }

        /// Fronti arrivati dall'ultima chiamata: (pin BCM, livello alto).
        pub fn edges(&mut self) -> Vec<(u32, bool)> {
            self.rx.try_iter().collect()
        }
    }
}

#[cfg(not(target_os = "linux"))]
mod gpio {
    /// Fuori da Linux non ci sono GPIO.
    pub struct Lines;

    impl Lines {
        pub fn open(_pins: &[u32], _debounce_us: u32) -> Result<(Self, Vec<bool>), String> {
            Err("GPIO disponibili solo su Linux (Raspberry Pi)".into())
        }

        pub fn edges(&mut self) -> Vec<(u32, bool)> {
            Vec::new()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Uno scatto in avanti (dt scende per primo) o indietro, a partire dal riposo (11).
    fn detent(k: &mut Knob, forward: bool) -> Option<i32> {
        let seq: [(bool, bool); 4] = if forward {
            [(true, false), (false, false), (false, true), (true, true)]
        } else {
            [(false, true), (false, false), (true, false), (true, true)]
        };
        seq.into_iter().map(|(c, d)| k.rotate(c, d)).last().flatten()
    }

    #[test]
    fn a_detent_moves_the_counter_by_one_scale_within_the_limits() {
        let mut k = Knob::new(20);
        k.configure(0, 400, 20, 200);
        assert_eq!(detent(&mut k, true), Some(220));
        assert_eq!(detent(&mut k, false), Some(200));
        for _ in 0..30 {
            detent(&mut k, true);
        }
        assert_eq!(k.counter, 400);
        assert_eq!(detent(&mut k, true), None); // già al massimo
    }

    #[test]
    fn bounces_do_not_count() {
        let mut k = Knob::new(20);
        k.configure(0, 10, 1, 5);
        // mezzo scatto avanti e ritorno: nessun movimento
        for (c, d) in [(true, false), (false, false), (true, false), (true, true)] {
            assert_eq!(k.rotate(c, d), None);
        }
        // due livelli che cambiano insieme: ignorati
        assert_eq!(k.rotate(false, false), None);
        assert_eq!(k.counter, 5);
    }

    #[test]
    fn click_on_release_and_long_press_after_one_and_a_half_seconds() {
        let mut k = Knob::new(20);
        assert_eq!(k.button(true, 10.0), None);
        assert_eq!(k.hold(10.5), None);
        assert_eq!(k.button(false, 10.6), Some(Action::Click));
        k.button(true, 20.0);
        assert_eq!(k.hold(21.6), Some(Action::LongClick));
        assert_eq!(k.hold(22.0), None);
        assert_eq!(k.button(false, 22.1), None); // niente click dopo la pressione lunga
    }

    /// `n` transizioni in avanti (11 -> 10 -> 00 -> 01 -> 11) o indietro dallo stato dell'encoder.
    fn turn(k: &mut Knob, forward: bool, n: usize) -> Option<i32> {
        let mut last = None;
        for _ in 0..n {
            let next = match (k.state, forward) {
                (0b11, true) | (0b00, false) => 0b10,
                (0b10, true) | (0b01, false) => 0b00,
                (0b00, true) | (0b11, false) => 0b01,
                _ => 0b11,
            };
            last = k.rotate(next & 0b10 != 0, next & 0b01 != 0).or(last);
        }
        last
    }

    #[test]
    fn optical_encoders_count_every_transition() {
        let mut k = Knob::new(600);
        k.configure(0, 400, 20, 200);
        // una tacca (1/20 di giro) sono 120 transizioni: 20 pixel, cioè 1 pixel ogni 6
        assert_eq!(turn(&mut k, true, 6), Some(201));
        assert_eq!(turn(&mut k, true, 114), Some(220));
        assert_eq!(turn(&mut k, false, 120), Some(200));
        // mezzo giro (1200 transizioni) porta da metà al fondo, oltre resta al fine corsa
        turn(&mut k, true, 1200);
        assert_eq!(k.counter, 400);
        turn(&mut k, true, 400);
        assert_eq!(k.counter, 400);
        assert_eq!(turn(&mut k, false, 6), Some(399)); // e si torna indietro subito
    }

    #[test]
    fn the_travel_scale_follows_turns_per_travel() {
        // un giro intero per 400 pixel: 20 pixel per tacca, come il KY-040; mezzo giro: 40
        assert_eq!(travel_scale(400, 1.0), 20);
        assert_eq!(travel_scale(400, 0.5), 40);
        let mut k = Knob::new(360);
        k.configure(0, 400, travel_scale(400, 0.5), 0);
        turn(&mut k, true, 360 * 4 / 2); // mezzo giro di un 360 impulsi per giro
        assert_eq!(k.counter, 400);
    }

    #[test]
    fn the_mouse_turns_the_left_knob_and_its_buttons_are_click_select_and_use() {
        // 1000 pixel di mouse per tutta la corsa di 400: 50 pixel per tacca da 20
        let mut enc = Encoders::mouse(1000.0);
        let scale = enc.travel_scale(400);
        enc.configure(0, 400, scale, 200);
        let moved = |dy| MouseFrame {
            dy,
            ..Default::default()
        };
        let rotate = |v| vec![Event {
            player: 0,
            action: Action::Rotate(v),
        }];
        assert_eq!(enc.poll(0.0, moved(25.0)), rotate(210));
        // i pezzi di pixel e di tacca si accumulano
        assert!(enc.poll(0.0, moved(1.2)).is_empty());
        assert!(enc.poll(0.0, moved(1.3)).is_empty());
        assert_eq!(enc.poll(0.0, moved(0.5)), rotate(211));
        // al fine corsa si ferma e tornando indietro riparte subito
        assert_eq!(enc.poll(0.0, moved(5000.0)), rotate(400));
        assert_eq!(enc.poll(0.0, moved(-50.0)), rotate(380));
        let pressed = MouseFrame {
            click: true,
            activate: true,
            ..Default::default()
        };
        let actions: Vec<Action> = enc.poll(0.0, pressed).into_iter().map(|e| e.action).collect();
        assert_eq!(actions, [Action::Click, Action::Activate]);
        assert!(enc.is_mouse() && enc.has_knob(0) && !enc.has_knob(1));
    }
}
