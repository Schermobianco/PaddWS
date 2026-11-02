//! Gamepad e stick arcade USB (le schede encoder dei cabinati si presentano come gamepad): uno per
//! giocatore, insieme ai tasti. Il primo collegato è del giocatore di sinistra, il secondo di quello
//! di destra; con un solo gamepad e un solo giocatore è di chi gioca, da qualunque lato
//! (`Pads::slot_of`).
//!
//! - Nativo (Windows, Linux, Raspberry Pi): gilrs. Con la mappatura di SDL (SDL_GameControllerDB,
//!   inclusa in gilrs) i pulsanti hanno il loro nome; quelli che restano senza nome (schede encoder
//!   sconosciute) valgono per numero (`raw_button`).
//! - Web: la Gamepad API del browser, letta a ogni frame da `rust/web/gamepad.js`.
//!
//! Comandi uguali per tutti, quelli della HOW TO PLAY: levetta o croce per muovere, A scatto (e
//! mosse speciali), B seleziona il bonus, C usa il bonus, Start, Select (gettone). La levetta
//! analogica diventa una direzione a 8 vie con una zona morta (`direction`); la croce e gli assi
//! digitali degli stick arcade danno già le 8 direzioni.

/// Comando di un gamepad (un bit di `Raw::buttons`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Control {
    Up,
    Down,
    Left,
    Right,
    A,
    B,
    C,
    Start,
    Select,
}

impl Control {
    pub const COUNT: usize = 9;
    pub const ALL: [Control; Self::COUNT] = [
        Control::Up,
        Control::Down,
        Control::Left,
        Control::Right,
        Control::A,
        Control::B,
        Control::C,
        Control::Start,
        Control::Select,
    ];

    pub const fn bit(self) -> u16 {
        1 << self as u16
    }
}

/// Bit delle quattro direzioni.
const DIRECTIONS: u16 = Control::Up.bit() | Control::Down.bit() | Control::Left.bit() | Control::Right.bit();

/// Zona morta della levetta analogica, in frazione della corsa.
pub const DEAD_ZONE: f32 = 0.35;
/// Seno di 22,5°: oltre questa componente (sulla levetta inclinata) l'asse conta. Così ogni
/// direzione delle 8 occupa 45° e le diagonali si riconoscono come sullo stick arcade.
const SECTOR: f32 = 0.382_683_43;

/// Ritardo e periodo della ripetizione delle direzioni tenute nei menu (s).
const REPEAT_DELAY: f64 = 0.4;
const REPEAT_EVERY: f64 = 0.12;

/// Un gamepad letto in questo frame: levetta (x a destra, y in giù, da -1 a 1) e pulsanti (bit di
/// `Control`, compresa la croce).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Raw {
    pub x: f32,
    pub y: f32,
    pub buttons: u16,
}

/// Direzione a 8 vie (dx, dy), con dy positivo in giù: la croce (o gli assi digitali) se è
/// premuta, altrimenti la levetta fuori dalla zona morta.
pub fn direction(raw: Raw) -> (i8, i8) {
    let on = |c: Control| i8::from(raw.buttons & c.bit() != 0);
    let digital = (
        on(Control::Right) - on(Control::Left),
        on(Control::Down) - on(Control::Up),
    );
    if digital != (0, 0) {
        return digital;
    }
    let m = raw.x.hypot(raw.y);
    if m.is_nan() || m < DEAD_ZONE {
        return (0, 0);
    }
    let axis = |v: f32| {
        if v / m > SECTOR {
            1
        } else if v / m < -SECTOR {
            -1
        } else {
            0
        }
    };
    (axis(raw.x), axis(raw.y))
}

/// Stato di un gamepad collegato.
#[derive(Clone, Copy, Debug, Default)]
struct Slot {
    id: u64,
    /// comandi tenuti (le direzioni a 8 vie di `direction`) e al frame prima
    held: u16,
    prev: u16,
    dir: (i8, i8),
    /// direzioni ripetute in questo frame e quando ripeterle di nuovo
    repeat: u16,
    next_repeat: f64,
}

impl Slot {
    fn update(&mut self, raw: Raw, now: f64) {
        self.dir = direction(raw);
        let (dx, dy) = self.dir;
        let mut dirs = 0;
        for (on, c) in [
            (dy < 0, Control::Up),
            (dy > 0, Control::Down),
            (dx < 0, Control::Left),
            (dx > 0, Control::Right),
        ] {
            if on {
                dirs |= c.bit();
            }
        }
        self.prev = self.held;
        self.held = (raw.buttons & !DIRECTIONS) | dirs;
        self.repeat = 0;
        if dirs & !self.prev != 0 {
            self.next_repeat = now + REPEAT_DELAY; // direzione nuova: la ripetizione aspetta
        } else if dirs != 0 && now >= self.next_repeat {
            self.repeat = dirs;
            self.next_repeat = now + REPEAT_EVERY;
        }
    }
}

/// I gamepad dei due giocatori.
pub struct Pads {
    backend: backend::Backend,
    slots: [Option<Slot>; 2],
}

impl Pads {
    pub fn open() -> Self {
        Self {
            backend: backend::Backend::open(),
            slots: [None; 2],
        }
    }

    /// Legge i gamepad (una volta per frame, `now` in secondi). Un gamepad nuovo prende il primo
    /// posto libero; se si scollega il primo, il secondo passa al suo posto.
    pub fn poll(&mut self, now: f64) {
        let raws = self.backend.read();
        for slot in &mut self.slots {
            if slot.is_some_and(|s| !raws.iter().any(|(id, _)| *id == s.id)) {
                *slot = None;
            }
        }
        if self.slots[0].is_none() {
            self.slots.swap(0, 1);
        }
        for (id, raw) in raws {
            let i = match self.slots.iter().position(|s| s.is_some_and(|s| s.id == id)) {
                Some(i) => i,
                None => match self.slots.iter().position(Option::is_none) {
                    Some(i) => {
                        self.slots[i] = Some(Slot { id, ..Slot::default() });
                        i
                    }
                    None => continue, // oltre due gamepad: non servono
                },
            };
            if let Some(slot) = &mut self.slots[i] {
                slot.update(raw, now);
            }
        }
    }

    pub fn connected(&self, slot: usize) -> bool {
        self.slots[slot].is_some()
    }

    /// Gamepad collegati (al massimo due).
    pub fn count(&self) -> usize {
        self.slots.iter().flatten().count()
    }

    /// Gamepad del lato `side` (0 sinistra, 1 destra): quello dello stesso numero, così ognuno
    /// resta al suo giocatore anche quando nella CHALLENGE lo sfidante vince e continua da destra.
    /// Se ne è collegato uno solo e gioca un solo giocatore, dal lato `solo`, è il suo.
    pub fn slot_of(&self, side: usize, solo: Option<usize>) -> Option<usize> {
        if self.count() == 1 && solo.is_some() {
            return (solo == Some(side)).then_some(0);
        }
        self.connected(side).then_some(side)
    }

    /// Lato comandato dal gamepad `slot` (l'inversa di `slot_of`).
    pub fn side_of(&self, slot: usize, solo: Option<usize>) -> usize {
        match solo {
            Some(s) if self.count() == 1 => s,
            _ => slot,
        }
    }

    fn bits(&self, slot: usize, f: impl Fn(&Slot) -> u16) -> u16 {
        self.slots[slot].as_ref().map_or(0, f)
    }

    /// Il comando è tenuto.
    pub fn held(&self, slot: usize, c: Control) -> bool {
        self.bits(slot, |s| s.held) & c.bit() != 0
    }

    /// Il comando è appena premuto.
    pub fn pressed(&self, slot: usize, c: Control) -> bool {
        self.bits(slot, |s| s.held & !s.prev) & c.bit() != 0
    }

    pub fn released(&self, slot: usize, c: Control) -> bool {
        self.bits(slot, |s| s.prev & !s.held) & c.bit() != 0
    }

    /// Per i menu: appena premuto, o una direzione tenuta che si ripete.
    pub fn nav_pressed(&self, slot: usize, c: Control) -> bool {
        self.pressed(slot, c) || self.bits(slot, |s| s.repeat) & c.bit() != 0
    }

    /// Direzione a 8 vie (dx, dy), dy positivo in giù.
    pub fn dir(&self, slot: usize) -> (i8, i8) {
        self.slots[slot].map_or((0, 0), |s| s.dir)
    }

    /// Un comando di un gamepad è appena premuto (si gioca con il gamepad).
    pub fn any_pressed(&self) -> bool {
        (0..2).any(|i| self.bits(i, |s| s.held & !s.prev) != 0)
    }
}

/// Pulsante senza nome numero `index` (da 0, l'ordine della scheda): i primi tre sono A, B e C,
/// il 9 e il 10 (come sulle schede encoder più diffuse) Select e Start. Nel browser fa lo stesso
/// `rust/web/gamepad.js`.
#[cfg_attr(target_arch = "wasm32", allow(dead_code))]
fn raw_button(index: u32) -> Option<Control> {
    match index {
        0 => Some(Control::A),
        1 => Some(Control::B),
        2 => Some(Control::C),
        8 => Some(Control::Select),
        9 => Some(Control::Start),
        _ => None,
    }
}

#[cfg(not(target_arch = "wasm32"))]
mod backend {
    use std::collections::HashMap;

    use gilrs::{Axis, Button, EventType, GamepadId, Gilrs};

    use super::{Control, Raw, raw_button};

    /// Pulsanti con nome: A in basso, B a destra, X a sinistra e Y in alto (disposizione Xbox);
    /// X e Y valgono entrambi C, così sugli stick arcade a sei pulsanti il terzo è C qualunque
    /// fila usi la mappatura.
    const BUTTONS: [(Button, Control); 11] = [
        (Button::South, Control::A),
        (Button::East, Control::B),
        (Button::West, Control::C),
        (Button::North, Control::C),
        (Button::Start, Control::Start),
        (Button::Select, Control::Select),
        (Button::DPadUp, Control::Up),
        (Button::DPadDown, Control::Down),
        (Button::DPadLeft, Control::Left),
        (Button::DPadRight, Control::Right),
        (Button::C, Control::C),
    ];

    pub struct Backend {
        gilrs: Option<Gilrs>,
        /// pulsanti senza nome tenuti, per gamepad
        unnamed: HashMap<GamepadId, u16>,
    }

    impl Backend {
        pub fn open() -> Self {
            let gilrs = match Gilrs::new() {
                Ok(g) => Some(g),
                Err(e) => {
                    eprintln!("Gamepads disabled: {e}");
                    None
                }
            };
            Self {
                gilrs,
                unnamed: HashMap::new(),
            }
        }

        /// Senza gamepad (per i test).
        #[cfg(test)]
        pub fn none() -> Self {
            Self {
                gilrs: None,
                unnamed: HashMap::new(),
            }
        }

        /// Gamepad collegati: (identificatore, stato).
        pub fn read(&mut self) -> Vec<(u64, Raw)> {
            let Some(g) = &mut self.gilrs else { return Vec::new() };
            while let Some(ev) = g.next_event() {
                match ev.event {
                    EventType::ButtonPressed(Button::Unknown, code)
                    | EventType::ButtonReleased(Button::Unknown, code) => {
                        if let Some(c) = unnamed_index(code.into_u32()).and_then(raw_button) {
                            let bits = self.unnamed.entry(ev.id).or_default();
                            if matches!(ev.event, EventType::ButtonPressed(..)) {
                                *bits |= c.bit();
                            } else {
                                *bits &= !c.bit();
                            }
                        }
                    }
                    EventType::Disconnected => {
                        self.unnamed.remove(&ev.id);
                    }
                    _ => {}
                }
            }
            g.gamepads()
                .filter(|(_, p)| p.is_connected())
                .map(|(id, p)| {
                    let mut buttons = self.unnamed.get(&id).copied().unwrap_or(0);
                    for (b, c) in BUTTONS {
                        if p.is_pressed(b) {
                            buttons |= c.bit();
                        }
                    }
                    // croce come assi (il "cappello" di alcune schede), con y in su positiva
                    let (hx, hy) = (p.value(Axis::DPadX), p.value(Axis::DPadY));
                    for (on, c) in [
                        (hx < -0.5, Control::Left),
                        (hx > 0.5, Control::Right),
                        (hy > 0.5, Control::Up),
                        (hy < -0.5, Control::Down),
                    ] {
                        if on {
                            buttons |= c.bit();
                        }
                    }
                    let raw = Raw {
                        x: p.value(Axis::LeftStickX),
                        y: -p.value(Axis::LeftStickY), // gilrs: y in su positiva
                        buttons,
                    };
                    (usize::from(id) as u64, raw)
                })
                .collect()
        }
    }

    /// Numero d'ordine di un pulsante senza nome dal codice nativo di gilrs (tipo << 16 | codice).
    /// Linux: i pulsanti dei joystick generici partono da BTN_TRIGGER (0x120; da BTN_SOUTH, 0x130,
    /// hanno già un nome). Windows: il codice è già l'indice del pulsante.
    fn unnamed_index(code: u32) -> Option<u32> {
        let low = code & 0xFFFF;
        if cfg!(target_os = "linux") {
            (0x120..0x130).contains(&low).then(|| low - 0x120)
        } else {
            Some(low)
        }
    }
}

#[cfg(target_arch = "wasm32")]
mod backend {
    use super::Raw;

    /// Gamepad letti al massimo e valori per gamepad: indice, x, y, pulsanti.
    const MAX: usize = 4;
    const FIELDS: usize = 4;

    unsafe extern "C" {
        /// Riempie `out` con i gamepad collegati (`rust/web/gamepad.js`): per ognuno indice, x,
        /// y (in giù positiva) e i bit di `Control`; restituisce quanti sono.
        fn paddws_gamepads(out: *mut f32, max: u32) -> u32;
    }

    pub struct Backend {
        buf: Vec<f32>,
    }

    impl Backend {
        pub fn open() -> Self {
            Self {
                buf: vec![0.0; MAX * FIELDS],
            }
        }

        pub fn read(&mut self) -> Vec<(u64, Raw)> {
            let n = unsafe { paddws_gamepads(self.buf.as_mut_ptr(), MAX as u32) } as usize;
            self.buf
                .as_chunks::<FIELDS>()
                .0
                .iter()
                .take(n.min(MAX))
                .map(|v| {
                    let raw = Raw {
                        x: v[1],
                        y: v[2],
                        buttons: v[3] as u16,
                    };
                    (v[0] as u64, raw)
                })
                .collect()
        }
    }

    /// Versione del plugin JavaScript che si aspetta il gioco (controllata da miniquad).
    #[unsafe(no_mangle)]
    pub extern "C" fn paddws_pad_crate_version() -> u32 {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stick(x: f32, y: f32) -> Raw {
        Raw { x, y, buttons: 0 }
    }

    #[test]
    fn the_analog_stick_gives_eight_directions_outside_the_dead_zone() {
        assert_eq!(direction(stick(0.2, -0.2)), (0, 0)); // nella zona morta
        assert_eq!(direction(stick(0.0, 1.0)), (0, 1));
        assert_eq!(direction(stick(0.7, 0.7)), (1, 1)); // diagonale
        assert_eq!(direction(stick(-0.6, -0.5)), (-1, -1));
        // a 15° dall'orizzontale resta avanti, senza giù
        let (s, c) = 15f32.to_radians().sin_cos();
        assert_eq!(direction(stick(c, s)), (1, 0));
        assert_eq!(direction(stick(f32::NAN, 0.0)), (0, 0));
    }

    #[test]
    fn the_digital_cross_wins_over_the_stick() {
        let raw = Raw {
            x: -1.0,
            y: 0.0,
            buttons: Control::Down.bit() | Control::Right.bit(),
        };
        assert_eq!(direction(raw), (1, 1));
        // su e giù insieme (croce rovinata) si annullano
        let both = Raw {
            buttons: Control::Up.bit() | Control::Down.bit(),
            ..Raw::default()
        };
        assert_eq!(direction(both), (0, 0));
    }

    #[test]
    fn held_directions_repeat_in_menus() {
        let mut s = Slot::default();
        let down = Raw {
            buttons: Control::Down.bit() | Control::A.bit(),
            ..Raw::default()
        };
        s.update(down, 0.0);
        assert_eq!(s.held & !s.prev, Control::Down.bit() | Control::A.bit());
        s.update(down, 0.2);
        assert_eq!((s.held & !s.prev, s.repeat), (0, 0));
        s.update(down, 0.41);
        assert_eq!(s.repeat, Control::Down.bit()); // solo le direzioni si ripetono
        s.update(down, 0.45);
        assert_eq!(s.repeat, 0);
        s.update(down, 0.54);
        assert_eq!(s.repeat, Control::Down.bit());
    }

    #[test]
    fn each_pad_keeps_its_side_and_a_lone_pad_follows_the_lone_player() {
        let mut pads = Pads {
            backend: backend::Backend::none(),
            slots: [Some(Slot::default()), None],
        };
        // un gamepad: con un giocatore solo è suo, da qualunque lato
        assert_eq!(pads.slot_of(1, Some(1)), Some(0));
        assert_eq!(pads.slot_of(0, Some(1)), None);
        assert_eq!(pads.side_of(0, Some(1)), 1);
        assert_eq!(pads.slot_of(0, None), Some(0));
        assert_eq!(pads.slot_of(1, None), None);
        // due gamepad: il primo a sinistra, il secondo a destra
        pads.slots[1] = Some(Slot {
            id: 1,
            ..Slot::default()
        });
        for solo in [None, Some(0), Some(1)] {
            assert_eq!([0, 1].map(|side| pads.slot_of(side, solo)), [Some(0), Some(1)]);
            assert_eq!([0, 1].map(|slot| pads.side_of(slot, solo)), [0, 1]);
        }
    }

    #[test]
    fn unnamed_buttons_are_a_b_c_then_select_and_start() {
        assert_eq!(
            [0, 1, 2, 3, 8, 9].map(raw_button),
            [
                Some(Control::A),
                Some(Control::B),
                Some(Control::C),
                None,
                Some(Control::Select),
                Some(Control::Start)
            ]
        );
    }
}
