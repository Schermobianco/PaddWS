//! Ritratti dei personaggi della scelta della racchetta di NEXT (`assets/characters/portraits`,
//! tools/gen_portraits.py): il ritratto grande di ogni tipo, la sua casella della griglia e la
//! casella di OMEGA in sagoma; OMEGA svelato per lo schermo VS della sua presentazione; i ritratti
//! medi della sfilata del finale, normali e sconfitti, e OMEGA in sagoma. Sono PNG a palette in cui l'indice è il ruolo del colore
//! (`portraits.json`: nero, bianco, tre grigi, il colore del personaggio e lo stesso scurito),
//! tradotti qui una volta in texture RGBA con i colori dei PC.

use macroquad::prelude::*;
use paddws_core::PaddleKind;
use serde_json::Value;

use crate::render::decode_indexed;

macro_rules! portrait_png {
    ($name:literal) => {
        include_bytes!(concat!("../../../assets/characters/portraits/", $name, ".png"))
    };
}

/// PNG dei ritratti grandi e delle caselle, nell'ordine di `PaddleKind::ALL`.
const BIG: [&[u8]; PaddleKind::COUNT] = [
    portrait_png!("arcade"),
    portrait_png!("titan"),
    portrait_png!("hammer"),
    portrait_png!("twist"),
    portrait_png!("blaster"),
    portrait_png!("rush"),
    portrait_png!("guardian"),
];
const SMALL: [&[u8]; PaddleKind::COUNT] = [
    portrait_png!("arcade_small"),
    portrait_png!("titan_small"),
    portrait_png!("hammer_small"),
    portrait_png!("twist_small"),
    portrait_png!("blaster_small"),
    portrait_png!("rush_small"),
    portrait_png!("guardian_small"),
];

/// Ritratti medi della sfilata: normale e sconfitto, nell'ordine di `PaddleKind::ALL`, poi OMEGA.
const MID: [(&[u8], &[u8]); PaddleKind::COUNT + 1] = [
    (portrait_png!("arcade_mid"), portrait_png!("arcade_mid_defeated")),
    (portrait_png!("titan_mid"), portrait_png!("titan_mid_defeated")),
    (portrait_png!("hammer_mid"), portrait_png!("hammer_mid_defeated")),
    (portrait_png!("twist_mid"), portrait_png!("twist_mid_defeated")),
    (portrait_png!("blaster_mid"), portrait_png!("blaster_mid_defeated")),
    (portrait_png!("rush_mid"), portrait_png!("rush_mid_defeated")),
    (portrait_png!("guardian_mid"), portrait_png!("guardian_mid_defeated")),
    (portrait_png!("omega_mid"), portrait_png!("omega_mid_defeated")),
];

pub struct Portraits {
    big: [Texture2D; PaddleKind::COUNT],
    small: [Texture2D; PaddleKind::COUNT],
    /// la casella di OMEGA, il boss segreto, in sagoma: non si sceglie
    pub omega_small: Texture2D,
    /// OMEGA svelato, nello schermo VS della sua presentazione
    pub omega_big: Texture2D,
    /// sfilata del finale: (normale, sconfitto) per tipo e poi OMEGA; OMEGA in sagoma
    mid: [(Texture2D, Texture2D); PaddleKind::COUNT + 1],
    pub omega_mid_locked: Texture2D,
    /// colore di ogni personaggio (`accent` di `portraits.json`): anche quello dei segni della
    /// sua racchetta
    accent: [Color; PaddleKind::COUNT],
}

impl Portraits {
    pub fn load() -> Self {
        let spec: Value = serde_json::from_str(include_str!("../../../assets/characters/portraits/portraits.json"))
            .expect("portraits.json incluso nell'eseguibile");
        let names = PaddleKind::ALL.map(|k| k.name().to_lowercase());
        Self {
            big: std::array::from_fn(|i| texture(&spec, &names[i], BIG[i])),
            small: std::array::from_fn(|i| texture(&spec, &names[i], SMALL[i])),
            omega_small: texture(&spec, "omega", portrait_png!("omega_small")),
            omega_big: texture(&spec, "omega", portrait_png!("omega")),
            mid: std::array::from_fn(|i| {
                let name = names.get(i).map_or("omega", |n| n.as_str());
                (texture(&spec, name, MID[i].0), texture(&spec, name, MID[i].1))
            }),
            omega_mid_locked: texture(&spec, "omega", portrait_png!("omega_mid_locked")),
            accent: std::array::from_fn(|i| {
                let [r, g, b] = rgb(&spec["accent"][&names[i]]);
                Color::from_rgba(r, g, b, 255)
            }),
        }
    }

    /// Colore del personaggio `kind`.
    pub fn accent(&self, kind: PaddleKind) -> Color {
        self.accent[kind as usize]
    }

    pub fn big(&self, kind: PaddleKind) -> &Texture2D {
        &self.big[kind as usize]
    }

    pub fn small(&self, kind: PaddleKind) -> &Texture2D {
        &self.small[kind as usize]
    }

    /// Ritratto medio della sfilata: del tipo `kind` (None: OMEGA), sconfitto o no.
    pub fn mid(&self, kind: Option<PaddleKind>, defeated: bool) -> &Texture2D {
        let (normal, beaten) = &self.mid[kind.map_or(PaddleKind::COUNT, |k| k as usize)];
        if defeated { beaten } else { normal }
    }
}

/// Colore RGB di `portraits.json`.
fn rgb(v: &Value) -> [u8; 3] {
    let a = v.as_array().expect("colore RGB");
    std::array::from_fn(|i| a[i].as_u64().expect("componente del colore") as u8)
}

/// Colori dei ruoli per il personaggio `name`, nell'ordine di `roles` di `portraits.json`.
fn role_colors(spec: &Value, name: &str) -> Vec<[u8; 3]> {
    let accent = rgb(&spec["accent"][name]);
    let dark = spec["dark"].as_f64().expect("fattore del colore scuro");
    spec["roles"]
        .as_array()
        .expect("ruoli")
        .iter()
        .map(|role| match role.as_str().expect("nome del ruolo") {
            "accent" => accent,
            "accent_dark" => accent.map(|c| (c as f64 * dark).round() as u8),
            gray => rgb(&spec["grays"][gray]),
        })
        .collect()
}

fn texture(spec: &Value, name: &str, png: &[u8]) -> Texture2D {
    let colors = role_colors(spec, name);
    let (w, h, index) = decode_indexed(png);
    let rgba: Vec<u8> = index
        .iter()
        .flat_map(|&i| {
            let [r, g, b] = colors[i as usize];
            [r, g, b, 255]
        })
        .collect();
    let texture = Texture2D::from_rgba8(w as u16, h as u16, &rgba);
    texture.set_filter(FilterMode::Nearest);
    texture
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_portrait_uses_known_roles_and_sizes() {
        let spec: Value = serde_json::from_str(include_str!("../../../assets/characters/portraits/portraits.json")).unwrap();
        let roles = spec["roles"].as_array().unwrap().len();
        let big = (spec["big"][0].as_u64().unwrap() as usize, spec["big"][1].as_u64().unwrap() as usize);
        let small = spec["small"].as_u64().unwrap() as usize;
        for png in BIG.iter().chain([&portrait_png!("omega")[..]].iter()) {
            let (w, h, index) = decode_indexed(png);
            assert_eq!((w, h), big);
            assert!(index.iter().all(|&i| (i as usize) < roles));
        }
        let mid = (spec["mid"][0].as_u64().unwrap() as usize, spec["mid"][1].as_u64().unwrap() as usize);
        for png in MID.iter().flat_map(|&(a, b)| [a, b]).chain([&portrait_png!("omega_mid_locked")[..]]) {
            let (w, h, index) = decode_indexed(png);
            assert_eq!((w, h), mid);
            assert!(index.iter().all(|&i| (i as usize) < roles));
        }
        for png in SMALL.iter().chain([&portrait_png!("omega_small")[..]].iter()) {
            let (w, h, index) = decode_indexed(png);
            assert_eq!((w, h), (small, small));
            assert!(index.iter().all(|&i| (i as usize) < roles));
        }
    }
}
