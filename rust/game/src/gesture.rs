//! Gesti delle mosse speciali di NEXT, riconosciuti nel livello dei comandi (il core riceve solo
//! `PlayerInput::special` per un tick e decide se la mossa parte).
//!
//! Come nei picchiaduro, una mossa sono due direzioni in sequenza seguite dallo scatto in avanti:
//! giù-su + scatto è STRAIGHT SHOT, su-giù + scatto è RISING STRIKE. Le due direzioni devono
//! arrivare entro `STEP_SECONDS` l'una dall'altra e lo scatto entro `DASH_SECONDS` dall'ultima.
//!
//! Le direzioni arrivano in due modi:
//! - dai tasti (`Gesture::press`): ogni pressione di su o giù è una direzione;
//! - da un movimento continuo (`Gesture::track`: manopola del cabinato, dito sul touch, mouse nel
//!   browser): una direzione è un tratto rapido in un verso, lungo almeno `MIN_TRAVEL`
//!   dell'altezza del campo e fatto entro `STEP_SECONDS`. "Giro rapido in un verso e ritorno,
//!   poi click": il ritorno è il secondo tratto. Un ritorno indietro più corto di `DEADBAND` non
//!   cambia il verso (tremolii del dito, rimbalzi dell'encoder).
//!
//! Non dipende da macroquad: i tempi sono in secondi e le posizioni in pixel dal bordo alto,
//! così si prova con i test qui sotto.

use paddws_core::Special;

/// Tempo massimo tra le due direzioni del gesto (s).
pub const STEP_SECONDS: f64 = 0.3;
/// Tempo massimo tra l'ultima direzione e lo scatto (s).
pub const DASH_SECONDS: f64 = 0.25;
/// Movimento continuo: corsa minima di un tratto, in frazione dell'altezza del campo.
pub const MIN_TRAVEL: f32 = 1.0 / 8.0;
/// Movimento continuo: ritorno che cambia il verso, in frazione dell'altezza del campo.
pub const DEADBAND: f32 = 1.0 / 48.0;
/// Movimento continuo: fermo oltre il quale il tratto riparte da dove ci si è fermati (s).
const STILL_SECONDS: f64 = 0.08;

/// Gesti del joystick (gamepad e stick arcade), come `move_gesture` del core MiSTer: mezzelune dei
/// picchiaduro con avanti = verso l'avversario.
/// - giù, giù-avanti, avanti + scatto (A) = STRAIGHT SHOT;
/// - avanti, giù, giù-avanti + scatto = RISING STRIKE (ha la precedenza).
///
/// Per ognuna delle tre direzioni si tiene l'ultimo istante in cui era tenuta: devono essere in
/// ordine, a non più di `STEP_SECONDS` l'una dall'altra, e lo scatto deve arrivare entro
/// `DASH_SECONDS` dall'ultima. Finita in avanti la mezzaluna vale come STRAIGHT SHOT anche se
/// prima c'era un avanti.
#[derive(Clone, Copy, Debug, Default)]
pub struct Stick {
    down: Option<f64>,
    down_forward: Option<f64>,
    forward: Option<f64>,
}

impl Stick {
    /// Direzione del joystick al tempo `t` (a ogni frame): giù, su e avanti (verso l'avversario).
    pub fn track(&mut self, down: bool, up: bool, forward: bool, t: f64) {
        if down && !forward {
            self.down = Some(t);
        }
        if down && forward {
            self.down_forward = Some(t);
        }
        if forward && !down && !up {
            self.forward = Some(t);
        }
    }

    /// Scatto in avanti al tempo `t`: la mossa se chiude una mezzaluna, che si consuma.
    pub fn dash(&mut self, t: f64) -> Option<Special> {
        let age = |at: Option<f64>| at.map_or(f64::INFINITY, |at| t - at);
        let (d, df, f) = (age(self.down), age(self.down_forward), age(self.forward));
        // `older` prima di `newer`, a non più di STEP_SECONDS
        let then = |older: f64, newer: f64| older >= newer && older - newer <= STEP_SECONDS;
        let special = if df <= DASH_SECONDS && then(d, df) && then(f, d) {
            Special::Rise
        } else if f <= DASH_SECONDS && then(df, f) && then(d, df) {
            Special::Straight
        } else {
            return None;
        };
        *self = Self::default();
        Some(special)
    }
}

/// Verso sullo schermo.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dir {
    Up,
    Down,
}

/// Una direzione del gesto: verso, inizio e fine (per i tasti coincidono).
#[derive(Clone, Copy, Debug, PartialEq)]
struct Stroke {
    dir: Dir,
    start: f64,
    end: f64,
}

/// Movimento continuo: ultimo campione e tratto in corso.
#[derive(Clone, Copy, Debug)]
struct Motion {
    /// ultima posizione, quando è cambiata l'ultima volta e quando è arrivato l'ultimo campione
    y: f32,
    moved: f64,
    seen: f64,
    /// inizio del tratto, punto più lontano raggiunto e verso (None finché non supera `deadband`)
    start_y: f32,
    start_t: f64,
    peak_y: f32,
    peak_t: f64,
    dir: Option<Dir>,
}

impl Motion {
    fn at(y: f32, t: f64) -> Self {
        Self {
            y,
            moved: t,
            seen: t,
            start_y: y,
            start_t: t,
            peak_y: y,
            peak_t: t,
            dir: None,
        }
    }

    /// Il tratto in corso, se è una direzione valida (abbastanza lungo e rapido).
    fn stroke(&self, min_travel: f32) -> Option<Stroke> {
        let dir = self.dir?;
        let rapid = (self.peak_y - self.start_y).abs() >= min_travel && self.peak_t - self.start_t <= STEP_SECONDS;
        rapid.then_some(Stroke {
            dir,
            start: self.start_t,
            end: self.peak_t,
        })
    }
}

/// Riconoscitore dei gesti di un giocatore.
#[derive(Clone, Debug, Default)]
pub struct Gesture {
    /// ultime due direzioni concluse, la più recente per ultima
    strokes: [Option<Stroke>; 2],
    motion: Option<Motion>,
    /// soglie del movimento continuo, in pixel
    min_travel: f32,
    deadband: f32,
}

impl Gesture {
    /// Riconoscitore per un campo alto `height` pixel (le soglie del movimento continuo).
    pub fn new(height: f32) -> Self {
        Self {
            min_travel: height * MIN_TRAVEL,
            deadband: (height * DEADBAND).max(1.0),
            ..Self::default()
        }
    }

    fn push(&mut self, stroke: Stroke) {
        self.strokes = [self.strokes[1], Some(stroke)];
    }

    /// Tasto di una direzione premuto al tempo `t`.
    pub fn press(&mut self, dir: Dir, t: f64) {
        self.push(Stroke { dir, start: t, end: t });
    }

    /// Posizione continua (`y` in pixel dal bordo alto) al tempo `t`.
    pub fn track(&mut self, y: f32, t: f64) {
        let Some(m) = &mut self.motion else {
            self.motion = Some(Motion::at(y, t));
            return;
        };
        if y == m.y {
            m.seen = t;
            return;
        }
        if m.seen - m.moved > STILL_SECONDS {
            // era fermo: il tratto riparte da qui (un movimento lento a scatti non è un gesto)
            *m = Motion::at(m.y, m.seen);
        }
        m.y = y;
        m.moved = t;
        m.seen = t;
        let closed = match m.dir {
            None => {
                if (y - m.start_y).abs() >= self.deadband {
                    m.dir = Some(if y > m.start_y { Dir::Down } else { Dir::Up });
                    (m.peak_y, m.peak_t) = (y, t);
                }
                None
            }
            Some(dir) => {
                let further = match dir {
                    Dir::Down => y > m.peak_y,
                    Dir::Up => y < m.peak_y,
                };
                if further {
                    (m.peak_y, m.peak_t) = (y, t);
                    None
                } else if (y - m.peak_y).abs() > self.deadband {
                    // cambio di verso: il tratto finisce nel punto più lontano e il nuovo parte da lì
                    let done = m.stroke(self.min_travel);
                    (m.start_y, m.start_t) = (m.peak_y, m.peak_t);
                    (m.peak_y, m.peak_t) = (y, t);
                    m.dir = Some(if dir == Dir::Down { Dir::Up } else { Dir::Down });
                    done
                } else {
                    None
                }
            }
        };
        if let Some(stroke) = closed {
            self.push(stroke);
        }
    }

    /// Il movimento continuo si interrompe (dito sollevato): il prossimo campione riparte da zero.
    pub fn lift(&mut self) {
        if let Some(stroke) = self.motion.and_then(|m| m.stroke(self.min_travel)) {
            self.push(stroke);
        }
        self.motion = None;
    }

    /// Scatto in avanti al tempo `t`: la mossa se completa un gesto. Il gesto riconosciuto si
    /// consuma (lo scatto dopo è di nuovo normale).
    pub fn dash(&mut self, t: f64) -> Option<Special> {
        // il tratto in corso conta già: si torna indietro e si clicca senza fermarsi
        let current = self.motion.and_then(|m| m.stroke(self.min_travel));
        let mut all = self.strokes.iter().flatten().copied().chain(current);
        let (mut a, mut b) = (None, None);
        for s in all.by_ref() {
            (a, b) = (b, Some(s));
        }
        let (a, b) = (a?, b?);
        let timely = b.end - a.end <= STEP_SECONDS && b.end >= a.end && t >= b.end && t - b.end <= DASH_SECONDS;
        let special = match (a.dir, b.dir) {
            (Dir::Down, Dir::Up) => Special::Straight,
            (Dir::Up, Dir::Down) => Special::Rise,
            _ => return None,
        };
        if !timely {
            return None;
        }
        self.strokes = [None; 2];
        if let Some(m) = &mut self.motion {
            *m = Motion::at(m.y, t);
        }
        Some(special)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Campo alto 480 pixel: tratti di almeno 60 pixel, ritorno oltre 10.
    const H: f32 = 480.0;

    /// Movimento continuo da `from` a `to` in `secs` secondi a partire da `t0`, a 60 campioni al
    /// secondo; restituisce il tempo dell'ultimo campione.
    fn sweep(g: &mut Gesture, from: f32, to: f32, t0: f64, secs: f64) -> f64 {
        let n = (secs * 60.0).round().max(1.0) as usize;
        for i in 0..=n {
            let k = i as f32 / n as f32;
            g.track(from + (to - from) * k, t0 + secs * i as f64 / n as f64);
        }
        t0 + secs
    }

    #[test]
    fn keys_down_up_dash_is_a_straight_shot_and_up_down_a_rising_strike() {
        let mut g = Gesture::new(H);
        g.press(Dir::Down, 1.0);
        g.press(Dir::Up, 1.2);
        assert_eq!(g.dash(1.4), Some(Special::Straight));
        // il gesto si consuma: lo scatto dopo è normale
        assert_eq!(g.dash(1.42), None);
        g.press(Dir::Up, 5.0);
        g.press(Dir::Down, 5.1);
        assert_eq!(g.dash(5.1), Some(Special::Rise));
    }

    #[test]
    fn keys_too_slow_or_in_the_wrong_order_are_a_normal_dash() {
        let mut g = Gesture::new(H);
        // direzioni troppo distanti
        g.press(Dir::Down, 1.0);
        g.press(Dir::Up, 1.35);
        assert_eq!(g.dash(1.4), None);
        // scatto troppo tardi
        g.press(Dir::Down, 2.0);
        g.press(Dir::Up, 2.1);
        assert_eq!(g.dash(2.4), None);
        // due volte la stessa direzione (il doppio tocco dell'accelerazione)
        g.press(Dir::Up, 3.0);
        g.press(Dir::Up, 3.1);
        assert_eq!(g.dash(3.2), None);
        // scatto prima della seconda direzione
        g.press(Dir::Down, 4.0);
        assert_eq!(g.dash(4.05), None);
        g.press(Dir::Up, 4.1);
        // solo una direzione dopo il gesto precedente: vale l'ultima coppia
        g.press(Dir::Down, 6.0);
        assert_eq!(g.dash(6.1), None);
    }

    #[test]
    fn a_quick_turn_and_back_then_a_click_is_a_move() {
        let mut g = Gesture::new(H);
        g.track(200.0, 0.0);
        g.track(200.0, 0.5); // fermo
        // giù di 100 pixel in 0,15 s e su di nuovo: STRAIGHT SHOT
        let t = sweep(&mut g, 200.0, 300.0, 0.5, 0.15);
        let t = sweep(&mut g, 300.0, 200.0, t, 0.15);
        assert_eq!(g.dash(t + 0.1), Some(Special::Straight));
        // su e giù, con il click mentre si torna ancora indietro: RISING STRIKE
        g.track(200.0, 3.0);
        let t = sweep(&mut g, 200.0, 120.0, 3.0, 0.12);
        let t = sweep(&mut g, 120.0, 190.0, t, 0.12);
        assert_eq!(g.dash(t), Some(Special::Rise));
    }

    #[test]
    fn slow_or_short_movements_are_not_a_move() {
        let mut g = Gesture::new(H);
        g.track(200.0, 0.0);
        // troppo lento: 100 pixel in mezzo secondo
        let t = sweep(&mut g, 200.0, 300.0, 0.0, 0.5);
        let t = sweep(&mut g, 300.0, 200.0, t, 0.5);
        assert_eq!(g.dash(t), None);
        // troppo corto: 30 pixel
        let t = sweep(&mut g, 200.0, 230.0, t + 1.0, 0.1);
        let t = sweep(&mut g, 230.0, 200.0, t, 0.1);
        assert_eq!(g.dash(t), None);
        // click troppo tardi dopo un gesto valido
        let t = sweep(&mut g, 200.0, 300.0, t + 1.0, 0.1);
        let t = sweep(&mut g, 300.0, 200.0, t, 0.1);
        g.track(200.0, t + 0.4);
        assert_eq!(g.dash(t + 0.4), None);
    }

    #[test]
    fn small_jitter_does_not_break_a_stroke() {
        let mut g = Gesture::new(H);
        g.track(200.0, 0.0);
        // giù con un ritorno di 5 pixel a metà (sotto la soglia), poi su
        g.track(240.0, 0.05);
        g.track(235.0, 0.07);
        g.track(300.0, 0.12);
        let t = sweep(&mut g, 300.0, 210.0, 0.12, 0.15);
        assert_eq!(g.dash(t + 0.05), Some(Special::Straight));
    }

    /// Joystick tenuto in (giù, su, avanti) dal tempo `from` a `to`, a 60 campioni al secondo.
    fn hold(s: &mut Stick, (down, up, fwd): (bool, bool, bool), from: f64, to: f64) -> f64 {
        let mut t = from;
        while t <= to {
            s.track(down, up, fwd, t);
            t += 1.0 / 60.0;
        }
        to
    }

    const D: (bool, bool, bool) = (true, false, false);
    const DF: (bool, bool, bool) = (true, false, true);
    const F: (bool, bool, bool) = (false, false, true);
    const UF: (bool, bool, bool) = (false, true, true);

    #[test]
    fn stick_quarter_circle_forward_is_a_straight_shot_and_forward_down_a_rising_strike() {
        let mut s = Stick::default();
        let t = hold(&mut s, D, 0.0, 0.05);
        let t = hold(&mut s, DF, t + 0.02, t + 0.06);
        let t = hold(&mut s, F, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t + 0.1), Some(Special::Straight));
        // si consuma
        assert_eq!(s.dash(t + 0.12), None);
        let t = hold(&mut s, F, 5.0, 5.05);
        let t = hold(&mut s, D, t + 0.02, t + 0.05);
        let t = hold(&mut s, DF, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t + 0.05), Some(Special::Rise));
        // avanti, poi la mezzaluna intera: finita in avanti vale STRAIGHT SHOT
        let t = hold(&mut s, F, 9.0, 9.05);
        let t = hold(&mut s, D, t + 0.02, t + 0.05);
        let t = hold(&mut s, DF, t + 0.02, t + 0.05);
        let t = hold(&mut s, F, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t), Some(Special::Straight));
    }

    #[test]
    fn stick_out_of_order_or_too_slow_or_upward_is_a_normal_dash() {
        let mut s = Stick::default();
        // all'indietro: avanti, giù-avanti, giù
        let t = hold(&mut s, F, 0.0, 0.05);
        let t = hold(&mut s, DF, t + 0.02, t + 0.05);
        let t = hold(&mut s, D, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t), None);
        // troppo lento tra giù e giù-avanti
        let mut s = Stick::default();
        let t = hold(&mut s, D, 2.0, 2.05);
        let t = hold(&mut s, DF, t + 0.4, t + 0.45);
        let t = hold(&mut s, F, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t), None);
        // scatto troppo tardi
        let mut s = Stick::default();
        let t = hold(&mut s, D, 4.0, 4.05);
        let t = hold(&mut s, DF, t + 0.02, t + 0.05);
        let t = hold(&mut s, F, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t + 0.3), None);
        // su-avanti non è avanti
        let mut s = Stick::default();
        let t = hold(&mut s, D, 6.0, 6.05);
        let t = hold(&mut s, DF, t + 0.02, t + 0.05);
        let t = hold(&mut s, UF, t + 0.02, t + 0.05);
        assert_eq!(s.dash(t), None);
    }

    #[test]
    fn lifting_the_finger_keeps_the_last_stroke() {
        let mut g = Gesture::new(H);
        g.track(100.0, 0.0);
        let t = sweep(&mut g, 100.0, 30.0, 0.0, 0.1);
        let t = sweep(&mut g, 30.0, 110.0, t, 0.1);
        g.lift();
        assert_eq!(g.dash(t + 0.1), Some(Special::Rise));
    }
}
