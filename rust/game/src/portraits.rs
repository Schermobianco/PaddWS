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

macro_rules! ship_png {
    ($name:literal) => {
        include_bytes!(concat!("../../../assets/ships/", $name, ".png"))
    };
}

/// Illustrazioni isometriche delle astronavi (`assets/ships/*.png`, 1120x630 = 224x126 a scala 5),
/// mostrate nella schermata finale `THE END` per la nave del vincitore.
const SHIPS: [&[u8]; PaddleKind::COUNT] = [
    ship_png!("arcade"),
    ship_png!("titan"),
    ship_png!("hammer"),
    ship_png!("twist"),
    ship_png!("blaster"),
    ship_png!("rush"),
    ship_png!("guardian"),
];
/// Scala nativa dei PNG di `assets/ships/` (1120x630 -> 224x126 pixel nativi).
const SHIP_SCALE: usize = 5;

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
    /// riga dopo l'ultima con il disegno in ogni ritratto grande, poi in quello di OMEGA
    /// (`art_bottom` di `portraits.json`): sotto ci va il nome nello schermo VS
    art_bottom: [f32; PaddleKind::COUNT + 1],
    /// la più bassa di quelle (`art_base`): i ritratti si abbassano fino a lì
    art_base: f32,
    /// illustrazione isometrica dell'astronave di ciascun tipo (224x126, sfondo trasparente)
    ships: [Texture2D; PaddleKind::COUNT],
}

impl Portraits {
    pub fn load() -> Self {
        let spec: Value = serde_json::from_str(include_str!("../../../assets/characters/portraits/portraits.json"))
            .expect("portraits.json incluso nell'eseguibile");
        let names = PaddleKind::ALL.map(|k| k.name().to_lowercase());
        Self {
            big: std::array::from_fn(|i| texture_cut(&spec, &names[i], BIG[i])),
            small: std::array::from_fn(|i| texture(&spec, &names[i], SMALL[i])),
            omega_small: texture(&spec, "omega", portrait_png!("omega_small")),
            omega_big: texture_cut(&spec, "omega", portrait_png!("omega")),
            mid: std::array::from_fn(|i| {
                let name = names.get(i).map_or("omega", |n| n.as_str());
                (texture(&spec, name, MID[i].0), texture(&spec, name, MID[i].1))
            }),
            omega_mid_locked: texture(&spec, "omega", portrait_png!("omega_mid_locked")),
            accent: std::array::from_fn(|i| {
                let [r, g, b] = rgb(&spec["accent"][&names[i]]);
                Color::from_rgba(r, g, b, 255)
            }),
            art_bottom: std::array::from_fn(|i| {
                let name = names.get(i).map_or("omega", |n| n.as_str());
                spec["art_bottom"][name].as_f64().expect("art_bottom del ritratto") as f32
            }),
            art_base: spec["art_base"].as_f64().expect("art_base dei ritratti") as f32,
            ships: std::array::from_fn(|i| ship_texture(SHIPS[i])),
        }
    }

    /// Riga del fondo comune dei ritratti grandi, dove finiscono tutti i personaggi (`art_base`).
    pub fn art_base(&self) -> f32 {
        self.art_base
    }

    /// Quanto scende il ritratto grande di `kind` (None: OMEGA) per finire sulla riga comune.
    pub fn art_drop(&self, kind: Option<PaddleKind>) -> f32 {
        self.art_base - self.art_bottom(kind)
    }

    /// Riga dopo l'ultima con il disegno nel ritratto grande di `kind` (None: OMEGA).
    pub fn art_bottom(&self, kind: Option<PaddleKind>) -> f32 {
        self.art_bottom[kind.map_or(PaddleKind::COUNT, |k| k as usize)]
    }

    /// Illustrazione isometrica dell'astronave `kind` (224x126 pixel nativi, sfondo trasparente).
    pub fn ship(&self, kind: PaddleKind) -> &Texture2D {
        &self.ships[kind as usize]
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

/// Pixel dello sfondo: quelli di ruolo 0 (nero) collegati a un bordo dell'immagine.
fn background(index: &[u8], w: usize, h: usize) -> Vec<bool> {
    let mut outside = vec![false; w * h];
    let mut todo: Vec<usize> = (0..w * h).filter(|&i| i % w == 0 || i % w == w - 1 || i < w || i >= w * (h - 1)).collect();
    while let Some(i) = todo.pop() {
        if outside[i] || index[i] != 0 {
            continue;
        }
        outside[i] = true;
        let (x, y) = (i % w, i / w);
        if x > 0 {
            todo.push(i - 1);
        }
        if x + 1 < w {
            todo.push(i + 1);
        }
        if y > 0 {
            todo.push(i - w);
        }
        if y + 1 < h {
            todo.push(i + w);
        }
    }
    outside
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
    texture_masked(spec, name, png, false)
}

/// Come [`texture`], ma il nero collegato ai bordi (lo sfondo) è trasparente: i ritratti grandi
/// stanno sulla griglia delle schermate prima della partita (`grid.rs`). Il nero dentro il disegno
/// resta.
fn texture_cut(spec: &Value, name: &str, png: &[u8]) -> Texture2D {
    texture_masked(spec, name, png, true)
}

fn texture_masked(spec: &Value, name: &str, png: &[u8], cut: bool) -> Texture2D {
    let colors = role_colors(spec, name);
    let (w, h, index) = decode_indexed(png);
    let outside = if cut { background(&index, w, h) } else { vec![false; w * h] };
    let rgba: Vec<u8> = index
        .iter()
        .enumerate()
        .flat_map(|(n, &i)| {
            let [r, g, b] = colors[i as usize];
            [r, g, b, if outside[n] { 0 } else { 255 }]
        })
        .collect();
    let texture = Texture2D::from_rgba8(w as u16, h as u16, &rgba);
    texture.set_filter(FilterMode::Nearest);
    texture
}

/// Decodifica un'illustrazione di `assets/ships/*.png` (RGB/RGBA a scala `SHIP_SCALE`), campionata
/// alla risoluzione nativa (`224x126`) con il nero puro reso trasparente.
fn decode_ship_rgba(bytes: &[u8]) -> (usize, usize, Vec<u8>) {
    let mut decoder = png::Decoder::new(bytes);
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().expect("PNG astronave incluso nell'eseguibile");
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).expect("frame PNG astronave");
    let (src_w, src_h) = (info.width as usize, info.height as usize);
    let bpp = match info.color_type {
        png::ColorType::Rgb => 3,
        png::ColorType::Rgba => 4,
        other => panic!("formato PNG astronave non atteso: {other:?}"),
    };
    let (w, h) = (src_w / SHIP_SCALE, src_h / SHIP_SCALE);
    let mut rgba = Vec::with_capacity(w * h * 4);
    for y in 0..h {
        let sy = y * SHIP_SCALE + SHIP_SCALE / 2;
        let row = &buf[sy * info.line_size..(sy + 1) * info.line_size];
        for x in 0..w {
            let sx = x * SHIP_SCALE + SHIP_SCALE / 2;
            let (r, g, b) = (row[sx * bpp], row[sx * bpp + 1], row[sx * bpp + 2]);
            let a = if r == 0 && g == 0 && b == 0 {
                0
            } else if bpp == 4 {
                row[sx * bpp + 3]
            } else {
                255
            };
            rgba.extend_from_slice(&[r, g, b, a]);
        }
    }
    (w, h, rgba)
}

fn ship_texture(bytes: &[u8]) -> Texture2D {
    let (w, h, rgba) = decode_ship_rgba(bytes);
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

    #[test]
    fn every_ship_artwork_decodes_to_native_pixel_size() {
        for png in SHIPS {
            let (w, h, rgba) = decode_ship_rgba(png);
            assert_eq!((w, h), (224, 126));
            assert_eq!(rgba.len(), w * h * 4);
            // sfondo nero trasparente negli angoli
            assert_eq!(rgba[3], 0);
        }
    }
}
