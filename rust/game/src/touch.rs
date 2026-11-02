//! Comandi touch per telefoni e tablet (versione web).
//!
//! Le dita arrivano in coordinate di disegno del campo (y dall'alto). In partita la racchetta
//! segue il dito nella propria metà dello schermo (posizione assoluta, come l'encoder), un
//! secondo dito fa lo scatto in avanti e un tocco su una capsula della riserva usa quel bonus;
//! nelle altre schermate un tocco vale come Invio sulla voce toccata. Nel browser, e su PC con
//! `PADDWS_MOUSE_TOUCH`, il tasto sinistro del mouse fa da dito, tranne quando il mouse fa da
//! spinner (`mouse.rs`).

use std::sync::atomic::{AtomicBool, Ordering};

use macroquad::prelude::*;

use crate::platform;
use crate::render::Renderer;

/// Identificatore del "dito" del mouse (quelli del touch sono piccoli interi).
const MOUSE_ID: u64 = u64::MAX;

/// Il mouse fa da spinner del giocatore 1: allora non è un dito.
static MOUSE_SPINNER: AtomicBool = AtomicBool::new(false);

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

/// Le dita di questo frame, compreso il mouse se vale come dito.
pub fn fingers(r: &Renderer) -> Vec<Finger> {
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
        let phase = if is_mouse_button_pressed(MouseButton::Left) {
            Some(TouchPhase::Started)
        } else if is_mouse_button_released(MouseButton::Left) {
            Some(TouchPhase::Ended)
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

/// Punti toccati in questo frame (dita appena appoggiate).
pub fn taps(r: &Renderer) -> Vec<Vec2> {
    fingers(r)
        .into_iter()
        .filter(|f| f.phase == TouchPhase::Started)
        .map(|f| f.pos)
        .collect()
}

/// Schermo in verticale nel browser: si chiede di ruotare il dispositivo.
pub fn portrait() -> bool {
    platform::WEB && screen_height() > screen_width()
}
