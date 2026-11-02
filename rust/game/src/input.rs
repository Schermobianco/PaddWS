//! Tasti della tastiera più i gamepad visti come tasti. Ogni schermata dice quale tasto vale
//! ciascun comando del gamepad di ogni giocatore (`Scene::pad_keys`): così menu, scelte dei bonus e
//! della racchetta, presentazioni e schermate della CHALLENGE leggono i gamepad con lo stesso
//! codice dei tasti, anche quando i due giocatori scelgono insieme con i loro tasti. In partita la
//! racchetta legge invece il gamepad direttamente (`Play::read_pads`: levetta analogica e
//! diagonali dei gesti); qui restano solo pausa, gettone e Start dello sfidante.
//!
//! Le scene usano `pressed`, `down` e `released` al posto delle funzioni di macroquad; i tasti
//! globali (F11, il C del filtro CRT) restano solo sulla tastiera.

use std::cell::RefCell;

use macroquad::prelude::*;

use crate::gamepad::{Control, Pads};

/// Per ciascun gamepad (0 il primo, 1 il secondo) il tasto che vale ogni comando, nell'ordine di
/// `Control::ALL`; None = il comando non fa niente in questa schermata.
pub type PadKeys = [[Option<KeyCode>; Control::COUNT]; 2];

/// Mappa dei gamepad data dal tasto per (gamepad, comando).
pub fn pad_keys(f: impl Fn(usize, Control) -> Option<KeyCode>) -> PadKeys {
    std::array::from_fn(|slot| Control::ALL.map(|c| f(slot, c)))
}

/// Nessun comando dei gamepad vale come tasto.
pub const NO_KEYS: PadKeys = [[None; Control::COUNT]; 2];

/// Tasti "premuti" dai gamepad in questo frame.
#[derive(Default)]
struct Virtual {
    down: Vec<KeyCode>,
    pressed: Vec<KeyCode>,
    released: Vec<KeyCode>,
}

thread_local! {
    static VIRTUAL: RefCell<Virtual> = RefCell::new(Virtual::default());
}

/// Tasti dei gamepad di questo frame secondo la mappa della schermata; le direzioni tenute si
/// ripetono, come serve nei menu.
pub fn set_pads(pads: &Pads, keys: &PadKeys) {
    let mut v = Virtual::default();
    for (slot, keys) in keys.iter().enumerate() {
        for (c, key) in Control::ALL.into_iter().zip(keys) {
            let Some(key) = *key else { continue };
            if pads.held(slot, c) {
                v.down.push(key);
            }
            if pads.nav_pressed(slot, c) {
                v.pressed.push(key);
            }
            if pads.released(slot, c) {
                v.released.push(key);
            }
        }
    }
    VIRTUAL.with(|x| *x.borrow_mut() = v);
}

/// Il tasto è appena premuto (sulla tastiera o da un gamepad).
pub fn pressed(key: KeyCode) -> bool {
    is_key_pressed(key) || VIRTUAL.with(|v| v.borrow().pressed.contains(&key))
}

/// Il tasto è tenuto.
pub fn down(key: KeyCode) -> bool {
    is_key_down(key) || VIRTUAL.with(|v| v.borrow().down.contains(&key))
}

/// Il tasto è appena rilasciato.
pub fn released(key: KeyCode) -> bool {
    is_key_released(key) || VIRTUAL.with(|v| v.borrow().released.contains(&key))
}

/// Uno dei tasti è appena premuto.
pub fn any_pressed(keys: &[KeyCode]) -> bool {
    keys.iter().any(|k| pressed(*k))
}
