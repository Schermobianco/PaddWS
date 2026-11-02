//! Il mouse come spinner del giocatore 1 (opzione `mouse.spinner`, voce MOUSE SPINNER del menu),
//! su PC e nel browser.
//!
//! Finché l'opzione è accesa il cursore resta catturato: su PC bloccato nella finestra (su Windows
//! liberato quando la finestra perde il fuoco, altrimenti resterebbe chiuso lì anche nelle altre
//! applicazioni), nel browser con il Pointer Lock, che macroquad richiede a ogni frame
//! e che il browser concede solo dopo un clic sulla pagina (Esc lo rilascia, un altro clic lo
//! riprende). Con il cursore catturato macroquad somma i movimenti grezzi del mouse, senza i bordi
//! dello schermo: la differenza tra due frame è il giro della manopola (`encoder::MouseFrame`).

use macroquad::prelude::*;

use crate::encoder::MouseFrame;
use crate::platform;

/// Stato del mouse tra un frame e l'altro.
#[derive(Default)]
pub struct Spinner {
    /// cursore catturato e posizione del frame precedente (pixel logici)
    grabbed: bool,
    last: Option<f32>,
}

impl Spinner {
    /// Il mouse di questo frame; `active` se fa da spinner. Spento (o con la finestra in secondo
    /// piano) il cursore torna libero e non arriva niente.
    pub fn frame(&mut self, active: bool) -> MouseFrame {
        let grab = active && platform::window_focused();
        if grab != self.grabbed {
            set_cursor_grab(grab);
            self.grabbed = grab;
            self.last = None; // la posizione salta tra quella vera e quella dei movimenti grezzi
        }
        if !grab {
            return MouseFrame::default();
        }
        let y = mouse_position().1;
        let dy = self.last.map_or(0.0, |last| y - last);
        self.last = Some(y);
        MouseFrame {
            dy,
            click: is_mouse_button_pressed(MouseButton::Left),
            select: is_mouse_button_pressed(MouseButton::Right),
            activate: is_mouse_button_pressed(MouseButton::Middle),
        }
    }
}

impl Drop for Spinner {
    /// All'uscita dal gioco il cursore torna libero.
    fn drop(&mut self) {
        if self.grabbed {
            platform::release_cursor();
        }
    }
}
