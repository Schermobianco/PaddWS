//! Sprite delle astronavi delle racchette di NEXT (`assets/ships/sprites/*.png`): l'astronave vista
//! dall'alto, con la faccia che colpisce a destra, disegnata a mano con `tools/paddle_editor.html`.
//!
//! I PNG sono a palette e l'indice è il ruolo del colore, come in `tools/paddle_shapes.py`: 0
//! trasparente, 1 corpo, 2 corpo in ombra, 3-5 colore del personaggio (pieno, scuro, chiaro), 6-10
//! grigi e nero, 11 giallo dei segnali. Gli indici 16-18 sono agganci, mai disegnati: un pixel nel
//! vuoto dove comincia un effetto animato, in colonna per lo spessore (16 motore: fiamme, accensione
//! e scia; 17 arma: lampo dei cannoni e partenza dei colpi; 18 speciale: getti di manovra di TWIST,
//! scie alari di RUSH). Il blocco tEXt "paddedit" dice quante colonne sporgono davanti alla faccia
//! (`front`, le canne del BLASTER).
//!
//! Qui tutto è nelle coordinate di `paddle_ui.rs`: `u` la colonna, con la faccia a 1 (la hitbox va
//! da -3 a 1) e negativa verso il retro; `v` la riga dall'alto. Le stesse regole le segue
//! `tools/gen_mister_paddles.py` per il MiSTer: cambiando le une, si cambiano le altre.

use std::sync::OnceLock;

use paddws_core::PaddleKind;
use paddws_core::next::GUARDIAN_SECTORS;

use crate::render::decode_indexed;

/// Ruoli del PNG (come `paddle_shapes.py`).
pub const NONE: u8 = 0;
pub const BODY: u8 = 1;
pub const SHADE: u8 = 2;
pub const MARK: u8 = 3;
pub const MARK_DARK: u8 = 4;
pub const MARK_LIGHT: u8 = 5;
pub const GRAY: u8 = 6;
pub const GRAY_LIGHT: u8 = 7;
pub const DARK: u8 = 8;
pub const DARK_DEEP: u8 = 9;
pub const BLACK: u8 = 10;
pub const SIGNAL: u8 = 11;
const ENGINE: u8 = 16;
const WEAPON: u8 = 17;
const SPECIAL: u8 = 18;

/// Uno dei tre toni del colore del personaggio.
pub fn is_mark(r: u8) -> bool {
    matches!(r, MARK | MARK_DARK | MARK_LIGHT)
}

/// Un aggancio: colonna `u`, prima riga `v`, righe `rows`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Anchor {
    pub u: i32,
    pub v: i32,
    pub rows: i32,
}

/// Sprite di un'astronave, già letto.
pub struct Ship {
    /// colonne e righe del PNG
    pub w: usize,
    pub h: usize,
    /// colonna del PNG della faccia
    pub face: usize,
    /// ruoli riga per riga, agganci già tolti
    px: Vec<u8>,
    /// agganci, dall'alto in basso (motori, armi, speciali)
    pub engines: Vec<Anchor>,
    pub weapons: Vec<Anchor>,
    pub specials: Vec<Anchor>,
    /// GUARDIAN: righe [y0, y1) delle cinque piastre (i pezzi tra le giunture)
    pub sectors: Option<[(i32, i32); GUARDIAN_SECTORS]>,
    /// colonna più a sinistra dei pixel nel colore del personaggio (cabina di ARCADE)
    pub mark_u0: i32,
    /// righe dei pixel nel colore del personaggio fino alla faccia (indicatore dei colpi del BLASTER)
    pub mark_rows: (i32, i32),
}

/// Colonne delle piastre del GUARDIAN fino alla faccia, e il binario subito dietro.
pub const PLATE: i32 = 4;

impl Ship {
    /// Colonna `u` della colonna `x` del PNG.
    fn u_of(&self, x: usize) -> i32 {
        x as i32 - self.face as i32 + 1
    }

    /// Prima colonna (la più indietro) e ultima (davanti alla faccia), in `u`.
    pub fn u_range(&self) -> (i32, i32) {
        (self.u_of(0), self.u_of(self.w - 1))
    }

    /// Colonne davanti alla faccia (le canne del BLASTER), agganci compresi.
    pub fn front(&self) -> i32 {
        (self.w - 1 - self.face) as i32
    }

    /// Ruolo del pixel (`u`, `v`) dello sprite (`NONE` fuori).
    pub fn at(&self, u: i32, v: i32) -> u8 {
        let x = u + self.face as i32 - 1;
        if x < 0 || v < 0 || x >= self.w as i32 || v >= self.h as i32 {
            return NONE;
        }
        self.px[v as usize * self.w + x as usize]
    }

    fn decode(bytes: &[u8], kind: PaddleKind) -> Self {
        let (w, h, index) = decode_indexed(bytes);
        let front = front_of(bytes).unwrap_or_else(|| guess_front(w, h, &index));
        assert!(front < w, "sporgenza dello sprite {kind:?}");
        let face = w - 1 - front;
        let mut ship = Self {
            w,
            h,
            face,
            px: index.iter().map(|&r| if r >= ENGINE { NONE } else { r }).collect(),
            engines: Vec::new(),
            weapons: Vec::new(),
            specials: Vec::new(),
            sectors: None,
            mark_u0: -3,
            mark_rows: (0, -1),
        };
        assert!(
            ship.px.iter().all(|&r| r <= SIGNAL),
            "ruolo sconosciuto nello sprite {kind:?}"
        );
        // agganci: gruppi in colonna dello stesso indice, dall'alto in basso
        let u_of = |x: usize| x as i32 - face as i32 + 1;
        let groups = |role: u8| {
            let mut out = Vec::new();
            for x in 0..w {
                let mut y = 0;
                while y < h {
                    if index[y * w + x] == role {
                        let y0 = y;
                        while y < h && index[y * w + x] == role {
                            y += 1;
                        }
                        out.push(Anchor {
                            u: u_of(x),
                            v: y0 as i32,
                            rows: (y - y0) as i32,
                        });
                    } else {
                        y += 1;
                    }
                }
            }
            out.sort_by_key(|a| (a.v, a.u));
            out
        };
        ship.engines = groups(ENGINE);
        ship.weapons = groups(WEAPON);
        ship.specials = groups(SPECIAL);
        // pixel nel colore del personaggio: cabina di ARCADE e indicatore del BLASTER
        let marks: Vec<(i32, i32)> = (0..h)
            .flat_map(|y| (0..w).map(move |x| (x, y)))
            .filter(|&(x, y)| is_mark(ship.px[y * w + x]) && x <= face)
            .map(|(x, y)| (ship.u_of(x), y as i32))
            .collect();
        if let Some(u0) = marks.iter().map(|m| m.0).min() {
            ship.mark_u0 = u0;
            ship.mark_rows = (
                marks.iter().map(|m| m.1).min().unwrap(),
                marks.iter().map(|m| m.1).max().unwrap(),
            );
        }
        if kind == PaddleKind::Guardian {
            ship.sectors = Some(ship.find_sectors());
        }
        ship
    }

    /// GUARDIAN: le giunture sono le righe in cui le piastre sono tutte nel colore del personaggio
    /// (o nere), i settori i pezzi tra l'una e l'altra; se non sono quattro, le righe del core
    /// (`round(h * i / 5)`).
    fn find_sectors(&self) -> [(i32, i32); GUARDIAN_SECTORS] {
        let seam = |v: i32| (2 - PLATE..=1).all(|u| matches!(self.at(u, v), MARK | MARK_DARK | MARK_LIGHT | BLACK));
        let mut bands = Vec::new();
        let mut y0 = 0;
        for v in 0..=self.h as i32 {
            if v == self.h as i32 || seam(v) {
                if v > y0 {
                    bands.push((y0, v));
                }
                y0 = v + 1;
            }
        }
        if bands.len() == GUARDIAN_SECTORS {
            return std::array::from_fn(|i| bands[i]);
        }
        let h = self.h as f32;
        let row = |i: usize| (h * i as f32 / GUARDIAN_SECTORS as f32 + 0.5).floor() as i32;
        std::array::from_fn(|i| (if i > 0 { row(i) + 1 } else { 0 }, row(i + 1)))
    }
}

/// Sporgenza davanti alla faccia dal blocco tEXt "paddedit" (`"front": N`).
fn front_of(bytes: &[u8]) -> Option<usize> {
    let decoder = png::Decoder::new(bytes);
    let reader = decoder.read_info().ok()?;
    let text = reader
        .info()
        .uncompressed_latin1_text
        .iter()
        .find(|t| t.keyword == "paddedit")?;
    let at = text.text.find("\"front\"")?;
    let rest = text.text[at + 7..].trim_start_matches([' ', ':']);
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok()
}

/// Senza il blocco "paddedit": la faccia è l'ultima colonna piena per almeno metà delle righe.
fn guess_front(w: usize, h: usize, index: &[u8]) -> usize {
    (0..w)
        .rev()
        .find(|&x| (0..h).filter(|&y| matches!(index[y * w + x], 1..=SIGNAL)).count() * 2 >= h)
        .map_or(0, |x| w - 1 - x)
}

/// BLASTER: distanza verticale dei due cannoni dal centro della racchetta alta `h` (in coordinate
/// di gioco), dagli agganci delle armi.
pub fn gun_dy(h: f32) -> f32 {
    let s = ship(PaddleKind::Blaster);
    let rows = s.h as f32;
    s.weapons.first().map_or(h / 2.0 - 9.0 * h / rows, |a| {
        let c = a.v as f32 + a.rows as f32 / 2.0;
        (rows / 2.0 - c).abs() * h / rows
    })
}

/// BLASTER: colonne delle canne davanti alla faccia (la bocca dei cannoni).
pub fn barrel() -> f32 {
    let s = ship(PaddleKind::Blaster);
    (s.front() - i32::from(!s.weapons.is_empty())).max(0) as f32
}

macro_rules! sprite {
    ($name:literal) => {
        include_bytes!(concat!("../../../assets/ships/sprites/", $name, ".png"))
    };
}

const PNGS: [&[u8]; 7] = [
    sprite!("arcade"),
    sprite!("titan"),
    sprite!("hammer"),
    sprite!("twist"),
    sprite!("blaster"),
    sprite!("rush"),
    sprite!("guardian"),
];

const KINDS: [PaddleKind; 7] = [
    PaddleKind::Arcade,
    PaddleKind::Titan,
    PaddleKind::Hammer,
    PaddleKind::Twist,
    PaddleKind::Blaster,
    PaddleKind::Rush,
    PaddleKind::Guardian,
];

/// Lo sprite dell'astronave `kind`.
pub fn ship(kind: PaddleKind) -> &'static Ship {
    static SHIPS: OnceLock<Vec<Ship>> = OnceLock::new();
    &SHIPS.get_or_init(|| KINDS.iter().zip(PNGS).map(|(&k, b)| Ship::decode(b, k)).collect())[kind as usize]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Gli sprite rispettano le regole che il gioco e il MiSTer danno per scontate: altezza del
    /// tipo, faccia quasi piena (gli spigoli possono essere arrotondati), agganci attesi.
    #[test]
    fn sprites_follow_the_rules() {
        let heights = [32, 48, 40, 40, 44, 34, 32];
        // [motore, arma, speciale]
        let anchors = [
            [2, 0, 0],
            [2, 0, 0],
            [1, 0, 0],
            [1, 0, 2],
            [2, 2, 0],
            [1, 0, 2],
            [2, 0, 0],
        ];
        for (i, &kind) in KINDS.iter().enumerate() {
            let s = ship(kind);
            assert_eq!(s.h, heights[i], "altezza di {kind:?}");
            let n = [s.engines.len(), s.weapons.len(), s.specials.len()];
            assert_eq!(n, anchors[i], "agganci di {kind:?}");
            for a in s.engines.iter().chain(&s.specials) {
                assert!(a.u < -3, "aggancio dietro la hitbox in {kind:?}: {a:?}");
            }
            for a in &s.weapons {
                assert!(a.u > 1, "aggancio dell'arma davanti alla faccia in {kind:?}: {a:?}");
            }
            // la faccia può avere gli spigoli arrotondati, ma è piena per almeno i 4/5 dell'altezza
            let full = (0..s.h as i32).filter(|&v| s.at(1, v) != NONE).count();
            assert!(full * 5 >= s.h * 4, "faccia di {kind:?} con {} righe vuote", s.h - full);
        }
        let g = ship(PaddleKind::Guardian).sectors.unwrap();
        assert!(g.iter().all(|&(a, b)| b - a >= 3), "settori del GUARDIAN: {g:?}");
    }
}
