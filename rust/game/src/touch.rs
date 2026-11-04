//! Comandi touch per telefoni e tablet (versione web).
//!
//! Le dita arrivano in coordinate di disegno del campo (y dall'alto). In partita la racchetta
//! segue il dito nella propria metà dello schermo (posizione assoluta, come l'encoder), un
//! secondo dito fa lo scatto in avanti e un tocco su una capsula della riserva usa quel bonus;
//! nelle altre schermate un tocco vale come Invio sulla voce toccata. Nel browser, e su PC con
//! `PADDWS_MOUSE_TOUCH`, il tasto sinistro del mouse fa da dito, tranne quando il mouse fa da
//! spinner (`mouse.rs`).
//!
//! macroquad tiene una sola fase per dito e per frame: se l'appoggio e il primo movimento (o
//! l'appoggio e il distacco) cadono nello stesso frame, l'appoggio si perde. Per questo le dita
//! si leggono una volta per frame (`poll`) e ogni dito arriva alle scene sempre come Started,
//! poi Moved/Stationary, poi Ended o Cancelled.

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};

use macroquad::prelude::*;

use crate::platform;
use crate::render::Renderer;

/// Identificatore del "dito" del mouse (quelli del touch sono piccoli interi).
const MOUSE_ID: u64 = u64::MAX;

/// Il mouse fa da spinner del giocatore 1: allora non è un dito.
static MOUSE_SPINNER: AtomicBool = AtomicBool::new(false);

thread_local! {
    static TRACKER: RefCell<Tracker> = RefCell::new(Tracker::default());
}

/// Da chiamare quando si accende o si spegne il mouse come spinner.
pub fn set_mouse_spinner(on: bool) {
    MOUSE_SPINNER.store(on, Ordering::Relaxed);
}

/// Un dito sullo schermo.
#[derive(Clone, Copy, Debug)]
pub struct Finger {
    pub id: u64,
    /// coordinate di disegno del campo, y dall'alto
    pub pos: Vec2,
    pub phase: TouchPhase,
}

fn ended(phase: TouchPhase) -> bool {
    matches!(phase, TouchPhase::Ended | TouchPhase::Cancelled)
}

/// Rimette in ordine le fasi delle dita da un frame all'altro.
#[derive(Default)]
struct Tracker {
    /// dita già annunciate come Started e non ancora finite, con l'ultima posizione
    down: Vec<(u64, Vec2)>,
    /// fasi rimandate al frame dopo (il distacco di un tocco appoggiato e staccato nello stesso
    /// frame, o l'appoggio di un dito che riusa l'identificatore di uno appena staccato)
    later: Vec<Finger>,
    /// dita di questo frame per le scene
    frame: Vec<Finger>,
}

impl Tracker {
    /// Le dita del frame per le scene, dalle dita grezze di macroquad.
    fn track(&mut self, raw: &[Finger]) {
        let mut out = Vec::new();
        for f in std::mem::take(&mut self.later) {
            self.note(f);
            out.push(f);
        }
        for &f in raw {
            if out.iter().any(|o| o.id == f.id) {
                // il dito ha già una fase rimandata in questo frame: la sua fine aspetta ancora
                if ended(f.phase) {
                    self.later.push(f);
                }
                continue;
            }
            let known = self.down.iter().any(|d| d.0 == f.id);
            match (known, f.phase) {
                (false, TouchPhase::Started | TouchPhase::Moved | TouchPhase::Stationary) => {
                    // appoggio perso sotto il primo movimento: lo si annuncia ora
                    out.push(Finger { phase: TouchPhase::Started, ..f });
                }
                (false, _) => {
                    // appoggiato e staccato nello stesso frame: ora l'appoggio, poi il distacco
                    out.push(Finger { phase: TouchPhase::Started, ..f });
                    self.later.push(f);
                }
                (true, TouchPhase::Started) => {
                    // un dito nuovo con l'identificatore di uno staccato nello stesso frame
                    out.push(Finger { phase: TouchPhase::Ended, ..f });
                    self.later.push(f);
                }
                _ => out.push(f),
            }
            self.note(*out.last().expect("appena aggiunto"));
        }
        // dita sparite senza distacco (finestra che perde il fuoco): finiscono annullate
        for (id, pos) in std::mem::take(&mut self.down) {
            if out.iter().any(|o| o.id == id) || self.later.iter().any(|l| l.id == id) {
                self.down.push((id, pos));
            } else {
                out.push(Finger {
                    id,
                    pos,
                    phase: TouchPhase::Cancelled,
                });
            }
        }
        self.frame = out;
    }

    /// Tiene il conto delle dita appoggiate dopo una fase annunciata.
    fn note(&mut self, f: Finger) {
        self.down.retain(|d| d.0 != f.id);
        if !ended(f.phase) {
            self.down.push((f.id, f.pos));
        }
    }
}

/// Il mouse vale come un dito: nel browser sempre, su PC solo per provare il touch; mai quando fa
/// da spinner.
pub fn mouse_as_finger() -> bool {
    !MOUSE_SPINNER.load(Ordering::Relaxed) && (platform::WEB || std::env::var_os("PADDWS_MOUSE_TOUCH").is_some())
}

/// Da chiamare all'avvio: senza la simulazione di macroquad ogni tocco arriva una volta sola (e
/// un tocco non diventa il click dello spinner).
pub fn init() {
    if platform::WEB || std::env::var_os("PADDWS_MOUSE_TOUCH").is_some() {
        simulate_mouse_with_touch(false);
    }
}

/// Da chiamare una volta per frame, prima delle scene: legge le dita del frame.
pub fn poll(r: &Renderer) {
    let raw = raw_fingers(r);
    TRACKER.with_borrow_mut(|t| t.track(&raw));
}

/// Le dita come le dà macroquad, compreso il mouse se vale come dito.
fn raw_fingers(r: &Renderer) -> Vec<Finger> {
    // macroquad dà i tocchi in pixel fisici e il mouse in pixel logici: si porta tutto ai logici
    let dpi = screen_dpi_scale();
    let mut out: Vec<Finger> = touches()
        .into_iter()
        .map(|t| Finger {
            id: t.id,
            pos: r.to_world(t.position / dpi),
            phase: t.phase,
        })
        .collect();
    if mouse_as_finger() {
        // un click rapido, premuto e rilasciato nello stesso frame, è un dito già staccato
        let phase = if is_mouse_button_released(MouseButton::Left) {
            Some(TouchPhase::Ended)
        } else if is_mouse_button_pressed(MouseButton::Left) {
            Some(TouchPhase::Started)
        } else if is_mouse_button_down(MouseButton::Left) {
            Some(TouchPhase::Moved)
        } else {
            None
        };
        if let Some(phase) = phase {
            out.push(Finger {
                id: MOUSE_ID,
                pos: r.to_world(mouse_position().into()),
                phase,
            });
        }
    }
    out
}

/// Le dita di questo frame (lette da `poll`).
pub fn fingers() -> Vec<Finger> {
    TRACKER.with_borrow(|t| t.frame.clone())
}

/// Punti toccati in questo frame (dita appena appoggiate).
pub fn taps() -> Vec<Vec2> {
    fingers()
        .into_iter()
        .filter(|f| f.phase == TouchPhase::Started)
        .map(|f| f.pos)
        .collect()
}

/// Schermo in verticale nel browser: si chiede di ruotare il dispositivo.
pub fn portrait() -> bool {
    platform::WEB && screen_height() > screen_width()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn f(id: u64, y: f32, phase: TouchPhase) -> Finger {
        Finger {
            id,
            pos: vec2(0.0, y),
            phase,
        }
    }

    fn phases(t: &Tracker) -> Vec<(u64, TouchPhase)> {
        t.frame.iter().map(|f| (f.id, f.phase)).collect()
    }

    #[test]
    fn a_swipe_whose_start_was_lost_still_starts() {
        let mut t = Tracker::default();
        t.track(&[f(0, 10.0, TouchPhase::Moved)]);
        assert_eq!(phases(&t), [(0, TouchPhase::Started)]);
        t.track(&[f(0, 30.0, TouchPhase::Moved)]);
        assert_eq!(phases(&t), [(0, TouchPhase::Moved)]);
        t.track(&[f(0, 30.0, TouchPhase::Ended)]);
        assert_eq!(phases(&t), [(0, TouchPhase::Ended)]);
        t.track(&[]);
        assert!(t.frame.is_empty() && t.down.is_empty());
    }

    #[test]
    fn a_tap_inside_one_frame_starts_then_ends() {
        let mut t = Tracker::default();
        t.track(&[f(3, 50.0, TouchPhase::Ended)]);
        assert_eq!(phases(&t), [(3, TouchPhase::Started)]);
        t.track(&[]);
        assert_eq!(phases(&t), [(3, TouchPhase::Ended)]);
        t.track(&[]);
        assert!(t.frame.is_empty() && t.down.is_empty());
    }

    #[test]
    fn a_reused_id_ends_the_old_finger_first() {
        let mut t = Tracker::default();
        t.track(&[f(0, 10.0, TouchPhase::Started)]);
        t.track(&[f(0, 90.0, TouchPhase::Started)]);
        assert_eq!(phases(&t), [(0, TouchPhase::Ended)]);
        t.track(&[f(0, 90.0, TouchPhase::Stationary)]);
        assert_eq!(phases(&t), [(0, TouchPhase::Started)]);
        t.track(&[f(0, 90.0, TouchPhase::Stationary)]);
        assert_eq!(phases(&t), [(0, TouchPhase::Stationary)]);
    }

    #[test]
    fn a_finger_that_vanishes_is_cancelled() {
        let mut t = Tracker::default();
        t.track(&[f(1, 10.0, TouchPhase::Started)]);
        t.track(&[]);
        assert_eq!(phases(&t), [(1, TouchPhase::Cancelled)]);
        assert!(t.down.is_empty());
    }
}
